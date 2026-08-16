param(
    [int]$QuitAfterFrames = 2400,
    [int]$TimeoutSeconds = 180,
    [int]$Scenario = 1,
    [switch]$EnableFrameProfiler,
    [ValidateSet('Default', 'Enabled', 'Disabled')]
    [string]$TrackMarks = 'Default',
    [int]$TrackMarkMaxActive = 240,
    [double]$TrackMarkLifetimeSeconds = 30.0,
    [double]$TrackMarkSpawnSpacingMeters = 0.0,
    [double]$TrackMarkDebugIntervalSeconds = 5.0
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
$profilerOverridePath = Join-Path $scenarioDir 'frame_profiler_override.json'
$previousProfilerOverride = if (Test-Path $profilerOverridePath) { Get-Content -Raw -Path $profilerOverridePath } else { '' }
$carrierPerfOverridePath = Join-Path $scenarioDir 'land_carrier_perf_override.json'
$previousCarrierPerfOverride = if (Test-Path $carrierPerfOverridePath) { Get-Content -Raw -Path $carrierPerfOverridePath } else { '' }

$godotOut = Join-Path $outDir "godot_direct_$stamp.log"
$sampleCsv = Join-Path $outDir "process_samples_direct_$stamp.csv"
$summaryPath = Join-Path $outDir "summary_direct_$stamp.txt"

$sampler = $null
try {
    Set-Content -Path $scenarioPath -Value (('{{"scenario":{0}}}' -f $Scenario)) -Encoding UTF8
    if ($EnableFrameProfiler) {
        Set-Content -Path $profilerOverridePath -Value '{"enabled":true,"report_interval_s":1.0,"summary_interval_s":10.0,"spike_threshold_ms":8.0,"top_count":12}' -Encoding UTF8
    }
    if ($TrackMarks -ne 'Default') {
        $trackMarksEnabled = if ($TrackMarks -eq 'Enabled') { 'true' } else { 'false' }
        $carrierOverride = '{{"track_marks_enabled":{0},"track_mark_max_active":{1},"track_mark_lifetime_s":{2},"track_mark_spawn_spacing_m":{3},"track_mark_debug_log_interval_s":{4}}}' -f `
            $trackMarksEnabled,
            $TrackMarkMaxActive,
            ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.###}', $TrackMarkLifetimeSeconds)),
            ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.###}', $TrackMarkSpawnSpacingMeters)),
            ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.###}', $TrackMarkDebugIntervalSeconds))
        Set-Content -Path $carrierPerfOverridePath -Value $carrierOverride -Encoding UTF8
    }

    $sampler = Start-Job -ArgumentList $sampleCsv, $TimeoutSeconds -ScriptBlock {
        param($sampleCsvInner, $timeoutSecondsInner)
        'timestamp,elapsed_s,pid,process,cpu_s,delta_cpu_s,working_set_mb,private_mb,threads,top_processes' |
            Set-Content -Path $sampleCsvInner -Encoding UTF8
        $lastCpu = @{}
        $start = Get-Date
        while (((Get-Date) - $start).TotalSeconds -lt $timeoutSecondsInner) {
            Start-Sleep -Seconds 2
            $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
            $godotProc = Get-Process | Where-Object { $_.ProcessName -like 'Godot*' } | Sort-Object CPU -Descending | Select-Object -First 1
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
            } else {
                $line = '{0},{1},,,,,,,,"{2}"' -f (Get-Date).ToString('o'), $elapsed, $topText
            }
            Add-Content -Path $sampleCsvInner -Value $line -Encoding UTF8
        }
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $godot --path $project --quit-after $QuitAfterFrames --print-fps 2>&1 |
            ForEach-Object { "$_" } |
            Tee-Object -FilePath $godotOut
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}
finally {
    if ($sampler -ne $null) {
        Stop-Job $sampler -ErrorAction SilentlyContinue
        Receive-Job $sampler -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $sampler -Force -ErrorAction SilentlyContinue
    }
    if ($previousScenario -ne '') {
        Set-Content -Path $scenarioPath -Value $previousScenario -Encoding UTF8
    } else {
        Remove-Item -Path $scenarioPath -ErrorAction SilentlyContinue
    }
    if ($previousProfilerOverride -ne '') {
        Set-Content -Path $profilerOverridePath -Value $previousProfilerOverride -Encoding UTF8
    } else {
        Remove-Item -Path $profilerOverridePath -ErrorAction SilentlyContinue
    }
    if ($previousCarrierPerfOverride -ne '') {
        Set-Content -Path $carrierPerfOverridePath -Value $previousCarrierPerfOverride -Encoding UTF8
    } else {
        Remove-Item -Path $carrierPerfOverridePath -ErrorAction SilentlyContinue
    }
}

$samples = if (Test-Path $sampleCsv) { Import-Csv $sampleCsv } else { @() }
$godotSamples = $samples | Where-Object { $_.process -like 'Godot*' -and $_.delta_cpu_s }
$avgCore = if ($godotSamples.Count -gt 0) {
    [math]::Round(((($godotSamples | ForEach-Object { [double]$_.delta_cpu_s } | Measure-Object -Average).Average / 2.0) * 100), 1)
} else { 0 }
$maxWs = if ($godotSamples.Count -gt 0) {
    [math]::Round((($godotSamples | ForEach-Object { [double]$_.working_set_mb } | Measure-Object -Maximum).Maximum), 1)
} else { 0 }

$fpsTail = if (Test-Path $godotOut) {
    Select-String -Path $godotOut -Pattern 'Project FPS|FrameProfiler|LandCarrierPerfOverride|LandCarrierTrackMarks|HELI NAVIGATION|TUNER|SPAWN|ERROR|WARNING' -CaseSensitive:$false |
        Select-Object -Last 160 |
        ForEach-Object { $_.Line }
} else { @() }
$reportPath = Join-Path $project 'heli_navigation_report.log'
$reportTail = if (Test-Path $reportPath) { Get-Content $reportPath -Tail 100 } else { @() }

@(
    "exit_code=$exitCode",
    "stamp=$stamp",
    "avg_godot_cpu_one_core_percent=$avgCore",
    "max_godot_working_set_mb=$maxWs",
    "godot_output=$godotOut",
    "process_samples=$sampleCsv",
    "track_marks=$TrackMarks",
    "track_mark_max_active=$TrackMarkMaxActive",
    "track_mark_lifetime_s=$TrackMarkLifetimeSeconds",
    'track_mark_fade=gpu_smooth',
    '',
    '--- selected runtime output ---',
    $fpsTail,
    '',
    '--- heli_navigation_report tail ---',
    $reportTail
) | Set-Content -Path $summaryPath -Encoding UTF8

Get-Content $summaryPath -TotalCount 280
Write-Output "SUMMARY_PATH=$summaryPath"
Write-Output "GODOT_OUT=$godotOut"
Write-Output "SAMPLE_CSV=$sampleCsv"
if (Test-Path $scenarioPath) {
    Write-Output "SCENARIO_RESTORED=$(Get-Content -Raw -Path $scenarioPath)"
} else {
    Write-Output 'SCENARIO_RESTORED=<missing>'
}
if (Test-Path $profilerOverridePath) {
    Write-Output "PROFILER_OVERRIDE_RESTORED=$(Get-Content -Raw -Path $profilerOverridePath)"
} else {
    Write-Output 'PROFILER_OVERRIDE_RESTORED=<missing>'
}
