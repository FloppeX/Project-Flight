# Control authority and wind comparison — 2026-09-17

Reduced low-speed control authority is a major contributor to the tested recovery failures. Wind adds a separate difficulty, including on already-aligned finals. No production flight settings or guidance were changed for this comparison.

## Outcomes

Each success below means an observed wire catch followed by a stable stop, not merely entry into a landing state.

| Configuration | Turn onto final | Already aligned final |
| --- | ---: | ---: |
| Previous authority and damping, calm | 6/6 | 3/3 |
| Progressive authority and damping, calm | 1/6 | 3/3 |
| Progressive authority and damping, wind enabled | 0/6 | 0/3 |

All unsuccessful attempts waved off. The only successful progressive/calm turn was right_v70. Successful catches recorded zero aircraft damage and zero part-health loss, although several touchdowns were classified HARD; the previous-control left_v60 touchdown had 7.34 m/s pre-contact sink. These are recovery counts, not proof of satisfactory touchdown quality.

## Method

- Aircraft 5, Advanced flight model, 1,100 kg, real aircraft physics and carrier cables.
- Stationary carrier at a deterministic clear approach location; no moving-carrier or terrain-route differences between variants.
- Turn cases: left and right entries at 50, 60 and 70 m/s, using the existing quick-turn-in recovery harness.
- Straight cases: aligned 1,000 m behind, 105 m above the deck, at 50, 60 and 70 m/s.
- Exactly matching entry dictionaries, aircraft positions, velocities, masses and carrier transforms were verified across all three variants for both suites.
- Wind uses the existing WindField settings, with its clock reset before each attempt. Calm disables that field. The previous-control variant disables progressive authority, also restoring the previous damping relationship; it does not revert every recent aerodynamics change.
- One attempt per case, fixed 60 Hz headless simulation. The quick-turn-in harness retains its existing final handoff behavior, including its diagnostic `press` handoff. These are prepared approach tests, not full operational return-to-base missions or rendered flight-quality checks.

The test wrapper is `Tests/AuthorityApproachComparison.gd`; its subclass is `Tests/Fixtures/AuthorityApproachHarness.gd`. Results, 10 Hz telemetry and stdout are under `captures/authority_{legacy_calm,reduced_calm,reduced_windy}_{turn,straight}*`. All six result files contain the expected case counts. No SCRIPT ERROR was found; headless dummy-renderer material errors and shutdown leak warnings remain in the logs.

Example invocation (replace variant and select the desired suite):

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 --script res://Tests/AuthorityApproachComparison.gd -- --test-scenario=5 --landing-turn-in-matrix --landing-aircraft-model=Aircraft_5 --landing-matrix-repeats=1 --landing-attempt-limit=6 --landing-attempt-timeout=90 --authority-case=reduced_calm
```

For the straight suite, replace `--landing-turn-in-matrix` with `--landing-sight-matrix --landing-matrix-start-case=3` and use `--landing-attempt-limit=3`.

## Interpretation and next repair target

The calm comparison isolates the progressive control/damping change: the aircraft can still complete an aligned final, but the existing turn-in maneuver usually fails. Wind then prevents all three tested aligned finals as well. This supports adapting AI planning and correction to the new physics while retaining the intended low-speed softness. It does not establish that wind strength alone is excessive, or that every airframe behaves identically. A previous-controls/wind fourth variant would be needed to separate wind's standalone effect from its interaction with reduced authority.

There is a concrete mismatch to address first: `AIPilot._estimate_maximum_roll_rate_rad_s()` estimates damping using `max(control_authority, 0.3)`, while progressive `SimpleAero` uses `get_progressive_rate_damping_factor()`. At 60 m/s with a 100 m/s reference and no stall loss, these factors are 0.36 versus 0.60. This makes the AI's predicted steady roll rate about 67% too optimistic under those assumptions. The AI already reads the new roll authority for torque, so it is partly adapted, but its roll-rate estimate is inconsistent with the applied damping. This is a plausible contributor, not yet proven to explain all failures.

## Follow-up: shared roll damping estimate

Implemented a shared `SimpleAero.get_rate_damping_factor_at_speed()` used by progressive physics and the AI's steady roll-rate estimate. The AI correction is restricted to Advanced progressive controls. The applied physics schedule, low-speed softness and landing safety gates are preserved.

The repeat did **not** fix recovery:

| Progressive controls | Before | After |
| --- | ---: | ---: |
| Calm, turn onto final | 1/6 | 0/6 |
| Wind, turn onto final | 0/6 | 0/6 |
| Calm, aligned final | 3/3 | 3/3 |
| Wind, aligned final | 0/3 | 0/3 |

Every failed attempt waved off. Entry conditions match the archived baseline for all 18 repeated attempts. Before-change artifacts are retained under `captures/authority_before_roll_fix/`; the current reduced-control artifacts contain the repeat. The original legacy baseline was not rerun. The existing `Aircraft5ProgressiveControlProbe` passed, including physical low-speed roll response (about 19 deg/s at 55 m/s and 23 deg/s at 65 m/s). All four repeated suites completed with no SCRIPT ERROR; the usual dummy-renderer/shutdown warnings remain. A direct standalone SimpleAero check-only command cannot resolve the project's TerrainReference autoload; the complete project tests successfully load and execute it.

The estimate correction is mathematically consistent, but the loss of the one successful calm turn is a behavioral regression. It must not be presented as a completed recovery repair. The fixed quick-turn maneuver and approach controller need further work; a corrected maximum-rate estimate alone does not establish a feasible turn or wind-compensated final. Full operational recovery validation remains outstanding.
