param(
    [string]$ArchiveDir = "Archive",
    [string]$UsedList = "used_files.txt",
    [switch]$WhatIf = $false
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $UsedList)) {
    Write-Error "Used files list not found: $UsedList"
    Write-Host "Run archive_report.ps1 first to generate the list."
    exit 1
}

$projectRoot = Get-Location
$used = Get-Content $UsedList | Where-Object { $_ -and ($_ -is [string]) }
$usedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$used)

function To-Rel([string]$full) {
    $rel = $full.Substring($projectRoot.Path.Length)
    return ($rel -replace '^[\\/]+','')
}

$allFiles = Get-ChildItem -Recurse -File | Where-Object {
    $_.FullName -notmatch "\\\.git\\" -and 
    $_.FullName -notmatch "\\\.godot\\" -and 
    $_.FullName -notmatch "\\$ArchiveDir\\" -and
    $_.FullName -notlike "*\tools\*"
}

$unused = @()
foreach ($f in $allFiles) {
    $rel = To-Rel $f.FullName
    
    # Skip system files
    if ($rel -like "*.import" -or 
        $rel -like "*.uid" -or 
        $rel -eq "used_files.txt" -or
        $rel -eq "project.godot" -or
        $rel -like "*.tmp") {
        continue
    }
    
    if (-not $usedSet.Contains($rel)) {
        $unused += $f
    }
}

if ($unused.Count -eq 0) {
    Write-Host "No unused files found."
    exit 0
}

Write-Host "Found $($unused.Count) unused files to archive:"
Write-Host ""

$destRoot = Join-Path $projectRoot $ArchiveDir
$movedCount = 0

foreach ($f in $unused) {
    $rel = To-Rel $f.FullName
    $dest = Join-Path $destRoot $rel
    $destDir = Split-Path -Parent $dest
    
    if ($WhatIf) {
        Write-Host "WOULD MOVE: $rel -> $dest"
    } else {
        Write-Host "Moving: $rel"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        try {
            Move-Item -LiteralPath $f.FullName -Destination $dest -Force
            $movedCount++
        } catch {
            Write-Warning "Failed to move: $($f.FullName) -> $dest : $($_.Exception.Message)"
        }
    }
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "This was a dry run. To actually move files, run without -WhatIf"
} else {
    Write-Host ""
    Write-Host "Moved $movedCount files to $ArchiveDir"
    Write-Host "To restore files, run: .\tools\restore_archive.ps1 -ArchiveDir `"$ArchiveDir`""
}















