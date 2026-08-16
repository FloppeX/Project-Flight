# Land Carrier Changelog

This document contains historical version notes, session-by-session records, and archived long-form material. It is not the source of truth for current status: use the [README](../README.md) for the project description, goals, implemented state, roadmap, and known problems.

This file was created on 2026-03-19 by renaming and reorganizing `Land Carrier Project description.md`. The still-relevant foundational vision from that original document is now maintained in the README; the historical implementation detail remains here.

Status words such as "working" below describe the code at the time of the entry. They should not be read as a current validation result.

## Version History

- 2026-08-14: Large-map and tactical-command consolidation - the navigation/tactical footprint is now `50 km x 50 km`; new games can select Open Canyons or the vertically varied Fractured Badlands profile; persistent fog of war is revealed by friendly observers and blocks player ground/carrier orders into unknown terrain; scenario loading reports staged progress with rotating aircraft-themed nonsense text; the tactical map renders relief plus separate vehicle/carrier mobility; Fractured Badlands provides three protected carrier routes and four cross-connectors; startup placement, deck-passenger carrying, AirOps scramble reservations, rock streaming, and command/personnel UI received focused smoke coverage. Standing CAP no longer auto-scrambles aircraft at scenario start, while detected threats and explicit player orders still can.
- 2026-08-03: Operations, combat, and presentation pass - added shared operations/order infrastructure and a world unit index; expanded ground-combat allocation and scenario tests; improved ground-threat assignment and engagement saturation; introduced performance budgets/LOD paths for aircraft, vehicles, particles, impacts, debris, and wrecks; and continued fixed-wing, helicopter, carrier-recovery, deck, and pilot-roster work.
- 2026-08-01: Carrier-recovery integration update - dirty-entry recovery routing, physically attainable 3D arc tracking, pre-final rollout/stability, handoff ownership, holding, and two-aircraft queue behavior were repaired far enough to produce focused end-to-end catches. Five additional far/very-far entries caught, but the complete dirty matrix, 100-attempt final-controller regression, and 20-run mixed combat/recovery suite were still outstanding.
- 2026-07-16: Air-combat and AirOps pass - dogfight gunnery gained curved lead, energy discipline, anti-stalemate behavior, arc-based awareness, threat/opportunity target scoring, role posture, and sustained fire. AirOps moved from fixed role slots to a dynamic sensor-driven mission board with clustered strike tasks and defense-first scoring. Combat logging, radio-bark hygiene, deck launch queuing, and terrain streaming jump-fill behavior were also improved.
- 2026-06-25: Carrier and cockpit performance pass - carrier tread plates and track marks were reduced/capped, dust and rotor wash became camera-gated, and the modular cockpit instrument panel plus panel interaction received a first playable implementation. Pilot visuals continued converging on the canonical Rigify/GLB asset and flat-shaded project style.
- 2026-06-15: Helicopter combat-aim pass - helicopter gun/rocket runs gained dedicated ingress/fire/egress planning, PID-style aim correction, ballistic prediction, fire gating, and structured telemetry. Centerline aim-reference and gun pitch-authority defects were corrected, producing recorded gun hits while broader routing and survival remained under active development.
- 2026-06-10 to 2026-06-12: Aircraft 11 and helicopter-navigation pass - added the Aircraft 11 helicopter with swing doors and rotor-wash effects; moved helicopter A* path work off the main thread; added turn-speed governing, airborne separation, landing-clearance queuing, radar route display, and carrier-relative deck/terrain fixes.
- 2026-06-07: Helicopter carrier-approach pass - introduced authored hold points and a queued three-phase carrier approach, corrected collective fights during final/descent, improved terrain feelers and waypoint simplification, retuned helicopter speeds, and hardened deck placement and LZ touchdown detection.
- 2026-06-04: Helicopter reliability and diagnostics pass - added a crash flight recorder, scripted carrier approach markers, stronger yaw/bank compensation, terrain-climb and sink guards, an F11 endurance-test mode, tractor-bot retrieval fixes, volume settings, and freed-instance guards around asynchronous deck actions.
- 2026-05-31: Helicopter AI control pass - replaced open-loop control with PD-based velocity, altitude, yaw, and roll loops; added collective rate limiting and an autonomous outbound/LZ/inbound/carrier mission cycle; improved flare, carrier-relative touchdown, and Aircraft 10 tuning.
- 2026-05-29: First dedicated helicopter AI pass - added `HelicopterPilot`, low-level terrain-aware takeoff/transit/hover/landing states, helicopter-specific AI toggle routing, and fixes preventing the moving carrier from transform-carrying active rotorcraft.
- 2026-05-28: Ejection and scout-helicopter pass - added the staged ejection-seat/parachute flow, pilot camera handoff and authoring markers, cockpit visibility rules, Aircraft 10, improved rotor folding/droop visuals, and the authored hardpoint asset.
- 2026-05-20: Helicopter deck operations / pilot roster pass - Aircraft 9 received a more usable heavy arcade helicopter tuning pass with cyclic lag, yaw inertia, simple ground effect, speed-dependent weather-vane help, retractable four-point gear, one-line `HELI_DEBUG` telemetry, and deck takeoff/landing fixes. The carrier remains a scripted/kinematic moving platform; `VelocityFrame` now makes deck-relative velocity explicit so helicopters can inherit carrier speed on takeoff and avoid double-counting carrier motion on touchdown. Rotor fold/unfold state was hardened so the authored two coaxial three-blade rotor sets deploy before spool-up instead of appearing as one overlapped blade per rotor. The carrier pilot roster now tracks pilot identity, skill, experience, mission time, kills, Ace status, rest/wound hooks, temperament, and voice assignment, with the `,` roster overlay showing best pilots first. Voice assets were expanded/imported with Brazilian male, French Canadian female, Nigerian male, and Scottish female sets while the disliked Scottish male set was removed; radio barks now suppress recent exact repeats.
- 2026-05-19: Aircraft 9 rescue helicopter placeholder - moved the new helicopter GLB into `Models/Aircraft_9`, imported it, and added `Aircraft/Aircraft_9.tscn` with common aircraft damage/camera/HUD systems, four fixed landing-gear contact points, and a first arcade helicopter flight model. `HelicopterFlight.gd` maps shared pitch/roll/yaw inputs and engine power into cyclic disc tilt, collective rotor lift, body-hanging alignment torque, yaw authority, drag, translational lift, and simple ground effect; Aircraft 9 is intentionally far heavier than the rest of the aircraft roster and currently tuned toward stable/heavy with responsive cyclic authority and slower rotor-disc lag. The visual rotor now uses the new blade GLB as two counter-rotating three-blade rotors centered on the model's rotor shaft; top blades are flipped along their length for the opposite rotor pitch, and blades start folded aft before unfolding through an engine-start interlock. The old placeholder helicopter prop/sound hookup was removed from the scene. Key `9` now retrieves Aircraft 9 from the hangar; helicopter retrieval skips the catapult and parks at a forward deck takeoff spot halfway between the elevator and bow. Helicopters are currently forced to remain human-controlled, so AI cannot spool them up or take off on its own; the old deck-state reset shortcut moved to `F9`.
- 2026-05-17: Radio / voice / AirOps integration pass - `RadioComms` now supports sticky per-callsign pilot voice assignment across Ukrainian, British male, Filipino, Arabic female, German female, and Scottish male sets; Citadel has converted/imported flight-specific line sets for Archer, Bulldog, Crimson, and Dingo; radio playback uses heavier long-distance telephone-style filtering, static, distortion, stale queue expiry, and one-shot order acknowledgements to reduce chatter spam. Source performances are still being regenerated/tuned, so the pipeline is stronger than the final voice direction.
- 2026-05-17: AirOps and attack behavior follow-through - Citadel orders were tightened so interceptor/CAS announcements correspond more closely to actual flight assignments, empty flights can be scrambled into role, and duplicate confirmations are suppressed; AI gun/rocket ground-attack runs are less likely to be aborted by low-altitude avoidance before firing, while the low-altitude failsafe avoids the old hard-pull stall trap by considering speed/energy.
- 2026-05-17: Aircraft 4 turret and Aircraft 5 gear pass - Aircraft 4's turret was nerfed and constrained so it cannot fire downward through the aircraft plane; the new Aircraft 5 gear rig was split into reusable nose/left/right gear scenes with linkage, lower-leg compression, wheel/axle steering, and multi-stage retract animation.
- 2026-05-10: Night vision overlay lock pass - cockpit NV now projects the HUDglass polygon from interpolated camera/HUDglass render transforms instead of raw physics transforms, addressing the high-G drift expected when physics interpolation is enabled; the cockpit `nv_active` stabilizer is now applied only while the player's own cockpit camera is the active viewport camera, avoiding stale NV state when cycling away from the player cockpit. Needs a live high-G visual pass before calling the drift fix fully proven.
- 2026-05-10: Night vision target-feed sync - `I` toggles are now accepted only by the currently active cockpit overlay, preventing duplicate overlay instances from flipping state independently; the overlay now resolves the instrument panel from its own aircraft instead of the first global `instrument_panel`, and the target display stores the requested NV state so late material creation still inherits the toggle.
- 2026-05-10: Night combat penalty pass - `DayNightCycle` now publishes an AI darkness factor from sun/ambient/sky energy. `AIPilot` applies darkness-scaled reductions to sensor range, contact refresh cadence, effective dogfight range, gun/rocket firing gates, and stale long-time-of-flight shot tolerance; `TurretController` applies darkness-scaled detection range, search cadence, aim-solution cadence, LOS cadence, noise cadence, and effective aim-skill penalties; `GroundVehiclePlatoon` shortens hostile search/pursuit range at night.
- 2026-05-08: Night vision pass — cockpit NV overlay (`I` key) implemented as a `CanvasLayer`/`Polygon2D` projected onto the HUDglass mesh; shader applies luminance gain, gamma, scanlines, per-frame fine grain, smooth value-noise coarse grain (no rectangular artefacts), vignette, and occasional horizontal scan artefacts; NV is cockpit-mode-only and hidden in all other views; instrument panel target-camera feed also switches to a matching green NV look via extended shader uniforms; `CockpitCamera` gained an `nv_active` flag that smoothly zeroes the g-force position offset while NV is on; overlay drift relative to the HUD glass during high-G manoeuvres was left as an open issue and later addressed in the 2026-05-10 pass.
- 2026-05-03: Mission-return recovery framework - AI aircraft returning to the carrier now enter a carrier-relative marshal/hold/approach sequence before the existing straight-in landing controller; returning aircraft request landing clearance from `FlightDeckManager`, hold behind the carrier if the deck is busy, and fly tunable descent gates intended for later steep-approach testing in canyon terrain; the deck manager now reserves the landing deck for one cleared aircraft and releases that reservation on catch, missed approach, crash/destruction, recovery start, or reset; `F3` commands the closest eligible airborne AI aircraft to return, wire overshoots now enter missed-approach navigation instead of continuing in final landing mode, and default recovery gate spacing now starts at 2000 m behind the carrier with final handoff around 1000 m.
- 2026-05-02: Carrier recovery / tractorbot / moving-landing pass - landing-test aircraft now spawn continuously with ordered names and clearer outcome types; landing debug distinguishes catches, bolters, wave-offs/go-arounds, and crashes; AI landing control was retuned toward yaw-dominant lineup with light visual bank and smoother pitch/FPA response; `F2` spawns a recovery-debug aircraft behind the carrier on the landing path; moving-carrier landings now compensate for the carrier's scripted 10 m/s motion, though this remains an active tuning target; arresting cable extension was shortened and stop distance smoothed to keep aircraft near the landing area; the elevator now defaults down when idle; tractor bots ride the elevator for launch/recovery, retrieve landed aircraft, rotate them forward on the platform, descend with the aircraft, and use live wheel positions during pickup; cockpit air-rush/wind was reduced relative to propeller/interior sound.
- 2026-04-29: Landing scoring and debug instrumentation pass — `_landing_snap()` expanded with heading/pitch/score fields; distance-triggered snaps at 400 m / 200 m / 100 m per approach; wire scoring (Wire 2 = 10 pt base, Wire 1/3 = 5 pt base, lateral factor); `get_wire_number()` and `get_engage_lateral_m()` added to `ArrestingCable`; rolling average tracked in `FlightDeckManager`; FPA descent cap raised from 10° to 25° and pitch input limits raised to 0.65; minimum glideslope enforcement (glideslope carrot and FPA floor) attempted and reverted — still open.
- 2026-04-23: AI attack / wind-farm / aircraft roster pass - ground-attack debug telemetry was rebuilt around state-change, weapon-release, 1 Hz attack-run, and sparse background logs; strike release ranges were tightened and bomb drops staggered so aircraft attack closer and retain stores for later passes; multiple freed-instance crash paths around AIPilot targeting/UI cleanup were hardened; AI contact, collision-avoidance, RTB, and release-solution work was throttled/cached for better performance; cockpit radar terrain view was zoomed in and synchronized to the same terrain bounds/origin logic as the `M` tactical map; enemy Aircraft_3 now spawns storeless as a clean fighter and patrol density increased via smaller patrol flights; enemy wind-turbine sites were added with grouped startup placement, distance markerization/activation, team-main-color tinting, guard gun emplacements, spinning/exploded rotor behavior, and debug placement; Aircraft_6 was added as a new slow, stable, rugged aircraft type with airborne debug spawn on key `6`.
- 2026-04-13: Combat/UI/content expansion pass - project renamed to `Land Carrier`; pause menu rebuilt with Orbitron all-caps styling and untinted overlay; rotating HUD pitch ladder and boxed speed/altitude readouts added; gun-profile weapon framework expanded to 10/15/20/25 mm across hardpoints and turrets; hit-assist radius defaults to `0.5 m` and is runtime-adjustable; carrier and emplacement turret aim/range/LOS/arc behavior hardened with expanded debug telemetry; Aircraft_4 integrated as a heavy rear-turret enemy aircraft (`140 HP`) with debug spawn support; Aircraft_2/7/8/3 loadouts updated; cockpit pilot system standardized with randomized pilot palettes and cockpit hiding; team livery/insignia randomization expanded (24-color cycle, tail/wing projection fixes); critical-damage aircraft death state replaced with jammed controls plus chunk breakup/smoke; gun emplacements added with random weapons, activation-distance sleeping, team colors, and collider-bottom terrain grounding.
- 2026-04-06: Performance profiling & fog system overhaul — frame spike logger added to ScenarioManager; identified terrain chunk collision rebuild (0.12s timer) and volumetric fog as primary performance culprits; `stream_update_interval_s` raised to 0.5s, initial-fill chunk budget raised to 16 to eliminate pop-in delay while keeping steady-state at 2 builds/tick; switched to volumetric fog for seamless horizon blending; render scale set to 0.5 for 4K performance; fixed `shake_frequency` missing declaration in `aircraft.gd`; shadow cascade splits retuned (`split_1=0.03`, `split_2=0.15`) for better near-geometry resolution; complete day/night palette overhaul — dawn (apricot/dusty salmon), day (bleached ochre glare), dusk (copper/cinnabar/burnt orange), twilight (plum/brown-violet) with per-phase density and anisotropy; `fog_aerial_perspective=1.0` and uniform sky colour prevent horizon seam in all camera orientations.
- 2026-04-05 (late): Fog/horizon tuning pass — investigated persistent horizon line; identified root causes as missing `fog_aerial_perspective` in active code path and sky gradient visible during bank; zeroed `zenith_darkness` and `sky_ground_darkening` on all phases; `sky_curve`/`ground_curve` widened to 0.45; `fog_depth_begin` and `fog_depth_curve` now explicitly set in the builtin-fog branch to override stale resource values.
- 2026-04-05: Floating origin system audit & completion — added missing `apply_origin_shift` handlers to 8 scripts (NavGraph, vehicle_enemy_light, vehicle_friendly_light, WorldMapSymbolLayer, RadarCanvas, BridgeHologram, CameraController, DustEffect); fixed AIPilot parse error from bad indentation in `_scan_contacts`; fixed `is` operator crash on freed instances in AIPilot sensor scans by reordering `is_instance_valid` check first; terrain chunk `load_radius_chunks` increased from 4 to 10 so terrain fills the camera view distance; DayNightCycle now forces sky/ground horizon colors to match fog color every frame; day phase fog/sky colors adjusted for desert haze look; fog/sky horizon tuning still in progress.
- 2026-04-03: HUD / Flight model / Ground ops polish - added flight path vector (FPV) symbol to HUD showing actual velocity direction with dotted line from boresight crosshair, visible even when FPV is off-screen; increased low-speed sideslip damping from 0.06 to 0.3 so aircraft velocity vector tracks nose more tightly during normal maneuvering; fixed ground vehicle platoons to default to carrier escort immediately upon deployment instead of parking at static rally point; fixed aircraft landing/recovery by searching multiple groups (aircraft, ai_aircraft, friendlies) instead of just aircraft group (critical for recovering AI-launched aircraft); added Aircraft_8 as deployable variant matching Aircraft_7 framework.
- 2026-04-02: Flight-feel / terrain-polish / control-handoff pass - added cliff-only planform straightening + washboard suppression + low-frequency contour jitter to reduce organic-looking billowing cliff faces, tightened rock scatter grounding/slope rejection, added `Aircraft_7` as a faster less-stable interceptor retrievable with `7`, added engine throttle spool lag plus another flight-feel/stability tuning pass, and cleaned up Start/Select/stick-click controller behavior so viewed-aircraft AI/player toggling, commander/cockpit zoom, pause, and AI-viewed HUD/cockpit presentation work more reliably.
- 2026-03-31: Enemy-runway usability / ground-handling / cockpit-audio polish - fixed the circular cockpit radar presentation, made runway striping stable from different view angles, added an adjacent taxiway slab to the enemy runway, improved taxi/takeoff/landing handling with nosewheel steering + grounded rudder/stability tuning, and added a much more structured cockpit-audio pass with per-aircraft engine/interior sounds, cockpit-only airflow layers, crash-aware shutdown, reduced in-cockpit stereo spread, and stronger interior filtering.
- 2026-03-29: Enemy base prototype / enemy runway pass - the old enemy airfield concept was renamed to an enemy runway and folded into a new `EnemyBase` object; the map now starts with one random enemy base containing a runway, `5-6` barracks aligned to the runway grid, and a dark leveled base pad; the base already exposes hooks for future enemy flight/platoon spawning and mission generation.
- 2026-03-28: Interactive tactical command grid prototype - the `M` map now supports selecting flights/platoons, mission buttons, map-click targeting, CAP route drafting, draft preview, and confirm/cancel flow; player-issued orders can auto-scramble empty flights or auto-deploy empty platoons without losing the queued task.
- 2026-03-27: Tactical map / air-ground polish - enemy platoon contacts stay visible on the flat map, render hot pink, use nav-safe contact routing, and show counters/routes; terrain streaming now follows the active camera; `Insert` screenshots save to the project-root `screenshots` folder; F/R/E debug spawns were fixed; aircraft, weapons, audio, and turbulence received another tuning pass; adaptive terrain triangulation removed the repeating cliff washboard artifact.
- 2026-03-26 (late): Ground navigation/tactical display follow-up — ground platoon and vehicle staging now prefers carrier-reachable terrain with larger margins from steep slopes/cliffs; nav/tactical-map bake expanded to `25 x 25 km`; added the full-screen `M` map with a fixed vector-style terrain display and live symbols; startup/loading splash updated to use `splash image 5`; battle-bus heavy guns were softened against aircraft; enemy platoons now stay abstract on tactical displays until individual vehicles are actually revealable.
- 2026-03-26: Ground warfare/tactical map pass — enemy ground roster now uses buggy, pickup, and battle bus variants; added vehicle LMG and heavy-gun turrets plus small explosive heavy rounds; enemy wave spawning now picks flat ground more carefully; platoons travel in simple formations, pace to their slowest member, break/reform around combat, and enemy vehicle shooting is intentionally inaccurate but permissive; bridge holomap ground markers changed to cubes, enemy platoons appear as medium red cubes only when friendly units have terrain line-of-sight; suspension/dust/turret update-frequency optimizations and pooled dust work reduced ground-combat CPU cost.
- 2026-03-24: Aircraft_5 wing fold animation (multi-phase slide/rotate with mirrored geometry handling) and left gear retraction fix; deck lights converted from OmniLight3D to SpotLight3D to prevent bleed into dust/sky; dust effect switched to additive blending; building barracks scale fix (20x→1x); ground vehicle carrier avoidance reworked to elliptical zones with tangential flow steering; escort corner order changed to front-first; enemy barracks base spawning added.
- 2026-03-23: Ground vehicle suspension overhaul — 4-corner probe spring-damper system with separate pitch/roll Euler springs; chassis floats ~1m above ground with all wheels in contact; works on terrain and carrier ramp; forward-axis velocity projection eliminates lateral sliding; asymmetric accel/decel; larger turn radii; carrier edge avoidance (10m buffer); escort formation uses actual carrier dimensions; ramp bay floor extended 3m to close gap at deck transition. Bullet first-frame flash fixed (set transform before add_child). Large procedural rock structures with colliders removed (visual scatter rocks kept). Shadow quality improved (soft filter quality 0→2, atlas 4K→8K, cascade split blending enabled). Aircraft_3 added as new aircraft type; enemy aircraft now use Aircraft_3 scene.
- 2026-03-20: Bridge hologram pass â€” added the bridge holomap as a 2 m tactical table, then iterated it into a wireframe-only deep-greenâ†’neon-green terrain display with faction-colored air/ground markers, raised carrier/ground markers, lower-frequency/camera-gated refresh, and yaw-only carrier-frame projection to reduce stutter/flicker; HUD main reticle collimation fixed to use the physical HUD glass plane and aircraft boresight; dogfight gun aiming/fire logic tightened substantially (stronger terminal authority, stricter fire gates, burst cancellation, muzzle-point velocity solve/inheritance); autocannon ammo increased to 1000, AA missile launchers can start at 0 ammo, and carrier defense turret mounts now support two independently functioning turrets per set.
- 2026-03-17: README/docs refresh; radio test call on `V` moved to `Audio/` and routed through filtered/static radio comms; carrier now spawns facing its first active waypoint; elevator-adjacent deck lights retuned/repositioned; nearest friendly can be ordered to land with `L`; AI landing approach reworked around authored approach marker heights plus carrier-relative altitude reference (`deck = 40 m`); landing gear now animates through pivot nodes with configurable stowed rotations and hidden/shadowless stowed visuals; Aircraft 2 gear scene wiring repaired after mesh changes; flight-deck recovery/launch flow hardened with cable-release fallback, wheel-based deck settling, and tractor-bot wheel lookup fixes; chase camera now uses a level orbit around the aircraft.
- 2026-03-15 (s2): Ground vehicles now use shared NavGraph waypoint pathing with replan cooldown/backoff to prevent once-per-second hitches; turret/targeting debug spam disabled by default; carrier steering/stuck diagnostics improved; Aircraft 2 wing-fold hinge canted upward and mirrored correctly; HUD symbology made fully opaque; cockpit-view canopy/interior shadow suppression added to Aircraft 1/2 to reduce flicker; hangar storage now preserves aircraft type, damage, fuel, and loadout state; startup crash from early `find_hardpoints()` call hardened; arrested-landing recovery remains under active investigation.
- 2026-03-15: AI launch/climb/patrol fixes; wing fold integration; Air Operations Manager (Citadel) with four named flights, intercept/CAS vectoring, hangar scramble, and radio comms; AIPilot CLIMBINGâ†’SEARCH altitude-based transition; mass-scaled catapult launch power; carrier-relative wheel friction; spacebar exits free camera to spectator.
- 2026-03-14 (s2): Battlefield systems pass - added platoon-style ground vehicle grouping/objectives plus F/E/R/G spawn hotkeys; added free-fly camera on Space and frozen death-camera linger before spectate handoff; aircraft radar now draws a heading-up low-res terrain map with sharper cliff emphasis and circular mask; HUD green/line weight improved; aircraft keep scene-authored weapon loadouts while auto-adding AAM targeting support when needed; carrier waypoint/pathfinding startup disabled by default to reduce load wait; autocannon speed raised to 1200 m/s with proper velocity inheritance; terrain flats gained subtle relief and cliffs were made taller; bullets now leave larger ground marks/rock chips and attach hit marks to aircraft/vehicles; ground vehicle/turret behavior received major ongoing tuning, but ground combat movement/stance remains an active tuning area.
- 2026-03-14: AI/player-control overhaul - all aircraft default to AI; controller Start now toggles spectator/pilot mode with nearest-friendly takeover and AI handback; spectator LB/RB cycles carrier + friendlies; AI loop unified around launch -> patrol carrier -> engage -> RTB -> land; dogfight lost-sight variation added; ballistic gun lead/drop aiming improved; AA missiles inherit aircraft speed, use mixed AI missile/gun logic, avoid ripple-firing, have improved guidance/proximity handling, and now use tunable spiral guidance for style + imperfect accuracy; aircraft wing box colliders added; landing gear / target-sync freed-instance crashes hardened.
- 2026-03-13 (s2): Terrain cell_size_m reduced 18â†’12 for more detail; height quantization (quant_step_m=6m, relaxation disabled) for grid-aligned 0Â°/26.6Â°/45Â° slopes; per-face independent color tint (removed spatial gradient bleed); sharp sandâ†’grey cliff border (steep_slope_band export); carrier path-retry disabled (stuttering fix); splash/loading screen added (LoadingScreen.gd autoload, 5s minimum display, fade-out); LoadingScreen registers with TerrainNavGrid.bake_complete.
- 2026-03-13: Carrier nav-grid pathfinding overhaul â€” A* search window expanded to full destination; `_cell_clear` separated into impassable-clearance + slope-only checks; `max_smooth_segment_m` limits LOS smoothing; spawn/destination restricted to lowest height level; debug heightmap image export with full-route A* preview; shadow acne fix (normal bias, soft shadows, tighter cascade).
- 2026-03-10: Modular Turret System overhaul â€” unified component-based `Turret` and `TurretController` systems; replaced hitscan with physical bullets; smooth pitch/yaw aiming; integrated with ground vehicles and carrier defenses.
- 2026-03-09: Moving carrier tracking overhaul â€” all deck objects (parked, elevator, catapult) now follow carrier each frame; carrier-local lerping for horizontal moves; PinJoint3D wheel latches moved with carrier to prevent world-space anchoring during catapult spool; debug message cleanup across Catapult, FlightDeckManager, Elevator, TractorBot
- 2026-03-08: Terrain strata spatial variation, rock scatter fix (world-Y offset + atomic MultiMesh swap), slope/mesa color tuning, spatial gradient color patches, bullet speed 900 m/s, hard shadow edges + 4-split cascades, volumetric explosion smoke (SphereMesh puffs), explosion position fix (call_deferred)
- 2026-03-07: Custom low-poly terrain rollout (streaming chunks, mesas/gullies, palette pass, base height offset), carrier flat-ground placement near map center, key-1 retrieval/player flow hardening
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

