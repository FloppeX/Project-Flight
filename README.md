# Project Flight

This document is the short project brief for Project Flight. For version history, session summaries, and archived long-form notes, see [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md).

## Brief Description

Land Carrier is a single-player strategic action game inspired by Armourgeddon and Carrier Command. The player commands a massive tracked land carrier across a post-apocalyptic desert, launches aircraft, supports ground units, and balances offense with defense of the carrier itself.

There are no scripted missions. Each scenario is intended to support open-ended problem solving, with the player deciding how to use available aircraft, vehicles, and carrier systems to achieve the objective.

## Core Concept

### Aesthetic Vision

The project aims for a low-poly, flat-shaded look with an old-school Amiga feel.

### The World

The setting is a desert wasteland with mesas, cliffs, ruins, rock formations, fortified enemy positions, and resource locations. Weather is planned to matter to gameplay through turbulence, wind, and reduced visibility during dust storms.

### The Carrier

The land carrier is the centerpiece of the game: a 200-meter-long tracked mobile fortress that serves as command center, airbase, logistics hub, and home. It carries aircraft, ground vehicles, elevator and catapult operations, arresting gear, tractor bots, defensive turrets, and an estimated complement of 250-350 souls - crew and their families. A folding rear ramp deploys for ground vehicle operations.

### Player Units

Aircraft are the primary player-flown vehicles and are meant to be modular, upgradeable, and recoverable. Ground vehicles are mostly AI controlled, but support the player's wider tactical plan.

### High-Level Gameplay Loop

The player pushes into enemy-controlled territory, launches and recovers aircraft, protects the carrier, attacks enemy positions, and gradually expands capability through resources, repairs, and upgrades.

## Current Status

**Last Updated:** 2026-03-28
**Godot Version:** 4.4.1.stable.official.49a5bc7b6
**Project Health:** PLAYABLE
**Control Mode:** AI-by-default with spectator/pilot toggle (game controller)

### Local Godot Install

Portable Godot 4.4.1 is available on this machine for project checks and local runs:

- `C:\Users\jonto\tools\godot-4.4.1\Godot_v4.4.1-stable_win64.exe`
- `C:\Users\jonto\tools\godot-4.4.1\Godot_v4.4.1-stable_win64_console.exe`

Example project launch from this repo root:

```powershell
& "C:\Users\jonto\tools\godot-4.4.1\Godot_v4.4.1-stable_win64_console.exe" --path "C:\Godot projects\Project-Flight"
```

### Core Systems

| System | Status | Notes |
|--------|--------|-------|
| Flight Physics | Working | SimpleAero integration complete; aircraft thrust has been bumped across the roster and shared forward drag reduced so dives and acceleration feel less artificially capped |
| AI Pilot | Working | Full carrier cycle exists; path-follower carrier recovery remains the default; hierarchy-of-needs safety layer (terrain avoidance > collision avoidance > state machine); terrain fan avoidance with directional escape sampling; dogfight proximity override breaks off ground attack when enemies close; close-pass breakaway logic now reduces merge collisions; CCIP ballistic sim throttled via caching |
| Catapult | Working | Launches AI and player aircraft |
| Arresting Cables | Working | Roll stabilization, mass-adaptive braking |
| Landing Gear | Working | Suspension/damping implemented; Aircraft 1, 2, and 5 now use animated gear pivots instead of pop-in/out, with stowed visuals/shadows suppressed |
| Tailhook | Working | Auto-deploy/stow functional |

### Aircraft Systems

| System | Status | Notes |
|--------|--------|-------|
| Player Control | Working | Full manual flight control |
| AI Control | Working | All vehicles default to AI; Start toggles spectator/pilot takeover of nearest friendly aircraft; LB/RB cycles carrier + friendly aircraft while spectating; Space exits free camera to spectator; `L` now assigns the next eligible friendly aircraft to landing |
| Weapons | Working | Autocannon, bombs, missiles; bullets inherit muzzle-point velocity in turns and are oriented to match actual velocity at spawn; shared aircraft autocannon now fires at `1200 RPM`, uses `1000 m/s` muzzle velocity, and randomizes across the heavy auto-gun sound set for less repetitive bursts; autocannon ammo pool increased for sustained tests; AA missile launchers can now be intentionally fielded empty |
| Targeting | Working | HUD target box, sensor cone |
| HUD | Working | Radar, instruments, CCIP, terrain map overlay on radar; HUD symbology/text fully opaque, and the main gunsight now uses proper HUD-glass collimation/boresight projection |
| Camera System | Working | Multiple camera modes, free-fly debug camera, delayed death-camera handoff; chase camera now orbits the aircraft on a level horizontal plane; the old bridge cam has been replaced by a first-person commander view inside the carrier bridge |
| Destruction | Working | Explosion with volumetric smoke puffs (SphereMesh, staggered, rising/fading); ParticleManager autoload handles all particle lifecycle; enemy barracks bases spawn on flat terrain; high-altitude aircraft kills now skip the bright multichunk wreck breakup so floating debris clouds do not appear in the sky |
| Damage Effects | Working | 3-tier progressive damage system: hydraulic/fuel/flap failures, engine cap/control loss/HUD flicker, engine sputter/structural failure/HUD blackout; escalating smoke trails |

