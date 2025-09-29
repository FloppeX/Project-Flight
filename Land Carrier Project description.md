## Project Change Log (latest session)

### Session Summary (2025-09-26)
*   **Flight Deck Cycle Automation**:
	*   Implemented a complete, robust cycle for landing, hangar storage, retrieval, and launch, all orchestrated by the `FlightDeckManager`.
	*   Added a visual-only tractorbot system. Three disk-shaped bots move to the aircraft's gear colliders, while the `FlightDeckManager` handles the actual aircraft movement (with physics disabled) for a convincing towing effect.
	*   The elevator is now fully integrated, correctly descending with the aircraft and bots, and returning to the flight deck after operations.
	*   Ensured that throughout all movement and elevator sequences, the aircraft's gear colliders and the tractorbots maintain a constant, exact height of 0.2 meters above the flight deck or elevator platform.
*   **Arresting Cable & Aircraft Stabilization**:
	*   Added a roll-stabilizing and leveling torque to the `ArrestingCable` logic. When an aircraft engages a cable, this force counteracts roll, preventing the aircraft from flipping over.
*   **Environment and Visual Enhancements**:
	*   Created a `DeckLights` system that procedurally places green centerline and white edge lights along the flight deck using start/end markers.
	*   Implemented a custom, unshaded terrain shader that colors the landscape based on slope—sandy brown for flat areas and gray for steep slopes—to better match the project's low-poly aesthetic.
	*   Developed a performant, camera-centered rock scattering system (`RockStream`) that uses Poisson-disk sampling to distribute rocks deterministically in a ring around the camera, streaming them in and out for performance.

### Session Summary (2025-09-23)
*   **Cameras**
	*   Bridge camera: fixed discovery via `carrier_cam` group, robust aircraft/camera lookup, horizontal `look_at()` with 180° yaw correction, and smoothed pitch tracking.
	*   Cinematic camera: positions 100–200 m ahead of aircraft with random ±30 m horizontal and 0–30 m vertical offsets, relative to aircraft axes (no ground snapping).
*   **Scorch Marks / Decals**
	*   Explosion and bullet decals now project cleanly: use decal projection-from-above (Basis.IDENTITY + random yaw), increased projection depth, minimal surface offset, and bullet marks attach to aircraft so they move with it.
*   **HUD / Radar**
	*   Carrier is drawn as a blue rectangle, size ~two enemy dots wide, positioned/oriented correctly from aircraft frame; applied +90° visual rotation for alignment.
*   **Landing Gear Suspension**
	*   Documented spring/damping parameters in `addons/simplified_flightsim/.../LandingGear.gd` and noted overrides in `Aircraft/Aircraft 1/Aircraft 1.tscn`.
*   **Environment & Lighting**
	*   Enabled Filmic tonemap, Glow, SSAO, Volumetric Fog; added a deck `ReflectionProbe`.
	*   Added dust layer as separate scene `Environment/DustLayer.tscn` (height 800 m with falloff) to preserve environment fog while allowing clear air above.
	*   Tweaked directional light shadow bias/normal bias/blur to reduce flicker and striping on aircraft.
*   **Arresting Cable Stabilization**
	*   Added roll damping and signed-angle roll leveling torque when cable engaged to prevent flip-overs; tunable gains exported.
*   **Carrier Deck Lights**
	*   New `LandCarrier/DeckLights.tscn` + `DeckLights.gd`: generates green centerline lights at 6 m spacing and white edge rows at configurable offset; billboard material fix (`billboard_mode` on material).
*   **Stability**
	*   Resolved a main scene corruption by restoring `Main_Scene.tscn` and instancing the dust layer as a separate scene.

### Session Summary (2025-09-20)
*   **Enemy Stability:** Fixed critical issue where ground units (`EnemyBox`) would fall through terrain or teleport to the world origin. This was resolved by converting them from `RigidBody3D` to `StaticBody3D` and implementing a robust ground-snapping mechanism, ensuring they remain firmly on the terrain.
*   **HUD Overhaul:**
	*   **Target Box:** Implemented a properly collimated green target box on the HUD. The box is now projected onto a 3D plane, eliminating parallax and ensuring it accurately frames the selected target from the pilot's perspective.
	*   **CCIP Collimation:** Applied the same ray-plane intersection logic to the CCIP (bomb impact point) display, making it accurately collimated with the 3D world.
