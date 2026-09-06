# Land Carrier

Land Carrier is a single-player strategic action game about commanding a massive tracked aircraft carrier across a hostile low-poly desert. It combines carrier operations, direct vehicle control, autonomous AI crews, tactical command, exploration, and combined-arms combat.

This README is the canonical living project document. It describes the current game, design goals, implemented systems, recent work, near-term plan, and known problems. Detailed development history belongs in the [changelog](docs/Land%20Carrier%20Changelog.md); dated investigations are evidence, not automatically current truth.

**Project state:** playable systems sandbox; not yet a complete campaign

**Engine:** Godot 4.6.2

**Main scene:** `res://UI/MainMenu.tscn`

**Status reviewed:** 2026-09-04 against the current source tree

## Project vision

The player commands a moving community of roughly 250-350 people living aboard a land carrier approximately 200 m long and 35 m tall, carried by six massive tracks. The carrier is a home, airbase, logistics hub, weapons platform, and strategic commitment. Losing aircraft, pilots, supplies, access routes, or time should matter because those losses weaken the same society the player is trying to move through the world.

The broad inspiration is the freedom and systemic problem-solving of *Armour-Geddon* and *Carrier Command*, adapted to a landlocked carrier and a more intimate crew-scale campaign. Scenarios should present goals and systemic circumstances rather than a fixed sequence of scripted missions; the player decides how to achieve them.

The visual direction is deliberately legible and austere: low-poly forms, an Amiga-era palette sensibility, deep canyons, mesas, industrial ruins, dust, haze, and large silhouettes that can be read at speed.

### Design pillars

1. **Player intent, autonomous execution.** The player sets priorities, missions, routes, and exceptions. Pilots, deck crews, platoons, repairs, and routine logistics should execute competently without constant babysitting.
2. **Command by exception.** Direct control is available because it is enjoyable or tactically important, not because routine AI is deliberately helpless.
3. **One coherent strategic loop.** Carrier movement, aircraft range, ground routes, enemy infrastructure, resources, POIs, recovery, and upgrades should alter one another rather than become isolated minigames.
4. **Open-ended problem solving.** A threat should admit several answers: avoid it, scout it, strike it, suppress it, send ground forces, accept the risk, or spend scarce resources on another route.
5. **Consequences over chores.** The carrier should feel alive through autonomous activity and visible consequences. The player intervenes where judgment matters.
6. **Legible simulation.** Tactical information, terrain mobility, sensor coverage, and AI behavior should be understandable. Prefer visible feedback loops over hidden input caps or unexplained overrides.

## Intended campaign loop

The long-form campaign is planned as a sequence of large regions rather than one undifferentiated endless map:

1. Enter a region with incomplete information.
2. Explore with the carrier, aircraft, helicopters, and ground platoons.
3. Identify routes, threats, infrastructure, resources, survivors, and opportunities.
4. Choose an operational intent: move quickly, remain concealed, resupply, rescue, raid, or dismantle a threat network.
5. Let the carrier's autonomous systems execute that intent while the player handles exceptions or takes direct control.
6. Recover, repair, rearm, and live with the consequences.
7. Reach an exit and carry the resulting state into the next region.

The campaign loop is a design direction, not complete current functionality. The present build contains many of its component systems and a first same-region strategic checkpoint save, but no complete region objective, strategic economy, or between-region persistence.

<details>
<summary>Planned ending direction - spoilers</summary>

The journey is meant to be oriented toward a mythical green sanctuary. At the end, the player reaches a ruined city whose tallest buildings reveal a vast ocean beyond it. The land carrier was once capable of becoming a ship; after repairs and preparation, it jettisons its tracks and enters the water.

The exact way this is foreshadowed and mechanically earned remains deliberately open. The ending should emerge from the campaign's movement, survival, repair, and community themes rather than feel like an unrelated final cutscene.

</details>

## Current playable state

The game already supports a substantial combined-arms sandbox. Most major systems work in isolation or in focused scenarios; the largest missing layer is the strategic structure that makes their outcomes persist and matter.

| Area | Current capability | Important limit |
|---|---|---|
| World and terrain | Streamed procedural low-poly canyon terrain, floating origin, rock streaming, day/night cycle, dust, fog, and two selectable terrain profiles | Large-map preprocessing and valley rendering remain performance watch areas |
| Strategic map | `50 km x 50 km` navigation and tactical-map coverage, cursor-centred zoom and scrollbar panning, relief shading, mobility overlays, routes, contacts, mission drafting, and loading progress | The map is a command surface, but it does not yet express a regional objective or economy |
| Exploration | Persistent fog of war: carrier, aircraft, helicopters, and ground vehicles permanently reveal terrain as they travel | Exploration persists through strategic checkpoint saves, but not yet between regions |
| Carrier movement | Player-authored routes over carrier-legal terrain; no automatic route is assigned at scenario start | The carrier cannot be ordered into unexplored terrain |
| Carrier deck | Hangar, elevator, tractor bots, catapult launch, deck staging, landing clearance, arresting wires, and recovery flow | Full mission-to-recovery reliability is promising but not yet accepted across the complete validation suite |
| Air operations | Four named flights, sensor-fused tasking, CAP/intercept/strike roles, autonomous downed-pilot tracking and Aircraft_11 rescue dispatch, player orders, threat-driven scrambling, and direct flight control | Standing CAP no longer auto-launches at startup; the rescue path still needs full live scenario validation, and richer player doctrine and mission editing remain planned |
| Ground operations | Four named platoons, vehicle-bay deployment/retrieval, formations, escort, move, attack, protect, hold, and map-issued orders | Player ground destinations must already be explored; pathing and steep-terrain behavior still need broad live testing |
| Combat | Fixed-wing, helicopter, vehicle, turret, rocket, bomb, gun, damage, destruction, and ejection systems | Balance and some AI flight-path integration remain under investigation |
| Enemy operations | Bases, patrols, ground forces, emplacements, wind farms, virtualized distant units, and replenishment behavior | Destroying infrastructure does not yet remove a clearly communicated enemy capability |
| POIs | Procedural placement, physical world-site hooks, aircraft discovery, ground investigation, non-modal awaiting-orders notices, tactical markers, and choice cards | Wrecked Scout Car and Abandoned Outpost now provide real intelligence consequences; the other nine POI definitions remain presentation-only |
| Personnel | Pilot roster, skills, experience, kills, wounds/rest hooks, callsigns, voices, personnel UI, and checkpoint persistence | Rescue pickup is implemented but is not yet connected to injury, rest, and full career continuity |
| Command UI | Carrier console with Tactical and Personnel views, map selection during new game, mission confirmation flow, and live unit state | This is the first command-screen slice, not the final strategic interface |
| Campaign checkpoints | Validated primary-plus-backup save slot, automatic safe-state checkpoints, pause-menu save status, and main-menu Continue | Calm deployed CAP/transit/RTB flights and moving/protecting/escorting platoons are preserved; active attack orders, combat, tracked mobile enemies, and moving deck machinery must clear first |

