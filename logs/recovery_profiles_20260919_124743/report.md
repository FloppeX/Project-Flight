# Clear-site fleet recovery assessment

Aircraft 1, 2, 5 and 14, two arrivals each; calm wind, identical clear carrier pose and heading. Uses the project aircraft settings recorded by the manifest source hashes. Each uncaught attempt has 900 simulated seconds. This is eight trials, not a fleet reliability estimate; launch, combat and concurrent recoveries are outside scope.

| Aircraft | Arrival | Outcome | Health | Seconds to wire | Seconds to stow | Missed approaches | Strict / permissive handoffs |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | near_outbound | STOWED | 100.0 | 93.8 | 131.5 | 0 | 1 / 0 |
| 1 | standard_inbound | STOWED | 100.0 | 170.4 | 209.6 | 0 | 1 / 0 |
| 2 | near_outbound | STOWED | 150.0 | 80.0 | 116.6 | 0 | 0 / 1 |
| 2 | standard_inbound | STOWED | 150.0 | 159.4 | 197.8 | 0 | 1 / 0 |
| 5 | near_outbound | STOWED | 100.0 | 89.4 | 131.0 | 0 | 0 / 1 |
| 5 | standard_inbound | STOWED | 100.0 | 159.3 | 202.2 | 1 | 1 / 0 |
| 14 | near_outbound | STOWED | 100.0 | 88.6 | 119.3 | 0 | 1 / 0 |
| 14 | standard_inbound | STOWED | 100.0 | 109.3 | 141.3 | 0 | 0 / 1 |

Complete: True

The public recovery-site assessment checks the nominal final terrain corridor only. Its UI warning is advisory and does not change landing permission, steer the carrier, or guarantee the whole recovery circuit is clear. Raw events, placement validation and error counts are retained alongside this report.

## Corridor checks during recovery

| Aircraft | Clear samples | Obstructed samples | Unknown samples | Script errors |
| --- | ---: | ---: | ---: | ---: |
| 1 | 69 | 0 | 0 | 0 |
| 2 | 63 | 0 | 0 | 0 |
| 5 | 67 | 0 | 0 | 0 |
| 14 | 55 | 0 | 0 | 0 |