*   **Targeting System:** The aircraft's targeting module now correctly detects when a target has been destroyed and automatically clears the target, preventing players from staying locked onto defeated enemies.
*   **Projectile & Explosion FX:**
	*   **Delayed Explosions:** Added a randomized 0-1 second delay before an enemy explodes after its health reaches zero, improving the visual feedback of destruction.
	*   **Bomb Damage:** Corrected an issue where the bomb launcher was overriding the bomb projectile's properties. Bombs now correctly use their intended splash damage radius of 30 meters, consistent with AG missiles, making them effective area-denial weapons.
*   **Landing Gear Suspension:** Implemented suspension system with damping for smoother landings and enhanced immersion during carrier operations (launching and landing).
*   **Bullet Collision System:** Fixed critical issue where bullets were inconsistently hitting aircraft (1 in 20 hit rate). Resolved logic flow bug in projectile collision detection and implemented smart damage targeting system. Added bullet impact sounds and scorch marks on aircraft surfaces.
*   **Enemy Weapon Integration:** Refactored enemy boxes to use the same weapon system as aircraft (Autocannon.tscn) instead of custom bullet code. Implemented burst firing system with configurable burst length and delay timing.
*   **Enhanced Enemy Ballistics:** Upgraded enemy targeting with iterative lead calculation, drag compensation, and gravity drop accounting for more realistic and challenging combat.

### Core systems
- Catapult
  - Uses `controls_disabled` meta on aircraft during launch; restores on release.
  - Engine spool-up/hold sequence driven by timers (3s ramp, 3s hold).
  - Immobilizes main wheels during latch with `PinJoint3D`; releases on launch.
  - Force-based towing replaced springy coupling; PD force applied at nose gear during shuttle run.

- Engine/Controls
  - `ControlEngine.gd` respects `controls_disabled` (skips input/auto-stop when set).
  - `Engine.gd` `set_throttle_input()` directly sets power when engine running to avoid start-up race.

- Landing Gear
  - Added parking brake meta support: when `parking_brake` is set, directional damping engages even if `controls_disabled` is present.

- Arresting Cable
  - Added signals: `cable_engaged(aircraft)` and `cable_released(aircraft)`; grouped as `arresting_cable`.
  - Stores a reference to itself on the aircraft meta (`arresting_cable`) while engaged.
  - Exposes `manual_release()` for external control; restores gear friction on release.

- Flight Deck Manager
  - Auto-connects to all arresting cables (initial and dynamically added).
  - On cable engage: disables controls, ramps throttle down over 3s, waits 3s, releases cable, sets `parking_brake`, and dispatches tractor.
  - Tailhook auto-stow on cable release and as a fallback after manual release.
  - Added robust polling fallback for arrests (guarded to not conflict with the timed sequence).

### Tailhook
- `TailhookSimple.gd`
  - Added `ModuleType = "tailhook"` and ensures nodes are in `tailhook` group.
  - `stow()` disables colliders and visibility to prevent re-snagging.

### Tractor Bot
- Scene
  - New: `LandCarrier/TractorBot.tscn` with body, collision, `NavAgent`, tow arm (`TowArm`), visual cylinder, `Tip` marker, and `RopeAnchor` marker.
  - Optional `HitchBody` under `TowArm` for arm-attach mode.

