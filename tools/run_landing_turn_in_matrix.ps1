param(
    [ValidateRange(1, 20)]
    [int]$Repeats = 3,
    [ValidateRange(0, 5)]
    [int]$StartCase = 0,
    [ValidateRange(0, 120)]
    [int]$AttemptLimit = 0,
    [ValidateRange(1, 120)]
    [int]$TimeoutMinutes = 30,
    [switch]$Visible,
    [ValidateSet("current", "baseline", "energy")]
    [string]$GuidanceVariant = "current",
    [switch]$HoldoutEntries,
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe"
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$runId = "landing_turn_in_matrix_" + (Get-Date -Format "yyyyMMdd_HHmmss")
$stdoutPath = Join-Path $settingsDir ($runId + ".stdout.log")
$stderrPath = Join-Path $settingsDir ($runId + ".stderr.log")
$liveReportPath = Join-Path $settingsDir "landing_test_report.log"
$reportPath = Join-Path $settingsDir ($runId + ".report.log")
$resultPath = Join-Path $settingsDir ($runId + ".json")

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
    "--landing-turn-in-matrix",
    "--landing-aircraft-model=Aircraft_5",
    "--landing-matrix-repeats=$Repeats",
    "--landing-matrix-start-case=$StartCase",
    "--landing-guidance-variant=$GuidanceVariant"
)
if ($HoldoutEntries) {
    $arguments += "--landing-holdout-entries"
}
if (-not $Visible) {
    $arguments = @("--headless") + $arguments
}
if ($AttemptLimit -gt 0) {
    $arguments += "--landing-attempt-limit=$AttemptLimit"
}

Write-Host "Running Aircraft_5 90-degree turn-in matrix (repeats=$Repeats start_case=$StartCase attempt_limit=$AttemptLimit)"
$windowStyle = if ($Visible) { "Normal" } else { "Hidden" }
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments `
    -WindowStyle $windowStyle -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -PassThru
$finished = $process.WaitForExit($TimeoutMinutes * 60 * 1000)
if (-not $finished) {
    Stop-Process -Id $process.Id -Force
    throw "Aircraft_5 turn-in matrix timed out after $TimeoutMinutes minutes. Log: $stdoutPath"
}
if (Test-Path -LiteralPath $liveReportPath) {
    Copy-Item -LiteralPath $liveReportPath -Destination $reportPath -Force
}
if (-not (Test-Path -LiteralPath $reportPath)) {
    throw "Aircraft_5 turn-in matrix produced no report (exit $($process.ExitCode)). Log: $stdoutPath"
}
$resultLine = Get-Content -LiteralPath $reportPath |
    Where-Object { $_ -match "TURN_IN_RESULT json=" } |
    Select-Object -Last 1
if ($null -eq $resultLine -or $resultLine -notmatch "TURN_IN_RESULT json=(.+)$") {
    throw "Aircraft_5 turn-in matrix produced no TURN_IN_RESULT (exit $($process.ExitCode)). Report: $reportPath"
}
$result = $Matches[1] | ConvertFrom-Json
$result | Add-Member -NotePropertyName report_path -NotePropertyValue $reportPath
$result | Add-Member -NotePropertyName stdout_path -NotePropertyValue $stdoutPath
$result | Add-Member -NotePropertyName stderr_path -NotePropertyValue $stderrPath
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8

$caught = if ($null -ne $result.outcomes.CAUGHT) { [int]$result.outcomes.CAUGHT } else { 0 }
$waveoffs = if ($null -ne $result.outcomes.'WAVE-OFF') { [int]$result.outcomes.'WAVE-OFF' } else { 0 }
$bolters = if ($null -ne $result.outcomes.BOLTER) { [int]$result.outcomes.BOLTER } else { 0 }
$crashes = if ($null -ne $result.outcomes.CRASH) { [int]$result.outcomes.CRASH } else { 0 }
$timeouts = if ($null -ne $result.outcomes.TIMEOUT) { [int]$result.outcomes.TIMEOUT } else { 0 }
$routeFails = if ($null -ne $result.outcomes.'ROUTE-FAIL') { [int]$result.outcomes.'ROUTE-FAIL' } else { 0 }
$arrestFails = if ($null -ne $result.outcomes.'ARREST-FAIL') { [int]$result.outcomes.'ARREST-FAIL' } else { 0 }
$reached = @($result.cases | Where-Object { $_.reached_pre_landing }).Count
$reachRate = if ($result.attempts -gt 0) { $reached / [double]$result.attempts } else { 0.0 }
Write-Host ("Aircraft_5 complete: pre_landing_entry={0}/{1} ({2:0%}) stopped_catches={3} waveoffs={4} bolters={5} crashes={6} timeouts={7} route_fails={8} arrest_fails={9}" -f `
    $reached, $result.attempts, $reachRate, $caught, $waveoffs, $bolters, $crashes, $timeouts, $routeFails, $arrestFails)
foreach ($case in $result.cases) {
    Write-Host ("  {0,-10} {1,-10} entry={2,5:0}m lat={3,6:+0.0;-0.0;0.0}m track={4,5:0.0}deg bank={5,5:0.0}deg max={6,5:0.0}deg pre_landing={7} contact_callback={8}@{9:0.0}m/s" -f `
        $case.label, $case.outcome, $case.rollout_behind_m, $case.rollout_lateral_m,
        $case.rollout_track_error_deg, $case.rollout_bank_deg, $case.maximum_bank_deg,
        $case.reached_pre_landing, $case.touchdown_class, $case.touchdown_descent_mps)
}
Write-Host "Result JSON: $resultPath"
Write-Host "Report: $reportPath"
Write-Host "Stdout: $stdoutPath"
