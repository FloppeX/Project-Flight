param(
    [int]$QuitAfterFrames = 3600,
    [int]$TimeoutSeconds = 190,
    [switch]$GpuProfile,
    [switch]$ScriptProfiling
)

$ErrorActionPreference = 'Stop'

$project = 'C:\Godot projects\Project-Flight'
$godot = 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outDir = Join-Path $project 'captures\perf_diagnostics'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$scenarioDir = Join-Path $env:APPDATA 'Godot\app_userdata\Land Carrier'
$scenarioPath = Join-Path $scenarioDir 'physical_test_scenario.json'
New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null
$previousScenario = if (Test-Path $scenarioPath) { Get-Content -Raw -Path $scenarioPath } else { '' }

$godotOut = Join-Path $outDir "godot_stdout_$stamp.log"
$godotErr = Join-Path $outDir "godot_stderr_$stamp.log"
$godotLog = Join-Path $outDir "godot_engine_$stamp.log"
$sampleCsv = Join-Path $outDir "process_samples_$stamp.csv"
$summaryPath = Join-Path $outDir "summary_$stamp.txt"

Set-Content -Path $scenarioPath -Value '{"scenario":1}' -Encoding UTF8

try {
    $args = @(
        '--path', $project,
        '--print-fps',
        '--quit-after', "$QuitAfterFrames"
    )
    if ($GpuProfile) {
        $args += '--gpu-profile'
    }
    if ($ScriptProfiling) {
        $args += '--profiling'
    }
    $args += @('--log-file', $godotLog)
    $proc = Start-Process -FilePath $godot -ArgumentList $args -PassThru `
        -RedirectStandardOutput $godotOut -RedirectStandardError $godotErr

    'timestamp,elapsed_s,pid,process,cpu_s,delta_cpu_s,working_set_mb,private_mb,threads,top_processes' |
        Set-Content -Path $sampleCsv -Encoding UTF8

    $lastCpu = @{}
    $start = Get-Date
    while (-not $proc.HasExited) {
        Start-Sleep -Seconds 2
        $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
        $godotProc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        $topText = ((Get-Process |
            Sort-Object CPU -Descending |
            Select-Object -First 8 |
            ForEach-Object {
                '{0}:{1}:cpu_total={2:F1}:ws={3:F0}MB' -f $_.Id, $_.ProcessName, $_.CPU, ($_.WorkingSet64 / 1MB)
            }) -join '|').Replace(',', ';')

        if ($godotProc) {
            $prevCpu = if ($lastCpu.ContainsKey($godotProc.Id)) {
                [double]$lastCpu[$godotProc.Id]
            } else {
                [double]$godotProc.CPU
            }
            $deltaCpu = [math]::Round(([double]$godotProc.CPU - $prevCpu), 3)
            $lastCpu[$godotProc.Id] = [double]$godotProc.CPU
            $line = '{0},{1},{2},{3},{4:F3},{5:F3},{6:F1},{7:F1},{8},"{9}"' -f `
                (Get-Date).ToString('o'),
                $elapsed,
                $godotProc.Id,
                $godotProc.ProcessName,
                $godotProc.CPU,
                $deltaCpu,
                ($godotProc.WorkingSet64 / 1MB),
                ($godotProc.PrivateMemorySize64 / 1MB),
                $godotProc.Threads.Count,
                $topText
            Add-Content -Path $sampleCsv -Value $line -Encoding UTF8
        } else {
            Add-Content -Path $sampleCsv -Value ('{0},{1},,,,,,,,"{2}"' -f (Get-Date).ToString('o'), $elapsed, $topText) -Encoding UTF8
        }

        if ($elapsed -ge $TimeoutSeconds) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            break
        }
    }

    $proc.WaitForExit()
    $exitCode = $proc.ExitCode

    $fpsLines = if (Test-Path $godotOut) {
        Select-String -Path $godotOut -Pattern 'FPS|gpu|profile|FrameProfiler|HELI NAVIGATION|TUNER|SPAWN|ERROR|WARNING' -CaseSensitive:$false |
            Select-Object -Last 120 |
            ForEach-Object { $_.Line }
    } else { @() }

    $engineLines = if (Test-Path $godotLog) {
        Select-String -Path $godotLog -Pattern 'FPS|gpu|profile|FrameProfiler|HELI NAVIGATION|TUNER|SPAWN|ERROR|WARNING' -CaseSensitive:$false |
            Select-Object -Last 120 |
            ForEach-Object { $_.Line }
    } else { @() }

    $samples = Import-Csv $sampleCsv
    $godotSamples = $samples | Where-Object { $_.process -like 'Godot*' -and $_.delta_cpu_s }
    $avgCore = if ($godotSamples.Count -gt 0) {
        [math]::Round(((($godotSamples | ForEach-Object { [double]$_.delta_cpu_s } | Measure-Object -Average).Average / 2.0) * 100), 1)
    } else { 0 }
    $maxWs = if ($godotSamples.Count -gt 0) {
        [math]::Round((($godotSamples | ForEach-Object { [double]$_.working_set_mb } | Measure-Object -Maximum).Maximum), 1)
    } else { 0 }

    $reportPath = Join-Path $project 'heli_navigation_report.log'
    $reportTail = if (Test-Path $reportPath) { Get-Content $reportPath -Tail 80 } else { @() }
    $profTail = if (Test-Path $godotOut) {
        Select-String -Path $godotOut -Pattern '\[FrameProfiler' |
            Select-Object -Last 40 |
            ForEach-Object { $_.Line }
    } else { @() }

    @(
        "exit_code=$exitCode",
        "stamp=$stamp",
        "avg_godot_cpu_one_core_percent=$avgCore",
        "max_godot_working_set_mb=$maxWs",
        "godot_stdout=$godotOut",
        "godot_stderr=$godotErr",
        "godot_engine_log=$godotLog",
        "process_samples=$sampleCsv",
        '',
        '--- profiler tail ---',
        $profTail,
        '',
        '--- fps/profile/search tail stdout ---',
        $fpsLines,
        '',
        '--- fps/profile/search tail engine log ---',
        $engineLines,
        '',
        '--- heli_navigation_report tail ---',
        $reportTail
    ) | Set-Content -Path $summaryPath -Encoding UTF8

    Get-Content $summaryPath -TotalCount 260
    Write-Output "SUMMARY_PATH=$summaryPath"
    Write-Output "SAMPLE_CSV=$sampleCsv"
    Write-Output "GODOT_OUT=$godotOut"
    Write-Output "GODOT_ENGINE_LOG=$godotLog"
}
finally {
    if ($previousScenario -ne '') {
        Set-Content -Path $scenarioPath -Value $previousScenario -Encoding UTF8
    } else {
        Remove-Item -Path $scenarioPath -ErrorAction SilentlyContinue
    }
    if (Test-Path $scenarioPath) {
        Write-Output "SCENARIO_RESTORED=$(Get-Content -Raw -Path $scenarioPath)"
    } else {
        Write-Output 'SCENARIO_RESTORED=<missing>'
    }
}
