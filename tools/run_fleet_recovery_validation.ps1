param([int]$Seed = 20260908)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settingsDir = Join-Path $env:APPDATA 'Godot/app_userdata/Land Carrier'
$validationId = 'fleet_recovery_validation_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$statusPath = Join-Path $settingsDir ($validationId + '.json')
$status = [ordered]@{ id = $validationId; status = 'BATCH_RUNNING'; seed = $Seed }
function Save-Status {
    $status | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
function Assert-Inputs($manifest) {
    foreach ($item in $manifest) {
        if ((Get-FileHash -LiteralPath (Join-Path $projectPath $item.path)).Hash -ne $item.sha256) {
            throw "Validation input changed: $($item.path)"
        }
    }
}
Write-Host "VALIDATION STATUS: $statusPath"
Save-Status
try {
    # The batch snapshots shared flight/world inputs. Retain the two runner
    # scripts as well, so the queued cycle cannot silently change configuration.
    $runnerManifest = @(foreach ($path in @('tools/run_carrier_desert_recovery_test.ps1',
        'tools/run_random_rtb_batch.ps1', 'tools/run_fleet_recovery_validation.ps1')) {
        [ordered]@{ path = $path; sha256 = (Get-FileHash -LiteralPath (Join-Path $projectPath $path)).Hash }
    })
    $status.runner_inputs = $runnerManifest
    Save-Status
    & (Join-Path $PSScriptRoot 'run_random_rtb_batch.ps1') -CasesPerModel 10 -Seed $Seed `
        -AttemptTimeoutSeconds 900 -TimeoutMinutesPerModel 180 6>&1 | ForEach-Object {
            $message = [string]$_
            Write-Host $message
            if ($message -match '^BATCH COMPLETE: (.+)$') { $status.batch_suite = $Matches[1] }
        }
    if (-not $status.Contains('batch_suite')) { throw 'Batch did not report completion.' }
    $suite = Get-Content -LiteralPath $status.batch_suite -Raw | ConvertFrom-Json
    if ($suite.status -ne 'COMPLETE' -or -not $suite.input_hashes_verified -or -not $suite.matched_starts_verified) {
        throw 'Batch validation incomplete.'
    }
    $manifest = @(Get-Content -LiteralPath (Join-Path $suite.inputs 'input_hashes.json') -Raw | ConvertFrom-Json)
    Assert-Inputs ($manifest + $runnerManifest)
    $status.batch_outcomes = @($suite.results | Select-Object aircraft_model, outcomes)
    $status.status = 'FULL_CYCLE_RUNNING'
    Save-Status
    # A completed batch with aircraft losses is still evidence. Continue the
    # independent operational test; abort only for missing results/input drift.
    $shellPath = (Get-Process -Id $PID).Path
    & $shellPath -NoProfile -File (Join-Path $PSScriptRoot 'run_carrier_desert_recovery_test.ps1') `
        -ActiveAircraft 3 -TargetTraps 3 -ObserveThroughStow -StrictFinalHandoff `
        -Seed $Seed -TimeoutMinutes 90 2>&1 | ForEach-Object {
            $message = [string]$_
            Write-Host $message
            if ($message -match '^Report: (.+)$') { $status.cycle_report = $Matches[1] }
        }
    $status.cycle_runner_exit_code = $LASTEXITCODE
    Assert-Inputs ($manifest + $runnerManifest)
    if (-not $status.Contains('cycle_report')) { throw 'Full cycle produced no terminal report.' }
    $line = Get-Content -LiteralPath $status.cycle_report | Where-Object { $_ -match 'RUN_RESULT json=' } | Select-Object -Last 1
    if ($line -notmatch 'RUN_RESULT json=(.+)$') { throw 'Full cycle report has no RUN_RESULT.' }
    $result = $Matches[1] | ConvertFrom-Json
    if (-not $result.observe_through_stow) { throw 'Full cycle did not observe through stow.' }
    $status.cycle_result = $result
    $status.inputs_verified = $true
    $status.status = 'COMPLETE' # Completion means results exist, not every aircraft succeeded.
    Save-Status
    Write-Host "VALIDATION COMPLETE: $statusPath"
} catch {
    $status.status = 'INFRASTRUCTURE_REVIEW'
    $status.error = $_.Exception.Message
    Save-Status
    throw
}
