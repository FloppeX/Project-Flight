# Aircraft regional damage

Implemented for fixed-wing aircraft 1–8, 14 and 16. Helicopters retain their existing damage behavior.

## Regions and consequences

Each region has its own health, currently half the aircraft's legacy total health. Effects are calculated from the remaining fraction against the original aircraft tuning, so repeated hits and save restoration do not compound multipliers accidentally.

| Region | Partial damage | Destruction |
| --- | --- | --- |
| Left/right wing | Less aileron authority, asymmetric lift, reduced flap benefit, extra drag. Wing stores stop firing below 25% health. | Authored break sections detach with their stores; catastrophic loss of flight control and bounded tumble. Aircraft 3 retains its authored inner wings. |
| Tail | Reduced elevator and rudder authority. | Capped rear fuselage and surviving tail surfaces leave as one physical assembly. All three control axes and passive alignment stop. Pitch rate builds about local X toward 120 degrees/second at flight speed. |
| Engine | Reduced thrust and smoke below 90% health. | Engine stops and cannot restart. The remaining aircraft can glide. Aircraft 2's rear engine/propeller also fails and leaves with its tail. |
| Cockpit | HUD outages below 75%; pilot injury below 35% reduces control authority by 15%. | Pilot death and disabled ejection. An already ejected pilot is protected. |
| Fuselage | Drag increases; fuel leaks below 50%; gear jams below 25%. | Existing critical-damage/fire/destruction sequence. |

The former horizontal/vertical stabilizer identifiers remain readable for older saved states and geometry checks. Projectile hits on either surface now spend the shared tail health. Losing both legacy surfaces also destroys the tail. The original per-part scene hierarchy, materials, insignia and folding pivots are retained.

AI retains its delayed automatic ejection for catastrophic wing/tail failure. Player ejection remains manual.

Engine smoke and the fixed-wing smoke/fire puffs originate at the propeller's fuselage or nacelle mount. The Engine module derives this from the authored propeller pivot and spin axis, inset 0.35 m into the mount (`damage_smoke_inset_m`). This handles nose, rear and elevated engine layouts without using the damage collider as a visual anchor. The point follows the aircraft but does not orbit with the blades. Regional smoke stops if Aircraft 2 loses its tail-mounted engine.

## Propeller strikes

All ten fixed-wing aircraft use a thin disc at the authored propeller mount. Its radius and thickness follow the shared blade geometry and each aircraft's mounting scale. The full disc detects physical bodies even when the engine is stopped or the model is visually culled; terrain, deck and other aircraft all count. The aircraft's own body and attached colliders are excluded. Translation is swept between physics frames, with rotation covered by short interpolated steps. World-origin shifts reset the sweep history.

A strike immediately shuts off thrust and engine audio, hides intact blades and blur, and leaves five uneven, capped blade stubs at roughly one-third length around the original hub. Ten loose blade fragments inherit the aircraft's movement and scatter, then expire after 12 seconds. Broken propellers cannot restart, and their state survives save/load without replaying fragments. The damage page reports **PROPELLER SHATTERED**. Propeller failure does not consume structural engine health or remove its body collider; subsequent engine and airframe impacts retain their normal regional handling. Helicopter rotors retain their existing behavior.

## Ground contact

Regular terrain uses impact speed into the surface instead of treating every contact as fatal. Wheel arrivals tolerate 6 m/s normal impact; belly arrivals tolerate 3 m/s. Excess impact damages each contacted region independently. Several contact points on one region count as one impact episode, while a simultaneous wheel/wing/tail strike can damage all three. Angular motion contributes to impact speed at the contact point.

Wheel impacts above 9 m/s shear the gear off into physical debris and disable wheel support, allowing the remaining airframe to belly slide. This currently fails the gear as a set, rather than tracking separate health for each leg. It covers fixed gear and independently animated rigs. Sheared gear remains absent after save/load, without replaying debris.