- Script: `LandCarrier/TractorBot.gd`
  - States: IDLE → MOVING_TO_AIRCRAFT → COUPLING → TOWING_TO_DESTINATION → (DISCONNECTING) → UNCOUPLING → RETURNING_TO_STAGING.
  - Reverse towing: faces and pulls the aircraft while driving in reverse; slows near destination.
  - Two modes:
	- Arm mode: extend arm, optional `PinJoint3D` at `TowArm/Tip` to aircraft; keeps arm extended during towing.
	- Rope mode (default): virtual rope with `rope_length_m` (2 m); only pulls when stretched beyond length.
  - Exports and markers:
	- `approach_a_marker`, `approach_b_marker` for elevator approach flow.
	- `elevator_marker` for final placement and disconnect; `disconnect_distance_m` (horizontal) controls dropout threshold.
	- Speed/handling: `cruise_speed_mps`, `tow_speed_mps`, `accel_mps2`, `turn_speed_deg_s`, `turn_in_place_deg` (turn-in-place on approach only).
	- Towing PD tuning: `tow_kp`, `tow_kv`, `tow_force_limit`, `tow_force_smoothing_s`.
  - Flow:
	- Approach plane, stop; in arm mode aim/extend; latch (arm or rope).
	- Phase 0: tow toward Approach A; Phase 1: toward Approach B (slower).
	- Drop rope when aircraft center within `disconnect_distance_m` (XZ) of `elevator_marker`; bot continues to B then staging.
	- After disconnect, sets aircraft `parking_brake` to hold position; prevents re-coupling with `_latched` guard.

### Misc
- Exported and used `controls_disabled`, `parking_brake`, `arresting_cable` metas consistently across systems.
- Added robust lookup helpers for engine controller, engine, nose gear, and tailhook modules.

### HUD: Radar and Targeting Displays
- Enemy registry: Added `Enemies/EnemyRegistry.gd` as an autoload to maintain a shared list of enemies per team.
- Targeting module: New `AircraftModule_ControlTargeting` finds targets in a ±30–60° cone and cycles via inputs (E/Q, X to clear).
- Instrument panel UI: Top row preserved; added a lower HBox with two square displays:
  - Left: Radar map showing known enemies within 5 km, top-down relative to aircraft.
  - Right: Target view using a dedicated `SubViewport` + `Camera3D` to show the currently targeted enemy.
- Inputs: Added `target_next` (E), `target_prev` (Q), `target_clear` (X) to `project.godot`.

### Notes / Next steps
- Tractor pathing: if circling or stalls occur, confirm `approach_a_marker`, `approach_b_marker`, and `elevator_marker` assignments, and consider enabling a deck `NavigationRegion3D` for `NavAgent`.
- If a rigid rope is preferred, replace virtual rope with a tuned `Generic6DOFJoint3D` (linear limit on one axis), but this needs careful axis setup per scene orientation.
The Land Carrier Project
Welcome to the Land Carrier project. This document serves as an initial overview, providing the foundational concepts and vision for the game before we dive into the detailed development roadmap. The aim is to give AI assistants a clear understanding of the project's essence to better assist with subsequent coding and design tasks.

Core Concept & Inspiration
Land Carrier is a strategic action game heavily inspired by classics like Armourgeddon and Carrier Command. I envision a unique blend of real-time tactical air combat and commanding a massive, mobile base. This will be a single player game. There will be no scripted missions. Each scenario will involve the player using the resources at his disposal to achieve the mission goals any way they see fit.

Aesthetic Vision
The game will feature a distinct "low-poly" aesthetic with flat shading. The goal is to evoke an "old school Amiga vibe," creating a visually recognizable and charming retro-inspired look.

The Game World
The setting is a post-apocalyptic desert landscape. While largely flat, the terrain will include varied features such as:
	  Elevations and depressions
	  Stony areas and rock formations
	  Mesas
	  Ancient ruins, hinting at a collapsed civilization
	  Resource zones, where materials can be collected.
	  Fortified enemy bases
A dynamic weather system will impact gameplay, featuring turbulence and wind affecting flight, and dust storms reducing visibility for all units.

The Land Carrier
At the heart of the game is the eponymous Land Carrier. Unlike traditional ships, this is a colossal, track-driven mobile fortress. It is 200 meters long, towers 35 meters above the ground and moves on six massive tracks (three per side). It's designed to be a self-contained command center, equipped with defensive weapon turrets and capable of deploying both aerial and ground vehicles.

