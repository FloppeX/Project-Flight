# Recovery queue, fuel reserve and wheel-supported wire prediction

## Changes

### Approach preparation can overlap stow

`FlightDeckManager.request_recovery_approach()` can admit one fixed-wing successor after its predecessor catches a wire or enters hangar storage. It does not admit a successor behind an airborne final, nor during an outbound launch. An admitted approach retains its place when fuel priority changes.

The existing exclusive landing clearance still requires the deck to be clear. `AIPilot` checks that clearance at the final handoff, before permissive handoff overrides, and in final itself. If storage has not cleared the deck in time, the successor goes around. Actual arrest takes precedence over that check.

This deliberately overlaps only airborne preparation with ground handling; no simultaneous deck landings, forced catches, tractor shortcuts or flight-physics changes.

### Recovery is fuel-aware

- Fuel telemetry uses actual available fuel divided by the sum of all fuel engines' full-power burn rates. Unknown fuel is reported as unknown, not empty.
- Waiting aircraft with less than eight minutes of conservative endurance receive priority, lowest reserve first. An already admitted approach/final is not displaced. Plentiful-fuel aircraft retain FIFO ordering.
- Fixed-wing pilots may return before the ordinary 35% bingo threshold if estimated transit, queued recovery slots and a two-minute margin would consume their remaining full-power endurance.
- Initial planning allowance is 150 seconds per slot. This is a conservative scheduling estimate, not a guaranteed landing time or a substitute for better throughput.
- Fuel capacity, consumption and ordinary bingo threshold are unchanged. The existing fixed-wing profile has approximately 7.8 minutes of full-power reserve at bingo, so the previous 11-minute hold was genuinely too long for a normal mission return.

### The wire predictor now considers wheel support

The baseline Aircraft_3_3 snapshot at 663.153 seconds projected wheel contact at 1.935 seconds, between wire 1 (1.792 seconds) and wire 2 (2.173 seconds). Its freely descending hook was projected 1.461 m below wire 2. Continuing horizontally at wheel-contact height instead gives approximately +0.289 m, within the existing 0.8 m wire tolerance. The aircraft subsequently caught wire 2 despite a late wave-off.

A separate `deck_supported_wire_crossing()` check now recognizes that possible catch. It requires near-term support, an acceptable contact sink rate, modest bank, lateral wire overlap and a safe physical deck footprint. The stopping footprint is rechecked for the selected later wire. Unsafe/off-deck touchdowns, high hooks, lateral misses and wires crossed before support remain rejected.

This is a prediction, not a promise: suspension response and bouncing can still change the outcome. Actual hook/wire collision and arrest physics are unchanged.

## Diagnostics and focused verification

- `RecoverySequencingSmoketest`: exclusive final, one prepared successor, no airborne-final/launch overlap, fuel priority without revoking an approach, earlier queue-aware RTB, busy-deck rejection, actual-catch precedence and freed-reservation cleanup.
- `WireReachabilitySmoketest`: existing bounded-correction cases plus the logged supported-wire case and negative support/height/lateral/sink cases.
- `FixedWingFuelEnduranceSmoketest`: existing fuel profile and hangar refuelling regression.
- `RecoveryDeckEnvelopeSmoketest`: existing directional deck/escape envelope regression.

The sequencing test exposed a pre-existing freed-object type-boundary error in queue pruning. Stale aircraft are now validated as `Variant` before casting, so a destroyed/freed waiter can be removed safely.

The full-scenario harness now records remaining fuel, conservative endurance, recovery budget, approach permission and source-tagged projectile damage separately from generic health changes. This avoids interpreting critical-damage bleed as repeated bullet impacts.

## Full-scenario validation

Visible five-aircraft rerun label: `five_aircraft_recovery_pipeline_20260911`.

Completed: **four caught and stowed at 100 health; one destroyed airborne on a retry**. No aircraft exhausted its fuel. All were model 5, as in [the baseline](FULL_SCENARIO_FIVE_AIRCRAFT_RECOVERY_2026-09-11.md).

