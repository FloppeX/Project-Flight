# Land Carrier

This document is the short project brief for Land Carrier. For version history, session summaries, and archived long-form notes, see [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md).

## Brief Description

Land Carrier is a single-player strategic action game inspired by Armourgeddon and Carrier Command. The player commands a massive tracked land carrier across a post-apocalyptic desert, launches aircraft, supports ground units, and balances offense with defense of the carrier itself.

There are no scripted missions. Each scenario is intended to support open-ended problem solving, with the player deciding how to use available aircraft, vehicles, and carrier systems to achieve the objective.

## Core Concept

### Design North Star: An Autonomous Carrier Society

The carrier should feel like a functioning war machine and mobile colony, not a collection of units waiting for player orders. Its operational controllers and crew are expected to act independently: they detect needs, create and assign missions, launch aircraft, conduct patrols and attacks, recover vehicles and pilots, repair and rearm equipment, and reorganize after losses. Normal operations should continue without requiring the player to micromanage them.

The intended division of responsibility is **player intent, autonomous execution**. The player decides what matters; the carrier's people and systems decide how to carry it out. This is also a development direction: new carrier, AirOps, GroundOps, flight-deck, logistics, and personnel systems should strengthen the autonomous operational loop rather than make routine work depend on repeated player commands.

The design should follow **command by exception**:

- The autonomous organization handles ordinary operations and reacts to routine threats.
- The player sets priorities, route, doctrine, acceptable risk, and resource commitments.
- The player is called on when priorities conflict, circumstances become unusual, or consequences are important.
- The player may directly take control of an aircraft, helicopter, turret, vehicle, or other station whenever that is interesting, urgent, or personally meaningful.
- Direct control is an intervention and a source of action gameplay, not a chore required to keep the carrier functioning.

The player's exact fictional office and the final balance between strategic authority and free-form participation remain open design questions. However, the player should not be merely a passenger: some decisions must require their judgment, particularly decisions involving route, sacrifice, diplomacy, scarce resources, and the expedition's values.

### Campaign Direction

The working campaign premise is a long carrier expedition through a sequence of regions or maps, potentially with distinct biomes, in search of a distant safe or utopian territory. Whether that destination exists as promised is deliberately not settled yet. The journey provides direction; the condition and character of the carrier society that arrives should provide much of the meaning.

Each region should create an operational cycle:

1. **Enter:** arrive carrying forward surviving personnel, vehicles, supplies, upgrades, and damage.
2. **Discover:** scouts and sensors reveal terrain, weather, settlements, resources, routes, and enemy activity.
3. **Choose intent:** the player selects broad priorities such as advance, avoid contact, obtain fuel, rescue people, protect a settlement, or remove a strategic threat.
4. **Operate:** autonomous controllers turn those priorities and the current sensor picture into patrols, strikes, escorts, rescues, logistics, recovery, and repair work.
5. **Respond:** unexpected threats and conflicting needs create exceptional decisions; the player may revise priorities or intervene directly.
6. **Recover and adapt:** the carrier deals with fatigue, casualties, damage, ammunition, fuel, experience, and new people or capabilities.
7. **Move on:** the player chooses when and how to leave, usually without enough time or resources to solve every problem in the region.

Meaningful play should come from competing priorities rather than unit-level busywork. Committing aircraft to a strike can weaken carrier defense; waiting for repairs can allow enemies to reinforce; rescuing a pilot can risk more lives; helping a settlement can consume time but earn people, knowledge, or supplies. Policies and doctrine should let the player express intent without approving every launch, weapon choice, or repair.

This campaign structure is a target, not a claim about what is already implemented. Near-term systems may remain sandbox-oriented, but they should be built so they can eventually participate in this persistent autonomous expedition loop.

### Planned Campaign Ending (Design Spoilers)

The expedition is trying to reach a mythical safe settlement said to have forests, streams, and abundant plant life. For most of the game, the desert contains very little vegetation. As the carrier approaches its destination across the later regions, the environment should quietly validate the stories: isolated hardy plants become more common, followed by patches of grass, damp ground, running water, and increasingly green terrain. This progression should create genuine hope without revealing the final destination too early.

When the expedition finally reaches the promised location, it finds a ruined and abandoned city rather than the sanctuary it expected. The discovery should initially feel like the failure of the myth and the loss of the destination that sustained the journey.

Beyond the ruins, however, the crew encounters something larger and more majestic than the promised city: the ocean. This should be the first clear sight of the sea in the game, ideally preceded by subtle sensory clues such as unfamiliar wind, gulls, moisture, or distant surf. The reveal changes the ending from arrival to possibility.

In the final sequence, the land carrier is modified so that it can enter the water. It drives into the sea, floats, and jettisons its enormous tread assemblies. The former land carrier has become a true carrier ship. Carrying the surviving society and everything it has become during the campaign, it sails toward the horizon and a new frontier, leaving room for a sequel.

The ending's thematic purpose is that utopia is not a finished place waiting to be discovered. It is the community the expedition preserved and shaped during the journey. The ruined city can still provide knowledge, seeds, records, materials, infrastructure, or other evidence that its promise was once real, so reaching it is not meaningless even though it is no longer a sanctuary.

The carrier's ability to survive the conversion should be foreshadowed enough to feel surprising but credible. Possible foundations include a sealed or ship-derived hull, dormant marine systems, old plans, or conversion infrastructure found near the city; the exact explanation remains open. These clues should not reveal the ocean or the final transformation prematurely.

### Aesthetic Vision

The project aims for a low-poly, flat-shaded look with an old-school Amiga feel.

### The World

The setting is a desert wasteland with mesas, cliffs, ruins, rock formations, fortified enemy positions, and resource locations. Weather is planned to matter to gameplay through turbulence, wind, and reduced visibility during dust storms.

### The Carrier

The land carrier is the centerpiece of the game: a 200-meter-long tracked mobile fortress that serves as command center, airbase, logistics hub, and home. It carries aircraft, ground vehicles, elevator and catapult operations, arresting gear, tractor bots, defensive turrets, and an estimated complement of 250-350 souls - crew and their families. A folding rear ramp deploys for ground vehicle operations.

### Player Units

Aircraft, helicopters, ground vehicles, defenses, and carrier stations can provide direct action gameplay, with aircraft remaining the primary player-flown vehicles. They are nevertheless AI-first participants in the carrier's autonomous operations: the player can take control when desired without becoming responsible for their routine execution. Vehicles are meant to be modular, upgradeable, recoverable, and part of the player's wider strategic plan.

### High-Level Gameplay Loop

The carrier expedition advances through dangerous regions while its autonomous organization scouts, launches and recovers aircraft, protects the carrier, attacks threats, and manages routine logistics. The player chooses direction and priorities, resolves consequential conflicts, intervenes directly when desired, and gradually shapes the expedition through resources, repairs, personnel, doctrine, and upgrades.

## Current Status

**Last Updated:** 2026-07-16
**Godot Version:** 4.6.2.stable.official.71f334935
**Project Health:** PLAYABLE
**Control Mode:** AI-by-default with viewed-aircraft player/AI toggle (game controller + keyboard parity in pause/menu flows)
**Active Carrier Scene:** `LandCarrier2.tscn` (the new carrier) — instanced by `Main_Scene.tscn`.
**Recent Focus:** Air-combat AI (dogfight gunnery + energy), the AirOps/Citadel dynamic tasking brain, and battlefield readability (map fog-of-war, combat event log). See the 2026-07-16 changes below.

## Control And AI Design Rule

This project should prefer feedback-loop systems over hidden hard limiters.

Do not add secret caps, clamps, safety gates, speed limits, input limiters, altitude bands, or forced slowdowns as a first-line fix for unstable aircraft, helicopters, vehicles, or weapons. Those often create contradictory control goals: one system asks for full power, another silently caps pitch or lift, another reduces speed near a waypoint, and the vehicle starts oscillating, stalling, hovering, or crashing for reasons that are very hard to see from playtesting.

Hard bounds are acceptable only when they represent a real physical range or engine/API requirement, such as normalizing an input to `-1..1`, keeping throttle in `0..1`, preventing invalid array indexes, or enforcing actual authored vehicle capability. They should not encode behavior policy unless the policy is explicit, documented, visible in debug output, and has been chosen deliberately.

For AI pilots and vehicle controllers, the expected approach is:

- Decide what the vehicle is trying to achieve: target path, target altitude, desired climb/sink rate, desired heading, desired energy state.
- Use measured response to adjust controls through clear feedback loops.
- Let full control authority be available when the feedback loop calls for it.
- If the vehicle overreacts, fix the loop: gains, damping, prediction/lookahead, reference frame, path choice, or physical tuning.
- If a limiter is truly needed, name it honestly, expose it as tuning, print/debug when it activates, and explain why a feedback fix is not enough.

This is especially important for helicopters. They have delayed response and strong coupling between collective, cyclic, speed, lift, and altitude. The AI should fly them by making deliberate control changes based on observed response, not by stacking hidden safety barriers that fight each other.

### Recent Changes (2026-07-16)

**Air-combat AI — dogfight gunnery, energy, and behavior.** The AI dogfight was overhauled so fights actually resolve instead of stalemating:
- **Curved (turn-rate) lead gunnery** — the biggest fix. The AI now estimates a target's angular turn rate and propagates its future position along that turn arc (not a straight line), so shots lead a jinking bandit correctly over the bullet's flight time. This converted "positions well but never hits" into decisive kills.
- **Energy realism + discipline** — induced drag now bleeds energy from hard maneuvering (keyed off load factor, since the arcade model keeps velocity aligned to the nose so AoA stays ~0). A pull-cap around corner speed keeps hard turns *sustainable* — a plane can no longer dump 110 m/s → ~10 m/s in one merge pull and mutual-kill while stalled.
- **Anti-stalemate stack** — bug-out when losing badly, scissors-reset when stuck in a co-energy turn fight, a keep-it-low ceiling (fights stay near the deck, readable), a hard dive floor (no more pressing a committed dive into terrain), and a max-extend cap (a plane behind on energy fights instead of running forever).
- **Situational awareness by arc** — pilots detect enemies by arc (front easy, behind/below near-impossible), scaled by skill; a knife-fight range override so a close bandit is never "lost," plus a bounced-from-behind reaction so a plane getting shot re-acquires the shooter.
- **Smart target reprioritization** — pilots no longer fixate on their first pick. Air targets are scored by threat (enemy on your 6) and opportunity (easy kill ahead), not just distance; ground attackers re-evaluate during setup (never mid-dive). Applies to ground attack too.
- **Role posture** — `air_combat_posture` (DOGFIGHTER vs DEFENSIVE): attackers/bombers/fleeing aircraft keep flying their mission and *evade* (defensive jink) instead of dropping everything to turn-fight; they only commit to a dogfight if truly cornered.
- **Sustained fire** — guns hold the trigger on a strong, stable solution instead of always pulsing on a fixed burst/cooldown.
- **Dogfight test harness** (`Scenario/DogfightTestMode.gd`, scenario 4) grew a 1v1 neutral-merge diagnostic mode and auto-restarting rounds with a results log.