Player Units
Aircraft: Players will manage and fly a fleet of propeller-driven aircraft. Initially simple, they will evolve into more advanced models with diverse payloads. A key design element is their modularity, allowing for customization and potentially in-game crafting/repair of components like engines, steering, and landing gear.
Ground Vehicles: A variety of ground units, including tanks and scout buggies, will complement the air force. These are controlled by AI but can, to a limited extent, be commanded by the player.

High-Level Gameplay Loop
The primary objective involves attacking and "liberating" enemy-held areas. This will require a strategic balance between offensive maneuvers and the critical defense of the Land Carrier itself.

Development Approach for AI Assistants
As we embark on this project, please keep the following guidelines in mind:
	  Iterative Development: Focus on incremental progress, one step at a time. Ask questions to clarify implementations. Confirm before creating structures or code. Do not bite off large chunks - nibble one piece at a time.
	  Clear Documentation: Document all changes within scripts comprehensively.
	  Reduce clutter: Clearly mark any temporary structures or test code for easy identification and future removal. Also mark unused and redundant structures and move to an archive folder.
	  Adhere to Structure: Maintain consistency with the established project structure. Clean up and move files to the correct folder. Create folders if needed, but confirm first.

Current Tasks
I. Aircraft Systems
Landing Gear
	  Current State: Deployable and retractable. Each wheel has a collider.
	  Required: Each wheel should be connected to its mesh, potentially under one Rigidbody node per wheel.
	  Enhancement: Implement suspension with damping for smoother landings and enhanced immersion during carrier operations (launching and landing).
Tail Hook
	  Required: Each aircraft needs a tailhook.
	  Functionality: A metal hook extending from the rear when gear is deployed, designed to catch arresting wires on the carrier deck during landing.
Targeting System
	  Sensors: Aircraft sensors should search for enemies within a forward-extending cone.
	  HUD Display: A diamond shape should be projected on the HUD to indicate the enemy's location.
	  Instrument Panel Display: A zoomed-in view of the targeted enemy should be shown on the instrument panel.
Destruction Mechanics ("Blowing Up")
	  Trigger: A vehicle is destroyed when its hit points are reduced to 0.
	  Player View (Aircraft): When the player's aircraft is destroyed, the view switches to an outside camera that rotates slowly around the point of destruction.
	  Visuals: The aircraft mesh is removed and replaced with wreckage parts that fall and collide with terrain.
Flight & Control Model
	  Aerodynamics: Aircraft use a simplified aerodynamic model (SimpleAero.gd) including lift, drag, and stall.
	  Turbulence: Continuous turbulence (ContinuousTurbulence.gd) and wind vectors apply forces dynamically.
	  AI Pilot System: AI-controlled aircraft use the same inputs as the player (aileron, elevator, rudder, throttle, gear, weapons). Core states: Launch, Navigate, Attack, Defend, Land. AI selects a waypoint and adjusts inputs to reach it.
Cameras
	  Managed via CameraManager.gd and CameraTripod.gd.
	  Modes: cockpit (default), chase, orbit, cinematic tripod.
	  External orbit view activates on destruction.
Pilot Interface
	  HUD: target diamonds, CCIP bomb marker, flight path indicator.
	  Instruments: artificial horizon (InstrumentAttitude.gd), speed, altitude.

II. Enemies
Current State
	  Enemies currently have health, can detect targets, and possess a turret with an autocannon, which they use to fire at detected targets.
Required
	  Implement movement capabilities.
	  Assign a mesh.
	  Develop rudimentary AI for decision-making.
	  Implement simple pathfinding.

Future Enhancements
	  Expand to mobile AAA vehicles, missile launchers, and patrol aircraft.
	  Behavior system: patrol, pursue, engage, retreat.
	  Escalation: tougher enemies appear as the player captures territory.


III. Land Carrier Systems
Tracks
	  Current State: Six Rigidbody tracks acting as contact points with the ground.
	  Required: Each track must be fixed horizontally relative to the carrier.
	  Enhancement: Allow vertical movement with damping suspension. Front and rear sets of tracks should rotate slightly along the horizontal axis when the carrier turns.

