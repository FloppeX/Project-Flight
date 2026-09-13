param(
    [ValidatePattern('^$|^random_rtb_[0-9]{8}_[0-9]{6}_seed_20260908$')]
    [string]$FirstProbeSuiteId = '',
    [ValidatePattern('^$|^random_rtb_[0-9]{8}_[0-9]{6}_seed_20260908$')]
    [string]$SecondProbeSuiteId = '',
    [switch]$RunFleetBatch
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settingsDir = Join-Path $env:APPDATA 'Godot/app_userdata/Land Carrier'
$runner = Join-Path $PSScriptRoot 'run_random_rtb_batch.ps1'
$reportPath = Join-Path $settingsDir ('escape_regression_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
$probes = @(
    @{ model = 'Aircraft_1'; index = 6 },
    @{ model = 'Aircraft_2'; index = 9 },
    @{ model = 'Aircraft_5'; index = 9 }
)
$report = [ordered]@{ status = 'RUNNING'; probes = @(); fleet_requested = [bool]$RunFleetBatch }
Write-Host "REGRESSION REPORT: $reportPath"
function Save-Report {
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}
Save-Report
try {
    foreach ($probe in $probes) {
        $suitePath = ''
        $existingSuiteId = if ($probe.model -eq 'Aircraft_1') { $FirstProbeSuiteId }
            elseif ($probe.model -eq 'Aircraft_2') { $SecondProbeSuiteId } else { '' }
        if ($existingSuiteId) {
            $suitePath = Join-Path $settingsDir ($existingSuiteId + '.json')
            $deadline = (Get-Date).AddMinutes(32)
            # The first probe may already be running in the foreground tool session.
            do {
                $suite = $null
                if (Test-Path -LiteralPath $suitePath) {
                    try { $suite = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json }
                    catch { $suite = $null } # Runner is replacing its status JSON.
                }
                if ($null -ne $suite -and $suite.status -eq 'COMPLETE') { break }
                if ((Get-Date) -gt $deadline) { throw 'Existing probe did not complete within 32 minutes.' }
                Start-Sleep -Seconds 2
            } while ($true)
        } else {
            & $runner -OnlyAircraft $probe.model -StartCaseIndex $probe.index -CasesPerModel 1 `
                -Seed 20260908 -AttemptTimeoutSeconds 900 -TimeoutMinutesPerModel 30 6>&1 |
                ForEach-Object {
                    $message = [string]$_
                    Write-Host $message
                    if ($message -match '^BATCH COMPLETE: (.+)$') { $suitePath = $Matches[1] }
                }
            if (-not $suitePath) { throw "No completed suite reported for $($probe.model)." }
            $suite = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
        }
        if ($suite.status -ne 'COMPLETE' -or -not $suite.input_hashes_verified -or
            $suite.results.Count -ne 1 -or $suite.start_case_index -ne $probe.index -or
            $suite.results[0].aircraft_model -ne $probe.model -or $suite.cases_per_model -ne 1) {
            throw "Unexpected/incomplete probe suite: $suitePath"
        }
        # A supplied first probe must match the code used for subsequent probes.
        foreach ($inputFile in (Get-Content -LiteralPath (Join-Path $suite.inputs 'input_hashes.json') -Raw | ConvertFrom-Json)) {
            if ((Get-FileHash -LiteralPath (Join-Path $projectPath $inputFile.path)).Hash -ne $inputFile.sha256) {
                throw "Probe inputs changed: $($inputFile.path)"
            }
        }
        $result = $suite.results[0]
        $report.probes += [ordered]@{ model = $probe.model; case_index = $probe.index;
            suite = $suitePath; outcomes = $result.outcomes; engine_crash_after_results = $result.engine_crash_after_results }
        Save-Report
    }
    $report.status = 'PROBES_COMPLETE'
    Save-Report
    if (@($report.probes | Where-Object { [int]$_.outcomes.CAUGHT -ne 1 }).Count -gt 0) {
        throw 'At least one probe did not finish with a stopped catch. Full fleet run deferred for diagnosis.'
    }
    if ($RunFleetBatch) {
        Write-Host 'All three probes caught; starting matched 30-case fleet regression.'
        $report.status = 'FLEET_RUNNING'
        Save-Report
        & $runner -CasesPerModel 10 -Seed 20260908 -AttemptTimeoutSeconds 900 -TimeoutMinutesPerModel 180 6>&1 |
            ForEach-Object {
                $message = [string]$_
                Write-Host $message
                if ($message -match '^BATCH COMPLETE: (.+)$') { $report.fleet_suite = $Matches[1] }
            }
        if (-not $report.Contains('fleet_suite')) { throw 'Fleet runner did not report completion.' }
    }
    $report.status = 'COMPLETE'
    Save-Report
    Write-Host "REGRESSION COMPLETE: $reportPath"
} catch {
    $report.status = 'NEEDS_REVIEW'
    $report.error = $_.Exception.Message
    Save-Report
    throw
}