### Map profiles

- **Open Canyons** is the original procedural canyon landscape and the default map.
- **Fractured Badlands** adds stronger continuous vertical variation, irregular ridges, mesas, basins, three protected carrier-scale cross-map routes, and four cross-connectors. Its protected routes are validated at a maximum `20 degree` grade across the carrier-width traces.

Both profiles use the same `50 km x 50 km` strategic/nav footprint. The tactical map distinguishes general vehicle terrain from the more restrictive carrier corridors. Potential bridges and overpasses are a future extension; they are not currently represented as separate stacked navigation layers.

### Fog of war and order rules

- Terrain begins greyed out on the tactical map.
- Exploration is permanent for the duration of the scenario.
- Fixed-wing aircraft reveal a `3000 m` radius, helicopters `2000 m`, the carrier `3000 m`, and ground vehicles `800 m` by default.
- Friendly ground orders and carrier route points are rejected when their destination is unexplored.
- Enemy AI continues to use global navigation; the exploration restriction is enforced only at the player command boundary.
- While the tactical map is open, `H` temporarily removes or reapplies the fog mask for debugging. It does not alter exploration state.

## Recent changes

This is a short current summary, not a second full changelog.

### September 2026 - first consequential POI

- Added a physical Wrecked Scout Car site using the authored `Models/wrecked car.glb` asset, with a grounded wreck pose and physical collision.
- A ground team reaching the site now files a non-modal `AWAITING ORDERS` notice instead of interrupting play. The decision can be opened from the notice or its pulsing tactical-map star, and deferring it leaves the order pending.
- Recovering the patrol log reveals the nearest enemy base and a five-kilometre sector around it. Pending/resolved choice state and the revealed intelligence target persist through campaign checkpoints.
- Turned the former Abandoned Settlement card into a physical Abandoned Outpost using `Models/ruin - building.glb`. Recovering its survey records reveals the two nearest unknown POIs and enough surrounding terrain to dispatch ground teams to them.

### September 2026 - carrier command authority

- Made the tactical-map `HOLD` order authoritative during aircraft launches. Launch safety can straighten and slow an actively routed carrier, but it no longer creates movement or requests an autonomous launch-corridor reposition after the player has stopped the carrier; a terrain-blocked launch now waits for a new movement order.

### September 2026 - tactical-map navigation

- Added cursor-centred tactical-map zoom from `1x` to `8x`. Right trigger or left mouse button zooms in; left trigger or right mouse button zooms out.
- Added horizontal and vertical map scrollbars for panning the zoomed view. Terrain, fog, mobility, symbols, routes, hit-testing, grid references, and hover readouts now share the same view transform.
- Mouse clicks retain their target/waypoint editing roles while an order is being drafted; controller triggers remain available for zoom at all times.

### August 2026 - strategic checkpoints

- Added a persistent Gameplay selector for `SIMPLIFIED` and `ADVANCED` fixed-wing flight models. Advanced remains the default and owns the explicit quadratic drag, half-thrust baseline, high-speed control envelope, stress feedback, and progressive departure work; Simplified restores the pre-overhaul response.
- Added a progressive advanced-model fixed-wing stall departure with a local-axis nose break, persistent wing drop, autorotation, reduced stabilizing assistance, recovery hysteresis, and sharply separated controls in an established stall. The experimental rudder-to-roll coupling was removed; the fixed-wing rudder assist remains slower, travel-limited, speed-scheduled, and driven by geometric sideslip in Advanced.
- Expanded the player-only fixed-wing recorder to buffered 10 Hz telemetry covering raw and assisted controls, acceleration and G, specific energy, aerodynamic forces, departure state, control ownership, and numbered L3 markers.
- Added a first same-region checkpoint system which persists carrier position and route, resources, hangar and vehicle-bay inventory, pilot records, exploration, POIs, enemy bases and virtual formations, destroyed infrastructure, and floating-origin terrain state.
- Added automatic checkpoints after a calm safe-state window, a manually gated `SAVE CAMPAIGN` pause action with a specific blocker message, and a validated `CONTINUE` main-menu action. Writes are validated through a temporary file and retain the previous checkpoint as a backup.
- Checkpoints deliberately exclude volatile combat state. Calm deployed flights preserve aircraft type, pilot, loadout, damage, fuel, engine and gear state, transform, velocity, and CAP/RTB intent; calm deployed platoons preserve vehicle damage, transform, velocity, and movement/protection/escort intent. Active CAS/intercept/pursuit/attack orders, active combat, downed-pilot rescue, launch/recovery sequences, moving deck or bay machinery, tracked mobile enemies, and enemy attacks or materialized enemy formations must clear before saving.

### August 2026 - large map and command layer

