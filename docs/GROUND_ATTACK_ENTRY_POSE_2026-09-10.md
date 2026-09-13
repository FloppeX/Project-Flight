# Ground-attack entry-pose implementation

## Purpose

The v14 matrix found valid horizontal alignment but unusable attack entries:
some aircraft finished capture near 900 m, too high/close to aim before a safe
pull-out. The first implementation of the entry-pose plan addresses that setup
geometry without changing flight-model authority, weapon accuracy gates or
terrain/recovery protection. The alternate planner remains opt-in.

## Implemented

- A retained entry waypoint, entry range and target speed are planned alongside
  the staging waypoint and the validated egress. The speed target remains the
  existing 110 m/s direct-attack target; live airspeed also sizes the turn radius.
- Desired entry range combines the existing outer commit distance, a height-based
  acquisition angle (15 degrees for direct fire, 18 for bombs), and a six-second
  aiming allowance beyond the existing minimum weapon lane. This sizes the
  planned arrival; it does not authorize firing or suppress live safety checks.
- Turn distance and line-settling distance are separate. The latter uses the
  capture controller's lookahead scale and expected cross-track convergence,
  with at least three seconds of flight for settling.
- Search retains 16 headings, now at four heights instead of two (64 bounded
  candidates). Each candidate validates its actual planned entry and egress.
- Terrain-safe staging/transit altitude is separate from entry altitude. The
  staging-to-entry descent is checked for terrain clearance. Once joining, the
  normal unified 3D controller aims at the entry waypoint's position and height,
  while the retained line controller continues lateral capture.
- Live target translation and floating-origin shifts keep the entry waypoint
  and line origin consistent. Fresh approaches clear the stored pose.

The search remains event-driven after a remembered blocked approach. In the
small v15 arena, measured maxima were 3.44-6.27 ms for the gun/bomb cases and
19.23 ms for rockets. This is an occasional planning cost, not per-frame work,
but 19 ms can still affect a frame; production-terrain and fleet scheduling cost
has not been accepted. The per-frame change is constant-size waypoint handling.

## Focused physical tests: v15

All four previously failing cases completed 90 simulated seconds with their
aircraft alive, verified hashes, and a damaging first pass:

| Case | First commit | First damage | Damage by cutoff |
| --- | ---: | ---: | ---: |
| Slow crosswise guns | 56.27 s | 62.37 s | 160.00 |
| Fast oblique guns | 56.93 s | 62.10 s | 140.00 |
| Slow crosswise bombs | 59.30 s | 72.42 s | 348.17 |
| Slow crosswise rockets | 54.80 s | 59.80 s | 274.52 |

The gun entries now occur near 1,400 m at approximately 325 m altitude. In v14,
they occurred around 875/1,032 m at 545/573 m altitude and did not fire on their
first pass. The setup now achieves the intended usable entry, but takes longer
than production direct re-entry. This is not yet a throughput win.

Artifacts: `ground_v15_pose_{slow_guns,fast_guns,slow_bomb,slow_rocket}.json` in
normal Godot user data. A subsequent target-frame bookkeeping correction is
covered by the final-source v16 matrix; v15 is intermediate-source evidence.

## Validation and acceptance

The focused ground suite passes 71 checks, including height/speed-aware entry
range, settling distance, actual planned corridor validation for all weapons,
pose reset, target translation and floating-origin rebasing. Existing skill,
pursuit, evasion and bomb-separation regressions passed during the iteration.

The complete v16 matrix repeats all 12 cases for 150 seconds, with final source
held unchanged. All twelve are COMPLETE, alive at cutoff, with every recorded
hash rechecked against current source and no GDScript runtime/parse or
invalid-call/access errors in stderr. Every alternate case records actual axis
capture, not just an enabled setting.

**Damaging first passes: new alternate 6/6, previous alternate 2/6, direct 6/6.**
The four formerly empty first passes now release weapons and damage the target.
These are small paired samples, not statistical estimates of fleet reliability.

| Case | First damage: new alternate | First damage: direct | Damage: new alternate | Damage: direct |
| --- | ---: | ---: | ---: | ---: |
| Slow crosswise guns | 62.33 s | 29.63 s | 170.00 | 360.00 |
| Fast oblique guns | 62.10 s | 50.35 s | 120.00 | 120.00 |
| Slow crosswise bombs | 72.42 s | 33.83 s | 584.43 | 630.37 |
| Fast oblique bombs | 73.10 s | 57.12 s | 505.80 | 456.18 |
| Slow crosswise rockets | 59.83 s | 27.95 s | 489.86 | 170.00 |
| Fast oblique rockets | 62.70 s | 48.90 s | 178.78 | 431.52 |

The new slow rocket case makes two salvos by cutoff versus one for direct
re-entry. Conversely, slower gun acquisition reduces damage within the same
window. Weapon damage varies with wall-clock-sensitive timing and impact
geometry; do not pool damage across weapons or infer a universal accuracy gain.
These runs retain ordinary headless timing, not `--fixed-fps`.

Final matrix artifacts: `ground_v16_pose_<slow_cross|fast_oblique>_<guns|bomb|rocket>_<axis|direct>.json`.
Final recorded search-time maxima were 3.49-7.02 ms for guns/bombs and up to
21.47 ms for rockets under concurrent test load. Production planning cost still
requires attention before enabling this across a fleet.

### Full natural wave-off sequence

`ground_v16_cycle_bomb_axis.json` runs the original inbound scenario for 240 s,
without an injected remembered rejection. The first bomb releases at 20.22 s;
after a real terrain wave-off, the new entry pose produces a repeat release at
171.33 s. That bomb impacts at 176.57 s, 0.72 m from target centre. Total recorded
damage is 565.47, with two released bombs and three attack commits. The final
commit does not produce another release before cutoff; this is not a claim of
three completed damaging passes.

This thirteenth final run is also COMPLETE, alive, hash-verified against current
source and free of GDScript runtime/parse or invalid-call/access errors. Existing
engine camera/interpolation and shutdown-resource warnings remain. No owned
test process is left running; no scheduled task was created or resumed.

### Decision and next step

Keep `ground_attack_alternate_axis_enabled=false` in production. The missed-
first-pass failure is fixed in this matrix, but all six new alternate cases
still deal their first damage about 12-39 s later than direct re-entry. The
current conservative staging allowance is not yet an economical approach.

Next, retain the validated entry height/range and aim window, but replace the
mandatory distant staging-plane visit with a reachable, shorter join when the
current flight path already has room. Size an outbound extension only for the
missing turn/settling space. Test shorter joins first on these same failing-now-
recovered gun poses; do not regain speed by accepting the old high/late entries
or disabling pull-out protection. Then repeat the matrix and natural wave-off
case, and profile the event-driven search before enabling it generally.

Moving/firing targets, other airframes and production terrain remain outside
this acceptance sample. No aircraft physics, weapon behavior or production
default was changed in this entry-pose iteration.
