## Current Status

**Last Updated:** 2026-03-06
**Godot Version:** 4.4.1.stable.official.49a5bc7b6
**Project Health:** PLAYABLE
**Control Mode:** Manual (Game Controller) + AI autonomous

### Core Systems
| System | Status | Notes |
|--------|--------|-------|
| Flight Physics | Working | SimpleAero integration complete |
| AI Pilot | Working | Full carrier cycle: hangar → catapult → climb → approach → land → hangar |
| Catapult | Working | Launches AI and player aircraft |
| Arresting Cables | Working | Roll stabilization, mass-adaptive braking |
| Landing Gear | Working | Suspension and damping implemented |
| Tailhook | Working | Auto-deploy/stow functional |

### Aircraft Systems
| System | Status | Notes |
|--------|--------|-------|
| Player Control | Working | Full manual flight control |
| AI Control | Working | Press 1 to spawn AI from hangar; auto land-after-launch |
| Weapons | Working | Autocannon, bombs, missiles |
| Targeting | Working | HUD target box, sensor cone |
| HUD | Working | Radar, instruments, CCIP |
| Camera System | Working | Multiple camera modes |
| Destruction | Working | Explosion and wreckage |

### Carrier Systems
| System | Status | Notes |
|--------|--------|-------|
| Flight Deck Manager | Working | Orchestrates all operations including AI config |
| Elevator | Working | Hangar <-> deck transit |
| Tractor Bots | Working | Aircraft towing system |
| Deck Lights | Working | Procedural light placement |
| Arresting Cables | Working | Multi-cable support |
| Tracks | Partial | Basic movement, needs refinement |

### Enemy Systems
| System | Status | Notes |
|--------|--------|-------|
| Detection | Working | Sensor-based target acquisition |
| Weapons | Working | Autocannon with burst fire |
| Ballistics | Working | Lead calculation and gravity |
| Ground Snapping | Working | StaticBody3D terrain alignment |
| Movement | Partial | Basic positioning, no pathfinding |
| AI Behavior | Partial | Dogfight behavior implemented and actively tuned |

### Environment
| System | Status | Notes |
|--------|--------|-------|
| Terrain | Working | Terrain3D with LOD (desert) |
| Terrain Shader | Working | Slope-based coloring |
| Rock Scatter | Working | Poisson disk distribution |
| Lighting | Working | Directional + deck lights |
| Post-Processing | Working | Filmic, glow, SSAO, fog |
| Weather | Planned | Not yet implemented |

### Immediate Priorities
1. Dogfight tuning pass: improve final nose placement and shot conversion at close range
2. End-to-end AI cycle testing: hangar -> catapult -> climb -> approach -> land -> hangar (loop)
3. Implement enemy movement and pathfinding
4. Add carrier defense turrets
5. Develop resource management system

### Version History
- 2026-03-06: Dogfight controller rework (direct nose-pointing control), inverted recovery, firing logic/rudder tuning
- 2026-03-04 (s2): AI hangar-launch cycle: controls_disabled fix, terrain avoidance post-launch, aggressive climb, proximity waypoint clearing, land-after-launch flow
- 2026-03-04: AI landing tumble fix, bomb accuracy, auto-hangar recovery, post-arrest AI hand-off
- 2026-03-03: Arresting cable physics overhaul (mass-adaptive, quadratic damping)
- 2025-09-26: Flight deck automation
- 2025-09-23: Camera and lighting improvements
- 2025-09-20: Enemy stabilization and HUD overhaul
- 2025-10-05: AI pilot system implementation
- 2025-09-14: Catapult and arresting cables

---

## Project Change Log (latest session)

### Session Summary (2026-03-06) - Dogfight Control Rework

**Overview:** Air-to-air behavior was reworked from mixed navigation heuristics to a direct nose-pointing controller. The AI now picks an aim direction and drives roll/pitch/yaw to put the nose on that aim point.

#### Dogfight Control Architecture (`AI/AIPilot.gd`)
- Replaced the previous layered dogfight steering stack with a direct local-space control loop in `_state_dogfight`.
- Outer loop computes desired bank from local azimuth error (`yaw_err_rad`) to the blended target/lead aim point.
- Inner loops:
  - Roll PD tracks desired bank.
  - Pitch tracks local elevation error (`pitch_err_rad`) with turn-load bias and low-speed limits.
  - Yaw tracks azimuth error with coordinated-turn and yaw-rate/sideslip damping.