### Session Summary (2026-05-20) - Helicopter Deck Operations and Pilot Roster

**Overview:** This session moved Aircraft 9 from "model integrated" toward a testable playable helicopter. The flight model is still deliberately arcade and still needs visual attitude tuning, but takeoff from the carrier, carrier-speed handoff, and carrier landing now work in live testing without the previous bow shove.

#### Aircraft 9 Helicopter
- Added a heavier-feeling helicopter control pass: cyclic lag, yaw inertia, speed-sensitive yaw/weather-vane behavior, simple ground effect, and reduced auto-power assumptions so the player can spool up and lift off deliberately.
- Added one-line `HELI_DEBUG` output for filtering logs while tuning speed, deck-relative speed, climb, body pitch/roll, disc tilt, yaw input/rate, collective, ground effect, and max speed.
- Added retractable four-point visual landing gear controlled through the normal gear path.
- The helicopter still tends to require more nose-down attitude than desired in forward flight; this is a tuning issue rather than considered finished behavior.

#### Carrier-Relative Deck Motion
- Kept the carrier as a scripted/kinematic moving platform rather than converting it to a `RigidBody3D`.
- Added/used explicit carrier deck reference velocity so a helicopter staged on deck can inherit the carrier's velocity on takeoff.
- Fixed the parked/frozen deck-ready state so debug and release logic do not treat a stationary-on-deck helicopter as sliding backward at carrier speed.
- Fixed touchdown behavior by preventing helicopters from being transform-carried by the carrier while also moving under physics with carrier-relative wheel contact. Parked/staged helicopters are still carried; live landing gear contact relies on physics plus `VelocityFrame`.
- Result from live testing: takeoff is better but still not perfectly smooth; carrier landing now works without the helicopter being pushed off the front.

#### Rotor Visuals
- Confirmed Aircraft 9 has three blade instances per rotor and hardened the fold/unfold state so the unfold request persists through engine-start interlock.
- This addresses the symptom where each rotor could appear to have only one blade because the three folded blades were overlapped and not reliably deploying before spool-up.
- The rotor system continues to ignore deprecated old helicopter assets and uses the authored coaxial blade setup.

#### Pilot Roster and Voice Work
- Added a carrier pilot roster model with pilot identity fields: name, gender, national origin, language/voice set, temperament, skill level, experience, mission time, air kills, ground kills, Ace status, and rest/wound hooks.
- Pilots are assigned from the carrier roster to available aircraft/flights rather than permanently belonging to specific aircraft.
- Added a roster overlay bound to `,`, sorted with stronger pilots toward the top.
- Kill credit now tracks contributors so pilot stats can credit kills more fairly than pure last-hit behavior, including support for shared/assisted credit and damaged-enemy crash follow-through.
- Added/imported newer pilot voice sets including Brazilian male, French Canadian female, Nigerian male, and Scottish female; removed the Scottish male set.
- Added recent-bark repeat suppression so the same line is not replayed within a few seconds.

#### Validation / Caveats
- `Aircraft_9.tscn` loads headless with `GODOT_EXIT:0`; existing canopy/livery warnings remain.
- Helicopter carrier landing was live-tested successfully after the carrier-relative velocity fix.
- The helicopter is now playable enough for iteration, but flight attitude, forward-speed drag/trim, landing smoothness, and any future AI helicopter behavior remain open tuning areas.

### Session Summary (2026-05-17) - Radio Voices, AirOps Follow-Through, and Gear/Turret Polish

**Overview:** This session focused on making the carrier command loop more believable: Citadel should issue orders that map to actual flight behavior, pilots should respond without endlessly repeating themselves, and radio voice playback should feel like one coherent comms system even while the generated source clips are still uneven. Several supporting gameplay fixes also landed around ground-attack commitment, Aircraft 4 turret balance, and the new Aircraft 5 landing gear rig.

#### AirOps / Flight Orders
- Citadel order chatter was tightened so flights do not repeatedly acknowledge the same attack/intercept/CAP assignment.
- AirOps now tracks order acknowledgement keys and clears them when a role/task is cleared, reducing stale repeated "attack target" confirmation loops.
- The current design remains sensor-picture driven: Citadel acts on carrier radar and friendly aircraft/ground vehicle reports rather than omniscient world state.
- Enemy aircraft reports can trigger air-to-air interceptor scrambles, while reported ground vehicles/structures can trigger CAS/ground-attack tasking.
- This still needs pressure testing: flights should not just acknowledge orders, they should visibly switch to and prosecute the assigned task.

#### AI Attack / Safety Behavior
- Ground-attack behavior was adjusted so aircraft are less likely to pull away from turret/ground targets before they can fire rockets or guns.
- Low-altitude failsafe behavior was softened from the old "pull full back and stall" pattern; it now considers speed/energy before demanding aggressive escape pitch.
- Gun attacks now follow the same committed-attack idea as rocket attacks, avoiding some premature crash-avoidance cancellations during the attack window.
- This is improved in testing, but should still be watched around cliffs, turrets, and very low attack runs.

#### Radio Voice System
- Pilot voice playback now groups clips by voice prefix and assigns a sticky voice set to each callsign, so a given pilot does not randomly change actor/accent between barks.
- Current pilot voice prefixes are Ukrainian, British male, Filipino, Arabic female, German female, and Scottish male.
- The Scottish and regenerated German sets were converted from numbered MP3 source folders into normalized PCM WAVs with the canonical pilot bark filenames, then imported through Godot.
- Citadel line folders for Archer, Bulldog, Crimson, and Dingo were converted/imported so flight-specific orders can be played as full lines rather than stitched fragments.
- Radio queue entries now expire after a short age limit, so delayed clips that no longer match the situation are dropped instead of playing late.
- The radio bus was pushed toward a heavier long-distance telephone/radio sound: narrower bandpass, stronger filtering/resonance, more static bed, and more clipping/distortion.
- Voice performance quality is still a content risk. The technical pipeline is in place, but some generated voices still need stronger direction and better acting choices before they fully sell the fiction.

#### Aircraft 4 Turret Balance
- Aircraft 4's turret was constrained so it cannot fire down through the aircraft's own plane.
- Its effectiveness was reduced separately from ground turrets, so it should no longer feel like a flying ground-emplacement turret.

#### Aircraft 5 Landing Gear Rig
- The new landing gear model was split into reusable gear scenes and wired into Aircraft 5.
- Nose gear steering now pivots below the rotation linkage so only the lower assembly/wheel turns on the ground.
- Gear retract animation now uses staged mechanical motion: linkage rotation, lower-leg compression into the upper leg, then main assembly fold.
- Left/right gear received mirrored/centerline/forward-folding animation passes, with the final current setup using linkage rotation plus lower-leg compression before the upper leg rotates forward.

#### Validation / Caveats
- Godot import successfully processed newly converted audio assets after re-exporting them as PCM WAV where needed.
- `--check-only` runs continue to load scripts and then hit the known headless dummy-renderer/material crash on exit; no new radio script parse errors were observed before that crash.
- The radio voice set is technically wired, but source performances remain subjective and should be judged in actual combat context.

### Session Summary (2026-05-03) - Mission Return Recovery Framework

**Overview:** Added the first framework pass for aircraft that have completed a mission and need to recover aboard the carrier. This does not claim the final descent geometry is solved; the point is to give us a controllable structure where marshal altitude, step-down gates, and final handoff distance can be tuned safely.

#### AI Mission Return
- `return_to_base()` now enters `start_recovery()` first, falling back to the old RTB/final-landing path only if the recovery framework cannot initialize.
- New AI states were added: `RECOVERY_MARSHAL`, `RECOVERY_HOLD`, and `RECOVERY_APPROACH`.
- Recovery gates are carrier-relative, so they follow the moving carrier rather than relying on fixed world positions.
- The default framework uses a high marshal point behind the carrier, a hold offset to the side, and three tunable descent gates before handing off to the existing straight-in landing controller.
- `F3` now commands the closest eligible airborne AI aircraft to return through this recovery framework.
- Aircraft that overshoot the wires now leave final landing immediately and enter missed-approach navigation, rather than continuing to follow the final landing carrot.
- The default gate spacing was moved aft: marshal at 2000 m, mid at 1600 m, low at 1300 m, and final landing handoff at 1000 m behind the carrier.

#### Deck Clearance
- `FlightDeckManager` now has a simple landing-clearance reservation: one aircraft can hold the deck while approaching, and other aircraft are denied until the reservation is released.
- Reservations release on catch, missed approach / wave-off, crash/destruction, post-arrest recovery start, and reset/abort paths.

### Session Summary (2026-05-02) - Carrier Recovery, Tractorbots, and Moving Landings

**Overview:** This session focused on turning carrier recovery from a debug-friendly landing test into a more complete deck cycle. The strongest improvements are in landing telemetry, tractorbot/elevator behavior, and the recovery path for aircraft that have just landed. Moving-carrier landings now have an initial 10 m/s compensation path and can get aircraft onto the deck, but they are still under active tuning and should not be considered fully solved yet.

