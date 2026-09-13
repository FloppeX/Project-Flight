param(
    [string]$SourceBlend = 'D:\3D printing files\Officer female - coffee mug.blend',
    [string]$Blender = 'C:\Program Files\Blender 5.1\blender.exe',
    [string]$Godot = 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
& $Blender --background $SourceBlend --python-exit-code 1 --python (Join-Path $PSScriptRoot 'export_officer_coffee.py')
if ($LASTEXITCODE -ne 0) { throw 'Coffee officer Blender export failed.' }
& $Godot --headless --path $projectRoot --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Coffee officer import failed.' }
& $Godot --headless --path $projectRoot --script res://tools/BuildOfficerCoffeeWalk.gd
if ($LASTEXITCODE -ne 0) { throw 'Coffee walk animation build failed.' }
& $Godot --headless --path $projectRoot --script res://tools/OfficerCoffeeAnimationSmoketest.gd
if ($LASTEXITCODE -ne 0) { throw 'Coffee officer animation validation failed.' }
