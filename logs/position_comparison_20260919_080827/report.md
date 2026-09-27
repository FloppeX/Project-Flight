# Carrier-position comparison

Aircraft 5; two arrival profiles at each of two positions. Wind field disabled in both, same carrier heading, shared above-deck spawn height, speed and relative heading. Authored flight-control settings unchanged. Physics runs at 60 Hz, uncapped headlessly.

| Position | Arrival | Outcome | Caught | Stowed | Duration s | Missed approaches |
| --- | --- | --- | --- | --- | ---: | ---: |
| obstructed | near_outbound | TIMEOUT | False | False | 901.0 | 6 |
| obstructed | standard_inbound | TIMEOUT | False | False | 901.0 | 3 |
| clear | near_outbound | STOWED | True | True | 536.0 | 4 |
| clear | standard_inbound | STOWED | True | True | 239.0 | 0 |

## First handoff attempt per arrival

| Position | Trial | Decision | Vertical error m | Lateral error m | Track error deg | Bank deg |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| obstructed | 1 | rejected | 307.4 | -16.3 | 23.1 | 16.3 |
| obstructed | 2 | rejected | 302.0 | 25.8 | 8.7 | 12.3 |
| clear | 1 | rejected | 63.5 | -147.0 | 25.7 | 16.4 |
| clear | 2 | press | 69.8 | -38.3 | 6.7 | 10.7 |

Position validation must show obstructed=false and clear=true for corridor_clear. The clear site is near (-144, 525, -2375); the obstructed site is near (-21, 522, 2). This is a four-attempt placement comparison, not a fleet reliability estimate or exact checkpoint replay. A clear nominal final corridor does not guarantee an aligned arc exit, a clear entire recovery circuit or successful flight control. Timeouts are 900 simulated seconds per uncaught attempt. Raw results, placement checks and handoff measurements are in summary.json.

## Interpretation

Both obstructed-site attempts timed out without a catch; both clear-site attempts caught the wire and stowed at full health. First final-handoff attempts at the obstructed site were 302-307 m above target. This supports carrier placement as a major contributor to the earlier batch failures, but does not establish impossibility at that site or fleet-wide reliability. The clear near-outbound arrival still required four missed approaches, and both successful arrivals used permissive press handoffs rather than strict handoffs. Validate the carrier recovery corridor before repeating fleet tests, then address remaining alignment and recovery-duration issues.

Both workers completed and exited. Neither recorded a SCRIPT ERROR. SHA-256 checks confirmed AIPilot.gd, LandingSight.gd and SimpleAero.gd were unchanged during this experiment. Raw JSONL and status files are retained alongside this report.
