# Land Carrier

This document is the short project brief for Land Carrier. For version history, session summaries, and archived long-form notes, see [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md).

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

**Last Updated:** 2026-05-10
**Godot Version:** 4.4.1.stable.official.49a5bc7b6
**Project Health:** PLAYABLE
**Control Mode:** AI-by-default with viewed-aircraft player/AI toggle (game controller + keyboard parity in pause/menu flows)

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
| Flight Physics | Working | SimpleAero integration complete; aircraft thrust has been bumped across the roster and shared forward drag reduced so dives and acceleration feel less artificially capped; aircraft now also use per-type pitch/roll self-righting plus grounded rudder assist so takeoff, landing, and general hand-flying feel less "nose goes wherever I point it"; engine throttle response now ramps through spool-up/down lag instead of snapping instantly; low-speed sideslip damping increased so the velocity vector tracks the nose more tightly during normal maneuvering |
| AI Pilot | Working | Full carrier cycle exists; path-follower carrier recovery remains the default; landing mode now favors yaw/rudder lineup with only light bank for visual readability, includes smoother pitch/FPA response, and has a 10 m/s scripted-carrier compensation path that is promising but still being tuned; hierarchy-of-needs safety layer (terrain avoidance > collision avoidance > state machine); terrain fan avoidance with directional escape sampling; low-altitude failsafe now avoids the old hard-pull stall trap by considering energy/speed before commanding escape pitch; dogfight proximity override breaks off ground attack when enemies close; close-pass breakaway logic now reduces merge collisions; CCIP ballistic sim throttled via caching; attack releases are closer and bomb drops are staggered; dogfight and contact handling were hardened against freed-instance crashes; contact scans, collision avoidance, and RTB checks are further throttled for CPU cost |
| Catapult | Working | Launches AI and player aircraft |
| Arresting Cables | Working | Roll stabilization and mass-adaptive braking; extension is currently constrained to a short stop distance with smoother deceleration so caught aircraft remain near the landing area instead of stretching wires across the elevator |
| Landing Gear | Working | Suspension/damping implemented; Aircraft 1, 2, and 5 now use animated gear pivots instead of pop-in/out, with stowed visuals/shadows suppressed; nosewheel taxi steering now follows rudder at low speed, and rebound damping/deadband were retuned to reduce "pumping" on rollout |
| Tailhook | Working | Auto-deploy/stow functional |

### Aircraft Systems

