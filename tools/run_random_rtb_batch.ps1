param(
    [ValidateRange(1, 100)][int]$CasesPerModel = 10,
    [ValidateRange(1, 2147483647)][int]$Seed = 20260908,
    [ValidateRange(30, 1800)][int]$AttemptTimeoutSeconds = 900,
    [ValidateRange(1, 180)][int]$TimeoutMinutesPerModel = 90,
    [ValidateSet('Aircraft_1', 'Aircraft_2', 'Aircraft_5')][string]$FirstAircraft = 'Aircraft_1',
    [ValidateSet('', 'Aircraft_1', 'Aircraft_2', 'Aircraft_5')][string]$OnlyAircraft = '',
    [ValidateRange(0, 10000)][int]$StartCaseIndex = 0,
    [ValidatePattern('^$|^random_rtb_[0-9]{8}_[0-9]{6}_seed_[0-9]+$')][string]$ResumeSuiteId = "",
    [switch]$Visible,
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$suiteId = "random_rtb_" + (Get-Date -Format "yyyyMMdd_HHmmss") + "_seed_$Seed"
if ($ResumeSuiteId) { $suiteId = $ResumeSuiteId }
$suitePath = Join-Path $settingsDir ($suiteId + ".json")
$results = @()
$savedResults = @()
if ($ResumeSuiteId -and (Test-Path -LiteralPath $suitePath)) {
    $savedResults = @((Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json).results)
}
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
# Retain exact inputs: later tuning must not make this batch impossible to interpret.
$snapshotDir = Join-Path $settingsDir ($suiteId + "_inputs")
if (-not $ResumeSuiteId) { New-Item -ItemType Directory -Path $snapshotDir | Out-Null }
$inputPaths = @("AI/AIPilot.gd", "AI/LandingSight.gd", "Aircraft/aircraft.gd", "Aircraft/SimpleAero.gd",
    "Aircraft/AircraftPartDamageModel.gd", "Aircraft/AircraftWingDamageColliderFollower.gd",
    "AirOps/AirOpsManager.gd", "AirOps/FlightDirector.gd", "LandCarrier/CarrierDamageControl.gd",
    "Aircraft/Aircraft_1.tscn", "Aircraft/Aircraft_2.tscn", "Aircraft/Aircraft_5.tscn",
    "Scenario/LandingTestMode.gd", "LandCarrier/ArrestingCable.gd", "LandCarrier/arresting_cable.tscn",
    "addons/simplified_flightsim/aircraft_modules/LandingGear/LandingGear.gd",
    "LandCarrier/LandCarrier2.tscn", "LandCarrier/CarrierTargetCamera.gd",
    "LandCarrier/MonitorStation.gd", "LandCarrier/ComputerStation.gd",
    "LandCarrier/CarrierCollisionSetup.gd", "LandCarrier/FlightDeckManager.gd",
    "LandCarrier/LandCarrier.gd", "Main_Scene.tscn", "project.godot",
    "Environment/LowPolyTerrain.gd", "Environment/TerrainReference.gd",
    "Scenario/ScenarioManager.gd", "Scenario/CarrierCombatTestMode.gd",
    "Scenario/GoAroundTestObserver.gd",
    "addons/simplified_flightsim/aircraft_modules/Flaps/flaps.gd")
foreach ($path in $inputPaths) {
    if ($ResumeSuiteId) {
        $savedPath = Join-Path $snapshotDir (Split-Path $path -Leaf)
        if ((Get-FileHash -LiteralPath (Join-Path $projectPath $path)).Hash -ne
            (Get-FileHash -LiteralPath $savedPath).Hash) { throw "Input changed since batch start: $path" }
    } else {
        Copy-Item -LiteralPath (Join-Path $projectPath $path) -Destination $snapshotDir
    }
}
# Include imported carrier geometry without duplicating large binary assets.
$manifestPath = Join-Path $snapshotDir "input_hashes.json"
if ($ResumeSuiteId) {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "This older batch has no world-input manifest; start a fresh batch."
    }
    $inputManifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
} else {
    $inputManifest = @(foreach ($path in ($inputPaths + @("Models/LandCarrier/Land carrier 4.glb"))) {
        [ordered]@{ path=$path; sha256=(Get-FileHash -LiteralPath (Join-Path $projectPath $path)).Hash }
    })
    $inputManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}
