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

The land carrier is the centerpiece of the game: a 200-meter-long tracked mobile fortress that serves as command center, airbase, logistics hub, and home. It carries aircraft, ground vehicles, elevator and catapult operations, arresting gear, tractor bots, defensive turrets, and an estimated complement of 250–350 souls — crew and their families. A folding rear ramp deploys for ground vehicle operations.

### Player Units

Aircraft are the primary player-flown vehicles and are meant to be modular, upgradeable, and recoverable. Ground vehicles are mostly AI controlled, but support the player's wider tactical plan.

### High-Level Gameplay Loop

The player pushes into enemy-controlled territory, launches and recovers aircraft, protects the carrier, attacks enemy positions, and gradually expands capability through resources, repairs, and upgrades.

## Current Status

**Last Updated:** 2026-03-22
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
| Flight Physics | Working | SimpleAero integration complete |
| AI Pilot | Working | Full carrier cycle exists; path-follower carrier recovery remains the default; hierarchy-of-needs safety layer (terrain avoidance > collision avoidance > state machine); terrain fan avoidance with directional escape sampling; dogfight proximity override breaks off ground attack when enemies close; CCIP ballistic sim throttled via caching |
| Catapult | Working | Launches AI and player aircraft |
| Arresting Cables | Working | Roll stabilization, mass-adaptive braking |
| Landing Gear | Working | Suspension/damping implemented; Aircraft 1 and 2 now use animated gear pivots instead of pop-in/out, with stowed visuals/shadows suppressed |
| Tailhook | Working | Auto-deploy/stow functional |

### Aircraft Systems

| System | Status | Notes |
|--------|--------|-------|
| Player Control | Working | Full manual flight control |
| AI Control | Working | All vehicles default to AI; Start toggles spectator/pilot takeover of nearest friendly aircraft; LB/RB cycles carrier + friendly aircraft while spectating; Space exits free camera to spectator; `L` now assigns the next eligible friendly aircraft to landing |
| Weapons | Working | Autocannon, bombs, missiles; bullets inherit muzzle-point velocity in turns and are now oriented to match actual velocity at spawn; autocannon ammo pool increased for sustained tests; AA missile launchers can now be intentionally fielded empty |
| Targeting | Working | HUD target box, sensor cone |
| HUD | Working | Radar, instruments, CCIP, terrain map overlay on radar; HUD symbology/text fully opaque, and the main gunsight now uses proper HUD-glass collimation/boresight projection |
| Camera System | Working | Multiple camera modes, free-fly debug camera, delayed death-camera handoff; chase camera now orbits the aircraft on a level horizontal plane; the old bridge cam has been replaced by a first-person commander view inside the carrier bridge |
| Destruction | Working | Explosion with volumetric smoke puffs (SphereMesh, staggered, rising/fading); ParticleManager autoload handles all particle lifecycle |
| Damage Effects | Working | 3-tier progressive damage system: hydraulic/fuel/flap failures, engine cap/control loss/HUD flicker, engine sputter/structural failure/HUD blackout; escalating smoke trails |

### Carrier Systems

| System | Status | Notes |
|--------|--------|-------|
| Flight Deck Manager | Partial | Orchestrates deck/hangar/catapult/recovery flow, scramble queues, and runtime aircraft persistence; now supports last-leg wave-offs when the deck is occupied, bolter/go-around recovery retries, and cleanup of extra tractor bots by sending them below via the elevator |
| Air Operations Manager | Working | Autoload (Citadel). Commands four named flights (Archer, Bulldog, Crimson, Dingo); intercept/CAS vectoring; scrambles from hangar when a flight has no members; radio comms throughout |
| Wing Fold (Aircraft 2) | Working | Wings fold in hangar/transport, unfold at catapult; instant-snap on spawn |
| Elevator | Working | Hangar <-> deck transit; aircraft tracks carrier horizontally |
| Tractor Bots | Working | Aircraft towing system; follow carrier as carrier children and now use shared wheel-node lookup instead of brittle hard-coded wheel names |
| Deck Lights | Working | Procedural light placement; center elevator-adjacent strips retuned and recolored yellow |
| Arresting Cables | Working | Multi-cable support |
| Carrier Movement Tracking | Working | All deck objects (parked, transport, catapult) move with carrier each frame |
| Vehicle Ramp | Working | Three-panel folding ramp at the carrier rear for ground vehicle deploy/recovery; uses existing GLB meshes; zig-zag fold with simultaneous hinge animation; dynamic terrain-tracking deploy angle; Z key toggles deploy/stow |
| Tracks | Working | Nav-grid A* pathfinding with path simplification; full-path computation (no more segmented replanning); steering response/deadzone/settle tuning; height deadband smoothing; tread belt UV rewritten to use baked path-based mapping from imported track mesh; new belt debug modes (path UV, cross UV, direction arrows); terrain-feeler wall avoidance; stuck detection; spawn faces first waypoint |
| Carrier Defensive Turrets | Working | Carrier defense mounts can now host dual functioning turrets per set and are wired through the shared turret controller/weapon stack; turret pitch calculation simplified and barrel forward derivation cleaned up |
| Bridge Commander | Working | First-person commander pawn with analog walk/look on the bridge; simple collision, warm bridge lighting, and bridge-view camera handoff integrated |
| Bridge Hologram | Working | 2 m centered wireframe tactical table with deep-green-to-neon-green terrain, blue/red 3D aircraft markers, blue/red ground-unit squares, raised carrier/ground markers, camera-gated low-frequency refresh, incremental multi-frame terrain rebuild, and waypoint path visualization (dots + lines); now runs in physics_process with interpolation for smoother carrier-relative motion; carrier plate enlarged |

