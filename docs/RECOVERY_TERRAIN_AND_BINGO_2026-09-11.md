# Recovery terrain control and bingo-fuel stress test

## Scope and important correction

This follow-up investigates the prior five-aircraft run's failed entry/retry, then tests a real five-aircraft launch/travel/recall cycle at 35% fuel. It does not alter aircraft physics, fuel capacity, consumption, wire geometry or damage immunity.

The old loss cannot be exactly replayed: its trace omitted the terrain's floating-origin transform and aircraft angular velocity. Disabling `randomize_play_area_each_run` did not disable random carrier startup placement. The earlier authored-frame terrain height of 485 m was therefore not valid evidence about the original collision. The initial unseeded physical replay and unseeded control comparisons also used different terrain frames; do not count them as an A/B test or proof of the old loss's cause.

`LandCarrier.startup_placement_seed` now optionally fixes placement; zero retains ordinary random gameplay. This diagnostic uses 20260911 and records the terrain/carrier frame. The entry replay transforms the old carrier-relative pose and velocity into that known site, explicitly marking it as an approximate pose replay, not a checkpoint. Matching terrain and entry geometry is useful, but asynchronous scenario work and other randomness still prevent a bit-identical simulation.

Headless tests use `--fixed-fps 60` with normal 60 Hz physics. Trace time is simulation time, and `wall_s` is recorded separately. These runs demonstrate state and physical outcomes, not rendered appearance.

## Reproduced fault and implemented fix

At the same seeded site and entry geometry, both the default controller and the existing experimental capture-control candidate hit the ridge in PRE_LANDING:

| Run label | Outcome |
| --- | --- |
| `recovery_seeded_entry_base_20260911` | Destroyed 103.75 simulated seconds after entry; right-wing terrain impact |
| `recovery_seeded_entry_candidate_20260911` | Same ridge/shape failure, approximately 104 seconds after entry |
| `recovery_seeded_terrain_fix_20260911` | Survived the full 300-second observation at 100 health; waved off and retried, but did not catch/stow |
| `recovery_seeded_retry_fix_20260911` | Retry entry also survived 300 seconds at 100 health, with two wave-offs and no catch/stow; nominal carrier corridor explicitly reported obstructed |

Destruction stacks identify `aircraft._evaluate_terrain_impact` through the body-shape contact callback, not fuel exhaustion or an incoming projectile initiating the ridge loss.

Two control gaps were fixed in the shared fixed-wing pilot:

1. A 450 m path-capture band was also being used to grant reduced terrain clearance. The controller can steer from that far away, but centerline checks do not establish safe terrain there. Response-aware terrain protection now activates outside a 50 m close-tracking band. This does not cancel the route or reduce turn authority, and 50 m is a tracking tolerance, not proof that every nearby terrain point is clear.
2. PRE_LANDING's final FPA pitch servo overwrote the route controller's terrain climb floor. It now preserves that floor after the glideslope/sight calculation, converting world vertical speed into the carrier-relative frame. Normal glideslope control resumes when the floor clears.

The experimental turn-capture flags remain off: the paired test did not justify enabling them. The fix prevents a reproduced crash; it does not yet solve the blocked approach or establish reliable landings.

The diagnostic now records control inputs, the terrain climb floor, terrain transform throughout the run, and nominal carrier-corridor validity, in addition to death stacks/contact metadata. These final logging additions postdate the first fixed entry replay and both bingo-run launches.

## Bingo-fuel baseline

Label: `recovery_bingo_seeded_20260911`. Five actual model-5 aircraft used the ordinary hangar and catapult. A legal player waypoint was issued and the carrier travelled approximately 1.28 km. Recall at simulation time 211.133 s set each real fuel tank to 35%, representing the end of a sortie; there were no refills afterward.

| Aircraft inventory name | Result | Catch / stow time from scenario start |
| --- | --- | --- |
| Aircraft_1_1 | Soft touchdown without a catch; requeued; exhausted fuel in hold and later destroyed | None |
| Aircraft_2_2 | Exhausted fuel in hold and later destroyed | None |
| Aircraft_3_3 | Exhausted fuel during PRE_LANDING; destroyed in subsequent carrier contact | None |
| Aircraft_4_4 | Caught and stowed at 100 health | 452.667 / 493.483 s |
| Aircraft_5_5 | Caught and stowed at 100 health | 589.183 / 631.050 s |

Fuel exhaustion occurred 468–478 seconds after recall. The run ended at 797.133 s with two stowed and three destroyed. The initial failed attempt was a non-damaging carrier touchdown at 2.21 m/s sink and 40.82 m/s relative speed, not an airborne terrain crash. One missed catch consumed enough extra queue time to expose the reserve problem.

This is a deliberate late-return stress case: imposing 35% on the entire group at recall bypasses the earlier queue-budget-triggered return that normal missions can use. It shows that queue priority cannot make an already-late five-aircraft arrival feasible. It does not establish that the earlier-return policy is ineffective, or that the terrain fix can solve throughput.

## Verification and remaining work

### Five-aircraft rerun with terrain fix

Label: `recovery_bingo_terrain_fix_20260911`, same placement seed and 35% recall setup. Recall at 211.233 s; carrier travel approximately 1.23 km; completed at 768.233 s.

| Aircraft | Result | Catch / stow (s) | Full-power reserve at stow |
| --- | --- | --- | --- |
| Aircraft_1_1 | Waved off; fuel exhaustion while holding, then destroyed | None | None |
| Aircraft_2_2 | Stowed, 100 health | 405.333 / 446.133 | 281.8 s |
| Aircraft_3_3 | Stowed, 100 health | 524.250 / 565.933 | 162.6 s |
| Aircraft_4_4 | Stowed, 100 health | 653.950 / 695.700 | 33.0 s |
| Aircraft_5_5 | Engine stopped with sub-tick residual fuel during approach; subsequent right-wing terrain impact | None | None |

Result: **3/5 stowed, two losses after usable-fuel exhaustion**, versus 2/5 in the preceding run. This is encouraging but is not a controlled statistical improvement: initial placement was the same, but approach order and trajectories differed. The terrain fix still allowed a high wave-off on the first approach; it does not make a late group arrival sustainable.

The fuel-empty event initially used a 0.001-unit cutoff. Aircraft_5_5's engine stopped with 0.001062 units (0.0142 full-power seconds) left because energy requests are all-or-nothing per physics tick. The trace records zero burn from 679.233 s onward; the old event cutoff missed it. Future diagnostics use stopped burn plus less than one full-power tick of endurance, with focused regression coverage. Existing run logs are preserved unchanged.

Focused tests passed: RecoveryRouteCapture (including terrain-floor preservation/release), RecoveryTerrainEscape, RecoverySequencing, RecoveryDeckEnvelope, WireReachability and FixedWingFuelEndurance. Existing exit ObjectDB warnings remain; full-world diagnostics also produce renderer null-material/resource errors. Do not describe these as completely clean exits.

The next substantive work is recovery feasibility and scheduling, not more bank authority: validate the actual entry-to-final path against terrain, avoid repeating an unsuitable circuit at a blocked carrier site, budget recovery for the whole returning group and a retry, and provide an explicit low-fuel exception instead of continuing the ordinary hold until the engine stops. Simply reinstating an unconditional terrain-clearance gate would bring back indefinite holds; carrier movement and aircraft approach admission need to be coordinated.

Saved campaign file sizes/timestamps were checked and remained unchanged during this work.
