# Helicopter attack behavior: shoot-and-scoot first

## Intended doctrine

Two distinct attack styles, sharing mission/target selection but not a single
flight maneuver:

- **Shoot-and-scoot (first slice):** approach a useful firing line, settle the
  real weapon sight, fire, turn away before reaching the target, and relocate
  toward terrain cover. Do not require flying over the target to finish a pass.
- **Pop-up (now a first slice):** see [implementation and validation](HELICOPTER_POPUP_2026-09-11.md). Route behind verified cover, identify an exposed firing
  height with a clear weapon trajectory, ascend, fire, descend behind cover,
  then relocate before exposing again. Requires rotor clearance, vertical
  stopping room, cover-height/visibility checks and an escape if the position
  is compromised. Not implemented in this pass.

Keep the authored helicopters and player flight feel. No changes here to
HelicopterFlight, rotor forces, mass, drag, suspension, control authority, gun
accuracy, or RocketPod salvo timing. Aircraft 9 retains its independently
operated side guns; turret damage is included in the diagnostic total.

## Implemented first slice

- Return, hover, land and rescue explicitly cancel both new attack-state and
  legacy combat ownership, including a retained commanded target.
- Navigation altitude relaxation consumes elapsed navigation time rather than
  a single physics tick at each 0.35-second planning update. Route retry timers
  advance once per active physics update, not per route query.
- Live lineup/RUN guidance no longer blends back onto the old terrain route or
  requests new routes to a moving look-through point. Staging and escape retain
  normal terrain routing. Existing reactive flight protection remains active.
- The timed RUN begins within weapon range plus eight seconds of nominal
  closure, rather than as soon as distant lineup is possible. Ingress has a
  progress watchdog and overall timeout.
- Autonomous selection uses the shared GroundTargetPriority helper. Explicit
  orders continue to constrain the candidate list. Weapon preference remains
  rockets first when available; broader role-specific selection is future work.
- Turn-away range includes an approximate turn radius and response reserve,
  derived from actual horizontal speed and existing bank capability. Ingress
  also exits if it reaches that boundary without acquiring the firing line.
- New rocket salvos require room to complete their existing six-rocket cadence
  before turn-away. Already-started salvos retain the existing commitment rule.
- Escape selection samples six lateral/backward candidates on the near side of
  the target. It checks terrain clearance along each chord, rejects target
  overflight, and prefers endpoints with terrain blocking this target's LOS.
  Selection is repeated from the actual breakoff position. Without a usable
  new chord, normal routing retains the prior escape goal (or an away goal).
- A destroyed target no longer cancels an escape in progress. Escapes finish
  on arrival or a bounded timeout, instead of immediately selecting again just
  because the target is distant/dead.

### Limits

This is not full dynamic trajectory prediction. A clear sampled chord does not
prove the helicopter's curved turn is clear. Terrain cover is checked against
the selected target, not every hostile observer. Unknown terrain is not counted
as cover. The actual route can be longer/higher than the candidate chord;
"cover_candidate" is not a claim that the helicopter has reached concealment.
An exposed escape is permitted where no covered candidate exists.

The search is bounded (six candidates per escape query, including queries during
attack-axis selection), not a whole-map cover search. It does add height queries
at planning transitions; there is no fleet performance claim yet. Existing
blocking worker joins on route cancellation have not been redesigned.

## Diagnostic and validation

`Tests/HelicopterAttackDiagnostic.gd` uses the real aircraft, pilot, authored
weapons, normal aircraft damage, durable non-firing target, flat collidable
terrain and a synthetic baked navigation grid. Crucially, combat-hunt mode is
off and normal helicopter pathfinding is enabled. Starts are at (300,80,-2200)
with 35 m/s forward velocity and a running engine. It logs state occupancy,
damage, closest range, lowest altitude, control samples and source hashes.

