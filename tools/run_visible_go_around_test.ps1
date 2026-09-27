param(
    [ValidateSet('Aircraft_1', 'Aircraft_2', 'Aircraft_5')][string]$Aircraft = 'Aircraft_2',
    [ValidateRange(0, 6)][int]$StartCase = 0,
    [ValidateRange(0, 7)][int]$Cases = 0,
    [ValidateSet('Escape', 'LandingRetry')][string]$Mode = 'Escape',
    [string]$GodotPath = 'C:\Godot\Godot_v4.6.2-stable_win64.exe'
)
$ErrorActionPreference = 'Stop'
if ($Cases -eq 0) { $Cases = if ($Mode -eq 'LandingRetry') { 4 } else { 7 } }
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runPrefix = if ($Mode -eq 'LandingRetry') { 'visible_landing_retry_' } else { 'visible_go_around_' }
$runId = $runPrefix + (Get-Date -Format 'yyyyMMdd_HHmmss')
$runDir = Join-Path $env:APPDATA ('Godot\app_userdata\Land Carrier\' + $runId)
New-Item -ItemType Directory -Path $runDir | Out-Null
$paths = @('AI/AIPilot.gd', 'AI/LandingSight.gd', 'Aircraft/aircraft.gd', 'Aircraft/SimpleAero.gd',
    'Aircraft/Aircraft_1.tscn', 'Aircraft/Aircraft_2.tscn', 'Aircraft/Aircraft_5.tscn',
    'Scenario/LandingTestMode.gd', 'Scenario/GoAroundTestObserver.gd',
    'LandCarrier/ArrestingCable.gd', 'LandCarrier/arresting_cable.tscn',
    'LandCarrier/LandCarrier2.tscn', 'LandCarrier/LandCarrier.gd', 'LandCarrier/FlightDeckManager.gd',
    'LandCarrier/CarrierCollisionSetup.gd', 'Environment/LowPolyTerrain.gd',
    'Main_Scene.tscn', 'project.godot', 'Models/LandCarrier/Land carrier 4.glb',
    'addons/simplified_flightsim/aircraft_modules/Flaps/flaps.gd')
$manifest = @(foreach ($path in $paths) {
    $source = Join-Path $projectPath $path
    Copy-Item -LiteralPath $source -Destination $runDir
    [ordered]@{ path=$path; sha256=(Get-FileHash -LiteralPath $source).Hash }
})
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDir 'input_hashes.json') -Encoding UTF8
$modeFlag = if ($Mode -eq 'LandingRetry') { '--landing-retry-test' } else { '--landing-go-around-test' }
$timeout = if ($Mode -eq 'LandingRetry') { 480 } else { 90 }
$arguments = @('--path', ('"' + $projectPath + '"'), '--scene', 'res://Main_Scene.tscn',
    '--windowed', '--resolution', '1280x800', '--position', '60,50', '--max-fps', '60',
    '--', '--test-scenario=5', '--test-seed=20260908', $modeFlag,
    "--landing-aircraft-model=$Aircraft", "--landing-matrix-start-case=$StartCase",
    "--landing-attempt-limit=$Cases", "--landing-attempt-timeout=$timeout")
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Normal `
    -RedirectStandardOutput (Join-Path $runDir 'stdout.log') `
    -RedirectStandardError (Join-Path $runDir 'stderr.log') -PassThru
[ordered]@{ run_id=$runId; pid=$process.Id; aircraft=$Aircraft; cases=$Cases; start_case=$StartCase; mode=$Mode;
    visible=$true; realtime=$true; directory=$runDir } |
    ConvertTo-Json | Tee-Object -FilePath (Join-Path $runDir 'run.json')
