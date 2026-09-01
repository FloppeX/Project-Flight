param(
    [double]$SampleIntervalSeconds = 1.0,
    [switch]$GpuProfile,
    [switch]$ScriptProfiling
)

$ErrorActionPreference = 'Stop'
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

$project = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$godot = 'C:\Godot\Godot_v4.6.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot executable not found: $godot"
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$started = Get-Date
$userDataDir = Join-Path $env:APPDATA 'Godot\app_userdata\Land Carrier'
$captureRoot = Join-Path $userDataDir 'perf_play_sessions'
$sessionDir = Join-Path $captureRoot $stamp
$userPerfDir = Join-Path $userDataDir 'perf_logs'
$userFlightLogPath = Join-Path $userDataDir 'airplane_aero_report.log'
$projectFlightLogPath = Join-Path $project 'airplane_aero_report.log'
$userHitchLogPath = Join-Path $userPerfDir 'hitch_events.csv'
New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
New-Item -ItemType Directory -Force -Path $userPerfDir | Out-Null

$stdoutPath = Join-Path $sessionDir 'godot_stdout.log'
$stderrPath = Join-Path $sessionDir 'godot_stderr.log'
$engineLogPath = Join-Path $sessionDir 'godot_engine.log'
$processCsvPath = Join-Path $sessionDir 'process_samples.csv'
$metadataPath = Join-Path $sessionDir 'session.txt'
$activeSessionPath = Join-Path $project 'captures\perf_play_sessions\active_session.txt'
$activeSessionParent = Split-Path -Parent $activeSessionPath
New-Item -ItemType Directory -Force -Path $activeSessionParent | Out-Null

