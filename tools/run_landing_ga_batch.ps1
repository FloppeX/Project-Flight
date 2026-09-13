param(
    [ValidateSet("Aircraft_1", "Aircraft_5")]
    [string]$AircraftModel = "Aircraft_5",
    [ValidateRange(4, 24)]
    [int]$Population = 4,
    [ValidateRange(1, 10000)]
    [int]$TrialBudget = 24,
    [ValidateRange(1, 240)]
    [int]$TimeoutMinutes = 30,
    [switch]$Visible,
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe"
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$modelSlug = $AircraftModel.ToLowerInvariant()
$runId = "landing_ga_batch_" + $modelSlug + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")
$stdoutPath = Join-Path $settingsDir ($runId + ".stdout.log")
$stderrPath = Join-Path $settingsDir ($runId + ".stderr.log")
$liveReportPath = Join-Path $settingsDir "landing_test_report.log"
$reportPath = Join-Path $settingsDir ($runId + ".report.log")
$statePath = Join-Path $settingsDir ("landing_ga_state_" + $modelSlug + ".json")

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

$arguments = @(
    "--path", ('"' + $projectPath + '"'),
    "--scene", "res://Main_Scene.tscn",
    "--fixed-fps", "60",
    "--",
    "--test-scenario=5",
    "--landing-genetic-tuning",
    "--landing-aircraft-model=$AircraftModel",
    "--landing-ga-population=$Population",
    "--landing-attempt-limit=$TrialBudget"
)
if (-not $Visible) {
    $arguments = @("--headless") + $arguments
}

Write-Host "Running $AircraftModel landing GA batch: population=$Population trials=$TrialBudget"
Write-Host "The airframe-specific state is saved after every trial and will resume on the next batch."
$windowStyle = if ($Visible) { "Normal" } else { "Hidden" }
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments `
    -WindowStyle $windowStyle -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -PassThru
$finished = $process.WaitForExit($TimeoutMinutes * 60 * 1000)
if (-not $finished) {
    Stop-Process -Id $process.Id -Force
    throw "$AircraftModel landing GA timed out after $TimeoutMinutes minutes. State was preserved at $statePath"
}
if (Test-Path -LiteralPath $liveReportPath) {
    Copy-Item -LiteralPath $liveReportPath -Destination $reportPath -Force
}
if (-not (Test-Path -LiteralPath $reportPath)) {
    throw "$AircraftModel landing GA produced no report (exit $($process.ExitCode)). Log: $stdoutPath"
}
$resultLine = Get-Content -LiteralPath $reportPath |
    Where-Object { $_ -match "GA_RUN_RESULT json=" } |
    Select-Object -Last 1
if ($null -eq $resultLine -or $resultLine -notmatch "GA_RUN_RESULT json=(.+)$") {
    throw "$AircraftModel landing GA produced no GA_RUN_RESULT (exit $($process.ExitCode)). Report: $reportPath"
}
$result = $Matches[1] | ConvertFrom-Json
$tally = $result.tally.direct
$caught = if ($null -ne $tally.CAUGHT) { [int]$tally.CAUGHT } else { 0 }
$bolters = if ($null -ne $tally.BOLTER) { [int]$tally.BOLTER } else { 0 }
$waveoffs = if ($null -ne $tally.'WAVE-OFF') { [int]$tally.'WAVE-OFF' } else { 0 }
$crashes = if ($null -ne $tally.CRASH) { [int]$tally.CRASH } else { 0 }
$timeouts = if ($null -ne $tally.TIMEOUT) { [int]$tally.TIMEOUT } else { 0 }
Write-Host "$AircraftModel batch complete: catches=$caught bolters=$bolters waveoffs=$waveoffs crashes=$crashes timeouts=$timeouts"
Write-Host ("GA position: generation={0} curriculum={1} candidate={2}/{3} case={4}/{5} best_fitness={6:0.0}" -f `
    $result.tuner.generation, $result.tuner.curriculum, $result.tuner.candidate,
    $result.tuner.population, $result.tuner.case, $result.tuner.cases, $result.tuner.best_fitness)
Write-Host "State: $statePath"
Write-Host "Report: $reportPath"
Write-Host "Stdout: $stdoutPath"
