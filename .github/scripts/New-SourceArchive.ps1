# Explorer Patcher Plus source packaging, noel-digital-fan, 2026-11-19.
param([Parameter(Mandatory = $true)][string]$Destination)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

$sourceRoot = & git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { throw 'A Git checkout is required.' }
$commit = & git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not identify the source commit.' }
$submodules = & git submodule status --recursive
if ($LASTEXITCODE -ne 0 -or ($submodules | Where-Object { $_ -match '^[-U]' })) {
    throw 'All submodules must be initialized and free of unresolved conflicts.'
}
$files = & git -c core.quotepath=false ls-files --recurse-submodules
if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate corresponding source files.' }
$patches = & git diff --submodule=diff
if ($LASTEXITCODE -ne 0) { throw 'Could not record build-time source patches.' }
$destinationPath = [IO.Path]::GetFullPath($Destination)
$archive = [IO.Compression.ZipFile]::Open($destinationPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $path = Join-Path $sourceRoot $file
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $path,
            $file.Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    $entry = $archive.CreateEntry('BUILD-SOURCE.txt')
    $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
    try {
        $writer.WriteLine("Explorer Patcher Plus source commit: $commit")
        $writer.WriteLine("Submodule source revisions:`n$($submodules -join "`n")")
        $writer.WriteLine("Build-time source patches (also included in the archived files):`n$($patches -join "`n")")
        $writer.WriteLine('Separate prebuilt dependencies are not relicensed by this source archive. See README.md.')
    }
    finally { $writer.Dispose() }
}
finally { $archive.Dispose() }
Write-Host "Packaged fork source and submodules from $commit into $destinationPath"