### Current Carrier Troubleshooting Notes

- Tread mapping / visible split investigation: [Land Carrier Track Mapping Problem](docs/Land%20Carrier%20Track%20Mapping%20Problem.md)
- Bridge/commander jitter investigation: [Land Carrier Bridge Jitter Problem](docs/Land%20Carrier%20Bridge%20Jitter%20Problem.md)

### Enemy Systems

| System | Status | Notes |
|--------|--------|-------|
| Detection | Working | Sensor-based target acquisition |
| Weapons | Working | Autocannon with burst fire |
| Ballistics | Working | Lead calculation with gravity compensation; enemy turrets now use actual bullet speed from weapon for lead timing |
| Ground Snapping | Working | StaticBody3D terrain alignment |
| Movement | Partial | Aircraft behavior solid; ground vehicles now share NavGraph waypoint path-following with cooldown/backoff logic and fixed nav waypoint consumption to prevent infinite replan loops; movement/combat stance still being tuned |
| AI Behavior | Working | Carrier-centered patrol, dogfight, missile/gun choice, RTB/landing, lost-sight variation, and platoon-based ground vehicle objectives implemented; still being tuned |

### Environment

| System | Status | Notes |
|--------|--------|-------|
| Terrain | Working | Custom low-poly procedural terrain mesh with chunk streaming; `cell_size_m=12`; height quantization (6 m snap) for grid-aligned slopes |
| Terrain Shaping | Working | Flat areas now include subtle undulation/detail noise; cliffs/canyons deepened for stronger relief |
| Terrain Shader | Working | Slope-based coloring; sharp sand-to-grey border (`steep_slope_band`); per-face independent tint (no spatial bleeding) |
| Rock Scatter | Working | MultiMesh rocks placed at correct world height; atomic swap prevents popping |
| Lighting | Working | Directional + deck lights; soft shadows, split cascades, normal bias; shadow acne fixed |
| Post-Processing | Working | Filmic, glow, SSAO, fog |
| Weather | Planned | Not yet implemented |

## Current Agenda

1. Continue tuning AI precision control in dogfights so aircraft point more authoritatively at gun solutions, align the pipper with the real gun line, and waste fewer shots.
2. Validate the new default path-follower landing mode, especially touchdown wings-level behavior, wave-offs, and bolter/go-around retries.
3. Continue tuning terrain fan avoidance and collision avoidance — the hierarchy-of-needs safety layer is in but needs edge-case polish.
4. Continue tuning ground vehicle movement, combat stance, and pathing performance.
5. Expand the bridge experience with more environmental polish and commander-facing command-space features; waypoint visualization is now on the holomap.
6. Build out ground vehicle deployment flow using the new rear ramp — AI-driven drive-off/drive-on, deployment queuing, and integration with the vehicle bay.

**Current focus:** As of 2026-03-22, recent work added a three-panel folding vehicle deployment ramp at the carrier rear (VehicleRamp.gd) with zig-zag fold mechanics, simultaneous hinge animation, dynamic terrain-tracking angle, and Z-key toggle — using the existing ramp meshes from the carrier body GLB. Prior session work included AI terrain fan/collision avoidance, CCIP caching, baked tread belt UV mapping, full-path carrier navigation with path simplification, waypoint holomap visualization, turret cleanup, enemy ballistics improvements, and ground vehicle nav fixes. Active work continues on vehicle deployment flow, AI flight tuning, and bridge-command features.

## Working Style Notes

- Build iteratively and favor small, well-documented steps.
- Keep temporary structures easy to identify and remove later.
- Maintain the established project structure and move files into the correct folders when the design is clear.

## Additional Documentation

- [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md)
- [Land Carrier Track Mapping Problem](docs/Land%20Carrier%20Track%20Mapping%20Problem.md)
- [Land Carrier Bridge Jitter Problem](docs/Land%20Carrier%20Bridge%20Jitter%20Problem.md)
- [Controller Guide](docs/CONTROLLER_GUIDE.md)