#### Landing Test / Debug Flow
- Landing mode now spawns test aircraft continuously at fixed intervals rather than waiting for the previous aircraft to despawn before starting the next timer.
- Test aircraft are named in spawn order (`LandingTest_001`, `LandingTest_002`, etc.) so long debug logs are traceable.
- Recovery debug spawns are separate (`RecoveryDebug_###`): `F2` creates an aircraft roughly 1000 m behind the carrier at about 100 m altitude in landing mode for repeatable landing/retrieval testing.
- Landing outcome logs now include a `type=` field so catches, bolters, wave-offs/go-arounds, and crashes can be separated. This matters because a go-around is acceptable behavior, while a crash is a serious failure.

#### AI Landing Behavior
- Landing lineup was retuned toward rudder/yaw correction, with only light banking for readability.
- Pitch/FPA control was damped to reduce the oscillation seen in the 400 m / 200 m / 100 m landing traces.
- Aim point and wire scoring were tuned after many catches clustered on Wire 3; the current baseline favors Wire 2 more often, though landing scores still vary with lateral error and touchdown distance.
- Moving-carrier landings now account for the carrier's scripted 10 m/s motion even though the carrier itself is not a physics body with a real velocity. This is working enough for deck contact, but carrier-relative speed and arrest behavior remain live-test risks.

#### Arresting Cable / Rollout
- Arresting wire extension was reduced so caught aircraft do not stretch the cables far enough to end up over the elevator.
- Stop behavior was changed from an abrupt clamp to a smoother deceleration over roughly 16 m, which looks less jarring while keeping aircraft close to the landing area.
- Cable disconnect / rollout behavior was tightened so aircraft do not keep rolling gradually after the cable releases.

#### Tractorbot / Elevator Recovery
- The elevator now defaults to the down position when idle instead of rising empty and resting at deck level.
- Tractor bots ride up with the elevator when an aircraft needs retrieval, move to the landed aircraft, tow it back to the elevator, rotate it to face forward on the platform, descend with the aircraft, and stay below.
- Bots were adjusted to stay on the elevator/deck floor rather than floating high above it, and carrier/elevator-relative placement was tightened to reduce flicker during vertical travel.
- Tractor pickup now uses live wheel positions during the approach and final drive-to-gear phase. Cached pickup targets are only a planning seed and are refreshed when the aircraft/wheels have moved, which is important because recently landed aircraft may still be settling.
- Tractor positioning timeouts were relaxed so bots get more time to reach their assigned live wheel before recovery falls back or snaps.

#### Cockpit Audio
- Cockpit air-rush and wind layers were reduced so the propeller/interior engine sound is audible again.
- There are still multiple wind sources, including air-rush and outside-wind-dependent wind, so cockpit balance should be revisited after more flight testing.

#### Remaining Risks
- Moving-carrier landing is improved but not proven; the carrier's scripted motion means aircraft, cables, and recovery code must agree on an artificial carrier-relative velocity.
- Tractor bots now look for live wheel positions, but this still needs in-game validation across off-center landings, aircraft settling, and deck/elevator motion.
- The current arrest stop distance is deliberately short for deck operations; it may need retuning if the visual stop feels too compressed.

---

### Session Summary (2026-04-29) — Landing Scoring and Debug Instrumentation

**Overview:** Added a wire-based landing points system, expanded per-approach debug telemetry, and raised the FPA descent cap so aircraft can actually descend steeply enough to land. Minimum glideslope enforcement (preventing too-shallow approaches) was attempted twice and reverted; that problem remains open.

#### Landing Points Scoring
- Wire 2 (the middle arresting cable, sorted by local Z ascending) gives a 10 pt base score. Wires 1 and 3 give 5 pts.
- Score is multiplied by a lateral factor: `clamp(1 − |lateral_m| / 24.8, 0, 1)`. Catching the center of Wire 2 dead-center gives exactly 10 pts.
- `ArrestingCable` gained two public methods: `get_wire_number()` (sorts all sibling cables by Z and returns 1-based index) and `get_engage_lateral_m()` (lateral offset in meters from cable midpoint at hook engagement).
- `FlightDeckManager` tracks `_landing_score_total` and `_landing_attempt_count` across the test session. A rolling average is printed after every outcome — catches score their wire/lateral result; bolters, wave-offs, and crashes score 0. The F1 toggle resets both counters.

#### Landing Debug Snap System
- `_landing_snap(label, extra)` in `AIPilot.gd` now includes heading and nose pitch in addition to speed, altitude, vertical speed, FPA, bank, and gear state.
- The `extra` parameter carries wire/lateral/score data on CAUGHT lines and `pts=0.0` on BOLTER/WAVE-OFF/DESTROYED lines.
- Three distance-triggered snaps fire at 400 m, 200 m, and 100 m from the touchdown point during each approach, giving a four-line trace per landing attempt (three distance snaps + outcome).
- One-shot flags (`_land_snap_400_done`, `_land_snap_200_done`, `_land_snap_100_done`, `_land_snap_touch_done`) prevent duplicate fires and reset in `start_landing()`.

#### FPA Descent Cap
- Both `landing_approach_max_descent_fpa_deg` and `landing_final_max_descent_fpa_deg` raised from 10° to 25°.
- `landing_approach_fpa_pitch_input_limit` and `landing_final_pitch_input_limit` raised from 0.52/0.55 to 0.65.
- This fixed an issue where aircraft on a deep approach could not pitch down fast enough to reach the deck before overshooting.

#### Minimum Glideslope Enforcement (attempted, reverted)
- A glideslope-path carrot was implemented: the carrot was placed on the ideal 4.5° glideslope line rather than directly at the touchdown point. An aircraft 400 m out at −3 m altitude received a carrot 25 m above it, commanding a steep climb followed immediately by a steep descent. This caused pitch oscillation to ±40° and most test aircraft were destroyed. Reverted.
- A minimum FPA floor was then tried: `desired_fpa = min(desired_fpa, -deg_to_rad(glideslope_deg))` gated on `dist > 50 m and alt > 5 m`. Reverted at user request.
- The `landing_glideslope_deg` export var (4.5°) remains in `AIPilot.gd` but is currently unused. Approach path quality is the main open problem for the landing lane.

---

### Session Summary (2026-04-23) - AI Attack, Wind Farms, and Aircraft 6

**Overview:** This session concentrated on practical combat behavior and content integration rather than new command systems. The main themes were making strike aircraft actually usable and debuggable under load, hardening stale-reference crashes during aircraft death/retargeting, adding enemy wind-farm infrastructure that behaves like the rest of the world simulation, and folding a new aircraft type into the roster/debug-spawn flow.

#### AI Strike Behavior / Weapon Release / Telemetry
- Reworked AIPilot debug output cadence so pilots now report every state transition, every weapon release event, once per second during attack runs, and only occasionally (`~10 s`) outside attack-critical phases.
- Tightened release behavior so bombs and rockets are committed closer to the target instead of from overly conservative ranges.
- Bomb release logic now staggers drops rather than dumping the entire rack at once, and retains some stores for follow-up passes.
- Ground-attack aiming was simplified toward the carrier center as a cheap, stable default aimpoint while broader precision work continues.
- Enemy strike aircraft that had been diving aggressively without releasing ordnance now complete weapon delivery much more consistently.

#### AI Stability / Freed-Instance Hardening / Performance
- Hardened multiple stale-reference crash paths tied to aircraft destruction and retargeting, including dogfight enemy scans, ground-attack target sanitation, cockpit/instrument target lookups, and virtual flight/platoon support paths.
- Fixed several `is Node3D` checks that were touching previously freed instances before validating them.
- Reduced AI cost during busy air combat by throttling or caching contact filtering / sensor scans, collision-avoidance prediction, RTB trigger checks, repeated dogfight missile-targeting node lookups, and attack-run CCIP-equivalent / release-solution work.

#### Pilot Radar / Tactical Map Consistency
- Zoomed the cockpit terrain/radar map in from the old wide view to a tighter `3.5 km` range.
- Switched the cockpit map to the same terrain image/origin/span convention used by the full `M` tactical map.
- Removed the old floating-origin drift behavior so the cockpit map no longer wanders out of sync with the actual world terrain.

#### Enemy Air Operations
- Enemy `Aircraft_3` is now treated as a clean fighter: external stores are stripped so it can focus on dogfighting rather than carrier strike behavior.
- Enemy patrol presence increased by reducing hostile flight size, which yields more patrol elements in the world without increasing total deployed aircraft much.

#### Wind Turbines / Enemy Infrastructure
- Added a wind-turbine building asset, moved it into the proper model folder, and created a dedicated scene with health and destruction behavior.
- Wind turbines have `200 HP`, a spinning rotor around the rotor assembly's local Z axis, exploded replacement behavior that preserves rotor orientation, and aircraft-like exploded-part cleanup timing.
- Exploded turbine pieces and rotor segments are initially held together; parts disconnect when they hit the ground, and the exploded rotor continues spinning.
- Startup world generation now places `25` enemy wind turbines in elevated groups of `3-4`, with nearest-neighbor spacing around `80-120 m`.
- Wind farms remain cheap at long range by existing as distant markers until the player gets closer, then pop in around `3000 m` and collapse back to marker form beyond `4000 m`.
- Wind turbines appear on the map as buildings, are treated as enemy structures, and only their `main color` material parameter is switched to team color on both intact and exploded variants.
- Added `2-3` nearby enemy gun emplacements around turbine groups, with the same main-color-only tint rule applied to emplacement visuals.
- Debug placement flow was also added so free-look `W` can place a wind turbine at the looked-at ground point.

#### Aircraft 6
- Added the new aircraft asset as `Models/Aircraft_6/aircraft_6.glb` and created `Aircraft/Aircraft_6.tscn` using Aircraft 3's scene structure as the starting point.
- Wired key `6` into the debug air-spawn flow so it spawns a friendly `Aircraft_6` at `60 m/s`, `200 m` above the carrier, already airborne.
- Tuned `Aircraft_6` to be a very forgiving low-speed aircraft with slower top speed, lower stall speed, much stronger rudder authority, much higher passive stability/damping, and substantially higher durability.
- Left custom exploded-model hookup for later because no Aircraft 6-specific exploded mesh exists yet.

### Session Summary (2026-04-13) - Combat/UI/Content Integration Pass

**Overview:** This session merged a long chain of combat, vehicle, input, HUD, and presentation work into a single coherent baseline. The project moved from a mostly prototype gun/camera/control stack to a more systemic setup: shared gun profiles across mounts, tighter turret fire gating, standardized cockpit pilot/livery pipelines, and new static defense population behavior around enemy areas.

#### Identity / Project Structure
- Project name set to `Land Carrier` in `project.godot`.
- Main-scene flow and docs alignment cleaned up around the Land Carrier naming.

#### Pause Menu / UI / Font Pass
- Pause menu rebuilt around `Orbitron-VariableFont_wght.ttf` with larger all-caps menu entries and clearer spacing.
- Pause overlay tint removed (transparent pause background).
- Pause interaction now supports both keyboard and gamepad navigation/accept/back paths.
- Controls text in pause now reflects newer targeting/control bindings.

#### HUD / Flight Display
- Added attitude indicator pitch ladder behavior that rotates with aircraft roll so the ladder stays level to the horizon.
- Added side tick marks at regular pitch increments and tuned ladder width/placement.
- Moved speed and altitude readouts upward and wrapped them in dedicated boxes for readability.
- Added follow-up width tuning to make the pitch ladder slightly narrower.

#### Input / Camera / View Control
- `Start` handoff now toggles player/AI control for the currently viewed friendly aircraft without forcing target/camera swaps.
- Shoulder-button spectate cycling remains active in AI-view mode, including bridge-view contexts.
- Added target lock-to-HUD-center action on `L3`.
- Added/confirmed target cycling on D-pad left/right.
- Debug spawn controls extended: `4` spawns friendly Aircraft_4 above carrier; `R` now spawns mixed enemy Aircraft_3/Aircraft_4 flights.

#### Gun Framework / Ballistics / Hit Registration
- Introduced unified gun-profile families usable by hardpoints and turrets:
- 10 mm Machine Gun: `800 RPM`, `600 m/s`, moderately wide spread, light recoil, standard round, `5` damage, `400 m` range.
- 15 mm Machine Gun: `600 RPM`, `600 m/s`, medium spread, medium recoil, standard round, `10` damage, `500 m` range.
- 20 mm Autocannon: `400 RPM`, `500 m/s`, low spread, medium recoil, small explosive round, `20` damage, `550 m` range.
- 25 mm Autocannon: `300 RPM`, `400 m/s`, low spread, heavy recoil, small explosive round, `30` damage, `600 m` range.
- Sound routing per gun class added/cleaned:
- 10 mm uses `gun_lmg_1..9`.
- 20/25 mm uses `autocannon_1..4`.
- Projectile hit-assist radius now defaults to `0.5 m` and applies to aircraft, vehicles, and buildings.
- Runtime tuning hotkeys added: Up Arrow increases hit-assist radius by `0.2 m`, Down Arrow decreases by `0.2 m`; live radius text shown top-left.
- Turret lead now uses effective projectile speed consistent with in-sim velocity cap behavior.
- Fire gating now includes effective range checks so units stop firing beyond useful ballistic range.

#### Turret Logic / Debug / Performance
- Carrier and emplacement turret aim skill tuning:
- Carrier defense turrets: `aim_skill = 0.8`.
- Gun emplacements: `aim_skill = 0.5`.
- Turret fire logic now enforces line-of-sight to aim point before firing.
- Added extensive turret debug telemetry:
- per-tick target/lead/range/LOS/arc state logging.
- per-bullet closest miss tracking (center/edge), timeout/impact reason, and speed diagnostics.
- Rear-arc turret logic for Aircraft_4 corrected to center around aft heading with symmetric arc:
- yaw center `180 deg`, yaw limits `+/-110 deg`.
- pitch limits `+90 deg / -20 deg`.
- Increased turret angular velocity for better target tracking responsiveness while preserving damped small-angle behavior.

#### Decals / Bullet Marks / Freed-Instance Stability
- Reworked bullet-mark/decal handling to avoid freed-instance access crashes.
- Added hard cap of 15 latest bullet decals per aircraft.
- Fixed multiple freed-instance parser/runtime issues in bullet/decal diagnostic code paths.

#### Aircraft Damage / Death-State Rework
- Replaced immediate death behavior at `0 HP` with a critical-damage phase:
- player control disabled.
- control inputs jammed to random max pitch/roll directions.
- explosion rolls at `10%` chance each second.
- Final breakup now uses dark rigid debris chunks (ground-vehicle-style), each with small smoke puffs.
- Debris chunks self-destroy on terrain contact (plus lifetime fallback).

#### Aircraft / Loadouts / New Aircraft_4
- Added/integrated `Aircraft_4` into standard aircraft scene conventions and systems.
- `Aircraft_4` tuned as heavy/slower enemy type with rear turret and `140 HP`.
- Loadout updates:
- Aircraft_2 now fields 25 mm autocannon.
- Aircraft_7 and Aircraft_8 now field 20 mm autocannons.
- Aircraft_3 gained an additional hardpoint and now mounts dual 10 mm machine guns.
- Player baseline gun setup moved to 15 mm machine-gun profile.

#### Cockpit Pilot / Livery / Insignia
- Standardized cockpit pilot scene + pose usage across aircraft.
- Pilot pose controls exposed and mirrored for practical editor-side tuning.
- Cockpit visibility behavior finalized so pilot is hidden in cockpit view.
- Added randomized per-aircraft pilot material palette:
- Main color pool: grey, tan, green, dark blue.
- Main dark pool: dark grey, brown, dark blue.
- Helmet colors: sampled from the 24-color aircraft preset pool.
- Team livery randomization expanded:
- each side gets random color and insignia assignment from pools.
- `C` cycles 24 aircraft color presets (includes black, cream, pink, red variants).
- Wing/tail insignia projection pipeline improved:
- wing decal side mapping corrected.
- tail orientation corrected (including upside-down and 90-degree projection fixes).
- support for slanted stabilizer placement via editable marker orientation.

#### Propeller Visual Pipeline
- Replaced older shader/visibility workaround with authored propeller-node behavior.
- Aircraft propellers now rely on model nodes (`hub`, `blades`, `propeller disc`) so low-speed blades and high-speed disc visibility are controlled directly from asset setup.
- Fixed transparent-disc artifact regressions (invisible blades and rear-placed quad artifacts).

#### Enemy Bases / Gun Emplacements
- Expanded enemy-side static defenses beyond runway/barracks:
- new gun emplacement scene using `turret base.glb` + turret stack.
- emplacement health set to `150`.
- random weapon assignment per emplacement: 10 mm, 15 mm, or 20 mm.
- spawn pattern: `4-5` emplacement clumps per enemy faction, `1-3` emplacements per clump.
- performance behavior: emplacements stay inactive until hostiles are within activation distance.
- team livery integration: emplacement/turret materials use faction main color.
- placement robustness:
- random placement seeks suitable flat terrain near carrier-relevant ground band.
- collider-bottom grounding added so spawned emplacements sit correctly on terrain.

#### Stability / Crash Fixes
- Hardened freed-instance checks in bullet and recovery/deck code paths (including `_perform_cable_release` argument validation issues).
- Removed deprecated/unused legacy enemy box path.
- Multiple parser-warning-as-error cleanup passes performed across updated scripts.

---

### Session Summary (2026-04-06) - Performance Profiling & Fog / Atmosphere Overhaul

**Overview:** Added a frame spike logger to identify performance culprits. Profiling confirmed terrain chunk collision rebuilds (0.12s timer, 8 builds/tick) and volumetric fog as the two main sources of hitches and sustained slowdowns. Tuned both. Replaced the old flat-colour fog system with a full four-phase day/night atmosphere using a new palette designed for a dusty post-apocalyptic desert world.

#### Spike Logger
- Added temporary CSV spike logger to `ScenarioManager.gd` — logs all frames >33ms to `user://spike_log.csv` with timestamp
- Profiling revealed: 0.1–0.5s periodic spikes from terrain chunk rebuilds; sustained 4–9s slowdowns from volumetric fog GPU cost at 4K

