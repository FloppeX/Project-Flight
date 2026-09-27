# Recovery-site assessment

Follow-up controller fixes, Aircraft 2 settings, and the subsequent bounded comparison are documented in [Recovery profiles](RECOVERY_PROFILES_2026-09-19.md). The results below describe the earlier baseline.

The carrier damage-control page now displays a separate fixed-wing approach status: terrain clear, obstructed (with a reposition/change-heading suggestion), or unverified. The public `FlightDeckManager.get_recovery_site_status(force_refresh)` API uses the existing nominal final-corridor terrain sampler. Disabled checking or an unavailable terrain provider is unverified rather than reported as clear.

This is an advisory. It does not revoke landing clearance, interrupt a landing, change helicopter handling, steer the carrier, or certify the full recovery circuit. Existing flight controls and recovery permissions are unchanged. The sampled corridor result can be cached for the existing terrain-check interval.

`Tests/RecoverySiteStatusSmoketest.gd` exercises clear and obstructed terrain, disabled checks, a missing provider, restored clearance, and the warning text on the real CarrierPage. Run with `--headless --script`; without headless it also captures `user://recovery_site_warning.png`. The focused check passed; the rendered warning was inspected. The fixture suppresses deck-operation startup, not the terrain assessment implementation.

## Bounded fleet comparison

`Tests/CarrierPositionComparison.gd` now consumes the public assessment and rejects unchecked or unexpected placement. With `--clear-position`, `--batch-model=1` (or 2, 5, 14), `--trials=2`, and `--trial-timeout=900`, each worker flies near-outbound and standard-inbound arrivals at the same clear carrier pose and heading. Wind is disabled, authored aircraft handling retained, and above-deck spawn heights are shared with the earlier obstructed-site comparison. Each uncaught attempt gets 900 simulated seconds; a caught aircraft remains until the deck finishes stowing it.

The current eight-attempt run is recorded in `logs/active_clear_site_fleet.txt`. `python tools/summarize_clear_site_fleet.py` writes its report and summary, including failures, health, missed approaches, strict/permissive handoffs and successful wire/stow timings. The manifest records process IDs and flight/deck source hashes. Completed workers' raw JSONL and status files are copied into the report directory.

This small calm-weather sample isolates model and arrival differences at one placement. It does not measure fleet-wide reliability, wind robustness, launch-to-recovery sorties, or concurrent recovery queues. The previous 100-attempt assessment remains stopped.

## Remaining retry-policy issue observed

The bounded fleet run completed all eight attempts: Aircraft 1 and 5 each stowed 2/2 undamaged; Aircraft 2 and 14 each timed out 2/2. All successful handoffs used the permissive final-commit path, so strict stabilized-approach acceptance remains unproven. Aircraft 5's near-outbound arrival needed three missed approaches and 541 seconds to stow. Every sampled nominal corridor remained clear; no worker recorded a script error. SHA-256 checks confirmed the flight/deck sources were unchanged during the run, and all four workers exited. Full results are in `logs/clear_site_fleet_20260919_101352/report.md`.

Aircraft 2 kept retrying but failed to align at the final handoff. Aircraft 14 additionally stopped retrying as described below. The next contained repair should address the retry-policy inconsistency, then the turn-to-final alignment, preserving the short recovery geometry and testing actual wire capture and stow.

In the near-outbound trial Aircraft 14 missed three approaches, then remained in `RECOVERY_HOLD` from approximately 261 to 907 simulated seconds without clearance or a queue position. `AIPilot._state_recovery_hold` returns before requesting clearance while the attempt limit is reached. `_update_recovery_retry_cooldown` never releases that condition when `landing_bolter_retry_cooldown_s <= 0`. Aircraft 14 inherits the zero default, while Aircraft 2 explicitly sets a 20-second retry cooldown. This explains the observed persistent hold path and deserves a separate recovery-policy fix; it does not explain the original alignment errors. No retry configuration was changed during this assessment.
