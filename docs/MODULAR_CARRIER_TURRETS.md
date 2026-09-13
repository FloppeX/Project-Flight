# Modular carrier turrets

Implemented 2026-09-08.

- `LandCarrier2.tscn` uses four empty `CarrierDefenseTurretPosition.tscn` hull platforms, retaining their authored transforms. Its five `TurretPosition 1` through `TurretPosition 5` island nodes are also build sites.
- `CarrierDefenseLoadout.gd` chooses two distinct sites at startup, uniformly shuffling all nine. Each gun independently draws from the five existing profiles (duplicates are allowed).
- Each `CarrierTurretBuildSite.gd` can `build_turret(caliber_mm)` once while occupied. A built site adds only `CarrierDefenseTurretAssembly.tscn`, not another platform. The hull scene uses its `TurretPosition` anchor; island sites use their own transform. Existing DefenseOps discovers these controllers normally.
- The new modular rig is shared by carrier and friendly-vehicle turrets. It hides the authored `barrel position` locator, retains its position and orientation without its marker-sizing scale, and converts its +Y forward direction to the barrels' +Z forward direction. Barrel pitch and turret yaw retain the existing aiming logic.
- `GunProfile.caliber_mm` selects the matching authored barrel through `TurretGunCatalog.gd`. Muzzle position comes from the imported mesh bounds. Weapon scenes with embedded aircraft gun visuals use the modular barrel/muzzle when mounted in this rig; aircraft mounts remain unchanged.
- Carrier checkpoint state includes site paths and calibers. Pending-load startup restores those choices instead of rerolling. Later constructed turrets and deliberately empty saved loadouts are preserved. Legacy saves lacking this section receive the new two-turret start.
- No construction UI, build costs, or build timer is included in this slice. Seven sites remain empty at a new-game start. The unused legacy `LandCarrier.tscn` and standalone legacy defense-turret scene remain available.

## Verification

Run `Tests/ModularCarrierTurretsSmoketest.gd` with Godot `--headless --path . --script`. It checks all five gun/barrel swaps on the actual friendly-vehicle controller, muzzle placement, pitch/yaw alignment, nine empty authored sites, two distinct starting turrets, pending-load and carrier save hooks, later construction, invalid/duplicate save rejection, and randomized site/caliber coverage.

`Tests/ModularTurretsRenderedProbe.gd` uses Forward+ to capture all five barrels plus a hull and island installation under `captures/modular_turrets/`. This is a static placement check, not a full live-combat acceptance test.

Also run `Tests/StartupCameraSequenceSmoketest.tscn` and `Tests/DefenseOpsSensorSmoketest.gd` for preview-system isolation and defense/sensor regressions. Headless main-menu testing currently reports material-null cleanup errors despite passing its assertions; ObjectDB shutdown warnings also remain in the test harness.