Sliding friction slows the aircraft. Body contact also damps rotation: strong resistance to spinning across the ground, with lighter resistance to impact-induced tipping and rolling. The flight model recognizes belly support and stops applying airborne stall/departure, alignment and self-leveling forces during the skid. This contact damping is applied only while supported, so airborne local-X tail tumbling resumes if support is lost. Sustained scraping wears only the regions touching the ground, with wings and tail wearing faster than the body. A wing or tail can tear away while the fuselage and cockpit survive; appendage impacts do not automatically explode the whole plane or kill its pilot. Severe body impacts (24 m/s or more), destroyed fuselage, or destroyed cockpit can still be fatal.

Dirt contact produces terrain-colored dust: broad, dense plumes at scraping body/wing/tail points and smaller trails at loaded wheels. The effect uses real collision and suspension contacts, stops emitting below 2 m/s or after liftoff, and lets existing puffs dissipate. Carrier/runway contact does not emit dirt dust. Each aircraft reuses a capped puff pool with the existing distance/visibility budget and particle lifetime manager.

Fixed-wing aircraft have progressive wheel brakes on both controller triggers. Brake demand follows the lower trigger pressure, with a 5% deadzone; the trigger difference keeps the existing rudder/nose-wheel steering. Service braking is bounded by wheel load and tuned to at most 5 m/s² additional deceleration with all wheels loaded. Only deployed, intact, contacting wheels apply it, using deck-relative speed on carriers. Input expires when player controls stop, and carrier transport, catapult control and arrestment suppress it. This does not change belly-skid friction or helicopter skid controls.

Carrier and runway contact policies remain in their existing paths. Terrain streaming's deep-penetration guard remains active. This adds landing/contact behavior, not an AI off-field landing planner or wreck salvage system.

## Cockpit display

- **F10** opens DAMAGE on the left MFD in cockpit view. Ctrl+F10 retains its recording binding.
- **[ / ]** cycle the left MFD's pages.
- The existing cockpit interaction on **STRUCT** opens DAMAGE; the MFD itself also retains its existing page interaction.
- The six-area silhouette shows intact, damaged, critical and destroyed regions; additional warnings rotate in groups of three.
- STRUCT reports the weakest structural region. GEAR displays JAMMED or FAILED when applicable.

The display follows the aircraft currently bound to the pooled instrument panel.

## Mesh regeneration

The original source GLBs and editable Aircraft 16 `.blend` are preserved. Aircraft scenes reference generated `Models/Aircraft_N/aircraft_N_damage.glb` files. After editing a source asset, rebuild its damage derivative:

```powershell
& 'C:\Program Files\Blender 5.1\blender.exe' --background --factory-startup --python-exit-code 1 --python tools/build_aircraft_damage_meshes.py -- --aircraft 16
& 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --import --quit
```

Omit `-- --aircraft 16` to rebuild all ten. The builder preserves skin corner normals, joins cut-boundary seam vertices, adds fracture caps to both halves, and verifies external surface-area conservation. `tools/configure_aircraft_damage.py` records the scene bindings and collider locations. `tools/aircraft_damage_geometry_audit.gd` dumps current mesh bounds for inspection.

`tools/build_propeller_damage.py` derives `Models/Aircraft_1/propeller_shattered.glb` and the small `propeller_strike_geometry.gd` dimension resource from the shared original `aircraft 2 propeller.glb`. Run it with the same Blender command above, substituting the script and omitting the aircraft argument, then reimport. The source stays untouched; the builder checks five blades, closed fracture caps and valid output geometry.

## Verification and limits