Elevator System
	  Description: A central 20x20m shaft for moving aircraft from the hangar to the flight deck.
	  Functionality: When an aircraft is ready, the elevator lowers, the aircraft is spawned on the platform, and the elevator raises.

	  Enhancement: Implement cover "plates" that slide in from the sides to cover the opening when the elevator is lowered.
Catapult
	  Functionality: After an aircraft reaches the flight deck, it moves to the catapult.
	  Interaction: The aircraft becomes enabled. Player input (button press) propels the plane forward until it leaves the flight deck, after which it flies under its own power.

Arresting Cables
	  Functionality: One or more cables at the back of the carrier extend across the landing area.
	  Interaction: These cables are caught by an aircraft's tailhook, bringing the aircraft to a quick and smooth stop.
Tractor Bots
	  Functionality: When an aircraft needs to be moved on the flight deck, three flat little  bots  are spawned and move to the aircraft's wheels. Each bot  lifts up  its wheel. The aircraft can then be slid around, giving the illusion that they are moving it.
	  Triggers:
		? When an aircraft has landed and come to a stop on the flight deck, it is moved to the elevator and despawned.
		? When an aircraft is spawned, raised with the elevator, and moved to the catapult.

Carrier Defenses
	  Turrets: Autocannons and missile batteries.
	  Control: Can be AI-operated or player-operated via command interface.
Command Interface
	  RTS-style zoomed-out view for ordering carrier defenses, aircraft, and ground vehicles.

IV. Weapons Systems
Weapon Types
	  Current State: Autocannons and bombs.
	  Future: Rockets, missiles, torpedoes (if aquatic maps added).
	  Integration: Weapons are carried on aircraft hardpoints.
Weapon Switching & Firing
	  Mechanism: Player has a button to switch between active weapons.
	  Firing: Pressing the fire button fires all instances of the currently active weapon type.
Bombs Specifics
	  Physics: Low drag, predictable fall path.
	  Arming: Should arm approximately one second after being dropped.
	  Firing Logic: Each press should only launch one bomb from each bomb weapon instance.
CCIP (Continuously Computed Impact Point) for Bombs
	  Required: A CCIP display on the HUD when bombs are armed.
	  Functionality: Continuously shows the estimated impact point of a dropped bomb.
	  Update Rate: Does not need to update every tick; ~5 updates per second is sufficient.

V. Graphics & Presentation
Aesthetic
	  Low-poly meshes with flat shading and minimal textures.
	  Retro palette designed to evoke Amiga-era games.
Terrain & Environment
	  Terrain meshes use LOD to reduce vertex load.
	  Procedural scatter of rocks, shrubs, ruins for scale and altitude cues (Poisson disk or jitter).
	  Ruins and mesas add verticality and cover.
Effects
	  Dust storms: reduce visibility and introduce turbulence.
	  Explosions: debris meshes with physics.
	  Lighting: carrier deck lights, aircraft navigation lights, night effects.
Performance Settings
	  Adjustable terrain LOD and shadow quality.
	  Texture filtering options.
	  Ability to disable cockpit interiors for low-spec systems.

VI. Strategy & Progression
Resource Management
	  Aircraft consume fuel and ammo.
	  Returning to carrier refuels and rearms.
Repairs
	  Damaged aircraft can be despawned into the hangar for repair (resource cost).
Upgrades
	  Capturing enemy outposts unlocks new weapons, aircraft, and carrier defenses.
Enemy Escalation
	  Enemy counter-attacks increase in intensity as the player expands territory.
	  Forces the player to balance offense and defense.

VII. Future Work / Open Questions
These items are not yet fully designed and should be explored further:
Gameplay Systems
	  How will resources (fuel, ammo, repair parts) be represented numerically? Flat pool, or per-unit tracking?
	  Should there be crew/AI staff management aboard the carrier?
	  How do players lose? Is the game over only if the carrier is destroyed, or can territory loss also trigger defeat?
