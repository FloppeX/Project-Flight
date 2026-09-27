# Project organization review — 2026-09-18

The gameplay code is already grouped by subsystem. Retain these boundaries rather
than moving scenes and scripts solely to make the root look smaller.

| Location | Role |
|---|---|
| `AI/`, `AirOps/`, `GroundOps/`, `Operations/` | Controllers and operational orders |
| `Aircraft/`, `GroundVehicle/`, `LandCarrier/`, `Enemies/` | Vehicle and actor scenes/scripts |
| `Models/`, `Images/`, `Audio/`, `Materials/`, `Shaders/` | Authored and imported assets |
| `Tests/` | Focused regression tests and probes |
| `tools/` | Authoring, profiling and maintenance tools; also older test entry points |
| `docs/` | Guides, designs and current engineering evidence |
| `docs/plans/` | Proposals, explicitly distinct from implemented behavior |
| `Archive/` | Historical reports and retired maintenance tools; Godot ignores this folder |
| `logs/`, `captures/`, `run_archives/` | Local logs, captured media and diagnostic run bundles |

## Files that look obsolete but are still referenced

- `LandCarrier/LandCarrier.tscn`: used by `CarrierMarkingSmoketest` and
  `RecordingTakePreview`; do not archive based on the production scene alone.
- `LandCarrier/CarrierDefenseTurret.tscn`: used by `TechnicalIndexCatalog`, sensor
  and gunnery tests, and the older carrier scene.
- `LandCarrier/TractorBot.gd`: `FlightDeckManager` still performs a `TractorBot`
  type check. Its scene/script pair stays together pending deliberate retirement.
- Aircraft 12's source model is now `Models/Aircraft_12/aircraft_12.glb` (formerly
  root `aircraft 13.glb`). Aircraft 10 similarly lives under `Models/Aircraft_10/`.
- Root champion JSON files: several are tuner output paths or seed inputs.
  Retain the set until their read/write paths are migrated together.
- Pilot names and callsigns now live in `Data/Pilots/`; PilotRoster and
  CarrierManager read from the new paths. The data contents are unchanged.
- `Models/Characters/archive/`: already has its own `.gdignore` and explanation;
  keeping this asset history alongside its source family is reasonable.

## Remaining organizational inconsistencies

Tests are split between `Tests/` and `tools/`. Consolidating them would require
updating scene/script paths, UIDs where applicable, and documented commands; this
review leaves working entry points intact. Dated reports alone are not evidence
of deprecation, so recent September diagnostics remain in `docs/`.

The main README remains the current status source. The changelog remains at its
established path as the historical index. The archive manifest records this pass's
moves. Reference searches are useful evidence, but cannot prove the absence of
external scripts, saved resource paths or dynamically constructed references.

## Model consolidation

Eleven model files were moved under `Models/` with their import settings and UIDs
preserved. Scene references were updated. Imported root names were pinned to
their previous values so filename changes do not rename scene hierarchies.

| Previous location | Current location |
|---|---|
| `aircraft 13.glb` | `Models/Aircraft_12/aircraft_12.glb` |
| `Aircraft/aircraft 10.glb` | `Models/Aircraft_10/aircraft_10.glb` |
| `Aircraft/Visuals/Parachute.glb` | `Models/AircraftShared/parachute.glb` |
| `Aircraft/Visuals/ejection_seat.glb` | `Models/AircraftShared/ejection_seat.glb` |
| `LandCarrier/monitor station.glb` | `Models/LandCarrier/monitor_station.glb` |
| `Weapons/RocketPod/rocket pod.glb` | `Models/Weapons/rocket_pod.glb` |
| `Weapons/Hardpoint.glb` | `Models/Weapons/hardpoint.glb` |
| `Weapons/bomb.glb` | `Models/Weapons/bomb.glb` |
| `Weapons/bomb rack.glb` | `Models/Weapons/bomb_rack.glb` |
| `Projectiles/Rocket/rocket.glb` | `Models/Weapons/rocket.glb` |
| `Projectiles/AG Missile/missile.glb` | `Models/Weapons/missile.glb` |

Removed `Aircraft/cactus.glb` and `Aircraft/Visuals/ejection seat.glb`, including
their import sidecars. Their bytes and import parameters matched the retained
vegetation cactus and underscore-named ejection-seat model respectively; no
references to the redundant paths or UIDs were found in the searched resources.
Sounds remain under `Audio/`; gameplay scenes remain alongside subsystem code.

Validation: Godot reimport completed without reported import errors. All eleven
moved models retained their node names, hierarchy, transforms, mesh bounds and
surface counts; source-file hashes were unchanged. ParachuteSequenceSmoketest
passed. Sixteen of seventeen affected scenes loaded and instantiated off-tree.
That pass exposed two conflicting scene headers in
`Projectiles/AG Missile/ag_missile.tscn`. The follow-up repair makes it a thin
inherited compatibility scene for `ag_missile_projectile.tscn`; the holder chooses
the canonical projectile first. A focused test checks matching physics/damage
properties, child transforms and default scene selection. These checks do not
establish rendered appearance or full gameplay behavior.

## Resource validation command

Run `./tools/validate_scene_resources.ps1` from PowerShell (optional `-Godot`
executable override). It loads gameplay scenes and dependencies without running
scene `_ready` methods; project autoloads still initialize. It skips `.gdignore`
directories and excludes tests, tools, addons and captures from the default scan.
Use `-SceneRoot res://Tests,res://tools` to check those separately, or
`-SceneRoot res://Aircraft` to narrow the scan. Output is saved to
`logs/scene_resource_check.log`. Missing directories, no scenes, load failures,
or logged engine/script errors produce a nonzero exit code. Warnings alone do
not fail the check. This checks resource loading, not gameplay correctness.
