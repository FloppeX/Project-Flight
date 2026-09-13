# Matched airborne RTB batch: Aircraft 1, 2 and 5

## Purpose and frozen baseline

Run ten airborne return-to-base orders per airframe, using the same ten seeded
starts for each model. This is an evaluation batch, not a genetic tuning run.

Aircraft 1 and 2 now carry Aircraft 5's landing/recovery pilot exports, including
energy-aware throttle, acceleration-based lateral guidance, early landing sight,
bounded pitch/AoA correction, high-path capture, high-miss wave-off, stronger
press-final authority, and a 20-second retry cooldown. The -3 m desired hook
crossing target and other numerical controller settings are copied as a common
initial baseline, not claimed to be optimal for these different airframes.

Aircraft 2 also receives the landing-configuration drag/lift multipliers already
present on 1 and 5: gear 1.5, flaps drag 3.55, flaps lift bonus 0.13. Mass, clean
flight aerodynamics, control-surface powers, gear geometry, hook geometry, and
colliders remain airframe-specific. The shared physics-shape-index collision fix
already applies to all three.

## Protocol

- Runner: `tools/run_random_rtb_batch.ps1`.
- Suite: `random_rtb_20260908_111322_seed_20260908`.
- One aircraft at a time; ten trials of Aircraft 1, then 2, then 5.
- Dedicated start-generator seed 20260908, independent of scene RNG consumption.
- Horizontal positions sampled uniformly by area inside an 8 km disk around the
  carrier; height sampled uniformly from 500 to 1,000 m above the deck.
- Level flight, zero bank and vertical speed, 90 m/s; random heading relative to
  the inward bearing. Bombs removed consistently, other authored equipment kept.
- Require at least 100 m terrain clearance. Resample an invalid position instead
  of silently clamping it above the requested altitude range. Accepted candidate
  and actual initial AGL are recorded, and paired manifests are checked afterward.
- Standard scenario-5 stationary carrier, with its existing terrain-clear
  approach staging. This does not test arbitrary carrier placement or motion.
- Issue the normal `return_to_base()` command after aircraft initialization;
  no prepared turn-in, teleport-to-final, or direct control injection.
- Normal retries continue. A 900-second simulated elapsed limit includes queue
  and retry holds, preventing idle holding from extending a trial indefinitely.
- A successful landing requires wire engagement followed by two continuous
  seconds below 1.5 m/s relative to the carrier. Health and damage are separate
  outcomes. Automatic deck recovery assistance is excluded; stow is not tested.
- Headless Godot 4.6.2, fixed 60 Hz simulation. A wall-clock process limit is
  an infrastructure failure, not a scored aircraft timeout.
- Input snapshots and separate process stdout/stderr logs are archived under
  `user://random_rtb_20260908_111322_seed_20260908*`. The combined JSON includes
  every starting condition, terminal outcome, duration, retries and touchdown data.

## Verification

- `RandomRTBBatchSmoketest`: passed (three matching landing/recovery profiles,
  deterministic model-independent starts and requested position/height bounds).
- `LandingTestHarnessSmoketest`: passed after updating old Aircraft-1-default
  expectations to the newly requested common baseline.
- `LandingRecoveryReliabilitySmoketest`: passed.
- `AircraftCollisionShapeLookupSmoketest`: passed across 15 models / 30 collider
  configurations, 264 gentle wheel contacts and 124 body-contact checks.

## Infrastructure note

Aircraft 1 wrote all ten outcomes and the complete structured result, then Godot
crashed during shutdown (signal 11, process exit -1073741819, renderer cleanup
errors). These completed observations were preserved; they were not relabelled
as an aircraft failure or silently rerun. The runner was made resumable with
input-hash verification and explicit post-result engine-crash reporting, then
continued with Aircraft 2. Pilot, physics and harness inputs remained unchanged.

Aircraft 2 and 5 also exited with the same post-result engine crash. No GDScript
parse errors, invalid calls, or script runtime errors were found in their stderr
logs; existing ComputerStation startup errors and renderer/shutdown warnings
remain. This is a completed simulation batch, not a clean engine-exit test.

## Results: all 30 trials completed

Paired start position, heading, deck-relative altitude, accepted candidate and
initial terrain clearance match across all three airframes (1 mm tolerance).
All ten sampled starts used candidate 0. Actual ranges were 636–7,269 m from the
carrier and 584–951 m above deck. Snapshot hashes confirm that pilot, physics,
aircraft scenes and harness inputs stayed unchanged through the run.

| Aircraft | Wire catches | Sustained stops | Crash/contact failures | Timeouts | Mean successful RTB | Successful time range |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 6 | 5/10 | 5 | 0 | 164.0 s | 130.0–225.7 s |
| 2 | 7 | 7/10 | 2 | 1 | 256.5 s | 121.8–476.5 s |
| 5 | 5 | 5/10 | 5 | 0 | 171.8 s | 147.3–206.2 s |

All **17 sustained stops retained full health and recorded zero damage**. Five
Aircraft-2 stops and one Aircraft-5 stop had a HARD touchdown classification;
hard contact does not automatically mean damage.

