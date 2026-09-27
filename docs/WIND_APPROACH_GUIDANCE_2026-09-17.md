# Wind-aware final approach — 2026-09-17

Status: a verified improvement to prepared straight-in approaches, **not a completed recovery repair**. The fixed quick-turn-in approaches still fail with progressive low-speed controls.

## Retained changes

- Final-approach throttle and stall protection use airspeed. Geometric lookahead and carrier-relative flight-path guidance retain ground/deck-relative velocity.
- Terminal rudder coordination measures aerodynamic sideslip using air-relative velocity. Wind-induced ground drift is no longer interpreted as sideslip to eliminate.
- With acceleration guidance active, LANDING uses the same terminal objective as PRE_LANDING. It no longer mixes the new bank objective with the old runway-heading rudder objective. Its smoothing starts from the previous frame's rudder input, not the old controller's freshly computed command.
- Rudder commands use the estimated available steady yaw rate from authority, rudder power and damping. Commands remain bounded to full control-surface travel; no additional aircraft force or artificial motion is applied.
- Lateral capture has a six-second outer horizon, extended when necessary by its configured response delay. It starts removing drift earlier instead of distributing correction over the entire time remaining to the wire. Existing acceleration limits and landing safety gates remain intact.

No aircraft control strength, wind strength, carrier collision geometry or cable gates were relaxed. The previous roll-estimate correction remains in place.

## Final matched runs

Aircraft 5, Advanced model, same prepared entries and deterministic stationary carrier as the previous comparison. Entry speeds are 50, 60 and 70 m/s; turn cases include both directions. A catch requires a real cable engagement and stable stop.

| Progressive controls | Before this change | Retained change |
| --- | ---: | ---: |
| Calm, straight-in | 3/3 | 3/3 |
| Wind, straight-in | 0/3 | 2/3 |
| Calm, turn-in | 0/6 | 0/6 |
| Wind, turn-in | 0/6 | 0/6 |

The windy 60 and 70 m/s entries caught and stopped with NORMAL touchdown classifications and zero recorded aircraft/part damage. The windy 50 m/s entry waved off. All final turn failures were wave-offs; none of these 18 final attempts crashed or recorded aircraft/part damage. One calm straight-in touchdown was classified HARD, so the catch count is not a blanket touchdown-quality claim.

An earlier rudder candidate with an eight-second lateral horizon produced two windy catches but a collision in the slowest case; it was superseded. Attempts to change the quick-turn minimum bank, increase turn-controller gains, retain capture speed or delay controller handoff did not establish a reliable turn-in improvement and were removed. Their trial logs are diagnostic artifacts, not final validation.

## Evidence and limits

- Baseline before this turn: `captures/authority_before_guidance_fix/`.
- Final results and telemetry: `captures/authority_reduced_{calm,windy}_{straight,turn}_final_{result.json,samples.jsonl}`.
- Final stdout: `captures/guidance_final_{calm,windy}_{straight,turn}.log`.
- `RecoveryWindControlSmoketest` verifies air-relative coordination, increased rudder travel under weaker authority, both turn directions and bounded saturated commands.
- `LandingSightSmoketest` verifies moving-deck prediction, capture/sink checks, sensor geometry and observation without control mutation.
- The previous-authority calm straight-in regression also caught and stopped all three aircraft with zero aircraft damage (`authority_legacy_calm_straight_final_result.json`). All 18 progressive-control entry manifests exactly match their baseline.
- These are headless physical approach tests, not rendered flight-quality checks or complete takeoff-to-hangar cycles. The quick-turn harness still uses its existing prepared geometry and permissive `press` final handoff. Its outcomes must not be generalized to all operational routes or all wind directions/seeds.
- Known headless dummy-renderer material errors and shutdown leak warnings remain. The final suites and focused checks have no SCRIPT ERROR.

The remaining failure precedes final capture: the quick turn can exit with substantial cross-track velocity and displacement, then hand that pose to the limited final controller. This work does not prove a solution for that path. A feasible arrival trajectory and its full operational handoff still require validation.

The comparison harness now accepts `--authority-run=<label>` to keep trial outputs separate. Reproduce a final straight-in suite with:

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 --script res://Tests/AuthorityApproachComparison.gd -- --test-scenario=5 --landing-sight-matrix --landing-aircraft-model=Aircraft_5 --landing-matrix-repeats=1 --landing-matrix-start-case=3 --landing-attempt-limit=3 --landing-attempt-timeout=90 --authority-case=reduced_windy --authority-run=final
```

For turn-in, replace the sight-matrix and start-case flags with `--landing-turn-in-matrix`, and use six attempts.
