# Fleet recovery regression after flap wiring fix

## Scope

User requested a modest rollback of Aircraft 2's recent handling boost, then a
complete Aircraft 1/2/5 comparison. Halved only that boost:

| Aircraft 2 parameter | Before boost | Boosted | This run |
| --- | ---: | ---: | ---: |
| Roll power | 8.5 | 10.2 | 9.35 |
| Yaw power | 2.4 | 3.0 | 2.7 |
| Roll surface rate /s | 4.2 | 4.8 | 4.5 |
| Yaw surface rate /s | 3.0 | 3.5 | 3.25 |

Shared flap detection, gear-independent flap commands, early centerline capture,
bounded lineup acceleration, and go-around fixes remain in place. Mass, thrust,
pitch handling, drag coefficients, and damage settings are unchanged. The optional
extra forward configuration-drag scale remains 1.0; restored authored flap physics
provides the actual drag increase compared with the old broken flap detection.

## Test protocol

Final headless suite: `random_rtb_20260908_215155_seed_20260908`.
Original visible suite: `random_rtb_20260908_214433_seed_20260908` (interrupted).

- 10 matched terrain-accepted starts per model, 30 total, seed 20260908.
- Aircraft 1, then 2, then 5; sequential spawns.
- 500–1000 m above carrier, within 8 km, random headings, 90 m/s initial speed.
- Stationary staged carrier; removable stores removed as in the prior batch.
- Headless, fixed 60 Hz simulation with rendering disabled, per user request
  during the original visible run. Restarted all 30 cases; do not pool modes.
- Ordinary RTB/recovery, including retries; no forced final or wave-off.
- 900 s attempt timeout, including deck queue time. Success requires a wire catch and two seconds
  continuously below 1.5 m/s. Damage and touchdown severity are separate fields.
- Tests airborne return through stopped recovery, not launch or hangar stowing.
- Process-specific stdout/results and input snapshots/hashes retained. No flight
  settings are to be changed while the batch runs.

Added `-Visible` to the existing batch launcher and a presentation-only observer
flag to scenario 5, without converting random RTB starts into prepared finals.
The observer waits for loading to finish and labels the aircraft model/case.
The visible run completed Aircraft 1 case 0: stopped catch in 212.8 s, no retries,
zero health damage, HARD 3.3 m/s touchdown. Case 1 was interrupted. Preserved all
logs and stopped only the known runner/test processes before restarting headless.

Preflight checks PASS: RandomRTBBatchSmoketest and LandingFlapWiringSmoketest.
Existing resource/wing-node warnings remain separate from these PASS results.

## Results

Partial only: Aircraft 1 completed all 10 cases. Aircraft 2 and 5 did not start.
The runner stopped at its post-model input-integrity check: `LandCarrier2.tscn`
and `LandCarrier.gd` changed during the run (defense-position/loadout integration,
last-write time 22:13:21). Those external edits were preserved. Do not pool this
run with later models or claim a complete controlled fleet comparison.

| Aircraft 1 result | Count |
| --- | ---: |
| Stopped wire catch, no recorded body/part damage | 5 |
| Timeout without touchdown | 5 |
| Aircraft crash / arrest failure | 0 |
| HARD / NORMAL touchdown among catches | 4 / 1 |

Completed catches were cases 1, 2, 4, 6, 9 (zero-based), taking 393.85, 846.62,
671.47, 348.83 and 263.63 seconds respectively. All ten cases recorded zero body
and part-health damage; total wave-offs 23, bolters 0. Only two cases caught on
their first approach. This suggests repeated approach rejection remains a more
prominent limitation than touchdown destruction in this sample. Repeated
`unreachable wire/deck crossing` outcomes warrant checking predicted clearance
against actual trajectories, but do not by themselves establish false alarms.

Infrastructure warning: Godot wrote the complete Aircraft 1 result and then
crashed during shutdown (signal 11, exit -1073741819), following dummy-renderer
resource cleanup errors. No SCRIPT ERROR or Parse Error was found in its stderr.
The engine shutdown crash is separate from the zero simulated aircraft crashes.
Input changes and shutdown failure are separate observations; causation is not
established. Process-specific logs, per-case results and original snapshots are
preserved under the suite ID above. The suite is marked HALTED_INPUT_DRIFT.

Next: establish a frozen test workspace (or pause concurrent carrier edits),
then restart the complete headless comparison. Do not infer fleet reliability
from either this partial batch or the earlier two prepared Aircraft 2 starts.

## Isolated restart (22:42)

User approved a separate test copy. Started a fresh complete batch, not a resume:
`random_rtb_20260908_224209_seed_20260908`.

- Frozen project: `C:/Godot projects/Flight-Recovery-Tests/rtb_20260908_2242`.
- Private user data and results: `C:/Users/jonto/AppData/Roaming/FlightRecoveryTests/rtb_20260908_2242`.
- Runner PID at launch: 47928. Runner stdout/stderr are in that private data folder.
- Actual independent copies of source and imported assets, approximately 1.70 GB;
  no links back to mutable project files. Excluded history, logs and capture caches.
- Copied current working tree, including current carrier changes. Only copy-local
  project user-directory configuration and the runner output directory were adjusted.
- Copied settings.cfg into private user data; no live saves or old test results.
- RandomRTBBatchSmoketest and LandingFlapWiringSmoketest PASS in this copy.
- Aircraft 1 case 0 is confirmed spawned and producing live flight telemetry.
  No script/parse/load failure or engine crash was found in the startup check.
- Unchanged protocol: 10 cases each for Aircraft 1, 2 and 5; seed 20260908;
  500–1000 m / within 8 km / 90 m/s; 900 s per case; headless fixed 60 Hz.

The detached runner automatically advances through all three models and writes
the final suite JSON after checking matched starts and its 27 input hashes.
Results are pending; this section confirms launch, not completion. Main-project
edits no longer change this test copy. No additional handling tuning was applied.
