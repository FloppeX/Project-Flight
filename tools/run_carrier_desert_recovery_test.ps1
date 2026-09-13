param(
    [int]$Seed = 20260825,
    [ValidateRange(1, 8)]
    [int]$ActiveAircraft = 6,
    [ValidateRange(0, 1000)]
    [int]$TargetTraps = 24,
    [ValidateRange(5, 120)]
    [int]$TimeoutMinutes = 45,
    [string]$AircraftModel = "",
    [switch]$StrictFinalHandoff,
    [switch]$ObserveThroughStow,
    [ValidateRange(0, 500)]
    [double]$ForceWaveoffAtM = 0,
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe"
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runId = "desert_recovery_" + (Get-Date -Format "yyyyMMdd_HHmmss") + "_seed_$Seed"
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$stdoutPath = Join-Path $settingsDir ($runId + ".stdout.log")
$stderrPath = Join-Path $settingsDir ($runId + ".stderr.log")
$reportPath = Join-Path $settingsDir ("carrier_combat_test_" + $runId + ".log")

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}

$supportedAircraftModels = @("Aircraft_1", "Aircraft_2", "Aircraft_5", "Aircraft_7", "Aircraft_8")
if (-not [string]::IsNullOrWhiteSpace($AircraftModel) -and $AircraftModel -notin $supportedAircraftModels) {
    throw "Unsupported aircraft model '$AircraftModel'. Choose one of: $($supportedAircraftModels -join ', ')"
}

$arguments = @(
    "--headless",
    "--path", ('"' + $projectPath + '"'),
    "--scene", "res://Main_Scene.tscn",
    "--fixed-fps", "60",
    "--",
    "--test-scenario=6",
    "--test-profile=desert_recovery",
    "--rolling-active=$ActiveAircraft",
    "--rolling-target-traps=$TargetTraps",
    "--test-seed=$Seed",
    "--test-run-id=$runId",
    "--quit-on-test-complete"
)

if (-not [string]::IsNullOrWhiteSpace($AircraftModel)) {
    $arguments += "--desert-aircraft-model=$AircraftModel"
    # A model-isolation run should terminate with that one airframe's result;
    # rolling replacement would turn one failure into an unbounded relaunch test.
    $arguments += "--rolling-finite-cohort"
}
if ($StrictFinalHandoff) {
    $arguments += "--strict-recovery-handoff"
}
if ($ObserveThroughStow) {
    $arguments += "--observe-through-stow"
    $arguments += "--rolling-finite-cohort"
}
if ($ForceWaveoffAtM -gt 0) {
    $arguments += "--force-waveoff-at-m=$ForceWaveoffAtM"
}

$finalMode = if ($StrictFinalHandoff) { "strict" } else { "diagnostic" }
$waveoffMode = if ($ForceWaveoffAtM -gt 0) { " waveoff=${ForceWaveoffAtM}m" } else { "" }
Write-Host "Starting accelerated desert carrier recovery: $runId active=$ActiveAircraft target_traps=$TargetTraps model=$AircraftModel final=$finalMode$waveoffMode"
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments `
    -WindowStyle Hidden -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -PassThru
$finished = $process.WaitForExit($TimeoutMinutes * 60 * 1000)

if (-not $finished) {
    Stop-Process -Id $process.Id -Force
    throw "Desert recovery timed out after $TimeoutMinutes minutes. Logs: $stdoutPath"
}

$resultLine = $null
if (Test-Path -LiteralPath $reportPath) {
    $resultLine = Get-Content -LiteralPath $reportPath |
        Where-Object { $_ -match "RUN_RESULT json=" } |
        Select-Object -Last 1
}
if ($null -eq $resultLine -or $resultLine -notmatch "RUN_RESULT json=(.+)$") {
    throw "Desert recovery produced no RUN_RESULT (exit $($process.ExitCode)). Logs: $stdoutPath"
}

$result = $Matches[1] | ConvertFrom-Json
Write-Host "$($result.status): caught=$($result.caught) launches=$($result.friendly_launched) active_cap=$ActiveAircraft target_traps=$TargetTraps sim=$($result.sim_time_s)s"
if ($result.status -ne "PASS" -and -not [string]::IsNullOrWhiteSpace($result.failure_reason)) {
    Write-Host "Failure: $($result.failure_reason)"
}
if ($null -ne $result.recovery_stages) {
    Write-Host ("Stages: launch={0} outbound={1} rtb={2} route={3} pre_landing={4} final={5} caught={6}" -f `
        $result.recovery_stages.launch_complete,
        $result.recovery_stages.outbound_complete,
        $result.recovery_stages.rtb_started,
        $result.recovery_stages.recovery_route,
        $result.recovery_stages.pre_landing,
        $result.recovery_stages.final_handoff,
        $result.recovery_stages.confirmed_landing)
}
if ($null -ne $result.forced_waveoff -and $result.forced_waveoff.enabled) {
    Write-Host ("Waveoff: requested={0}m actual={1}m triggered={2} cleared={3}" -f `
        $result.forced_waveoff.requested_remaining_m,
        $result.forced_waveoff.actual_remaining_m,
        $result.forced_waveoff.triggered,
        $result.forced_waveoff.cleared)
}
Write-Host "Report: $reportPath"
if ($result.observe_through_stow) {
    foreach ($cycle in $result.cycles) {
        Write-Host ("  {0} {1}: launched={2} returned={3} caught={4} stopped={5} stowed={6} health={7} damage={8}" -f `
            $cycle.model, $cycle.status, $cycle.launched, $cycle.rtb_started,
            $cycle.wire_caught, $cycle.stopped, $cycle.stowed, $cycle.health, $cycle.damage_taken)
    }
}
if ($result.status -ne "PASS") {
    exit 1
}
