# Pilot helmet patterns

Expanded 2026-09-15: nine designs. Pattern IDs are append-only to preserve the
original shader mode numbers and existing saved designs.

| Pattern ID | Design |
| --- | --- |
| `plain` | Solid helmet shell, no built-in stripe |
| `racing_stripes` | Diagonal racing bands |
| `stars` | Side and crown star badges |
| `camo` | Continuous three-tone camouflage patches |
| `lightning_bolts` | Angular lightning emblems on both sides |
| `shooting_stars` | Forward stars with three trailing streaks on both sides |
| `flames` | Two-tone hot-rod flames rising from the lower rim |
| `checkerboard` | Checkered band around the lower shell |
| `chevrons` | Three forward-pointing bands across the crown and sides |

These are procedural paint textures over the whole helmet shell, including the
former stripe faces. The current `pilot.glb` retains the animation-compatible rig
but assigns those faces to `Helmet_Color_2` too, so there is no built-in stripe.
`helmet_color_2` controls the uniform base; `helmet_color_1` remains in saved
palettes for backward compatibility but has no visible surface on this model.
Runtime paint never edits the imported mesh or its authored UVs.

## Per-pilot settings

The existing `pilot_livery_colors` identity dictionary now also accepts:

```gdscript
"helmet_pattern": "stars",
"helmet_marking_color": Color(0.96, 0.93, 0.82),
```

The marking color's alpha controls overlay strength. Missing ink uses contrasting
cream or near-black. Missing/unknown pattern uses `plain` (a solid-color helmet).
Every newly generated pilot receives one of the eight painted designs, randomized
helmet colors (including the legacy unused slot) and a randomized marking color.
Colors come from the existing curated helmet palette, with minimum RGB
separation between the underlying colors and ink. This is a readability heuristic,
not an accessibility or perceptual contrast guarantee. `plain` remains available
for manual customization but is excluded from random selection.

Existing saved roster pilots receive a **one-time helmet-only randomization**
when their identity loads. The upgrade is seeded from their ID, name, and previous
helmet colors; reloading the same Continue save or Trailer baseline produces the
same result even before saving again. Suit colors, identity, and career state
are left alone. `helmet_randomization_version = 1` is saved with the palette to
prevent subsequent rerolls, including of later manual edits. Save files/baseline
files are not rewritten by this code until the normal game save operation.

To customize a roster pilot and immediately refresh their assigned cockpit:

```gdscript
PilotRoster.set_pilot_helmet_pattern(pilot_id, "stars", Color(0.96, 0.93, 0.82))
```

This writes the identity-owned appearance, so subsequent assignments and the
existing ejection/rescue/passenger palette-copy paths carry it with the pilot.
Already spawned detached representations are not live-edited by this setter.
The pattern and ink are included in roster saves. This first slice adds a data/API
setting, **not a new player-facing helmet editor**.

## Implementation

- `Aircraft/Visuals/PilotHelmetPattern.gd` builds one cached derived mesh per
  source mesh, including the runtime flat-shaded pilot variant. All helmet
  primitives use the same bind-pose bounding box for CUSTOM0 paint coordinates.
- The shader reads those stable coordinates instead of posed/world positions,
  so paint follows the skinned head. Original colors show through unpainted areas.
- Stripes are diagonal racing bands; stars are side/crown badges; camo is a
  continuous 3D patch pattern. The authored double-sided helmet shell is retained.
- Side emblems point forward on both sides. Flames and checkerboard use periodic
  angular mapping to avoid a rear wrap seam. All designs are static paint (no
  time-driven flickering or flame animation). Flames use the marking color and a
  darker shade of it; choose a gold/orange marking color for traditional flames.
- Vertex geometry, bone weights, UVs, materials, LOD indices, blend shapes,
  flat-shading markers, and non-helmet surfaces are preserved. Reusing a pooled
  body resets its material overrides, including pattern-to-plain transitions.
- Mesh preparation refuses an already-authored CUSTOM0 channel instead of
  overwriting unknown data. This slice targets the shared current pilot mesh.
