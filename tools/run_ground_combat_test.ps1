param(
    [ValidateRange(1, 12)]
    [double]$TimeScale = 6.0,
    [ValidateRange(2, 30)]
    [int]$TimeoutMinutes = 4,
    [switch]$Visible,
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe"
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runId = "ground_combat_" + (Get-Date -Format "yyyyMMdd_HHmmss")
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$stdoutPath = Join-Path $settingsDir ($runId + ".stdout.log")
$stderrPath = Join-Path $settingsDir ($runId + ".stderr.log")
$reportPath = Join-Path $settingsDir ("ground_combat_test_" + $runId + ".log")

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}

$arguments = @(
    "--path", ('"' + $projectPath + '"'),
    "--scene", "res://Main_Scene.tscn",
    "--",
    "--test-scenario=7",
    "--ground-test-time-scale=$TimeScale",
    "--test-run-id=$runId"
)

if ($Visible) {
    Write-Host "Launching visible ground combat test: $runId"
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru
    Write-Host "Godot PID: $($process.Id)"
    Write-Host "Report: $reportPath"
    return
}

$arguments = @("--headless", "--fixed-fps", "60") + $arguments + @("--quit-on-test-complete")
Write-Host "Starting accelerated ground combat validation: $runId"
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments `
    -WindowStyle Hidden -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -PassThru
$finished = $process.WaitForExit($TimeoutMinutes * 60 * 1000)

if (-not $finished) {
    Stop-Process -Id $process.Id -Force
    throw "Ground combat test timed out after $TimeoutMinutes minutes. Logs: $stdoutPath"
}

$resultLine = $null
if (Test-Path -LiteralPath $reportPath) {
    $resultLine = Get-Content -LiteralPath $reportPath |
        Where-Object { $_ -match "RUN_RESULT json=" } |
        Select-Object -Last 1
}
if ($null -eq $resultLine -or $resultLine -notmatch "RUN_RESULT json=(.+)$") {
    throw "Ground combat test produced no RUN_RESULT (exit $($process.ExitCode)). Logs: $stdoutPath"
}

$result = $Matches[1] | ConvertFrom-Json
Write-Host "$($result.status): enemies_destroyed=$($result.enemy_destroyed)/$($result.enemy_initial) friendly_alive=$($result.friendly_alive)/$($result.friendly_deployed_peak) elapsed=$([Math]::Round($result.elapsed_s, 1))s"
Write-Host "Report: $reportPath"
if ($result.status -ne "PASS") {
    exit 1
}