Use normal physics pacing, not `--fixed-fps`: helicopter attack timers currently
use wall time in several places. A render-frame `--quit-after` is only an outer
guard, not the diagnostic duration. `--max-fps 60` prevents an uncapped render
loop from exhausting that guard before enough physics time elapses.

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --max-fps 60 --script res://Tests/HelicopterAttackDiagnostic.gd --quit-after 20000 -- --model=10 --label=example --duration=120
```

Initial cold-start diagnostics are invalid as attack baselines. The corrected
`ready_baseline` runs completed for 9 and 10: first damage 63.2/60.0 s and total
damage 545/387.4 at 90 s. Aircraft 11 hit the original render-frame cap without a
completion artifact; no outcome is inferred from that run. These uncapped
baselines are useful context, not tightly matched timing controls for later
capped runs.

Intermediate `scoot_v1` (120 s, before the final ingress boundary and actual
escape-direction guards):

| Aircraft | Alive | First damage | Total damage | Closest range | Lowest altitude |
| --- | --- | ---: | ---: | ---: | ---: |
| 9 | Yes | 60.00 s | 200.0 | 460.2 m | 42.3 m |
| 10 | Yes | 54.12 s | 840.4 | 321.1 m | 59.7 m |
| 11 | Yes | 113.47 s | 10.0 | 328.3 m | 43.4 m |

These demonstrate surviving attacks and turn-away in this flat arena, not
reliable combat or concealment. Aircraft 9's total includes side-gun damage.
Aircraft 11 remains a weak gun attacker. Final-source results are recorded below.

### Final-source check: scoot_v2

All three runs completed 90 seconds with normal terrain routing enabled and
matching recorded pilot hashes. No GDScript errors occurred in these runs.

| Aircraft | Alive | First damage | Total damage | Closest range | Lowest altitude |
| --- | --- | ---: | ---: | ---: | ---: |
| 9 | Yes | 57.38 s | 612.5 | 433.4 m | 64.5 m |
| 10 | Yes | 54.02 s | 585.7 | 451.6 m | 53.2 m |
| 11 | Yes | None | 0.0 | 328.3 m | 47.3 m |

Aircraft 9 and 10 reached first damage earlier than in the original completed
diagnostics, but different frame pacing and asynchronous route timing prevent
calling these controlled speedup measurements. Aircraft 11 did not damage the
target during the final 90-second run: the first slice is not a fleet combat
reliability sign-off. None overflew the target in these three final runs.

Artifacts are `user://heli_attack_scoot_v2_<9|10|11>.json`; earlier runs use
`ready_baseline` and `scoot_v1` labels. Never interpret an absent completion
artifact as a successful test.

Focused regression coverage:

- `HelicopterShootScootSmoketest.tscn`: exposed vs covered candidates, blocked
  escape chords, invalid/unknown terrain, target exclusion, live-guidance
  ownership, attack cancellation, range reserve and navigation timing.
- `HelicopterDeckTouchdownHandoffSmoketest.gd`: existing deck-settle handoff.
- `HelicopterTakeoffDoorsSmoketest.gd`: authored door closure at departure.
- `AirOpsRescueSmoketest.gd`: rescue assignment and parked departure.

Focused tests are not a full moving-carrier landing cycle. Headless runs do not
verify visual flight quality. Existing camera-interpolation and shutdown
ObjectDB/resource warnings occur in the diagnostic environment.

## Next iteration (at this checkpoint)

The subsequent [pop-up implementation](HELICOPTER_POPUP_2026-09-11.md) supersedes
the gun-only Aircraft 11 assumption and the deferred pop-up item below. The
varied-terrain and complete carrier-cycle validation items remain open.

1. Improve aircraft 11's body-gun convergence without changing its aerodynamics;
   separate pitch needed for travel from sight settling during the firing window.
2. Exercise moving targets and real terrain: measure exposure, route progress,
   closest target approach, escape safety, actual concealment and repeat-pass time.
3. Validate complete deploy/attack/return/land/stow cycles on a moving carrier,
   including return orders during every attack phase.
4. Tune short ingress/escape choices only after those results. Then implement
   pop-up attacks with a shared cover-position representation, not an unrelated
   second mission controller. Preserve the same player/AI salvo cadence.