- Expanded the tactical/navigation footprint to `50 km x 50 km` and added a progress-reporting scenario loading screen with slowly rotating pseudo-technical status messages.
- Added persistent fog-of-war exploration, correct observer-relative reveal, unexplored-order rejection, and the `H` fog-mask inspection toggle.
- Removed automatic carrier routing and corrected initial carrier, aircraft, deck-passenger, and ground-platoon placement so startup units no longer create remote explored patches.
- Added selectable Open Canyons and Fractured Badlands profiles. Fractured Badlands now uses continuous varied elevation rather than fixed global shelves, with three protected routes and four usable cross-connectors.
- Rebuilt tactical-map terrain presentation around relief and mobility: vehicle routes and carrier-legal corridors are visually distinct.
- Added incremental rock streaming and more generous rock placement away from steep slopes while suppressing rocks on or near near-vertical terrain.
- Refined the carrier console, mission flyout, confirmation gating, personnel view, and pilot presentation.
- Changed AirOps startup behavior so a standing CAP requirement does not empty the hangar automatically; real intercepts, strikes, and explicit player orders can still launch flights.
- Added persistent Air Ops tracking for downed pilots, automatic Aircraft_11 rescue launch and reassignment, pickup completion, and three configurable utility helicopters in the starting hangar.
- Added a main-menu Technical Index with nested ground-vehicle, airplane, helicopter, structure, and weapon catalogs. Entries load their gameplay scene into an isolated rotatable 3D preview and show a description plus scene-derived specifications.

### Late July to early August 2026 - operations and validation

- Added unified operations/order infrastructure, a world unit index, ground-combat allocation tests, and broader performance budgets for aircraft, vehicles, particles, impacts, wrecks, and debris.
- Reworked carrier recovery setup and demonstrated focused catches from dirty entries plus a two-aircraft queue. The full acceptance matrix and mixed combat/recovery suite remain incomplete.
- Improved ground-threat assignment and engagement saturation so aircraft do not abandon relevant ground combat merely because another gunner is already engaged.
- Added loaded landing-gear stance and visible lower-strut compression to the newer gear rig.

### July 2026 - air combat and AirOps

- Reworked dogfight gunnery around curved lead, energy discipline, threat/opportunity target scoring, role posture, and anti-stalemate behavior.
- Rebuilt AirOps from fixed slots into a dynamic mission board using the friendly sensor picture.
- Added meaningful combat-event logging and reduced duplicate radio barks.

For detailed dated history, including experiments and reverted approaches, use the [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md).

## Near-term roadmap

### Priority 1 - first complete regional traversal slice

The next feature should make the existing systems form one small playable game:

- Start the carrier near one edge of a region and define a reachable exit near the opposite edge.
- Put one enemy base or capability network across the fastest carrier route while retaining slower or riskier alternatives.
- Give scouting enough information to compare those routes without revealing the whole solution.
- Make at least one target change a concrete enemy capability, such as patrol generation, radar coverage, ground reinforcement, or repair/rearm rate.
- Expand real POI consequences beyond the first Wrecked Scout Car intelligence reward into supplies, rescue opportunities, route access, and difficult trade-offs.
- End the region with a concise operational summary: time, losses, pilots, surviving vehicles, resources gained/spent, infrastructure destroyed, and route taken.

This slice should use temporary scenario-scoped state first. It does not need the entire campaign persistence system before it can prove the loop.

### Priority 2 - consequences and enemy network

- Replace generic destruction with readable capability effects.
- Make enemy bases, radar, logistics, airfields, emplacements, and patrol generation part of one network.
- Surface cause and effect in the tactical UI and combat log.
- Let stealth, delay, attrition, and route choice remain valid alternatives to destroying everything.

### Priority 3 - operational resources and persistence

- Define the minimum economy needed for decisions: likely fuel, munitions, spares, and a fabrication/salvage resource.
- Connect sorties, carrier movement, repair, recovery, POIs, and enemy infrastructure to those resources.
- Decide deliberately which resources are shared carrier pools and which belong to individual units; avoid per-unit accounting unless it creates a meaningful decision.
- Make returning aircraft refuel, rearm, and repair through the carrier economy rather than resetting for free.
- Extend the calm-state checkpoint slice toward region transitions and explicit scenario seeds. Keep volatile projectiles, particles, in-progress deck animations, async path jobs, and radio queues out of the save contract.

### Later possibilities

- Bridges, overpasses, tunnels, and stacked routes using authored connection points and a layered/hybrid navigation graph.
- Weather with operational effects: sandstorms, electrical storms, reduced visibility, and terrain-dependent hazards.
- Structural part damage and breakoff for aircraft, vehicles, buildings, and the carrier.
- Decouple machine-gun presentation from authoritative projectile cadence: retain the current simulated bullets and damage while using high-rate rattling gun audio, a few additional batched cosmetic tracers, and clustered impact art such as three small holes within one pooled decal.
- Modular aircraft components and upgrades, including engines, control systems, landing gear, weapons, and field repair/fabrication choices.
- Complete ejection, downed-pilot rescue, injury, rest, and career-continuity loops.
- Broader helicopter roles: rescue/winch, scout, attack, and gunship support.
- More terrain profiles, regional biomes, upgrades, fabrication, and an in-game vehicle/weapon codex.

### Open design decisions

- What constitutes defeat beyond the carrier's destruction: loss of mobility, loss of the community, resource exhaustion, or failure to leave a region?
- How much crew management should exist beyond pilots and operational staffing without turning command into roster maintenance?
- Which upgrades are discovered, fabricated, salvaged, or unlocked by defeating enemy infrastructure?
- How should enemy escalation respond to the player's progress without making successful play feel like an arbitrary punishment?
- How much of each region should be authored versus generated? Objectives may be authored, but their solution should remain systemic rather than scripted.

## Known problems and validation gaps

These items are deliberately phrased by evidence level. Older reports may describe failures that have since changed.

