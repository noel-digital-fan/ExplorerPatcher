# Explorer Patcher Plus release synchronization, noel-digital-fan, 2026-11-19.
# Modified 2026-11-21: report source changes independently of publication.
param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$DefaultBranch
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    Write-Host "git $($Arguments -join ' ')"
    $result = & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed ($LASTEXITCODE)." }
    return $result
}

function Invoke-GitHub {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $result = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub API request failed ($LASTEXITCODE)." }
    return ($result | ConvertFrom-Json)
}

function Write-OutputValue([string]$Name, [string]$Value) {
    if ($Value -match '[\r\n]') { throw 'Workflow output must be a single line.' }
    [IO.File]::AppendAllText($env:GITHUB_OUTPUT, "$Name=$Value`n", [Text.UTF8Encoding]::new($false))
}

function Write-Summary([string]$Message) {
    Write-Host $Message
    if ($env:GITHUB_STEP_SUMMARY) {
        [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, "$Message`n", [Text.UTF8Encoding]::new($false))
    }
}

if (!$env:GITHUB_OUTPUT) { throw 'GITHUB_OUTPUT is required.' }
Write-OutputValue release_required false
Write-OutputValue source_changed false
$initialCommit = Invoke-Git rev-parse HEAD
Write-OutputValue validation_ref $initialCommit

# /latest excludes drafts and prereleases. Never merge the moving master branch.
$upstream = Invoke-GitHub api repos/valinet/ExplorerPatcher/releases/latest
if ($upstream.draft -or $upstream.prerelease -or !$upstream.tag_name) {
    throw 'Expected a published official stable release.'
}
$releaseTag = "fork-$($upstream.tag_name)"
Invoke-Git check-ref-format "refs/tags/$($upstream.tag_name)"
Invoke-Git check-ref-format "refs/tags/$releaseTag"

# A tag alone is not a success marker: failed builds and draft uploads must retry.
$pages = Invoke-GitHub api "repos/$Repository/releases?per_page=100" --paginate --slurp
$releases = @($pages | ForEach-Object { $_ })
$published = $releases | Where-Object {
    $_.tag_name -eq $releaseTag -and !$_.draft -and !$_.prerelease -and
    @($_.assets | Where-Object { $_.name -eq 'ep_setup.exe' -and $_.size -gt 0 }).Count -eq 1 -and
    @($_.assets | Where-Object { $_.name -eq 'ep_setup_arm64.exe' -and $_.size -gt 0 }).Count -eq 1 -and
    @($_.assets | Where-Object { $_.name -eq 'Explorer-Patcher-Plus-source.zip' -and $_.size -gt 0 }).Count -eq 1
}
if ($published) {
    Write-Summary "Already published $releaseTag with both fork installers and source; nothing to do."
    return
}

$branch = Invoke-Git symbolic-ref --short HEAD
if ($branch -ne $DefaultBranch) { throw "Expected branch $DefaultBranch, found $branch." }
if (Invoke-Git status --porcelain) { throw 'The checkout must be clean before syncing.' }

Invoke-Git fetch --no-tags https://github.com/valinet/ExplorerPatcher.git "+refs/tags/$($upstream.tag_name):refs/remotes/upstream/stable-release"
$upstreamCommit = Invoke-Git rev-parse 'refs/remotes/upstream/stable-release^{commit}'

# A previous upload attempt may already have created this tag. Rebuild that same
# source, rather than changing an existing release tag to a different commit.
$tagCommit = & git rev-parse --verify --quiet "refs/tags/$releaseTag^{commit}" 2>$null
if ($LASTEXITCODE -eq 0) {
    Invoke-Git merge-base --is-ancestor $upstreamCommit $tagCommit
    Invoke-Git merge-base --is-ancestor $tagCommit HEAD
    $sourceCommit = $tagCommit
    Write-Summary "Retrying $releaseTag from its existing source commit $sourceCommit."
}
else {
    Invoke-Git config user.name 'github-actions[bot]'
    Invoke-Git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
    & git merge --no-edit $upstreamCommit
    if ($LASTEXITCODE -ne 0) {
        $conflicts = & git diff --name-only --diff-filter=U
        Write-Summary "Merge failed for $($upstream.tag_name). Resolve conflicts manually: $($conflicts -join ', '). No changes were pushed."
        Invoke-Git merge --abort
        throw 'Upstream release conflicts with the fork. Your remote branch is unchanged.'
    }
    $sourceCommit = Invoke-Git rev-parse HEAD
    # No force push: concurrent user changes must cause a failure and a fresh retry.
    Invoke-Git push origin "HEAD:refs/heads/$DefaultBranch"
    Write-OutputValue validation_ref $sourceCommit
    if ($sourceCommit -ne $initialCommit) {
        Write-OutputValue source_changed true
    }
}

Write-OutputValue ref $sourceCommit
Write-OutputValue release_tag $releaseTag
Write-OutputValue upstream_release_url $upstream.html_url
Write-OutputValue release_required true
Write-Summary "Build $releaseTag from fork commit $sourceCommit, integrating official stable release $($upstream.tag_name). Existing fork commits are retained."
