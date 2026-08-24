# Land Carrier

Land Carrier is a single-player strategic action game about commanding a massive tracked aircraft carrier across a hostile low-poly desert. It combines carrier operations, direct vehicle control, autonomous AI crews, tactical command, exploration, and combined-arms combat.

This README is the canonical living project document. It describes the current game, design goals, implemented systems, recent work, near-term plan, and known problems. Detailed development history belongs in the [changelog](docs/Land%20Carrier%20Changelog.md); dated investigations are evidence, not automatically current truth.

**Project state:** playable systems sandbox; not yet a complete campaign

**Engine:** Godot 4.6.2

**Main scene:** `res://UI/MainMenu.tscn`

**Status reviewed:** 2026-08-22 against the current source tree

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
| Strategic map | `50 km x 50 km` navigation and tactical-map coverage, relief shading, mobility overlays, routes, contacts, mission drafting, and loading progress | The map is a command surface, but it does not yet express a regional objective or economy |
| Exploration | Persistent fog of war: carrier, aircraft, helicopters, and ground vehicles permanently reveal terrain as they travel | Exploration persists through strategic checkpoint saves, but not yet between regions |
| Carrier movement | Player-authored routes over carrier-legal terrain; no automatic route is assigned at scenario start | The carrier cannot be ordered into unexplored terrain |
| Carrier deck | Hangar, elevator, tractor bots, catapult launch, deck staging, landing clearance, arresting wires, and recovery flow | Full mission-to-recovery reliability is promising but not yet accepted across the complete validation suite |
| Air operations | Four named flights, sensor-fused tasking, CAP/intercept/strike roles, autonomous downed-pilot tracking and Aircraft_11 rescue dispatch, player orders, threat-driven scrambling, and direct flight control | Standing CAP no longer auto-launches at startup; the rescue path still needs full live scenario validation, and richer player doctrine and mission editing remain planned |
| Ground operations | Four named platoons, vehicle-bay deployment/retrieval, formations, escort, move, attack, protect, hold, and map-issued orders | Player ground destinations must already be explored; pathing and steep-terrain behavior still need broad live testing |
| Combat | Fixed-wing, helicopter, vehicle, turret, rocket, bomb, gun, damage, destruction, and ejection systems | Balance and some AI flight-path integration remain under investigation |
| Enemy operations | Bases, patrols, ground forces, emplacements, wind farms, virtualized distant units, and replenishment behavior | Destroying infrastructure does not yet remove a clearly communicated enemy capability |
| POIs | Procedural POI placement, starting discoveries, aircraft discovery, ground reveal, tactical markers, and choice cards | POI choices currently close the card but do not change game state |
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

### August 2026 - strategic checkpoints

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
- Give at least one POI a real consequence: supplies, intelligence, a rescue opportunity, route access, or a difficult trade-off.
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
| Confirmed | POI decisions have no gameplay effect | `POIManager` records reveal state, but confirming a card currently only closes it |
| Confirmed | No regional win condition, strategic economy, or between-region persistence | A first same-region calm-state checkpoint exists, but the larger campaign transition and economy systems have not been implemented |
| Confirmed | Carrier tread animation has visible discontinuities at the lower turnarounds | Debug the baked loop coordinate before further shader tuning; see the track report |
| Partly resolved | Fixed-wing carrier recovery | Focused dirty-entry and two-aircraft catches succeeded on the current recovery work, but the remaining matrix, 100-attempt final regression, and 20-run mixed suite were not completed |
| Unresolved / needs current retest | Fixed-wing route and turn authority | Historical telemetry found a split between horizontal and vertical guidance and uncertain lift response; later code changed substantially, so the old diagnosis is a baseline rather than proof of the current failure |
| Needs current measurement | Valley-frame performance | Low frame rates were observed in valleys; terrain/rock streaming and presentation budgets were changed afterward, but no current acceptance measurement is documented here |
| Needs current retest | Carrier/free-camera 3D audio | The last written investigation from April ended with inconsistent or missing carrier sound; its present state has not been re-verified during this documentation pass |
| Investigate | 3D texture mipmaps and insignia residency | Enable mipmaps selectively for distance-viewed 3D textures such as tracks, scorch marks, and insignia decals, but first lazy-load or size-limit the 102 insignia images instead of keeping the whole catalog resident |
| Watch item | Terrain and streamed clutter edge cases | Floating rocks, cliff-edge clearance, delayed chunks/collision, and startup preprocessing should remain in live-test coverage |
| Resolved | Bridge/commander micro-jitter | Moving the world origin and fixing mixed process/physics camera updates resolved the documented issue; keep the report as historical evidence |

## Development and verification

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
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://tools/carrier_console_smoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/TechnicalIndexSmoketest.gd
& "C:\Godot\Godot_v4.6.2-stable_win64_console.exe" --headless --path . --script res://Tests/SettingsOptionsSmoketest.gd
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