- `RegionalAircraftDamageSmoketest.tscn`: ten airframes; partial effects, engine shutdown/restart prevention, actual stabilizer-hit routing, both fracture caps, saved tail failure without new debris, and bounded local-X tumble.
- `RegionalDamageSystemsSmoketest.tscn`: ten airframes; real fuel drainage, jam/collapse behavior, save restoration, disabled/lost stores, ejected-pilot protection, pooled cockpit page/input checks on 5 and 16.
- `RegionalGroundLandingSmoketest.tscn`: 22 contact cases across the ten airframes; gentle wheel/belly contact, slide deceleration, hard-landing gear collapse and a destructive impact. Aerodynamics are disabled in this contact fixture to isolate suspension and collision behavior.
- `RoughLandingDamageSmoketest.tscn`: physical gear debris and save/load across all ten airframes, simultaneous regional contacts, duplicate-contact protection and scraping wear. Three six-second physical cases check gear failure into a slowing belly slide and separate wing/tail ridge strikes with surviving pilots and airframes. Aerodynamics and AI ejection are disabled to isolate contact behavior; structural failure forces remain enabled. A rendered run saves the three outcomes in `captures/rough_landing/`.
- `AircraftGroundSkidSmoketest.tscn`: six twelve-second wheel/belly/tail-loss arrivals on Aircraft 5 and 16 with the advanced flight model active. Checks rotational settling after an imposed yaw/tipping impulse, sustained contact dust, stopping emission at rest/liftoff, hard-surface exclusion and bounded pooling. Rendered wheel and skid trails are saved in `captures/ground_skid/`. Earlier contact-only fixtures did not exercise the flight model's airborne stall classification during a skid.
- `TriggerWheelBrakeSmoketest.tscn`: input routing on ten fixed-wing airframes in both flight modes, helicopter exclusion, release/expiry, carrier-control suppression and stowed/sheared-gear gates. Six eight-second physical rollouts on 5 and 16 compare coasting, half and full brakes with advanced aerodynamics active; a paired taxi comparison checks both steering directions. Airborne twins check that held brakes add no force, and a moving-deck fixture checks stopping relative to the deck. The last two fixtures isolate wheel forces from aerodynamics and engine thrust.
- `EngineSmokeOriginSmoketest.tscn`: geometry-checked mount positions on all ten airframes, regional smoke and authored legacy smoke/fire paths, moved/rotated aircraft, rotating propellers, saved damage, restored healthy engine state and detached rear-engine suppression. `-- --render-smoke` saves Forward+ views of aircraft 2, 5, 6 and 16 to `captures/engine_smoke/`; these cover rear, elevated and nose engine placement.
- `PropellerDamageSmoketest.tscn`: ten airframes, blade stubs and fragments, immediate zero thrust, restart prevention, saved failure without repeated debris, intact structural engine support and helicopter exclusion. Physical disc queries cover terrain, deck, another authored aircraft, stopped/spinning blades, visual culling, fast traversal and world-origin shifts. `-- --render-propeller` saves inspected nose/pusher close-ups of aircraft 2, 5 and 16 to `captures/propeller_damage/`. These fixtures verify collision detection and state changes; landing feel still needs gameplay evaluation.
- Existing fixed-wing collider, folding breakaway, Aircraft 14 damage, control-surface checks (1/2/3/5), carrier contact (72 contacts), landing configuration, and flight-model-mode checks pass. Aircraft 16 runtime checks pass with headless renderer material diagnostics in its carrier-fit fixture.
- `RegionalDamageRenderedProbe.tscn`: inspected intact/detached views of all ten airframes and the actual cockpit panel render in `captures/regional_damage/`.

The older `FixedWingControlEnvelopeSmoketest` still fails its stall-floor/normal-speed assumptions. Its exercised authority functions are unchanged from HEAD; the current flight-model-mode test passes. This is not counted as a passing regression.

The pooled dust pass also fixes duplicate recording exit-hook connections when a puff is reused. `RecordingLifecycleSmoketest` passes. The broader `RecordingCombatSmoketest` invoked with `--script` reports `VelocityFrame` startup compilation errors and subsequent uninitialized regional-system errors despite printing PASS; that run is not counted as a clean pass. Sandboxed Godot runs also report an unrelated root-certificate-store read error.

Terrain fixtures do not establish handling quality on every slope, obstacle, wind condition or moving surface. Damage balance, the pilot-injury penalty, smoke appearance in combat and emergency landing feel still need gameplay evaluation.