### Carrier Systems

| System | Status | Notes |
|--------|--------|-------|
| Flight Deck Manager | Partial | Orchestrates deck/hangar/catapult/recovery flow, scramble queues, and runtime aircraft persistence; now supports last-leg wave-offs when the deck is occupied, bolter/go-around recovery retries, and cleanup of extra tractor bots by sending them below via the elevator |
| Air Operations Manager | Working | Autoload (Citadel). Commands four named flights (Archer, Bulldog, Crimson, Dingo); intercept/CAS vectoring; player-facing tactical-map orders now support CAP routes, CAS tasking, and RTB; empty flights auto-scramble from the hangar when manually ordered; radio comms throughout |
| Wing Fold (Aircraft 2) | Working | Wings fold in hangar/transport, unfold at catapult; instant-snap on spawn |
| Wing Fold (Aircraft 5) | Working | Multi-phase fold: lateral slide, then overlapping X/Y rotations with smoothstep easing; mirrored left-wing geometry handled with flipped X sign |
| Elevator | Working | Hangar <-> deck transit; aircraft tracks carrier horizontally |
| Tractor Bots | Working | Aircraft towing system; follow carrier as carrier children and now use shared wheel-node lookup instead of brittle hard-coded wheel names |
| Deck Lights | Working | Procedural SpotLight3D placement (downward-facing, no bleed into dust/sky); center elevator-adjacent strips retuned and recolored yellow |
| Arresting Cables | Working | Multi-cable support |
| Carrier Movement Tracking | Working | All deck objects (parked, transport, catapult) move with carrier each frame |
| Vehicle Ramp | Working | Three-panel folding ramp at the carrier rear for ground vehicle deploy/recovery; uses existing GLB meshes; zig-zag fold with simultaneous hinge animation; dynamic terrain-tracking deploy angle; Z key toggles deploy/stow |
| Vehicle Bay Manager | Working | Manages ground vehicle deployment and retrieval via the rear ramp; spawns vehicles on the bay floor, drives them down the ramp at 3s intervals; retrieval rallies all platoon members behind the carrier, deploys ramp when first vehicle arrives, drives them up one at a time; auto-stows ramp after completion; carrier-local positioning during ramp transit so everything works while the carrier moves |
| Ground Ops Manager | Working | Autoload singleton managing four named platoons (Ember, Ferret, Grizzly, Hammer); V deploys next empty platoon, B retrieves last deployed, N requests carrier escort; commands: move, attack, protect, escort, pursue, hold, retrieve; the tactical map can now issue point-based MOVE / ATTACK / PROTECT / ESCORT / HOLD / RETRIEVE orders; empty platoons auto-deploy when given a task and preserve that queued objective through deployment instead of defaulting back to escort; carrier escort places vehicles at carrier corners with velocity matching; platoons use simple formation slots, pace to the slowest member when out of combat, break formation during combat, and reform afterward; ground staging now prefers carrier-reachable terrain with a larger buffer from steep slopes/cliffs |
| Tracks | Working | Nav-grid A* pathfinding with path simplification; full-path computation (no more segmented replanning); steering response/deadzone/settle tuning; height deadband smoothing; tread belt UV rewritten to use baked path-based mapping from imported track mesh; new belt debug modes (path UV, cross UV, direction arrows); terrain-feeler wall avoidance; stuck detection; spawn faces first waypoint |
| Carrier Defensive Turrets | Working | Carrier defense mounts can now host dual functioning turrets per set and are wired through the shared turret controller/weapon stack; turret pitch calculation simplified and barrel forward derivation cleaned up |
| Bridge Commander | Working | First-person commander pawn with analog walk/look on the bridge; simple collision, warm bridge lighting, and bridge-view camera handoff integrated |
| Bridge Hologram | Working | 2 m centered wireframe tactical table with deep-green-to-neon-green terrain, blue/red 3D aircraft markers, blue/red ground-unit cubes, raised carrier/ground markers, camera-gated low-frequency refresh, incremental multi-frame terrain rebuild, and waypoint path visualization (dots + lines); enemy platoons show as medium red cubes only when actually observed via friendly terrain line-of-sight, and enemy ground vehicles do not split into individual markers until those specific vehicles are visually revealable; now runs in physics_process with interpolation for smoother carrier-relative motion; carrier plate enlarged |
| World Map | Working | Full-screen tactical map on `M`; fixed `25 km x 25 km` terrain/nav window with live holomap-style symbols layered over an interactive phosphor command display; terrain now reads in three solid green elevation bands for fast silhouette recognition; carrier/platoon routes and enemy counters render directly on the map; enemy platoons stay visible as abstract hot-pink contacts while individual enemy vehicles still require visual reveal; the first playable command layer now supports selecting named flights/platoons, drafting missions, clicking map targets, CAP route authoring, and confirming orders from the map itself |

### Workflow / Debug

| System | Status | Notes |
|--------|--------|-------|
| Screenshot Capture | Working | `Insert` saves screenshots to the project-root `screenshots/` folder for review/debugging |

