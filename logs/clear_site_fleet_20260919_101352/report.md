# Clear-site fleet recovery assessment

Aircraft 1, 2, 5 and 14, two arrivals each; calm wind, identical clear carrier pose and heading. Authored handling retained. Each uncaught attempt has 900 simulated seconds. This is eight trials, not a fleet reliability estimate; launch, combat and concurrent recoveries are outside scope.

| Aircraft | Arrival | Outcome | Health | Seconds to wire | Seconds to stow | Missed approaches | Strict / permissive handoffs |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | near_outbound | STOWED | 100.0 | 102.3 | 134.0 | 0 | 0 / 1 |
| 1 | standard_inbound | STOWED | 100.0 | 186.9 | 226.1 | 0 | 0 / 1 |
| 2 | near_outbound | TIMEOUT | 150.0 | — | — | 6 | 0 / 0 |
| 2 | standard_inbound | TIMEOUT | 150.0 | — | — | 5 | 0 / 0 |
| 5 | near_outbound | STOWED | 100.0 | 506.2 | 541.0 | 3 | 0 / 1 |
| 5 | standard_inbound | STOWED | 100.0 | 168.8 | 211.8 | 0 | 0 / 1 |
| 14 | near_outbound | TIMEOUT | 100.0 | — | — | 3 | 0 / 0 |
| 14 | standard_inbound | TIMEOUT | 100.0 | — | — | 3 | 0 / 0 |

Complete: True

The public recovery-site assessment checks the nominal final terrain corridor only. Its UI warning is advisory and does not change landing permission, steer the carrier, or guarantee the whole recovery circuit is clear. Raw events, placement validation and error counts are retained alongside this report.

## Corridor checks during recovery

| Aircraft | Clear samples | Obstructed samples | Unknown samples | Script errors |
| --- | ---: | ---: | ---: | ---: |
| 1 | 73 | 0 | 0 | 0 |
| 2 | 360 | 0 | 0 | 0 |
| 5 | 152 | 0 | 0 | 0 |
| 14 | 360 | 0 | 0 | 0 |
