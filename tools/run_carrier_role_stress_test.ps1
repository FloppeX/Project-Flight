param(
    [int]$Seed = 20260801,
    [ValidateRange(5, 120)]
    [int]$TimeoutMinutes = 30,
    [switch]$Visible,
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe"
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runId = "role_stress_" + (Get-Date -Format "yyyyMMdd_HHmmss") + "_seed_$Seed"
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$stdoutPath = Join-Path $settingsDir ($runId + ".stdout.log")
$stderrPath = Join-Path $settingsDir ($runId + ".stderr.log")
$reportPath = Join-Path $settingsDir ("carrier_combat_test_" + $runId + ".log")

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}

$arguments = @(
    "--path", ('"' + $projectPath + '"'),
    "--scene", "res://Main_Scene.tscn",
    "--fixed-fps", "60",
    "--",
    "--test-scenario=6",
    "--test-profile=role_stress",
    "--test-seed=$Seed",
    "--test-run-id=$runId"
)

if ($Visible) {
    Write-Host "Launching visible role stress test: $runId"
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru
    Write-Host "Godot PID: $($process.Id)"
    Write-Host "Report: $reportPath"
    return
}

$arguments = @("--headless") + $arguments + @("--quit-on-test-complete")
Write-Host "Starting accelerated role stress validation: $runId"
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments `
    -WindowStyle Hidden -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -PassThru
$finished = $process.WaitForExit($TimeoutMinutes * 60 * 1000)

if (-not $finished) {
    Stop-Process -Id $process.Id -Force
    throw "Role stress test timed out after $TimeoutMinutes minutes. Logs: $stdoutPath"
}

$resultLine = $null
if (Test-Path -LiteralPath $reportPath) {
    $resultLine = Get-Content -LiteralPath $reportPath |
        Where-Object { $_ -match "RUN_RESULT json=" } |
        Select-Object -Last 1
}
if ($null -eq $resultLine -or $resultLine -notmatch "RUN_RESULT json=(.+)$") {
    throw "Role stress test produced no RUN_RESULT (exit $($process.ExitCode)). Logs: $stdoutPath"
}

$result = $Matches[1] | ConvertFrom-Json
Write-Host "$($result.status): ground=$($result.ground_destroyed)/4 enemy_air=$($result.enemy_spawned - $result.enemy_alive)/$($result.enemy_spawned) recovered=$($result.caught)/$($result.recovery_requested) role_violations=$($result.role_violations)"
Write-Host "Report: $reportPath"
if ($result.status -ne "PASS") {
    exit 1
}
