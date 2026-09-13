# Dogfight energy, climbing and target awareness investigation

Implementation follow-up: [visual tracking and energy results](DOGFIGHT_VISUAL_TRACKING_RESULTS_2026-09-09.md).
The investigation below records the pre-change findings; the follow-up describes
the implemented first pass, validation and remaining limitations.

## Scope and outcome

Investigation and plan only: no production pilot gains, airframe tuning, thrust,
drag coefficients or tactical behavior were changed. Added an opt-in force-audit
signal to SimpleAero and a separate headless diagnostic scene. The signal does
not allocate a sample unless a diagnostic listener is connected.

There are confirmed perception bypasses and a defect in the previous duel arena.
The force audit does not support the claim that ordinary lift creates free
translational energy. Engines supply the observed energy gain, less substantial
drag losses, with a small residual still to quantify. The aerodynamic model is
nonphysical in some important ways, but increasing drag indiscriminately would
mix together several different problems.

## Confirmed findings

### Perception does not constrain current pursuit

In AI/AIPilot.gd:

- `_state_dogfight` only applies the awareness-drop test when simple pursuit is
  **disabled**. Simple pursuit is the current default.
- When a target leaves the sight cone, simple pursuit explicitly clears the
  lost-sight behavior and continues toward the known target.
- `_find_best_air_target` bypasses awareness acquisition inside the 1200 m
  knife-fight radius.
- Steering reads `combat_target.global_position` and `linear_velocity` directly.
  A scalar awareness value is not an observed, timestamped target track.
- The current arc/range awareness update does not itself ray-test cockpit or
  terrain visibility. It also classifies front/rear before above/below, which is
  only a rough proxy for what a pilot could actually see.
- Even the old loss path needs auditing: setting the local `target_invalid` flag
  does not itself clear a physically valid target if no replacement is found.
  Removing just the simple-pursuit bypass is not a complete fix.

In the terrain-corrected 90-second audit, Aircraft 5 spent 10.9 seconds actively
dogfighting with awareness below the loss threshold, and Aircraft 3 spent 16.1
seconds doing so. These are counts at 60 Hz, not just occasional snapshots.

### Current pursuit bypasses tactical reset logic

`_state_dogfight` fixes the tactic to NEUTRAL in simple pursuit rather than calling
`_compute_dogfight_energy_tactic`. The existing scissors timeout, extend/rebuild,
zoom and related maneuvers are therefore not the tactics governing these duels.
The recent speed-reserve/unload controller is active, but that is not a strategy
for escaping an unwinnable turning geometry. Turning the entire legacy tactical
system back on would also reinstate behavior that previously hurt gun pursuit;
prefer a small, explicit supervisor around the working pursuit controller.

### The previous duel's ground-height contract was incomplete

GunsOnlyDuel supplies a flat collision plane, but not a terrain height callable.
`_query_ground_height_provider` returns NaN without a terrain provider. The
preferred-ceiling calculation adds that value to 1400 m; its comparison then
cannot activate. Physical collision ground and AI terrain knowledge are different
interfaces.

Two diagnostic 90-second headless runs confirmed this. Only the second supplied
the pilot with a test-local height callable returning the actual flat ground, 0 m.

| Ground contract | Aircraft 5 altitude at 90 s | Aircraft 3 altitude at 90 s | Missing-ground samples per aircraft |
| --- | ---: | ---: | ---: |
| Original duel / no provider | 1687 m | 1601 m | 5280 / 5280 |
| Valid flat-ground provider | 1367 m | 1413 m | 0 / 5280 |

With valid ground, sampled peak altitudes were 1483 m and 1421 m; both pilots
commanded descent above the ceiling, and actual descents occurred. Both rounds
still ended in draws without damage. Ground validity substantially changes the
behavior, but does not fix the dogfight. These runs were not seed-controlled
paired experiments; the code path and logged validity establish the defect,
while the exact difference in trajectories should not be treated as a calibrated
effect size. The earlier four-minute climb to roughly 3 km is not clean evidence
of a failed production ceiling in a real terrain scene.

### Energy accounting: powered gain, not demonstrated free lift

