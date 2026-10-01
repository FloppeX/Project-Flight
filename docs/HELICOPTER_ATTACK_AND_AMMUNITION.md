# Aircraft ammunition and attacks on helicopters

Aircraft Autocannon startup now reads `GunProfile.aircraft_ammo_capacity`.
The default is 200 rounds per gun (10 and 15 mm); 20 mm carries 150,
25 mm 100, and the 40 mm profile specifies 60. Payload mass follows the
actual ammunition count. Restoring a saved weapon count still preserves it;
new mounts/rearmed sorties receive the new capacity. Ground/carrier turret
ammunition is not changed.

The existing `40mm_autocannon_hardpoint.tscn` actually references a rocket
pod, so the profile's aircraft capacity is tested directly on Autocannon.
This change does not replace that authored asset or create missing mounts.

Fixed-wing pilots classify helicopter targets by aircraft type, not by a
temporary speed advantage. They retain attack speed, establish a ballistic
gun line, then extend along a latched outbound direction before reversing.
Extension requires elapsed time, traveled distance, target separation, and
adequate energy. Outbound spacing adds the turn diameter to the firing-run
distance, rather than using only the larger of the two. The shorter spacing
produced hits on the first pass but left subsequent passes still turning.
The pilot climbs gradually when it has speed to spare.
Collision avoidance, finite visual contact, and terrain recovery still apply.
Ordinary fighter pursuit retains its existing controller.

A helicopter pass uses a travel-dependent timeout rather than the legacy
four-second limit. During a pass, the gun aiming point may be below the
normal cruise-clearance height; sampled terrain margin and the physical
pullout check still constrain it. Ballistic refinement cannot redirect an
extension back at the target. Extension origins rebase with floating origin.

## Verification

- `WeaponPayloadMassSmoketest`: all 15 aircraft pass, including per-mount
  ammunition count, shot consumption, carried mass, and rearm mass.
- `HelicopterAttackPassSmoketest`: 20 checks pass, including production
  tactic selection, low-target aim, extension control, reset, and rebasing.
- `DogfightPursuitSmoketest`: 80 checks pass.
- `VisualContactSmoketest`: 29 checks pass. Its headless shutdown reports
  material/resource cleanup errors after the assertions.
- `HelicopterAttackPassDiagnostic`, production Aircraft 5 physics and finite
  ammunition, 180 simulated seconds with a durable helicopter body proxy:
  hovering at 300 m, 66 rounds/64 hits/three firing passes; crossing at
  20 m/s at 300 m, 42 rounds/40 hits/three firing passes. Both attackers survive. These runs
  use commanded intercepts with coarse controller reports every five seconds;
  gunfire still requires the pilot's own visual contact.

Acceptance traces: `logs/helicopter_attack_hover_spacing.json`,
`logs/helicopter_attack_moving_spacing.json`, and
`logs/helicopter_attack_integration.log`.

## Remaining limits

The 140 m altitude crossing-target case also survives three passes and
records eight rounds/five hits with the final spacing
(`logs/helicopter_attack_low_spacing.json`). Its firing opportunities are
more limited by terrain avoidance. The earlier shorter-spacing version
fired once without hitting (`logs/helicopter_attack_low_aim.json`); that
intermediate result is not acceptance evidence. Earlier exploratory traces include
a frozen proxy moved manually; the final diagnostic uses a moving physics
body with measured velocity instead.

These tests verify maneuver/state behavior and representative firing, not
every airframe, helicopter defense, terrain layout, or rendered combat feel.
Existing wall-time timers mean hit counts under fixed simulation steps are
representative rather than deterministic benchmarks. Several headless runs
report resource cleanup warnings at exit.
