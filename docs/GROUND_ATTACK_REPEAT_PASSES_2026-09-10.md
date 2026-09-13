# Ground attack: repeat passes and release feedback

Follow-up to [the initial diagnostic](GROUND_ATTACK_DIAGNOSTIC_2026-09-09.md).
Aircraft 5, production controls/weapons, ordinary aircraft damage, durable
non-firing targets. Temperament remains deferred. No scheduled monitoring.

## Findings and changes

1. **Direct point pursuit did not close the return intercept reliably.** In the
   instrumented baseline the gun aircraft reduced its flight-path bearing error
   to about 26 degrees, but then approached so far off-axis that it needed another
   extension. It made only one attack entry in 180 simulated seconds.
   Direct interception now requests the target-bearing rotation rate plus the
   remaining flight-path error over a settling horizon, with measured-rate rollout
   feedback. Rear-hemisphere turn-side selection and extension safety remain.
2. **The correction must reach the final 3D acceleration solver.** Changing only
   the bank hint was insufficient: a previously computed point-pursuit lateral
   acceleration remained authoritative. The final version supplies the corrected
   lateral acceleration to the existing joint bank/load solver. It does not add
   an independent elevator controller, extra force or higher bank limit.
   The shared turn-response observer was already active; a missing observer gate
   was investigated but was not the underlying defect.
3. **Rocket bursts froze stick inputs, not aim direction.** A baseline burst
   progressively missed by 9, 11, 22, 28, 42 and 50 m while all six releases
   retained the same cached predicted impact. The pilot now continues normal
   CCIP/aim feedback throughout a burst. Existing burst-aware routine egress and
   critical terrain/structure protection retain their authority.
4. **Bomb proximity and last-chance overrides accepted known wide misses.** A
   physical usefulness check now applies to normal, proximity-forced and pull-up
   releases. For ordinary targets it uses the smaller of the skill tolerance and
   the bomb's configured blast radius. Carrier-specific large-target tolerance is
   retained. No-prediction and known 100 m misses do not become useful merely
   because it is time to pull out. The aircraft still pulls out; it can retry.
5. **Actual impact telemetry is now available.** Each bomb/rocket records release
   time/position, the pilot's cached prediction, target position, actual collision
   position and horizontal prediction error. Expiry/cleanup is distinguished from
   collision. The aircraft trace adds velocity, forward direction, requested bank,
   measured track rate and release miss. A cached prediction is intentionally not
   labelled a fresh per-projectile ballistic solution.

## Experiments

Logs are in `%APPDATA%/Godot/app_userdata/Land Carrier/`. Only COMPLETE runs with
`hashes_verified: true` count as completed physical tests. Settings and source
hashes are embedded in every diagnostic JSON.

- `ground_v5_*`: instrumented baseline. Guns: 180 s, one entry, 26 rounds,
  110 damage, alive. Bombs: 60 s, two bombs, 414.54 damage, alive. Their horizontal
  prediction errors were 0.09 and 7.71 m: this example does not support a grossly
  incorrect bomb gravity/drag model. Rockets: 60 s, six releases, 50 damage, alive.
- `ground_v6_*`: rejected intermediate handoff. Guns made three entries in 180 s,
  but only eight rounds/50 damage; bombs and rockets each made two entries in
  120 s without releasing. More entries alone were not accepted as success.
- `ground_v7_*`: corrected acceleration handoff, continuous rocket aiming and
  useful-bomb-release gate. Same 1000 m lateral-offset entry; 120 simulated
  seconds per flat/ridge trial. Final results are recorded below.

The harness uses simulation-duration completion and ordinary headless pacing,
not accelerated `--fixed-fps`. Wall-clock-dependent systems and initialization
timing still make runs differ; these are small diagnostic samples, not statistical
hit probabilities or a strict deterministic A/B benchmark. Rocket runs are
especially CPU-heavy. No performance optimization is claimed.

### Completed flat-ground results

| Weapon | Attack entries | Releases | Emplacement damage | Aircraft |
| --- | ---: | ---: | ---: | --- |
| Guns | 2 | 67 | 400.00 | Alive |
| Bombs | 2 | 3 | 878.02 | Alive |
| Rockets | 2 | 12 | 259.23 | Alive |

All three ran 120.02 simulated seconds with verified hashes. Wall durations were
120.27, 120.24 and 197.40 seconds respectively. The gun baseline needed 180 s and
still had only one firing pass/110 damage; this is the clearest repeat-pass gain.
All three bomb collisions caused damage: actual centre misses 19.58, 6.36 and
3.14 m, with prediction errors 0.66, 0.37 and 3.80 m. Rocket misses still vary
substantially within a salvo (roughly 2–34 m in the first burst and 7–30 m in the
second). Continuous tracking is not a claim that every rocket now hits.

The minimum sampled flat gun altitude was 31.40 m. The aircraft survived, but
that is a relatively thin margin and should be stressed in further terrain tests.
"Alive" is not a claim of no damage or general crash-proof behavior.

### Completed ridge results

| Weapon | Attack entries | Releases | Emplacement damage | Aircraft |
| --- | ---: | ---: | ---: | --- |
| Guns | 2 | 34 | 150.00 | Alive |
| Bombs | 1 | 1 | 212.31 | Alive |
| Rockets | 1 | 6 | 184.45 | Alive |

All three ran 120.02 simulated seconds. The ridge sits across the egress/return
area; bombs and rockets recorded `terrain_obstructed` on a later attempted entry,
not a second completed attack. This preserves safety but exposes the next planning
problem: selecting a different clear re-attack axis promptly, rather than extending
and rediscovering an obstructed line. No terrain gate was weakened to improve the
entry count. Ridge gun minimum sampled AGL was 67.04 m.

All six final runs are COMPLETE, verified their hashes during the run, and were
checked again against the current source files after completion. Every run damaged
the emplacement and every aircraft survived. All diagnostic processes launched for
this investigation have exited; no scheduled task was created or resumed.

### Regression checks

Ground plan/priority/release checks: 32, zero failures. Includes a real release
handler exercise with the proximity fallback enabled: 100 m miss withheld, absent
prediction withheld, 12 m solution released. Skill 60, visual contact 29, evasion
62, pursuit 80 and deck-footprint waveoff 136 checks passed. Go-around response,
recovery route capture and terrain escape also passed. The headless tests still
emit renderer/material/resource cleanup errors at exit; these are not reported
as clean shutdowns. The six completed physical diagnostic stderr logs contained no
GDScript runtime/parse errors or invalid-call/access errors.

## Remaining scope

Follow-up: [rocket refresh, bomb separation and the alternate-axis prototype](GROUND_ATTACK_AXIS_AND_RELEASE_SAFETY_2026-09-10.md).

- Repeat precision and burst dispersion still need a larger varied-entry matrix.
- Terrain-rejected entries need a clear alternative attack axis, not simply
  another extension toward the same obstructed return geometry.
- Small-target bomb usefulness currently uses centre-to-impact distance; it does
  not yet model the full footprint of a large non-carrier structure.
- Moving/firing threats, finite ammunition, mission-manager-enabled attacks,
  Aircraft 1/2 and production terrain need separate acceptance runs.
- Convert the remaining gameplay wall-clock timers before accelerated testing.
- No aerodynamic, suspension, damage-model, landing or dogfight changes here.
