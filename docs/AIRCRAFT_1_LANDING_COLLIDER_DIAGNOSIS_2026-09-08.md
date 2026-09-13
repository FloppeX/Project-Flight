# Aircraft 1 landing explosions: diagnostic finding

## Confirmed bug

`Aircraft/aircraft.gd`, `_on_Aircraft_body_shape_entered`, passes the physics
`local_shape_index` directly to `shape_owner_get_owner`. Shape indices and shape
owner IDs are different identifiers. The required lookup is
`shape_owner_get_owner(shape_find_owner(local_shape_index))`, with suitable
invalid-index handling. `AircraftPartDamageModel._shape_node_for_local_index`
already uses the correct two-step mapping.

Aircraft 1's multi-panel `WingDamageColliderFollower` duplicates and reassigns
both wing shapes in `_ready`. On the current Godot build this moves those shapes
to the end of the shape-index array while their owner IDs remain unchanged.
The wheel dimensions can look perfectly reasonable in the editor: the failure
is in runtime contact classification.

| Actual Aircraft 1 contact | Physics shape index | Owner ID | Current erroneous classification |
| --- | ---: | ---: | --- |
| Right main gear | 5 | 7 | Horizontal stabilizer |
| Left main gear | 6 | 8 | Vertical stabilizer |
| Nose gear | 7 | 9 | Right main gear |
| Left wing | 8 | 2 | Left main gear |
| Right wing | 9 | 3 | Nose gear |

Both main wheels therefore enter `_handle_carrier_body_contact` instead of
`land`. The body-contact path destroys the aircraft at 28 m/s **total relative
speed**, rather than evaluating vertical touchdown speed. Conversely, wing
contacts can incorrectly be treated as safe wheel contacts.

## Controlled reproduction

Command:

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/AircraftLandingColliderDiagnostic.gd --quit-after 600
```

The probe instantiates the actual aircraft scenes, lets their normal setup run,
then calls the existing collision handler with the runtime index of the named
wheel and a stationary carrier body. Velocity is 45 m/s forward, 1 m/s down.
This is a contact-handler reproduction, not a complete physical landing run.

| Instance / contact | Exploded | Touchdown recorded |
| --- | --- | --- |
| Aircraft 1 / right main | Yes | No |
| Aircraft 1 / left main | Yes | No |
| Aircraft 1 / nose | No | Yes, non-damaging |
| Aircraft 5 / right main | No | Yes, non-damaging |
| Aircraft 1 / right main, multi-panel fitting disabled on diagnostic instance only | No | Yes, non-damaging |

The final counterfactual restores matching indices and owner IDs and removes
the reproduced explosion. Disabling wing fitting is **not** the proposed fix:
correct the contact lookup and retain the wing geometry behavior.

Run completed with `COLLIDER_DIAGNOSTIC_COMPLETE`, exit 0. Godot reported an
ObjectDB leak warning at shutdown; no script errors appeared.

## Initial investigation scope and next step (before fix)

No production source, collider geometry, suspension, damage thresholds, or AI
controls were changed for this investigation. The diagnostic script and this
report are the only intended additions.

Recommended next step: fix the shared collision lookup, add regression coverage
for main-wheel and actual body contacts after runtime shape replacement, then
run Aircraft 1 physical landing trials. This is a confirmed sufficient cause
of gentle-contact explosions; it does not establish that suspension or other
landing behavior will be fault-free after the correction.

## Implemented correction and regression verification

The follow-up fix changes the shared `Aircraft/aircraft.gd` handler to resolve
the shape index through `shape_find_owner` before retrieving the owner node.
Negative and out-of-range indices are ignored. This applies to every aircraft
using the base script, including enemy aircraft and helicopters. No geometry,
suspension, AI control settings, or damage thresholds were altered.

`Tests/AircraftCollisionShapeLookupSmoketest.gd` exercises all 15 scenes directly
referencing this base script: Aircraft 1-12, Aircraft 14, CompleteFighterJet,
and EnemyFighter. Each scene is tested as authored and after replacing its
active body-shape resources at runtime.

- Before the fix, the initial 14-model test reported 42 failed assertions,
  including Aircraft 1's authored main wheels. This confirms the test detects
  the original defect, rather than merely passing the new implementation.
- Final expanded test: **PASS**, 15 models, 30 cases, 264 gentle gear contacts,
  124 slow body contacts, zero failed assertions.
- Gear contacts are checked on carrier, runway and generic surfaces at
  45 m/s forward and 1 m/s down: touchdown signal, no crash signal, no health loss.
- All active non-gear shapes still take the body-contact path. Each case also
  checks a genuinely fatal fast body impact and a damaging vertical wheel impact.
- Invalid indices generate no contact events or engine lookup errors.
- Existing AircraftContactSignal, FixedWingPartDamageCollider,
  Aircraft1LaunchCollision, and CarrierLandingPermissiveness smoke tests pass.

The final expanded regression run had no script/parse errors. Existing legacy
propeller UID fallback and missing wing-node warnings appeared in some models;
ObjectDB shutdown leak warnings remain. An intermediate test iteration also
reported one resource still in use at shutdown; the final expanded run did not.

### Physical landing verification

`desert_recovery_20260908_073755_seed_20260908` completed a single-Aircraft_1
deploy/launch/return/catch/stop/stow cycle: **PASS**, health 100, damage 0.
The actual carrier touchdown was recorded at 53.2 m/s relative speed and
6.5 m/s descent: a hard but non-damaging gear landing, not a fatal body impact.
Caught at 322.4 simulation seconds, stopped at 329.8, stowed at 350.1.

The run uses normal aggressive press handoff, not a strict-gate pass or a
test-forced final handoff. Stopping/storage use the normal deck manager.
The full-scene log includes unrelated `ComputerStation._attach_tactical_screen_display`
startup add-child errors; these did not prevent completion and were not changed.

Reproduction:

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/AircraftCollisionShapeLookupSmoketest.gd
.\tools\run_carrier_desert_recovery_test.ps1 -ActiveAircraft 1 -AircraftModel Aircraft_1 -ObserveThroughStow -StrictFinalHandoff -Seed 20260908 -TimeoutMinutes 15
```