| System | Status | Notes |
|--------|--------|-------|
| Player Control | Working | Full manual flight control |
| AI Control | Working | All vehicles default to AI; `Start` toggles only the currently viewed friendly aircraft between player and AI control without forcing camera/target changes; bottom-center `AI` indicator remains when viewing AI-controlled aircraft; shoulder buttons cycle viewed units (including bridge view); Space exits free camera to spectator; `L` assigns the next eligible friendly aircraft to landing; viewed-aircraft HUD/instruments remain active while AI is flying |
| Weapons | Working | Shared gun-profile stack now supports 10/15/20/25 mm gun families across hardpoints and turrets (stats, projectile type, spread, recoil, sound set); bullets inherit muzzle-point velocity and are oriented to actual spawn velocity; runtime hit-assist radius defaults to `0.5 m` and can be adjusted with Up/Down arrow keys; AA missile launchers can still be intentionally fielded empty |
| Targeting | Working | HUD target box, sensor cone, `L3` target lock, and D-pad left/right cycling through available hostile targets; destroyed targets can remain on the cockpit target camera briefly so the player can watch the impact/explosion before auto-switching |
| HUD | Working | Radar, instruments, CCIP, terrain map overlay on radar; cockpit radar scope remains circular and masked correctly; main gunsight uses HUD-glass collimation/boresight projection; FPV symbol shows actual velocity vector with dotted boresight linkage; rotating attitude pitch ladder (horizon-level) with side ticks is now integrated, and boxed speed/altitude readouts were repositioned upward for better readability; the cockpit terrain map now uses the same live terrain bounds/origin convention as the `M` tactical map and was flattened/stabilized to stop the old bulging/distorted surface feel |
| Camera System | Working | Multiple camera modes, free-fly debug camera, delayed death-camera handoff; chase camera now orbits the aircraft on a level horizontal plane; the old bridge cam has been replaced by a first-person commander view inside the carrier bridge; stick-click zoom is available in commander view and in the cockpit camera, including while viewing an AI-controlled aircraft |
| Night Vision / Night Combat | Partial | `I` toggles NV in cockpit view; green phosphor shader with scanlines, grain, vignette, and scan artefacts; instrument panel target feed also switches to NV; high-G overlay drift has been addressed by projecting from interpolated render transforms, but still needs live visual validation; AI pilots, turrets, and ground platoons now take moderate darkness penalties to detection, tracking, and firing |
| Cockpit Audio | Partial | Each aircraft now has its own interior loop plus cockpit-only wind / air-rush layers with crash-aware shutdown, reduced in-cockpit stereo spread, and stronger interior filtering; air-rush/wind gain has been reduced so propeller/interior sound is more audible, but the cockpit/exterior balance is still being tuned |
| Radio Comms | Working | Text radio log plus optional OS TTS; Citadel voice clips can now be added by placing files in `res://Audio` named `Citadel - <line>.wav/.ogg/.mp3`; matching clips play through the radio bus with static, filtering, dropout, and queued playback. Current clips all address Archer but are intentionally reused for every friendly flight for now |
| Destruction | Working | Aircraft now enter a critical-damage death state at `0 HP`: player control is disabled, stick inputs jam to random max directions, and each second rolls explosion chance (`10%` default); final breakup now emits dark rigid debris chunks with smoke trails that self-clean on terrain contact; ParticleManager still manages smoke lifecycle |
| Damage Effects | Working | 3-tier progressive damage system: hydraulic/fuel/flap failures, engine cap/control loss/HUD flicker, engine sputter/structural failure/HUD blackout; escalating smoke trails |
| Aircraft Roster | Working | `Aircraft_4` added as a heavy/slower enemy aircraft with rear turret; `Aircraft_7` and `Aircraft_8` remain fast interceptors; `Aircraft_6` is now a slow, stable, rugged low-speed aircraft with a friendly airborne debug spawn on `6`; weapon assignments were reworked (Aircraft 2: 25 mm, Aircraft 7/8: 20 mm, Aircraft 3: extra hardpoint + dual 10 mm); enemy Aircraft 3 now spawns clean with no external stores and serves as a fighter; pressing `7`/`8` retrieves those variants and `4` debug-spawns a friendly Aircraft_4 above the carrier |

### Carrier Systems

