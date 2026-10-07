# Helicopter damage

Aircraft 9, 10, 11, 12, 13 and 15 use `HelicopterDamageModel`, a rotorcraft subclass of the shared regional health/contact model. Fixed-wing failure forces are not used. Each region has half the aircraft's legacy maximum health, matching the existing regional damage convention.

| Region | Damage | Destruction |
| --- | --- | --- |
| Main rotor | Vibration, reduced lift and cyclic response. Below 55% health, damage worsens with rotor RPM and collective load. | Blades detach; lift and autorotation are lost. |
| Lower main rotor (9, 12) | Separate health; unequal rotor damage adds yaw imbalance. | Loss of either main rotor removes usable lift. |
| Tail rotor (10, 11, 13, 15) | Reduced yaw authority and increased powered yaw drift. | Powered spin around the main rotor axis. |
| Tail boom | Reduced fin stability. | Capped rear structure detaches. Conventional helicopters lose the tail rotor; coaxial helicopters retain 70% yaw authority and 25% yaw damping. |
| Engine | Reduced available drive and smoke from the engine region. | Drive stops and cannot restart. Collective remains controllable. |
| Cockpit | Instrument faults and pilot wounds. | Pilot death. |
| Fuselage | Extra drag, fuel leakage below 50%, gear jamming below 25%. | Existing critical-damage/destruction sequence. |

## Rotor hits

Main and tail rotors have cylinder-shaped strike discs. Physical contact with terrain, carrier geometry or aircraft bodies destroys the contacted rotor. Deployed rotors can be struck even when stopped; folded main rotors have no extended strike disc.

Bullet queries use separate Areas on physics layer 31. The hub is a solid target; the swept blade area has a per-projectile hit probability of 2.5% per blade (clamped to 4–18%). A miss excludes only that disc, so the same round can still hit the fuselage or another target behind it. Non-bullet projectiles use a solid disc. Rotor damage credits the owning aircraft.

## Rotor energy and autorotation

`HelicopterRotorEnergy` separates engine drive, collective and rotor RPM. Healthy powered flight retains the existing lift/handling balance at governed RPM. Shutdown and engine damage no longer remove rotor lift instantly. Descent with low collective sustains RPM; raising collective trades rotor energy for lift. Holding high collective exhausts that energy. Once RPM falls below the windmilling threshold, descent alone cannot restart the rotor.

The existing throttle/collective controls remain the controls: lower collective promptly after engine failure, retain RPM during descent, then raise it near the ground to flare. The engine instrument displays RPM and power; the DAMAGE page shows rotor regions, warnings and autorotation state. AI helicopters use the same rotor-energy model to unload and flare for an emergency landing.

Combat saves retain regional health, detached parts and rotor RPM/collective. Restoring does not replay debris. Already-airborne enemy spawns explicitly prime their rotor, then saved combat state takes precedence.

## Gear and skid breakaway

All six helicopters can lose their complete gear/skid set, using the fixed-wing terrain-impact thresholds: damage starts above 6 m/s into the contacted surface, and gear shears above 9 m/s. These are gameplay values rather than engineering limits. Forward speed alone does not break gear on a flat surface, but striking an edge uses the velocity into that edge. Moving-deck contacts use relative velocity.

Shearing releases the authored wheels, struts or skids as debris and disables both suspension contacts and rigid skid colliders. The helicopter can settle or slide on its belly, with further damage determined by the parts that actually hit or scrape. Gear loss does not itself kill the pilot or explode the helicopter. The current damage state is shared by the whole gear set, rather than tracking individual legs. Saves preserve the loss without replaying debris; the damage display warns `GEAR TORN OFF`.

Helicopter deck impacts use the regional contact episode handler, including belly sliding and angular damping. This prevents a rocking wreck taking a fresh minimum damage charge on every collision callback. Managed carrier transport remains excluded. Fixed-wing carrier collision handling remains unchanged.

## Meshes and verification

`tools/build_helicopter_damage_meshes.py` creates six damage GLBs from the authored source models. Original assets remain intact. The builder caps the separated sections and checks skin-area conservation; Aircraft 15 requires a planar cap across its source's open center seam. The existing authored tail-rotor blur discs supply the runtime strike plane and drive pivot.

Focused coverage is in `HelicopterDamageSmoketest` (all six regional models, sparse/solid hit routing, physical/swept rotor strikes, damage progression, capped tails and saves) and `HelicopterDamageFlightSmoketest` (healthy loaded hover, conventional/coaxial tail loss, level-ground autorotation and rotor exhaustion). `HelicopterDamagePreview` renders intact/detached variants with the actual damage diagram to `captures/helicopter_damage/`.

`HelicopterGearDamageSmoketest` checks detachable visuals, all disabled gear/skid colliders, save/load and repeat-detachment behavior across the fleet. Its 24 physical landings cover gentle and heavy drops onto terrain and a deck moving at 8 m/s; two additional gear/skid impacts strike a deck edge horizontally. Run the same scene command below with `HelicopterGearDamageSmoketest.tscn`. Run `HelicopterDamagePreview.tscn` with rendering enabled and `-- --gear` for gear breakaway previews. Aircraft 11's skids are separated from the existing fuselage mesh in the generated damage GLB; their surface geometry and the original asset are preserved.

`HelicopterDamageEnvelopeSmoketest` runs the normal AI physics loop without player input. Its 36 engine-failure cases cover all six helicopters in these entry conditions:

| Scenario | Conditions |
| --- | --- |
| Low altitude | 12 m above level ground |
| Forward flight | 60 m altitude, 20 m/s forward speed |
| Bank and drift | 60 m altitude, 12-degree bank, 6 m/s sideways speed |
| Slope | 60 m altitude, 6-degree ground slope |
| Gusts | 60 m altitude, 10 m/s crosswind plus gusts and turbulence |
| Moving deck | 60 m altitude, helicopter and deck initially moving at 8 m/s |

The test destroys the engine, retains full initial rotor RPM, and checks entry velocity, touchdown sink speed below 6 m/s, pilot survival and sustained settling. It records trajectory, rotor RPM, collective, contact counts and final damage in `logs/helicopter_damage_envelope.json`. The deck is a moving collision fixture; carrier approach selection, turns, obstacles and hangar recovery require separate integration coverage. These cases establish a tested autorotation window, not guaranteed survival at every height, speed, loading, slope or attitude. Controller feel remains a playtesting judgment.

Run from the project directory with the installed Godot executable (the tests provide their own timeout and nonzero failure exit):

```powershell
& 'C:/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://Tests/HelicopterDamageEnvelopeSmoketest.tscn --log-file logs/helicopter_damage_envelope.log
```

Append `-- --profile=moving_deck` to isolate one scenario. The component and baseline flight suites use the same command with `HelicopterDamageSmoketest.tscn` and `HelicopterDamageFlightSmoketest.tscn`, respectively.

The envelope tests exposed and guard against three touchdown defects: missing pitch/roll damping after the rotor stops, emergency guidance braking toward world zero over a moving deck, and first-contact gear braking before a carrier motion reference exists. Ground support now retains fuselage damping, and both guidance and gear friction use the contacted carrier's velocity.
