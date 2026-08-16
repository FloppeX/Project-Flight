# Land Carrier Track Mapping Problem

> **Document status:** Unresolved investigation. The visible loop discontinuity remains listed in the [README](../README.md#known-problems-and-validation-gaps); verify the symptom in the current build before resuming the proposed debug work.

## Summary

The land carrier uses a shader-driven fake tread animation rather than real moving tread geometry.
The overall look is now close, but there is still a persistent visible split in the tread animation at the lower front and lower rear turnarounds.

This is not primarily a texture-direction problem anymore.
It is a loop-mapping problem: the tread pattern is not staying on one continuous distance-along-loop coordinate around the full tread shape.

## Current User-Visible Symptom

From gameplay distance, the tread mostly reads correctly on the straight runs, but breaks at the turnaround areas:

- The top run generally looks coherent.
- On the front downward slope, the bands/segments appear to stretch and sometimes look like they accelerate.
- At the lower front corner, there is a visible split or handoff.
- A similar split appears again at the lower rear.
- Reversing tread direction changes the direction of motion but does not remove the split.

The user provided a video showing this clearly:

- `e:\Downloads\IMG_9316.MOV`

The important observation from that clip is that the split remains tied to the same geometric region of the tread, not to a simple UV wrap direction.

## Important Context

### Original setup

Originally, the tread effect was a very simple scrolling texture driven by UV motion.
That had several problems:

- the texture was too simple and looked like pulsing stripes
- the mesh has many faces / likely many UV islands
- UV scrolling did not read like one continuous belt
- direction and speed were initially wrong or unclear

### Mesh / authoring constraint

The user later realized the tread object has many faces.
That matters because a naive UV-scrolling shader tends to animate each face or island as its own little region, which creates pulsing and discontinuities.

The user also had an existing Blender bezier curve describing the tread shape.
A tiny Blender task was done to export that curve as:

- `res://Models/LandCarrier/track_path_export.glb`

The current tread system now uses that helper path as the source of truth for the loop shape.

## Current Implementation

The active tread implementation lives in:

- `LandCarrier/CarrierTread.gd`

The key design is:

- the helper path mesh from `track_path_export.glb` is loaded
- the helper path is projected into 2D
- projected points are clustered and ordered into a closed path
- the path is resampled
- tread mesh vertices are baked with a custom `UV2`
  - `UV2.x` = loop distance along the tread
  - `UV2.y` = cross-width on the tread face
- the shader scrolls along `UV2.x`

This is already a much better direction than the original raw UV scroll.

## Things That Definitely Improved

These changes helped and should probably be preserved:

- Switching away from naive imported UV scroll to a baked path-driven coordinate.
- Using the exported Blender helper path.
- Baking a custom loop coordinate into `UV2`.
- Keeping the tread as a shader illusion instead of trying to physically move geometry in Godot.
- Separating the tread issue from wheel spin direction and overall scroll direction.

The current effect is visibly closer to believable tread motion than the original pulsing-stripe version.

## Things We Tried

### 1. Raw UV scrolling on the tread mesh

This was the original style of approach.

Problems:

- heavy pulsing
- obvious fake sliding
- did not survive many-face / many-island tread geometry

Conclusion:

- Not viable for this mesh.

### 2. Retuning the procedural tread pattern itself

Many iterations were done on:

- band width
- band count
- seam sharpness
- speed
- direction

This improved readability but did not solve the core split.

Conclusion:

- Useful for visual tuning
- not the root fix

### 3. Top/bottom split shader hacks

We tried shader logic that made the lower run move opposite the upper run via a split.

Problems:

- often picked the wrong axis
- sometimes split inner vs outer tread width instead of upper vs lower run
- produced strange front/back transition zones
- became brittle and confusing

Conclusion:

- Too hacky for this mesh
- abandoned in favor of path-driven mapping

### 4. Local-position-based mapping instead of UV mapping

This was better than raw imported UVs because it avoided per-face UV restart behavior.
But on its own it still did not correctly represent a closed tread loop.

Conclusion:

- Better than UV scrolling
- still incomplete without a real loop path

### 5. Path-driven mapping using the exported Blender curve

This is the current system.
It was the biggest improvement and is the right overall direction.

However, the remaining split suggests there is still an issue in one of these areas:

- helper path ordering
- helper path to tread-space alignment
- closed-loop distance projection
- seam placement
- branch/turnaround interpretation

### 6. Left/right branch interpretation

At one stage the bake split the loop into branch-like interpretations and used midpoint tests to decide which side a vertex belonged to.

This seemed mathematically plausible, but in practice it produced or preserved a hard handoff in the lower front/rear regions.

Conclusion:

- likely one source of the visible split
- this approach should not be reintroduced casually

### 7. Seam relocation

We tried moving the UV wrap seam toward a less visible location, such as the upper run.

This did not remove the split at the lower front / rear.

Conclusion:

- the visible split is probably not just the wrap seam
- it is more likely caused by inconsistent local loop-distance assignment near the turnarounds

### 8. Helper path nearest-neighbor ordering

The helper path points were at one stage ordered by a nearest-neighbor walk after clustering.
This can be wrong for rounded-rectangle-like loops because the path can be chained in a locally plausible but globally wrong order.

That has since been changed toward a more loop-oriented ordering approach, but the split still appears.

Conclusion:

- ordering was a reasonable suspect
- but it was not the only issue

## Current Best Diagnosis

The remaining split is most likely caused by a mismatch between the helper path and the actual tread surface in the turnaround regions.

More specifically:

- the straight runs map well enough
- the lower front and lower rear corners do not receive a consistent continuous arc-length coordinate
- vertices in those areas are probably being projected onto the wrong nearby segment of the helper loop, or onto the right segment with the wrong local orientation

This would explain why:

- the split stays in the same physical place
- the straight runs can look fine
- front slope spacing can stretch
- seam moves or direction flips do not solve it

## Most Promising Next Directions

### Option A: Inspect baked path UVs directly on the tread

This is probably the best next debugging step.

Use the existing tread debug modes, or add stronger ones, so the tread shows:

- raw `UV2.x` as a continuous gradient
- contour lines every fixed interval of `UV2.x`
- highlighted wrap seam

Goal:

- verify whether `UV2.x` itself jumps at the lower front / rear
- separate a bake problem from a final shader presentation problem

If the gradient itself jumps, the bug is in the bake / projection.
If the gradient is smooth but the visible pattern still splits, the bug is in how the final procedural pattern interprets it.

### Option B: Compare helper path and tread in the same local plane

Add a temporary debug draw that renders:

- the projected helper loop
- sampled tread-vertex projections
- the chosen nearest segment / nearest point for a few representative vertices near the split

Goal:

- see whether the lower-front and lower-rear tread vertices are snapping to the wrong part of the helper loop

### Option C: Bake based on normalized angle/arc from the actual helper curve in Blender

This may be the best robust solution if Godot-side projection continues to be fragile.

Instead of exporting the helper path as a beveled mesh and reconstructing order in Godot:

- use Blender to bake a true distance-along-loop attribute or UV strip directly
- export that on the tread mesh
- in Godot, only scroll the baked coordinate

This avoids a lot of inference and reconstruction in `CarrierTread.gd`.

Tradeoff:

- requires more Blender work
- but likely gives the cleanest long-term result

### Option D: Export a denser and cleaner path representation

If staying in Godot:

- export the helper curve in a way that preserves clear point order
- avoid reconstructing order from raw mesh vertices when possible

For example:

- a path mesh with deliberately ordered vertices
- a custom exported list of sampled points
- a simpler one-ring path representation with less bevel ambiguity

The current helper export may still be adding ambiguity because it is a converted mesh rather than explicit ordered curve data.

### Option E: Use nearest-point projection plus tangent continuity checks

If projection remains Godot-side:

- keep nearest-point projection to the closed loop
- but add continuity constraints using neighboring vertices or local tangent consistency

Goal:

- stop vertices near the lower front/rear from projecting onto a geometrically close but topologically wrong part of the loop

This is more advanced, but it directly targets the kind of corner snapping that seems likely here.

## Less Promising Directions

These were tried already or are unlikely to solve the root issue alone:

- changing only tread speed
- changing only tread direction
- changing only band size
- changing only shader sharpness
- moving the seam without fixing the loop-distance assignment
- reintroducing simple top/bottom split logic
- relying on imported mesh UVs

## Suggested Practical Next Step

If resuming work on this:

1. Add a very clear debug view for baked `UV2.x` on the tread mesh.
2. Confirm whether the discontinuity already exists in baked path space.
3. If yes, debug projection around lower front and lower rear specifically.
4. If no, debug only the final procedural band shader.

That is the cleanest way to avoid more blind tuning.

## Related Files

- `LandCarrier/CarrierTread.gd`
- `LandCarrier/CarrierTread.tscn`
- `LandCarrier/LandCarrier.tscn`
- `Models/LandCarrier/track_path_export.glb`
- `Models/LandCarrier/carrier_track_texture.png`

## Short Version

The tread is close.
The remaining defect is a persistent split at the lower front and rear turnarounds.
It is almost certainly a continuity problem in the loop-distance mapping, not a simple texture-direction or speed issue.
The most useful next move is to debug the baked loop coordinate directly and verify how tread vertices near the turnarounds are projected onto the helper path.
