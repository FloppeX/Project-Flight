param(
    [ValidateRange(1, 100)]
    [int]$Runs = 6,
    [int]$BaseSeed = 20260801,
    [ValidateRange(1, 120)]
    [int]$RunTimeoutMinutes = 30,
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe"
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$batchId = "batch_" + (Get-Date -Format "yyyyMMdd_HHmmss")
$batchDir = Join-Path $settingsDir $batchId
$summaryPath = Join-Path $batchDir "summary.jsonl"

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}
New-Item -ItemType Directory -Path $batchDir -Force | Out-Null

Write-Host "Carrier strike-to-recovery batch (enemy air skipped): $batchId"
Write-Host "Runs: $Runs; base seed: $BaseSeed; timeout: $RunTimeoutMinutes minutes per run"
Write-Host "Summary: $summaryPath"

for ($index = 1; $index -le $Runs; $index++) {
    # A prime stride keeps adjacent runs from sharing the same early random stream.
    $runSeed = $BaseSeed + (($index - 1) * 7919)
    $runId = "${batchId}_run_$('{0:D2}' -f $index)_seed_$runSeed"
    $stdoutPath = Join-Path $batchDir ($runId + ".stdout.log")
    $stderrPath = Join-Path $batchDir ($runId + ".stderr.log")
    $reportPath = Join-Path $settingsDir ("carrier_combat_test_" + $runId + ".log")
    $arguments = @(
        "--headless",
        "--path", ('"' + $projectPath + '"'),
        "--scene", "res://Main_Scene.tscn",
        "--fixed-fps", "60",
        "--",
        "--test-scenario=6",
        "--test-profile=full_cycle",
        "--test-seed=$runSeed",
        "--test-run-id=$runId",
        "--skip-enemy-air",
        "--quit-on-test-complete"
    )

    Write-Host "[$index/$Runs] Starting seed $runSeed"
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments `
        -WindowStyle Hidden -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath -PassThru
    $finished = $process.WaitForExit($RunTimeoutMinutes * 60 * 1000)

    if (-not $finished) {
        Stop-Process -Id $process.Id -Force
        $timeoutResult = [ordered]@{
            run_id = $runId
            seed = $runSeed
            status = "TIMEOUT"
            timeout_minutes = $RunTimeoutMinutes
        } | ConvertTo-Json -Compress
        Add-Content -LiteralPath $summaryPath -Value $timeoutResult
        Write-Warning "[$index/$Runs] TIMEOUT seed $runSeed"
        continue
    }

    $resultLine = $null
    if (Test-Path -LiteralPath $reportPath) {
        $resultLine = Get-Content -LiteralPath $reportPath | Where-Object { $_ -match "RUN_RESULT json=" } | Select-Object -Last 1
    }
    if ($null -ne $resultLine -and $resultLine -match "RUN_RESULT json=(.+)$") {
        $resultJson = $Matches[1]
        Add-Content -LiteralPath $summaryPath -Value $resultJson
        $result = $resultJson | ConvertFrom-Json
        Write-Host "[$index/$Runs] $($result.status): caught=$($result.caught)/$($result.friendly_launched) sim=$($result.sim_time_s)s"
    } else {
        $missingResult = [ordered]@{
            run_id = $runId
            seed = $runSeed
            status = "NO_RESULT"
            exit_code = $process.ExitCode
        } | ConvertTo-Json -Compress
        Add-Content -LiteralPath $summaryPath -Value $missingResult
        Write-Warning "[$index/$Runs] NO_RESULT seed $runSeed (exit $($process.ExitCode))"
    }
}

$rows = @(Get-Content -LiteralPath $summaryPath | ForEach-Object { $_ | ConvertFrom-Json })
$passes = @($rows | Where-Object { $_.status -eq "PASS" }).Count
$caught = ($rows | Measure-Object -Property caught -Sum).Sum
$launched = ($rows | Measure-Object -Property friendly_launched -Sum).Sum
Write-Host "Batch complete: passes=$passes/$Runs caught=$caught/$launched"
Write-Host "Summary: $summaryPath"