| Inventory name | Approach starts (s) | Catch (s) | Stowed (s) | Full-power endurance at stow / last live sample |
| --- | ---: | ---: | ---: | ---: |
| Aircraft_1_1 | 158.092 | 292.006 | 332.871 | 17.9 min |
| Aircraft_2_2 | 318.675 | 441.449 | 483.198 | 15.7 min |
| Aircraft_3_3 | 458.957 | 565.094 | 606.943 | 13.9 min |
| Aircraft_5_5 | 735.407 | 841.783 | 883.549 | 9.8 min |
| Aircraft_4_4 | 592.130; retry 868.536 | None | Destroyed 966.362 | 7.6 min, 34.30 fuel units |

Recall was at 157.075 seconds. The second and third catches were approximately 50 and 100 seconds earlier than baseline. Successor approaches began 14–24 seconds before predecessor stow finished. No late `escape_deadline_no_reachable_wire` wave-off occurred; supported-wire feasibility appeared in live telemetry. Four successful recoveries had no damaging touchdown contacts.

However, **overall recovery is not yet reliably faster**: Aircraft_4_4 arrived at the final handoff roughly 372 m off-axis, banked 22 degrees, at 715.075 seconds. The existing geometry gate correctly rejected that approach. It escaped safely, yielded to Aircraft_5_5 and rejoined the queue before retrying. The longest initial hold fell from 680 seconds to 577 seconds, but the failed approach and retry consumed the savings: the last successful stow was 726 seconds after recall, versus 691 seconds in baseline. Recovery order and carrier placement differed, so this is not a deterministic performance benchmark.

### Remaining loss and limitations

Aircraft_4_4 was destroyed approximately 2.3 km from the carrier during the retry's arrival turn. Its last sample was healthy, at altitude 751.7 m with fuel remaining; there was no prior projectile-damage event or touchdown/crash signal. `destroyed` preceded a generic 100-health-loss notification, consistent with the destruction explosion causing that subsequent damage rather than an incoming bullet initiating it. The original destruction call site was not recorded, so its exact cause remains unresolved.

Correction from subsequent investigation: the terrain Y=485 m obtained by `RecoveryTerrainTraceReplay.gd` was in the authored frame, not the original run's floating-origin frame. Startup carrier placement was random even with map-area randomization disabled, and the original trace omitted the terrain transform. That height result cannot support or exclude terrain impact. A later physical pose replay hit terrain with its left-wing collider, but also used a different terrain frame; it demonstrates a possible failure, not the original cause. New diagnostics record the frame and seed carrier placement. Old poses can only be replayed as relative entry geometry at a known test site, not exact checkpoints.

The harness has therefore been extended **after this run** to capture destruction call stacks, collision metadata and local ground height, and to update the final health summary on health-change events. The original summary still contains the last sampled 100 health alongside `destroyed=true`; the event log records the subsequent zero-health notification. Do not interpret the stale summary as survival.

Also added after the run: a regression-tested carrier-motion constraint for the prepared approach, covering the case where the generic terrain-corridor check is false during stow. The visible run predates this final guard; the focused sequencing test passes with it.

The full run reported no script errors, but renderer resource/null-material errors occurred during shutdown after results were written. Focused tests retain the existing exit ObjectDB leak warning. A missing arresting-cable metadata warning in the older reliability harness was guarded, and that test passed cleanly apart from the exit warning.

### Next bounded step

Replay Aircraft_4_4's bad turn-in and retry with the new destruction evidence, improving arrival alignment and identifying the actual collision/destruction cause. Then run a cohort returning near bingo. The short launch-and-recall test plus low-reserve unit checks do **not** establish that a five-aircraft group can all land after a normal full-length mission, especially after failed approaches. Fuel-aware recall uses an estimated budget, not a guarantee against exhaustion.
