param(
    [double]$SampleIntervalSeconds = 2.0,
    [switch]$GpuProfile,
    [switch]$ScriptProfiling
)

$ErrorActionPreference = 'Stop'

$project = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$godot = 'C:\Godot\Godot_v4.6.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot executable not found: $godot"
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$started = Get-Date
$captureRoot = Join-Path $project 'captures\perf_play_sessions'
$sessionDir = Join-Path $captureRoot $stamp
$userPerfDir = Join-Path $env:APPDATA 'Godot\app_userdata\Land Carrier\perf_logs'
$userDataDir = Join-Path $env:APPDATA 'Godot\app_userdata\Land Carrier'
$userFlightLogPath = Join-Path $userDataDir 'airplane_aero_report.log'
$projectFlightLogPath = Join-Path $project 'airplane_aero_report.log'
New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
New-Item -ItemType Directory -Force -Path $userPerfDir | Out-Null

$stdoutPath = Join-Path $sessionDir 'godot_stdout.log'
$stderrPath = Join-Path $sessionDir 'godot_stderr.log'
$engineLogPath = Join-Path $sessionDir 'godot_engine.log'
$processCsvPath = Join-Path $sessionDir 'process_samples.csv'
$metadataPath = Join-Path $sessionDir 'session.txt'
$activeSessionPath = Join-Path $captureRoot 'active_session.txt'

$arguments = @(
    '--path', ('"{0}"' -f $project),
    '--print-fps',
    '--log-file', ('"{0}"' -f $engineLogPath)
)
if ($GpuProfile) {
    $arguments += '--gpu-profile'
}
if ($ScriptProfiling) {
    $arguments += '--profiling'
}
$arguments += @('--', '--perf-log')

$process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

@(
    'status=running'
    "started=$($started.ToString('o'))"
    "pid=$($process.Id)"
    "session_dir=$sessionDir"
    "stdout=$stdoutPath"
    "stderr=$stderrPath"
    "engine_log=$engineLogPath"
    "process_samples=$processCsvPath"
    'player_flight_log='
    'player_flight_marks='
    'player_mark_count=0'
    "gpu_profile=$([bool]$GpuProfile)"
    "script_profiling=$([bool]$ScriptProfiling)"
) | Set-Content -Path $metadataPath -Encoding UTF8
Copy-Item -LiteralPath $metadataPath -Destination $activeSessionPath -Force

'timestamp,elapsed_s,pid,cpu_s,delta_cpu_s,cpu_one_core_equiv_pct,working_set_mb,private_mb,threads,handles' |
    Set-Content -Path $processCsvPath -Encoding UTF8

$sampleInterval = [math]::Max($SampleIntervalSeconds, 0.5)
$previousCpu = [double]$process.CPU
while (-not $process.HasExited) {
    Start-Sleep -Milliseconds ([int][math]::Round($sampleInterval * 1000.0))
    if ($process.HasExited) {
        break
    }
    $sample = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if ($null -eq $sample) {
        continue
    }
    $cpu = [double]$sample.CPU
    $deltaCpu = [math]::Max($cpu - $previousCpu, 0.0)
    $previousCpu = $cpu
    $elapsed = ((Get-Date) - $started).TotalSeconds
    $oneCorePercent = ($deltaCpu / $sampleInterval) * 100.0
    $line = '{0},{1:F3},{2},{3:F3},{4:F3},{5:F1},{6:F1},{7:F1},{8},{9}' -f `
        (Get-Date).ToString('o'),
        $elapsed,
        $sample.Id,
        $cpu,
        $deltaCpu,
        $oneCorePercent,
        ($sample.WorkingSet64 / 1MB),
        ($sample.PrivateMemorySize64 / 1MB),
        $sample.Threads.Count,
        $sample.HandleCount
    Add-Content -Path $processCsvPath -Value $line -Encoding UTF8
}

$process.WaitForExit()
$ended = Get-Date
$exitCode = $process.ExitCode

$capturedMetricsPath = ''
$newestMetrics = Get-ChildItem -LiteralPath $userPerfDir -Filter 'perf_*.csv' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $started.AddSeconds(-5) } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -ne $newestMetrics) {
    $capturedMetricsPath = Join-Path $sessionDir 'engine_metrics.csv'
    Copy-Item -LiteralPath $newestMetrics.FullName -Destination $capturedMetricsPath -Force
}

$capturedReportPath = ''
$userReportPath = Join-Path $userPerfDir 'performance_report.log'
if (Test-Path -LiteralPath $userReportPath) {
    $reportInfo = Get-Item -LiteralPath $userReportPath
    if ($reportInfo.LastWriteTime -ge $started.AddSeconds(-5)) {
        $capturedReportPath = Join-Path $sessionDir 'performance_report.log'
        Copy-Item -LiteralPath $userReportPath -Destination $capturedReportPath -Force
    }
}

$capturedFlightLogPath = ''
$capturedFlightMarksPath = ''
$playerMarkCount = 0
$freshFlightLogs = @(
    $userFlightLogPath
    $projectFlightLogPath
) | Where-Object {
    Test-Path -LiteralPath $_
} | ForEach-Object {
    Get-Item -LiteralPath $_
} | Where-Object {
    $_.LastWriteTime -ge $started.AddSeconds(-5)
} | Sort-Object LastWriteTime -Descending

if ($freshFlightLogs.Count -gt 0) {
    $capturedFlightLogPath = Join-Path $sessionDir 'player_flight.csv'
    Copy-Item -LiteralPath $freshFlightLogs[0].FullName -Destination $capturedFlightLogPath -Force
    try {
        $markedRows = @(Import-Csv -LiteralPath $capturedFlightLogPath | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.pilot_mark)
        })
        $playerMarkCount = $markedRows.Count
        if ($playerMarkCount -gt 0) {
            $capturedFlightMarksPath = Join-Path $sessionDir 'player_flight_marks.csv'
            $markedRows | Export-Csv -LiteralPath $capturedFlightMarksPath -NoTypeInformation -Encoding UTF8
        }
    }
    catch {
        Write-Warning "Could not extract player flight markers: $($_.Exception.Message)"
    }
}

@(
    'status=complete'
    "started=$($started.ToString('o'))"
    "ended=$($ended.ToString('o'))"
    "duration_s=$([math]::Round(($ended - $started).TotalSeconds, 3))"
    "pid=$($process.Id)"
    "exit_code=$exitCode"
    "session_dir=$sessionDir"
    "stdout=$stdoutPath"
    "stderr=$stderrPath"
    "engine_log=$engineLogPath"
    "process_samples=$processCsvPath"
    "engine_metrics=$capturedMetricsPath"
    "performance_report=$capturedReportPath"
    "player_flight_log=$capturedFlightLogPath"
    "player_flight_marks=$capturedFlightMarksPath"
    "player_mark_count=$playerMarkCount"
    "gpu_profile=$([bool]$GpuProfile)"
    "script_profiling=$([bool]$ScriptProfiling)"
) | Set-Content -Path $metadataPath -Encoding UTF8
Copy-Item -LiteralPath $metadataPath -Destination $activeSessionPath -Force

Get-Content -LiteralPath $metadataPath