#### Terrain Streaming
- `stream_update_interval_s` raised from 0.12s to 0.5s — reduces chunk rebuild frequency from ~8/s to ~2/s
- Initial-fill budget raised to 16 builds/tick when `_pending_builds.size() > load_radius_chunks * 2` — eliminates terrain pop-in delay on startup while steady-state stays at 2/tick
- `max_chunk_builds_per_update` default reduced to 2 in script

#### Render Scale
- `quality/3d/render_scale = 0.5` set in project settings — renders 3D at 1080p on 4K display, ~4× GPU cost reduction

#### Fog / Atmosphere System
- Switched from depth fog to volumetric fog for seamless horizon blending (no depth-cutoff seam)
- `vol_length_m = 5000` matches camera far clip; `detail_spread = 1.0` (was 6.0 in resource); emission zeroed
- Complete palette overhaul across all four phases:
  - **Dawn**: apricot/dusty salmon sky (`dust_color` `#AD6B47`), peach-amber sun disc, density 0.0012, anisotropy 0.4
  - **Day**: bleached ochre/yellow-gray glare (`#D7C299`), cream sun, density 0.0007, anisotropy 0.15
  - **Dusk**: copper/cinnabar (`#B34D24`), deep burnt-orange disc, density 0.0014, anisotropy 0.5 (strongest forward scatter)
  - **Twilight**: plum/brown-violet (`#3D2430`), wine-red sun residue, density 0.0008, anisotropy 0.0
  - Blends between phases give pre-dawn (plum→dusty rose), pre-sunset (ochre→amber), post-sunset (rust→bruised purple) for free
- Sky set to uniform `dust_col` on all four colour slots (`sky_top`, `sky_horizon`, `ground_horizon`, `ground_bottom`); `sky_curve = ground_curve = 0.45`; `zenith_darkness = 0.0` — eliminates gradient band visible during aircraft bank
- `fog_aerial_perspective = 1.0` (was missing from active code path) — syncs sky background fog to geometry fog

#### Bug Fix
- `shake_frequency: float = 8.0` declared in `aircraft.gd` — was used but never declared, causing parser error

---

### Session Summary (2026-04-05) - Floating Origin Audit & Bug Fixes

**Overview:** Audited the floating origin system added by Gemini and found 8 scripts that cache world-space positions but lacked `apply_origin_shift` handlers — 3 critical (NavGraph, both ground vehicle scripts), 4 high/medium (WorldMapSymbolLayer, RadarCanvas, BridgeHologram, CameraController), 1 low (DustEffect). Also fixed two Gemini-introduced bugs in AIPilot. Terrain chunk radius expanded. Fog/sky horizon tuning attempted but not yet resolved.

#### Floating Origin Completion
- **NavGraph.gd**: Added shift for `_nodes` PackedVector3Array (all nav graph positions) plus spatial index rebuild — without this, all ground pathfinding breaks after an origin shift
- **vehicle_enemy_light.gd** / **vehicle_friendly_light.gd**: Added shift for `_waypoint_positions`, `_nav_path_positions`, `_nav_path_goal`, `_combat_scoot_destination`
- **WorldMapSymbolLayer.gd**: Added shift for `_selection_world_pos`, `_selection_route_origin_world`, `_selection_route_points`, `_draft_origin_world`, `_draft_points` (guards `Vector3.INF` sentinels)
- **RadarCanvas.gd**: Added `_ready()` with group registration; shifts `_terrain_bounds_xz.position` so radar terrain map stays aligned
- **BridgeHologram.gd**: Shifts `_last_terrain_center_world` to prevent unnecessary terrain rebuild
- **CameraController.gd**: Shifts `deathcam_target_position`
- **DustEffect.gd**: Shifts `_last_position` to prevent one-frame speed spike

#### AIPilot Bug Fixes
- Fixed parse error from bad indentation at line 4228 in `_scan_contacts()` (Gemini had 5 tabs instead of 2)
- Fixed `is` operator crash on freed instances in both hostile and friendly sensor scan loops — `is_instance_valid(node)` must come before `node is Node3D`

#### Terrain
- `load_radius_chunks` increased from 4 to 10 so terrain geometry fills the full camera view distance (3360 m vs 1344 m before), preventing visible terrain edge/horizon

#### Fog / Sky (in progress)
- DayNightCycle now overrides `sky_horizon_color` and `ground_horizon_color` to match fog color every frame
- Day phase sky/fog colors adjusted for warmer desert haze
- `sky_curve` / `ground_curve` widened to spread horizon band
- `fog_aerial_perspective` set to 1.0
- Horizon line visibility still being addressed

---

### Session Summary (2026-04-03) - HUD / Flight Model / Ground Ops Polish

**Overview:** Visibility and flight feel polish with key HUD improvements, flight model slip tuning, and ground operations bug fixes. Added flight path vector (FPV) symbol to show actual velocity direction, tightened aircraft sideslip damping, fixed ground vehicle escorting behavior, and repaired a critical group-search issue affecting aircraft landing/recovery.

#### HUD / Flight Path Vector (`HUD/heads_up_display.gd`)
- Added flight path vector (FPV) symbol: circle with three stubs (top, left, right) showing the aircraft's actual velocity direction
- Drawn as a dotted line from the boresight crosshair to the FPV position, visible even when the FPV is off the HUD glass edge
- Calculates correctly via collimated HUD projection and handles off-screen cases gracefully, pointing toward where the aircraft is actually flying
- Only draws when airspeed > 15 m/s; hidden on the ground or very slow flight

#### Flight Model Tuning (`Aircraft/SimpleAero.gd`)
- Increased `alignment_low_speed_strength` from 0.06 to 0.3 to tighten the velocity-vector-to-nose tracking at normal maneuvering speeds
- Previous value was effectively zero, leaving aircraft feeling very loose and allowing excessive sideslip during turns; new value creates natural weathervaning without feeling locked-in

#### Ground Operations Fixes (`GroundOps/GroundOpsManager.gd`, `LandCarrier/FlightDeckManager.gd`)
- Fixed ground vehicle platoons to default to carrier escort immediately in `_process_deploy_queue()` instead of assigning a static move objective that was never updated
- Previously, newly deployed platoons would drive to a fixed point 100m behind the carrier and stop; now they form up at carrier corners and follow with velocity matching
- Fixed aircraft landing/recovery issue: `_find_arrested_aircraft()` and `_find_stopped_aircraft_in_recovery_zone()` now search `["aircraft", "ai_aircraft", "friendlies"]` groups instead of just `"aircraft"`
  - Root cause: `FlightDeckManager` removes launched AI planes from the "aircraft" group in `_configure_retrieved_aircraft_as_ai()`, making recovery invisible to single-group searches
  - This fix allows AI-launched aircraft to be properly recognized and collected during carrier recovery

#### Aircraft Roster (`Aircraft/Aircraft_8.tscn`, `LandCarrier/FlightDeckManager.gd`)
- Added `Aircraft_8` as a new deployable variant, structured identically to `Aircraft_7`
- Key `8` retrieves `Aircraft_8` from the carrier hangar



**Overview:** This pass stayed focused on feel and presentation rather than new mission systems. The terrain got another round of targeted cliff-shape cleanup, the procedural rock scatter became more believable around slopes, `Aircraft_7` was promoted into a real retrievable interceptor, engine/flight response received more tuning, and the player/AI handoff path was tightened so viewing an AI-flown aircraft feels intentional instead of half-disabled.

#### Terrain / Rock Polish (`Environment/LowPolyTerrain.gd`, `Environment/RockStream.gd`)
- Added a cliff-only planform-straightening pass so steep walls no longer read as broad rounded curtains after the previous slope quantization work.
- Added a light post-quantization washboard-suppression pass and low-frequency cliff contour jitter so the terrain keeps its low-poly structure without falling into obvious repeating zig-zags or organic billowing arcs.
- Tightened procedural rock grounding so rocks use their real mesh bounds for placement, sit slightly embedded into the terrain, and reject steep/unsupported cliff-edge placements instead of hovering in space.

#### Flight Feel / Aircraft_7 (`Aircraft/Aircraft_7.tscn`, `Aircraft/SimpleAero.gd`, `addons/simplified_flightsim/aircraft_modules/Engine/Engine.gd`, `AI/AIPilot.gd`, `LandCarrier/FlightDeckManager.gd`, `LandCarrier/LandCarrier.tscn`)
- Added `Aircraft_7` as a new hangar-retrievable interceptor based on the `Aircraft_5` setup, but tuned to be more powerful, faster, less stable, and a bit less nimble.
- Bound key `7` to retrieve `Aircraft_7` from the carrier hangar, matching the existing aircraft retrieval flow.
- Added engine throttle spool-up/down lag so aircraft no longer leap forward instantly when throttle is punched.
- Fixed an AI/player stability handoff bug that could zero out the player aircraft's stability, corrected the roll-restoring sign error, and then retuned `Aircraft_5` so the self-righting assist is present but not overbearing.
- Continued tuning the flight-path alignment helper so it stays very weak through slower flight, then only becomes meaningfully stronger at higher speed where the aircraft should feel more nose-aligned and less floaty.

#### Player/AI Handoff / Camera / HUD (`FlightDirector.gd`, `project.godot`, `tools/ScreenshotCapture.gd`, `Camera/CameraController.gd`, `LandCarrier/Commander.gd`)
- Cleaned up the controller Start-button handoff so it now toggles only the currently viewed friendly aircraft between player and AI control instead of occasionally grabbing the wrong control path.
- Added a bottom-center `AI` status overlay while the currently viewed aircraft is under AI control.
- Kept viewed-aircraft HUD/instrument presentation alive even while that aircraft is being flown by AI, and re-enabled the viewed aircraft's `CameraController` so cockpit zoom is available in that state too.
- Removed the stale joypad overlap from the old `toggle_ai_pilot` action so there is a single obvious gamepad handoff path instead of two partially conflicting ones.
- Mapped pause to the gamepad Select/Back button and restored stick-click zoom behavior for both commander view and the cockpit camera.

#### Verification
- Repeated headless Godot 4.4.1 boots were used during the terrain, flight, and control-handoff changes.
- The 2026-04-02 pass did not introduce new script or scene parse errors; the remaining output is still the existing material-remap, occasional nav-path, and headless cleanup warnings.

### Session Summary (2026-03-31) - Enemy Runway Usability, Flight Feel, and Cockpit Audio

**Overview:** This pass stayed in the "make the core loop feel convincing" lane rather than expanding scope. The work tightened the enemy runway into a more believable operating surface, improved low-speed and on-ground aircraft behavior, fixed the cockpit radar presentation, and added a broader cockpit-audio pass so interior vs exterior listening states feel much more intentional.

#### Enemy Runway / Taxiway / Radar (`Buildings/building_enemy_runway.tscn`, `Buildings/building_enemy_runway.gdshader`, `HUD/RadarCanvas.gd`)
- Fixed the cockpit radar display so the terrain map now renders directly inside a proper circular scope instead of relying on awkward post-mask geometry.
- Corrected the enemy-runway stripe shader so the painted markings stay visible from different camera angles instead of disappearing as view angle changes.
- Added a light-grey adjacent taxiway slab to the enemy runway scene to create a proper hard surface for taxi-before-launch / taxi-after-landing behavior and future runway-side building placement.

#### Ground Handling / Flight Feel (`addons/simplified_flightsim/aircraft_modules/LandingGear/LandingGear.gd`, `Aircraft/SimpleAero.gd`, `Aircraft/Aircraft_1.tscn`, `Aircraft/Aircraft_2.tscn`, `Aircraft/Aircraft_3.tscn`, `Aircraft/Aircraft_5.tscn`)
- Added low-speed rudder-driven nosewheel steering with a gradual cutoff so taxiing is controllable without making high-speed ground handling twitchy.
- Added grounded rudder assist so players can still make useful alignment corrections on takeoff and landing roll instead of losing all yaw authority whenever wheels are on the ground.
- Reduced suspension rebound damping and added a small deadband so the landing gear settles more cleanly and no longer "pumps" up and down as noticeably after touchdown.
- Replaced the old generic return-to-level feel with explicit pitch/roll stability torques, then tuned stability strength per aircraft so some types feel calmer and others remain looser/more agile.

#### Cockpit Audio / Aircraft Sound Pass (`Weather/ContinuousTurbulence.gd`, `Audio/AudioManager3D.gd`, `Audio/AudioManager3D.tscn`, `Aircraft/Aircraft_1.tscn`, `Aircraft/Aircraft_2.tscn`, `Aircraft/Aircraft_3.tscn`, `Aircraft/Aircraft_5.tscn`, `addons/simplified_flightsim/aircraft_modules/Engine/Engine.gd`)
- Replaced the shared engine loop set so each main aircraft now uses its own dedicated looping engine sound.
- Added per-aircraft cockpit interior loops that only play for the cockpit camera instead of leaking into chase/cinematic listening.
- Split cockpit airflow into layered wind / air-rush / stall-buffet sounds; the rush is now speed-driven, while buffet groundwork exists but is currently muted during tuning.
- Tightened aircraft-only audio ownership so cockpit airflow layers do not play while viewing from outside the aircraft, and all cockpit/wind layers stop cleanly when an aircraft is destroyed.
- Reworked cockpit audio presentation with stronger interior bus filtering, reduced in-cockpit stereo panning, routing of cockpit-only loops through the interior bus, and ongoing air-rush level tuning so the cockpit sounds enclosed rather than like the same exterior mix with a tiny volume cut.

#### Verification
- Repeated headless Godot 4.4.1 boots were used during the radar, runway, flight, and audio integrations.
- The 2026-03-31 polish pass did not introduce new script or scene parse errors; the remaining startup noise is still the pre-existing material-remap and headless cleanup warnings.

### Session Summary (2026-03-29) - Enemy Base Prototype and Enemy Runway Rollout

**Overview:** This pass turned the old loose enemy barracks spawn into the first real enemy-base prototype. The world now starts with one randomly placed enemy base that has its own runway site, a clustered barracks layout, and the first object-level hooks for future enemy flights, platoons, and mission generation.

#### Enemy Runway / Landing Surface (`Buildings/building_enemy_runway.tscn`, `Aircraft/aircraft.gd`, `addons/simplified_flightsim/aircraft_modules/LandingGear/LandingGear.gd`)
- Renamed the old enemy airfield concept to an **enemy runway**.
- Kept the runway as a simple Godot scene rather than an imported mesh: dark grey strip, white edge lines, and dashed centerline.
- Added the dedicated runway-surface handling needed so player aircraft can land and roll out on the enemy runway without being treated like they hit generic terrain.
- Tightened runway rollout behavior so carrier-specific "hold still on deck" damping no longer makes runway landings feel like hidden wheel brakes are engaged.

#### Enemy Base Object (`Enemies/EnemyBase.gd`, `Enemies/EnemyBase.tscn`, `Buildings/building_barracks.tscn`)
- Added a reusable `EnemyBase` scene/object as the enemy-side equivalent of the land carrier at a structural level.
- Each base now owns:
  - one runway,
  - `5-6` barracks,
  - fixed grid-aligned building slots on both sides of the runway,
  - future-facing spawn hooks for enemy flights and platoons.
- Reused the existing barracks prefab for the base structures instead of introducing a separate permanent building type.

#### Placement / Grounding (`ScenarioManager.gd`, `Buildings/building_enemy_base_ground.tscn`)
- Startup now spawns one random enemy base on the map instead of a loose debug building cluster.
- Placement scoring was expanded from a runway-only strip check to a broader base footprint so the chosen site better fits the whole installation.
- Added a dark-brown leveled foundation pad under the entire enemy base so the runway and barracks sit on visibly even ground instead of inheriting every terrain bump.
- The base pad is intentionally sunk into the terrain body enough to avoid obvious gaps while keeping the visible top surface clean and readable.

#### Enemy Spawner Hooks (`Enemies/EnemyAircraftSpawner.gd`)
- Added initial `spawn_enemy_flight_from_base(...)` and `spawn_enemy_platoon_from_base(...)` hooks so the base can later become a proper enemy operations node instead of just scenery.
- Updated the `X` debug action to spawn a full enemy base using the same layout logic as the startup path.
- For now these hooks are structural groundwork; enemy AI runway launch/recovery and autonomous mission generation are still future work.

#### Verification
- Repeated headless Godot 4.4.1 boots were used while the base/runway work was integrated.
- The enemy-base rollout completed without introducing new script or scene parse errors; the remaining startup noise is the existing material-remap and headless cleanup warnings.

### Session Summary (2026-03-28) - Interactive Tactical Command Grid Prototype

**Overview:** The `M` map moved from display-only tactical picture to the first playable command console. Flights and platoons can now be selected from the map UI, given an initial mission order, and confirmed directly through the same AirOps/GroundOps layer the AI will eventually use.

#### Tactical Command UI (`UI/WorldMapOverlay.gd`, `UI/WorldMapSymbolLayer.gd`)
- Rebuilt the full-screen `M` map into a phosphor-style command layout with left and right control panels around the existing terrain display.
- Added selectable asset lists for named flights and platoons, mission buttons that change with the selected asset, a live order-draft summary, and confirm/cancel controls.
- The center map is now an input surface: clicking it can place a target or build a CAP route draft, while the symbol layer previews the pending route and highlights the selected asset.
- Current first-slice mission set:
  - Flights: `CAP`, `CAS`, `RTB`
  - Platoons: `MOVE`, `ATTACK`, `PROTECT`, `ESCORT`, `HOLD`, `RETRIEVE`
- Current limitation: only CAP uses multi-click route execution for now; CAS and platoon target orders are still single-point tasks.

#### Air Operations Hooks (`AirOps/AirOpsManager.gd`, `AirOps/Flight.gd`)
- Added map-friendly flight query/status helpers so the UI can ask for mission, strength, lead state, position, and active waypoints without poking directly into internals.
- Added routed CAP support: the player can now issue a CAP route from the tactical map, and a single clicked CAP point auto-expands into a patrol loop.
- Manual flight orders now auto-scramble empty flights instead of silently assigning an impossible order to a zero-strength flight.

