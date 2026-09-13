param(
    [ValidateSet("Aircraft_1", "Aircraft_5")]
    [string]$AircraftModel = "Aircraft_5",
    [string]$GodotPath = "C:\Godot\Godot_v4.6.2-stable_win64_console.exe",
    [int]$RestartDelaySeconds = 5,
    [switch]$Visible
)

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$settingsDir = Join-Path $env:APPDATA "Godot\app_userdata\Land Carrier"

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

Write-Host "Landing GA overnight runner: $AircraftModel"
Write-Host "Project: $projectPath"
Write-Host "Display: $(if ($Visible) { 'visible window' } else { 'headless' })"
Write-Host "Press Ctrl+C to stop. GA state is saved after every aircraft."

while ($true) {
    $arguments = @(
        "--path", ('"' + $projectPath + '"'),
        "--scene", "res://Main_Scene.tscn",
        "--fixed-fps", "60",
        "--",
        "--test-scenario=5",
        "--landing-genetic-tuning",
        "--landing-aircraft-model=$AircraftModel"
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
