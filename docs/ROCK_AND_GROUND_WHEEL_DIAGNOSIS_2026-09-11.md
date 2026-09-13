# Rock streaming and ground-vehicle wheel audit — 2026-09-11

Follow-up: [implemented fixes and verification](ROCK_AND_WHEEL_IMPLEMENTATION_2026-09-11.md).

Scope: investigation and diagnostic fixtures only. No production behavior or
visibility distances changed in this pass. Aircraft/helicopter landing gear uses
a separate system; the wheel findings below concern the five ground-vehicle scenes.

## Rock streaming

The preceding rendered scenario measured 101.970 ms in `RockStream.rebuild` inside
a 130.770 ms frame. The new isolated probe uses the same rock settings and terrain
profile/seed parameters, but does not generate terrain collision chunks. Its ray
queries therefore miss: these are CPU scaling measurements, not replacements for
the real-scenario collision/render evidence.

| Operation | Candidate cells evaluated | Cached cells reused | Total CPU |
|---|---:|---:|---:|
| Cold 500 m-radius footprint | 1264 | 0 | 62.061 ms |
| Move 50 m | 80 | 1184 | 4.431 ms |
| Transfer 8 km / 4 km | 1264 | 0 | 62.709 ms |
| Same location after origin shift | 1265 | 0 | 66.714 ms |

Candidate evaluation accounts for 60–65 ms of the full rebuilds. Its nested
support checks account for 32–35 ms; ray-query calls take about 1 ms in the empty
physics world. The rest, including enumeration and MultiMesh replacement, is
roughly 1–2 ms. Optimizing MultiMesh upload alone would miss the dominant CPU cost.

Each candidate performs five procedural height queries before the density test;
accepted candidates can perform another sixteen support queries (two rings of
eight directions), then a collision-surface query. Normal incremental caching
works. The expensive discontinuities are new areas and discarded caches.

`apply_origin_shift()` clears the cache, and both cell coordinates and placement
noise use the shifted world frame. In the same-place translation probe, **none
of the previous 592 rock positions matched the rebuilt set** (1 cm tolerance).
Thus origin shifts can cause visible redistribution, not just wasted work.

Additional source findings:

- A footprint containing zero rocks still enters the rebuild path every frame
  because the no-movement early return requires `instance_count > 0`. Negative
  caching avoids candidate resampling, but not footprint enumeration/repacking.
- A miss in collision snapping is cached using procedural height, with no later
  chunk-ready correction. The source explicitly notes procedural height and the
  final postprocessed collision surface may differ.
- `_load_mesh_from_scene()` instantiates the rock scene to find its mesh without
  freeing the temporary node hierarchy. This is a resource-lifetime defect worth
  correcting, but not proof that it causes the full-scenario shutdown crash.

### Recommended first implementation

1. Anchor cell keys, random seeds and placement noise in a stable terrain frame;
   retain local transforms and cached empty cells across floating-origin shifts.
2. Queue missing cells and process near-visible work first under a roughly 2 ms
   soft frame budget. Reuse existing rocks while gradually filling new regions;
   bound outstanding work and cancel obsolete requests on retarget/rebake.
3. Separate candidate acceptance from collision finalization. Retry unresolved
   terrain contacts when the relevant chunk becomes available. Avoid treating a
   temporary collision miss as a permanent final placement.
4. Retain/update a bounded MultiMesh buffer, handle completed empty footprints,
   and free the temporary import instance.

Expected effect: remove the demonstrated 60–100 ms monolithic population work
from one frame without reducing density or terrain-support checks. A 60 ms cold
population spread over 2 ms slices needs approximately 30 frames (0.5 s at 60 Hz),
plus overhead. This trades incremental appearance for a shorter frame stall;
it is a target budget, not a measured post-fix guarantee.

## Ground-wheel correctness

Both `vehicle_enemy_light.gd` and `vehicle_friendly_light.gd` duplicate the same
support algorithm. Four corner rays choose chassis height/pitch/roll, then each
wheel gets a separate ray. Detailed sampling runs every second simulation tick.

Confirmed by the source and focused flat-collision-floor probes:

- **Contact coordinates ignore the wheel basis.** Initialization adds the wheel
  and marker positions rather than composing their transforms. The enemy buggy's
  cached contact differs from its authored marker by up to 0.492 m; pickup and
  battle bus errors are 0.008 and 0.040 m. Mirrored/rotated mounts matter.
- **Steering overwrites authored mounting yaw.** The buggy, pickup and battle bus
  right-front wheels begin near 180 degrees, but a straight-ahead drive command
  replaces this with zero. Steering should be relative to the authored basis.
- **Ray direction and wheel travel axis differ.** Rays go down in world Y, but
  the result is applied only to local wheel Y. In a deliberately tilted 30-degree
  chassis over a flat floor, applying the computed targets still leaves up to
  0.51–0.67 m contact-height error. This is a geometry stress test, not a claim
  about the steady-state error of a normally settled vehicle.
- **There is no suspension-travel clamp.** That stress fixture requested roughly
  1.7–2.3 m wheel travel. Chassis movement and stale local target values can make
  wheel repositioning excessive during support/detail transitions.
