param(
    [string]$Godot = 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe',
    [string[]]$SceneRoot = @()
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logDirectory = Join-Path $projectRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$logPath = Join-Path $logDirectory 'scene_resource_check.log'
$arguments = @('--headless', '--path', $projectRoot, '--script',
    'res://tools/validate_scene_resources.gd', '--', '--disable-campaign-autosave')
foreach ($scene in $SceneRoot) { $arguments += "--scene-root=$scene" }
& $Godot @arguments *> $logPath
$engineExit = $LASTEXITCODE
$diagnostics = @(Select-String -LiteralPath $logPath -Pattern '^SCRIPT ERROR:|^ERROR:' )
Select-String -LiteralPath $logPath -Pattern 'SCENE_RESOURCE_CHECK|^SCRIPT ERROR:|^ERROR:' |
    ForEach-Object { $_.Line }
Write-Output "Full output: $logPath"
# Godot can return a PackedScene despite a dependency/script error. Treat logged
# engine errors as failures too, even when the resource-level check passes.
if ($engineExit -ne 0 -or $diagnostics.Count -gt 0 -or
    -not (Select-String -LiteralPath $logPath -Pattern '^SCENE_RESOURCE_CHECK PASS ')) {
    exit 1
}
exit 0
