param(
    [ValidateRange(1, 3650)][int]$KeepDays = 14,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$rootPrefix = $projectRoot.TrimEnd('\') + '\'
$cutoff = (Get-Date).AddDays(-$KeepDays)
$candidates = @(Get-ChildItem -LiteralPath $projectRoot -File -Filter '*.log')
foreach ($relative in @('logs', 'run_archives', 'turn_optimizer_runs', 'gunnery_optimizer_runs')) {
    $directory = [IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
    if (-not $directory.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Directory outside project: $directory"
    }
    if (Test-Path -LiteralPath $directory) {
        if ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing linked directory: $directory"
        }
        $candidates += Get-ChildItem -LiteralPath $directory -File -Filter '*.log' -Recurse
    }
}
$old = @($candidates | Where-Object LastWriteTime -LT $cutoff)
$bytes = ($old | Measure-Object Length -Sum).Sum
foreach ($file in $old) {
    $resolved = [IO.Path]::GetFullPath($file.FullName)
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "File outside project: $resolved"
    }
    $ancestor = $file
    while ($ancestor.FullName -ne $projectRoot) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing linked path: $($ancestor.FullName)"
        }
        $ancestor = if ($ancestor -is [IO.FileInfo]) { $ancestor.Directory } else { $ancestor.Parent }
    }
}
if ($Apply) {
    foreach ($file in $old) { Remove-Item -LiteralPath $file.FullName }
}
[pscustomobject]@{
    Mode = $(if ($Apply) { 'Deleted' } else { 'Preview' })
    Logs = $old.Count
    MiB = [math]::Round($bytes / 1MB, 2)
    OlderThan = $cutoff
}
