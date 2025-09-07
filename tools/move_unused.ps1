param(
    [string]$UsedList = "used_files.txt",
    [string]$ArchiveDir = "_archive"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $UsedList)) {
    Write-Error "Used list not found: $UsedList"
    exit 1
}

$projectRoot = Get-Location
$used = Get-Content -LiteralPath $UsedList | Where-Object { $_ -and ($_ -is [string]) }
$usedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$used)

function To-Rel([string]$full) {
    $rel = $full.Substring($projectRoot.Path.Length)
    # Remove any leading path separators (both Windows and POSIX)
    return ($rel -replace '^[\\/]+','')
}

$allFiles = Get-ChildItem -Recurse -File | Where-Object {
    $_.FullName -notmatch "\\\.git\\" -and $_.FullName -notmatch "\\\.godot\\" -and $_.FullName -notmatch "\\$ArchiveDir\\"
}

$unused = @()
foreach ($f in $allFiles) {
    $rel = To-Rel $f.FullName
    if ($rel -eq $UsedList) { continue }
    if ($rel -like '*/tools/*' -or $rel -like '*\\tools\\*') { continue }
    if ($rel -like '*/.import/*' -or $rel -like '*\\.import\\*') { continue }
    if (-not $usedSet.Contains($rel)) {
        $unused += $f
    }
}

if ($unused.Count -eq 0) {
    Write-Host "No unused files found."
    exit 0
}

$destRoot = Join-Path $projectRoot $ArchiveDir
New-Item -ItemType Directory -Force -Path $destRoot | Out-Null

foreach ($f in $unused) {
    $rel = To-Rel $f.FullName
    $dest = Join-Path $destRoot $rel
    $destDir = [System.IO.Path]::GetDirectoryName($dest)
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    try {
        Move-Item -LiteralPath $f.FullName -Destination $dest -Force
    } catch {
        Write-Warning "Failed to move: $($f.FullName) -> $dest : $($_.Exception.Message)"
    }
}

Write-Host "Moved" $unused.Count "unused files to" $ArchiveDir