- Added straight-flight preference when target is mostly ahead and yaw error is small: bank and pull bias are blended toward level flight.

#### Inverted Recovery Behavior (`AI/AIPilot.gd`)
- Added explicit inverted recovery guard in dogfight (`basis.y.y < -0.05`):
  - Forces upright roll target (`desired_bank = 0`) with stronger roll recovery gains.
  - Neutralizes yaw and uses conservative pitch until upright.
  - Suppresses weapon fire during inverted recovery.
- This prevents "leveling off while inverted"; AI now prioritizes rolling upright first.

#### Rudder and Fire Behavior Tuning (`AI/AIPilot.gd`)
- Increased rudder authority to full scale (`dogfight_max_rudder_input = 1.0`).
- Added/raised simple dogfight yaw gains and smoothing controls for faster nose placement.
- Relaxed fire gating:
  - Lowered minimum aim/hit thresholds.
  - Increased burst duration and shortened cooldown.
  - Added geometric fallback so AI fires when target is clearly in front even if hit model is conservative.

#### Current Result / Remaining Issue
- Dogfight behavior is improved and more coherent than earlier sessions.
- Remaining tuning focus: terminal closure phase. AI can point generally toward target but still needs stronger "last bit" nose authority to convert more opportunities into shots.

### Session Summary (2026-03-04 part 2) - AI Hangar-Launch-Climb-Land Cycle

**Overview:** Pressing **1** now spawns an AI-controlled aircraft from the hangar, which is raised by the elevator, towed to the catapult, launched, climbs to a waypoint, and then automatically begins a carrier landing approach — completing a full hands-off cycle.

#### Spawning AI from Hangar (`LandCarrier/FlightDeckManager.gd`)
- `_configure_retrieved_aircraft_as_ai()`: disables player UI/targeting nodes, keeps camera tripods enabled, sets `controls_disabled` (so AI stays silent until the catapult fires), enables AIToggle, and sets `ai_pilot.land_after_launch = true`.
- Aircraft is added to `friendlies` and `ai_aircraft` groups; removed from `aircraft` group.

#### AIToggle Priority Fix (`Aircraft/AIToggle.gd`)
- `enable_ai()` previously checked altitude first: aircraft on deck (Y > 10 m) wrongly went to `SEARCH` instead of `LAUNCHING`.
- Fixed: `controls_disabled` is checked **first**. Calls `ai_pilot.launch()` (not just `change_state`) so that `launch_position` is correctly recorded at the catapult deck position, enabling the 300 m deck-clearance distance calculation.

#### AIPilot `controls_disabled` Guard (`AI/AIPilot.gd`)
- `_physics_process` returns early (no `_apply_controls` call) when `controls_disabled` is set — prevents the AI from interfering with the catapult, tractor bots, or recovery sequence.
- Previously, calling `_apply_controls(throttle=0)` triggered `engine_stop()`, killing the catapult spool-up.

#### Post-Launch Terrain Avoidance Fix (`AI/AIPilot.gd`)
- `emergency_min_agl_m = 180 m` was firing immediately after catapult launch (aircraft at ~15 m AGL), slamming `pitch_input = 1.0` and causing a violent loop.
- Fixed: `_check_emergency_terrain_avoidance()` returns early for `LAUNCHING` (always) and for `CLIMBING` when climbing (`linear_velocity.y > 2 m/s`).

#### LAUNCHING State (`AI/AIPilot.gd`)
- Applies `pitch_input = 0.05` when `vel.y < 2 m/s` to prevent gravity drag into the ground during the brief deck-clearance phase.
- Transitions to `CLIMBING` once aircraft is 300 m from the recorded launch position.

