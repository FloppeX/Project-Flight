# Helicopter rocket compatibility and pop-up attacks — 2026-09-11

## Scope

Aircraft 9, 10 and 11 now accept rocket pods on every existing hardpoint.
Gun options remain available. Aircraft 11 defaults to a rocket pod; 9 and 10
retain their mixed default loadouts. This does not add weapon stations, change
AirOps' utility/rescue role assignments, or replace saved/custom loadouts.

HelicopterFlight, authored rotor/airframe physics, projectile ballistics and
RocketPod salvo timing are unchanged. The usual weapon payload mass still applies.

## Implemented first slice

Rocket-equipped pilots can choose a nearby pop-up opportunity at target
selection or during ingress. Otherwise they keep using shoot-and-scoot.

1. **Approach:** use normal terrain navigation to a sheltered low station, then
   brake and capture that station using ordinary control inputs.
2. **Rise:** ascend toward a terrain-qualified firing height, with a bounded
   climb demand instead of the transit controller's urgency boost.
3. **Fire:** use the existing ballistic/CCIP and alignment release gates, fire
   one normal pod salvo, and keep aiming until that salvo finishes.
4. **Descend:** return to the low station and verify concealment before moving.
5. **Relocate:** move about 180 m laterally along a sheltered route. Remember the
   used station so the next attack does not simply reuse it.

This is not a physics-perfect stationary hover shot: fixed forward launchers
require body pitch, and body pitch also produces forward motion. The controller
accepts bounded movement while firing and recaptures the sheltered station.
Its aim controller accounts for the existing airframe leveling torque through
normal cyclic inputs; it does not move the aircraft or rotate weapons directly.

## Qualification and failure handling

- Local candidate search only: current position and lateral offsets up to 360 m.
  Candidate searches are limited to once per three seconds and skipped outside
  weapon range. No long orbit is added to manufacture a pop-up opportunity.
- A low station must conceal the aircraft's rotor-height envelope from the
  selected target and provide a clear local terrain footprint.
- Rise height is bounded to 160 m above the low station; the high point must have
  a clear terrain sightline and be inside effective rocket range.
- A physical sphere sweep checks the ascent column for obstacles.
- A sheltered, terrain-clear relocation chord must exist before commitment.
- Target movement beyond 60 m, target loss, and changed cover cause descent;
  a blocked column causes escape. Checks are throttled to 0.25 seconds.
- No solution in the eight-second firing window causes descent without firing.
  A salvo already running is allowed to finish on its normal timer.
- Every phase has a 45-second watchdog. Failure falls back to escape and a
  cooldown, rather than indefinite setup or an exposed hover.
- New hover/land/return/rescue orders cancel pop-up ownership through the
  existing attack cancellation path. Floating-origin shifts move all anchors.
- Local predicted terrain clearance and existing airborne-separation inputs
  remain in the station-keeping controller.

## Verification

`Tests/HelicopterPopupSmoketest.tscn` passes geometry, unknown-terrain rejection,
insufficient-rise rejection, relocation, floating-origin, real rocket/gun
mounts on all five stations, phase progression, normal-salvo completion,
target-loss descent, blocked-column escape, timeout, and command cancellation.

`Tests/ForwardGunHardpointSmoketest.gd` passes all 15 aircraft configurations,
including preservation of fixed-wing reserved-gun station restrictions.

The physical diagnostic uses real aircraft, controls, weapons and collidable
terrain, a durable target, normal navigation (not hunt mode), a warm engine,
and a baked navigation grid. A 110 m ridge lies between the helicopter starting
at 80 m altitude / 680 m range and the target. The runs are headless with normal
physics pacing, not accelerated fixed-FPS runs. JSON artifacts include source
hashes, positions, controls, attack/pop-up phases, volleys, damage and clearance.

Initial Aircraft 11 probe (`popup_v1`) survived but failed to fire. It exposed
two control issues: transit climb overshoot and nose-high settling against
airframe leveling. The corrected `popup_v2` Aircraft 11 run hit at 20.0 seconds,
dealt 103.0 damage, completed relocation at about 63 seconds and survived the
100-second observation. This is evidence for the first cycle, not a general
success-rate claim.

Final-source `popup_v3` results (one 85-second run per model):

| Aircraft | First damage | Total damage | First relocation complete | Minimum AGL | Closest target range | Alive |
|---|---:|---:|---:|---:|---:|---|
| 9 | 21.4 s | 210.5 | 69.0 s | 79.5 m | 560.5 m | Yes |
| 10 | 20.0 s | 146.3 | 62.5 s | 79.7 m | 594.6 m | Yes |
| 11 | 20.0 s | 103.0 | 63.0 s | 79.7 m | 595.1 m | Yes |

All three logs show one normal rocket volley, `salvo_complete` descent,
concealed relocation completion and a new pop-up setup from another position.
None overflew the target. Aircraft 9 also has independently operated side guns;
its total damage must not be read as rocket-only damage. All artifact statuses
are `COMPLETE` and pilot/aircraft-scene/flight-model SHA256 hashes matched the
files at final verification. The tested pilot hash is
`9d7706a83ef726fca9b3c9f6da90d2cebfcf507d3d8fd905a00b2193348146b0`.

The shoot-and-scoot regression and AirOps rescue smoketest also pass. These
checks do not constitute a mixed-aircraft simultaneous combat acceptance run.

### Reproduction

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . `
  --max-fps 60 --script res://Tests/HelicopterAttackDiagnostic.gd `
  --quit-after 16000 -- --model=11 --label=popup_check --duration=85 --popup-terrain
```

Artifacts: `user://heli_attack_<label>_<model>.json`. Require `status=COMPLETE`;
a killed or partial run is not a pass. The target intentionally cannot die.

## Limits and next tests

This is one synthetic ridge geometry, not validation across generated maps.
The planner reasons about terrain cover against the selected target, not all
nearby threats or building-based cover. Sampled terrain chords and a physical
ascent sweep are not a full swept-volume proof of the curved flight trajectory.
Nearby aircraft can displace a holding pilot. Existing minimum-AGL guards keep
the hide station relatively high (normally around 80 m on flat ground).

Next: vary ridge height/width, incoming position/speed, hardpoint loadout and
target motion; then observe windowed runs in generated terrain. Improve entry
and recovery reliability before broadening the doctrine or tuning per-airframe
gains. Headless results do not establish visual quality or player-flight feel.

The test scenes can emit existing camera interpolation and shutdown resource/
ObjectDB leak warnings. These are not being counted as clean-shutdown passes.
