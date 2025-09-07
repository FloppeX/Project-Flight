param(
    [string]$ArchiveDir = "_archive"
)

$ErrorActionPreference = 'Stop'

$root = Get-Location
$arch = Join-Path $root $ArchiveDir
if (-not (Test-Path -LiteralPath $arch)) {
    Write-Error "Archive not found: $arch"
    exit 1
}

$files = Get-ChildItem -LiteralPath $arch -Recurse -File
foreach ($f in $files) {
    $rel = $f.FullName.Substring($arch.Length) -replace '^[\\/]+',''
    $dest = Join-Path $root $rel
    $destDir = Split-Path -Parent $dest
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Move-Item -LiteralPath $f.FullName -Destination $dest -Force
}

Write-Host "Restored" ($files | Measure-Object).Count "files from" $ArchiveDir


