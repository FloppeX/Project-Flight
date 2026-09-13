# Rocket salvo aim signal: preserve the shared burst

## User constraint

Player and AI use the same RocketPod salvo. The pilot must hold aim during it;
do not pause, selectively withhold, stretch or cancel individual shots to improve
accuracy. No per-shot AI guard was implemented. RocketPod's six-round default,
0.07-second interval, cooldown, ammunition use and scheduling code are unchanged.
Actual projectile physics and collisions are also unchanged in this slice.

## Investigation

Physics-frame attack telemetry exposed predicted misses jumping from roughly
10 m to 800-1,100 m during a burst. Both the old controller and an experimental
angular controller reacted to those false near-aircraft impacts.

The rocket impact predictor excluded the firing aircraft but raycast against
every other body, including already-fired rockets. Its forward simulation treated
those moving projectiles as stationary obstacles. A focused reproduction changed
the prediction from ground at z=1199.888 m to a rocket body at z=97.5 m.

Two angular-controller experiments were rejected and removed. In v22 neither
new-controller approach fired within 90 seconds; in v23 both fired but damage
was below their controls. These are not accepted aiming improvements. Their
physics-frame traces were useful in exposing the bad prediction signal.

## Accepted implementation

`Aircraft/aircraft.gd` now retries a rocket-prediction segment after excluding an
intersected `ProjectileNew` body. It checks the same segment again, so solid
obstacles behind a projectile are retained. At most 16 extra queries occur per
segment; there is no projectile-roster scan, and unobstructed segments still use
one query. Exhausting the retry budget retains the remaining obstruction.

The calculation is shared by the player sight and AI. This is not an AI-only
firing advantage. It does not claim to predict future projectile-projectile
collisions; those still happen in the real simulation.

The diagnostic-only `rocket_ccip_ignore_projectiles` property permits a paired
control via `--ground-legacy-rocket-clutter`. Normal behavior enables filtering.
The harness now logs physics-frame aim, inputs, angular rates and burst state,
plus whether a real impact body was another projectile.

## Final paired validation

Four normal-timing headless Aircraft 5 runs completed 90.02 simulation seconds
each, in approximately 190-195 wall seconds under concurrent load. Both poses
use the ridge arena and the existing opt-in re-entry planner. Source was frozen
during each batch; final reports verify their hashes and those hashes match
current source. All four survived, fired six rockets, left no pending projectile
and had no GDScript parse/runtime/invalid-call/access errors.

| Pose | Max predicted miss during burst: fixed / old | Mean actual miss: fixed / old | Damage: fixed / old |
| --- | ---: | ---: | ---: |
| Crosswise, 85 m/s | 24.2 / 1028.9 m | 20.62 / 16.83 m | 70.00 / 25.00 |
| Oblique, 125 m/s | 38.9 / 1093.3 m | 197.33 / 193.17 m | 174.40 / 299.10 |

Each oblique run had one actual projectile-projectile collision, included in
the mean rather than silently discarded. Neither crosswise run had one.
First damage was 27.88 / 27.90 s crosswise and 49.08 / 49.08 s oblique.
The corrected predictor removes the huge false signal; these results do NOT
establish better overall accuracy. Actual mean miss was slightly worse in both
pairs, and damage changed in opposite directions.

The new focused smoke test passes six checks: clear ground impact, projectile
clutter rejection, old-behavior reproduction, solid obstruction behind clutter,
unchanged collision layers, and safe cleanup. Ground-attack plan (104), pilot
skill (60), pursuit (80), evasion (62), bomb separation (9), go-around response,
recovery route capture and recovery terrain escape also pass. Existing engine
interpolation/camera, JSON non-finite optional-field and shutdown-resource
warnings remain; this is not a warning-free engine run.

Artifacts in normal Godot user data:

- `ground_v24_clutter_{slow|fast}_{new|old}.json` and their stdout/stderr logs.
- `ground_v24_*Smoketest.log` for the regression suite.
- Rejected experiments: `ground_v22_aim_*` and `ground_v23_aim_*` (historical
  source hashes; their controller code is no longer present).

RocketPod source SHA256 remains
`8C7A453C44F32DFEE32B285FA71E90CFF2113892084DC43457F16E30669FDDB5`.
All owned test processes exited. No automation was created or resumed.

## Remaining work

Retune aim only against the corrected signal, evaluating every projectile in the
unchanged salvo. Do not use damage alone: random dispersion, target-edge damage
and rocket-projectile collisions can obscure control quality. Keep misses,
angular motion, acquisition time, physical collision identity and survival.

Rocket-projectile collisions are a separate confirmed issue in the oblique
fixtures. Investigate release separation and collision attribution before
choosing a shared player/AI fix; do not silently alter the salvo scheduler.

These Aircraft 5 fixed-arena tests do not establish fleet or production-terrain
reliability. Shorter rocket approach joins and the alternate-axis planner retain
their existing disabled/opt-in status.