| Status | Problem | Current evidence / next proof |
|---|---|---|
| Partly resolved | Most POI decisions have no gameplay effect | Wrecked Scout Car reveals the nearest enemy base and its five-kilometre sector; Abandoned Outpost reveals two nearby unknown POIs; the other nine definitions still only close their cards |
| Confirmed | No regional win condition, strategic economy, or between-region persistence | A first same-region calm-state checkpoint exists, but the larger campaign transition and economy systems have not been implemented |
| Confirmed | Carrier tread animation has visible discontinuities at the lower turnarounds | Debug the baked loop coordinate before further shader tuning; see the track report |
| Partly resolved | Fixed-wing carrier recovery | Focused dirty-entry and two-aircraft catches succeeded on the current recovery work, but the remaining matrix, 100-attempt final regression, and 20-run mixed suite were not completed |
| Implemented / fleet tuning pending | Advanced fixed-wing energy, parasite drag, control envelope, and stall departure | Advanced removes hidden combined linear damping, uses the half-power baseline, and models explicit drag, axis-specific authority, rate-limited surfaces, progressive departure, and stress feedback; Simplified preserves the former response, and each airframe still needs rendered level/dive/pullout/stall tuning |
| Unresolved / needs current retest | Fixed-wing route and turn authority | Historical telemetry found a split between horizontal and vertical guidance and uncertain lift response; later code changed substantially, so the old diagnosis is a baseline rather than proof of the current failure |
| Needs current measurement | Valley-frame performance | Low frame rates were observed in valleys; terrain/rock streaming and presentation budgets were changed afterward, but no current acceptance measurement is documented here |
| Needs current retest | Carrier/free-camera 3D audio | The last written investigation from April ended with inconsistent or missing carrier sound; its present state has not been re-verified during this documentation pass |
| Investigate | 3D texture mipmaps and insignia residency | Enable mipmaps selectively for distance-viewed 3D textures such as tracks, scorch marks, and insignia decals, but first lazy-load or size-limit the 102 insignia images instead of keeping the whole catalog resident |
| Watch item | Terrain and streamed clutter edge cases | Floating rocks, cliff-edge clearance, delayed chunks/collision, and startup preprocessing should remain in live-test coverage |
| Resolved | Bridge/commander micro-jitter | Moving the world origin and fixing mixed process/physics camera updates resolved the documented issue; keep the report as historical evidence |

## Development and verification

### Flight model gameplay setting

`SETTINGS > GAMEPLAY > FLIGHT MODEL` persistently selects the fixed-wing model. `ADVANCED` is the default for existing installs that do not yet have the setting. The setting is global, applies to player and AI fixed-wing aircraft on the next physics frame, and does not alter helicopter physics.

- `SIMPLIFIED` restores project/default rigid-body damping, the former `0.40` forward-drag scale, pre-overhaul full engine thrust, one direct low-speed/stall authority value for all axes, immediate control response without Vne stiffening, the former gentler AoA/lift-loss thresholds, scalar angular damping, and the former world-down nose force.
- `ADVANCED` uses zero hidden linear damping, explicit `2.20` forward-drag scaling, the authored half-thrust fleet values, per-axis and rate-limited control surfaces, high-speed stiffening/stress, the stronger progressive stall departure, reduced stabilizing assistance while departed, and layered speed/stress airflow feedback.
- Both modes retain fixed-wing telemetry, L3 markers, ordinary coordinated-turn auto-rudder, and ground steering assistance. Rudder input no longer applies any direct roll torque in either mode.

Advanced player pitch, roll, and manual rudder use the Gameplay flight-control deadzone once, followed by a blended cubic response rather than the former pure `power 1.8` curve. The rollout/default deadzone is `5%`. Pitch blends `35%` cubic response, roll `25%`, and rudder `15%`, retaining finite response near center and exactly full command at full stick/trigger. For a normalized post-deadzone input `x`, the mapping is `output = (1 - expo) * x + expo * x^3`. At half physical trigger with the default deadzone, manual rudder is approximately `0.42` instead of the previous `0.18`. The existing manual-rudder command still progressively fades automatic assistance. Simplified fixed-wing and helicopter controls retain the previous power curve, authored yaw-action deadzone, and second-stage deadzone.

### Fixed-wing energy and drag model

`Aircraft/SimpleAero.gd` owns fixed-wing aerodynamic drag. In Advanced, fixed-wing rigid bodies use `DAMP_MODE_REPLACE` with zero `linear_damp`, so Godot's project-default linear damping cannot add an undocumented force proportional to aircraft mass and speed. Simplified restores the rigid body's authored/default damping mode and value. Helicopters use `HelicopterFlight.gd` and are outside this change.

Clean forward parasite drag is quadratic:

```text
drag = forward_drag_strength * forward_drag_scale * drag_base_multiplier * forward_speed^2
```

The default `forward_drag_scale` is `2.20`. The first drag-isolation run used Aircraft_5's former 12,500 N engine and reached about 183 m/s in the powered dive, compared with about 140 m/s under the removed hidden damping; it retained roughly 121-138 m/s through the pullout instead of falling to about 87 m/s. That established that the old hidden damping was excessive, but it also exposed excessive sustained thrust.

The current fixed-wing baseline halves each non-helicopter scene's `PowerFactor`. Aircraft_5 now has 6,250 N thrust, `0.22` forward-drag strength, and `0.8` base multiplier, giving a theoretical clean, zero-AoA level ceiling of about 127 m/s. The same simplified force balance predicts about 166 m/s in a steady 30-degree powered dive and 197 m/s vertically, before induced/high-AoA/configuration drag. This separation is intentional: thrust sets sustained level speed, explicit quadratic drag sets dive behavior, and the control envelope makes high dive speed consequential. Because quadratic-drag terminal speed scales with the square root of thrust, halving thrust reduces a thrust-limited ceiling to about 71 percent rather than 50 percent. These are analytical baselines, not proof of final fleet balance.