**AirOps / Citadel — dynamic tasking brain.** The carrier's `AirOpsManager` was rebuilt from a fixed 3-slot role model (one CAP + one INTERCEPT + one CAS) into a **dynamic mission board**. Each tick it builds tasks from the fused sensor picture (carrier radar + every friendly vehicle's sensors + buildings), **clusters** nearby enemy ground/structure targets into strike areas, scores tasks (defense-first: intercepts outrank strikes outrank CAP), and assigns the nearest available flight — scrambling from the hangar to fill gaps. This supports concurrent strikes + patrol + interception, which the old model could not. Verified end-to-end in the normal game (patrol → detect targets → strike/intercept assignment).
- Radio-bark audit: Citadel now speaks only on a genuine **role change** (CAP/INTERCEPT/STRIKE), not on every target switch within a role, and no longer double-barks on scramble. This fixes the "random, not tied to what's happening" chatter.
- Deck-launch fixes: the deck now pumps a pending AI-launch queue whenever it's free (a scramble arriving during a busy deck no longer queues forever), a stuck scramble times out instead of blocking all future tasking, and **combat scrambles skip utility helicopters** in the hangar (Aircraft 11 rescue helis were being catapulted as fighters at startup — they now stay parked as rescue assets).
- Carrier launch behavior: instead of *holding* launches while the carrier is turning, the carrier now straightens/settles to open a launch window; and a terrain check refuses to launch aircraft straight into a cliff on the departure path.

