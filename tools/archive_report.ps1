param(
    [string]$Example = "res://example/Example1_Simple.tscn",
    [string]$OutReport = "archive_candidates.txt",
    [string]$ArchiveDir = "Archive"
)

$ErrorActionPreference = 'Stop'

Write-Host "Analyzing dependencies from: $Example"
Write-Host "Output report: $OutReport"
Write-Host "Archive folder: $ArchiveDir"
Write-Host ""

# Generate used files list
Write-Host "Step 1: Generating dependency list..."
& "$PSScriptRoot\list_used_files.ps1" -Example $Example -Out "used_files.txt"

if (-not (Test-Path "used_files.txt")) {
    Write-Error "Failed to generate used_files.txt"
    exit 1
}

$used = Get-Content "used_files.txt" | Where-Object { $_ -and ($_ -is [string]) }
$usedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$used)

Write-Host "Found $($used.Count) used files"
Write-Host ""

# Find all project files
Write-Host "Step 2: Scanning project files..."
$projectRoot = Get-Location

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

Write-Host "Found $($allFiles.Count) total project files"
Write-Host ""

# Categorize files
Write-Host "Step 3: Categorizing files..."

$unused = @()
$usedFiles = @()
$systemFiles = @()

foreach ($f in $allFiles) {
    $rel = To-Rel $f.FullName
    
    # Skip system files
    if ($rel -like "*.import" -or 
        $rel -like "*.uid" -or 
        $rel -eq "used_files.txt" -or
        $rel -eq "project.godot" -or
        $rel -like "*.tmp") {
        $systemFiles += $f
        continue
    }
    
    if ($usedSet.Contains($rel)) {
        $usedFiles += $f
    } else {
        $unused += $f
    }
}

# Group unused files by type
$unusedByType = @{}
foreach ($f in $unused) {
    $ext = [System.IO.Path]::GetExtension($f.Name).ToLowerInvariant()
    if (-not $unusedByType.ContainsKey($ext)) {
        $unusedByType[$ext] = @()
    }
    $unusedByType[$ext] += $f
}

# Generate report
Write-Host "Step 4: Generating report..."

$report = @()
$report += "ARCHIVE CANDIDATES REPORT"
$report += "========================="
$report += "Generated: $(Get-Date)"
$report += "Source: $Example"
$report += ""
$report += "SUMMARY:"
$report += "--------"
$report += "Used files: $($usedFiles.Count)"
$report += "Unused files: $($unused.Count)"
$report += "System files: $($systemFiles.Count)"
$report += ""

$report += "UNUSED FILES BY TYPE:"
$report += "--------------------"
foreach ($ext in ($unusedByType.Keys | Sort-Object)) {
    $count = $unusedByType[$ext].Count
    $size = ($unusedByType[$ext] | Measure-Object -Property Length -Sum).Sum
    $sizeMB = [math]::Round($size / 1MB, 2)
    $report += "$ext`: $count files ($sizeMB MB)"
}
$report += ""

$report += "DETAILED UNUSED FILES:"
$report += "---------------------"
foreach ($ext in ($unusedByType.Keys | Sort-Object)) {
    $report += ""
    $report += "=== $ext files ==="
    foreach ($f in ($unusedByType[$ext] | Sort-Object Name)) {
        $rel = To-Rel $f.FullName
        $sizeKB = [math]::Round($f.Length / 1KB, 1)
        $report += "  $rel ($sizeKB KB)"
    }
}

$report += ""
$report += "USED FILES (for reference):"
$report += "--------------------------"
foreach ($f in ($usedFiles | Sort-Object Name)) {
    $rel = To-Rel $f.FullName
    $report += "  $rel"
}

$report | Set-Content -Path $OutReport

Write-Host "Report saved to: $OutReport"
Write-Host ""
Write-Host "SUMMARY:"
Write-Host "--------"
Write-Host "Used files: $($usedFiles.Count)"
Write-Host "Unused files: $($unused.Count)"
Write-Host "System files: $($systemFiles.Count)"
Write-Host ""

if ($unused.Count -gt 0) {
    Write-Host "UNUSED FILES BY TYPE:"
    foreach ($ext in ($unusedByType.Keys | Sort-Object)) {
        $count = $unusedByType[$ext].Count
        $size = ($unusedByType[$ext] | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 2)
        Write-Host "  $ext`: $count files ($sizeMB MB)"
    }
    Write-Host ""
    Write-Host "To move unused files to archive, run:"
    Write-Host "  .\tools\move_to_archive.ps1 -ArchiveDir `"$ArchiveDir`""
} else {
    Write-Host "No unused files found!"
}