The raw harness labels all contact/crash failures `CRASH`. Aircraft-5 case 9
ended on a 3.7 m/s body-contact crash signal with no recorded damage and unknown
terminal health (`last_health=-1`). It is **not confirmed destroyed**. Four other
Aircraft-5 failures, all five Aircraft-1 failures, and both Aircraft-2 failures
record zero health. Do not interpret the table as twelve confirmed explosions.
The timeout also has unknown terminal health, not evidence of zero health.

| Matched case | Radius, m | Height above deck, m | Heading off inward bearing | Aircraft 1 | Aircraft 2 | Aircraft 5 |
| --- | ---: | ---: | ---: | --- | --- | --- |
| 1 | 2147 | 584 | -106° | Stop | Stop | Stop |
| 2 | 4591 | 842 | -135° | Crash | Crash | Stop |
| 3 | 7269 | 757 | -147° | Stop | Stop | Stop |
| 4 | 4481 | 626 | +176° | Crash | Stop | Crash |
| 5 | 2219 | 808 | -165° | Crash after catch | Stop | Crash |
| 6 | 4730 | 951 | +101° | Crash | Crash | Crash |
| 7 | 7185 | 606 | -23° | Crash | Timeout | Stop |
| 8 | 2060 | 601 | -93° | Stop | Stop | Crash |
| 9 | 1939 | 627 | -73° | Stop | Stop | Contact failure; destruction unconfirmed |
| 10 | 636 | 876 | +125° | Stop | Stop | Stop |

## What the logs suggest

### Aircraft 5: deck-entry clearance before more tuning

All ten reached final; the five failures were cases 4, 5, 6, 8 and 9, all before
a wire catch. Contact records cluster at carrier-relative longitudinal position
75–79 m on the approach side, near the stern, with lateral offsets about 11–16 m.
This is a tighter and more actionable failure cluster than a generic RTB problem.

- Several failed approaches predicted hook/deck-plane intersections **32–54 m
  short of the target wire**. Successful examples near engagement predicted about
  **11–20 m short**. Hook and gear deck-intersection times were similar where both
  were valid. These are predictions, not exact measured touchdown positions.
- Case 4 still had **18.5 m/s sideways velocity** at 17 m remaining. It touched a
  wheel normally, then failed before catching. Position-only alignment would miss
  this dangerous momentum.
- Cases 5 and 6 were already about **16 m off centerline**, despite relatively
  small remaining sideways speeds; fixing velocity alone would not fix these.
- Case 9 was below deck height near the stern when the contact signal ended its
  trial. Its outcome should not be conflated with confirmed destruction.

**Recommended next slice:** reproduce these five fixed cases on Aircraft 5;
instrument the contacted aircraft shape and carrier collider; then constrain the
predicted gear/body footprint to clear the finite stern and deck edges before
optimizing the wire crossing. Couple that with earlier lateral braking. Do not
simply increase sink, extend the hook, or lower the hook target further. The
current -3 m crossing bias merits a controlled A/B test, but this batch alone does
not establish that it is the root cause.

### Aircraft 1: recovery-turn terrain clearance

Cases 2, 4, 6 and 7 failed in RECOVERY_APPROACH before PRE_LANDING. Their final
terrain samples were at or below nearby terrain/low AGL. Three clustered around
carrier-relative x=963–1198 m, z=1121–1219 m, consistent with a repeatable bad
recovery corridor. Peak banks in these cases were roughly 80–83 degrees.
These values are observed peaks, not configured bank limits, and do not alone
prove the causal control error. Case 5 instead caught a wire and then crashed
during arrestment. That should be investigated separately from route capture.

### Aircraft 2: failed escapes and inefficient turn capture

Cases 2 and 6 crashed after wave-offs; case 7 timed out after a wave-off and long
recovery/hold behavior. The timeout was 900 s total, including about 145 s in hold.
Case 10 eventually stopped after 446 s but first ranged 9.09 km from the carrier
despite spawning only 636 m away. Its route telemetry included about 50 degrees
of bank at 39 m/s with available load near 1 g. That points toward an
airframe-aware speed/lift constraint in turn capture; it is not proof that a lower
fixed bank limit alone is the solution.

## Data and reproducibility

Combined JSON and per-model stdout/stderr are in:

`C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier\random_rtb_20260908_111322_seed_20260908.json`

Use each case's `entry.distance_m`, `entry.radial_deg`, `entry.offset_x_m`,
`entry.offset_z_m`, and `entry.alt_m` for random-start geometry. The top-level
case `behind_m` / `lateral_m` fields are legacy straight-final fields and should
not be treated as the random start's actual longitudinal/lateral coordinates.
`maximum_bank_deg` can include post-contact motion; it is not a clean measure of
maximum commanded approach bank. `last_health=-1` means not sampled, not dead.

Run a new batch with:

```powershell
./tools/run_random_rtb_batch.ps1 -Seed 20260908 -CasesPerModel 10
```

Validate/rebuild the completed aggregate without spawning more aircraft:

```powershell
./tools/run_random_rtb_batch.ps1 -ResumeSuiteId random_rtb_20260908_111322_seed_20260908
```

Resume refuses changed snapshot inputs or incomplete existing model logs instead
of silently overwriting or rerunning them. The seed reproduces the starts, not a
guarantee of bit-identical asynchronous navigation or physics timing. Ten paired
cases at one staged carrier location are diagnostic evidence, not a statistically
robust fleet-wide reliability estimate, and no pre-change A/B batch was run here.