Tune aircraft identity with explicit aerodynamic parameters, not `linear_damp`. For a desired clean level ceiling, estimate `drag_coefficient = engine_thrust / desired_speed^2`, then set `forward_drag_scale = drag_coefficient / (forward_drag_strength * drag_base_multiplier)`. Validate level acceleration, a powered dive, pullout retention, climb recovery, combat behavior, and carrier recovery separately. Gear/flap drag, high-angle-of-attack drag, and maneuver-induced drag remain separate forces and should not be folded into the clean-speed coefficient.

### Fixed-wing control envelope and stress feedback

`SimpleAero` turns pilot or AI commands into rate-limited elevator, aileron, and rudder positions before applying torque:

```text
player controls -> deadzone/response curve -> speed-limited desired surface -> rate-limited actual surface -> torque
AI command ---------------------------> speed-limited desired surface -> rate-limited actual surface -> torque
```

Aircraft_5 uses an Advanced `pitch_power` of `6.25`, reduced from `7.5` after a direct full-input sweep showed that pitch authority—not roll or rudder—was driving its unusually tight player pull. At 82 m/s with the authored stores fitted (`1,400 kg` runtime mass), the change reduced peak pitch rate from about `26.0` to `21.6 deg/s`, peak normal load from `3.71` to `3.27 g`, and delayed reaching `3 g` from `0.90` to `1.12 s`. The normalized input range still reaches exactly `1.0`; this changes the airframe torque behind full elevator rather than clipping the stick. Aircraft_5 retains an explicit Simplified compatibility override of `7.5`, so this Advanced handling tune does not alter the former flight model. Its `13.0` roll and `2.0` yaw powers are unchanged.

Each airframe can tune four envelope concepts in the inspector: `stall_speed`, the existing stall-relative full-control margin, `control_stiffening_start_speed_mps`, and `never_exceed_speed_mps` (Vne). `control_stiffening_full_speed_mps` defines the beyond-Vne end of the curve. At the default Vne, elevator travel is limited to 50 percent, aileron to 68 percent, and rudder to 40 percent; the surfaces also move more slowly as Vne approaches. Near the stall, the default retained authority is 35 percent elevator, 25 percent aileron, and 50 percent rudder, so rudder remains more useful than aileron during recovery. The AoA/speed stall loss is applied on top of those floors.

The high-speed yaw wobble was traced to the full-strength rudder assist interacting with rate-limited surfaces. A fresh 110-127 m/s report contained 59 saturated rudder commands in 119 samples, 75 command-sign reversals, and 11 samples where the lagging surface still opposed the newest command. The fixed-wing assist now responds at 4 input units/s and is limited to 35 percent travel in the normal envelope; it slows to 1.2 units/s and 18 percent travel as high-speed stiffening reaches full effect. It responds to geometric sideslip by default instead of feeding `SimpleAero`'s alignment acceleration back into itself. In Advanced mode, positive local-X sideslip now produces positive yaw, matching the +Z-forward `SimpleAero` convention; Simplified aircraft and helicopters retain their established sign convention. Coordinated-turn auto-rudder also follows the actual aileron position, so it cannot reverse before the ailerons cross neutral. In the isolated Aircraft_5 runtime regression, with central lateral alignment disabled, a 170 m/s start with 7 percent sideslip reached 0.87 high-speed stiffening, commanded at most 0.165 rudder, reached 0.147 actual rudder, produced no command or surface sign reversals over four seconds, and reduced sideslip to 3.2 percent. This is headless evidence that the rudder itself corrects the identified case without a limit cycle, not a substitute for a rendered high-speed handling check. Helicopter steering is unchanged.

The experimental direct rudder-to-opposite-roll torque has been removed. Rudder now produces yaw only; any future roll coupling should be reintroduced through a separately tuned aerodynamic mechanism rather than an unconditional torque shortcut.

Aircraft_5's roll-linked autorudder is `0.25`, raised from `0.15` after fresh player telemetry confirmed the previous setting produced only about 15 percent rudder relative to aileron travel and felt absent during small rolls. This is aileron-to-rudder coordination, not the removed rudder-to-roll mechanism: it follows the rate-limited physical aileron position and remains subject to the rudder's low-speed authority and high-speed travel/rate limits. The separate sideslip-assist feedback remains damped and speed-scheduled, preserving the high-speed yaw-wobble fix.

### Fixed-wing fleet handling profiles

Aircraft_5 is the fleet reference: balanced control response, stability, stall speed, autorudder, and a theoretical clean Advanced level ceiling of about `127 m/s`. Other fixed-wing scenes deliberately move connected parameters together rather than changing one arbitrary control multiplier. Each of the nine airframes now authors its normal and stiffened pitch/roll/yaw surface rates, low-speed authority margins, stiffening onset, Vne, passive directional stability, lift limit, stall-AoA range, lift loss, nose break, wing drop, autorotation, departure buildup, and recovery rate. Control power relative to angular damping sets how quickly an airframe rotates; stability and alignment set how eagerly it settles; stall and induced drag shape the low-speed and sustained-turn character; thrust and explicit quadratic drag set straight-line performance. The clean ceilings below are analytical force-balance estimates, not measured top speeds with stores or proof of final handling feel.