**Battlefield readability:**
- **Map fog-of-war (lite)** — the tactical map shows everything, but enemies not currently in the friendly sensor picture are drawn in a **muted** version of their real color; they brighten to full color when the carrier radar or a friendly picks them up. Friendlies are always full color. (Tunable; can be toggled off.)
- **Combat event log** — a new lightweight `CombatLog` autoload records *meaningful* events (attacks started, engagements, hits with coalescing so a burst isn't one line per bullet, kills with hit totals, crashes, and flight taskings/launches) to `user://combat_log.txt` with timestamps — not a per-frame trace.
- The bridge **holomap is temporarily disabled** (removed for now; may return later).

**Terrain streaming:** added a fast-fill burst when the view jumps (camera switch / teleport) so terrain appears quickly, then relaxes back to the low steady-state rate that keeps normal flying hitch-free.

### Recent Changes (2026-06-25)

- Carrier performance pass: rear track marks now use a capped `MultiMeshInstance3D` path instead of many individual nodes. Only the rear two treads generate marks, active marks are capped at 240, and marks are opaque/darker with slower stepped fading. Carrier tread plates were reduced to 20 per track and skip plate animation when not on screen.
- Carrier steering pass: the carrier no longer pivots only around its center for turning. Steering now approximates front and rear axle steering with a rear-axle steering ratio and crawl speed for hard turns.
- Dust optimization and behavior: dust and rotor-wash effects are camera/frustum gated so they do less work when unseen. Rotor wash dust now ramps with rotor power rather than spawning at zero/low rotor speed, and dust opacity was increased slightly.
- Modular cockpit instrument panel: `HUD/InstrumentPanel.tscn` now builds its cockpit display from reusable instrument modules. Modules include MFDs, readouts, warning lights, a gear/flap status area, stall and missile-lock indicators, and a first-pass slip ball. Aircraft 5 has an explicit test layout assigned in its `InstrumentPanel.module_layout`.
- Cockpit panel interaction: in cockpit view, looking at the instrument panel projects a small press-dot cursor onto the panel texture. Pressing D-pad down uses that projected point to interact with modules, including cycling MFD modes. Instrument-panel rendering and module updates are view-gated so only the currently viewed aircraft keeps its live panel/target-camera feed active.
- Pilot/ejection visual direction: the active plan is to keep the Rigify/GLB pilot model as the canonical pilot visual. Temporary mismatched FBX visual swaps for parachute hanging and running were removed from the active flow. `PilotPose.gd` now recognizes the current Rigify-style export (`c_pos`, `thigh_fk.l`, etc.) and drives parachute/ground/locomotion poses procedurally on that rig.
- Downed pilot movement: the downed pilot now keeps the original GLB model visible and calls `PilotPose.set_locomotion_pose()` while moving. The current procedural jog/run is a rough placeholder and is expected to need visual tuning.
- Low-poly visual consistency: cockpit pilots and ejection seats now pass through a cached flat-normal conversion path so they better match the project's flat-shaded visual direction. This is implemented via `PilotVisualMaterials.gd`, `PilotPose.gd`, and `FlatShadedVisual.gd`.
- Diagnostics: `tools/run_perf_diagnostic_direct.ps1` can run startup/performance smoke checks with track-mark override settings and frame-profiler override support. Current runs still show existing terrain/render shutdown noise on forced quit; those errors are not yet resolved.

### Recent Changes (2026-06-15)

- Helicopter combat aiming: `HelicopterPilot` runs a dedicated combat layer for Aircraft 9/10/11 attack runs (gun and rocket). An attack plan authors an ingress → fire-start → fire-end → egress route past the target; during the attack phase a PID aim controller (`_get_combat_aim_commands`) corrects pitch/yaw to put the gun/rocket line on a predicted aim point (lead for guns, ballistic + CCIP correction for rockets), then a fire gate (`_is_combat_aim_settled_for_fire`) holds fire until alignment and settle time are met. A structured `heli_combat_report.log` records every shot, result, and no-shot attack run for diagnosis.
- Combat aim reference frame fix: the aim error was being measured from each weapon's off-centerline hardpoint position to the target. Because the flight controller can only rotate the airframe about its center of mass, that left a fixed parallax angle the body could never null out — every gun pass showed a persistent ~2-3° yaw/pitch residual and zero hits. Aim error is now measured from the aircraft centerline (`aircraft.global_position` and the aircraft forward axis), consistent with the fire gate; the ballistic/CCIP prediction still uses the real hardpoint muzzle. This removed the systematic bias and guns began landing hits.
- Gun nose-down authority: guns were starved of the nose-down assistance rockets already had, so the pipper hung just above the target and the firing window passed before the nose arrived. Guns now get a matching pitch-down rate boost (`combat_gun_nose_down_rate_scale`), a higher pitch authority cap (`combat_gun_max_pitch_input`), and a stronger pitch control gain (`combat_gun_pitch_control_gain` 1.65 → 3.2) so the controller actually uses the available authority at the small errors it holds. Per the project rule, these are exposed feedback-loop gains, not hidden limiters.

### Recent Changes (2026-06-10 to 2026-06-12)

- Aircraft 11: new helicopter added (`Aircraft/Aircraft_11.tscn`) with swing doors (`HeliSwingDoors.gd`), animated via hinge nodes, player-toggleable with `O`; doors auto-open after landing idle. Uses the authored Aircraft_11 GLB with tail rotor and rotor disc assets from the Aircraft_9 set.
- Rotor wash dust effect: `Effects/RotorWashEffect.gd` added — pooled 64-puff particle system using a shared mesh/material; spawns dust puffs at terrain contact below 25 m AGL at a configurable spawn interval; distance-culled at 800 m; samples terrain color from the shader; excluded from carrier raycasts.
- Free camera fix: jitter eliminated by decoupling physics and render transforms; trigger buttons now control vertical movement in free cam.
- Helicopter AI: terrain height raycasts now exclude the carrier body so helicopters no longer climb 80–100 m above deck when over the carrier.
- Airborne separation: `HelicopterPilot` gains a new separation system — helicopters brake and push apart when within `airborne_separation_start_m` (90 m) of another helicopter, with speed-based push authority and vertical offset to prevent stacking.
- Threaded pathfinding: `HelicopterPilot` A* pathfinding moved to a dedicated thread (`_run_threaded_pathfinding_job` + static helpers); all grid sampling, wall-cost, and simplification logic now runs off the main thread to avoid frame spikes.
- Turn-speed governor: look-ahead up to 900 m detects sharp turns (> 25° up to 110°) and computes a physics-based speed limit from lateral acceleration budget and turn radius; speed bleeds down before the corner.
- Radar flight route: `HUD/RadarCanvas.gd` now draws the active AI waypoint path as a light-blue polyline on the cockpit radar scope for both `HelicopterPilot` and `AIPilot` aircraft; simplified to skip waypoints closer than 4 px on screen.
- Livery / texture shader: `Shaders/upper_fuselage_test_stripes.gdshader` added — spatial shader with base color, stripe/pattern color, tertiary color, and pattern mode (solid/stripe/check); used for helicopter fuselage texture work.
- FDM landing clearance queue: `FlightDeckManager` now manages a formal `_landing_clearance_queue` so multiple inbound helicopters are serialized; clearance times out after 30 s, retries after 12 s cooldown, and abandons if the requestor flies beyond 6000 m.
- F11 heli test now tracks Aircraft 11: stat recording and test-mode despawn/spawn cover Aircraft_9, Aircraft_10, and Aircraft_11 by key.

### Recent Changes (2026-06-07)

- Helicopter carrier approach overhaul: scripted three-phase approach (TO_APPROACH_POINT → FINAL → DESCEND) now uses 4 authored hold points (`Helicopter Hold Point 1–4`) for queue stacking so multiple inbound helicopters don't bunch up. Hold positions step 100 m further behind and 50 m higher per slot. Gate capture tolerance raised to 20 m height, 45 m radius. Approach drops back to LOW_LEVEL_TRANSIT if it can't catch the moving gate.
- Carrier landing gate collective fix: `_fly_carrier_approach_gate` now uses a dedicated gentle two-loop altitude hold instead of routing through `_calculate_collective` — eliminates the 40 m altitude oscillations caused by the LANDING boost slamming collective to 1.0 and overshooting. Same fix applied to `_fly_carrier_final`.
- Carrier DESCEND phase: now descends at `max_descent_mps` until within flare height, then switches to gentle flare. Pitch authority reduced near the deck so forward speed correction doesn't tilt the rotor disk and accelerate the sink. Landing detection loosened: any gear contact at deck level triggers touchdown regardless of horizontal speed.
- FDM landing queue: `get_landing_queue_position()` method added to FlightDeckManager so each helicopter knows its queue slot and flies to the correct hold point.
- Helicopter pathfinding: A* async job now completes reliably (budget 4000 iterations/frame, 600 m search padding). Path simplifier fixed — clearance check now uses `heightmap_path_target_agl_m` (50 m) not `cruise_agl_m` (55 m), so flat segments actually collapse. Turn waypoints preserved: skip not allowed if any intermediate point involves > 25° turn. `_transit_cruise_altitude_m` bleeds back down at 40%/frame capped at 25 m/s; path descent rate raised to 15 m/s.
- Helicopter pathfinding penalties retuned: `ground_level_band_m` 80 → 35, `first_plateau_min_m` 85 → 40 so first-plateau terrain is correctly classified and preferred. `max_terrain_above_reference_m` 270 → 190, `mountain_avoidance_m` 220 → 185 to block second-plateau routing. `terrain_sample_spacing_m` 45 → 120 for faster simplification.
- 5-feeler terrain probe fan: replaced 2 side feelers with 5 (forward 0°, ±20°, ±50°). Each feeler samples at near (33%) and far (100%) distance; near hits weighted 2.5×. Speed-scaled probe distance: `120 + speed × 3 m`, capped at 400 m. Feelers cached and recomputed every 0.1 s. Forward feeler suppresses speed but not in symmetric corridors (canyon pass detection). Gains raised: roll 0.12 → 0.45, yaw 0.20 → 0.60, margin 30 → 45 m.
- Waypoint skip respects turns: `_advance_heightmap_path_to_clear_point` now checks that no intermediate waypoint involves > 25° turn before allowing a skip, so the helicopter follows corners instead of cutting across them into walls.
- Aircraft 9 cruise speed set to 50 m/s (was placeholder 150). Aircraft 10 cruise speed set to 60 m/s. Both now decelerate correctly within 600 m of the carrier approach gate.
- Carrier approach inbound decel: speed governed by `_get_carrier_approach_arrival_speed_limit` (physics-based v²=u²+2as). Turn suppression disabled for INBOUND so the decel zone is never zeroed by heading offset. Decel rate raised to 4 m/s².
- Destroyed plane linger: pressing LB/RB or Y/Triangle during the explosion linger cancels it immediately so the player isn't forced to watch.
- Radio filter chain updated: HPF 800 Hz, LPF 2800 Hz, EQ midrange boost, 12:1 compressor, hard clip (drive 0.65, pre-gain 8.0), limiter. Effect chain rebuilt on every game start so export var changes take effect.
- Bridge glass hidden from commander camera: `Commander.gd` scans the carrier scene tree for `MeshInstance3D` nodes named "glass" and hides them when the commander camera is active, shows them again when switching away.
- Helicopter gear placement on deck: gear collider offset now computed in global Y (tilt-safe) throughout all tractor bot placement paths. Final safety pass after `_settle_launch_aircraft_on_wheels` pushes aircraft up if any gear collider is below deck surface. Elevator-up ride also uses global Y offset.
- Machine gun spread reduced: 10 mm 1.25° → 0.4°, 15 mm 1.0° → 0.35°.
- LZ landing detection loosened: `terrain_landing_settled_agl_m` 3 → 6 m, `terrain_landing_settled_speed_mps` 0.6 → 3.0 m/s, `terrain_landing_touchdown_radius_m` 20 → 40 m so helicopters register as landed without requiring a near-perfect hover touchdown.
- Altitude collective: when above target altitude in transit, collective now actively reduces below trim proportional to excess height, allowing the helicopter to trade altitude for speed naturally rather than maintaining hover while too high.

### Recent Changes (2026-06-04)

- Helicopter crash flight recorder: `HelicopterPilot` now maintains a 15-second ring buffer of all HELI_AI debug lines. On the `destroyed` signal it writes `user://heli_crash_report_<name>.log` with a structured post-mortem: flight milestones (landed at LZ, departed, landed at carrier), then the last 15 seconds of debug output, then a CRASH marker. The file is appended on each crash so multiple events accumulate. `crash_log_enabled` and `crash_log_history_s` are exported for tuning.
- Helicopter crash flight recorder milestones: key events (landed at LZ with position, departed LZ, landed at carrier, departed carrier) are recorded as timestamped milestone lines in the report above the raw debug output.
- Scripted carrier approach: carrier landing now follows a fixed two-marker path authored in the carrier scene (`Helicopter Approach Point` at 15 m above deck / 100 m behind, `Helicopter Landing Point` on deck). The helicopter flies transit all the way to the approach gate, then hands off to a three-phase scripted approach: TO_APPROACH_POINT (transit flight to gate), FINAL (carrier speed + 5 m/s forward at approach altitude), DESCEND (match carrier speed, descend to landing point). Replaces the old altitude-controller-fighting approach that consistently arrived 30 m below deck.
- Helicopter AI control fixes: terrain recovery suppressed during carrier approach (was firing at deck AGL and killing speed/collective); landing flare suppressed during TO_APPROACH_POINT and FINAL phases (was detecting below-deck position and subtracting collective); nose-up pitch capped at `transit_max_nose_up = 0.05` at cruise speed to prevent panic braking; forward lean drop rate-limited to prevent sudden pitch-up on decel.
- Helicopter yaw authority increased: `max_yaw_input` 0.25 → 0.55, `transit_sharp_turn_yaw_input` 0.22 → 0.65, `transit_sharp_turn_yaw_gain` 0.18 → 0.35, `transit_pedal_turn_yaw_input` 0.55 → 0.85, `transit_pedal_turn_yaw_gain` 0.55 → 0.70. AI now uses yaw authority comparable to player input for turning.
- Bank collective compensation: `_calculate_transit_collective` now boosts collective proportional to bank angle so the helicopter maintains altitude through turns instead of losing height.
- Terrain climb speed limit: if the terrain ahead requires a climb the helicopter cannot achieve at current speed, forward lean is reduced to bleed speed first. Prevents the spiral-dive-into-cliff failure seen in crash reports.
- Emergency sink recovery: if sinking fast at low AGL in transit, pitch and roll are blended toward level and collective pushed toward 1.0 as a last-resort guard.
- Helicopter test mode (F11): `FlightDeckManager` toggles a helicopter endurance test — despawns all non-helicopter aircraft, clears stored aircraft queue, freezes POI reveals, locks day/night to midday, then spawns one Aircraft 10 via normal hangar retrieval every 60 seconds up to a maximum of 4 alive. F11 again despawns all test helicopters and restores normal operation. Crash logs are wiped at test start.
- Helicopter tractor-bot retrieval fixed: AI helicopters that land under their own control are now correctly picked up by tractor bots and stored in the hangar. Fixed: `carrier_transport_mode` was causing the FDM recovery scan to skip parked helicopters; `helicopter_deck_takeoff_ready` was not cleared on landing so `_is_helicopter_ready_for_deck_recovery` always returned false; `_complete_helicopter_retrieval_sequence` was calling `enable_ai` which re-initialized the mission and caused immediate re-takeoff.
- Volume setting in pause menu: Options screen added to the pause menu with a master volume slider (0–100%). Setting is saved to `user://settings.cfg` on every change and loaded at startup.
- Freed-aircraft crash fixes: multiple async functions in `FlightDeckManager` (`_complete_helicopter_retrieval_sequence`, elevator follow loops) now guard `is_instance_valid` after every `await` and no longer pass freed aircraft references to `_set_manual_transport` or `_restore_aircraft_physics`.

### Recent Changes (2026-05-31)

- Helicopter AI PD controller overhaul: replaced the previous open-loop cyclic/collective with proper PD controllers on every axis. Forward velocity uses D-on-measurement (derivative of actual speed, not error) so the controller backs off forward tilt as speed builds without a derivative spike on setpoint changes. Altitude uses a two-loop design — outer loop converts altitude error to a desired climb rate, inner loop drives collective to achieve that rate — which avoids the gain-imbalance that caused the older single-P to cut throttle to near-zero when climbing fast. Yaw uses P (angle error) plus D (yaw rate) with no extra lerp filter, since HelicopterFlight already smooths the physical yaw response. Lateral roll combines position correction, lateral speed damping, and a coordinated-turn bank term derived from the yaw error so the helicopter banks into turns rather than flat-pivoting.
- Helicopter collective rate limiting: the AI now rate-limits its own collective command (0.30/s up, 0.15/s down) before sending to ControlEngine, preventing the wild frame-to-frame swings that caused engine cut-out oscillation on altitude transitions. IDLE state always zeroes collective directly, bypassing the limiter.
- Helicopter mission loop: Aircraft 9 and 10 now fly an autonomous OUTBOUND → AT_LZ → INBOUND → AT_CARRIER cycle. On enable the helicopter picks a random LZ 500–2000 m away, flies out, lands, dwells 12 s, returns to the carrier, dwells 20 s, and repeats. Carrier landing uses carrier-relative speed detection so the helicopter can match deck velocity and still register as stationary on a moving carrier.
- Helicopter carrier-sliding fix: the sliding-at-carrier-speed bug was traced to the carrier's `CharacterBody3D` physically pushing the parked `RigidBody3D` helicopter via `move_and_slide`. A proximity check in the AT_LZ IDLE phase zeroes the dwell timer if the carrier comes within 120 m so the helicopter takes off before contact. Separately, `VelocityFrame.clear_reference` is called on terrain touchdown and continuously while at the LZ to prevent stale carrier-velocity metas from triggering `_hold_deck_ready_helicopter` on terrain.
- Helicopter landing flare: the collective cap during LANDING is now AGL-dependent. At `landing_flare_agl_m` (8 m) the cap is trim − 12 %, ensuring a meaningful descent; at ground level it rises to trim − 2 %, giving a near-hover cushion and a much softer touchdown. Landing target altitude is also set to terrain − 1.5 m so the altitude controller always commands gentle descent all the way to contact.
- Helicopter state restoration: debug output now also prints from `_ready` and `initialize` so it is visible even before the physics loop starts. `debug_enabled` is set in both helicopter scenes. Aircraft 10 starts with `ai_enabled_at_start = true` for testing.
- Aircraft 10 flight tuning: `cruise_speed_mps = 52`, `max_speed_mps = 65`, `decel_distance_m = 400`, `cyclic_rate = 3.0`, `collective_rate_up = 0.8`, `altitude_guard_m = 15`, `sink_guard_mps = 3.0`. The altitude guard and sink guard thresholds were the main reason Aircraft 10 was flying slowly; they were triggering on normal cruise oscillations and cutting forward cyclic.
- Burst rockets: `RocketPod` now fires four rockets in quick succession (70 ms burst interval) on a single trigger pull rather than one per press, with a separate inter-burst cooldown.
- Pilot 2 GLB wired as cockpit pilot: both `CockpitPilot.tscn` and `CockpitPilot2.tscn` now instance `pilot 2 - sitting in cockpit.glb` (Auto-Rig Pro full rig with sitting pose baked as a 1-frame animation). `PilotPose.gd` detects the ARP rig, hides control-shape meshes, and auto-plays the sitting animation.

### Recent Changes (2026-05-29)

- Helicopter AI first pass: `AI/HelicopterPilot.gd` adds a dedicated rotorcraft controller for Aircraft 9 and Aircraft 10 with takeoff, low-level transit, hover, and landing states. It samples terrain height through `TerrainNavGrid`/terrain references and uses a local corridor planner rather than the fixed-wing recovery/attack controller.
- Helicopter AI takeoff tuning: the takeoff state now commands enough collective to clear the helicopter deck brake release threshold instead of hovering just below liftoff. The floor is exposed through `takeoff_collective_min` and `takeoff_deck_release_margin` for in-game tuning.
- AI toggle routing: helicopters now use `HelicopterPilot` when switched to AI control, while their old fixed-wing `AIPilot` node stays disabled. Aircraft 9 and Aircraft 10 have the helicopter AI scene node wired in, but their scene defaults no longer auto-enable AI on startup.
- Flight-deck carry fix: the carrier's scripted deck transform carry now deduplicates aircraft that appear in multiple groups, moves carrier pin joints once per carrier update, and avoids transform-carrying live helicopters just because their gear is touching the deck. Parked, braked, transport-mode, and explicitly staged helicopters still ride with the carrier.

### Recent Changes (2026-05-28)

- Ejection-seat sequence: player aircraft with an authored `EjectionSeat` now support triple D-pad-up ejection. The canopy is jettisoned first, the seat fires after a short delay, the pilot/cockpit camera ride the seat, the parachute deploys, and the seat separates and falls away. Enemy aircraft and aircraft without ejection seats do not use this path.
- Parachuting pilot camera flow: once the player ejects, the ejected pilot becomes the active camera target for cockpit, chase, and cinematic views. View cycling should remain on the parachuting pilot rather than snapping back to the abandoned aircraft or another plane. The abandoned aircraft is expected to continue crashing independently.
- Editable parachute authoring scene: `Aircraft/Visuals/Parachute.tscn` now contains editor-facing `PilotMount` and `HeadCameraMount/HeadCameraPreview/Camera3D` markers. Runtime placement reads those markers so the hanging pilot and parachute cockpit camera can be adjusted directly in the scene.
- Pilot 2 rig integration: the shared cockpit pilot now uses the rigged Pilot 2 model, with a common yaw correction and a conservative zeroed pose baseline while the rig/pose workflow is still being sorted out. Current pose work is explicitly in-progress, especially parachute hanging posture and cockpit seating.
- Cockpit visibility: the pilot model is hidden when the cockpit/head camera is current, including while parachuting, so first-person views are not blocked by the pilot mesh. External views still show the pilot.
- Aircraft 10 scout helicopter: a smaller single-rotor helicopter scene has been added with two hardpoints, front/rear landing gear layout, tail-rotor propeller visuals, rockets and a 15 mm gun, and lighter scout-helicopter tuning. It is still being tuned for power, yaw authority, lag, and forward-flight feel.
- Helicopter rotor visuals: segmented rotor blades now support rest droop, subtle stowed vertical separation, fold/stow behavior, spin-up/spin-down transitions, and thrust-dependent negative droop at high thrust. The rotor debug pass exposed and fixed the large vertical blade-offset bug that was moving blades meters above/below the helicopter.
- Hardpoint asset refresh: the shared hardpoint scene now uses the authored root `Hardpoint.glb` model.

### Recent Changes (2026-05-20)

- Aircraft 9 helicopter flight pass: the rescue helicopter now has a more usable heavy arcade rotorcraft model with cyclic lag, yaw inertia, simple ground effect, speed-dependent weather-vane help from the tail surfaces, controller throttle/collective handling, one-line `HELI_DEBUG` telemetry, and retractable four-point landing gear. It is still intentionally a first playable pass, not a final helicopter simulation.
- Helicopter deck operations: Aircraft 9 skips the catapult, is staged on the forward deck, inherits the carrier's deck velocity on takeoff, and can land back on the carrier without being pushed off the bow. The fix keeps the carrier as a scripted/kinematic moving platform and makes deck-relative velocity explicit through `VelocityFrame`, rather than converting the carrier to a physics body.
- Helicopter visuals: the coaxial rotor now uses two counter-rotating three-blade rotor sets from the authored blade asset, starts folded aft, unfolds before engine spool-up, and no longer relies on deprecated helicopter placeholder assets or sounds.
- Pilot roster / personnel framework: carrier pilots now have names, gender, national origin, language/voice set, temperament, skill level, experience, mission time, air kills, ground kills, Ace status, wound/rest state hooks, and a roster overlay bound to `,`. Pilots are assigned from the carrier roster as aircraft are launched rather than being permanently tied to a specific aircraft.
- Radio voice set expansion: pilot voice sets were expanded/imported beyond the earlier Ukrainian/British/Filipino/Arabic/German baseline, including Brazilian male, French Canadian female, Nigerian male, and Scottish female, while the disliked Scottish male set was removed. Radio bark repeat suppression now avoids replaying the exact same line too quickly.
- Aircraft kill credit: aircraft damage now tracks contributors so pilot stats can credit kills more fairly than pure last-hit only; this includes support for assisted/shared credit and better handling when a damaged aircraft later crashes.

### Recent Changes (2026-05-17)

- AirOps order follow-through: Citadel orders now correspond more closely to actual flight tasks, with duplicate attack/order confirmations suppressed so flights should acknowledge once rather than flooding the radio. Empty flights can still be scrambled into the requested role, and current work continues to make launched flights reliably act on those assignments.
- Combat attack behavior: aircraft ground-attack safety rules were adjusted so rocket and gun runs are less likely to be aborted by low-altitude crash-avoidance before weapons can fire. Low-altitude failsafe logic now avoids the old hard-pull stall trap by considering speed/energy before demanding aggressive climbout.
- Radio voice pipeline: Citadel and pilot voice clips are now file-backed, normalized, imported, and routed through heavier long-distance-radio filtering/static/distortion. Pilot voice sets now include Ukrainian, British male, Filipino, Arabic female, German female, and Scottish male. Each pilot callsign is assigned a sticky voice set so a given pilot no longer changes actor/accent between barks.
- Radio queue hygiene: stale voice clips expire from the radio queue after a short window, reducing old order acknowledgements and delayed barks that no longer match the tactical situation.
- Citadel flight-specific lines: Archer, Bulldog, Crimson, and Dingo Citadel line folders have been converted/imported so orders can address the intended flight without relying on stitched phrases. Some voice performances are still being regenerated/tuned; the radio filter helps unify them but does not replace good source takes.
- Aircraft 4 turret balance: the aircraft-mounted turret is weaker and constrained so it cannot fire down through the aircraft's own plane, making it less oppressive than ground turrets.
- Landing gear visuals: the new Aircraft 5 landing gear rig was split into reusable gear scenes and wired for nose/left/right gear animation. Nose steering now pivots at the rotation linkage, and the main gear has multi-stage retract motion with linkage rotation, lower-leg compression, and centerline/forward folding behavior.

### Recent Changes (2026-05-10)

- Night vision overlay lock: the cockpit NV `CanvasLayer` projection now uses the camera and HUD glass interpolated render transforms instead of raw physics transforms, addressing the high-G HUDglass-relative drift seen with physics interpolation enabled. NV now also only activates the cockpit camera's `nv_active` stabilizer while the player's own cockpit camera is the active viewport camera, preventing stale player-cockpit overlay/stabilizer state when cycling to other views. This still needs a live high-G visual pass to fully validate.
- Night vision target-feed sync: `I` is now handled only by the currently active cockpit overlay, and that overlay drives the instrument panel attached to the same aircraft instead of whichever panel happens to be first in the global `instrument_panel` group. The target-camera shader also remembers pending NV state before its material exists, so the HUD overlay and target feed should toggle together reliably.
- Night combat penalties: `DayNightCycle` now exposes an AI darkness factor derived from sun/ambient/sky energy. AI pilots have reduced sensor range, slower contact refresh, shorter effective dogfight range, stricter gun/rocket fire gates, and less tolerance for stale long-time-of-flight shots as darkness increases. Turret controllers now search and solve aim more slowly at night, detect at shorter range, and apply lower effective aim skill/noisier tracking. Ground platoons also shorten hostile pursuit/search radius at night.
- Carrier ops / sensor picture: AirOps now treats Citadel as having a carrier radar picture (`5 km` range) plus friendly aircraft/ground vehicle reports; friendly aircraft can call targets in, and AirOps uses reported contacts to launch interceptors against inbound aircraft and CAS flights against spotted ground threats. Interceptor scrambles use air-to-air loadouts only, while ground strikes avoid wasting fighters on bombs/rockets unless a ground target is actually known.
- Ground ops escort behavior: GroundOps now tries to keep at least two ground vehicles escorting the carrier and will aim for four when possible, using the existing vehicle bay/ramp deployment flow.
- Targeting and target camera: D-pad left/right target cycling now cycles available hostile targets instead of relying only on the forward cone, and the cockpit target camera can hold on a destroyed target's last position long enough to watch the kill before auto-switching. This is currently a final-position hold, not persistent wreck tracking.
- Terrain safety and clutter: aircraft ground-clearance checks now sample terrain more carefully around cliffs/canyons to reduce false cliff-edge snags, and rock scatter placement rejects unsupported/steep/cliff-edge placements more aggressively so streamed rocks are less likely to float. This looks much better in play but remains worth watching in extreme terrain.
- Radio chatter: `RadioComms` now auto-loads Citadel voice clips from `res://Audio` using the `Citadel - <line>.wav/.ogg/.mp3` naming convention, queues matching voice playback with radio static/dropout processing, and tolerates the current Archer-addressed clips for all friendly flights.
- Weapon tuning: light machine gun spread was brought back down to a sane baseline after it had become much larger than intended.

### Recent Changes (2026-05-08)

- Night vision overlay: pressing `I` in cockpit view enables a green NV mode rendered as a `CanvasLayer` `Polygon2D` projected onto the HUDglass mesh; the shader applies luminance gain, gamma, heavy scanlines, fine per-frame grain, smooth value-noise coarse grain (no rectangular artefacts), vignette falloff, and occasional horizontal scan-line artefacts for a worn-tube feel; NV is cockpit-only and hides in all other camera modes.
- Instrument panel target camera NV: the existing target-display `ShaderMaterial` was extended with `nv_enabled`, `nv_gain`, `nv_gamma`, and `nv_noise` uniforms; toggling NV also switches the instrument panel target feed to the same green NV look.
- `CockpitCamera.gd`: added `nv_active` flag; when set, the g-force position offset smoothly returns to zero so the cockpit camera stays at its base position during NV use.
- Previous known issue: NV overlay position relative to the HUD glass was not fully stable during high-G manoeuvres; this has been patched by projecting from interpolated render transforms, but should be live-tested before treating it as fully proven.

### Recent Changes (2026-05-03)

- Mission-return recovery framework: AI aircraft returning to the carrier now have a marshal / hold / recovery-approach sequence before the existing straight-in landing controller. They fly to a high carrier-relative gate behind the carrier, request landing clearance from `FlightDeckManager`, hold behind the carrier if the deck is unavailable, then step through tunable descent gates before handing off to the proven final landing mode. The gate altitudes are intentionally exposed for later steep-descent tuning in canyon terrain.
- Landing deck clearance reservation: `FlightDeckManager` can now reserve the landing deck for one requesting aircraft, reject other landing requests while the reservation is active, and release the reservation on catch, missed approach, crash/destruction, recovery start, or reset paths.
- Recovery test controls: `F3` commands the closest eligible airborne AI aircraft to return via the new recovery framework; aircraft that overshoot the wires now leave final landing immediately and enter missed-approach navigation instead of continuing to fly the landing carrot.
- Recovery gate spacing: the default carrier-relative recovery gates were moved farther aft, with the marshal point now 2000 m behind the carrier and final handoff around 1000 m, giving aircraft more room to settle before final landing.

### Recent Changes (2026-05-02)

- Carrier recovery validation pass: landing test spawns now run continuously at fixed intervals with ordered names (`LandingTest_001`, etc.), and debug outcome lines distinguish catches, bolters, wave-offs / go-arounds, and crashes so harmless missed recoveries are not mixed with aircraft-loss failures.
- AI carrier landing tuning: landing control now favors rudder/yaw for lineup with only light visual banking; pitch/FPA damping was softened to reduce oscillation; standing-carrier landings are generally reliable, and moving-carrier landings now compensate for the carrier's scripted 10 m/s motion, though this remains an active tuning area rather than a fully solved system.
- Arresting cable and rollout tuning: wire extension was shortened and arrest deceleration was smoothed over roughly 16 m so aircraft stop closer to the landing area and are less likely to be dragged over the elevator.
- Tractorbot / elevator recovery flow: the elevator defaults down when idle; bots ride up with the elevator for retrieval, tow landed aircraft to the elevator, rotate them forward on the platform, descend with the aircraft, and stay below. Tractor bots now re-check live wheel positions during pickup so recently landed aircraft can move without making the bots chase stale wheel targets.
- Debug recovery spawn: `F2` creates a `RecoveryDebug_###` aircraft about 1000 m behind the carrier at about 100 m altitude in landing mode, intended for repeatedly testing landing and post-arrest retrieval.
- Cockpit audio balance: cockpit air-rush / wind layers were reduced relative to propeller/interior engine sound; this is improved but still worth listening for during flight-feel passes because wind can still dominate depending on context.

### Recent Changes (2026-04-29)

- Landing debug snap system: `_landing_snap()` now prints heading and nose pitch in addition to existing fields; an `extra` parameter carries wire/lateral/score data for outcome lines; distance-triggered snaps fire at 400 m, 200 m, and 100 m from touchdown per approach so each attempt produces a trace of the full approach, not just the outcome.
- Landing points scoring: Wire 2 (middle cable by Z order) = 10 pt base; Wire 1 and Wire 3 = 5 pt base; score is multiplied by a lateral factor (`1 − |lateral_m| / 24.8`) so a centered catch on wire 2 gives exactly 10 pts; `ArrestingCable` exposes `get_wire_number()` and `get_engage_lateral_m()`; `FlightDeckManager` tracks a rolling average across all attempts in a test session and prints it after every outcome (catch, bolter, wave-off, and crash all count, with 0 pts for non-catches).
- FPA descent cap raised from 10° to 25° for both the approach and final-approach phases; pitch input limits raised from 0.52/0.55 to 0.65 so the FPA controller can command steeper descents without saturating.
- Known gap: minimum glideslope enforcement (preventing too-shallow approaches) is still unresolved. A glideslope-path carrot caused violent altitude oscillation and was reverted; a minimum FPA floor was also tried and reverted. The `landing_glideslope_deg` export var (4.5°) exists in `AIPilot` but is currently unused.

### Recent Changes (2026-04-23)

- AI strike behavior / telemetry: attack debug output was redesigned so pilots now log state transitions, weapon releases, 1 Hz updates during attack runs, and only sparse background status outside combat; strike release ranges were tightened so bombs and rockets are delivered closer to the target; bomb drops are now staggered instead of dumping the full rack at once, and attack aiming was simplified toward the carrier center for a cheaper, more stable release reference.
- AI stability / performance: multiple freed-instance crashes during aircraft destruction and target churn were hardened in `AIPilot.gd` and related support paths; dogfight/contact loops now validate references more defensively; contact scans, collision-avoidance checks, RTB checks, and attack-solution style calculations are throttled/cached more aggressively to reduce attack-time CPU spikes.
- Enemy air operations: enemy `Aircraft_3` now strips all external stores and acts as a clean fighter/dogfighter; enemy patrol density increased by splitting patrol flights into smaller elements.
- Pilot map / radar: the cockpit terrain map was zoomed in and now samples the same terrain bounds/origin convention as the full `M` tactical map, preventing the old drift/out-of-sync behavior after origin shifts.
- Wind turbines / defended sites: enemy wind turbines were added as destructible infrastructure with spinning rotors, exploded-part behavior, map visibility, main-color-only team tinting, distant markerization, and proximity-based activation; startup now places grouped wind farms on elevated ground with nearby gun emplacements, and free-look debug placement uses `W`.
- Aircraft 6: new `Aircraft_6` mesh/scene added; key `6` now spawns a friendly `Aircraft_6` 200 m above the carrier at 60 m/s; the new aircraft is tuned as a slow, stable, high-rudder-authority, low-stall, high-durability type.
- Aircraft 9: rescue helicopter model added under `Models/Aircraft_9` with a first-pass `Aircraft_9` scene. It uses the existing aircraft systems, a dedicated arcade helicopter flight model tuned as a very heavy stable rescue helicopter, four-point fixed landing gear contact layout, and key `9` hangar retrieval while deeper helicopter controls are built. Helicopter retrieval now skips the catapult and parks the aircraft on the forward deck halfway between the elevator and bow takeoff area; the visual rotor uses the new blade asset as two counter-rotating three-blade rotors with flipped top-blade pitch, starts folded aft, unfolds before engine startup, and replaces the deprecated placeholder prop/sound setup. At this stage helicopters were player-only; see the 2026-05-29 notes for the first-pass helicopter AI.

### Recent Changes (2026-04-18)

- AI ground attack: fixed multiple compounding issues that prevented enemy strike aircraft from ever firing weapons in attack runs.
  - Overshoot detection in `ATTACK_POSITIONING` was firing every physics frame (no cooldown); added 10 s recompute cooldown so aircraft don't spiral on stale approach directions.
  - Added 30 s hard timeout in `ATTACK_POSITIONING` that forces a fresh setup-waypoint recompute from the aircraft's current position, unsticking aircraft in wide orbits.
  - "Too slow" speed gate used `stall + margin + 10 m/s = 58 m/s` as the threshold, causing aircraft that cruise at 57 m/s to take the early-return path every frame and never reach the distance check that transitions to `ATTACK_DIVE`; threshold lowered to `stall + margin = 48 m/s`.
  - Low-altitude pitch guardrail (ground + 300 m band → forced climb VS) applied in all states including `ATTACK_DIVE`; it was overriding dive commands with a +2.7 m/s climb demand and holding pitch at max nose-up; `ATTACK_DIVE` is now excluded from the guardrail.
  - Collision avoidance miss threshold (80 m) was aborting dives when multiple aircraft attacked the same target simultaneously; threshold tightened to 25 m during `ATTACK_DIVE` only.
  - Attack parameters loosened across the board: setup distances reduced, altitude offsets lowered, pull-up distances reduced, bomb CCIP "still-improving" wait gate removed, rocket alignment widened to 40°, rocket alignment check switched from CCIP-corrected aim point to raw target position, bomb min dive angle dropped from 12° to 3°, bomb fallback altitude raised, break-off distance reduced.

### Recent Changes (2026-04-13)

- Project identity: project name is now `Land Carrier` in `project.godot`.
- Pause menu/UI: Orbitron variable font integration, larger all-caps menu text, transparent pause overlay (no tint), and full keyboard/gamepad navigation in pause screens.
- HUD: rotating attitude pitch ladder added and tuned (including narrower side rails), with boxed speed/altitude readouts moved upward for cleaner readability.
- Targeting controls: `L3` now locks the hostile closest to HUD center; D-pad left/right target cycling is wired and exposed.
- View/control behavior: `Start` toggles player vs AI control for the currently viewed friendly aircraft without forcing a camera switch; shoulder cycling remains for viewed units including bridge view.
- Weapons framework: shared gun-profile system now supports 10 mm, 15 mm, 20 mm, and 25 mm weapons across hardpoints and turrets, with per-profile RPM, velocity, spread, recoil, damage, range, projectile type, and sound set.
- Gun tuning: 10 mm uses wider spread and LMG sounds, 20/25 mm use tighter spread and autocannon sounds; player standard aircraft gun baseline is 15 mm.
- Hit registration: projectile hit-assist radius now defaults to `0.5 m` (radius), applies to aircraft/vehicles/buildings, and is adjustable at runtime with Up/Down arrows (`+/- 0.2`) with live top-left readout.
- Turret combat: turret fire now checks line-of-sight/range/arc gates before firing; debug telemetry and arc visualization were expanded to diagnose lead/LOS/range misses.
- Turret balancing: carrier defense turret `aim_skill` is set to `0.8`; ground gun emplacements use `0.5`.
- Aircraft 4: new enemy heavy aircraft is integrated into the normal aircraft pipeline, with rear-arc turret constraints, `140 HP`, and debug spawn support (`4` for friendly Aircraft_4; `R` spawns mixed enemy Aircraft_3/Aircraft_4 flights).
- Aircraft loadouts: Aircraft 2 uses a 25 mm autocannon, Aircraft 7/8 use 20 mm autocannons, and Aircraft 3 gained an extra hardpoint with dual 10 mm guns.
- Pilot/cockpit: all aircraft now use the shared cockpit pilot setup/pose pipeline, pilots are hidden while in cockpit view, and pilot material colors are randomized per aircraft from defined uniform/helmet palettes.
- Livery/insignia: teams now get randomized colors and insignia from shared pools; `C` cycles 24 preset aircraft colors (including black/cream/pink variants), and tail/wing insignia projection logic was expanded for curved/slanted surfaces.
- Propeller visuals: aircraft propellers now use authored model-node swapping (`hub`, `blades`, `propeller disc`) for low-speed blade visibility vs high-speed disc shimmer.
- Critical damage: aircraft at `0 HP` now enter a jammed-control death state (random max stick jam), then roll a `10%` per-second explosion chance that spawns dark debris chunks with smoke trails that self-clean on ground contact.
- Ground defenses: new gun emplacements (turret base + randomized 10/15/20 mm turret weapon) spawn in clumps per enemy faction, stay dormant until hostiles are near, inherit team livery color, and are grounded by collider-bottom snapping to terrain.

### Local Godot Install

Portable Godot 4.6.2 is available on this machine for project checks and local runs:

- `C:\Godot\Godot_v4.6.2-stable_win64_console.exe`

Example project launch from this repo root:

```powershell
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --path "C:\Godot projects\Project-Flight"
```

### Core Systems

| System | Status | Notes |
|--------|--------|-------|
| Flight Physics | Working | SimpleAero integration complete; aircraft thrust has been bumped across the roster and shared forward drag reduced so dives and acceleration feel less artificially capped; aircraft now also use per-type pitch/roll self-righting plus grounded rudder assist so takeoff, landing, and general hand-flying feel less "nose goes wherever I point it"; engine throttle response now ramps through spool-up/down lag instead of snapping instantly; low-speed sideslip damping increased so the velocity vector tracks the nose more tightly during normal maneuvering |
| AI Pilot | Working | Full fixed-wing carrier cycle exists; path-follower carrier recovery remains the default; landing mode now favors yaw/rudder lineup with only light bank for visual readability, includes smoother pitch/FPA response, and has a 10 m/s scripted-carrier compensation path that is promising but still being tuned; hierarchy-of-needs safety layer (terrain avoidance > collision avoidance > state machine); terrain fan avoidance with directional escape sampling; low-altitude failsafe now avoids the old hard-pull stall trap by considering energy/speed before commanding escape pitch; dogfight proximity override breaks off ground attack when enemies close; close-pass breakaway logic now reduces merge collisions; gun/rocket attack runs now suppress some low-altitude avoidance behavior while committed so aircraft can prosecute ground targets more reliably; CCIP ballistic sim throttled via caching; attack releases are closer and bomb drops are staggered; dogfight and contact handling were hardened against freed-instance crashes; contact scans, collision avoidance, and RTB checks are further throttled for CPU cost. Helicopters use a dedicated `HelicopterPilot` with full PD controllers on all axes (forward velocity PD with D-on-measurement, two-loop altitude PD, yaw PD, coordinated roll), a rate-limited collective command to prevent oscillation, a full OUTBOUND → AT_LZ → INBOUND → AT_CARRIER mission loop, AGL-dependent landing flare, and carrier-relative speed detection for deck landings. Aircraft 9 (heavy rescue) and Aircraft 10 (fast scout at 52 m/s) are each tuned separately via scene overrides. Still needs live validation of terrain-following edge cases and carrier deck approach/landing. |
| Catapult | Working | Launches AI and player aircraft |
| Arresting Cables | Working | Roll stabilization and mass-adaptive braking; extension is currently constrained to a short stop distance with smoother deceleration so caught aircraft remain near the landing area instead of stretching wires across the elevator |
| Landing Gear | Working | Suspension/damping implemented; Aircraft 1, 2, and 5 now use animated gear pivots instead of pop-in/out, with stowed visuals/shadows suppressed; Aircraft 5 uses the newer reusable gear rig with upper/lower leg compression, rotation linkage, connector arm, and wheel/axle animation; nosewheel taxi steering now pivots below the rotation linkage, and rebound damping/deadband were retuned to reduce "pumping" on rollout |
| Tailhook | Working | Auto-deploy/stow functional |

### Aircraft Systems

| System | Status | Notes |
|--------|--------|-------|
| Player Control | Working | Full manual flight control |
| AI Control | Working | All fixed-wing vehicles default to AI; `Start` toggles only the currently viewed friendly aircraft between player and AI control without forcing camera/target changes; helicopters route through the dedicated `HelicopterPilot` when toggled to AI, but Aircraft 9/10 scene defaults are currently player/manual on startup while the rotorcraft AI is tuned; bottom-center `AI` indicator remains when viewing AI-controlled aircraft; shoulder buttons cycle viewed units (including bridge view); Space exits free camera to spectator; `L` assigns the next eligible friendly aircraft to landing; viewed-aircraft HUD/instruments remain active while AI is flying |
| Weapons | Working | Shared gun-profile stack now supports 10/15/20/25 mm gun families across hardpoints and turrets (stats, projectile type, spread, recoil, sound set); bullets inherit muzzle-point velocity and are oriented to actual spawn velocity; runtime hit-assist radius defaults to `0.5 m` and can be adjusted with Up/Down arrow keys; AA missile launchers can still be intentionally fielded empty |
| Targeting | Working | HUD target box, sensor cone, `L3` target lock, and D-pad left/right cycling through available hostile targets; destroyed targets can remain on the cockpit target camera briefly so the player can watch the impact/explosion before auto-switching |
| HUD | Working | Radar, instruments, CCIP, terrain map overlay on radar; cockpit radar scope remains circular and masked correctly; main gunsight uses HUD-glass collimation/boresight projection; FPV symbol shows actual velocity vector with dotted boresight linkage; rotating attitude pitch ladder (horizon-level) with side ticks is now integrated, and boxed speed/altitude readouts were repositioned upward for better readability; the cockpit terrain map now uses the same live terrain bounds/origin convention as the `M` tactical map and was flattened/stabilized to stop the old bulging/distorted surface feel. The cockpit instrument panel now supports modular MFD/readout/warning/slip-ball layouts, D-pad-down panel interaction with a projected cursor dot, and view-gated panel/target-camera updates so only the currently viewed cockpit panel renders live |
| Camera System | Working | Multiple camera modes, free-fly debug camera, delayed death-camera handoff, and ejected-pilot camera handoff; chase camera now orbits the aircraft or parachuting pilot on a level horizontal plane; the old bridge cam has been replaced by a first-person commander view inside the carrier bridge; stick-click zoom is available in commander view and in the cockpit camera, including while viewing an AI-controlled aircraft |
| Night Vision / Night Combat | Partial | `I` toggles NV in cockpit view; green phosphor shader with scanlines, grain, vignette, and scan artefacts; instrument panel target feed also switches to NV; high-G overlay drift has been addressed by projecting from interpolated render transforms, but still needs live visual validation; AI pilots, turrets, and ground platoons now take moderate darkness penalties to detection, tracking, and firing |
| Cockpit Audio | Partial | Each aircraft now has its own interior loop plus cockpit-only wind / air-rush layers with crash-aware shutdown, reduced in-cockpit stereo spread, and stronger interior filtering; air-rush/wind gain has been reduced so propeller/interior sound is more audible, but the cockpit/exterior balance is still being tuned |
| Radio Comms | Working | Text radio log plus optional OS TTS; Citadel and pilot voice clips can be added by placing files in `res://Audio` with the expected `Citadel - <line>` or `<voice prefix> - <pilot line>` names; matching clips play through a heavier long-distance-radio bus with static, filtering, distortion, dropout, stale-queue expiry, and recent-bark repeat suppression. Citadel has flight-specific Archer/Bulldog/Crimson/Dingo line sets, and pilots now draw sticky assigned voice sets from the carrier roster |
| Destruction / Ejection | Partial | Aircraft now enter a critical-damage death state at `0 HP`: player control is disabled, stick inputs jam to random max directions, and each second rolls explosion chance (`10%` default); final breakup emits dark rigid debris chunks with smoke trails that self-clean on terrain contact. Aircraft with ejection seats support canopy jettison, seat launch, parachute deployment, seat separation, and ejected-pilot camera takeover, but pilot poses, parachute camera placement, and downed-pilot gameplay still need live tuning |
| Damage Effects | Working | 3-tier progressive damage system: hydraulic/fuel/flap failures, engine cap/control loss/HUD flicker, engine sputter/structural failure/HUD blackout; escalating smoke trails |
| Aircraft Roster | Working | `Aircraft_4` added as a heavy/slower enemy aircraft with rear turret; `Aircraft_7` and `Aircraft_8` remain fast interceptors; `Aircraft_6` is now a slow, stable, rugged low-speed aircraft; `Aircraft_9` is a player-flyable rescue helicopter with authored dual counter-rotating rotor visuals, fold/unfold behavior, retractable gear, and explicit carrier-relative deck velocity handling; `Aircraft_10` is a smaller armed scout helicopter with two hardpoints, rockets, 15 mm gun, front/rear landing gear, and tail-rotor propeller visual; `Aircraft_11` is a new helicopter in active development with swing doors (`O` key), authored GLB, and tail/rotor disc assets. Weapon assignments were reworked (Aircraft 2: 25 mm, Aircraft 7/8: 20 mm, Aircraft 3: extra hardpoint + dual 10 mm); enemy Aircraft 3 now spawns clean with no external stores and serves as a fighter; pressing `7`/`8`/`9` retrieves those variants and `4` debug-spawns a friendly Aircraft_4 above the carrier |

### Instrument Panel Layouts

The cockpit instrument panel is still the same scene, `HUD/InstrumentPanel.tscn`, but it now has an exported `module_layout` array. If the array is empty and `auto_build_default_modules` is enabled, `HUD/instrument_panel.gd` builds the default two-MFD layout. To give an aircraft its own cockpit, edit that aircraft scene's `InstrumentPanel.module_layout` in the Inspector. Aircraft 5 currently has an explicit layout assigned for testing.

Each layout entry is a dictionary. Coordinates are panel texture pixels in the panel viewport, currently `800 x 600`. Common keys:

- `type`: module type, usually `mfd`, `readout`, `warning_lights`, or `slip_ball`
- `id`: stable local id for the module
- `title`: short label shown on the module
- `rect`: `Rect2(x, y, width, height)` in panel pixels
- `instrument`: readout source for `readout` modules
- `modes`: MFD mode list, such as `["MAP", "TARGET", "WEAPONS", "DAMAGE", "SYSTEMS"]`
- `lights`: warning-light ids for `warning_lights` modules

Supported readout instruments currently include `speed`, `altitude`, `vertical_speed`, `fuel`, `gear`, `flaps`, `stall`, `missile_lock`, `engine`, `damage`, `g_force`, and `weapons`. MFDs can cycle between map, target camera, weapons, damage, and systems-style pages. The interaction model is intentionally simple for now: aim the cockpit camera at the panel, use the projected dot to choose a point, and press D-pad down. The slip ball is a rough first-pass sideslip indicator based on local lateral velocity rather than a fully simulated mechanical ball.

### Carrier Systems

| System | Status | Notes |
|--------|--------|-------|
| Flight Deck Manager | Partial | Orchestrates deck/hangar/catapult/recovery flow, scramble queues, and runtime aircraft persistence; now supports continuous landing-test spawning, named recovery-debug aircraft, last-leg wave-offs when the deck is occupied, bolter/go-around recovery retries, crash-vs-go-around debug classification, post-arrest tractor/elevator retrieval, and a helicopter-specific deck staging path that skips catapult launch. Helicopter deck takeoff also exposes a brake-release collective threshold that the helicopter AI now clears deliberately |
| Air Operations Manager | Working | Autoload (Citadel). Commands four named flights (Archer, Bulldog, Crimson, Dingo); maintains a friendly sensor/contact picture from carrier radar, aircraft, and ground vehicles; launches air-to-air interceptors against reported inbound aircraft and CAS flights against reported ground targets; player-facing tactical-map orders support CAP routes, CAS tasking, and RTB; empty flights auto-scramble from the hangar when ordered; duplicate order acknowledgements are suppressed so radio confirmations should not repeat endlessly; radio comms throughout |
| Wing Fold (Aircraft 2) | Working | Wings fold in hangar/transport, unfold at catapult; instant-snap on spawn |
| Wing Fold (Aircraft 5) | Working | Multi-phase fold: lateral slide, then overlapping X/Y rotations with smoothstep easing; mirrored left-wing geometry handled with flipped X sign |
| Elevator | Working | Hangar <-> deck transit; aircraft tracks carrier horizontally; idle default is down so retrieval can bring tractor bots up from below instead of leaving an empty platform at deck level |
| Tractor Bots | Working | Aircraft towing system; follow carrier as carrier children, ride the elevator for launch/recovery tasks, rotate recovered aircraft forward on the elevator, and use live wheel-node lookup during pickup instead of brittle or stale hard-coded wheel positions |
| Deck Lights | Working | Procedural SpotLight3D placement (downward-facing, no bleed into dust/sky); center elevator-adjacent strips retuned and recolored yellow |
| Arresting Cables | Working | Multi-cable support |
| Carrier Movement Tracking | Working | Parked, transport, catapult, braked, and explicitly staged deck objects move with the scripted carrier; live wheel/gear contact uses explicit carrier-relative velocity through `VelocityFrame` so aircraft and helicopters do not double-count carrier motion while touching down or rolling. The deck carry pass now deduplicates multi-group aircraft and does not transform-carry live helicopters merely because their gear is touching the deck |
| Vehicle Ramp | Working | Three-panel folding ramp at the carrier rear for ground vehicle deploy/recovery; uses existing GLB meshes; zig-zag fold with simultaneous hinge animation; dynamic terrain-tracking deploy angle; Z key toggles deploy/stow |
| Vehicle Bay Manager | Working | Manages ground vehicle deployment and retrieval via the rear ramp; spawns vehicles on the bay floor, drives them down the ramp at 3s intervals; retrieval rallies all platoon members behind the carrier, deploys ramp when first vehicle arrives, drives them up one at a time; auto-stows ramp after completion; carrier-local positioning during ramp transit so everything works while the carrier moves |
| Ground Ops Manager | Working | Autoload singleton managing four named platoons (Ember, Ferret, Grizzly, Hammer); tries to keep at least two ground vehicles escorting the carrier and four when available; V deploys next empty platoon, B retrieves last deployed, N requests carrier escort; commands: move, attack, protect, escort, pursue, hold, retrieve; tactical map can issue point-based MOVE / ATTACK / PROTECT / ESCORT / HOLD / RETRIEVE orders; empty platoons auto-deploy when given a task and preserve that queued objective through deployment; carrier escort places vehicles at carrier corners with velocity matching; platoons use simple formation slots, pace to the slowest member when out of combat, break formation during combat, and reform afterward; ground staging prefers carrier-reachable terrain with a larger buffer from steep slopes/cliffs |
| Tracks | Working | Nav-grid A* pathfinding with path simplification; full-path computation (no more segmented replanning); steering response/deadzone/settle tuning; height deadband smoothing; tread belt UV rewritten to use baked path-based mapping from imported track mesh; new belt debug modes (path UV, cross UV, direction arrows); terrain-feeler wall avoidance; stuck detection; spawn faces first waypoint |
| Carrier Defensive Turrets | Working | Carrier defense mounts host dual active turrets through the shared controller/weapon stack; firing is now gated by aim tolerance, line-of-sight, fire arc, and effective range; lead debug reporting was expanded and carrier turret `aim_skill` is tuned to `0.8`; Aircraft 4's airborne turret has been separately constrained/nerfed so it cannot fire down through the aircraft plane |
| Bridge Commander | Working | First-person commander pawn with analog walk/look on the bridge; simple collision, warm bridge lighting, and bridge-view camera handoff integrated |
| Bridge Hologram | Working | 2 m centered wireframe tactical table with deep-green-to-neon-green terrain, blue/red 3D aircraft markers, blue/red ground-unit cubes, raised carrier/ground markers, camera-gated low-frequency refresh, incremental multi-frame terrain rebuild, and waypoint path visualization (dots + lines); enemy platoons show as medium red cubes only when actually observed via friendly terrain line-of-sight, and enemy ground vehicles do not split into individual markers until those specific vehicles are visually revealable; now runs in physics_process with interpolation for smoother carrier-relative motion; carrier plate enlarged |
| World Map | Working | Full-screen tactical map on `M`; fixed `25 km x 25 km` terrain/nav window with live holomap-style symbols layered over an interactive phosphor command display; terrain now reads in three solid green elevation bands for fast silhouette recognition; carrier/platoon routes and enemy counters render directly on the map; enemy platoons stay visible as abstract hot-pink contacts while individual enemy vehicles still require visual reveal; the first playable command layer now supports selecting named flights/platoons, drafting missions, clicking map targets, CAP route authoring, and confirming orders from the map itself |

### Workflow / Debug

| System | Status | Notes |
|--------|--------|-------|
| Screenshot Capture | Working | `Insert` saves screenshots to the project-root `screenshots/` folder for review/debugging |
| Pause | Working | `Select/Back` toggles pause on gamepad and `P` on keyboard; pause menu now supports both keyboard and gamepad navigation, uses larger all-caps Orbitron styling, and no longer tints the screen |

### Current Carrier Troubleshooting Notes

- Tread mapping / visible split investigation: [Land Carrier Track Mapping Problem](docs/Land%20Carrier%20Track%20Mapping%20Problem.md)
- Bridge/commander jitter investigation: [Land Carrier Bridge Jitter Problem](docs/Land%20Carrier%20Bridge%20Jitter%20Problem.md)
- Carrier / free-look audio investigation (2026-04-03): bridge/control-room/deck/elevator/tread audio hooks were added and bridge window damping was being tuned, but carrier-related 3D audio is still unresolved in free-look camera testing.
- Current audio state (2026-04-03): an accidental always-on 2D debug deck-sound player in `FlightDirector.gd` was disabled; mono versions of the carrier 3D source WAVs were created for deck / tread / elevator use; free-camera listener handoff was also patched, but the latest in-game symptom regressed to no carrier sound at all in free look.
- Recommended resume point: instrument the active 3D listener and named `3d_audio` players at runtime first, then continue debugging from verified listener/source state instead of doing more blind attenuation or mix tuning.
- Performance (2026-04-06): render scale set to 0.5 for 4K; terrain chunk rebuild interval raised to 0.5s with smart initial-fill burst; volumetric fog is the main remaining GPU cost; spike logger removed from `ScenarioManager.gd`; AI terrain fan/ahead checks throttled to ~20 Hz in `AIPilot.gd` and `get_height` callable cached to eliminate per-call `has_method` overhead.

### Enemy Systems

| System | Status | Notes |
|--------|--------|-------|
| Detection | Working | Sensor-based target acquisition |
| Weapons | Working | Enemy and friendly weapons now share the same profile-driven gun framework (10/15/20/25 mm families, projectile/sound/profile variance); turrets and hardpoints both consume the same ballistic data, and engagement now respects weapon effective range for firing decisions |
| Ballistics | Working | Lead calculation with gravity compensation now uses real effective projectile speed and measured target velocity in turret controllers; bullet telemetry debug was added to inspect closest miss distances and lead quality in live combat |
| Enemy Bases | Working | Two enemy bases are placed on suitable flat terrain near carrier ground level, with floating-origin-safe placement logic and associated base assets (runway + structures + support hooks) |
| Gun Emplacements | Working | Enemy teams receive random emplacement clumps (`4-5` groups/team, `1-3` guns/group); each emplacement has `150 HP`, random 10/15/20 mm turret weapon, activation-distance sleeping for performance, collider-bottom ground snapping, and main-color-only team tinting; wind-turbine groups now also get `2-3` nearby enemy gun emplacements as local defenses |
| Ground Snapping | Working | StaticBody3D terrain alignment plus collider-aware ground placement for spawned emplacements/buildings |
| Movement | Working | Aircraft behavior solid; ground vehicles use spring-damper suspension with chassis floating above ground and all wheels in contact (works on terrain and carrier ramp); forward-axis velocity projection; larger turn radii; elliptical carrier avoidance with tangential flow steering; enemy/friendly platoon and vehicle staging validates carrier-reachable flat ground with larger margins from steep terrain; enemy vehicles now anchor destinations more carefully and reject direct segments that would climb steep slopes; abstract platoon contacts follow nav-safe representative routes instead of tunneling through mountains; movement/combat stance still being tuned |
| AI Behavior | Working | Carrier-centered patrol, dogfight, missile/gun choice, RTB/landing, lost-sight variation, and platoon-based ground vehicle objectives implemented; ground vehicles hold position once arrived (30m hysteresis), avoid siblings during retrieval rally, and use formation/rejoin behavior for platoon travel; escort positions prioritize front corners; friendly debug-spawned aircraft can now be kept in a shared flight; close-pass breakaway logic now reduces head-on air-to-air collisions; enemy vehicle gunnery is intentionally inaccurate but permissive, so they shoot often without feeling too dead-eye; sensor scans now use cached group nodes with periodic refresh and guard against freed instances; enemy Aircraft_3 now behaves as a storeless fighter, and strike runs release closer to target with staggered bomb drops; still being tuned |

### Environment

| System | Status | Notes |
|--------|--------|-------|
| Terrain | Working | Custom low-poly procedural terrain mesh with chunk streaming around the active camera plus forward preload; current main-scene terrain is roughly `100 km x 100 km`, while the baked navigation / tactical-map coverage is `25 km x 25 km`; height quantization and adaptive triangulation keep the low-poly shape readable; aircraft ground-clearance checks now use more conservative local terrain sampling around cliffs/canyons to avoid snagging on invisible heightmap edges |
| Terrain Shaping | Working | Flat areas now include subtle undulation/detail noise; cliffs/canyons deepened for stronger relief |
| Terrain Shader | Working | Slope-based coloring; sharp sand-to-grey border (`steep_slope_band`); per-face independent tint (no spatial bleeding) |
| Rock Scatter | Working | MultiMesh rocks are embedded more firmly into the terrain, use actual mesh bounds for placement, avoid steep/unsupported cliff-edge placements, and still use atomic swap to prevent popping; floating rocks are much rarer now but remain a live-test watch item in extreme cliff terrain |
| Wind Turbines | Working | Enemy wind farms now spawn at startup in elevated `3-4` turbine groups with `80-120 m` spacing, `2-3` nearby guard emplacements, map markers at distance, and `3000 m` pop-in / `4000 m` pop-out behavior similar to platoons; turbines use main-color-only enemy tinting on intact and exploded variants, have `200 HP`, spinning rotors, aircraft-style exploded debris behavior, and support free-look debug placement on `W` |
| Lighting | Working | Directional + deck SpotLights; soft shadows, 8K atlas, blended cascade splits, normal bias; shadow acne fixed |
| Post-Processing | Working | Filmic, glow, SSAO, volumetric fog |
| Floating Origin | Working | Shifts the world when the camera exceeds 4000 m from origin to prevent float32 precision loss; all systems that cache world-space positions (AI pilots, carrier waypoints, nav graph, ground vehicles, flights, terrain grid, UI overlays, cameras, dust effects) implement `apply_origin_shift` via the `origin_shifter` group |
| Weather | Partial | Continuous turbulence plus layered cockpit wind/air-rush audio are in-game and under active tuning; four-phase day/night cycle drives atmosphere colour, volumetric fog density/anisotropy, and sun energy through dawn/day/dusk/twilight palettes (apricot → bleached ochre → copper/cinnabar → plum); broader weather, visibility, and storm systems are still planned |

## Current Agenda

1. Aircraft 11: integrate into full F11 heli test loop, tune flight feel, validate swing door behavior in cockpit vs external views.
2. Rotor wash dust effect: tune puff scale/lifetime/rise speed and validate distance culling; confirm color sampling from terrain shader is correct for all terrain types.
3. Terrain pathfinding: validate threaded pathfinding correctness under concurrent requests; watch for turn-speed governor over-braking at shallow bends; confirm feeler fan still prevents canyon wall strikes.
4. Carrier landing: DESCEND position hold and touchdown detection need live testing across all three helicopter types; airborne separation may need tuning if multiple inbound helis bunch up near hold points.
5. Stabilize ejection/parachute flow: Pilot 2 pose authoring, parachute cockpit camera placement, first-person pilot hiding, view cycling, landing/downed-pilot persistence, and making sure abandoned-aircraft destruction never steals camera focus back.
6. Continue tuning helicopter feel: Aircraft 9 heavy rescue at 50 m/s cruise, rotor stow/spin/droop visuals, carrier deck takeoff collective threshold.
7. AirOps/Citadel dynamic tasking (NEW brain, verified end-to-end): now watch it under sustained pressure across a full round — confirm the whole loop plays out in one game (patrol → strike a target group to destruction → enemy planes appear → reassign to intercept → relaunch fresh CAP). Open follow-ups: launch cadence is gated by deck-sequence duration + scramble/reassign churn (the first flight, "Archer", still tends to time out its scramble because its queued aircraft get reassigned to other flights); the `min_cap` reserve is coded but lightly exercised; player-override coexistence with the auto-tasker is untested.
8. Validate the new interactive `M`-map workflow in live play: asset selection, mission drafting, confirm/cancel flow, and readability under pressure.
9. Expand mission authoring beyond the first slice, especially richer waypoint editing and more flight directives than the current CAP / CAS / RTB set.
10. Continue tuning AI precision control in dogfights so aircraft point more authoritatively at gun solutions, align the pipper with the real gun line, and waste fewer shots while still breaking off unsafe close merges.
11. Continue tuning moving-carrier landings at the current scripted 10 m/s carrier speed; arrest/recovery behavior and carrier-relative speed handling still need live validation.
12. Continue tuning ground vehicle movement, steep-slope avoidance, spotting, and pathing performance, especially with multiple active platoons.
13. Keep watching terrain edge cases: floating rocks, cliff-edge altitude checks, terrain streaming gaps, and delayed collision/chunk loading.
14. Continue expanding bridge/commander command features and allow AirOps/GroundOps AI to create and manage missions through the same order model the player uses.
15. Continue regenerating and judging radio performances; the technical pipeline is solid, but several voices still need better source direction/energy before the chatter fully sells the fiction.

### Upcoming Fixes (from the 2026-07-16 air-combat/AirOps pass)

- **Even-fight conversion ceiling:** a perfectly matched 1v1 (same aircraft/skill) can still run to the round timeout landing only a hit or two — the gunnery converts against a clear advantage but not against a true equal. Wants better sustained-tracking / angle exploitation, not a hard cap.
- **Energy realism is drag-only for now:** hard turning bleeds energy, but at full throttle the engine still out-powers the drag, so energy doesn't *deplete* over a fight. The realistic version needs thrust that falls off with speed — but the engine is a shared module, so it would affect the whole game's flight feel and was deliberately deferred.
- **Launch throughput:** the deck launch sequence (elevator → tractor → catapult) plus scramble/reassign churn keeps launches slow. The real lever is shortening the deck sequence or making a scramble reserve its own launched aircraft so the first flight doesn't get its planes stolen.
- **Dogfight balance:** with the new gunnery, the higher-skilled side wins nearly every round; the skill gap in the test may now be too decisive for variety. Aircraft-vs-aircraft balance (e.g. Aircraft 2 tending to beat Aircraft 5 with equal pilots) also wants a look against the intended roster roles.
- **CombatLog polish:** ground-attack targets currently log as raw node names (e.g. `@StaticBody3D@454`) — resolve to friendlier building/vehicle labels.
- **Visibility model consistency:** the map's fog-of-war keys off the AirOps sensor picture, while the (now-disabled) bridge holomap used its own terrain line-of-sight reveal. If the holomap returns, unify the two so "what the player can see" is one rule.

## Planned Features

### Weather
- **Sandstorm** — reduced visibility, radar range shrink, engine stress, ground vehicles slow; fog density + sky tint via `WeatherManager`; extends existing `DustEffect`
- **Twister** — autonomous moving hazard; `Area3D` applies radial + upward force to `RigidBody3D`; vortex mesh with UV-scrolling spiral shader + debris particles
- **Electrical storm** — no-fly zone with periodic damage; HUD interference (radar flicker, targeting offline); lightning via `ImmediateMesh` + ambient light flashes on strike

### Resource System
- **Plasteel** — salvage resource harvested from wrecks and old buildings; used for structural fabrication
- **Corium** — ambient deposits leeching from the ground; renewable but rate-limited; used for electronics and advanced parts
- Build order: `ResourceManager` autoload → `ResourceNode` scene → wreck/death hooks → HUD counters → procedural Corium scatter → ground vehicle collection orders → fabricator UI

### Structural Damage / Part Breakoff
- Named `Area3D` hit zones on aircraft (left wing, right wing, tail, engine, canopy, etc.)
- At health ≤ 0, any projectile hit on a zone detaches that part: hides the corresponding intact-model mesh(es) and spawns the matching Voronoi fracture piece(s) from `aircraft_N_exploded.glb` as individual physics objects with the aircraft's current velocity + outward impulse
- Secondary trigger: `breaks_on_collision` flag on a zone causes breakoff from hard impacts regardless of health (useful for ground collisions, near-miss blasts)
- Generalises to ground vehicles, the carrier, and buildings — anything with a fractured model variant
- Prerequisite: intact-model GLBs need separately named submesh nodes per breakable zone for clean visual holes; Voronoi piece names in the exploded GLBs already exist and are suitable for mapping

### Pilot Ejection / Rescue
- Ejection is now in-game for aircraft with seats, but needs pose/camera polish and broader live testing.
- Downed pilots should become rescue objectives. Ground vehicles can recover pilots on pathable terrain; inaccessible mesa tops, cliff shelves, or canyon ledges should require air rescue.
- Rescue flow should tie into pilot roster survival, wounded/rest states, and career continuity rather than treating aircraft loss as the only consequence.

### Helicopters
- Continue building out the helicopter family around the existing Aircraft 9 rescue helicopter and Aircraft 10 scout helicopter.
- First useful roles: rescue/winch pickup for downed pilots, armed scout/attack helicopter, and gunship support.
- Controls and feel to keep tuning: analog collective, cyclic lag, yaw authority, rotor governor behavior, forward-flight trim, deck handling, and existing weapon inputs where possible.
- AI direction: use the dedicated `HelicopterPilot` as the first test bed for low-level terrain-aware flight. The current approach is local corridor sampling over terrain height, not a full aircraft navmesh/pathfinder yet.

### Codex
- In-game encyclopedia accessible from the pause menu
- 3D rotating model viewer per entry with description text below
- Covers vehicles and weapons

**Current focus:** As of 2026-07-16, the active work is air combat and carrier air operations — the dogfight AI (curved-lead gunnery, energy discipline, anti-stalemate behavior) and the AirOps/Citadel dynamic tasking brain, plus battlefield readability (map fog-of-war and the combat event log). Near-term follow-ups are in *Upcoming Fixes* above: even-fight gunnery conversion, launch cadence, and dogfight/aircraft balance. (Helicopter Aircraft 11 development and the heli test loop from the previous focus are paused, not dropped.)

## Working Style Notes

- Build iteratively and favor small, well-documented steps.
- Keep temporary structures easy to identify and remove later.
- Maintain the established project structure and move files into the correct folders when the design is clear.

## Additional Documentation

- [Pilot Portrait Catalog](Images/Pilot%20Portraits/pilot_portrait_catalog.csv) - maps all 100 pilot portrait filenames to apparent presentation plus semicolon-separated strong and additional regional fits. The region fields are deliberately loose casting suggestions for a culturally mixed fictional future, not claims about ancestry or nationality.
- [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md)
- [Land Carrier Track Mapping Problem](docs/Land%20Carrier%20Track%20Mapping%20Problem.md)
- [Land Carrier Bridge Jitter Problem](docs/Land%20Carrier%20Bridge%20Jitter%20Problem.md)
- [Controller Guide](docs/CONTROLLER_GUIDE.md)