### Current Carrier Troubleshooting Notes

- Tread mapping / visible split investigation: [Land Carrier Track Mapping Problem](docs/Land%20Carrier%20Track%20Mapping%20Problem.md)
- Bridge/commander jitter investigation: [Land Carrier Bridge Jitter Problem](docs/Land%20Carrier%20Bridge%20Jitter%20Problem.md)

### Enemy Systems

| System | Status | Notes |
|--------|--------|-------|
| Detection | Working | Sensor-based target acquisition |
| Weapons | Working | Autocannon with burst fire; enemy ground roster now includes buggy, pickup, and battle bus variants; battle bus mounts an LMG plus a heavy gun that fires smaller explosive rounds, but its anti-air performance has been deliberately softened so it is threatening without feeling like precision flak |
| Ballistics | Working | Lead calculation with gravity compensation; enemy turrets now use actual bullet speed from weapon for lead timing |
| Ground Snapping | Working | StaticBody3D terrain alignment |
| Movement | Working | Aircraft behavior solid; ground vehicles use spring-damper suspension with chassis floating above ground and all wheels in contact (works on terrain and carrier ramp); forward-axis velocity projection; larger turn radii; elliptical carrier avoidance with tangential flow steering; enemy/friendly platoon and vehicle staging validates carrier-reachable flat ground with larger margins from steep terrain; enemy vehicles now anchor destinations more carefully and reject direct segments that would climb steep slopes; abstract platoon contacts follow nav-safe representative routes instead of tunneling through mountains; movement/combat stance still being tuned |
| AI Behavior | Working | Carrier-centered patrol, dogfight, missile/gun choice, RTB/landing, lost-sight variation, and platoon-based ground vehicle objectives implemented; ground vehicles hold position once arrived (30m hysteresis), avoid siblings during retrieval rally, and use formation/rejoin behavior for platoon travel; escort positions prioritize front corners; friendly debug-spawned aircraft can now be kept in a shared flight; close-pass breakaway logic now reduces head-on air-to-air collisions; enemy vehicle gunnery is intentionally inaccurate but permissive, so they shoot often without feeling too dead-eye; still being tuned |

### Environment

| System | Status | Notes |
|--------|--------|-------|
| Terrain | Working | Custom low-poly procedural terrain mesh with chunk streaming around the active camera plus forward preload; `cell_size_m=12`; height quantization (6 m snap) for grid-aligned slopes; adaptive quad triangulation removes the old repeating cliff-face washboard pattern while keeping flat shading; current baked navigation / tactical-map coverage is `25 km x 25 km` even though the terrain system itself supports a much larger playspace |
| Terrain Shaping | Working | Flat areas now include subtle undulation/detail noise; cliffs/canyons deepened for stronger relief |
| Terrain Shader | Working | Slope-based coloring; sharp sand-to-grey border (`steep_slope_band`); per-face independent tint (no spatial bleeding) |
| Rock Scatter | Working | MultiMesh rocks placed at correct world height; atomic swap prevents popping |
| Lighting | Working | Directional + deck SpotLights; soft shadows, 8K atlas, blended cascade splits, normal bias; shadow acne fixed |
| Post-Processing | Working | Filmic, glow, SSAO, fog |
| Weather | Planned | Not yet implemented, though turbulence/wind tuning is actively being iterated |

## Current Agenda

1. Validate the new interactive `M`-map workflow in live play: asset selection, mission drafting, confirm/cancel flow, and readability under pressure.
2. Expand mission authoring beyond the first slice, especially richer waypoint editing and more flight directives than the current CAP / CAS / RTB set.
3. Continue tuning AI precision control in dogfights so aircraft point more authoritatively at gun solutions, align the pipper with the real gun line, and waste fewer shots while still breaking off unsafe close merges.
4. Validate the default path-follower landing mode, especially touchdown wings-level behavior, wave-offs, and bolter/go-around retries.
5. Continue tuning ground vehicle movement, steep-slope avoidance, spotting, and pathing performance, especially with multiple active platoons.
6. Recheck terrain streaming and far-edge cases so delayed terrain/collision chunks do not reopen "edge of the world" failures.
7. Continue expanding bridge/commander command features and allow AirOps/GroundOps AI to create and manage missions through the same order model the player uses.

**Current focus:** As of 2026-03-28, current work is centered on tactical command readability and player-directed ops. The `M` map is now the first playable command console for assigning flights and platoons, while the surrounding systems continue to be tuned so route previews, platoon abstraction, terrain safety, and actual AI behavior stay in sync.

## Working Style Notes

- Build iteratively and favor small, well-documented steps.
- Keep temporary structures easy to identify and remove later.
- Maintain the established project structure and move files into the correct folders when the design is clear.

## Additional Documentation

- [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md)
- [Land Carrier Track Mapping Problem](docs/Land%20Carrier%20Track%20Mapping%20Problem.md)
- [Land Carrier Bridge Jitter Problem](docs/Land%20Carrier%20Bridge%20Jitter%20Problem.md)
- [Controller Guide](docs/CONTROLLER_GUIDE.md)
