param(
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64.exe",
    [int]$RestartDelaySeconds = 5,
    [switch]$Visible
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"
$scenarioPath = Join-Path $settingsDir "physical_test_scenario.json"

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

Write-Host "Landing GA overnight runner"
Write-Host "Project: $projectPath"
Write-Host "Display: $(if ($Visible) { 'visible window' } else { 'headless' })"
Write-Host "Press Ctrl+C to stop. GA state is saved after every aircraft."

while ($true) {
    # A clean game exit resets this setting to Normal Game, so restore scenario 5 before every launch.
    '{"scenario":5}' | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
    $arguments = @(
        "--path", ('"' + $projectPath + '"'),
        "--scene", "res://Main_Scene.tscn"
    )
    if (-not $Visible) {
        $arguments = @("--headless") + $arguments
    }
    # Godot's Windows GUI binary returns control to PowerShell immediately when invoked with `&`.
    # Start-Process -Wait prevents the watchdog from accidentally launching overlapping optimizers.
    $windowStyle = if ($Visible) { "Normal" } else { "Hidden" }
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle $windowStyle -Wait -PassThru
    $exitCode = $process.ExitCode
    Write-Warning "Godot exited with code $exitCode. Restarting in $RestartDelaySeconds seconds..."
    Start-Sleep -Seconds ([Math]::Max($RestartDelaySeconds, 1))
}
