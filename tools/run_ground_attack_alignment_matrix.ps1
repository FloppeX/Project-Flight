param(
    [ValidatePattern('^[a-zA-Z0-9_]+$')][string]$RunTag = ('ground_alignment_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
    [ValidateRange(30, 600)][int]$DurationSeconds = 150,
    [ValidateRange(1, 4)][int]$ParallelRuns = 4,
    [string]$GodotPath = 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logRoot = Join-Path $env:APPDATA 'Godot\app_userdata\Land Carrier'
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable not found' }
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$queue = [System.Collections.Generic.Queue[object]]::new()
# Every pair has the same start and real weapons; only alternate-axis selection differs.
foreach ($pose in @(
    @{Name='slow_cross'; Heading=90; Speed=85; Offset=1000},
    @{Name='fast_oblique'; Heading=225; Speed=125; Offset=-1000}
)) {
    foreach ($weapon in @(@{Name='guns'; Value='Guns'}, @{Name='bomb'; Value='Bomb'}, @{Name='rocket'; Value='Rocket Pod'})) {
        foreach ($mode in @('axis', 'direct')) {
            $stem = "$($RunTag)_$($pose.Name)_$($weapon.Name)_$mode"
            foreach ($suffix in @('.json', '.stdout.log', '.stderr.log')) {
                if (Test-Path -LiteralPath (Join-Path $logRoot ($stem + $suffix))) { throw "Refusing to overwrite $stem$suffix" }
            }
            $queue.Enqueue(@{Stem=$stem; Pose=$pose; Weapon=$weapon.Value; Mode=$mode})
        }
    }
}
$active = [System.Collections.Generic.List[object]]::new()
$completed = 0
$failed = 0
$lastProgress = Get-Date
while ($queue.Count -gt 0 -or $active.Count -gt 0) {
    while ($queue.Count -gt 0 -and $active.Count -lt $ParallelRuns) {
        $case = $queue.Dequeue()
        $axisFlag = if ($case.Mode -eq 'axis') { '--ground-alternate-axis' } else { '--ground-legacy-axis' }
        # Wall-clock-sensitive weapon timers make --fixed-fps unsuitable here.
        $arguments = '--headless --path "' + $projectPath + '" --max-fps 60 --quit-after 60000 --scene res://Tests/GroundAttackDiagnostic.tscn -- "--ground-weapon=' + $case.Weapon + '" --ground-duration=' + $DurationSeconds + ' --ground-reentry --ground-ridge --ground-heading=' + $case.Pose.Heading + ' --ground-speed=' + $case.Pose.Speed + ' --ground-offset=' + $case.Pose.Offset + ' ' + $axisFlag + ' --ground-output=user://' + $case.Stem + '.json'
        $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logRoot ($case.Stem + '.stdout.log')) -RedirectStandardError (Join-Path $logRoot ($case.Stem + '.stderr.log'))
        $active.Add(@{Case=$case; Process=$process; Started=Get-Date})
        Write-Output "START $($case.Stem) pid=$($process.Id)"
    }
    foreach ($run in @($active.ToArray())) {
        $run.Process.Refresh()
        if (-not $run.Process.HasExited) {
            if (((Get-Date) - $run.Started).TotalMinutes -gt 20) {
                throw "Test exceeded 20 wall minutes; inspect owned pid=$($run.Process.Id), run=$($run.Case.Stem)"
            }
            continue
        }
        $reportPath = Join-Path $logRoot ($run.Case.Stem + '.json')
        $report = if (Test-Path -LiteralPath $reportPath) { Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json } else { $null }
        if ($null -eq $report -or $report.status -ne 'COMPLETE' -or -not $report.hashes_verified) {
            $failed++
            Write-Output "INVALID $($run.Case.Stem) exit=$($run.Process.ExitCode)"
        } else {
            $completed++
            $damage = ($report.targets | Measure-Object damage -Sum).Sum
            Write-Output "COMPLETE $($run.Case.Stem) alive=$($report.aircraft_alive) releases=$($report.releases) damage=$([math]::Round($damage, 2)) first_damage=$([math]::Round($report.first_damage_s, 2))"
        }
        [void]$active.Remove($run)
    }
    if (((Get-Date) - $lastProgress).TotalSeconds -ge 30) {
        Write-Output "MATRIX_PROGRESS completed=$completed invalid=$failed running=$($active.Count) queued=$($queue.Count)"
        $lastProgress = Get-Date
    }
    if ($queue.Count -gt 0 -or $active.Count -gt 0) { Start-Sleep -Seconds 2 }
}
Write-Output "MATRIX_FINISHED completed=$completed invalid=$failed tag=$RunTag"
if ($failed -gt 0) { exit 1 }