$arguments = @(
    '--path', ('"{0}"' -f $project),
    '--print-fps',
    '--log-file', ('"{0}"' -f $engineLogPath)
)
if ($GpuProfile) {
	Write-Warning 'Godot --gpu-profile prints a report every rendered frame and can add substantial capture overhead. Use it only for a short GPU-specific run, not the normal hitch capture.'
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
    "hitch_events=$userHitchLogPath"
    'hitch_summary='
    'hitch_count=0'
    'severe_hitch_count=0'
    'performance_mark_count=0'
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
    $line = @(
        (Get-Date).ToString('o', $invariantCulture)
        $elapsed.ToString('F3', $invariantCulture)
        $sample.Id.ToString($invariantCulture)
        $cpu.ToString('F3', $invariantCulture)
        $deltaCpu.ToString('F3', $invariantCulture)
        $oneCorePercent.ToString('F1', $invariantCulture)
        ($sample.WorkingSet64 / 1MB).ToString('F1', $invariantCulture)
        ($sample.PrivateMemorySize64 / 1MB).ToString('F1', $invariantCulture)
        $sample.Threads.Count.ToString($invariantCulture)
        $sample.HandleCount.ToString($invariantCulture)
    ) -join ','
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

$capturedHitchPath = ''
$capturedHitchSummaryPath = ''
$hitchCount = 0
$severeHitchCount = 0
$performanceMarkCount = 0
if (Test-Path -LiteralPath $userHitchLogPath) {
    $hitchInfo = Get-Item -LiteralPath $userHitchLogPath
    if ($hitchInfo.LastWriteTime -ge $started.AddSeconds(-5)) {
        $capturedHitchPath = Join-Path $sessionDir 'hitch_events.csv'
        Copy-Item -LiteralPath $userHitchLogPath -Destination $capturedHitchPath -Force
        try {
            $hitchRows = @(Import-Csv -LiteralPath $capturedHitchPath)
            $automaticHitches = @($hitchRows | Where-Object { $_.event_type -in @('hitch', 'severe_hitch') })
            $severeHitches = @($hitchRows | Where-Object { $_.event_type -eq 'severe_hitch' })
            $performanceMarks = @($hitchRows | Where-Object { $_.event_type -eq 'player_mark' })
            $hitchCount = $automaticHitches.Count
            $severeHitchCount = $severeHitches.Count
            $performanceMarkCount = $performanceMarks.Count
            $capturedHitchSummaryPath = Join-Path $sessionDir 'hitch_summary.txt'
            $summaryLines = [System.Collections.Generic.List[string]]::new()
            $summaryLines.Add('performance_hitch_summary')
            $summaryLines.Add("session=$stamp")
            $summaryLines.Add("hitch_threshold_ms=33")
            $summaryLines.Add("hitch_count=$hitchCount")
            $summaryLines.Add("severe_hitch_count=$severeHitchCount")
            $summaryLines.Add("performance_mark_count=$performanceMarkCount")
            $summaryLines.Add('')
            $summaryLines.Add('worst_hitches:')
            foreach ($row in ($automaticHitches | Sort-Object { [double]::Parse([string]$_.wall_delta_ms, $invariantCulture) } -Descending | Select-Object -First 25)) {
                $scopeText = [string]$row.scope_top
                if ($scopeText.Length -gt 240) {
                    $scopeText = $scopeText.Substring(0, 240) + '...'
                }
                $summaryLines.Add(('  elapsed_s={0} wall_delta_ms={1} type={2} fps={3} process_ms={4} physics_ms={5} materializing={6} scopes={7}' -f `
                    $row.elapsed_s,
                    $row.wall_delta_ms,
                    $row.event_type,
                    $row.fps,
                    $row.process_ms,
                    $row.physics_ms,
                    $row.materializing_flights,
                    $scopeText))
            }
            if ($performanceMarkCount -gt 0) {
                $summaryLines.Add('')
                $summaryLines.Add('player_marks:')
                foreach ($row in $performanceMarks) {
                    $markElapsed = [double]::Parse([string]$row.elapsed_s, $invariantCulture)
                    $nearestHitch = $automaticHitches |
                        Sort-Object { [math]::Abs([double]::Parse([string]$_.elapsed_s, $invariantCulture) - $markElapsed) } |
                        Select-Object -First 1
                    if ($null -ne $nearestHitch) {
                        $offsetSeconds = [double]::Parse([string]$nearestHitch.elapsed_s, $invariantCulture) - $markElapsed
                        $summaryLines.Add(('  elapsed_s={0} wall_time={1} nearest_hitch_offset_s={2} nearest_hitch_ms={3} nearest_hitch_scopes={4}' -f `
                            $row.elapsed_s,
                            $row.wall_time,
                            $offsetSeconds.ToString('F3', $invariantCulture),
                            $nearestHitch.wall_delta_ms,
                            $nearestHitch.scope_top))
                    }
                    else {
                        $summaryLines.Add(('  elapsed_s={0} wall_time={1} nearest_hitch=none' -f `
                            $row.elapsed_s,
                            $row.wall_time))
                    }
                }
            }
            $summaryLines | Set-Content -LiteralPath $capturedHitchSummaryPath -Encoding UTF8
        }
        catch {
            Write-Warning "Could not summarize hitch events: $($_.Exception.Message)"
        }
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

$durationText = ($ended - $started).TotalSeconds.ToString('F3', $invariantCulture)

@(
    'status=complete'
    "started=$($started.ToString('o'))"
    "ended=$($ended.ToString('o'))"
    "duration_s=$durationText"
    "pid=$($process.Id)"
    "exit_code=$exitCode"
    "session_dir=$sessionDir"
    "stdout=$stdoutPath"
    "stderr=$stderrPath"
    "engine_log=$engineLogPath"
    "process_samples=$processCsvPath"
    "engine_metrics=$capturedMetricsPath"
    "performance_report=$capturedReportPath"
    "hitch_events=$capturedHitchPath"
    "hitch_summary=$capturedHitchSummaryPath"
    "hitch_count=$hitchCount"
    "severe_hitch_count=$severeHitchCount"
    "performance_mark_count=$performanceMarkCount"
    "player_flight_log=$capturedFlightLogPath"
    "player_flight_marks=$capturedFlightMarksPath"
    "player_mark_count=$playerMarkCount"
    "gpu_profile=$([bool]$GpuProfile)"
    "script_profiling=$([bool]$ScriptProfiling)"
) | Set-Content -Path $metadataPath -Encoding UTF8
Copy-Item -LiteralPath $metadataPath -Destination $activeSessionPath -Force

Get-Content -LiteralPath $metadataPath