| Aircraft | Intended handling identity | Advanced profile highlights | Stall / Vne / clean ceiling |
| --- | --- | --- | ---: |
| Aircraft_1 / Sand Sprite | Light, versatile, responsive, but power-limited when loaded | Quick surfaces, mild directional stability, forgiving `21-40 deg` stall progression | `39 / 160 / 104 m/s` |
| Aircraft_2 / Crusader | Fast, heavy, rock-solid attack platform | Slow surfaces, strong self-leveling/weathervaning, progressive stall, high approach speed | `50 / 195 / 133 m/s` |
| Aircraft_3 / Wasp | Primitive light fighter that is lively but still recoverable | Very quick low-speed roll, early high-speed stiffening, distinct wing drop, mediocre energy retention | `36 / 145 / 105 m/s` |
| Aircraft_4 / Vulture | Slow armored bomber and steady gun platform | Fleet-lowest response, strongest stability, early stiffening, well-signalled nose-down stall | `47 / 130 / 95 m/s` |
| Aircraft_5 / Kestrel | Balanced multirole reference | `6.25 / 13.0 / 2.0` control power, conventional asymmetric stall, middle-of-fleet envelope | `42 / 180 / 127 m/s` |
| Aircraft_6 / Razorback | Very slow, rugged, stable low-level attacker | Strong rudder, strongest low-speed authority, latest and mildest stall, lowest Vne | `32 / 115 / 63 m/s` |
| Aircraft_7 / Dagger | High-speed interceptor that rewards energy rather than tight turning | Fleet-high sprint/Vne, late stiffening, high stall speed, abrupt `18.5-33 deg` departure | `50 / 205 / 160 m/s` |
| Aircraft_8 / Ghost | Smooth, efficient blended-wing strike fighter | Efficient sustained turns, responsive pitch, slower roll/yaw, comparatively gentle stall | `40 / 195 / 145 m/s` |
| Aircraft_14 / KAW FX-5 Spitewing | BD-5-inspired ultra-compact point-defense interceptor: exceptional climb, fast roll, and notoriously twitchy controls with almost no stall margin | Fleet-fastest surfaces, lowest damping, early `16-29 deg` stall, strongest wing drop/autorotation | `37 / 165 / 134 m/s` |

Existing aircraft retain their former Simplified elevator power through `simplified_pitch_power_override`; the expanded envelopes are Advanced-specific except for already-shared scene traits such as mass, stall speed, roll/yaw power, damping, stability, and straight-line performance. `FixedWingFleetHandlingSmoketest` locks the authored profiles, verifies every scene and production AI pilot load, checks clean-speed headroom above stall, rejects duplicate handling signatures, and guards the principal role relationships. `TurnGym --fleet-smoke` additionally flies all nine airframes through the production coordinated-turn controller at role-appropriate entry speeds.

The main-menu Technical Index is the pilot-facing source for this information. Every fixed-wing entry includes its operational role and concise flight notes, then derives mass, estimated clean speed, clean/flap stall speeds, stiffening onset/Vne, pitch-roll-yaw power, surface rates, stall-AoA range, and model lift limit directly from the selected gameplay scene. Numeric changes therefore appear in the index without maintaining a second copied data table. Estimated clean speed is the same unloaded zero-AoA force-balance approximation used here; it is not a guaranteed combat or loaded speed.

