# Ground-attack approach alignment

## Scope and hypothesis

Aircraft 5, production flight controls and weapons, durable non-firing ground
targets, physical terrain and normal aircraft damage. The alternate-axis search
remains opt-in while these tests run. No changes to flight-model authority,
terrain avoidance, weapon accuracy gates, or pull-out clearance.

The previous alternate planner selected a terrain-clear staging coordinate but
discarded it on proximity alone. In the logged bomb re-entry the aircraft reached
that coordinate flying outbound, then made a large reversal with direct target
pursuit. A successful point capture was not a successful approach alignment.

## Changes under test

- Retain the selected inbound direction after reaching the staging point.
- Start joining when the aircraft passes the staging plane, including when it
  passes abeam of the point. Do not turn back just to enter a proximity bubble.
- Price departure and arrival heading changes in the bounded candidate search.
- Join the fixed attack line with cross-track and ground-track feedback, including
  the rate at which the desired intercept heading changes during convergence.
- Pass the resulting lateral acceleration into the existing unified 3D guidance
  solve; a bank hint alone is insufficient.
- Require no more than 80 m sideways error, 12 degrees ground-track heading error,
  and the existing 35-degree commit bank limit to finish alignment. Keep following
  the selected line until committing, rather than reverting to point pursuit.
- Preserve the chosen approach's egress direction as well as its entry direction.
- Give line guidance explicit ownership only during its navigation calls, so
  extension and low-speed recovery navigation retain their own commands. The
  controller uses the current navigation target, not a stale setup coordinate.
- Treat 1,400 m as the outer edge of the commit window. The inner alignment
  deadline uses the existing weapon/pull-out minimum lane (900 m for these bombs),
  with a real wave-off if that window is missed. Live recovery/corridor checks
  still decide whether an aligned aircraft may attack.

The new per-frame guidance is constant-size vector arithmetic. The candidate
search is still 32 heading/height combinations, event-driven after a rejected
approach, not a new per-frame terrain search.

## First iteration: rejected early deadline

All three `ground_v10_*` runs completed 180 simulated seconds with verified
source hashes and surviving aircraft. The bomb candidate released once for
212 damage; production direct re-entry released twice for 539 damage. The gun
candidate released 70 rounds for 280 damage, but did not exercise alternate-axis
capture in this interval.

The bomb trace showed convergence from 580 m cross-track at 130 s to 93 m at
145 s. The first implementation incorrectly treated the 1,400 m outer commit
range as an alignment deadline and waved off shortly before capture. That
candidate was not accepted as an improvement. The next iteration uses the
existing minimum useful weapon lane for the inner deadline instead.

## Second iteration and opposite-side reproduction

`ground_v11_bomb_axis.json` completed 180 s with 3 releases, 598.07 damage and a
surviving aircraft. The repeat pass released at 153.58 s, versus about 171 s in
the direct baseline. Fixing the inner alignment deadline preserved the useful
convergence observed in the first trial.

However, `ground_v11_bomb_reentry_axis.json` exposed a separate missed-point
failure. From the opposite-side outbound pose, it repeatedly tried to reach the
staging coordinate and released no bombs by 120 s. The matching direct case,
`ground_v11_bomb_reentry_default.json`, released 2 at 34.05/34.78 s for 403.57
damage. Both aircraft survived. This motivated the staging-plane handoff.

The diagnostic's `--ground-reentry` option starts the aircraft outbound at
`(offset, 500, -1800)` with a remembered terrain rejection, rather than spending
a first attack getting there. It changes initial conditions only; production
control and weapon code still flies the entire run. The comparison uses offset
-1000 m. The ordinary full scenario retains offset +1000 m, altitude 600 m,
inbound speed 100 m/s, and the physical 260 m ridge.

The unfinished v11 rocket run and four v12 runs were deliberately stopped before
source edits/restarts. They are **not** completed results or survival evidence.

## Final-source validation