#### Ground Operations Hooks (`GroundOps/GroundOpsManager.gd`, `GroundVehicle/ground_vehicle_platoon.gd`, `GroundVehicle/vehicle_enemy_light.gd`)
- Added point-based platoon `ATTACK` and `PROTECT` objective types so the tactical map can order ground forces against map positions instead of only scene nodes.
- Empty platoons now auto-deploy when given a player order from the map.
- Deployment flow no longer overwrites a pre-staged objective with the old rally/escort defaults, so queued player orders survive the deployment phase.
- Enemy ground vehicles now treat the new position-based platoon objectives as dynamic navigation goals for replanning.

#### Verification
- Verified with a headless Godot 4.4.1 boot after the integration work.
- Existing material/UID warnings remain, but no new script errors were introduced by the tactical command grid pass.

### Session Summary (2026-03-27) - Tactical Readability, Terrain Safety, and Audio/Flight Tuning

**Overview:** This pass tightened the battlefield presentation around the `M` map, hardened ground/terrain edge cases, fixed several debug-spawn workflows, and pushed another round of tuning into aircraft feel, audio, and map readability.

#### Tactical Map / Platoon Contact Pass (`UI/WorldMapSymbolLayer.gd`, `GroundVehicle/ground_vehicle_platoon.gd`, `LandCarrier/BridgeHologram.gd`, `UI/WorldMapOverlay.gd`)
- Enemy platoons now remain visible on the flat `M` map even before their member vehicles are individually revealed.
- Platoon markers were recolored hot pink to clearly distinguish abstract platoon contacts from regular enemy ground-vehicle markers.
- The tactical map orientation bug was fixed so terrain and symbols are shown from above rather than as if viewed from below.
- Added map counters for visible enemy platoons and visible enemy ground vehicles.
- Added carrier and platoon route/waypoint visualization on the tactical map.
- Reworked platoon contact routing so the abstract platoon marker follows a nav-safe representative contact instead of tunneling straight through mountains, and platoon movement now actually follows the shown route preview instead of only acting on the final destination.
- The tactical map art direction was pushed further into a vector-monitor look, then simplified to three solid terrain elevation colors for faster reading at a glance.

#### Ground Spawn / Navigation / Streaming (`Enemies/EnemyAircraftSpawner.gd`, `GroundVehicle/vehicle_enemy_light.gd`, `Environment/LowPolyTerrain.gd`, `Environment/RockStream.gd`, `Main_Scene.tscn`, `tools/ScreenshotCapture.gd`)
- `E` now spawns an enemy platoon `7-12 km` away in a random direction on a legal, in-bounds staging point.
- Enemy ground vehicles now avoid steep-slope routes more aggressively instead of trying to drive straight up bad terrain.
- Terrain streaming now centers on the active camera and preloads farther ahead, reducing "edge of the world" holes during fast traversal.
- Ground vehicles now fall back to baked terrain heights when a streamed collision chunk has not arrived yet, preventing units from falling forever through unloaded terrain.
- `Insert` screenshots now save into the project-root `screenshots/` folder for faster debugging and review.
- Platoon and vehicle path replans were desynchronized and route-preview recomputes made change-driven, removing the obvious once-per-second hitch when platoons were active.

#### Air Ops / Flight Tuning (`Enemies/EnemyAircraftSpawner.gd`, `AI/AIPilot.gd`, `Aircraft/Aircraft_1.tscn`, `Aircraft/Aircraft_2.tscn`, `Aircraft/Aircraft_3.tscn`, `Aircraft/Aircraft_5.tscn`, `Aircraft/SimpleAero.gd`, `Aircraft/aircraft.gd`, `Weather/ContinuousTurbulence.gd`)
- `F` and `R` debug spawns were fixed: `F` now spawns three friendly `Aircraft_5`s above the carrier and keeps them in the same flight; `R` now spawns three enemy aircraft `10 km` away in a random legal direction.
- Dogfight AI now uses the existing close-pass avoidance logic during head-on merges, making aircraft break away instead of charging directly into collision.
- All aircraft received a `+2000` engine-power increase, and shared forward drag was reduced so dives and acceleration feel less artificially capped.
- Continuous turbulence at higher speed/altitude was softened so fast aircraft buffet less violently.
- Aircraft destroyed high above the ground no longer spawn the bright multichunk wreck breakup that looked like colored debris floating in the sky.

#### Weapons / Audio (`Weapons/Autocannon/Autocannon.tscn`, `Weapons/Autocannon/autocannon.gd`, `Weapons/Turrets/bullet_weapon.gd`)
- Shared aircraft autocannon rate of fire was doubled and muzzle velocity increased to `1000 m/s`.
- Aircraft autocannons and vehicle machine guns now randomize across the `gun_machinegun_auto_heavy` sound set, with overlap-friendly audio playback so long bursts sound heavier and less repetitive.

#### Terrain Presentation (`Environment/LowPolyTerrain.gd`)
- Replaced the old fixed quad diagonal split with adaptive triangulation.
- Result: the repeating left-leaning cliff-face washboard artifact disappeared while preserving the flat-shaded low-poly look.

#### Verification
- Repeated headless Godot 4.4.1 boots were used after each cluster of changes to catch script/runtime regressions.

### Session Summary (2026-03-26 late) - Ground Nav Safety, Flat Map, Splash Refresh, and Platoon Contact Abstraction

**Overview:** Tightened ground spawn/path safety around cliffs and disconnected shelves, added a fixed full-screen tactical map, refreshed startup presentation, softened battle-bus anti-air lethality, and clarified tactical spotting so enemy platoons stay abstract until their vehicles are individually revealable.

#### Ground Navigation Safety (`TerrainNavGrid.gd`, `NavGraph.gd`, `Enemies/EnemyAircraftSpawner.gd`, `GroundVehicle/vehicle_enemy_light.gd`, `GroundVehicle/vehicle_friendly_light.gd`)
- Ground platoon staging now requires not just locally acceptable terrain, but a valid anchored navigation route back toward the carrier area.
- Nav clearance treats steep transition bands more aggressively, so path anchors and routes keep a healthier margin from cliffs/high-angle terrain.
- Friendly and enemy ground vehicles now use the stricter anchor/clearance rules too, reducing the odds of isolated shelf spawns or cliff-hugging path choices.

#### Tactical Map (`UI/WorldMapOverlay.gd`, `UI/WorldMapSymbolLayer.gd`, `project.godot`, `TerrainNavGrid.gd`)
- Added a full-screen map toggle on `M`.
- The map uses a fixed `25 km x 25 km` terrain/nav window instead of dragging with the carrier; units and the carrier move across the map.
- Visual style was pushed toward a black-and-green vector display:
  - carrier-level terrain remains black,
  - the next raised band fills dark green,
  - higher terrain fills lighter green,
  - impassable cliff edges draw as bright green outlines.
- Live symbols on the `M` map reuse the holomap language so aircraft, ground vehicles, platoons, and the carrier are readable at a glance.

#### Splash / Presentation (`project.godot`, `UI/LoadingScreen.gd`)
- Both the engine boot splash and the in-project loading screen now use `splash image 5`.

#### Heavy Gun AA Tuning (`Weapons/Turrets/turret_controller.gd`, `GroundVehicle/vehicle_enemy_battle_bus.tscn`, `Projectiles/HeavyRound/heavy_round.gd`)
- Battle-bus heavy turrets now apply harsher penalties against air targets instead of behaving like highly accurate flak.
- Heavy-round splash is less punishing to aircraft, so near-misses no longer feel disproportionately lethal.

#### Tactical Contact Abstraction (`LandCarrier/BridgeHologram.gd`, `UI/WorldMapSymbolLayer.gd`)
- Enemy platoons remain visible as abstract platoon contacts before close visual breakup.
- Enemy ground vehicles no longer split into individual holomap / `M` map markers until those specific vehicle positions are revealable, which preserves the intended "platoon first, vehicles later" read.

### Session Summary (2026-03-26) - Enemy Ground Roster, Platoon Cohesion, Holomap Spotting, and Ground Combat Polish

**Overview:** Reworked the enemy ground game into a mixed platoon system with new vehicle types and turrets, tightened spawn validity so vehicles follow the same flat-ground rules as other terrain users, expanded holomap ground/platoon readability, and added several low-risk performance passes for suspension, dust, and turret scanning.

#### Enemy Ground Vehicle Roster (`GroundVehicle/vehicle_enemy_buggy.tscn`, `GroundVehicle/vehicle_enemy_pickup.tscn`, `GroundVehicle/vehicle_enemy_battle_bus.tscn`, `Enemies/EnemyAircraftSpawner.gd`)
- Retired the old single enemy vehicle from manual `E`-key spawning in favor of a random mix of buggy, pickup, and battle bus vehicles.
- Each `E` press now spawns a compact 4-vehicle enemy wave around one randomized staging point instead of a single old-style vehicle type.
- Buggy tuned as a faster/tighter light vehicle (`30 m/s`) and pickup as a tougher, wider-turning truck (`25 m/s`, more health).
- Battle bus established as the heavier support vehicle in the roster.

#### Vehicle Turrets / Weapons (`Weapons/Turrets/vehicle_lmg_turret.tscn`, `Weapons/Turrets/vehicle_heavy_gun_turret.tscn`, `Weapons/Turrets/heavy_gun_weapon.tscn`, `Projectiles/HeavyRound/*`)
- Added a simple same-origin vehicle LMG turret rig for buggy/pickup mounts.
- Added a heavy-gun turret for the battle bus that fires smaller explosive rounds rather than plain bullets.
- Heavy-gun scene wiring was corrected so only one barrel elevates visually (mount/base split correctly between the two GLB instances).
- Heavy-gun projectile speed reduced to `500 m/s`.

#### Platoon Movement / Formation (`GroundVehicle/ground_vehicle_platoon.gd`, `GroundVehicle/vehicle_enemy_light.gd`, `GroundVehicle/vehicle_friendly_light.gd`)
- Replaced the old nearest-neighbor “glue” behavior with simple platoon formation slots.
- Platoons now pace themselves to the slowest member while traveling out of combat.
- Vehicles break out of formation while actively fighting and naturally reform once combat ends.
- Escort routing/path use was tightened so escort vehicles stop trying to path through the carrier hull while reaching front-corner slots.

#### Ground Spawn Validity (`Enemies/EnemyAircraftSpawner.gd`)
- Enemy/friendly vehicle staging logic now checks local terrain flatness instead of only matching carrier-relative height.
- Individual spawned vehicles also search for nearby valid flat ground patches before final placement.
- Result: platoons are much less likely to appear on steep hillsides or partially buried in terrain.

#### Ground Combat Readability / Accuracy Tuning (`GroundVehicle/vehicle_enemy_light.gd`, `Enemies/EnemyBox.gd`, `Enemies/EnemyAircraft.gd`)
- Enemy ground vehicles were tuned away from dead-eye accuracy by lowering `aim_skill`.
- Their firing rules remain permissive, so they still shoot often and feel aggressive.
- Static enemy boxes and older enemy aircraft defaults were also softened slightly so the broader enemy side feels less laser-precise overall.

#### Holomap (`LandCarrier/BridgeHologram.gd`)
- Ground units now render as cubes instead of being misclassified as aircraft wedge markers.
- Friendly ground vehicles show as blue cubes; enemy ground vehicles as red cubes.
- Enemy platoons render as medium red cubes centered on the platoon position.
- Platoon markers no longer reveal by range alone; they appear only when the carrier or another friendly observer has terrain line-of-sight to the platoon center.

#### Performance / Effects (`GroundVehicle/vehicle_enemy_light.gd`, `GroundVehicle/vehicle_friendly_light.gd`, `Effects/DustEffect.gd`, `Effects/ParticleManager.gd`, `Weapons/Turrets/turret_controller.gd`)
- Suspension probing is now distance-LOD’d and staggered rather than fully detailed for every vehicle at all times.
- Dust now only appears on terrain (not the ramp/deck), respects distance gating, and reuses pooled puff meshes.
- Turrets search for targets less often when far from the active camera.
- ParticleManager was hardened so pooled dust callbacks don’t crash if the owner disappears first.

#### Navigation / Stability Fixes
- Fixed an enemy-vehicle stack overflow caused by navigation path recompute recursion.
- Enemy escort/path behavior now uses staged destinations and safer path consumption logic.

### Session Summary (2026-03-24) - Aircraft_5 Wing Fold, Deck Lights, Dust Fix, Vehicle Avoidance

**Overview:** Added multi-phase wing fold animation for Aircraft_5, fixed left landing gear retraction, converted deck lights to SpotLights, fixed dust particle darkening, corrected building barracks scale, and reworked ground vehicle carrier avoidance.

#### Aircraft_5 Wing Fold (`Aircraft/WingFold5.gd`, `Aircraft/Aircraft_5.tscn`)
- New multi-phase fold animation: lateral slide (0.5s) → Y rotation (2.5s) → X rotation starts after 1s delay, overlapping with Y (1.5s).
- Left wing mesh is mirrored in the GLB — X rotation sign must be flipped (+X for left, -X for right). Y rotation is -Y for both.
- Quaternion multiplication: rest_quat * X_rotation * Y_rotation.
- Wings fold when `parking_brake` or `carrier_transport_mode` meta is set; unfold when cleared.
- Smoothstep easing on all phases.

#### Aircraft_5 Left Gear Fix (`Aircraft/Aircraft_5.tscn`)
- Added missing `gear_collision_shapes` and `gear_visual_root_paths` entries for the left landing gear.

#### Deck Lights (`LandCarrier/DeckLights.gd`, `LandCarrier/LandCarrier.tscn`)
- Converted all deck lights from OmniLight3D to SpotLight3D pointing downward (-90° X rotation).
- Reduced default light_range from 18m to 6m to prevent bleed into dust clouds and sky.
- BridgeCeilingLight also converted from OmniLight3D to SpotLight3D (spot_range=10, spot_angle=60°).

#### Dust Effect (`Effects/DustEffect.gd`)
- Changed from standard alpha transparency to additive blending (`BLEND_MODE_ADD`) to prevent dark gasoline-like appearance when particles overlap.
- Alpha range lowered to 0.05–0.12.

#### Building Barracks (`Buildings/building_barracks.tscn`, `Buildings/building_barracks_destroyed.tscn`)
- Mesh scale reduced from 20x to 1x — GLB was already the correct size.
- Collision box scaled down proportionally.

#### Enemy Base Spawning (`Enemies/EnemyAircraftSpawner.gd`)
- X key spawns 3–5 barracks buildings on flat ground 2000–3500m from carrier.
- `_find_flat_base_position()` samples terrain to find suitable flat ground.

#### Ground Vehicle Avoidance (`GroundVehicle/vehicle_friendly_light.gd`, `GroundVehicle/vehicle_enemy_light.gd`)
- Replaced rectangular carrier avoidance with elliptical zones (rx=70m, rz=90m) with tangential flow.
- Avoidance blended into steering direction only — throttle is never reduced by avoidance or facing direction.
- Vehicle-to-vehicle spacing uses nudge-based steering instead of velocity push.
- Minimum turn rate floor (50%) during avoidance to prevent slow-speed lockup.

#### Escort Formation (`GroundVehicle/ground_vehicle_platoon.gd`)
- Corner order changed: first two slots are now front-right and front-left (both ahead of carrier), instead of front-right and rear-right.

---

### Session Summary (2026-03-23) - Ground Vehicle Suspension, Driving Physics, and Polish

**Overview:** Complete rewrite of ground vehicle suspension from quaternion-based tilt to a 4-corner probe spring-damper system with Euler-decomposed pitch/roll springs. Overhauled driving physics for realistic feel. Added Aircraft_3. Various visual fixes and polish.

#### Ground Vehicle Suspension (`GroundVehicle/vehicle_enemy_light.gd`, `GroundVehicle/vehicle_friendly_light.gd`)
- New 4-corner probe system reads CollisionShape3D box size at runtime and raycasts at each corner.
- Separate pitch and roll springs using `Basis.from_euler` (EULER_ORDER_YXZ) — cleanly separates yaw steering from terrain tilt.
- Spring parameters: `spring_stiffness=120`, `spring_damping=18`, `spring_tilt_stiffness=80`, `spring_tilt_damping=18`.
- Chassis rides ~1m above ground with all 6 wheels always in surface contact.
- Works seamlessly on terrain and carrier ramp — deploy/retrieve code sets XZ only, springs handle Y and tilt.
- All `rotate_y()` calls replaced with `global_rotate(Vector3.UP, ...)` to prevent unwanted roll/pitch injection when vehicle is tilted.

#### Ground Vehicle Driving Physics
- Forward-axis velocity projection eliminates all lateral sliding.
- Asymmetric acceleration: 4x braking rate vs acceleration rate.
- Turn speed reduced (1.8→0.6), acceleration reduced (12→4), waypoint reach distance increased (8→25m).
- Carrier edge avoidance: vehicles stay 10m from carrier edges (±36x, ±52z) when not deploying/retrieving.

#### Escort Formation (`GroundVehicle/ground_vehicle_platoon.gd`)
- Corner positions now use actual carrier half-dimensions (32m wide, 48m long) plus escort distance, instead of fixed multipliers.
- 15m dead zone for stable position holding; removed carrier velocity compounding bug.

#### Carrier Ramp (`LandCarrier/VehicleRamp.gd`)
- Bay floor extended 3m past hinge to close gap at ramp/deck transition.

#### Bullet Fix (`Weapons/Turrets/bullet_weapon.gd`)
- Fixed first-frame flash: bullet transform now set before `add_child()` so `_ready()` tracer doesn't render at world origin.

#### Terrain (`Main_Scene.tscn`)
- Removed RockFeatureSpawner (large procedural rock structures with colliders). Visual-only RockStream and RockScatter preserved.

#### Shadow Quality (`project.godot`)
- Soft shadow filter quality: 0 (hard) → 2 (medium).
- Shadow atlas: 4096 → 8192.
- Cascade split blending enabled.

#### Aircraft
- Aircraft_3 model and scene added. Enemy aircraft spawner now uses `Aircraft_3.tscn`.

---

### Session Summary (2026-03-20) - Bridge Holomap, HUD Collimation, and Dogfight Gun Tuning