Graphics & Audio
	  Determine final retro-inspired palette (fixed 256 colors vs flexible HDR pipeline).
	  Sound design approach: authentic retro synth FX vs more modern soundscape.
	  Weather visuals: dust storms, lightning, heavy rain (possible expansion).
AI & Pathfinding
	  Aircraft AI landing logic still open: should they use full carrier approach patterns, or simplified  snap  behaviors?
	  Ground vehicle pathfinding over rugged terrain may need navmesh + off-mesh links.
Vehicle ideas
	  Helicopters
	  Hovercraft
	  Artillery (stationary and self propelled)
Pilot Ejection & Rescue
	  Pilot Ejection: A pilot can eject before an aircraft explodes. The canopy shoots off, and the pilot in his seat is propelled upward. The seat then detaches, and the parachute opens. The pilot floats to the ground.

	  Rescue: Ejected pilots wait on the ground to be rescued either by a ground vehicle or a rescue helicopter.

Session Summary (2025-09-14)
	Catapult
		Implemented robust teleport + settle alignment (collisions disabled during placement, deferred finalize), updated for +Z deck forward, added heading offset, and nose-gear-targeted shuttle approach with Area3D-only latch.
	Arresting Cables
		Aligned braking axis to +Z when selected, clarified parameters (braking_spring_stiffness_n_per_m, braking_damping_n_s_per_m, lateral_centering_stiffness_n_per_m, lateral_damping_n_s_per_m).
	Landing Gear & Tailhook Control
		Unified toggle: gear and tailhook alternate stow/deploy; start state forced (gear deployed, tailhook stowed). Added resilient module discovery and optional direct collider/visual control.
	Deck Forward Convention
		Updated systems to support carrier +Z as forward.
	Documentation & Debugging
		Added concise in-code comments and targeted debug logs for alignment, latching, and gear.

Coming Plans
	Catapult
		Finalize launch stroke tuning, release/return cycle, and interlocks; small UI indicator for latch/ready.
	FlightDeckManager
		Introduce central manager to orchestrate catapult, elevator, tractor bots, and aircraft tasks.
	Tractor Bots
		Implement CharacterBody3D bots that attach to wheels, lift, and translate aircraft to/from catapult and elevator.
	Arresting System
		Tune spring/damper values, consider multi-cable setup and refined lateral control.
	Cleanup
		Remove unused pickup-align path, consolidate deck-forward settings, and document editor assignments for gear colliders/visuals.

## Particle System

### ParticleManager (ParticleManager.gd)
A global singleton that manages all visual particle effects independently of their creators:

**Features:**
- **Global management**: All particles are handled centrally, ensuring they persist even after their creator is destroyed
- **Multiple particle types**: Supports different behaviors for different visual effects
- **Automatic cleanup**: Particles remove themselves after their lifetime expires
- **Extensible system**: Easy to add new particle types and behaviors

**Particle Types:**
- **Smoke**: Shrinks over time (used for missile trails)
- **Explosion**: Grows and fades out (for explosion effects)
- **Spark**: Moves with physics and gravity (for impact sparks)
- **Default**: Basic fade-out behavior

**Usage:**
```gdscript
# Get or create particle manager
var particle_manager = get_node_or_null("/root/ParticleManager")
if not particle_manager:
	particle_manager = preload("res://ParticleManager.gd").new()
	particle_manager.name = "ParticleManager"
	get_tree().root.add_child(particle_manager)

# Add particles
particle_manager.add_smoke_particle(mesh_instance, 1.5, Vector3(2.0, 2.0, 2.0))
particle_manager.add_explosion_particle(mesh_instance, 0.5, Vector3(1.0, 1.0, 1.0))
particle_manager.add_spark_particle(mesh_instance, 2.0, Vector3(0.5, 0.5, 0.5), velocity)
```

**Implementation Details:**
- Particles are MeshInstance3D nodes with materials
- Each particle has a type, lifetime, and initial scale
- Update behaviors are defined per particle type in the manager
- The system ensures visual effects persist naturally even when their source is destroyed