Measure specific mechanical energy as `h + speed^2 / (2*g)`, in equivalent metres
of altitude. For each force, its contribution per second is `force dot velocity /
(mass*g)`. A powered turn can maintain or gain energy when engine power exceeds
losses; hard maneuvering should cost more energy, not necessarily force simultaneous
continuous loss of both speed and altitude. See the [FAA energy-management chapter](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/05_afh_ch4.pdf).

The corrected-ground run recorded actual forces submitted by SimpleAero at 60 Hz,
and engine thrust vectors from the runtime engine modules. Both aircraft used the
Advanced flight model. The table averages the 88 measured seconds after startup;
energy rates are equivalent altitude metres per second, not vertical speed.

| Aircraft | Engine contribution | Drag contribution | Alignment contribution | Observed total energy gain | Integrated force prediction |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5 | +36.65 m/s | -33.27 m/s | -2.06 m/s | +132.9 m | +116.6 m |
| 3 | +43.01 m/s | -38.14 m/s | -1.92 m/s | +268.9 m | +259.7 m |

- Drag and alignment had zero positive-work samples in both runs.
- Absolute lift contribution stayed below 0.000022 m/s. Its direction is projected
  perpendicular to airflow, as intended, so it does essentially no direct work.
- The residual is approximately 0.19 m/s for Aircraft 5 and 0.11 m/s for Aircraft 3.
  These are not exact energy-conservation proofs: finite-step integration, force
  sampling order and uninstrumented forces remain to check. A timestep-convergence
  and engine-off test should resolve this before declaring conservation complete.
- Sparse one-second high-load samples had negative net energy rate; there is not
  enough high-load dwell here to define sustained-turn performance. The proposed
  isolated turn matrix is still needed.

### Flight-model issues worth measuring

1. Induced drag currently uses `(load^2 - 1) * mass*g * strength` with a multiplier
   `clamp(speed/90, 0.7, 1.7)`. For a fixed lift requirement it gets smaller, not
   larger, as speed falls to the floor. The standard relation is proportional to
   lift squared divided by dynamic pressure and wing geometry. See [NASA's
   induced-drag relation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/induced-drag-coefficient/)
   and [drag equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/drag-equation/).
   This is an arcade approximation, not a physically scaled drag polar. Its
   one-G baseline is implicitly mixed into other drag rather than explicitly
   represented by the same relation.
2. Clean zero-AoA lift saturates at one aircraft weight above the aligned-level
   speed; it is not simply dynamic pressure times a lift coefficient. At negative
   AoA, the ordinary pre-stall curve only reduces that to 65% at its lower limit.
   The controller cannot assume it has a normal signed lift curve or unrestricted
   unloading. Any new polar must also update the controller's inverse lift model.
3. Alignment adds translational forces independently of the wing lift model. It
   is dissipative in these runs, not a hidden energy source, but changes force
   direction and turn geometry. Its contribution must be included when asking
   how much wing load is needed and what drag should accompany the turn.
4. Engine thrust is constant with airspeed at a fixed throttle in the current
   model. Combined with low-load recovery intervals, there can be substantial
   positive energy even while the aircraft repeatedly turn. That can be a tuning
   decision rather than a numerical bug.

## Controller hypothesis requiring a focused regression

The 3D follower supplies one bank/load/vertical-path request. Later stages clamp
bank and load separately, then the turn-response observer can raise
`flight_path_load_g` again via a maximum. This risks recreating upward acceleration
after the vertical loop deliberately asked to unload. The code already contains
roll-in compatibility logic, but the later load floor can override it.

In the corrected-ground trace there are descending-path commands accompanied by
large target loads. This identifies a useful probe, not proof every such sample
is wrong: a banked descending turn can legitimately need substantial load. Compare
the complete desired acceleration with that achieved, in world coordinates,
through roll-in, bank reversal, load saturation and climb arrest.

## Recommended implementation order

### 1. Make the test trustworthy and reproducible

- Supply the arena's flat height through its normal terrain contract; assert
  ground validity and record the selected Advanced/Simplified model explicitly.
- Seed runs; record physics tick rate, model/loadout and relevant input hashes.
- Record per-aircraft shots, projectile outcomes, damage source, sampled aim,
  target-track age, force work and measured acceleration. Current damage callbacks
  are not a reliable projectile-shot counter.
