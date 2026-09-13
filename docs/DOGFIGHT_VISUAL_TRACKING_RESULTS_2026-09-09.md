# Dogfight visual tracking and energy: implementation and validation

Next iteration: [separation and capture follow-up](DOGFIGHT_SEPARATION_AND_CAPTURE_2026-09-09.md).

Implements a bounded first pass of `DOGFIGHT_ENERGY_AWARENESS_PLAN_2026-09-09.md`.
The pilots now use visual observations and finite memory, retain the improved gun
tracking controller, and have a committed tactical reset. The flight model was
measured, not retuned. Equal merges are still not reliably decisive.

## Production changes

- `AI/VisualContactTrack.gd` stores observed position, velocity, turn estimate and
  time, with growing uncertainty. Hidden motion is predicted for at most two
  seconds; memory expires after 5–10 seconds depending on pilot skill.
- `AIPilot` observes contacts at its existing perception cadence (approximately
  10 Hz), through range/night limits, a broad forward/side canopy-sector proxy,
  and a world collision ray. The current target plus at most three rotating
  candidates are checked per update: at most about 40 rays/second/pilot, not an
  all-pairs ray scan every physics tick. Actual CPU cost has not been profiled.
- Pursuit, target ranking, engagement/rejoin distance, defensive threat reactions,
  velocity/turn prediction and gun ballistics use that observed track. Nearby
  hidden contacts no longer bypass acquisition. Hidden contacts cannot start or
  continue a gun burst. Missing/expired tracks really clear the target and enter
  SEARCH rather than continuing to follow a live Node.
- Explicit intercept assignment/report events provide a separate 100 m / 5 m/s
  quantized controller cue. Reports never become visual firing solutions and
  expire after 60 seconds without a new report. They are not polled from the
  hidden aircraft each tick. Floating-origin shifts rebase both kinds of track.
- A small supervisor preserves useful forward pursuit, but commits to a five
  second extension after sustained poor geometry or prolonged visual loss,
  with an 18 second cooldown. It uses the aircraft's own velocity, can descend
  gently when sufficiently high, and does not reroll its direction every tick.
- During DOGFIGHT climb arrest, a late lateral-turn load floor cannot override
  the vertical controller's unloading request. This is deliberately restricted
  to combat control, not a change to player aerodynamics or landing control.

This is not a full perception simulation: canopy sectors are a generic proxy,
not authored cockpit/head geometry; skill currently changes retention rather
than scan scheduling. The supervisor uses coarse angle/progress timing, not yet
a learned maneuver selector or a full range/angle-trend tactical evaluator.
SEARCH reuses existing search/reacquisition behavior, not a new search-orbit
planner. Periodic carrier radar report integration remains a follow-up.

## Test infrastructure corrections

`Scenario/GunsOnlyDuel` now supplies its real flat ground through the normal
terrain-height contract, records the flight model, seed, physics rate and nine
input hashes, restores all 190 authored dogfight properties, and provides
`--duel-swap`, `--duel-same-model` and `--duel-tail-entry` variants.

It counts real projectile shots/outcomes separately from damage events. Component
damage is connected through the actual `PartDamageModel` node, so unchanged hull
health is no longer mistaken for no damage. At completion it freezes aircraft,
stops pilot/fire control, snapshots once and quits headlessly. Outstanding rounds
are reported as pending at cutoff; they are not counted as misses or allowed to
hit artificially frozen opponents. Zero-health bodies awaiting deferred death
signals no longer count as survivors in round scoring.

The old missing-ground diagnostic can still deliberately reproduce the missing
contract through `Tests/DogfightEnergyAudit.tscn` without `--audit-flat-ground`.
Production duels always have valid flat terrain knowledge.

## Energy measurements

`Tests/FixedWingEnergyBench.tscn` runs AI-off real-airframe response tests using
SimpleAero and player-equivalent pitch/roll controls. It applies a known steady
central thrust derived from the authored engines, with root module dispatch
disabled. Thus this is a transient aerodynamic response test, not a full engine
spool/offset-force test or a measured trimmed sustained-turn envelope.

Completed 72 cases:

- Aircraft 3 and 5: 60 and 120 Hz; initial speeds 60/100 m/s; requested banks
  0/45/70 degrees; engine off/full steady thrust; 12 seconds per case.
- Aircraft 1 and 2: the same 12-case matrix at 60 Hz.

All validated initial velocities; every engine-off case lost mechanical energy.
For Aircraft 3 and 5, drag never did positive work and lift work was effectively
zero. Worst absolute force-accounting residuals fell from about 3.5 equivalent
altitude metres at 60 Hz to about 1.6 at 120 Hz. These are finite-step measurements,
not a proof that every part of the force model is physically correct.

Example, Aircraft 5, 100 m/s initial speed, full steady thrust, over 12 seconds:

| Requested bank | Energy change, 60 Hz | Energy change, 120 Hz |
| --- | ---: | ---: |
| 0 degrees | +160.5 m | +160.4 m |
| 45 degrees | +77.5 m | +77.0 m |
| 70 degrees | -200.1 m | -201.0 m |

Energy here is `height + speed²/(2g)`, not just altitude. The hard turn costs
energy; a gentler powered turn can gain it. No global drag, thrust, mass, lift
curve or induced-drag coefficient was changed. The approximate induced-drag
polar is still a potential future improvement, but these tests do not justify
an indiscriminate drag increase. No GA was run.

The first bench attempt was rejected: unfreezing reset its requested velocity.
The corrected bench sets and verifies the physics-server velocity after unfreeze.
Do not use `contact_v1_20260909_163850_bench5_*` as physics evidence.

## Tracking and regression checks

Production Aircraft 5; unlimited-health controlled targets; 90 simulated seconds:

| Target | Shots | Hits | Within 1 degree and 900 m |
| --- | ---: | ---: | ---: |
| Straight tail chase | 673 | 671 | 89.03 s |
| Gentle left turn | 119 | 104 | 89.03 s |
| Crossing left | 106 | 103 | 19.00 s |
| Crossing right | 154 | 151 | 25.18 s |

The measured window excludes startup. Crossing cases first acquired precision
at 70.42 and 64.38 seconds respectively: eventual accuracy is good, acquisition
is still slow. These shorter runs are not directly comparable hit totals to the
previous 180-second runs. No claim is made that the hard-turn cases are solved.
All four tracking artifacts completed with their own input-hash checks passing.

- VisualContactSmoketest: 23 checks, zero failures, including a hidden position
  jump, rear/belly blindness, physical occlusion, reacquisition, active-burst
  cancellation, expired contact removal, coarse report expiry, origin rebasing,
  committed reset direction and climb-arrest load compatibility.
- DogfightPursuitSmoketest: 62 checks, zero failures. The fixture now waits for
  process-frame aircraft/module initialization rather than assuming two physics
  ticks initialize health and weapons.
- RecoveryRouteCapture, RecoveryTerrainEscape and GoAroundResponse: PASS.
- DeckFootprintWaveoff: PASS, 136 checks.

These are headless functional tests. Existing dummy-renderer/resource cleanup
warnings remain after some full-airframe tests; they are not clean shutdowns.
No fresh full carrier recovery batch or visual flight-quality assessment was
performed because flight physics and recovery control were not retuned.

## Duel results and follow-up

The final verification batch, seed 20260909, 60 Hz, all four runs COMPLETE with
input hashes unchanged and no script/parse errors:

| Start | Aircraft A hits/shots | Aircraft B hits/shots | Outcome |
| --- | ---: | ---: | --- |
| 5 vs 3, head-on | 4/5 | 9/10 | 240 s timeout; both component-damaged |
| 3 vs 5, head-on | 9/10 | 3/4 | 240 s timeout; both component-damaged |
| 5 vs 5, head-on | 2/3 | 3/3 | Both lost; draw at 53.6 s, apparent collision |
| 5 behind 3 by 500 m | 3/6 | 0/0 | Aircraft 5 wins at 5.9 s |

The earlier equal-aircraft acceptance run exposed the zero-health scoring bug:
its JSON labels team 2 the winner despite zero hull health at cutoff. That label
is not accepted as a surviving victory. The corrected verification run records
the mutual loss as a draw. It is not counted as a gun kill. The earlier tail-start
run scored 4/6 and ended at 12.9 s; the corrected scorer recognizes zero-health
defeat before waiting for the delayed destroyed signal.
The mixed duels end around 1.35–1.57 km altitude, not the old approximately 3 km
climb, but still overshoot the preferred ceiling and have long non-firing periods.

The next tuning targets are post-merge firing-position acquisition, deliberate
re-intercept after contact loss, and collision avoidance during very close pursuit.
Use independent seeds and starting advantages before claiming a win-rate change.
Seeding improves repeatability but is not a claim of bitwise determinism across
process/render scheduling. Keep aerodynamic retuning separate from these issues.

### Artifact locations

All run artifacts are under
`C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier/`:

- `contact_v2_20260909_164202_{tail,gentle}.json`
- `contact_cross_crossing_{left,right}_20260909_165202.json`
- `contact_v2_20260909_164202_bench5_{60,120}.json`
- `energy_bench3_{60,120}_20260909_164302.json`
- `contact_bench_{1,2}_20260909_165202.json`
- `contact_acceptance_20260909_165048_{merge,swap,equal,tail}.log[.json]`
- `contact_verified_20260909_165454_{merge,swap,equal,tail}.log[.json]`
- `contact_recovery_*Smoketest.stdout.log` and matching stderr logs.

Reproduce a duel, for example:

```powershell
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 --quit-after 16000 res://Scenario/GunsOnlyDuel.tscn -- --duel-seed=20260909 --duel-log=user://visual_duel.log
```