function Assert-StableInputs {
    foreach ($inputFile in $inputManifest) {
        if ((Get-FileHash -LiteralPath (Join-Path $projectPath $inputFile.path)).Hash -ne $inputFile.sha256) {
            throw "Batch inputs changed; do not pool this run as controlled evidence: $($inputFile.path)"
        }
    }
}
$models = @($FirstAircraft) + @(@("Aircraft_1", "Aircraft_2", "Aircraft_5") | Where-Object { $_ -ne $FirstAircraft })
if ($OnlyAircraft) { $models = @($OnlyAircraft) }
foreach ($model in $models) {
    Assert-StableInputs
    $prefix = Join-Path $settingsDir ($suiteId + "_" + $model.ToLowerInvariant())
    $stdoutPath = $prefix + ".stdout.log"
    $stderrPath = $prefix + ".stderr.log"
    $reportPath = $prefix + ".report.log"
    $displayArguments = if ($Visible) {
        @('--windowed', '--resolution', '1280x800', '--position', '60,50', '--max-fps', '60')
    } else { @('--headless', '--fixed-fps', '60') }
    $arguments = $displayArguments + @("--path", ('"' + $projectPath + '"'),
        "--scene", "res://Main_Scene.tscn", "--",
        "--test-scenario=5", "--test-seed=$Seed", "--landing-random-rtb",
        "--landing-rtb-seed=$Seed", "--landing-aircraft-model=$model",
        "--landing-matrix-start-case=$StartCaseIndex",
        "--landing-attempt-limit=$CasesPerModel", "--landing-attempt-timeout=$AttemptTimeoutSeconds")
    if ($Visible) { $arguments += '--landing-visible-observer' }
    $processExitCode = $null
    if ($ResumeSuiteId -and (Test-Path -LiteralPath $stdoutPath)) {
        Write-Host "RESUME preserved $model report: $stdoutPath"
        $savedModel = $savedResults | Where-Object aircraft_model -eq $model | Select-Object -Last 1
        if ($null -ne $savedModel) { $processExitCode = $savedModel.process_exit_code }
    } else {
        Write-Host "START $model cases=$CasesPerModel seed=$Seed stdout=$stdoutPath"
        $windowStyle = if ($Visible) { 'Normal' } else { 'Hidden' }
        $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle $windowStyle `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
        $deadline = (Get-Date).AddMinutes($TimeoutMinutesPerModel)
        while (-not $process.WaitForExit(1000)) {
            if ((Get-Date) -gt $deadline) {
                Stop-Process -Id $process.Id -Force
                throw "Batch infrastructure timeout for $model; partial logs at $stdoutPath"
            }
        }
        $processExitCode = $process.ExitCode
    }
    # Parse this process's own stdout; shared live report could belong to another run.
    Copy-Item -LiteralPath $stdoutPath -Destination $reportPath
    $resultLine = Get-Content -LiteralPath $stdoutPath | Where-Object { $_ -match "RTB_RESULT json=" } | Select-Object -Last 1
    if ($null -eq $resultLine -or $resultLine -notmatch "RTB_RESULT json=(.+)$") {
        throw "$model did not complete (exit=$processExitCode); inspect $stderrPath and $stdoutPath. Partial logs are never overwritten on resume."
    }
    $result = $Matches[1] | ConvertFrom-Json
    if ($result.attempts -ne $CasesPerModel -or $result.seed -ne $Seed -or $result.aircraft_model -ne $model -or
        $result.status -ne "COMPLETE") { throw "Result configuration/count mismatch for $model" }
    $engineCrash = [bool](Select-String -LiteralPath $stderrPath -Pattern 'CrashHandlerException' -Quiet)
    $result | Add-Member -NotePropertyName process_exit_code -NotePropertyValue $processExitCode
    $result | Add-Member -NotePropertyName engine_crash_after_results -NotePropertyValue $engineCrash
    if ($engineCrash -or ($null -ne $processExitCode -and $processExitCode -ne 0)) {
        Write-Warning "$model wrote all results but exited abnormally; preserved as an infrastructure warning."
    }
    $result | Add-Member -NotePropertyName stdout_path -NotePropertyValue $stdoutPath
    $result | Add-Member -NotePropertyName stderr_path -NotePropertyValue $stderrPath
    $results += $result
    $status = if ($results.Count -eq $models.Count) { "VALIDATING" } else { "RUNNING" }
    [ordered]@{ suite_id=$suiteId; status=$status; seed=$Seed; cases_per_model=$CasesPerModel;
        visible=[bool]$Visible; realtime=[bool]$Visible;
        timeout_s=$AttemptTimeoutSeconds; start_case_index=$StartCaseIndex; models=$models; inputs=$snapshotDir; results=$results } |
        ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $suitePath -Encoding UTF8
    Write-Host ("COMPLETE {0}: {1}" -f $model, ($result.outcomes | ConvertTo-Json -Compress))
    Assert-StableInputs
}
# Check paired comparisons really used the same terrain-accepted starting geometry.
foreach ($result in $results) {
    for ($i = 0; $i -lt $CasesPerModel; $i++) {
        $a = $results[0].cases[$i].entry
        $b = $result.cases[$i].entry
        if ($b.case_index -ne ($StartCaseIndex + $i)) { throw "Unexpected case index for $($result.aircraft_model)" }
        foreach ($key in @("candidate_index", "distance_m", "radial_deg", "alt_m", "heading_offset_deg",
            "offset_x_m", "offset_z_m", "spawn_agl_m")) {
            if ([math]::Abs([double]$a.$key - [double]$b.$key) -gt 0.001) {
                throw "Matched-start mismatch $($result.aircraft_model) case=$i field=$key"
            }
        }
    }
}
$finalSuite = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
$finalSuite.status = "COMPLETE"
$finalSuite | Add-Member -NotePropertyName matched_starts_verified -NotePropertyValue $true
$finalSuite | Add-Member -NotePropertyName input_hashes_verified -NotePropertyValue $true
$finalSuite | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $suitePath -Encoding UTF8
Write-Host "BATCH COMPLETE: $suitePath"
