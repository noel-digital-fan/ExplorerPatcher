# Explorer Patcher Plus release automation tests, noel-digital-fan, 2026-11-19.
# Runs real merges and pushes against disposable local Git repositories only.
$ErrorActionPreference = 'Stop'
$syncScript = Join-Path $PSScriptRoot 'Sync-UpstreamRelease.ps1'
$originalLocation = Get-Location
$originalOutput = $env:GITHUB_OUTPUT
$originalSummary = $env:GITHUB_STEP_SUMMARY
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('epp-sync-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$env:GITHUB_STEP_SUMMARY = ''
$global:EpSyncTestApiFailure = $false
$global:EpSyncTestReleases = '[[]]'

# The production script still parses real GitHub-shaped responses. No HTTP or
# credentials are used by these tests, and Git rewrites the upstream URL locally.
function gh {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    if ($global:EpSyncTestApiFailure) { $global:LASTEXITCODE = 1; return }
    $global:LASTEXITCODE = 0
    if ($Arguments[1] -eq 'repos/valinet/ExplorerPatcher/releases/latest') {
        return '{"tag_name":"v1","html_url":"https://github.com/valinet/ExplorerPatcher/releases/tag/v1","draft":false,"prerelease":false}'
    }
    if ($Arguments[1] -eq 'repos/test/ExplorerPatcher/releases?per_page=100') { return $global:EpSyncTestReleases }
    throw "Unexpected GitHub command: $($Arguments -join ' ')"
}

function Invoke-TestGit {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $result = & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Test setup failed: git $($Arguments -join ' ')" }
    return $result
}

function Assert($Condition, [string]$Message) {
    if (!$Condition) { throw "Assertion failed: $Message" }
}

function New-Fixture([string]$Name, [switch]$Conflict) {
    $directory = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    $upstream = Join-Path $directory 'upstream'
    $fork = Join-Path $directory 'fork'
    $origin = Join-Path $directory 'origin.git'
    Invoke-TestGit init -q -b master $upstream
    Set-Location $upstream
    Invoke-TestGit config user.name Test
    Invoke-TestGit config user.email test@example.invalid
    Set-Content base.txt base
    Invoke-TestGit add .
    Invoke-TestGit commit -qm base
    Invoke-TestGit clone -q $upstream $fork
    Set-Location $fork
    Invoke-TestGit config user.name Test
    Invoke-TestGit config user.email test@example.invalid
    Set-Content custom.txt 'custom search-box changes'
    if ($Conflict) { Set-Content base.txt 'fork modification' }
    Invoke-TestGit add .
    Invoke-TestGit commit -qm custom
    $customCommit = Invoke-TestGit rev-parse HEAD
    Invoke-TestGit clone -q --bare $fork $origin
    Invoke-TestGit remote set-url origin $origin
    $upstreamUri = ([uri]('file:///' + [IO.Path]::GetFullPath($upstream).Replace('\', '/').TrimStart('/'))).AbsoluteUri
    Assert ($upstreamUri.StartsWith('file:///')) 'test upstream must be an explicit local file URL'
    Invoke-TestGit config "url.$upstreamUri.insteadOf" https://github.com/valinet/ExplorerPatcher.git
    Set-Location $upstream
    if ($Conflict) { Set-Content base.txt 'upstream modification' }
    Set-Content released.txt 'official stable changes'
    Invoke-TestGit add .
    Invoke-TestGit commit -qm release
    Invoke-TestGit tag v1
    $releaseCommit = Invoke-TestGit rev-parse HEAD
    Set-Content unreleased.txt 'must not sync from upstream master'
    Invoke-TestGit add .
    Invoke-TestGit commit -qm unreleased
    Set-Location $fork
    return @{ Directory = $directory; Fork = $fork; Origin = $origin; Upstream = $upstream; Custom = $customCommit; Release = $releaseCommit }
}

function Run-Sync($Fixture) {
    Set-Location $Fixture.Fork
    $env:GITHUB_OUTPUT = Join-Path $Fixture.Directory 'outputs.txt'
    [IO.File]::WriteAllText($env:GITHUB_OUTPUT, '')
    & $syncScript -Repository test/ExplorerPatcher -DefaultBranch master | Out-Host
    $values = @{}
    foreach ($line in Get-Content $env:GITHUB_OUTPUT) {
        $parts = $line.Split('=', 2)
        $values[$parts[0]] = $parts[1]
    }
    return $values
}

try {
    $fixture = New-Fixture merge
    $values = Run-Sync $fixture
    Assert ($values.release_required -eq 'true') 'a new stable release requests a build'
    Assert ($values.release_tag -eq 'fork-v1') 'fork tags are separate from official tags'
    Invoke-TestGit merge-base --is-ancestor $fixture.Custom HEAD
    Invoke-TestGit merge-base --is-ancestor $fixture.Release HEAD
    Assert ((Get-Content custom.txt) -eq 'custom search-box changes') 'custom behavior is retained'
    Assert (Test-Path released.txt) 'stable-release changes were merged'
    Assert (!(Test-Path unreleased.txt)) 'unreleased upstream commits were not merged'
    Assert ((Invoke-TestGit --git-dir=$($fixture.Origin) rev-parse master) -eq $values.ref) 'the merged source was pushed'
    Write-Host 'PASS: stable tag merge preserves custom commits and excludes unreleased master'

    Invoke-TestGit tag fork-v1
    $values = Run-Sync $fixture
    Assert ($values.ref -eq (Invoke-TestGit rev-parse 'fork-v1^{commit}')) 'a retry uses the existing tag source'
    Write-Host 'PASS: failed publication retries the original tagged source'

    $global:EpSyncTestReleases = '[[{"tag_name":"fork-v1","draft":true,"prerelease":false,"assets":[]}]]'
    $values = Run-Sync $fixture
    Assert ($values.release_required -eq 'true') 'a draft is not treated as a successful release'
    Write-Host 'PASS: incomplete draft release is retried'

    $global:EpSyncTestReleases = '[[{"tag_name":"fork-v1","draft":false,"prerelease":false,"assets":[{"name":"ep_setup.exe","size":100}]}]]'
    $values = Run-Sync $fixture
    Assert ($values.release_required -eq 'true') 'a release missing ARM64 is retried'
    Write-Host 'PASS: a missing installer does not mark the release complete'

    # Place the matching release on the second API page to exercise pagination.
    $global:EpSyncTestReleases = '[[],[{"tag_name":"fork-v1","draft":false,"prerelease":false,"assets":[{"name":"ep_setup.exe","size":100},{"name":"ep_setup_arm64.exe","size":100},{"name":"Explorer-Patcher-Plus-source.zip","size":100}]}]]'
    $values = Run-Sync $fixture
    Assert ($values.release_required -eq 'false') 'a complete published release is idempotent'
    Write-Host 'PASS: already published release is skipped across API pages'
    $global:EpSyncTestReleases = '[[]]'

    $fixture = New-Fixture conflict -Conflict
    $before = Invoke-TestGit --git-dir=$($fixture.Origin) rev-parse master
    $failed = $false
    try { Run-Sync $fixture | Out-Null } catch { $failed = $true }
    Assert $failed 'merge conflicts fail the sync'
    Assert ((Invoke-TestGit --git-dir=$($fixture.Origin) rev-parse master) -eq $before) 'a conflict never changes the remote'
    Assert (!(Invoke-TestGit status --porcelain)) 'the failed merge is aborted cleanly'
    Write-Host 'PASS: merge conflict leaves the remote and checkout unchanged'

    $global:EpSyncTestApiFailure = $true
    $failed = $false
    try { Run-Sync $fixture | Out-Null } catch { $failed = $true }
    Assert $failed 'API failures stop processing'
    Assert ((Invoke-TestGit --git-dir=$($fixture.Origin) rev-parse master) -eq $before) 'API failure never pushes a change'
    $global:EpSyncTestApiFailure = $false
    Write-Host 'PASS: API errors fail closed'

    $fixture = New-Fixture ahead
    Invoke-TestGit fetch -q $fixture.Upstream master
    Invoke-TestGit merge -q --no-edit FETCH_HEAD
    $ahead = Invoke-TestGit rev-parse HEAD
    $values = Run-Sync $fixture
    Assert ($values.ref -eq $ahead) 'an intentionally newer fork is never reset to an older stable release'
    Assert (Test-Path unreleased.txt) 'newer commits already in the fork are retained'
    Write-Host 'PASS: bootstrap preserves a fork already ahead of stable'

    # Package the actual working source, including build-time patches, while
    # excluding arbitrary untracked files and Git's private metadata.
    Set-Content LICENSE 'test license notice'
    Invoke-TestGit add LICENSE
    Invoke-TestGit commit -qm license
    Set-Content custom.txt 'build-time source patch'
    Set-Content untracked-secret.txt 'must not enter archive'
    $archivePath = Join-Path $fixture.Directory 'source.zip'
    & (Join-Path $PSScriptRoot 'New-SourceArchive.ps1') -Destination $archivePath
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        Assert ($null -ne $archive.GetEntry('LICENSE')) 'the license is included in source'
        Assert ($null -ne $archive.GetEntry('BUILD-SOURCE.txt')) 'source provenance is included'
        Assert ($null -eq $archive.GetEntry('untracked-secret.txt')) 'untracked files are excluded'
        Assert (@($archive.Entries | Where-Object { $_.FullName -like '.git/*' }).Count -eq 0) 'Git metadata is excluded'
        $reader = [IO.StreamReader]::new($archive.GetEntry('custom.txt').Open())
        try { Assert ($reader.ReadToEnd().Trim() -eq 'build-time source patch') 'working source patches are included' }
        finally { $reader.Dispose() }
    }
    finally { $archive.Dispose() }
    Write-Host 'PASS: source packaging preserves licenses and source patches without untracked files'
}
finally {
    Set-Location $originalLocation
    $env:GITHUB_OUTPUT = $originalOutput
    $env:GITHUB_STEP_SUMMARY = $originalSummary
    Remove-Variable -Scope Global -Name EpSyncTestApiFailure,EpSyncTestReleases -ErrorAction SilentlyContinue
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (!$resolvedTestRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedTestRoot) -notlike 'epp-sync-test-*') {
        throw "Refusing to remove unexpected test path: $resolvedTestRoot"
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}