- **Distant support discards terrain tilt.** Beyond detailed range the chassis
  is explicitly levelled and wheels return toward nominal positions. The fallback
  is a single sample from the 40 m navigation grid, not the actual nearby collision
  surface. This is especially weak for a 3–9 m vehicle on broken terrain.

There is also an old unreachable copy of the solver after an unconditional return
in both scripts. Remove it during consolidation, but it is not being executed
twice and deleting it alone does not save the claimed raycasts.

## Wheel calculation cost versus visibility

Meshes are culled at **450 m**, while detailed suspension is allowed to **800 m**.
Visible vehicles continue at full simulation rate even in that hidden-wheel band.
Target-camera focus requests higher detail, but the wheel's hard visibility range
is applied separately; a narrow-FOV zoom still needs a policy based on projected
size/focus rather than a simple world-distance cut.

On the isolated flat floor, 600 consecutive direct support updates averaged
14.6–18.7 microseconds per vehicle at 600 m, versus 5.1–6.3 microseconds for the
900 m coarse path. A detailed probe refresh alone averaged 15.9–23.7 microseconds.
These are **small per-vehicle CPU costs in this fixture**. At thirty visible
vehicles they scale to roughly 0.44–0.56 ms per tick, not a demonstrated giant
frame stall. Busy-world raycasts, terrain boundaries and rendering need separate
measurement; do not blame every slowdown on wheel-position math.

### Recommended wheel implementation

1. Share one support/contact component between friendly and enemy ground vehicles.
   Cache proper rest transforms, steer relative to the mount, and derive current
   contact locations without feeding the animated suspension position back into
   the rest pose. Clamp travel and explicitly handle lost support.
2. Use one set of wheel support hits for both chassis support and wheel travel.
   Intersect along the suspension axis, or solve its intersection with the hit
   surface plane; handle near-parallel/invalid support safely. Moving decks and
   ramps must retain real physics queries.
3. Decouple drawing from detailed suspension. Keep a cheap wheel silhouette at
   distance; use a slowly refreshed support plane and interpolate between samples.
   Keep full-rate integration with lower-rate, staggered queries near the player;
   selected/zoomed targets and deployment/retrieval get accurate support.
4. Validate flat terrain, slopes, steps, unloaded terrain, ramp/deck transitions,
   mirrored mounts, steering and detail transitions. Then measure 30–60 vehicles
   in a real populated scenario.

Reusing contacts could reduce each refresh from 8 to 4 rays on four-wheel vehicles
and from 10 to 6 on six-wheel vehicles: **40–50% fewer support rays**, not a promised
40–50% whole-frame improvement. Preserve the vehicle silhouette independently of
that CPU optimization; imported wheels have 12–18 material surfaces per vehicle,
so simply disabling culling also has a draw-submission cost.

### Rendered wheel-only A/B result

Completed Forward+ / Vulkan run on RX 7800 XT, V-sync and frame cap disabled,
1280x720 window (native captured images 1920x1080). Thirty stationary vehicles
are arranged at roughly 300–1100 m. Imported mesh LOD and shadow distance policy
remain enabled. ABBA order used two three-second samples for each wheel policy,
with 1.5 seconds warmup before each sample. The averages of those paired runs are:

| Wheel policy | Mean frame | Mean render CPU | Mean GPU | Draw calls |
|---|---:|---:|---:|---:|
| Current 450 m cutoff | 0.670 ms | 0.216 ms | 0.258 ms | 174 |
| Restore authored wheel visibility | 0.700 ms | 0.242 ms | 0.260 ms | 214 |

Removing only the wheel cutoff added approximately **0.030 ms/frame** here.
That is small in absolute terms and supports testing retained distant wheel
silhouettes. It does not guarantee this cost on other hardware, with zoomed views,
more vehicles or a fully populated scenario. This benchmark is deliberately not
an all-LOD-off comparison. Native screenshots for both policies were inspected.
The completed process exited 0 with an ObjectDB leak warning, not a crash.

Artifacts: `user://wheel_visibility_render_diagnostic.json`,
`user://wheel_visibility_450.png`, and `user://wheel_visibility_0.png`.

## Evidence and limitations

- `Tests/RockWheelDiagnostic.gd` -> `user://rock_wheel_diagnostic.json`.
  Final run exited 0 with completed measurements; renderer/ObjectDB resource-leak
  diagnostics remain at teardown. The first attempt had disabled the fixture's
  physics bodies, so its wheel timings/contact residuals are excluded. The corrected
  fixture verifies its floor ray hit before measuring.
- `Tests/WheelVisibilityRenderDiagnostic.gd` isolates the wheel range in a static
  thirty-vehicle Forward+ scene. It leaves mesh/shadow LOD enabled, disables
  simulation and varies only wheel range in ABBA order. The initial frame-count
  limit ended an uncapped trial early; only a completed run is usable.
- These fixtures do not rewrite scenario settings or campaign saves. Production
  fixes above remain proposed; only diagnostic scripts and this report were added.