#### CLIMBING State Overhaul (`AI/AIPilot.gd`)
- **Waypoint:** Fixed 3D point at `carrier_position + launch_forward × 600 m`, altitude = `carrier.y + 200 m`. Computed from stable inputs (carrier position + launch heading) so it is the same point every frame.
- **Exit condition:** `distance_to(nav_waypoint) < 200 m` — aircraft physically clears the waypoint. Previous altitude-only check was broken (waypoint was recalculated 1000 m ahead each frame, so distance was always ~1000 m).
- **Aggressive climb:** forces `pitch_input = 0.5` and `_smoothed_pitch_input = 0.5` directly while more than 50 m below target, bypassing the slow lerp ramp.
- **Pitch authority:** CLIMBING now uses `vs_limit = 25 m/s`, `vs_gain = 0.15` in `_navigate_to_waypoint()` (vs normal 10/0.08).
- **Gear/flap retraction:** runs on the first airborne frame in CLIMBING as before.

#### Land-After-Launch Flow
- `land_after_launch` flag (set by FDM before catapult) → cleared in `_state_launching()` when deck-clear, sets `_land_after_climb = true`.
- When climb waypoint is cleared and `_land_after_climb` is set → calls `start_landing()`.
- This ensures the aircraft goes through a proper climb (gear up, altitude gained) before attempting the approach, rather than diving straight from the deck toward the carrier.

---

### Session Summary (2026-03-04) - AI Carrier Landing & Hangar Recovery

**Overview:** AI aircraft can now complete the full carrier cycle autonomously: fly an approach, catch the arresting wire, stop safely, and be moved to the hangar without any player input.

#### AI Bomb Attack Improvements
- **CCIP tolerance tightened** from 50 m to 30 m for more accurate release.
- **Improving-accuracy hold:** AI waits for peak CCIP accuracy before releasing—holds fire while predicted miss is still decreasing and > 8 m, then releases at the minimum.
- **Systematic undershoot fixed:** `bomb_dive_aim_height_m` changed from 80 m to 0 m so the ballistic arc sweeps through the target rather than stopping short. Terrain clearance margin reduced from 80 m to 25 m. Result: bomb miss distance improved from ~32 m to ~22 m.
- **Multi-bomb drops restored:** 3 bombs per run with 0.2 s spacing (was 1 bomb; 0.5 s spacing was too long for CCIP to remain within tolerance).
- **Attack setup altitude** raised from 500 m to 650 m offset for better flight-path-angle buildup.

#### Bank Angle Judder Fix (`AI/AIPilot.gd`)
- Root cause: `desired_bank` was computed from `lateral_ratio` (local aircraft frame), which oscillates as the aircraft rolls, causing feedback near max bank.
- Fix: switched to world-space `bearing_err_rad` for both normal and precise aim modes. Bank is now `clamp(bearing_err_rad × gain, ±bank_limit)`.

#### Carrier Landing Tumble Fix (`LandCarrier/ArrestingCable.gd`, `LandingGear/LandingGear.gd`)
- **Root cause:** Lateral centering force was applied at the hook position (2.4 m behind, 1.7 m below CG), generating yaw and roll torques. Roll developed at ~200°/s; roll stabilization was capped too low (~20 kN·m).
- **Fixes applied:**
  - Lateral centering force moved to CG (`apply_central_force` instead of `apply_force` at hook offset).
  - `roll_max_torque_g_m` raised 3.0 → 30.0 (cap lifted from ~20 kN·m to ~200 kN·m).
  - Added `deck_hold_force` (15,000 N per wheel) in LandingGear: pulls each wheel toward the deck surface during cable engagement to resist flipping.
- **Result:** Roll holds at 0.0° throughout arrest; all wheels stay on deck; aircraft stops cleanly.

#### AI Post-Landing Recovery (`AI/AIPilot.gd`, `LandCarrier/FlightDeckManager.gd`)
- **Problem:** After the arresting cable auto-released (speed < 2 m/s), AIPilot resumed `_state_landing` and hit the stall-speed guard (`throttle = 1.0`), causing the aircraft to accelerate away.
- **AIPilot changes:**
  - `_physics_process` checks `controls_disabled` meta at entry; if set, zeros all inputs, calls `_apply_controls()`, and returns—preventing the AI from fighting FlightDeckManager.
  - When arrest ends (`_arrest_engaged_prev` → false), transitions to `State.IDLE` and calls `_request_carrier_recovery()` instead of resuming the approach.
  - `_request_carrier_recovery()` finds FlightDeckManager via group and calls `start_post_arrest_recovery(aircraft)`.