The deterministic fleet run completed all nine six-second, 45-degree-bank trials as valid, with no stalls and no control saturation. The deliberately slow-control Aircraft_2, Aircraft_4, and Aircraft_6 had `8.84`, `13.84`, and `10.53 deg` bank-error RMS, while the lighter Sand Sprite, Wasp, Kestrel, and Spitewing were at `1.70`, `1.21`, `2.56`, and `0.75 deg`. Aircraft_14 also had the highest turn effectiveness (`0.71` versus Aircraft_5's `0.31`), demonstrating the intended large response difference without a departure in that moderate turn. In its dedicated deep-stall runtime, Aircraft_14 reached full departure and approximately `1.79 / 0.38 / 0.89 rad/s` peak local pitch/yaw/roll rate, then returned to zero departure and `0.35` pitch authority as airflow rebuilt; Aircraft_5's comparison case reached `0.76` departure, `0.59 / 0.07 / 0.16 rad/s`, and full recovered pitch authority. These are deliberately strong calibration differences, not proof that the Spitewing's current break is final. Rendered player flights remain the acceptance test for feel. The fleet assertions and JSON result currently complete before a process-shutdown RID/resource leak makes the TurnGym executable return exit code `1`; the focused profile, stall, control-envelope, yaw, and Technical Index tests exit cleanly apart from their existing non-fatal teardown warnings.

Advanced directional stability is separate from the existing flight-path alignment force. Alignment is applied through the center of mass and removes lateral velocity, so it cannot physically turn the nose into the relative wind. `directional_stability_strength` instead applies a passive yaw moment proportional to signed sideslip, with yaw-rate damping, a forward-airflow blend, a per-mass torque cap, and the same deep-departure fade used by attitude stability. It does not write a rudder command and therefore still works when gameplay rudder assist is disabled. Every fixed-wing airframe now authors this value: the lively Wasp is weakest at `1.5`, the balanced Kestrel uses `2.4`, stable attack aircraft use stronger values, and Aircraft_14 keeps `4.0` with the fleet-highest `1.25` torque-per-kilogram cap. In an isolated 82 m/s A/B run with rudder and central alignment disabled, the Spitewing reduced a 13.7-degree sideslip to 6.25 degrees in 2.5 seconds, versus 13.93 degrees without the moment, while producing no yaw reversals. With the corrected Advanced rudder assist also active at 170 m/s, it reduced 7.1 percent sideslip to about 0.3 percent in four seconds with no command or surface reversals. These are bounded headless regressions, not final feel targets.

### Fixed-wing stall departure

The Kestrel reference stall begins at 20 degrees and reaches full severity at 38 degrees. At the full AoA stall, lift can fall by 65 percent; the low-speed stall can remove a further 45 percent. Other airframes override the AoA window, lift ceiling/loss, buffet, and departure moments: the Razorback has a broad `24-46 deg` progression and mild wing drop, while the Dagger and Spitewing have narrow, early breaks. Incipient-stall control loss remains axis-specific, but an established stall adds a separate nonlinear separation envelope. The baseline starts blending in at `0.12` combined stall/departure severity and is complete at `0.50`, where pitch, roll, and yaw authority are capped at 12, 5, and 20 percent respectively. Aircraft_14 separates earlier and retains only 10, 3, and 18 percent. Rudder remains the strongest recovery control, but no surface can fly the aircraft out of a fully separated state by itself.

The normal arcade control-flow calculation lets some total airspeed count while slipping, which keeps ordinary manoeuvring loose and controllable. That contribution fades with the separation envelope and reaches zero in a deep stall, so sideways or vertical motion no longer masquerades as useful airflow over the controls. Surface positions still follow the stick, but their aerodynamic torque becomes weak. As the automatic nose break reduces AoA, forward speed returns, and departure severity recovers, the caps release without a separate delay. The focused Aircraft_5 runtime stall reached exactly `0.12 / 0.05 / 0.20` pitch/roll/yaw authority at peak departure and returned to full pitch authority after recovery.

Departure severity builds and recovers progressively rather than switching at one threshold. Once established, it adds a local-axis nose-down break, chooses and holds one wing-drop direction for that departure, and adds yaw autorotation. Alignment, attitude stability, and angular damping fade with severity so they do not immediately erase the departure; separate entry and exit thresholds prevent threshold chatter. Releasing the pull and reducing AoA lets the model rebuild lift and damping. The focused Aircraft_5 runtime test reached `0.76` departure severity, approximately `0.59 / 0.06 / 0.16 rad/s` peak local pitch/yaw/roll rate, and returned to zero departure after the held pitch input was released. Those figures demonstrate that the behavior exists and recovers in headless physics; they do not establish that every aircraft's rendered stall feels right.

Advanced departure drag no longer treats rapid body rotation as proof of aerodynamic wing load. The marked `L3_003` tumble had only about `95 N` of lift but generated roughly `16.7 kN` of rotation-derived induced drag, creating an artificial `10-11 m/s` parachute descent. Advanced now fades the body-rate proxy to zero with departure severity and replaces it with an explicit `7.0 * departure^2 * speed^2` bluff-body term. The focused runtime stall produced about `14.5 kN` of this bounded drag. A seven-second recreation of the marked −10.74 m/s state accelerated to a late average sink of `48.7 m/s` rather than returning to the false slow equilibrium. That is a regression result, not proof that the final spin descent rate feels correct in a rendered flight.

In Advanced, the player-only `AirflowFeedback` layer now separates three cues: continuous speed-scaled cockpit wind, a maneuver-drag rush, and stall/departure buffet. The maneuver layer is driven by actual excess drag per unit mass—lateral, induced, high-AoA, and developed-departure drag—rather than stick position, so a clean high-speed pass sounds different from an energy-bleeding pull or skid. It fades in around `0.6 m/s2` of excess drag and reaches full intensity around `8.0 m/s2`. The same signal adds a restrained cockpit tremor and weak-motor controller hum; wing separation raises the sharper buffet and strong motor, with an irregular beat in a developed departure. These non-spatial pilot cues use the same unfiltered route as the cockpit-native loop: sending them through the `Interior` bus would apply the exterior-source 1000/550 Hz low-pass chain and make the air rush nearly disappear from inside the aircraft. Simplified retains the earlier stall/sideslip buffet but does not add the Advanced speed or maneuver-drag layers. Runtime cost is a fixed amount of scalar math per active fixed-wing physics tick; the three audio players and their shared streams are created lazily only when an aircraft becomes player-controlled, so AI fleet size does not multiply audio-player overhead. These are sensory cues only: they do not add forces, structural damage, or a hidden handling penalty.

### Player flight recorder

`SimpleAero` automatically records only the aircraft currently under direct player control. It samples at 10 Hz and batches rows into one-second writes so logging does not introduce a per-sample file-open hitch. Each row includes the selected flight model; session and physics-frame identity; position, attitude, local velocity and acceleration; lateral/normal/longitudinal G; speed and specific-energy rates; raw, shaped, assisted, and actual surface controls; rudder-assist internals; lift, thrust, total and departure drag, and alignment forces; stall/departure state; angular rates; landing configuration; health; and control-ownership flags.

Press the left stick (`L3`) while directly controlling a fixed-wing aircraft to add a numbered marker such as `L3_001`. The dedicated `flight_log_mark` input action is bound to `JOY_BUTTON_LEFT_STICK`; R3 remains the existing zoom control. A press forces an immediate row, flushes it to disk, and prints the marker plus aircraft, speed, AoA, and departure severity to the terminal. Holding L3 produces one marker; release and press again for the next.

For a preserved diagnostic run, launch from PowerShell and exit the game when finished:

```powershell
.\tools\run_logged_play_session.ps1
```

Use `-GpuProfile` only for a short GPU-specific diagnostic. Godot emits a report every rendered frame in that mode, so it can create console-I/O overhead and confound a long hitch capture.

The live CSV is written to `user://airplane_aero_report.log` and mirrored to `airplane_aero_report.log` in the project. The launcher copies the fresh telemetry and performance logs to `%APPDATA%\Godot\app_userdata\Land Carrier\perf_play_sessions\<timestamp>` so Godot's editor does not continuously import capture CSV files. `captures/perf_play_sessions/active_session.txt` remains as a lightweight pointer to the active or most recently completed external session. If L3 markers exist, the session also contains `player_flight_marks.csv` with just those rows and records the marker count in `session.txt`. At roughly 600-900 bytes per row, 10 Hz produces about 0.35-0.55 MB per minute per copy. One-second buffering reduces normal recorder file opens from approximately 20 per second to two per second across the user and project copies; a marker deliberately forces an extra flush.

The post-`6.25` deterministic Aircraft_5 `TurnGym` run completed all four 65-105 m/s AI cases. It held the commanded 72-degree bank to about 3.6 degrees RMS, recorded no stalls, and finished with 85-95 percent of entry speed. Turn effectiveness remained about 41-43 percent and load error was 1.4-1.8 g RMS, so the player-authority reduction did not materially destabilize the AI but its coordinated-turn controller still underuses the available airframe. A rendered player turn remains the deciding acceptance check for feel.

### Local launch

Portable Godot on the current development machine:

```powershell
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --path "C:\Godot projects\Project-Flight"
```

The industrial operator-console starting menu keeps the player-facing choices to New Campaign, Continue, Skirmish, Technical Index, Settings, and Quit. Debug builds group Free Flight, Landing Test, and Carrier Combat Test under a single Development Scenarios entry. The pause menu exposes a gated Save Campaign action and explains which strategic condition is still unsafe. The main, pause, settings, audio, gameplay, graphics, and controls screens share the same left-rail layout, typography, amber focus treatment, and dark console surfaces. The Settings hub separates Audio, Graphics, and Gameplay and provides a global reset. Audio persists master/radio volume and radio-caption visibility/duration. Graphics persists V-sync, display mode, resolution, frame limit, anti-aliasing, render scale/upscaling, view distance, and the FPS display; MSAA 2x is the default anti-aliasing mode. Gameplay persists rudder assists, stick deadzone, optional left-stick menu-pointer steering, look sensitivity/inversion, cockpit motion, and camera FOV.

The starting menu also selects carrier identity, livery, insignia, and map profile. Behind the operator rail, a five-shot carrier sequence cuts every 10.5 seconds between a tightened aerial quarter, a moving overhead orbit, fixed hilltop and ground-level viewpoints, and a long-lens broadside. The same `Camera3D` is reused for every composition, and fixed terrain viewpoints remain planted while the carrier moves through the scene. Its Technical Index automatically displays the first entry in each equipment class on a black, green-grid inspection display. The model stays planted on the grid while mouse drag or press-and-hold directional controls orbit the camera; holding the adjacent `-` / `+` controls changes zoom continuously. It covers the primary gameplay vehicles, structures, and weapon assemblies while intentionally omitting helper scenes, projectiles, templates, and destroyed variants. `M` opens the tactical carrier console. See the [controller guide](docs/CONTROLLER_GUIDE.md) for the broader input map, but treat its dated debug-key notes as needing live verification.

### Focused smoke tests

Prefer a focused headless test for the subsystem being changed. Examples:

```powershell
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/LayeredMapProfileSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/MapFogMovingAircraftSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/POIWreckedScoutCarSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/WorldMapZoomSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/LaunchTerrainRepositionSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://tools/carrier_console_smoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/TechnicalIndexSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/SettingsOptionsSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/FixedWingDragSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingDragRuntimeSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingControlEnvelopeSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingInputResponseSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/Aircraft5ControlAuthorityInvestigation.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingYawAssistSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingYawAssistRuntimeSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWing14YawAssistRuntimeSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/FixedWingFleetHandlingSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/FixedWingDirectionalStabilitySmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingDirectionalStabilityRuntimeSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingStallDepartureSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingStallRuntimeSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWing14StallRuntimeSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FixedWingFlatSpinRegressionSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/FlightModelModeSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/PlayerFlightRecorderSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Scenario/TurnGym.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Scenario/TurnGym.tscn -- --fleet-smoke
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/StartupCameraSequenceSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . res://Tests/NoMissileLoadoutSmoketest.tscn
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --scene res://Tests/SaveStateSmoketest.tscn -- --disable-campaign-autosave --test-scenario=0
```

Relevant focused coverage also exists for layered navigation, map startup, loading text, mobility textures, ground initial placement, AirOps scramble reservation, carrier deck passengers, floating-origin rigid bodies, rock streaming, landing gear, aircraft activity budgets, ground combat, dogfighting, and carrier recovery.

Tests prove the named subsystem contract, not overall scenario balance. For live telemetry, verify that the process, scenario marker, log timestamp, and terminal line all belong to the run being assessed.

### Engineering rules

- Build contained playable slices before expanding adjacent simulation.
- Measure a performance or AI problem before tuning it.
- Keep routine behavior autonomous and expose player intent through shared orders.
- Enforce exploration limits at the player command boundary, not inside global navigation.
- Prefer geometry, measured state, and feedback gains over arbitrary hard input ceilings.
- Preserve test logs and distinguish historical evidence from current-revision results.
- Keep originals for source assets; create trimmed/import-ready derivatives rather than overwriting them.

## Documentation map

| Document | Role | Status |
|---|---|---|
| This README | Canonical project description, goals, current state, roadmap, and known problems | Current |
| [Land Carrier Changelog](docs/Land%20Carrier%20Changelog.md) | Dated implementation history and archived session notes | Historical reference |
| [Controller Guide](docs/CONTROLLER_GUIDE.md) | Player and debug control reference | Useful, but last full audit is old |
| [Carrier Recovery Investigation](LANDING_RECOVERY_PROBLEM_REPORT_2026-07-31.md) | Evidence, architecture, acceptance criteria, and August implementation update | Partly superseded; validation incomplete |
| [Turn Authority Investigation](docs/Turn%20Authority%20Investigation.md) | Historical fixed-wing lift/turn telemetry and unresolved questions | Needs current retest |
| [AI Ground-Attack Handoff](docs/AI%20Pilot%20Ground%20Attack%20Handoff%202026-07-27.md) | Dated route-guidance handoff and test baseline | Historical handoff |
| [Track Mapping Problem](docs/Land%20Carrier%20Track%20Mapping%20Problem.md) | Detailed carrier-tread continuity investigation | Unresolved |
| [Bridge Jitter Problem](docs/Land%20Carrier%20Bridge%20Jitter%20Problem.md) | Diagnosis and resolution record | Resolved historical report |
| [Helicopter Attack Rewrite Plan](.attack_rewrite_plan.md) | Proposed contained helicopter attack rewrite | Proposal; verify against current code before use |
| [Turn Gym](Scenario/TURN_GYM.md) and [Gunnery Gym](Scenario/GUNNERY_GYM.md) | Focused scenario instructions | Specialist test references |
| [Pilot Portrait Catalog](Images/Pilot%20Portraits/pilot_portrait_catalog.csv) | Portrait presentation and loose casting suggestions | Asset reference |

When implementation changes project truth, update this README in the same change. Put detailed chronology in the changelog and retain investigation reports when their evidence remains useful, with a clear status note when they are resolved or superseded.
