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
