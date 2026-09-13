param(
    [ValidateSet("Both", "Aircraft_1", "Aircraft_5")]
    [string]$AircraftModel = "Aircraft_5",
    [ValidateRange(1, 20)]
    [int]$Repeats = 1,
    [ValidateRange(0, 15)]
    [int]$StartCase = 0,
    [ValidateRange(0, 320)]
    [int]$AttemptLimit = 0,
    [ValidateRange(1, 120)]
    [int]$TimeoutMinutes = 30,
    [switch]$Visible,
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe"
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$suiteId = "landing_sight_matrix_" + (Get-Date -Format "yyyyMMdd_HHmmss")
$suitePath = Join-Path $settingsDir ($suiteId + ".json")
$models = if ($AircraftModel -eq "Both") { @("Aircraft_1", "Aircraft_5") } else { @($AircraftModel) }
$results = @()

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

foreach ($model in $models) {
    $modelSlug = $model.ToLowerInvariant()
    $stdoutPath = Join-Path $settingsDir ($suiteId + "_" + $modelSlug + ".stdout.log")
    $stderrPath = Join-Path $settingsDir ($suiteId + "_" + $modelSlug + ".stderr.log")
    $liveReportPath = Join-Path $settingsDir "landing_test_report.log"
    $reportPath = Join-Path $settingsDir ($suiteId + "_" + $modelSlug + ".report.log")
    $arguments = @(
        "--path", ('"' + $projectPath + '"'),
        "--scene", "res://Main_Scene.tscn",
        "--fixed-fps", "60",
        "--",
        "--test-scenario=5",
        "--landing-sight-matrix",
        "--landing-aircraft-model=$model",
        "--landing-matrix-repeats=$Repeats",
        "--landing-matrix-start-case=$StartCase"
    )
    if (-not $Visible) {
        $arguments = @("--headless") + $arguments
    }
    if ($AttemptLimit -gt 0) {
        $arguments += "--landing-attempt-limit=$AttemptLimit"
    }

    Write-Host "Running $model landing-sight matrix (repeats=$Repeats start_case=$StartCase attempt_limit=$AttemptLimit)"
    $windowStyle = if ($Visible) { "Normal" } else { "Hidden" }
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments `
        -WindowStyle $windowStyle -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath -PassThru
    $finished = $process.WaitForExit($TimeoutMinutes * 60 * 1000)
    if (-not $finished) {
        Stop-Process -Id $process.Id -Force
        throw "$model landing matrix timed out after $TimeoutMinutes minutes. Log: $stdoutPath"
    }
    if (Test-Path -LiteralPath $liveReportPath) {
        Copy-Item -LiteralPath $liveReportPath -Destination $reportPath -Force
    }
    if (-not (Test-Path -LiteralPath $reportPath)) {
        throw "$model landing matrix produced no report (exit $($process.ExitCode)). Log: $stdoutPath"
    }
    $resultLine = Get-Content -LiteralPath $reportPath |
        Where-Object { $_ -match "MATRIX_RESULT json=" } |
        Select-Object -Last 1
    if ($null -eq $resultLine -or $resultLine -notmatch "MATRIX_RESULT json=(.+)$") {
        throw "$model landing matrix produced no MATRIX_RESULT (exit $($process.ExitCode)). Report: $reportPath"
    }
    $result = $Matches[1] | ConvertFrom-Json
    $result | Add-Member -NotePropertyName report_path -NotePropertyValue $reportPath
    $result | Add-Member -NotePropertyName stdout_path -NotePropertyValue $stdoutPath
    $result | Add-Member -NotePropertyName stderr_path -NotePropertyValue $stderrPath
    $results += $result

    $caught = if ($null -ne $result.outcomes.CAUGHT) { [int]$result.outcomes.CAUGHT } else { 0 }
    $waveoffs = if ($null -ne $result.outcomes.'WAVE-OFF') { [int]$result.outcomes.'WAVE-OFF' } else { 0 }
    $bolters = if ($null -ne $result.outcomes.BOLTER) { [int]$result.outcomes.BOLTER } else { 0 }
    $crashes = if ($null -ne $result.outcomes.CRASH) { [int]$result.outcomes.CRASH } else { 0 }
    $timeouts = if ($null -ne $result.outcomes.TIMEOUT) { [int]$result.outcomes.TIMEOUT } else { 0 }
    Write-Host "$model complete: catches=$caught waveoffs=$waveoffs bolters=$bolters crashes=$crashes timeouts=$timeouts"
    foreach ($case in $result.cases) {
        Write-Host ("  {0,-18} {1,-8} d={2,4:0} lat={3,4:+0;-0;0} alt={4,3:0} v={5,2:0} sight_viable={6,5:0%} touchdown={7}@{8:0.0}m/s" -f `
            $case.label, $case.outcome, $case.behind_m, $case.lateral_m, $case.alt_m,
            $case.speed_mps, $case.sight_viable_fraction,
            $case.touchdown_class, $case.touchdown_descent_mps)
    }
    Write-Host "Report: $reportPath"
}

$suiteResult = [ordered]@{
    suite_id = $suiteId
    generated_at = (Get-Date).ToString("o")
    repeats = $Repeats
    start_case = $StartCase
    attempt_limit = $AttemptLimit
    results = $results
}
$suiteResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $suitePath -Encoding UTF8
Write-Host "Combined JSON: $suitePath"