| System | Status | Notes |
|--------|--------|-------|
| Flight Deck Manager | Partial | Orchestrates deck/hangar/catapult/recovery flow, scramble queues, and runtime aircraft persistence; now supports continuous landing-test spawning, named recovery-debug aircraft, last-leg wave-offs when the deck is occupied, bolter/go-around recovery retries, crash-vs-go-around debug classification, and post-arrest tractor/elevator retrieval |
| Air Operations Manager | Working | Autoload (Citadel). Commands four named flights (Archer, Bulldog, Crimson, Dingo); maintains a friendly sensor/contact picture from carrier radar, aircraft, and ground vehicles; launches air-to-air interceptors against reported inbound aircraft and CAS flights against reported ground targets; player-facing tactical-map orders support CAP routes, CAS tasking, and RTB; empty flights auto-scramble from the hangar when ordered; radio comms throughout |
| Wing Fold (Aircraft 2) | Working | Wings fold in hangar/transport, unfold at catapult; instant-snap on spawn |
| Wing Fold (Aircraft 5) | Working | Multi-phase fold: lateral slide, then overlapping X/Y rotations with smoothstep easing; mirrored left-wing geometry handled with flipped X sign |
| Elevator | Working | Hangar <-> deck transit; aircraft tracks carrier horizontally; idle default is down so retrieval can bring tractor bots up from below instead of leaving an empty platform at deck level |
| Tractor Bots | Working | Aircraft towing system; follow carrier as carrier children, ride the elevator for launch/recovery tasks, rotate recovered aircraft forward on the elevator, and use live wheel-node lookup during pickup instead of brittle or stale hard-coded wheel positions |
| Deck Lights | Working | Procedural SpotLight3D placement (downward-facing, no bleed into dust/sky); center elevator-adjacent strips retuned and recolored yellow |
| Arresting Cables | Working | Multi-cable support |
| Carrier Movement Tracking | Working | All deck objects (parked, transport, catapult) move with carrier each frame |
| Vehicle Ramp | Working | Three-panel folding ramp at the carrier rear for ground vehicle deploy/recovery; uses existing GLB meshes; zig-zag fold with simultaneous hinge animation; dynamic terrain-tracking deploy angle; Z key toggles deploy/stow |
| Vehicle Bay Manager | Working | Manages ground vehicle deployment and retrieval via the rear ramp; spawns vehicles on the bay floor, drives them down the ramp at 3s intervals; retrieval rallies all platoon members behind the carrier, deploys ramp when first vehicle arrives, drives them up one at a time; auto-stows ramp after completion; carrier-local positioning during ramp transit so everything works while the carrier moves |
| Ground Ops Manager | Working | Autoload singleton managing four named platoons (Ember, Ferret, Grizzly, Hammer); tries to keep at least two ground vehicles escorting the carrier and four when available; V deploys next empty platoon, B retrieves last deployed, N requests carrier escort; commands: move, attack, protect, escort, pursue, hold, retrieve; tactical map can issue point-based MOVE / ATTACK / PROTECT / ESCORT / HOLD / RETRIEVE orders; empty platoons auto-deploy when given a task and preserve that queued objective through deployment; carrier escort places vehicles at carrier corners with velocity matching; platoons use simple formation slots, pace to the slowest member when out of combat, break formation during combat, and reform afterward; ground staging prefers carrier-reachable terrain with a larger buffer from steep slopes/cliffs |
| Tracks | Working | Nav-grid A* pathfinding with path simplification; full-path computation (no more segmented replanning); steering response/deadzone/settle tuning; height deadband smoothing; tread belt UV rewritten to use baked path-based mapping from imported track mesh; new belt debug modes (path UV, cross UV, direction arrows); terrain-feeler wall avoidance; stuck detection; spawn faces first waypoint |
| Carrier Defensive Turrets | Working | Carrier defense mounts host dual active turrets through the shared controller/weapon stack; firing is now gated by aim tolerance, line-of-sight, fire arc, and effective range; lead debug reporting was expanded and carrier turret `aim_skill` is tuned to `0.8` |
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

1. Live-test the new Citadel/AirOps loop under pressure: reported contacts, carrier radar range, interceptor loadouts, CAS tasking, radio line frequency, and whether the chatter remains helpful instead of noisy.
2. Validate the new interactive `M`-map workflow in live play: asset selection, mission drafting, confirm/cancel flow, and readability under pressure.
3. Expand mission authoring beyond the first slice, especially richer waypoint editing and more flight directives than the current CAP / CAS / RTB set.
4. Continue tuning AI precision control in dogfights so aircraft point more authoritatively at gun solutions, align the pipper with the real gun line, and waste fewer shots while still breaking off unsafe close merges.
5. Continue tuning moving-carrier landings at the current scripted 10 m/s carrier speed; aircraft can now get onto the deck, but arrest/recovery behavior and carrier-relative speed handling still need live validation.
6. Continue tuning ground vehicle movement, steep-slope avoidance, spotting, and pathing performance, especially with multiple active platoons.
7. Keep watching terrain edge cases: floating rocks, cliff-edge altitude checks, terrain streaming gaps, and delayed collision/chunk loading.
8. Continue expanding bridge/commander command features and allow AirOps/GroundOps AI to create and manage missions through the same order model the player uses.

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

### Codex
- In-game encyclopedia accessible from the pause menu
- 3D rotating model viewer per entry with description text below
- Covers vehicles and weapons

**Current focus:** As of 2026-05-10, the active lane is making carrier operations feel alive and trustworthy: Citadel should launch the right aircraft for reported threats, friendly units should only act on contacts they could plausibly know about, and the cockpit/radio feedback should make those decisions understandable. Carrier recovery and ground movement are still important active tuning areas rather than finished systems.

## Working Style Notes

- Build iteratively and favor small, well-documented steps.
- Keep temporary structures easy to identify and remove later.
- Maintain the established project structure and move files into the correct folders when the design is clear.

## Additional Documentation

- [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md)
- [Land Carrier Track Mapping Problem](docs/Land%20Carrier%20Track%20Mapping%20Problem.md)
- [Land Carrier Bridge Jitter Problem](docs/Land%20Carrier%20Bridge%20Jitter%20Problem.md)
- [Controller Guide](docs/CONTROLLER_GUIDE.md)