**Overview:** Added and heavily iterated the carrier bridge holomap, fixed the main HUD reticle so it behaves like a real collimated gunsight on the combiner glass, and kept tightening AI dogfight gun use so aircraft point harder, shoot later, and waste fewer rounds.

#### Bridge Holomap (`LandCarrier/BridgeHologram.gd`, `LandCarrier/BridgeHologram.tscn`, `LandCarrier/LandCarrier.tscn`)
- Added a 2 m x 2 m tactical holomap centered on the bridge table.
- Terrain display evolved from dots + wireframe into a wireframe-only table for cleaner readability.
- Terrain coloring now runs from deep green in low areas to neon green in high areas.
- Added faction-colored contact markers:
  - friendly aircraft = bright-blue 3D wireframe arrowheads,
  - enemy aircraft = red 3D wireframe arrowheads,
  - friendly ground vehicles = blue squares,
  - enemy ground vehicles = red squares.
- Carrier marker is now a larger bright-blue wireframe box that stands out clearly on the table.
- Aircraft markers now use full represented-aircraft orientation (yaw/pitch/roll) instead of a flat heading-only marker.
- Ground vehicles and the carrier marker were lifted so the terrain wireframe no longer visually cuts through them.
- Holomap refresh cost was reduced:
  - contacts refresh at 1 Hz,
  - terrain refresh slowed to roughly 1 Hz,
  - updates are skipped when the active camera is not near the bridge,
  - carrier-relative map projection now uses a yaw-only planar frame to avoid visible trembling from carrier pitch/roll motion.
- Reduced visual shimmer by separating terrain wireframe from the old dot layer and then removing the dot layer entirely.

#### HUD / Gunsight Collimation (`HUD/heads_up_display.gd`)
- Main gunsight reticle now uses the same ray-to-HUD-plane projection approach as the other collimated HUD symbology instead of a screen-space shortcut.
- Default HUD boresight behavior now uses aircraft forward/boresight instead of camera-forward drift.
- Fixed a temporary forward-axis mistake during the conversion; the aircraft in this project are authored facing `+Z`, and the reticle now follows that correctly.
- Result: the target box, CCIP, and main reticle now all share the same physical HUD-glass projection model.

#### AI Dogfight Gun Aiming / Fire Discipline (`AI/AIPilot.gd`, `Projectiles/Bullet/bullet.gd`)
- Tightened the precise-aim phase repeatedly so the AI drives harder through the final few degrees instead of settling for "pretty close."
- Increased terminal roll/pitch/yaw authority and reduced straight-and-level bias near gun alignment.
- Rudder usage in dogfight was loosened by reducing AI-side yaw damping/fades and raising yaw gains.
- Fire discipline was tightened substantially:
  - stricter minimum aim dot and hit-chance requirements,
  - much smaller fallback shot windows,
  - shorter gun bursts,
  - burst cancellation as soon as the fire solution becomes invalid.
- Gun aim solving now uses muzzle-point velocity instead of only aircraft-center velocity, which matters in hard turns.
- Bullet projectiles now inherit the muzzle point's angular/tangential velocity from aircraft rotation, reducing mismatch between the solved gun line and the actual bullet stream in tight maneuvering.
- Bullets can still hit wing colliders, but wing hits remain whole-aircraft damage rather than a separate localized damage model.

#### Weapons / Ammo (`Weapons/Autocannon/autocannon.gd`, `Weapons/AA_Missile/aa_missile_launcher.gd`, `Weapons/AA_Missile/aa_missile_launcher.tscn`)
- Increased autocannon ammo pool to 1000 rounds for sustained dogfight testing.
- AA missile launchers can now intentionally start with `0` ammo; launcher startup no longer auto-refills zero.

#### Carrier Defensive Turrets (`LandCarrier/CarrierDefenseTurret.tscn`)
- Reworked the carrier defense turret mount so each set can host two independently functioning turrets instead of one active turret plus one inert nested visual.
- Each turret in the set now has its own controller/weapon chain while still sharing the carrier-style turret-base mount.

### Session Summary (2026-03-17) - Carrier Air Ops Polish, Gear Pivots, and Docs Consolidation

**Overview:** Consolidated the project docs around `README.md`, added in-game radio playback, kept tightening the moving-carrier flight-deck loop, and reworked aircraft gear visuals to animate through real pivot nodes instead of popping.

#### Documentation / Project Structure (`README.md`, `docs/*`)
- Replaced the duplicated project-description flow with `README.md` as the maintained short project brief.
- Split historical material into this changelog and removed stale setup/troubleshooting duplicates.
- Added local portable Godot paths plus a ready-to-run console launch command to the README.

#### Radio / Audio (`Audio/Citadel voice test.mp3`, `Radio/RadioComms.gd`)
- Added keyboard-triggered radio playback on `V` using the Citadel voice test file.
- Routed the call through a dedicated filtered/static radio treatment for a broken comms sound.
- Moved the source MP3 into the root `Audio/` folder and updated references accordingly.

#### Carrier / Deck Presentation (`LandCarrier/LandCarrier.gd`, `LandCarrier/LandCarrier.tscn`)
- Carrier now aligns to its first active waypoint at spawn instead of beginning sideways.
- The elevator-adjacent center deck light strips were repositioned away from the elevator, raised slightly, and recolored yellow.

#### Flight Deck Recovery / Launch Reliability (`LandCarrier/FlightDeckManager.gd`, `Aircraft/AIToggle.gd`, `FlightDirector.gd`)
- Arrested recovery now handles missed cable-release signal cases by explicitly continuing recovery after manual release if needed.
- Switching a trapped/parked aircraft back to AI no longer makes it immediately throttle up and try to launch.
- Added `L` as a command that sends the nearest eligible friendly aircraft into landing mode; the old debug enemy landing shortcut moved to `Shift+L`.
- Retrieval-to-launch settling now uses wheel colliders and small pitch correction so the aircraft rests on all three wheels before the shuttle approaches.
- Tractor-bot assignment and wait logic now use shared wheel-node lookup instead of hard-coded wheel names, making recovery less fragile after aircraft scene edits.

#### AI Landing Approach / Altitude Reference (`AI/AIPilot.gd`, `Aircraft/aircraft.gd`)
- Approach sequencing now uses the authored approach marker heights directly after the aircraft reaches the horizontal gate for `approach_0`.
- Added descending capture radii for the marker sequence (`100 / 80 / 60 / 40 m`).
- After the `approach_0` horizontal gate, the AI lowers gear/tailhook/flaps and aggressively reduces throttle/speed for the landing pattern.
- Aircraft displayed altitude and AI altitude calculations now treat the carrier deck as approximately `40 m`, so deck operations read as real above-ground altitude instead of world-Y.
- Emergency terrain pull-up behavior during `APPROACH` was reduced so it stops fighting every planned descent.

#### Landing Gear / Aircraft Scene Wiring (`addons/simplified_flightsim/.../LandingGear.gd`, `Aircraft/Aircraft_1.tscn`, `Aircraft/Aircraft_2.tscn`)
- Aircraft 1 and 2 landing gear visuals now animate over time instead of popping visible/invisible.
- Added configurable per-gear stowed Euler rotations so the nose and mains can fold to different end orientations.
- Gear visuals now animate around dedicated pivot nodes in the aircraft scenes.
- Fully stowed gear visuals are hidden and stop casting shadows.
- Aircraft 2's gear scene wiring was repaired after mesh/collider changes so the deck manager, controls, and launch/recovery flow all reference the correct wheel colliders again.

#### Camera (`Camera/camera_chase.gd`)
- Chase camera behavior was reworked into a true 360-degree orbit that stays on the horizontal plane and orbits the aircraft around its origin rather than lagging behind it.

### Session Summary (2026-03-15 part 2) - Ground Vehicle Pathing, Cockpit Polish, and Hangar Persistence

**Overview:** Extended NavGraph pathing to ground vehicles, cleaned up several high-frequency debug/perf problems, improved cockpit readability/flicker in both aircraft, and expanded hangar storage to preserve more of each recovered aircraft's identity and state.

#### Ground Vehicle Pathfinding / Perf (`GroundVehicle/vehicle_enemy_light.gd`, `GroundVehicle/vehicle_friendly_light.gd`, `NavGraph.gd`)
- Friendly and enemy light vehicles now follow segmented `NavGraph` waypoint paths instead of steering straight at their long-range goal.
- Added periodic replanning, goal-shift detection, and stuck-triggered replans using the same general approach as the carrier.
- Added nearby-node checks plus retry cooldown/backoff when a vehicle cannot anchor to the graph, preventing the old once-per-second `find_path` failure loop and associated hitching.
- `NavGraph` "no node near start/goal" spam is now gated behind debug printing.

#### Carrier / Recovery Debugging (`LandCarrier/LandCarrier.gd`, `LandCarrier/FlightDeckManager.gd`)
- Carrier steering now uses signed heading error and a turn-in-place bias for better commitment to sharp path turns; debug output now reports more truthful speed/turn data.
- Added extra recovery handoff hardening in `FlightDeckManager` for arrested aircraft and expanded hangar retrieval/storage state handling.
- Recovery is still not fully reliable for all arrested-landings/player cases and remains an active debugging item.

#### Aircraft / Cockpit / HUD Polish (`Aircraft/WingFold.gd`, `Aircraft/CockpitCanopyVisibility.gd`, `HUD/heads_up_display.gd`, `Camera/CameraController.gd`)
- Aircraft 2 wing-fold hinge axis was tilted upward so folded wings point up and slightly aft; right-wing mirroring was corrected.
- HUD text, reticles, and linework now render fully opaque for better readability.
- Cockpit-view canopy hiding was expanded, and cockpit-only shadow suppression on nearby canopy/fuselage geometry was added to Aircraft 1 and Aircraft 2 to eliminate visible interior seam/shadow flicker.
- Cockpit camera near-plane tuning was added, though the shadow suppression change was the meaningful flicker fix.

#### Hangar Persistence (`LandCarrier/FlightDeckManager.gd`, `Weapons/ControlWeapons.gd`)
- Hangar storage/retrieval now preserves aircraft scene type, current health, fuel/energy state, hardpoint weapon scenes, ammo counts, and selected weapon type.
- Runtime restoration was deferred until after spawn to avoid early-node setup races.
- `ControlWeapons.find_hardpoints()` was hardened so missing aircraft references at startup/retrieval do not crash the project.

### Session Summary (2026-03-15) â€” AI Launch Polish, Air Ops Manager, Wing Fold

**Overview:** Polished the full AI carrier-launch cycle, added the Air Operations Manager that commands named flights and scrambles from the hangar when threats appear, and fixed several post-launch AI behavior issues.

#### Catapult / Launch Polish (`LandCarrier/Catapult.gd`, `LandCarrier/FlightDeckManager.gd`)
- Launch power now scales with aircraft mass: `_effective_tow_force_max = aircraft.mass Ã— launch_acceleration Ã— 4.0`, preventing light Aircraft 1 from launching too slow while still propelling heavier Aircraft 2.
- Reduced all catapult timing pauses (`engine_start_wait_s`, `spool_duration_s`, `hold_duration_s`, `settle_duration_s`) for a faster, snappier launch sequence.
- Aircraft is now frozen (`freeze = true`) immediately when the catapult sequence begins, preventing deck rolling before the shuttle latches.
- Landing gear friction changed to use carrier-relative velocity instead of world-space velocity so parked aircraft don't drift as the carrier moves.
- `FlightDeckManager._restore_aircraft_physics()` gained a `keep_frozen` parameter used during the retrieval path so aircraft stay frozen (and on the deck surface) until the tractor bots are clear and the launch sequence takes over.
- Aircraft are lowered to deck surface (gear contact) immediately after retrieval physics handoff, before tractor bots retreat.

#### Wing Fold (`Aircraft/WingFold.gd`)
- Wings snap to fully folded on the first frame when spawned in hangar/transport mode.
- Wings fold when `carrier_transport_mode` or `parking_brake` meta is set; unfold otherwise.
- Correctly stays unfolded through the entire catapult sequence â€” parking_brake is never set during catapult, so wings don't cycle during launch.
- Fold/unfold is animated over `fold_duration` seconds (export, default 2s); fold angle and axis are also exports.

#### AIPilot Post-Launch Behavior (`AI/AIPilot.gd`)
- **LAUNCHING state:** Pull-up pitch input raised to 0.8; a minimum floor of 0.2 prevents nose-drop at any speed; transition to CLIMBING now requires both deck clearance distance AND >60m AGL.
- **CLIMBING state:** Climb waypoint is anchored to aircraft's own position at launch (not the moving carrier), so carrier turns don't drag the waypoint sideways and trigger a bank. Bank is limited to 0 below 150m AGL, growing gradually to 30Â° above 300m. Pitch is speed-gated so the aircraft doesn't over-pitch at low speed. Transition from CLIMBING to SEARCH changed from distance-based (unreachable with a forward waypoint) to **altitude-based** â€” switches when the aircraft reaches `nav_waypoint.y âˆ’ 20m`.
- **TRANSIT state:** Implemented properly â€” navigates to `nav_waypoint` and transitions to SEARCH when within `on_station_radius_m` (export, default 400m). Previously this state immediately fell through to SEARCH.
- Added `on_station_radius_m` export variable.

#### Air Operations Manager (`AirOps/AirOpsManager.gd`, `AirOps/Flight.gd`)
- `AirOpsManager` is an autoload singleton with callsign **Citadel**.
- Manages four named flights: **Archer, Bulldog, Crimson, Dingo**.
- Scans for threats every 2.5s. Air threats trigger an **intercept** vector; ground vehicle threats trigger a **CAS** vector.
- When a threat appears and the best available flight has no members, **scrambles from the hangar**: calls `FlightDeckManager.queue_ai_flight(n, self)`, plays a radio scramble call, and registers each launched aircraft into the flight via `notify_aircraft_launched()`.
- Once the flight is airborne, the existing mission logic (CAP â†’ intercept/CAS â†’ recall to CAP) takes over automatically.
- When threats clear, the flight is recalled to CAP with appropriate radio comms.
- `Flight.gd` handles per-flight logic: CAP patrol, CAS target distribution (one target claimed per aircraft to avoid pile-ons), loose wedge formation during CAP, radio splash calls on target destruction, RTB ordering.

#### FlightDeckManager â€” Scramble API (`LandCarrier/FlightDeckManager.gd`)
- Added `queue_ai_flight(count: int, ops: Node)` â€” queues `count` sequential retrieval+launch cycles.
- After each catapult completion, calls `ops.notify_aircraft_launched(pilot)` with the just-launched AIPilot, then automatically starts the next retrieval if more are queued.

#### Camera / Input (`FlightDirector.gd`)
- **Space** now exits free-fly camera and returns to spectator mode (previously it cycled to the next target while staying in free camera).

---

### Session Summary (2026-03-14 part 2) - Battlefield Spawns, Radar Map, and Ground Combat Pass

**Overview:** Expanded the carrier battle sandbox with battlefield spawn controls, radar terrain visualization, better spectator/debug camera flow, and a long tuning pass on ground vehicles, turrets, projectiles, and terrain readability.

#### Battlefield Spawn / Scenario Controls (`Enemies/EnemyAircraftSpawner.gd`, platoon scripts, input cleanup)
- `F` now spawns a 5-vehicle friendly platoon on nearby ground (roughly 150-300 m from the carrier) instead of on the deck.
- Friendly platoons use a protect-the-carrier objective and try to spread around the carrier while watching for threats.
- `E` spawns a 5-vehicle enemy platoon roughly 1 km from the carrier at similar terrain height, with an attack-the-carrier objective.
- `R` spawns a 3-ship enemy strike flight about 2 km away at ~600 m altitude and points it at the carrier.
- `G` spawns a 3-ship friendly CAP flight circling over the carrier.
- Older overlapping keyboard actions on those letters were disabled so the new battlefield spawn controls do not trigger legacy behavior.

#### Camera / Spectator Debugging (`FlightDirector.gd`)
- Added a free-fly camera on `Space`:
  - first press leaves vehicle control in AI and enters free camera,
  - right stick pans the camera,
  - left stick moves/strafe-flies it up to 100 m/s,
  - pressing `Space` again cycles to the next vehicle while remaining in the free camera mode.
- Destroyed-aircraft view handoff was improved:
  - if the currently viewed aircraft dies, the camera now freezes in a detached chase-style view,
  - after ~5 seconds spectating hands off to the next aircraft or the carrier.

#### Radar / HUD (`HUD/RadarCanvas.gd`, `HUD/heads_up_display.gd`)
- Aircraft radar now draws a heading-up terrain map under the contact symbology using a low-resolution terrain snapshot.
- Radar terrain transform was corrected so the map now rotates/moves in the same frame as the contact projection.
- Terrain rendering on the radar was sharpened by emphasizing local relief, so steep cliffs read as darker, clearer lines.
- The terrain map is now visually clipped to a circular radar cutout instead of showing as a square patch.
- HUD linework/text was made darker green and thicker for better daytime readability.

#### Aircraft / Projectile / Weapon Handling (`Aircraft/aircraft.gd`, `Weapons/ControlWeapons.gd`, `Weapons/Autocannon/autocannon.gd`, `Projectiles/Bullet/bullet.gd`, `Projectiles/ProjectileNew/projectile_new.gd`)
- Aircraft no longer have their hardpoint loadouts overwritten at spawn; they keep the weapon setup authored in the scene.
- Missile-capable aircraft now auto-bootstrap the AAM targeting module if the launcher exists in the scene loadout.
- Newly spawned aircraft default back to `Autocannon` selection so they can immediately fire even before missile lock.
- Autocannon bullet speed increased to 1200 m/s and aircraft bullet inheritance was corrected to use real aircraft velocity.
- Bullets now leave larger ground impact marks and dirt/rock chips.
- Bullet impact marks also attach to aircraft and ground vehicles, not just the ground.
- Bullet visuals were simplified to reduce CPU cost while preserving rigid-body flight and the existing raycast impact path.

