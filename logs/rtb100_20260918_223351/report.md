# RTB batch results — stopped by user

Completed: 44/100.

| Aircraft | Attempts | Caught | Stowed | Undamaged stows | Lost | Timeout | Median wire s | Median stow s | Retry trials | Strict / press handoffs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 10 | 0 | 0 | 0 | 0 | 10 | — | — | 10 | 0 / 0 |
| 2 | 13 | 0 | 0 | 0 | 5 | 8 | — | — | 9 | 0 / 0 |
| 5 | 10 | 0 | 0 | 0 | 0 | 10 | — | — | 10 | 0 / 0 |
| 14 | 11 | 0 | 0 | 0 | 0 | 11 | — | — | 11 | 0 / 0 |

Timing medians include successful catches/stows only; failures remain in the attempt counts. Undamaged means no recorded health loss during the trial, not merely repaired health at storage. Retry counts are sampled at 1 Hz; strict/press handoffs come from controller event logs.

Five arrival profiles, five repeats per model, alternating sides. Normal 60 Hz physics at uncapped headless speed; authored handling and live weather. This is one carrier/terrain setup with fresh airborne spawns, not a random sample of all missions, a combat sortie, or a launch test. Models share the profile matrix but are not exact weather/trajectory replays. Wilson intervals in summary.json describe sample size only; correlated repeated cases limit population inference.

Stopped at user request. Active unfinished trials were interrupted and are excluded from completed-attempt counts. Raw events and last runtime statuses are preserved beside this report; their RUNNING status reflects the final pre-stop snapshot.

## Carrier-position confound confirmed after stopping

All 7,771 recorded batch snapshots reported `nominal_landing_corridor_clear=false` (Aircraft 1: 1,929; 2: 1,938; 5: 1,898; 14: 2,006). Each worker kept a single fixed carrier position, near (-21.21, 522.0, 2.30). The corridor predicate samples terrain against the nominal final glideslope plus airframe clearance; false therefore indicates an obstructed nominal landing corridor, not merely a pilot failing alignment.

The earlier successful full-sortie runs started at that same position but moved before recall. `arrival_select_sortie_final` recovered near (-144, 525, -2375), with all 175 recovery snapshots reporting a clear corridor. `handoff_sortie_damped` recovered near (-116, 525, -2870), with all 335 recovery snapshots clear. The prepared-entry fixture also explicitly relocated the carrier about 2.2 km from the batch position.

Consequently this batch establishes failure at an obstructed fixed carrier location. It does not establish general aircraft landing success rates or isolate flight-control failure. Earlier controller shortcomings still exist, but the position confound must be removed before another fleet reliability comparison. Next comparison should use unchanged aircraft/control settings and identical arrival cases at both the obstructed pose and a verified clear pose, with terrain-clearance validation before starting. No additional tests were started for this audit.