- Uses Godot's documented [custom mesh attributes](https://docs.godotengine.org/en/stable/classes/class_mesh.html#enum-mesh-arraycustomformat).
  Serialized surface dictionaries preserve LOD data because ArrayMesh does not
  expose a public surface-LOD getter; recheck this when upgrading the engine.

## Verification

```powershell
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://Tests/PilotHelmetPatternSmoketest.gd
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --path . --script res://Tests/PilotHelmetPatternSmoketest.gd -- --render
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --path . --script res://Tests/PilotHelmetPatternSmoketest.gd -- --render --posed
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --path . --script res://Tests/PilotHelmetPatternSmoketest.gd -- --render --posed --new
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --path . --script res://Tests/PilotHelmetPatternSmoketest.gd -- --render --posed --random
```

The focused test checks both material surfaces, source immutability, shared mesh
caching, pool-style reassignment, legacy fallback, metadata transfer, roster
save/restore for every design, stable original mode IDs, and applying the real
cockpit pose without losing the paint mapping.
The Forward+ renders show front/back close-ups, including the flat-shaded cockpit
pilot at two sampled animation times. Images are written under `user://` as
`pilot_helmet_patterns.png` and `pilot_helmet_patterns_posed.png`.
`--new` renders only the five added designs into a separate `_expanded.png` sheet.
Its flame example uses gold marking ink; other preview designs use cream.
`--random` shows reproducible samples from the actual random-palette generator.
Randomization checks cover 512 palettes, all painted designs, ink diversity,
legacy roster migration, repeated old/new save restores, suit preservation, and
keeping later manual changes intact.

Also run `PilotRosterRandomizationSmoketest.gd` and
`Aircraft11PassengerSmoketest.gd` for existing identity and passenger behavior.
These checks are not a full live ejection/rescue mission or replay export test.

## Stripe-free compatible model repair (2026-09-15)

The stripe-removal re-export also changed the rig from 339 bones under
`char_grp/rig` to 67 bones under `root`, breaking baked animation paths and parent
relationships. The agreed repair restores `pilot.glb` from commit
`90f5113d3e5c9f64662cc7cf79d61e34afcae567`, remapping only the primitive using
`Helmet_Color` to `Helmet_Color_2`. All other JSON fields, geometry/skin binary
buffers, animations, and hierarchy are unchanged from that compatible source.

`Tools/RestoreCompatiblePilotHelmet.py` performs the bounded repair and validates
unchanged binary chunks. It defaults to inspection; `--apply` first backs up the
current file outside Godot's import tree. The replaced user export is preserved at:

`C:/Users/jonto/AppData/Local/Project-Flight/asset-backups/pilot-20260915-204309-118269/pilot-before-rig-repair.glb`

Reimport and Forward+ posed rendering passed. The helmet smoke test now checks
uniform shell material assignment and every node/bone track in the baked animation
library. Passenger and ejection-animation-handoff regressions also passed, with
no missing-track or script errors. Existing ObjectDB shutdown warnings remain.

### Former stripe face lighting correction

The material-only repair exposed a separate authored geometry problem: 16 of the
former stripe triangles had reversed winding and normals relative to the connected
shell. Both vertex-color channels were white, so this was not leftover paint.
`Tools/FixPilotHelmetWinding.py --apply` corrected those 16 triangle index orders
and 32 split-vertex normals. It uses shared-edge orientation with the larger shell
as its reference, refusing non-manifold or mixed-vertex cases. Vertex positions,
weights, skeleton, animation data, materials, and scene hierarchy remain unchanged.

The pre-normal-repair file was backed up to:
`C:/Users/jonto/AppData/Local/Project-Flight/asset-backups/pilot-normals-20260915-220444-087033/pilot-before-normal-repair.glb`.

If rerunning `RestoreCompatiblePilotHelmet.py`, also run the winding repair before
reimporting; the historical source still contains those reversed faces. Use
`Tools/FixPilotHelmetWinding.py --check` as a no-write regression check. The repaired
asset reports zero inconsistent triangles and passes the helmet/animation smoke
test. A fresh Forward+ posed preview confirms the lighter stripe-shaped bands are
gone, while the intended faceted shading and painted designs remain.