#### Terrain / Presentation (`Environment/LowPolyTerrain.gd`, `UI/LoadingScreen.gd`, `Camera/CockpitCamera.gd`, `LandCarrier/LandCarrier.gd`)
- "Flat" terrain now has both broad undulation and smaller local relief so it reads less ironed out.
- Cliff/canyon depth was increased for stronger vertical relief.
- Cockpit G-force camera response was reduced vertically while preserving the existing horizontal motion feel.
- Loading screen minimum display time was reduced from 5 seconds to 2 seconds.
- Carrier waypoint/pathfinding startup work was disabled by default for now to avoid long startup waits.

#### Ground Vehicles / Turrets / Combat Tuning (`GroundVehicle/*`, `Weapons/Turrets/*`)
- Added platoon-style spacing/cohesion behavior for ground vehicles with a rough 30-80 m preferred spacing band.
- Ground vehicle AI was repeatedly simplified/tuned toward "close until in range, then stop and shoot" instead of constant milling.
- Vehicle spawn/support debugging was added and used to fix a post-spawn support bug that was pulling vehicles underground on the first frame.
- Wheel support now uses per-wheel contact nodes and smoothed support points; this improved chassis support but wheel/chassis behavior is still under active tuning.
- Turret system received multiple fixes:
  - better ballistic target lead with gravity,
  - better target aim point selection on vehicles,
  - fixed stale/freed target handling,
  - fixed turret weapon cooldown behavior,
  - infinite sustained turret ammo by default,
  - lower fire rate / higher damage ground turret gun profile.
- Ground combat currently works but remains a tuning area:
  - vehicles can still look too slidey/roomba-like,
  - wheel support and combat movement still need refinement,
  - turret/barrel rig behavior has improved but is still an active polish target.

#### Air AI vs Ground Targets (`AI/AIPilot.gd`)
- Air AI ground-attack flow was extended beyond legacy `EnemyBox` handling:
  - ground vehicles and the carrier are valid surface targets,
  - attack runs use surface-aware target positions,
  - target priority favors ground vehicles over the carrier when appropriate.
- Contact scanning was updated so ground vehicles are actually included in aircraft hostile/friendly awareness.

### Session Summary (2026-03-14) - AI Ownership, Dogfight, and Missile Behavior Pass

**Overview:** Reworked control ownership so aircraft are AI-first by default, then tightened the overall autonomous combat loop around the carrier. This session also focused heavily on dogfight aiming, missile launch/guidance behavior, and stability fixes around freed-instance crashes.

#### Player Control / Spectator Ownership (`FlightDirector.gd`, `LandCarrier/FlightDeckManager.gd`, aircraft scenes, docs)
- All aircraft now default to AI control instead of spawning under player control.
- Controller `Start` now toggles between spectator mode and pilot mode:
  - leaving spectator mode transfers control to the nearest friendly aircraft,
  - pressing `Start` again returns control to AI without forcing a camera/focus reset.
- While spectating, `LB/RB` cycles between the carrier and available friendly aircraft.
- Retrieval flow was updated so recovered/launched aircraft remain AI-controlled by default.
- Controller docs were updated to match the new ownership model.

#### Coherent AI Flight Loop (`AI/AIPilot.gd`)
- Friendly aircraft now follow a single baseline loop: launch -> climb -> patrol around the moving carrier -> engage nearby threats -> return to base and land when fuel/damage requires it.
- Patrol behavior was re-centered on the carrier instead of a stale launch point.
- Air and ground target selection now runs through one carrier-centered engagement-radius filter.
- RTB checks were corrected to use real aircraft health and fuel values rather than stale/incomplete data.
- Ground attack was enabled in the default autonomous flow so AI can attack valid ground targets during patrol.

#### Dogfight Variety and Gunnery (`AI/AIPilot.gd`)
- Lost-sight behavior was expanded: when a target leaves the 120-degree forward cone, the AI now sometimes recommits efficiently and sometimes chooses a less optimal response.
- Variation behaviors now include wrong-way turns, climbs, offsets, brief extensions, and opportunistic target switching.
- These choices are held for a short randomized duration so behavior reads as intent rather than frame-to-frame noise.
- Gun aiming was upgraded from "general direction" pursuit to true ballistic aim:
  - intercept uses actual weapon mount origin/direction,
  - fire gating checks bullet travel under gravity,
  - close-in steering blends onto the real ballistic aim point so AI settles the nose before firing.

#### Air-to-Air Missile Behavior (`Projectiles/AA Missile/aa_missile.gd`, `Weapons/AA_Missile/aa_missile_launcher.gd`, `Weapons/AA_Missile/ControlTargeting_AAM.gd`, `AI/AIPilot.gd`)
- AA missiles now inherit the launching aircraft's current velocity and add their own forward rail/launch speed.
- Guidance was reworked from soft pursuit into a stronger intercept/terminal-steering model, with more reliable proximity detonation on close passes.
- AI can now choose between guns and missiles in dogfight instead of always using one weapon type.
- Missile targeting/fire path fixes:
  - standardized AI checks on weapon id `AAMissile`,
  - synced AI dogfight target into the AAM targeting module,
  - respected configurable missile lock time instead of a hardcoded 3-second requirement.
- AI missile discipline was tightened so pilots wait for the previous missile to resolve before firing another.
- Added tunable spiral guidance so missiles corkscrew toward the target for a cooler look and less perfect hit rate.

#### Collision / Damage (`Aircraft/Aircraft_1.tscn`, `Aircraft/Aircraft_2.tscn`, `Enemies/EnemyFighter.tscn`)
- Added simple wing `BoxShape3D` colliders so wing hits can register instead of only the fuselage capsule being hittable.

#### Stability / Freed-Instance Fixes (`Projectiles/AA Missile/aa_missile.gd`, `addons/simplified_flightsim/aircraft_modules/Controls/ControlLandingGear.gd`, `Weapons/AA_Missile/ControlTargeting_AAM.gd`, `AI/AIPilot.gd`)
- Fixed AA missile proximity logic to avoid passing freed targets into typed function calls.
- Hardened landing gear and tailhook dispatch against cached nodes that had already been freed.
- Hardened AAM target syncing and targeter state so destroyed targets are cleared before lock/assignment logic runs.

---

### Session Summary (2026-03-13) - Carrier Navigation Overhaul + Shadow Fix

**Overview:** Completely reworked the carrier's pathfinding to use the nav grid correctly, fixed path quality, restricted spawn/destination to the lowest terrain level, added a debug heightmap image exporter, and fixed cockpit shadow acne.

#### TerrainNavGrid â€” A* Search Window Fix (`TerrainNavGrid.gd`)
- A* search window was previously computed from `bbox(start, clipped_goal) + padding`. When `path_max_segment_m = 1600m`, this window was too small to route around large impassable areas â€” the only path might require going significantly off the direct line. Fixed: search window now uses the full `to_world` destination so A* has room to find indirect routes regardless of segment clip.

#### `_cell_clear` Separated Checks (`TerrainNavGrid.gd`)
- Old behaviour: checked all neighbours within `body_clearance_cells` radius for both impassable AND slope. This caused interior flat cells to be rejected because a distant neighbour happened to be near a plateau edge, pushing A* to route along canyon walls.
- New behaviour: **clearance radius** (3 cells) checks only impassable cells; **slope check** uses radius-1 only. Opens up wide interior corridors while still keeping the carrier away from walls.

#### LOS Smoothing Segment Limit (`TerrainNavGrid.gd`)
- Added `@export var max_smooth_segment_m: float = 400.0`. `_smooth()` now skips any candidate that would create a segment longer than this, preserving more intermediate nodes for gentler turns.

#### Lowest-Level Spawn & Destination (`TerrainNavGrid.gd`, `LandCarrier.gd`)
- `_h_min_passable` cached after bake (printed in bake log).
- Added `@export var low_level_tolerance_m: float = 80.0`.
- `get_random_passable_position()` and `get_furthest_edge_position()` now skip cells above `_h_min_passable + low_level_tolerance_m`, ensuring carrier always spawns and targets the lowest terrain level.
- `get_furthest_edge_position()` gained a `max_slope_m` parameter (was hardcoded 30.0); LandCarrier passes `path_max_slope_m = 12.0` so both endpoints use identical criteria.

#### Tread Height via Nav Grid (`LandCarrier.gd`)
- `_update_tread_visuals` replaced 6 per-frame physics raycasts with `TerrainNavGrid.sample_height()` calls (bilinear interpolation). No runtime collision queries for terrain following.
- `height_smoothing = 15.0` for snappy body Y tracking; prevents carrier sinking into rising terrain.

#### Wall Avoidance Raycasts (`LandCarrier.gd`)
- Periodic horizontal raycasts (2 per `wall_check_interval = 12` frames) detect walls/cliff faces the A* path may graze. Result stored in `_wall_steer`, scaled Ã—0.4 to nudge without overriding waypoint steering.

#### Stuck Detection & No-Path Retry (`LandCarrier.gd`)
- `_stuck_timer`: if `wp_dist` grows for 20 continuous seconds, forces a replan and clears `_wall_steer`.
- `_no_path_timer`: if no valid path for 10s, retries `_compute_next_path_segment()`.
- TerrainNavGrid `_astar` returns `[]` on failure (no straight-line fallback that would drive into cliffs).

#### Debug Heightmap Image Export (`TerrainNavGrid.gd`)
- `save_debug_image(path_world, carrier_pos, destination, max_slope_m)` saves `user://navgrid_debug.png` each time a path is received.
- 3Ã— scaled image (~900Ã—900px). Shows: grayscale heightmap, dark-purple impassable cells, full-route orange A* preview (no segment limit), active segment in red, carrier (green cross), destination (cyan cross).
- Full-route preview runs a one-shot A* with `max_segment_m = INF` just for visualization; does not affect navigation.

#### Shadow Acne Fix (`Main_Scene.tscn`)
- Cockpit canopy shading was flickering wildly due to aircraft self-shadowing with hard shadows spread over 3000m (very low shadow map density at close range).
- Changed: `shadow_bias = 0.05`, `shadow_normal_bias = 2.0` (key fix for mesh self-shadowing), `shadow_blur = 1.0` (soft edges), `directional_shadow_max_distance = 1000m`, cascade splits 0.1 / 0.3 (first cascade covers only 100m, high density for cockpit view).

---

### Session Summary (2026-03-10) - Modular Turret System Overhaul

**Overview:** Completely refactored the disjointed, hardcoded weapon systems across ground vehicles and the carrier into a unified, modular, component-based turret architecture.

#### Universal Turret Component (`Weapons/Turrets/turret.gd`)
- Designed a core `Turret` visual and mechanical component.
- Implemented smooth, physically-constrained rotations (independent base yaw and barrel pitch) to track targets, moving away from instant-snapping logic for enhanced realism.

#### Autonomous AI Gunner (`Weapons/Turrets/turret_controller.gd`)
- Shifted all aiming algorithms from the vehicles into a standalone `TurretController` AI node.
- Handles target acquisition across groups, sophisticated ballistic lead calculation (accounting for target velocity and gravity drop), and manages burst-fire logic.

#### Physical Munitions (`Weapons/Turrets/bullet_weapon.gd`)
- Replaced the Land Carrier's hitscan mechanics with real physical interactions.
- Added a `BulletWeapon` component that spawns actual physical bullet projectiles dynamically from the articulated turret barrels.

#### Deep Vehicle Integration
- Re-architected `GroundVehicle` classes (friend/enemy) to securely parent the autonomous `TurretController` directly to their tilting visual `Body` meshes. 
- Vehicles now retain terrain pitch/roll without breaking the turret aim logic or experiencing visual "floating".

---

### Session Summary (2026-03-09) - Moving Carrier Tracking Overhaul

**Overview:** All aircraft and deck objects now correctly follow the carrier as it moves (~8 m/s north continuously). Previously, horizontal movement tweens and catapult operations used stale world-space position snapshots, causing aircraft to slide off the back of the carrier.

#### Root Cause Fix: Carrier-Local Lerping (`LandCarrier/FlightDeckManager.gd`)
- `_move_aircraft_horizontally`: converted from world-space lerp to carrier-local lerp. Start and target positions are converted to carrier-local space at function start; each frame lerps in local space and converts back via `carrier.to_global()`. The world position naturally tracks carrier movement each frame.
- `_move_aircraft_smoothly`: same carrier-local conversion applied (fallback path used when no gear colliders found).

#### Per-Frame Carrier Tracking (`LandCarrier/LandCarrier.gd` â€” `_carry_deck_passengers`)
- Applied carrier's per-frame `pos_delta` to all aircraft with `parking_brake` or `carrier_transport_mode` meta (parked / elevator transport).
- Extended to catapult phase: aircraft with `controls_disabled` but not `parking_brake`/`carrier_transport_mode` are also dragged (covers full catapult sequence from physics restore to launch release).
- Added `[Deck]` debug print every 2s showing plane Z, carrier Z, and gap â€” auto-stops when `controls_disabled` is cleared at launch.

#### PinJoint3D World-Space Anchor Fix (`LandCarrier/Catapult.gd`, `LandCarrier/LandCarrier.gd`)
- During catapult spool/hold phase, PinJoint3D wheel latches were added to world root and anchored the aircraft to a fixed world-space position, overriding `pos_delta` each physics frame.
- Fix: pin joints added to `"carrier_pin_joint"` group on creation. `_carry_deck_passengers` now also moves all nodes in that group by `pos_delta`, so the constraint anchor follows the carrier and no longer fights the aircraft position.

#### Debug Message Cleanup
- `Catapult.gd`: removed per-frame `[CATAPULT] In spooling up state` and `Commanded engine throttle` spam; gated unconditional `align_aircraft` transform prints behind `debug_enabled`.
- `FlightDeckManager.gd`: removed verbose per-event prints (tractorbot staging, controls_disabled handoff, physics restore messages).
- `SimpleTractorBot.gd`, `CarrierElevator.gd`: removed all chatty per-frame/per-event debug prints.

---

### Session Summary (2026-03-08) - Visual Polish Pass

**Overview:** Visual quality pass across terrain, lighting, weapons, and explosions.

#### Terrain (`Environment/LowPolyTerrain.gd`)
- Added `strata_height_variation_m` export: low-frequency noise modulates strata band height per region, so different areas of the map have different layer thicknesses.
- Slope-based color: steep faces blend toward grey (`steep_slope_color`, `steep_slope_strength`). Mesa tops use a more beige-yellow `plateau_color`.
- Spatial gradient color variation: low-frequency noise sampled at face centroid gives smooth color patches across the terrain. Per-quad hash (not per-triangle) prevents alternating stripe artifacts.
- Fixed `get_height()` to return world-space Y by adding `global_position.y` to the sampled height.

#### Rock Scatter (`Environment/RockStream.gd`)
- Fixed rocks appearing underground: `get_height()` now returns world Y correctly.
- Fixed rocks popping/repositioning every few seconds: replaced in-place `instance_count` mutation with an atomic MultiMesh swap (`_mmi.multimesh = new_mm`), eliminating the flash-to-origin artifact.

#### Lighting (`Main_Scene.tscn`, `project.godot`)
- Hard shadow edges: `shadow_blur = 0.0`, `soft_shadow_filter_quality = 0` (disabled).
- Eliminated shadow banding stripes: `shadow_bias = 0.15`, `shadow_normal_bias = 2.0`, `directional_shadow_mode = PARALLEL_4_SPLITS`.

#### Weapons (`Weapons/Autocannon/autocannon.gd`, `Projectiles/Bullet/bullet.gd`, `AI/AIPilot.gd`)
- Autocannon `muzzle_velocity` increased from 600 â†’ 900 m/s.
- Bullet now inherits 100% of firing aircraft velocity (was 30%).
- AI lead calculation updated to match new muzzle velocity.

#### Explosions (`Projectiles/Explosion/explosion.gd`)
- Replaced flat QuadMesh smoke particles with volumetric puff system: 12 `SphereMesh` (radial_segments=6, rings=4) blobs spawned staggered over 3+ seconds, each with non-uniform random scale, rising/expanding/fading tween animation.
- Smoke color: near-black at base, dark grey higher up.
- Fixed explosion effects spawning at world origin: `trigger_explosion()` is now called via `call_deferred` so the caller can set `global_position` before effects start.
- Removed flat debris particle fountain (GPUParticles3D with black cubes).
- Scorch mark raycast updated to use `collision_mask = 0xFFFFFFFF`.

---

### Session Summary (2026-03-07) - Low-Poly Terrain + Retrieval/Combat Tuning

**Overview:** Terrain3D was replaced in the main play scene with a custom procedural low-poly terrain pipeline, and aircraft retrieval/spawn behavior was stabilized. Dogfight firing was also tightened to reduce low-probability shots.

#### Custom Terrain System (`Environment/LowPolyTerrain.gd`, `Environment/LowPolyTerrainPrototype.tscn`, `Main_Scene.tscn`)
- Large low-poly mesh terrain generated from layered procedural noise and streamed as chunks around a moving target.
- Terrain shape pass includes:
  - broad flatter zones for flight readability,
  - deep/wide gully networks,
  - mesa generation with steep sides and flatter tops,
  - stepped/snap controls to keep the faceted low-poly look.
- Added global vertical lift parameter `base_height_offset_m` to prevent gully floors from bottoming out at world `y = 0`.
- Terrain color tuning moved to warm desert palette:
  - sand shifted to deeper warm orange-brown,
  - steep surfaces shifted to cooler light gray.

#### Scene Integration / Terrain3D Replacement (`Main_Scene.tscn`, `example/Example1_Simple.gd`)
- Main scene now uses `LowPolyTerrainPrototype` as the active terrain source.
- Carrier auto-placement samples terrain heights and selects flat ground near map center at runtime.
- Streaming/tuning overrides are set in-scene for chunk radius, update cadence, and terrain morphology.

#### Retrieval/Spawn Flow Hardening (`LandCarrier/FlightDeckManager.gd`)
- Retrieval pipeline remains elevator-based (spawn in hangar space, raise to deck, handoff to catapult path).
- Resolved invalid freed-object call during retrieval ascent sequencing by tightening retrieval state/object validity handling.
- Prevented immediate post-spawn destruction regressions by preserving physics-disabled retrieval staging until proper handoff.
- Key `1` retrieval flow is configured for player-controlled aircraft on retrieval launch.