- **FlightDeckManager changes:**
  - New `start_post_arrest_recovery(aircraft)`: sets `parking_brake` + `controls_disabled`, stows tailhook, dispatches tractor/elevator recovery job. Skips if already in `RECOVERY_IN_PROGRESS` (signal-based path already running).
- **Result:** Aircraft is automatically moved to elevator and stored in hangar after landing, with no player input required.

---

### Session Summary (2026-03-03) - Arresting Cable Physics Overhaul
*   **Goal:** Tune the arresting cable for a ~30m, non-linear stop and improve physical realism.
*   **Mass-Adaptive Braking:** Replaced fixed-force braking with a mass-adaptive system. The cable now calculates the required force based on the aircraft's mass, ensuring consistent performance for any aircraft (e.g., a 700kg fighter or a 16,000kg bomber).
*   **Quadratic Damping:** Implemented non-linear quadratic damping (`F ∝ v²`). This creates a more realistic feel, with a strong initial pull at high speed that eases off as the aircraft slows, resulting in a gentle roll-out at the end.
*   **Pitching Moment Dynamics:** The braking force is now applied at the tailhook's physical location instead of the aircraft's center of gravity. This introduces a natural nose-down pitching moment, causing the suspension to compress and react dynamically.
*   **Stability Enhancements:**
    *   Added a tunable artificial downforce (`engaged_downforce_g`) that is applied to each wheel individually, keeping the aircraft firmly planted on the deck during high-G deceleration.
    *   Increased the authority of the roll-stabilization torque to counteract the pitching moment and prevent rollovers.
*   **Bug Fixes & Refinements:**
    *   Corrected a physics bug where the spring force could push the aircraft forward.
    *   Fixed a G-force calculation error in the AI pilot's debug telemetry.
    *   Resolved an issue that could cause the aircraft to "rubber-band" backwards after stopping.
    *   Added robust debug logging for gear compression to monitor suspension performance.

---

### Session Summary (2025) - AI Ground Attack & Bombing System

**Overview:** The AI pilot now has a complete ground attack capability. Friendly AI aircraft can patrol, detect ground targets, execute bombing runs, and return to patrol—all autonomously.

**Controls:**
- **P** – Spawn a friendly AI plane (EnemyAircraftSpawner)
- **O** – Toggle all AI planes between patrol and attack mode
- **Y** – Switch camera (bridge ↔ AI plane views when no player)

---

#### AI Ground Attack State Machine

**Attack flow:**
1. **ATTACK_POSITIONING** – Fly to setup waypoint (~800m in front of target, 300–500m above)
2. **ATTACK_INBOUND** – Fly level toward target at setup altitude until dive start range
3. **ATTACK_DIVE** – Dive at target, drop bombs, pull up when done
4. **ATTACK_BREAK_OFF** – Fly away from target, then line up next run

**Configuration (AIPilot.gd):**
- `bomb_run_setup_distance_m`: 1400 m – setup waypoint offset
- `bomb_dive_start_distance_m`: 800 m – start dive at this horizontal range
- `bomb_pull_up_distance_m`: 250 m – minimum distance for break-off
- `bomb_release_altitude_window_m`: 300 m – drop when 5–300 m above target

---

#### Bomb Release Logic

**Simplified release model:**
- Drops when altitude above target is between **5 m and 300 m**
- Drops **3 bombs per run**, then pulls up
- Spacing: 0.11 s between bombs (slightly above weapon fire cooldown)
- Must be descending (flight path angle > 1°)
- No prediction or nose-alignment checks—altitude window only

**Break-off:**
- When 3 bombs have been dropped, or
- When within 120 m of target (safety margin)

---

#### Dive & Aim Behavior

**Aim correction:**
- Uses predicted bomb impact to steer the aim point toward the target
- Correction strength increases as range decreases (0.6–1.2)

**Precise aim mode** (within 500 m horizontal, 400 m altitude):
- Bank limited to 35° for steadier approach
- Aim height reduced to target + 15 m
- Bearing-based bank control instead of lateral ratio
- Faster roll response (reduced smoothing)

**Smooth aim height transition:**
- Aim height lerps from 80 m to 15 m between 600 m and 400 m range
- Avoids abrupt pitch changes

