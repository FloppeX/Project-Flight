# Land Carrier Bridge Jitter Problem

> **Document status:** Resolved on 2026-03-21. This file is retained as a diagnostic record; the resolution is summarized at the end and in the [README](../README.md#known-problems-and-validation-gaps).

## Summary

The land carrier has a commander / bridge camera view inside the control room.
When the carrier is moving, the bridge view shows visible jitter.

There are really two related symptoms:

- `micro jitter`: a fine, rapid trembling that is especially noticeable when looking at small stable interior details like the holomap
- `macro jitter` / wobble: larger occasional shakes or lurches depending on how the carrier is moving

The problem is reduced or absent when the carrier is not moving.
That means the issue is tied to the carrier’s motion / moving-platform behavior, not just to camera look controls.

## Current User-Visible Symptom

The current user reports:

- if the carrier is stopped, the bridge jitter disappears immediately
- when the carrier is moving, the bridge view still jitters
- the problem is visible on the holomap but is not limited to the holomap
- the same issue can be seen in other parts of the bridge interior

This is important because it rules out “the hologram itself is the only problem.”

## Most Important Diagnosis So Far

The strongest confirmed issue was this:

- the commander was a `CharacterBody3D`
- standing on a bridge interior floor collider
- while that floor was moving with the carrier
- and the floor collider was originally a moving `StaticBody3D`

That combination produced severe jitter.

Changing the bridge interior collision body to an `AnimatableBody3D` clearly helped.
It appears to have removed the worst “nonsense” jitter.

However, some motion-linked jitter still remains, especially while the carrier is actively driving.

So the current best model is:

1. One real issue was bad moving-platform collision setup inside the bridge.
2. Another remaining issue is likely tiny carrier hull corrections still showing up in the bridge camera.

## Relevant Files

- `LandCarrier/Commander.gd`
- `LandCarrier/Commander.tscn`
- `LandCarrier/LandCarrier.gd`
- `LandCarrier/LandCarrier.tscn`
- `LandCarrier/BridgeHologram.gd`

## Current Implementation State

### Bridge collision

In `LandCarrier/LandCarrier.tscn`:

- `BridgeWalkCollision` is now an `AnimatableBody3D`
- `sync_to_physics = true`

This should be preserved unless there is a strong reason to revisit it.
It was one of the few changes that clearly improved the symptom.

### Commander movement

In `LandCarrier/Commander.gd`, the commander is currently set up as:

- `CharacterBody3D`
- `motion_mode = MOTION_MODE_FLOATING`
- local-space movement only
- no floor/gravity dependence for standing in the bridge
- local X/Z clamped to bridge bounds derived from `BridgeWalkCollision/Floor`

This means:

- the commander no longer relies on floor contact to stay standing
- bridge wandering / drifting through walls is prevented by local bounds clamping
- the commander can remain constrained to the bridge even without “real walking on a moving floor”

This is the current best behavioral baseline.

### Camera / interpolation

Current commander camera state:

- commander root: interpolation inherited
- commander camera: interpolation inherited
- camera is not `top_level`

Many alternative camera/interpolation experiments were tried and then backed out because they made the view worse or confusing.

### Carrier smoothing

In `LandCarrier/LandCarrier.gd`, several hull-smoothing parameters exist now:

- `steer_response`
- `steer_deadzone`
- `settle_turn_angle_deg`
- `settle_steer_deadzone`
- `height_smoothing`
- `height_deadband_m`
- `height_target_response`

These were added to reduce tiny heading and ride-height corrections that may show up in the bridge view.

They may help somewhat, but they have not fully solved the remaining jitter.

### Hologram update timing

`BridgeHologram.gd` was changed from `_process()` to `_physics_process()` and set to inherit interpolation.

That was a reasonable consistency fix, but because the user still sees the jitter elsewhere in the bridge, it is not the whole solution.

## What Definitely Helped

### 1. Converting the bridge interior collision from `StaticBody3D` to `AnimatableBody3D`

This was the most meaningful confirmed improvement.

Before:

- heavy jitter while standing in the bridge

After:

- the worst jitter reduced significantly

This suggests the original moving-platform collision setup was genuinely wrong for Godot.

### 2. Stopping the commander from depending on floor-solving

Moving the commander to a floating local-space bridge movement model helped avoid “fight the moving floor every frame” behavior.

This also made it possible to keep the commander constrained to the bridge without requiring reliable moving-floor contact.

### 3. Hard bridge bounds clamp

Adding a bridge-boundary clamp derived from the floor collision shape fixed the practical gameplay issue where the commander might drift through walls or out of the room once floor physics was removed from the equation.

This should also probably be preserved.

## Things We Tried That Did Not Solve It

### 1. Simple interpolation toggles on the commander/camera/body mesh

We tried combinations of:

- interpolation `OFF`
- interpolation `ON`
- interpolation `INHERIT`

These changed the feel, but did not fully solve the issue by themselves.

At one point:

- turning interpolation off removed some micro shaking
- but introduced or failed to prevent larger wobble

Conclusion:

- interpolation mode matters
- but it is not the only root cause

### 2. Using the commander as a normal `CharacterBody3D` walking on the moving bridge floor

This is what originally caused a lot of trouble.

Problems:

- severe jitter while the carrier moved
- unreliable moving-platform interaction

Conclusion:

- not a good fit for this setup

### 3. Re-enabling ordinary collision/floor behavior after other experiments

This was tried because the user wanted the commander to have collisions again.

It restored collision response, but did not remove the motion-linked jitter.

Conclusion:

- collisions were not the core fix
- moving-platform/floor solving was the larger problem

### 4. Making the camera `top_level` and manually smoothing/following it

This was attempted as a visual filter.

Result:

- at least one version made the bridge view completely confusing / broken
- the user described it as “completely messed up”

Conclusion:

- this path is risky
- do not casually reintroduce detached camera-follow systems without very careful transform logic

### 5. Commander-local anchor snapping experiments

Several versions tried pinning or snapping the commander to an anchor while idle.

These sometimes changed the symptom, but did not cleanly solve it.

Conclusion:

- not enough on their own
- can also create new transform conflicts if overused

### 6. Holomap-only fixes

Switching the hologram to `_physics_process` was reasonable, but did not explain the full problem because the jitter remains visible in the rest of the bridge too.

Conclusion:

- the holomap may have had a secondary timing mismatch
- but the bridge jitter is larger than the hologram

## Strong Suspects For Remaining Root Cause

### 1. Carrier hull motion is still making tiny corrections every physics frame

This is currently the most plausible remaining cause.

Evidence:

- jitter disappears when the carrier stops
- user explicitly suspects tiny corrective motion from how the carrier is “supported” by the tracks
- bridge jitter is visible in multiple bridge objects, not just the commander or holomap

Where that may come from in `LandCarrier.gd`:

- ride-height updates based on sampled tread/terrain heights
- small steering corrections while following waypoints
- rapid alternation in heading or height as terrain samples change

### 2. Height support / terrain sampling noise

The carrier body height is derived from sampled terrain under the treads and then smoothed.

If the terrain samples or tread support points fluctuate slightly every frame, that can produce visible micro jitter in the entire bridge.

### 3. Small steer corrections from path following or avoidance

Even tiny heading corrections can be very visible from an interior viewpoint.
What looks negligible in world space can feel like a fast shake inside the bridge.

The carrier already has some steer deadzone / smoothing now, but it may still need more aggressive stabilization for bridge-view purposes.

## Most Promising Next Directions

### Option A: Add debug telemetry for actual carrier motion deltas

This is probably the best next debugging step.

Instrument the carrier and log or display per-physics-frame:

- yaw delta
- body Y delta
- `_current_steer`
- raw desired height
- smoothed desired height

Goal:

- confirm whether the visible bridge jitter corresponds to tiny rapid hull yaw changes, height changes, or both

This would turn the problem from “it feels shaky” into measurable signals.

### Option B: Add a dedicated bridge-view anchor on the carrier

Instead of changing the commander or detaching the camera in ad hoc ways:

- create a dedicated bridge camera anchor node on the carrier
- smooth only that anchor’s transform for viewing
- leave actual carrier physics / commander movement alone

This is promising because:

- it isolates visual smoothing from gameplay logic
- it avoids rewriting commander physics repeatedly
- it provides a bridge-only damping layer

If this is tried, it should be done carefully and incrementally.

### Option C: Stabilize only small hull corrections, not large ones

If the carrier needs tiny corrections for navigation but those should not shake the bridge view:

- introduce a view-oriented deadband / low-pass filter for tiny yaw and height changes
- allow large real motions through normally

This could make the bridge feel stable without hiding meaningful movement.

### Option D: Revisit the tread-support / ride-height model

If the whole carrier body is effectively “riding” on noisy per-tread terrain samples, the correct long-term fix may be there rather than in the camera.

Possible improvements:

- stronger filtering of terrain sample noise
- more stable aggregation of tread support heights
- slower response to tiny height changes
- separate low-frequency hull ride from high-frequency terrain detail

### Option E: Explicitly separate visual hull stabilization from gameplay collision

If gameplay needs the current carrier motion, but the bridge should feel calmer:

- keep the physical carrier transform as-is
- add a visual-only stabilized interior root for bridge occupants and bridge cameras

This is architecturally heavier, but may be appropriate if direct hull smoothing causes side effects elsewhere.

## Less Promising Directions

These were tried already or are unlikely to solve the remaining issue alone:

- re-toggling commander interpolation modes repeatedly
- reintroducing normal walking-on-floor physics for the commander
- tweaking only the hologram
- more commander anchor snapping without measuring hull motion
- detached camera follow systems without a very careful transform design

## Suggested Practical Next Step

If resuming work on this, the most useful next step is:

1. Instrument the carrier’s actual per-frame yaw and height changes while driving.
2. Correlate those values with visible bridge jitter.
3. Decide whether the remaining problem is mostly:
   - yaw correction noise
   - height correction noise
   - or both
4. Then either:
   - smooth the hull motion more intelligently, or
   - add a dedicated smoothed bridge-view anchor

That is likely to be more productive than further commander-only experiments.

## Resolution (2026-03-21)

### Root cause found: float32 precision loss at large world coordinates

The terrain and carrier were placed at (5000, 62, 5000) in the scene — approximately 7000m from the world origin. At that distance, float32 vertex precision degrades to ~1mm, causing visible shimmer on all geometry and shadows when the camera moves. This affected the bridge view most because the interior surfaces are viewed at very close range.

### What was done

1. **Moved terrain and carrier to the world origin** (0, 62, 0). No code references the old (5000, 62, 5000) offset — it was arbitrary.
2. **Moved commander look updates from `_process` to `_physics_process`** to avoid mixing render-frame and physics-frame transform writes on an interpolated node, which caused additional macro jitter during earlier experiments.

### What was ruled out via instrumentation

- Hull motion corrections (yaw/height deltas): measured at max 7.2 millidegrees and 1.4mm per physics frame, smooth and non-oscillating — too small to be the cause
- Physics interpolation: toggling ON/OFF made no difference
- Top-level camera with smoothed follow: created a mismatch between camera and bridge geometry, making things worse
- Shadow cascade blending: no measurable impact

### Key lesson

Float32 precision jitter at large world coordinates can look identical to interpolation or transform jitter. The diagnostic that mattered was moving the world to the origin — not any amount of transform smoothing or interpolation tuning.

## Short Version

The bridge jitter had two layers. The worst was fixed earlier by switching the bridge floor collision to `AnimatableBody3D`. The remaining micro jitter was caused by **float32 rendering precision loss** from the scene being placed 7000m from the world origin. Moving the terrain and carrier to (0, 62, 0) resolved it.
