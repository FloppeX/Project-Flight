# Recovery spacing and loaded landing-gear visual audit

Diagnostic pass only: no production recovery rules, suspension values, airframe scenes or aerodynamics changed in this pass.

## Recovery: the current admission policy is too conservative for the requested risk preference

`FlightDeckManager.request_recovery_approach()` only admits its single prepared successor once the preceding aircraft is actually arrested or being stowed. Consequently, most of the next aircraft's approach cannot overlap its predecessor's airborne approach. `AIPilot` also requires exclusive, currently clear-deck landing clearance at the early final handoff and throughout LANDING.

Recent measured catch-to-stow intervals were approximately **41 seconds**, rather than 30. That is still much shorter than the 119–137-second intervals between successful catches. These figures are observations from the prior bingo runs, not a measured probability of deck collision.

Recommended next implementation:

1. Schedule **touchdown times**, rather than waiting for a free deck before admitting an approach. Initially test approximately 35–45-second touchdown spacing, including a deliberately aggressive 35-second candidate against the roughly 41-second measured stow time.
2. Allow the following aircraft to fly its downwind/turn/final setup while the leader is airborne. Account for actual distance, speed and path progress so a nearby follower does not overtake a distant leader.
3. Separate planned approach/final sequencing from actual deck obstruction. A predecessor currently on deck should not automatically cause a wave-off a kilometre away if it is expected to be clear before arrival. Re-evaluate close in against the physical touchdown/arrestment area, not a generic busy flag while a tractor operates elsewhere.
4. Keep outbound launch conflicts and genuinely unavoidable imminent collisions as exceptions. A bolter should leave the inbound stream rather than automatically cancelling everyone behind it.
5. Retest the same five-aircraft bingo scenario, reporting touchdown spacing, catch-to-clear time, actual collisions and fuel losses. The aim is better completed recoveries, not minimizing every possible collision at the cost of certain fuel starvation.

This is not yet implemented or validated. Simply opening all clearance gates would not provide useful traffic spacing; conversely, retaining the current early exclusive-clearance checks would negate more generous approach admission.

## Gear: reproduced visual separation, not reversed damping

Added `Tests/LandingGearVisualAudit.gd`. It measures actual authored visual mesh bounds separately from suspension compression/contact on a flat physical surface. It uses the normal loaded deck-placement helper, freezes the diagnostic body, then pushes the body down 10 cm and updates suspension/visuals. Engine, pilot and aerodynamic updates are disabled for this isolated measurement. This is not a whole-aircraft touchdown simulation.

| Aircraft | Loaded visual/contact finding |
| --- | --- |
| 1 | Loaded compression about 5 cm nose / 12.5 cm mains; visual tires slightly intersect the surface by about 9–11 mm, not floating. |
| 2 | Nose tire approximately **20.0 cm above** the surface; main tires approximately **23.0 cm above**, despite loaded spring contacts. The gaps persist after pushing the body down 10 cm. |
| 5 | Loaded compression about 2 cm nose / 14 cm mains; visual tire bounds within approximately 2 mm of the surface. Extra body depression compresses the lower assemblies without lifting the tires off the surface. |
| 9 | Four articulated wheel rigs track the surface in this frozen test, including additional body depression. |
| 10 | Suspension colliders move, but their visual slots are unmapped. The body's `Skids` mesh is approximately 6.9 cm above the surface in static stance, then approximately 3.1 cm below after a 10 cm body depression. It follows the body, not the contact. |
| 11 | Both suspension colliders have unmapped visual slots. No separately named skid/gear mesh was found by the focused name filter, so the precise visible support geometry still needs asset inspection. Do not assign it aircraft 10's measured gap. |

### Why aircraft 2 floats

- Its spring rest height is **0.5 m**, while the rigid wheel radius is **0.3 m**.
- The moving-collider calculation lifts a collider by measured compression plus a 2.5 cm skin (and additional transient sink allowance).
- The old nose/main visual gear assemblies are children of those colliders. They inherit the collider's whole-assembly movement and its clearance allowance.
- Body descent and collider/assembly retraction therefore approximately cancel, leaving the visible tire above the surface. The upper mount moves too; there is no separate fixed upper strut and moving lower strut on this old assembly.

Aircraft 5 instead uses separate telescoping rigs whose lower assemblies are aligned to measured contact while the upper mounts stay attached to the fuselage. Upward movement of a lower leg **relative to the fuselage** is correct compression; upward tire movement **relative to the supporting deck** is the fault to prevent.

Screenshots were generated and inspected for aircraft 2 and 5 using an external diagnostic camera. First capture attempts used an automatically selected cockpit camera; those were corrected and overwritten. Current images are `user://gear_audit_2_static_load.png`, `gear_audit_2_body_pushed_down_10cm.png`, and the corresponding model-5 images. Geometry measurements are the quantitative contact evidence; camera perspective alone is not a centimetre-accurate measurement.

### Damping findings

The damper uses wheel-point velocity relative to the contacted surface, including body angular velocity. Compression produces positive resisting force, rebound reduces that support force, and total normal force is clamped nonnegative. No reversed damping sign was found.

Runtime spring/damping values are automatically sized for mass/load; authored scene numbers are only floors. In the audit aircraft 2 used approximately 47.6 kN/m and 11.38 kN s/m, while aircraft 5 used approximately 46.2 kN/m and 11.05 kN s/m. Their current loaded stiffness is much closer than the authored 12,000 versus 30,000 values suggest.

The existing fleet suspension test passed **60 drop cases across 15 models**, and the dedicated aircraft-5 static-strut test passed. Passing these tests does not mean every landing is softly damped: the 4 m/s isolated drop rebounded at about 0.70 m/s for aircraft 2 and 1.56 m/s for aircraft 5; an 8 m/s drop rebounded at about 3.97 m/s for aircraft 5. Hard impacts can also involve rigid collider response. Rebound damping currently uses only 35% of compression damping, so a controlled rebound-damping comparison is worth doing after fixing visual attachment/contact. Do not assume that globally increasing compression damping fixes floating geometry.

## Recommended gear implementation order

1. Give aircraft 2 a fuselage-fixed upper assembly and separately moving lower/tire assembly, preserving its authored mounting and tire geometry. Do not use collision skin or predictive collider movement as visible compression.
2. Match suspension rest/contact geometry to the actual tires. Validate frozen deck placement and the handoff back to physics together, so correcting a cosmetic gap does not introduce a physical pop.
3. Wire helicopter skid/support visuals to their suspension with the appropriate flex/motion; inspect aircraft 11's combined asset first. Wheels and skids should not share an invented telescoping animation indiscriminately.
4. Compare rebound damping variants in controlled drops and rolling/arrested landings, measuring bounce, bottoming and tire/deck gap. Preserve visible static sag and player aerodynamics.

## Evidence and limitations

- Full visual measurements: `user://landing_gear_visual_audit_20260911.json` (six models); rendered measurements use the separate `_rendered.json` file.
- Fleet report: `user://fleet_suspension_current_1789135471.json`; log `gear_audit_fleet_20260911.log`.
- Static aircraft-5 test: `LANDING_GEAR_STRUT_SMOKE PASS`.
- Renderer/exit ObjectDB/resource warnings and unrelated tuner log-file contention warnings occurred in some diagnostic processes. No script parse/runtime errors were found in the completed audit logs.
- These are focused subsystem diagnostics. Carrier motion, banked touchdown, damage and arresting-cable loads need the follow-up integration tests; static contact success is not universal landing proof.
