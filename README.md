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

The land carrier is the centerpiece of the game: a 200-meter-long tracked mobile fortress that serves as command center, airbase, and logistics hub. It carries aircraft, ground support systems, elevator and catapult operations, arresting gear, tractor bots, and defensive turrets.

### Player Units

Aircraft are the primary player-flown vehicles and are meant to be modular, upgradeable, and recoverable. Ground vehicles are mostly AI controlled, but support the player's wider tactical plan.

### High-Level Gameplay Loop

The player pushes into enemy-controlled territory, launches and recovers aircraft, protects the carrier, attacks enemy positions, and gradually expands capability through resources, repairs, and upgrades.

## Current Status

**Last Updated:** 2026-03-17
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
| AI Pilot | Working | Full carrier cycle exists; carrier approach now uses authored approach markers/heights and is under active landing-pattern tuning |
| Catapult | Working | Launches AI and player aircraft |
| Arresting Cables | Working | Roll stabilization, mass-adaptive braking |
| Landing Gear | Working | Suspension/damping implemented; Aircraft 1 and 2 now use animated gear pivots instead of pop-in/out, with stowed visuals/shadows suppressed |
| Tailhook | Working | Auto-deploy/stow functional |

### Aircraft Systems

| System | Status | Notes |
|--------|--------|-------|
| Player Control | Working | Full manual flight control |
| AI Control | Working | All vehicles default to AI; Start toggles spectator/pilot takeover of nearest friendly aircraft; LB/RB cycles carrier + friendly aircraft while spectating; Space exits free camera to spectator |
| Weapons | Working | Autocannon, bombs, missiles |
| Targeting | Working | HUD target box, sensor cone |
| HUD | Working | Radar, instruments, CCIP, terrain map overlay on radar; HUD symbology/text now fully opaque |
| Camera System | Working | Multiple camera modes, free-fly debug camera, delayed death-camera handoff; chase camera now orbits the aircraft on a level horizontal plane |
| Destruction | Working | Explosion with volumetric smoke puffs (SphereMesh, staggered, rising/fading) |

### Carrier Systems

| System | Status | Notes |
|--------|--------|-------|
| Flight Deck Manager | Partial | Orchestrates deck/hangar/catapult/recovery flow, scramble queues, and runtime aircraft persistence; recent recovery fallback, wheel-settle, and wheel-lookup hardening improved reliability, but moving-carrier recovery edge cases are still under test |
| Air Operations Manager | Working | Autoload (Citadel). Commands four named flights (Archer, Bulldog, Crimson, Dingo); intercept/CAS vectoring; scrambles from hangar when a flight has no members; radio comms throughout |
| Wing Fold (Aircraft 2) | Working | Wings fold in hangar/transport, unfold at catapult; instant-snap on spawn |
| Elevator | Working | Hangar <-> deck transit; aircraft tracks carrier horizontally |
| Tractor Bots | Working | Aircraft towing system; follow carrier as carrier children and now use shared wheel-node lookup instead of brittle hard-coded wheel names |
| Deck Lights | Working | Procedural light placement; center elevator-adjacent strips retuned and recolored yellow |
| Arresting Cables | Working | Multi-cable support |
| Carrier Movement Tracking | Working | All deck objects (parked, transport, catapult) move with carrier each frame |
| Tracks | Working | Nav-grid A* pathfinding; tread height from grid (no per-frame raycasts); wall avoidance raycasts; stuck detection |

### Enemy Systems

| System | Status | Notes |
|--------|--------|-------|
| Detection | Working | Sensor-based target acquisition |
| Weapons | Working | Autocannon with burst fire |
| Ballistics | Working | Lead calculation and gravity |
| Ground Snapping | Working | StaticBody3D terrain alignment |
| Movement | Partial | Aircraft behavior solid; ground vehicles now share NavGraph waypoint path-following with cooldown/backoff logic, but movement/combat stance still being tuned |
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

1. Validate the full end-to-end carrier cycle on a moving carrier, especially arrested landing -> tractor recovery -> elevator/hangar and retrieval -> catapult relaunch.
2. Continue tuning AI landing behavior around the authored approach markers, including speed reduction, descent timing, and final deck alignment.
3. Verify Aircraft 2's launch/recovery loop after the landing-gear mesh/pivot changes so all three wheels settle correctly onto the deck.
4. Continue tuning ground vehicle movement, combat stance, and pathing performance.
5. Expand enemy movement/pathfinding and build out the resource management layer.

**Current focus:** As of 2026-03-17, the main active work is carrier-air-ops polish: recovery reliability, launch handoff, and AI approach/landing tuning on the moving carrier.

## Working Style Notes

- Build iteratively and favor small, well-documented steps.
- Keep temporary structures easy to identify and remove later.
- Maintain the established project structure and move files into the correct folders when the design is clear.

## Additional Documentation

- [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md)
- [Controller Guide](docs/CONTROLLER_GUIDE.md)