The expanded focused suite passes 56 checks, including actual positioning-state
transitions for tail-first staging arrival and aligned capture at 1,300 m,
retention of line guidance, abeam staging passage, extension ownership, fresh
approach reset, mirror symmetry, and finite failure for degenerate input.
Final-source skill (60), pursuit (80), evasion (62), and bomb-separation (9)
regressions pass, along with go-around response, recovery route capture, and
recovery terrain escape.

All four final physical runs are COMPLETE with `hashes_verified=true`. Every
recorded hash was also rechecked against current source after all runs finished.

| Artifact (under Godot user data) | Simulated duration | Releases | Damage | Commits | Aircraft |
| --- | ---: | ---: | ---: | ---: | --- |
| `ground_v13_bomb_axis.json` | 180 s | 3 bombs | 606.57 | 2 | Alive |
| `ground_v13_bomb_reentry_axis.json` | 120 s | 3 bombs | 324.06 | 2 | Alive |
| `ground_v13_rocket_reentry_axis.json` | 120 s | 6 rockets | 355.00 | 1 | Alive |
| `ground_v13_rocket_reentry_default.json` | 120 s | 6 rockets | 25.00 | 1 | Alive |

The full bomb case releases on its repeat pass at 153.83 s, versus approximately
171 s for the v10 direct baseline (2 bombs, 539 damage in 180 s). At the first
sampled repeat-entry ATTACK_DIVE frame, 147.02 s, the new approach has 51.21 m
cross-track, 11.07 degrees track-heading error, 33.37 degrees bank and 1,360.54 m
remaining along the selected axis. The pilot achieves useful alignment without
the previous extra reversal or the incorrect 1,400 m deadline.

The opposite-side bomb reproduction now releases at 41.08 and 41.72 s, with
17.34 and 30.84 m actual centre miss. This fixes the v11 missed-staging-point
failure, but is still slower than the direct baseline's first releases at
34.05/34.78 s. A third bomb releases at 114.40 s and is **still in flight when
the 120 s test ends**. Its eventual impact is not measured or included in damage
or mean-miss claims. This run is not evidence that all three bombs hit.

The matched rocket pair fires its first salvo at 38.87 s with the selected axis
and 30.93 s with direct re-entry. Mean actual centre miss improves from 24.61 m
to 13.20 m, with 355 versus 25 damage. Both have one salvo by the cutoff: this
pair demonstrates better observed firing geometry, not greater attack frequency.

Ordinary headless timing was used, never `--fixed-fps`. Bomb wall durations were
180.24 and 120.28 s; rocket wall durations were 259.16 and 256.17 s. Fixed-seed
tests still have startup and wall-clock-sensitive weapon timing variation; these
are small physical comparisons, not deterministic or statistically conclusive
effect sizes. Initial-state and source settings/hashes are saved in each JSON.

There are no GDScript runtime/parse or invalid-call/access errors in the four
final physical stderr logs. Existing camera/interpolation and shutdown-resource
warnings remain; this is not a clean-renderer-shutdown claim. No owned test
process remains active and no scheduled task was created or resumed.

## Acceptance and next step

The alignment and state-handoff fixes are implemented for the shared ground
attack controller. Keep `ground_attack_alternate_axis_enabled=false` in
production for now; diagnostic opt-in is `--ground-alternate-axis`. The new
controller has a useful improvement in the original failure and the rocket
comparison, but does not uniformly beat direct re-entry in the opposite-side
bomb case. Production first-pass/direct behavior remains unchanged.

Next, test more headings/speeds with the same logged axis metrics, including a
ground-gun case that actually reaches alternate capture. Compare first useful
release, complete repeat-pass time, damaging impacts and survival. Then broaden
to moving/firing targets, Aircraft 1/2, and production terrain before enabling
the alternate planner fleet-wide. The current arena proves neither those cases
nor guaranteed safety of a sampled terrain-clear heading.

Follow-up: the [broader heading/speed matrix](GROUND_ATTACK_ALIGNMENT_MATRIX_2026-09-10.md)
exposes late/high entries despite successful horizontal capture. The alternate
planner remains disabled; the next change must address the complete entry pose.