Full-cycle reports are under
`C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier`, named
`carrier_combat_test_<run ID>.log`, with `<run ID>.stdout.log` and `.stderr.log`.

### Three-aircraft stress run: remaining failures

`desert_recovery_20260908_074002_seed_20260909` used three Aircraft_1s sharing
the queue and a different seed. It completed at 1593.8 simulation seconds with
**FAIL: 0/3 caught or stored, all three eventually destroyed**. Do not interpret
the successful single-aircraft cycle as reliable AI recovery in all conditions.

- Aircraft 01 survived wheel touchdown at 55.7 m/s relative speed and 5.5 m/s
  descent, then entered missed approach. Subsequent 16.8/17.1 m/s crash signals
  and severe damage preceded destruction on terrain beside the carrier.
- Aircraft 02 was destroyed in a carrier contact at 48.8 m/s and 13.9 degrees
  of bank. A wheel-touchdown event at 1.1 m/s descent was also emitted in that
  contact sequence. The log does not record the local shape of the fatal
  contact, so its precise physical cause remains unconfirmed.
- Aircraft 03 survived multiple wheel touchdowns around 55 m/s but did not
  catch a cable. It later remained in RECOVERY_HOLD with queue position -1,
  slowed to about 33 m/s while descending, and eventually struck terrain.
  The holding/queue/energy failure is not resolved by this collision lookup fix.

Thus the controlled regression verifies removal of the erroneous wheel/body
identity mapping, and one full physical cycle succeeds undamaged. The broader
flight tests also identify remaining cable-capture, carrier-contact and
missed-approach/holding work; those were not retuned in this fix.

```powershell
.\tools\run_carrier_desert_recovery_test.ps1 -ActiveAircraft 3 -AircraftModel Aircraft_1 -ObserveThroughStow -StrictFinalHandoff -Seed 20260909 -TimeoutMinutes 15
```

Regression output copies are saved in the same user-data directory as
`aircraft_collision_lookup_before_20260908.log`,
`aircraft_collision_lookup_after_20260908.log`,
`aircraft_contact_signal_after_20260908.log`,
`aircraft_part_damage_after_20260908.log`,
`aircraft1_launch_after_20260908.log`, and
`carrier_landing_permissiveness_after_20260908.log`.
