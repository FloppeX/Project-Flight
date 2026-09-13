# Ground attack: rocket refresh, release separation and alternate approaches

Follow-up to [repeat-pass feedback](GROUND_ATTACK_REPEAT_PASSES_2026-09-10.md).
Aircraft 5, real weapons, durable non-firing targets and normal aircraft damage.
No scheduled monitoring and no changes to flight physics, landing or temperament.

## Production changes

### Rocket prediction refresh

The normal prediction interval is 150 ms, versus a nominal 70 ms between rockets
in the pod's physical burst. Keep ordinary acquisition at that cadence, but use
50 ms near a useful solution (previous predicted miss under 60 m) or during a
burst. Continuous aiming from the previous iteration remains active. This changes
neither weapon dispersion nor the physical launch interval.

`rocket_ccip_precision_refresh_enabled` controls this behavior and defaults on.
The diagnostic's `--ground-legacy-rocket-refresh` flag selects the previous cadence.

Two paired 60-second tests (`ground_v8_*.json`) gave:

| Entry offset | Refresh | Rockets | Mean actual miss | Target damage | Aircraft |
| --- | --- | ---: | ---: | ---: | --- |
| +1000 m | Previous | 6 | 25.60 m | 0.00 | Alive |
| +1000 m | Faster near release | 6 | 16.62 m | 153.71 | Alive |
| -1000 m | Previous | 6 | 14.65 m | 239.55 | Alive |
| -1000 m | Faster near release | 6 | 12.05 m | 278.68 | Alive |

All four completed and verified their source hashes. Faster-refresh wall durations
were 110.86/109.03 s, versus 109.47/107.26 s for their respective comparisons.
That is a small observed difference here, not a general performance benchmark:
these headless tests run under concurrent load and include wall-clock-dependent
gameplay. Additional predictor work is limited to the near-release window. Two
pairs are evidence for keeping the change, not a statistical reliability claim.

### Bomb release separation

The alternate-route bomb trial exposed a separate physical failure. At 170.97 s,
the second bomb spawned into its predecessor: both registered bomb-body collisions
around 600 m from the target, despite predicted misses of about 6 and 5 m. These
were not ballistic misses or terrain impacts.

Bomb racks now check a shared, aircraft-local list of released bombs before
accepting another trigger. They require 1.25 m separation by default, with a short
200 ms relative-motion check for a predecessor moving back into the release area.
This is a conservative clearance for the default roughly 1.03 m-long bomb; custom
larger stores should adjust `release_clearance_m`. A pending-spawn flag prevents
two racks from approving overlapping releases in the same frame. Weak references
are pruned on registration and invalid predecessors never block release.

The check happens before ammunition/slots are consumed, so a blocked trigger can
be retried with a current aim prediction. Bomb collision masks, gravity, damage,
arming and steering physics are unchanged. This applies to player and AI racks,
including racks on helicopters.

## Experimental alternate-approach planner: default OFF

After a terrain-rejected approach and the normal physical pull-out, the prototype
searches 16 headings at two heights. It validates the attack at the actual commit
distance using the existing weapon corridor checks, includes the normal egress,
then selects a nearby terrain-cleared staging point. All live terrain and commit
checks still apply after repositioning; a sampled clear axis is not a guarantee
that the aircraft will fly it perfectly.

The bounded search runs only on replanning after a rejection, not every frame.
Measured search times were 1.88 ms for the bomb trial and 6.63 ms for the rocket
trial in this small arena. Production terrain cost remains unmeasured.

The physical trials did not establish a repeat-pass improvement. Both bomb cases
released three bombs in 240 s; the candidate lost two to the release collision
described above. The rocket candidate still had only one salvo by 180 s. Keep
`ground_attack_alternate_axis_enabled` off in production pending better
pose/heading capture. Use `--ground-alternate-axis` to opt into the prototype in
the diagnostic. The old direct re-entry remains the production default.

## Tests and next work

- Ground plan/priority/release/alternate-axis checks: 39 passed, including all
  three weapons finding validated side approaches and a fully blocked search
  refusing to invent a clear corridor.
- Bomb separation checks: 9 passed, including shared cross-rack clearance,
  approaching and freed predecessors, aircraft isolation and pending releases.
- Final-source skill (60) and pursuit (80) checks passed as well.

### Final physical confirmations

| Run | Duration | Releases | Emplacement damage | Aircraft |
| --- | ---: | ---: | ---: | --- |
| Bombs, ridge, production direct re-entry | 180 s | 2 | 533.92 | Alive |
| Bombs, ridge, experimental alternate axis | 180 s | 2 | 530.46 | Alive |
| Rockets, flat, production defaults | 60 s | 6 | 248.94 | Alive |

Artifacts: `ground_v9_bomb_guard_default.json`, `ground_v9_bomb_guard_axis.json`,
`ground_v9_rocket_default.json`, under the normal Godot user-data directory.
All three are COMPLETE with verified hashes, also checked against current source
after completion. The physical stderr logs contain no GDScript runtime/parse or
invalid-call/access errors. Smoke tests still have resource-cleanup warnings at
shutdown; this is not a clean-renderer-shutdown claim.

The collision reproduction now releases the first bomb of the second pass at
170.60 s and hits the emplacement at 175.98 s, 6.35 m from its centre. The unsafe
following release is withheld; it is not consumed or spawned. Both released bombs
cause damage instead of losing two stores to a midair collision. The default
re-entry case likewise has two damaging impacts, at 18.53 and 6.59 m centre miss.
This fixes the observed launch overlap, not every possible later bomb collision.

All ten physical diagnostic runs in this iteration completed with the aircraft
alive. No test process from this iteration remains active; no scheduled task was
created or resumed. These were small, durable-target
tests of Aircraft 5, not fleet-wide combat acceptance or a guarantee of survival.

Next: stronger terminal-axis capture for the alternate planner, more varied
rocket entries and moving/firing targets. Aircraft 1/2 and production terrain
remain outside this small acceptance sample. Do not trade terrain safety for an
artificially higher attack count.

Follow-up: terminal-axis capture, staging-plane handoff and matched physical
comparisons are recorded in [approach alignment](GROUND_ATTACK_APPROACH_ALIGNMENT_2026-09-10.md).