---

#### Pitch & Dive Stability

**Soft dive entry:**
- vs_limit and vs_gain ramp over 1.2 s (18→40 m/s, 0.12→0.25)
- Reduces initial pull-too-hard and oscillation at dive start

**Pitch oscillation fixes:**
- Deadband within 35 m of aim altitude (gentler correction)
- Stronger pitch derivative damping in dive (0.45 vs 0.28)
- Heavier pitch smoothing in dive (0.12 vs 0.2)
- Min-pitch threshold raised to 60 m in dive for earlier ease-off

---

#### Emergency & Safety

**Terrain avoidance:**
- Emergency pull-up if AGL < 180 m or terrain time-to-impact < 3 s
- Terrain sampling along dive path to raise aim point over hills

**Descending spiral recovery:**
- When banked > 25° and descending > 15 m/s, level wings first, then climb

---

#### Camera Behavior

**StandaloneCameraSwitcher (bridge-only / no-player mode):**
- Switches to bridge only when the **destroyed plane** is the one being viewed
- Viewing another plane or the bridge is unchanged when a different plane is destroyed
- Linger time: 4 s on destroyed plane’s camera before switching

---

### Session Summary (2025-02-15 Part 2) - Restored Manual Control

**Changes Made:**
- ✅ Disabled AI pilot by default in `CompleteFighterJet.tscn`
- ✅ Aircraft now starts with player control enabled
- ✅ Press **A** key if you want to toggle AI pilot on (optional)

**Configuration:**
- All controls are gamepad-based (Xbox/PlayStation controller)
- No keyboard flight controls configured (only toggle keys)
- Manual flight control is now the default

---

### Session Summary (2025-02-15) - Critical File Permission Issues

**Issue Overview:**
The project is experiencing widespread file permission errors that prevent Godot Engine from importing and saving resources. This affects:
- 3D model imports (.glb files)
- Texture imports (.png, .jpg, .svg files)
- Audio imports (.wav, .ogg files)
- Font imports (.ttf files)
- MD5 checksum files
- Godot's filesystem cache

**Symptoms:**
- ERROR: `Cannot create file 'res://.godot/imported/...'`
- ERROR: `Cannot save scene to file '...'`
- ERROR: `Cannot open MD5 file '...'`
- ERROR: `Cannot create file 'res://.godot/editor/filesystem_cache10'. Check user write permissions.`
- WARNING: Resources cannot be imported and must be loaded uncompressed
- ERROR: `Failed loading resource: ... Make sure resources have been imported by opening the project in the editor at least once.`

