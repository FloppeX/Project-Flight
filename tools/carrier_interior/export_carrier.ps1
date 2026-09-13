param(
    [string]$BlendFile = 'D:\3D printing files\Land carrier - unified.blend',
    [string]$Blender = 'C:\Program Files\Blender 5.1\blender.exe',
    [string]$Godot = 'C:\Godot\Godot_v4.6.2-stable_win64.exe',
    [switch]$Validate
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach ($required in @($BlendFile, $Blender, $Godot)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing file: $required" }
}
$logDirectory = Join-Path $env:TEMP 'ProjectFlight-CarrierExport'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

function Run-ExportStage([string]$Executable, [string[]]$StageArguments, [string]$Log, [string]$SuccessMarker = '') {
    # Windows Start-Process passes a single command line to the application.
    $quotedArguments = foreach ($item in $StageArguments) {
        if ($item.Contains('"')) { throw 'Double quotes are not supported inside an argument.' }
        '"' + $item + '"'
    }
    $process = Start-Process -FilePath $Executable -ArgumentList ($quotedArguments -join ' ') `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput $Log -RedirectStandardError ($Log + '.errors')
    $output = [IO.File]::ReadAllText($Log) + [IO.File]::ReadAllText($Log + '.errors')
    if ($process.ExitCode -ne 0 -or ($SuccessMarker -and -not $output.Contains($SuccessMarker))) {
        throw "Export stage failed. See $Log and $Log.errors"
    }
}

Write-Host 'Exporting the complete saved Blender carrier...'
Run-ExportStage $Blender @('--background', $BlendFile, '--python', (Join-Path $PSScriptRoot 'export_unified.py')) (Join-Path $logDirectory 'blender.log') 'CARRIER_UNIFIED_EXPORT_OK'
Write-Host 'Importing into Godot...'
Run-ExportStage $Godot @('--headless', '--editor', '--path', $projectRoot, '--import', '--quit') (Join-Path $logDirectory 'import.log')
Write-Host 'Rebuilding the editor-visible carrier model...'
Run-ExportStage $Godot @('--headless', '--path', $projectRoot, '--script', 'res://tools/carrier_interior/build_model.gd') (Join-Path $logDirectory 'build.log') 'CARRIER_INTERIOR_MODEL_BUILT'
if ($Validate) {
    Run-ExportStage $Godot @('--headless', '--path', $projectRoot, '--script', 'res://tools/carrier_interior/smoke.gd', '--quit-after', '1000') (Join-Path $logDirectory 'smoke.log') 'CARRIER_INTERIOR_SMOKE PASS'
    Run-ExportStage $Godot @('--headless', '--path', $projectRoot, '--script', 'res://tools/carrier_interior/game_smoke.gd', '--quit-after', '1000') (Join-Path $logDirectory 'game.log') 'CARRIER_INTERIOR_GAME_SMOKE PASS'
}
Write-Host "Carrier updated. Logs: $logDirectory"