- Stop the round and snapshot once on completion; the current observer otherwise
  logs again while aircraft physics continues after the displayed result.

### 2. Establish the physics and vertical-control baseline

- AI-off engine-off straight glides and banked turns: 60 and 120 Hz. Mechanical
  energy must not grow systematically; verify residual shrinks with timestep.
- Scripted player-equivalent control inputs at several speeds, throttle settings
  and banks (0/30/45/60/70 degrees) on Aircraft 3 and 5, then 1 and 2. Measure actual
  load, sustained turn rate, stall, speed/height exchange and force work.
- Unit/probe tests for rolling into and out of steep turns while commanded level
  or descending. Resolve saturation as one achievable acceleration vector; do not
  independently restore a horizontal load floor that violates vertical intent.
- Only if the measured turn envelope warrants it, replace the induced-drag
  approximation with a bounded `q*S*(Cd0 + k*Cl^2)` model. Derive Cl from actual
  wing lift, make the clean reference trim explicit, and preserve reference cruise
  and approach performance. Do not merely multiply all drag or force a sink.

### 3. Give the AI an observed target track

- Separate world-truth identity from pilot knowledge: last observed position,
  velocity/turn estimate, observation timestamp, confidence and uncertainty.
- Update only when visible (canopy/body sectors, range, terrain/airframe occlusion,
  finite perception rate). Skill improves scan, retention and estimation, not
  access to live hidden transforms.
- On loss, follow a short prediction with growing uncertainty, then deliberately
  search. No live target position/velocity reads in steering, threat scoring or
  ballistics while hidden. Prohibit blind gun fire. Remove blanket proximity
  immunity while retaining plausible easier reacquisition at close range.
- Treat radar/controller reports as separate, delayed/coarse observations, not a
  permanent exact visual solution. Keep a debug truth channel for telemetry only.
- Bound sensing cost using existing range candidates and staggered perception
  updates; ray-test plausible contacts rather than every possible pair each tick.

### 4. Add a small tactical supervisor

- Preserve the improved precision pursuit once a useful gun solution is forming.
- Detect lack of progress using tracking time, angle/range trend, speed reserve
  and recent shot opportunities, not just elapsed time in DOGFIGHT.
- Choose a committed extension, lag/re-intercept or low-visibility search with
  explicit exit conditions and hysteresis. Avoid per-tick random waypoint changes.
- Permit purposeful descending turns when affordable and clear of terrain; do
  not make climb the universal way to reset a fight. Energy constraints come
  from the measured airframe envelope and target estimates, not omniscient truth.

### 5. Validate before optimization

- Re-run straight/crossing/gentle tracking so perception/tactics do not destroy
  established pursuit gains. Add occluded/behind-target reacquisition tests.
- Run seeded 3-vs-5 and same-model duels with swapped starting sides and different
  starting advantages. Report shots, hits, time to firing position, lost-contact
  recovery, energy trends, stalemates, collisions and crashes; do not require
  every round to end in a kill.
- If flight physics changes, repeat the Aircraft 1/2/5 landing and go-around
  regressions and full recovery samples. Shared flight changes affect the player.
- Aircraft-specific GA comes only after sensing and force/energy invariants pass;
  it should tune tactics and control gains, not learn to exploit free information
  or inconsistent forces.

## Diagnostic artifacts

`Tests/DogfightEnergyAudit.tscn` runs the current duel for 90 seconds with a force
listener. Pass `--audit-flat-ground` for the flat-ground provider and a unique
`--duel-log=user://name.log`; it writes `name.log.audit.json` at completion.

Completed artifacts under Godot's `Land Carrier` user-data directory:

- `energy_audit_20260909_161844_missing.log.audit.json`
- `energy_audit_20260909_161844_flat.log.audit.json`

Both completed, preserved all 190 dogfight properties per aircraft and passed
before/after hash checks for the five listed AI/aero/airframe inputs. The hashes
do not cover every dependency. No script errors were found; renderer/resource
cleanup errors remain after completion. These are isolated diagnostic runs, not
a full physics or combat acceptance suite.