**Root Cause:**
The `.godot` directory (Godot's import cache and editor data folder) does not have proper write permissions, preventing the engine from creating/updating imported asset files.

**Resolution Steps:**

1. **Check Directory Permissions (Windows):**
   - Right-click the project folder → Properties → Security tab
   - Ensure your user account has "Full control" permissions
   - If not, click Edit → Add your user → Grant "Full control"
   - Apply to all subdirectories

2. **Check Directory Permissions (Linux/Mac):**
   ```bash
   # Check current permissions
   ls -la .godot/
   
   # Fix permissions if needed
   chmod -R u+rwX .godot/
   chmod -R u+rwX .
   ```

3. **Delete and Regenerate .godot folder:**
   - Close Godot completely
   - Delete the `.godot` folder entirely (it will be regenerated)
   - Reopen the project in Godot
   - Wait for all assets to reimport (may take several minutes)

4. **Check for Read-Only Attributes (Windows):**
   - Right-click project folder → Properties
   - Uncheck "Read-only" if checked
   - Apply to all files and subfolders

5. **Verify Disk Space:**
   - Ensure you have sufficient free disk space (recommended: >2GB free)
   - The `.godot/imported/` folder can grow quite large with many assets

6. **Check Antivirus/Security Software:**
   - Some antivirus software may block Godot from writing files
   - Add the project folder to antivirus exclusions if necessary
   - Check Windows Defender or other security software settings

7. **Run Godot with Elevated Permissions (Last Resort):**
   - Windows: Right-click Godot executable → "Run as administrator"
   - Linux/Mac: May need to adjust ownership: `sudo chown -R $USER:$USER .`

**Prevention:**
- Always ensure project folders have proper write permissions before opening in Godot
- Avoid placing projects in system-protected directories (Program Files, Windows System folders, etc.)
- Don't sync the `.godot` folder to cloud storage services (Dropbox, OneDrive, etc.) as this can cause conflicts
- Add `.godot/` to `.gitignore` - this folder should never be committed to version control

**Status:** ⚠️ **UNRESOLVED** - Project cannot run until permissions are fixed

---

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
	  AI Pilot System: AI-controlled aircraft use the same inputs as the player (aileron, elevator, rudder, throttle, gear, weapons). Core states: Launch, Climb, Transit, Search (patrol), Attack (ground attack with bombs), Break-off, RTB, Approach, Landing. **Ground attack:** AI detects ground targets (EnemyBox), sets up bombing runs from 1400 m, flies inbound, dives at 800 m, drops 3 bombs when 5–300 m above target, then breaks off. Press **O** to toggle AI between patrol and attack mode.
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

### Session Summary (2025-10-05)
*   **AI Pilot System Implementation**:
	*   Created comprehensive AI pilot system for autonomous aircraft control using same inputs as player
	*   **PIDController.gd**: Reusable PID controller for smooth, human-like control (prevents jerky robot movements)
	*   **AIPilot.gd**: Main AI brain with state machine (IDLE → LAUNCHING → CLIMBING → TRANSIT → SEARCH → ENGAGE → RTB → APPROACH → LANDING)
	*   **AIToggle.gd**: Toggle between AI and player control with 'A' key; disables player control modules when AI active
	*   Modified CompleteFighterJet.tscn to be AI-controlled by default
	*   Fixed SimpleAero integration (aileron_input → roll_input, etc.)
*   **AI Launch & Collision Systems**:
	*   Fixed critical collision bug where aircraft collision layers were set to 0 and never restored
	*   FlightDeckManager now saves/restores collision settings properly (default 513)
	*   Added ai_pilot.launch() command to initiate AI launch sequence
	*   Implemented deck clearance check - AI maintains level flight for 300m after launch before climbing
	*   Added automatic landing gear and tailhook retraction when airborne
*   **AI Sensor & Navigation Systems**:
	*   Implemented controlled information access - AI only "sees" what sensors detect:
		*   `altitude_agl`: Radar altimeter via raycast to terrain
		*   `terrain_ahead_distance`: Forward-looking terrain scan (2000m range)
		*   `known_enemies`/`known_friendlies`: Only contacts within 5000m sensor range
	*   Emergency terrain avoidance: Auto pull-up if AGL < 100m or terrain ahead < 500m
	*   Aircraft automatically added to "friendlies" group for AI detection
*   **Waypoint-Based Flight Control**:
	*   Restructured AI navigation to be waypoint-based instead of direct altitude control (eliminates oscillation)
	*   Navigation flow: "WHERE do I want to go?" → "WHAT heading/pitch/roll?" → "APPLY controls"
	*   Implemented proper coordinated turn physics:
		*   Bank angle selection: 20° (gentle) / 30-45° (standard) / 60° (steep) based on heading error
		*   Pull back elevator to turn - more bank requires more back pressure
		*   Rudder proportional to bank angle for coordination (0.5 × bank ratio)
	*   Organic altitude maintenance: Pitch control responds to both altitude error and vertical speed
	*   AI naturally discovers it needs more pitch in turns to maintain altitude (lift = total lift × cos(bank))
*   **Rectangular Patrol Pattern**:
	*   Implemented 4-waypoint rectangular patrol around carrier (750m × 750m square at 500m altitude)
	*   AI switches waypoints when within 50m, loops continuously
	*   Carrier position saved at launch for patrol reference
	*   Enemy engagement temporarily disabled to focus on stable flight
*   **Flight Parameters & Tuning**:
	*   Set AI flight limits: max pitch ±60°, max roll ±60° (limits on commanded angles, not actual aircraft capability)
	*   Changed initial climb altitude from 1000m to 500m
	*   Tuned PID controllers to prevent looping and oscillation:
		*   Pitch: 0.5 P, 0.3 D (reduced from 2.0)
		*   Altitude: 0.005 P, 0.01 D
		*   Heading: 0.3 P, 0.1 D