#### Dogfight Fire Discipline Updates (`AI/AIPilot.gd`)
- Gun firing adjusted to fixed half-second burst behavior.
- Fire gates tightened so AI is less trigger-happy when solution quality is poor.
- Aiming loop continues to be tuned for higher nose-point precision before firing.

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

**Overview:** Pressing **1** now spawns an AI-controlled aircraft from the hangar, which is raised by the elevator, towed to the catapult, launched, climbs to a waypoint, and then automatically begins a carrier landing approach â€” completing a full hands-off cycle.

#### Spawning AI from Hangar (`LandCarrier/FlightDeckManager.gd`)
- `_configure_retrieved_aircraft_as_ai()`: disables player UI/targeting nodes, keeps camera tripods enabled, sets `controls_disabled` (so AI stays silent until the catapult fires), enables AIToggle, and sets `ai_pilot.land_after_launch = true`.
- Aircraft is added to `friendlies` and `ai_aircraft` groups; removed from `aircraft` group.

#### AIToggle Priority Fix (`Aircraft/AIToggle.gd`)
- `enable_ai()` previously checked altitude first: aircraft on deck (Y > 10 m) wrongly went to `SEARCH` instead of `LAUNCHING`.
- Fixed: `controls_disabled` is checked **first**. Calls `ai_pilot.launch()` (not just `change_state`) so that `launch_position` is correctly recorded at the catapult deck position, enabling the 300 m deck-clearance distance calculation.

#### AIPilot `controls_disabled` Guard (`AI/AIPilot.gd`)
- `_physics_process` returns early (no `_apply_controls` call) when `controls_disabled` is set â€” prevents the AI from interfering with the catapult, tractor bots, or recovery sequence.
- Previously, calling `_apply_controls(throttle=0)` triggered `engine_stop()`, killing the catapult spool-up.

#### Post-Launch Terrain Avoidance Fix (`AI/AIPilot.gd`)
- `emergency_min_agl_m = 180 m` was firing immediately after catapult launch (aircraft at ~15 m AGL), slamming `pitch_input = 1.0` and causing a violent loop.
- Fixed: `_check_emergency_terrain_avoidance()` returns early for `LAUNCHING` (always) and for `CLIMBING` when climbing (`linear_velocity.y > 2 m/s`).

#### LAUNCHING State (`AI/AIPilot.gd`)
- Applies `pitch_input = 0.05` when `vel.y < 2 m/s` to prevent gravity drag into the ground during the brief deck-clearance phase.
- Transitions to `CLIMBING` once aircraft is 300 m from the recorded launch position.

#### CLIMBING State Overhaul (`AI/AIPilot.gd`)
- **Waypoint:** Fixed 3D point at `carrier_position + launch_forward Ã— 600 m`, altitude = `carrier.y + 200 m`. Computed from stable inputs (carrier position + launch heading) so it is the same point every frame.
- **Exit condition:** `distance_to(nav_waypoint) < 200 m` â€” aircraft physically clears the waypoint. Previous altitude-only check was broken (waypoint was recalculated 1000 m ahead each frame, so distance was always ~1000 m).
- **Aggressive climb:** forces `pitch_input = 0.5` and `_smoothed_pitch_input = 0.5` directly while more than 50 m below target, bypassing the slow lerp ramp.
- **Pitch authority:** CLIMBING now uses `vs_limit = 25 m/s`, `vs_gain = 0.15` in `_navigate_to_waypoint()` (vs normal 10/0.08).
- **Gear/flap retraction:** runs on the first airborne frame in CLIMBING as before.

#### Land-After-Launch Flow
- `land_after_launch` flag (set by FDM before catapult) â†’ cleared in `_state_launching()` when deck-clear, sets `_land_after_climb = true`.
- When climb waypoint is cleared and `_land_after_climb` is set â†’ calls `start_landing()`.
- This ensures the aircraft goes through a proper climb (gear up, altitude gained) before attempting the approach, rather than diving straight from the deck toward the carrier.

---

### Session Summary (2026-03-04) - AI Carrier Landing & Hangar Recovery

**Overview:** AI aircraft can now complete the full carrier cycle autonomously: fly an approach, catch the arresting wire, stop safely, and be moved to the hangar without any player input.

#### AI Bomb Attack Improvements
- **CCIP tolerance tightened** from 50 m to 30 m for more accurate release.
- **Improving-accuracy hold:** AI waits for peak CCIP accuracy before releasingâ€”holds fire while predicted miss is still decreasing and > 8 m, then releases at the minimum.
- **Systematic undershoot fixed:** `bomb_dive_aim_height_m` changed from 80 m to 0 m so the ballistic arc sweeps through the target rather than stopping short. Terrain clearance margin reduced from 80 m to 25 m. Result: bomb miss distance improved from ~32 m to ~22 m.
- **Multi-bomb drops restored:** 3 bombs per run with 0.2 s spacing (was 1 bomb; 0.5 s spacing was too long for CCIP to remain within tolerance).
- **Attack setup altitude** raised from 500 m to 650 m offset for better flight-path-angle buildup.

#### Bank Angle Judder Fix (`AI/AIPilot.gd`)
- Root cause: `desired_bank` was computed from `lateral_ratio` (local aircraft frame), which oscillates as the aircraft rolls, causing feedback near max bank.
- Fix: switched to world-space `bearing_err_rad` for both normal and precise aim modes. Bank is now `clamp(bearing_err_rad Ã— gain, Â±bank_limit)`.

#### Carrier Landing Tumble Fix (`LandCarrier/ArrestingCable.gd`, `LandingGear/LandingGear.gd`)
- **Root cause:** Lateral centering force was applied at the hook position (2.4 m behind, 1.7 m below CG), generating yaw and roll torques. Roll developed at ~200Â°/s; roll stabilization was capped too low (~20 kNÂ·m).
- **Fixes applied:**
  - Lateral centering force moved to CG (`apply_central_force` instead of `apply_force` at hook offset).
  - `roll_max_torque_g_m` raised 3.0 â†’ 30.0 (cap lifted from ~20 kNÂ·m to ~200 kNÂ·m).
  - Added `deck_hold_force` (15,000 N per wheel) in LandingGear: pulls each wheel toward the deck surface during cable engagement to resist flipping.
- **Result:** Roll holds at 0.0Â° throughout arrest; all wheels stay on deck; aircraft stops cleanly.

#### AI Post-Landing Recovery (`AI/AIPilot.gd`, `LandCarrier/FlightDeckManager.gd`)
- **Problem:** After the arresting cable auto-released (speed < 2 m/s), AIPilot resumed `_state_landing` and hit the stall-speed guard (`throttle = 1.0`), causing the aircraft to accelerate away.
- **AIPilot changes:**
  - `_physics_process` checks `controls_disabled` meta at entry; if set, zeros all inputs, calls `_apply_controls()`, and returnsâ€”preventing the AI from fighting FlightDeckManager.
  - When arrest ends (`_arrest_engaged_prev` â†’ false), transitions to `State.IDLE` and calls `_request_carrier_recovery()` instead of resuming the approach.
  - `_request_carrier_recovery()` finds FlightDeckManager via group and calls `start_post_arrest_recovery(aircraft)`.
- **FlightDeckManager changes:**
  - New `start_post_arrest_recovery(aircraft)`: sets `parking_brake` + `controls_disabled`, stows tailhook, dispatches tractor/elevator recovery job. Skips if already in `RECOVERY_IN_PROGRESS` (signal-based path already running).
- **Result:** Aircraft is automatically moved to elevator and stored in hangar after landing, with no player input required.

---

### Session Summary (2026-03-03) - Arresting Cable Physics Overhaul
*   **Goal:** Tune the arresting cable for a ~30m, non-linear stop and improve physical realism.
*   **Mass-Adaptive Braking:** Replaced fixed-force braking with a mass-adaptive system. The cable now calculates the required force based on the aircraft's mass, ensuring consistent performance for any aircraft (e.g., a 700kg fighter or a 16,000kg bomber).
*   **Quadratic Damping:** Implemented non-linear quadratic damping (`F âˆ vÂ²`). This creates a more realistic feel, with a strong initial pull at high speed that eases off as the aircraft slows, resulting in a gentle roll-out at the end.
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

**Overview:** The AI pilot now has a complete ground attack capability. Friendly AI aircraft can patrol, detect ground targets, execute bombing runs, and return to patrolâ€”all autonomously.

**Controls:**
- **P** â€“ Spawn a friendly AI plane (EnemyAircraftSpawner)
- **O** â€“ Toggle all AI planes between patrol and attack mode
- **Y** â€“ Switch camera (bridge â†” AI plane views when no player)

---

#### AI Ground Attack State Machine

**Attack flow:**
1. **ATTACK_POSITIONING** â€“ Fly to setup waypoint (~800m in front of target, 300â€“500m above)
2. **ATTACK_INBOUND** â€“ Fly level toward target at setup altitude until dive start range
3. **ATTACK_DIVE** â€“ Dive at target, drop bombs, pull up when done
4. **ATTACK_BREAK_OFF** â€“ Fly away from target, then line up next run

**Configuration (AIPilot.gd):**
- `bomb_run_setup_distance_m`: 1400 m â€“ setup waypoint offset
- `bomb_dive_start_distance_m`: 800 m â€“ start dive at this horizontal range
- `bomb_pull_up_distance_m`: 250 m â€“ minimum distance for break-off
- `bomb_release_altitude_window_m`: 300 m â€“ drop when 5â€“300 m above target

---

#### Bomb Release Logic

**Simplified release model:**
- Drops when altitude above target is between **5 m and 300 m**
- Drops **3 bombs per run**, then pulls up
- Spacing: 0.11 s between bombs (slightly above weapon fire cooldown)
- Must be descending (flight path angle > 1Â°)
- No prediction or nose-alignment checksâ€”altitude window only

**Break-off:**
- When 3 bombs have been dropped, or
- When within 120 m of target (safety margin)

---

#### Dive & Aim Behavior

**Aim correction:**
- Uses predicted bomb impact to steer the aim point toward the target
- Correction strength increases as range decreases (0.6â€“1.2)

**Precise aim mode** (within 500 m horizontal, 400 m altitude):
- Bank limited to 35Â° for steadier approach
- Aim height reduced to target + 15 m
- Bearing-based bank control instead of lateral ratio
- Faster roll response (reduced smoothing)

**Smooth aim height transition:**
- Aim height lerps from 80 m to 15 m between 600 m and 400 m range
- Avoids abrupt pitch changes

---

#### Pitch & Dive Stability

**Soft dive entry:**
- vs_limit and vs_gain ramp over 1.2 s (18â†’40 m/s, 0.12â†’0.25)
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
- When banked > 25Â° and descending > 15 m/s, level wings first, then climb

---

#### Camera Behavior

**StandaloneCameraSwitcher (bridge-only / no-player mode):**
- Switches to bridge only when the **destroyed plane** is the one being viewed
- Viewing another plane or the bridge is unchanged when a different plane is destroyed
- Linger time: 4 s on destroyed planeâ€™s camera before switching

---

### Session Summary (2025-02-15 Part 2) - Restored Manual Control

**Historical note:**
- This section reflects the 2025-02-15 behavior only.
- Current behavior is different: aircraft default to AI control, and controller `Start/Options` toggles spectator and pilot modes.

**Changes Made:**
- âœ… Disabled AI pilot by default in `CompleteFighterJet.tscn`
- âœ… Aircraft now starts with player control enabled
- âœ… Press **A** key if you want to toggle AI pilot on (optional)

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
   - Right-click the project folder â†’ Properties â†’ Security tab
   - Ensure your user account has "Full control" permissions
   - If not, click Edit â†’ Add your user â†’ Grant "Full control"
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
   - Right-click project folder â†’ Properties
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
   - Windows: Right-click Godot executable â†’ "Run as administrator"
   - Linux/Mac: May need to adjust ownership: `sudo chown -R $USER:$USER .`

**Prevention:**
- Always ensure project folders have proper write permissions before opening in Godot
- Avoid placing projects in system-protected directories (Program Files, Windows System folders, etc.)
- Don't sync the `.godot` folder to cloud storage services (Dropbox, OneDrive, etc.) as this can cause conflicts
- Add `.godot/` to `.gitignore` - this folder should never be committed to version control

**Status:** âš ï¸ **UNRESOLVED** - Project cannot run until permissions are fixed

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
	*   Implemented a custom, unshaded terrain shader that colors the landscape based on slopeâ€”sandy brown for flat areas and gray for steep slopesâ€”to better match the project's low-poly aesthetic.
	*   Developed a performant, camera-centered rock scattering system (`RockStream`) that uses Poisson-disk sampling to distribute rocks deterministically in a ring around the camera, streaming them in and out for performance.

### Session Summary (2025-09-23)
*   **Cameras**
	*   Bridge camera: fixed discovery via `carrier_cam` group, robust aircraft/camera lookup, horizontal `look_at()` with 180Â° yaw correction, and smoothed pitch tracking.
	*   Cinematic camera: positions 100â€“200 m ahead of aircraft with random Â±30 m horizontal and 0â€“30 m vertical offsets, relative to aircraft axes (no ground snapping).
*   **Scorch Marks / Decals**
	*   Explosion and bullet decals now project cleanly: use decal projection-from-above (Basis.IDENTITY + random yaw), increased projection depth, minimal surface offset, and bullet marks attach to aircraft so they move with it.
*   **HUD / Radar**
	*   Carrier is drawn as a blue rectangle, size ~two enemy dots wide, positioned/oriented correctly from aircraft frame; applied +90Â° visual rotation for alignment.
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
  - States: IDLE â†’ MOVING_TO_AIRCRAFT â†’ COUPLING â†’ TOWING_TO_DESTINATION â†’ (DISCONNECTING) â†’ UNCOUPLING â†’ RETURNING_TO_STAGING.
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
- Targeting module: New `AircraftModule_ControlTargeting` finds targets in a Â±30â€“60Â° cone and cycles via inputs (E/Q, X to clear).
- Instrument panel UI: Top row preserved; added a lower HBox with two square displays:
  - Left: Radar map showing known enemies within 5 km, top-down relative to aircraft.
  - Right: Target view using a dedicated `SubViewport` + `Camera3D` to show the currently targeted enemy.
- Inputs: Added `target_next` (E), `target_prev` (Q), `target_clear` (X) to `project.godot`.

### Notes / Next steps
- Tractor pathing: if circling or stalls occur, confirm `approach_a_marker`, `approach_b_marker`, and `elevator_marker` assignments, and consider enabling a deck `NavigationRegion3D` for `NavAgent`.
- If a rigid rope is preferred, replace virtual rope with a tuned `Generic6DOFJoint3D` (linear limit on one axis), but this needs careful axis setup per scene orientation.
## Archived Notes From Original Project Description

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
	  AI Pilot System: AI-controlled aircraft use the same inputs as the player (aileron, elevator, rudder, throttle, gear, weapons). Core states: Launch, Climb, Transit, Search (patrol), Attack (ground attack with bombs), Break-off, RTB, Approach, Landing. **Ground attack:** AI detects ground targets (EnemyBox), sets up bombing runs from 1400 m, flies inbound, dives at 800 m, drops 3 bombs when 5â€“300 m above target, then breaks off. Press **O** to toggle AI between patrol and attack mode.
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
	  Helicopters: flyable light helicopter family with auto-governed rotor RPM, analog collective, cyclic/yaw controls, stability assist, and armed scout / attack / rescue variants.
	  Hovercraft
	  Artillery (stationary and self propelled)
Pilot Ejection & Rescue
	  Pilot Ejection: A pilot can eject before an aircraft explodes. The canopy shoots off, and the pilot in his seat is propelled upward. The seat then detaches, and the parachute opens. The pilot floats to the ground.

	  Rescue: Ejected pilots wait on the ground to be rescued either by a ground vehicle or a rescue helicopter. Ground rescue should handle pathable terrain; mesa tops, canyon ledges, and other unreachable landing sites should become air-rescue tasks.

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
	*   **AIPilot.gd**: Main AI brain with state machine (IDLE â†’ LAUNCHING â†’ CLIMBING â†’ TRANSIT â†’ SEARCH â†’ ENGAGE â†’ RTB â†’ APPROACH â†’ LANDING)
	*   **AIToggle.gd**: Toggle between AI and player control with 'A' key; disables player control modules when AI active
	*   Modified CompleteFighterJet.tscn to be AI-controlled by default
	*   Fixed SimpleAero integration (aileron_input â†’ roll_input, etc.)
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
	*   Navigation flow: "WHERE do I want to go?" â†’ "WHAT heading/pitch/roll?" â†’ "APPLY controls"
	*   Implemented proper coordinated turn physics:
		*   Bank angle selection: 20Â° (gentle) / 30-45Â° (standard) / 60Â° (steep) based on heading error
		*   Pull back elevator to turn - more bank requires more back pressure
		*   Rudder proportional to bank angle for coordination (0.5 Ã— bank ratio)
	*   Organic altitude maintenance: Pitch control responds to both altitude error and vertical speed
	*   AI naturally discovers it needs more pitch in turns to maintain altitude (lift = total lift Ã— cos(bank))
*   **Rectangular Patrol Pattern**:
	*   Implemented 4-waypoint rectangular patrol around carrier (750m Ã— 750m square at 500m altitude)
	*   AI switches waypoints when within 50m, loops continuously
	*   Carrier position saved at launch for patrol reference
	*   Enemy engagement temporarily disabled to focus on stable flight
*   **Flight Parameters & Tuning**:
	*   Set AI flight limits: max pitch Â±60Â°, max roll Â±60Â° (limits on commanded angles, not actual aircraft capability)
	*   Changed initial climb altitude from 1000m to 500m
	*   Tuned PID controllers to prevent looping and oscillation:
		*   Pitch: 0.5 P, 0.3 D (reduced from 2.0)
		*   Altitude: 0.005 P, 0.01 D
		*   Heading: 0.3 P, 0.1 D
