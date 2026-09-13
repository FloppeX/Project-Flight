# Wire reachability versus instantaneous capture

## Evidence and scope

Completed baseline: isolated suite `random_rtb_20260908_224209_seed_20260908`.
Matched starts and input hashes passed. Aircraft 1 caught 5/10 (23 wave-offs),
Aircraft 2 10/10 (3 wave-offs), Aircraft 5 9/10 (27 wave-offs). All catches were
stopped recoveries without recorded body/part damage. No simulated aircraft
crashes; all three engine processes crashed on shutdown after saving results.

The escape-deadline gate used `predicted_viable_wire_number == 0` as evidence
that no landing was reachable. But this is a constant-velocity projection, not
a prediction of the pilot's future corrections. Aircraft 1 rejected crossings
with 4.8–4.9 seconds remaining, roughly -2.5 to -3 m vertical error, and only
3.3–3.4 m/s descent. A small bounded correction can eliminate that linear miss.
Aircraft 5 often rejected near the 0.8 m wire tolerance boundary. These logs
identify a logic problem; they do not establish that every old abort was false.

## Implemented change

- Separate instantaneous capture from feasible corrected interception.
- Test each future wire after 0.6 seconds of actuator response. Intersect the
  acceleration needed to reach wire height with the available acceleration and
  acceptable terminal descent intervals. Lateral correction is also bounded.
- Upward acceleration uses current estimated useful lift and bank, discounted
  by 0.65 and capped at 4 m/s². Downward correction is capped at 2 m/s². Lateral
  correction uses the existing profile limit. These are decision-model bounds,
  not added forces or increased player/AI control authority.
- The escape deadline now requires evaluated, unreachable wire geometry, not
  simply the absence of an instantaneous predicted catch. Incomplete geometry
  is unknown rather than proof of impossibility.
- Keep existing stern/lateral, high-miss, terrain, actual catch and bolter guards.
- Log explicit WAVE_OFF_DECISION reasons and include reachability in outcome
  summaries. Physics, aircraft profiles, cables, hook geometry and flap strength
  are unchanged.

This is a bounded kinematic feasibility approximation, not a full flight-model
rollout. It does not model wheel contact/suspension support or guarantee that
the current controller will execute the feasible correction. Those limitations
must be judged against the next logged run rather than hidden with tuning.

## Verification and new batch

PASS: WireReachabilitySmoketest, GoAroundResponseSmoketest (including corrected
versus uncorrectable misses at the escape deadline), LandingSightSmoketest and
RandomRTBBatchSmoketest. Existing shutdown resource warnings remain separate.
Scoped git diff whitespace validation passed.

Started main-project headless suite `random_rtb_20260908_235013_seed_20260908`,
runner PID 4716, at 23:50:13. Ten trials each for Aircraft 1/2/5, seed 20260908,
900 seconds per case, same random-start protocol. User confirmed project edits
will pause, so no separate project copy was made. Input hashes remain enforced.

Logs/results: `C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier`.
Runner output: `reachability_20260908_235013.stdout.log` and `.stderr.log`.

Comparison of the 27 baseline input hashes against this launch found differences
only in the two edited AI files and project.godot (the prior copy's private user
directory settings). No tracked aircraft/carrier/terrain input difference was
found. Runtime settings live in the main user directory again, so this is not
a claim of bit-for-bit deterministic execution across the two environments.

Completed: 9/10 stopped catches for each model, 27/30 total, zero timeouts.
All 27 stops were clean. The three remaining crashes were before deck contact;
see RECOVERY_TERRAIN_ESCAPE_2026-09-09.md for their diagnosis and follow-up.
Input hashes and paired starts verified. All three engines crashed during
shutdown after writing complete results, retained as infrastructure warnings.
Success still requires a wire catch followed by two seconds continuously below
1.5 m/s, with damage reported separately.
