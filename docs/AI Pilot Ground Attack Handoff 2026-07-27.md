# AI Pilot Ground-Attack Handoff — 2026-07-27

## Immediate objective

Replace the current split horizontal/vertical ground-attack route follower with coherent 3D flight-path guidance. The next test focus is gun strafing, but the solution should be shared by bombs and rockets where appropriate.

Do not start by retuning gun aim. Gun accuracy is currently adequate; ingress, repositioning, altitude control, and terrain survival are the limiting problems.

## Current architectural finding

Attack waypoints are stored as `Vector3` values, not usually as `Node3D` scene nodes. Flight-plan legs are dictionaries containing a 3D `position`, role, speed, capture radius, and turn radius. See `AI/AIPilot.gd`, especially:

- `set_flight_plan_legs()` near line 16611
- `_follow_waypoint_route()` near line 17660
- `_navigate_to_waypoint()` near line 12244
- ground-attack plan construction near line 3777

Despite carrying 3D positions, ordinary navigation is effectively 2.5D:

- X/Z route geometry supplies horizontal bearing, Dubins arcs, cross-track guidance, and desired bank.
- Y supplies a separately calculated desired vertical speed and pitch correction.
- Terrain routing largely creates horizontal geometry and assigns terrain-safe Y values to it.
- The route follower now derives a 3D pitch look-ahead point and slope, but lateral and vertical demands are still substantially independent.
- Fine gun/rocket aiming in `ATTACK_DIVE` does use a true local-space 3D line of sight.

This separation can demand a steep bank and a climb simultaneously without deriving one physically consistent lift vector. It is a likely cause of excessive climbing, vertical oscillation, low-energy turns, rejected approaches, and some terrain impacts.

## Proposed next implementation

For each active route leg/look-ahead point:

1. Derive a desired 3D flight-path direction from the route tangent plus cross-track capture and vertical path slope.
2. Compare that direction with the actual 3D velocity/flight-path vector, not merely body heading or waypoint bearing.
3. Convert the required acceleration into one coherent command:
   - lateral acceleration determines bank direction and magnitude;
   - vertical acceleration and gravity determine required lift magnitude;
   - bank and wing load come from the same acceleration vector;
   - pitch/elevator tracks the required load/flight-path correction with rate damping;
   - rudder remains for coordination or deliberate fine correction, not as a substitute for banking.
4. Preserve terrain protection and weapon-specific terminal/release logic.
5. Begin by using this only during `ATTACK_POSITIONING`; do not rewrite landing or dogfight control in the same change.

Avoid introducing another collection of fixed bank, pitch, or altitude magic numbers. Prefer geometry, measured velocity, achievable acceleration/load, terrain clearance, and time/distance-to-go.

## Ground-attack behavior already implemented

- Ground-attack route construction evaluates multiple ingress headings, terrain obstruction, turn reachability, attack setup, and egress.
- Routes use heightmap planning, fly-by/projection guidance, turn-radius-aware capture, and reciprocal corridor reuse.
- Assertive attack turns and arc primitives were added so combat pilots can use substantial bank and G instead of the former approximately 1.2–1.6 G turns.
- Guns and rockets now share the strafing ingress/setup profile through `_is_strafing_ground_attack_weapon_type()`.
- Guns lock the planned setup altitude like rockets, use the permissive strafing envelope, and hold the trigger once firing begins until the run ends.
- Rockets use a weapon-specific shallow ballistic profile and release waypoint; bombs do not.
- Bombs use shared corridor/pathfinding but retain bomb-specific setup altitude, CCIP, release, and dive logic. Bomb positioning still recalculates setup altitude and uses the older non-strafing descent clamp, so isolated bombing should be retested later.

## Latest verified gun test

Scenario: repeating isolated ground-attack waves, weapon focus `Guns`, two Aircraft_5 aircraft, four unarmed dummy turrets per wave, unlimited ammunition, no attack timeout or recovery phase.

Permanent log:

`C:\Godot projects\Project-Flight\gun_rocket_profile_visible_20260727_173558.log`

Terminal result at simulated `t=906.1` seconds:

- Wave 1: 4/4 ground targets destroyed.
- Wave 2: 0/4 destroyed before termination.
- 7 firing passes.
- 20 recorded direct-hit events.
- 6 miss reports of 25 rounds each: 150 explicitly recorded missed rounds.
- Both friendly aircraft crashed into terrain.
- Friendly 2 terrain impact at `t=756.5`.
- Friendly 1 terrain impact at `t=906.1`.
- Test terminal line: `COMPLETE friendly strike flight eliminated before ground targets were destroyed`.

Interpretation: once established on a firing run, gun aim is effective. The first wave was eventually cleared, and the last three kills came relatively close together. Overall performance remains unacceptable because reaching usable attack paths took almost fifteen simulated minutes and both aircraft were lost to terrain.

Recurring telemetry symptoms included:

- repeated `outside_setup_range`, `bad_attack_line_heading`, `bad_target_heading`, and `turn_unsettled` gates;
- attack-positioning banks commonly around 75–90 degrees;
- approach altitudes commonly 500–900 m AGL and occasionally much higher;
- substantial climb/descent commands while simultaneously following aggressive horizontal arcs;
- low-speed/high-altitude excursions followed by steep descents;
- terrain impacts during post-attack or repositioning flight, despite `terrain_emergency` behavior.

## Test and runtime files

- `Scenario/carrier_isolated_gun_attack_test.json` — repository gun-focused scenario.
- `Scenario/carrier_isolated_ground_attack_test.json` — shared isolated ground-attack scenario.
- `Scenario/CarrierCombatTestMode.gd` — repeating-wave test and telemetry.
- `Scenario/ScenarioManager.gd` — loads runtime `weapon_focus`.
- Runtime selection file: `C:\Users\jonto\AppData\Roaming\Godot\app_userdata\Land Carrier\physical_test_scenario.json`.
- Main implementation: `AI/AIPilot.gd`.
- Earlier investigation history: `docs/Turn Authority Investigation.md`.

The completed visible run used Godot PID `32520` and the log above. Verify current process state rather than assuming that PID still exists in a future session.

## Working practices and cautions

- The worktree is intentionally very dirty and contains extensive user work plus many untracked test artifacts. Do not reset, clean, discard, or broadly reformat unrelated files.
- Preserve every existing test log. New runs must use new timestamped log filenames.
- After changing AI behavior, the user prefers the visible test to be restarted without asking again.
- Use `C:\Godot\Godot_v4.6.2-stable_win64.exe`, project path `C:\Godot projects\Project-Flight`, and scene `res://Main_Scene.tscn` for visible runs.
- Stop only the exact test process being replaced; do not stop Godot editor processes or unrelated Godot processes.
- Check parser/script errors before starting a visible test.
- Terrain should remain deterministic, and the carrier should stay stationary after it has been placed in a validated legal launch position.
- Do not overstate conclusions from incomplete telemetry. Avoid double-counting duplicate `[CombatLog]` copies; use canonical `[CarrierCombatTest]` lines for test statistics.

## Recommended first action in the new session

Read this handoff and inspect the route look-ahead/arc guidance around `_update_route_maneuver_waypoint()`, `_update_route_arc_primitive_guidance()`, and `_navigate_to_waypoint()`. Design the smallest `ATTACK_POSITIONING`-only 3D acceleration/lift-vector path that can replace the competing horizontal bank and vertical-speed pitch demands. Then parser-check, restart the isolated visible gun test with a new log, and compare time-to-first-pass, kills per minute, altitude envelope, gate rejections, and terrain survival against the run above.
