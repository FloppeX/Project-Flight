# Aircraft 1, 2 and 5: jagged breakaway geometry

Implemented 2026-09-11, extending the Aircraft 6 mesh workflow.

## Behavior

Each aircraft now has five baked breakaway pieces with matching irregular
fracture surfaces and grey-metal end caps. Original GLBs remain untouched;
the aircraft scenes use sibling `aircraft_N_breakaway.glb` assets.

| Aircraft | Wing break, model-space distance from center | Tail pieces |
| --- | --- | --- |
| 1 | About 4.22 m, beyond the second folding hinge | Two horizontal tips and upper T-fin |
| 2 | About 4.45 m, beyond the folding hinge mechanism | Two horizontal tips and upper T-fin |
| 5 | About 3.8 m, beyond the folding hinge mechanism | Horizontal bridge and two upper fins |

The new wing tips are child meshes of the existing moving outer panels. The
wing-fold scripts, pivots, animation timing and authored node origins are
preserved. Aircraft 1 retains its middle folding panels as well as the inboard
part of each outer panel after damage. Its multi-panel damage-collider follower
also includes the new child tips so they remain covered in every fold pose.

Wing insignias follow the detachable child meshes. Aircraft 2 and 5's right-wing
markers previously followed the left wing; those now follow their own sides.
Aircraft 2's fin insignia follows its detached fin. The low-mounted tail markings
on 1 and 5 remain projected onto the surviving fin bases.

Damage thresholds and existing wing-loss flight-control behavior are unchanged.
As with Aircraft 6, the existing zone collider disables on destruction; this
does not add separately damageable root colliders or individual left/right
stabilizer health pools.

### Supported tails

These T/H-tail aircraft opt into
`AircraftPartDamageModel.vertical_stabilizer_supports_horizontal`: destruction
of the supporting vertical zone also destroys the horizontal zone through the
normal damage API. Thus the horizontal surface cannot remain floating above a
missing support. Destroying only the horizontal surface does **not** destroy the
fins. Unrelated airframes retain the default `false` behavior.

Independent debris remains an opt-in per zone. Horizontal tips fall separately
on 1/2; the twin upper fins fall separately on 5. Its central horizontal bridge
falls as one physical piece.

## Authoring and reproducibility

```powershell
& 'C:/Program Files/Blender Foundation/blender 4.5.3/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/build_folding_aircraft_breakaway.py -- --build
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --editor --path . --import --quit
```

Omit `--build` to inspect the originals without writing assets. The builder
reuses Aircraft 6's geometry/cap validation and original-normal transfer. All
cutting is offline: no runtime Boolean operations or mesh slicing.

Source topology requires a few explicit treatments:

- Aircraft 1 has an internal fin center sheet and overlapping tail-tip slivers.
  The generated copy removes the internal sheet and gives the visible slivers
  a closed 0.4-mm-thick wedge, preserving their outline. The exterior audit
  excludes that explicitly identified internal sheet, permits redundant face
  area reduction only with a tighter 0.5-mm coverage check, and verifies the
  resulting skin in both directions.
- Aircraft 2/5 contain overlapping unpainted hinge geometry inside their wing
  meshes. It is kept verbatim, outside the Boolean operation, and joined back
  into the original moving panel. Cuts are outboard of those mechanisms.
- The original T/H-tail junctions on 2/5 contain touching closed shells. They
  remain closed, but are not globally manifold at every shared edge; validation
  allows even-face closed junctions there, while still rejecting open boundaries.
- Both sides of every new fracture are checked for matching cap surfaces to
  within 1 mm. Original materials, UVs, model hierarchy and faceted normals are
  retained; the original source files are not rewritten.

Maximum sampled exterior differences: 0.209 mm for 1, 0.332 mm for 2, and
0.163 mm for 5. Aircraft 1's redundant exterior face area decreases by about
0.411 square metres without losing sampled outside coverage. These are sampled
geometric checks, not a proof of identical triangulation.

## Verification

```powershell
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/FoldingAircraftBreakawaySmoketest.gd
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/FixedWingPartDamageColliderSmoketest.gd
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/Aircraft6BreakawaySmoketest.gd
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --path . --script res://Tests/FoldingAircraftBreakawayRenderedProbe.gd
```

**PASS:** 24 damage cases and nine fold comparisons against the
original GLBs: sublethal retention, real collider-index damage routing, retained
roots, correct unaffected parts, support-loss propagation, separate capped
debris, no position jump when detaching folded parts, gravity after the initial
separation impulse, insignia following/transfer, and duplicate-damage protection.

Rendered captures in `captures/folding_aircraft_breakaway/` compare originals
with intact derivatives and show exploded geometry, close-up tail fractures,
fully folded aircraft and actual runtime damage. The owner is frozen in these
focused tests for repeatability; they are not a full combat-flight playtest.

The shared fixed-wing damage regression and Aircraft 6 breakaway regression
also pass. Rendered comparisons and breakup captures were inspected. Existing ObjectDB shutdown-leak
warnings and the fleet test's unrelated WingFold node warnings remain outside
this mesh change.
