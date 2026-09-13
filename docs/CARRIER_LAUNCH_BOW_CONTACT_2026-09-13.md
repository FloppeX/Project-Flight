# Carrier bow launch kick

## Evidence and cause

The player's saved take `2026-09-13T15-01-04_348817` contains Aircraft 5 slowing from roughly 62 to 31 m/s relative to the carrier while gaining about 18 m/s vertical speed near the bow. The motion is present in the stored subject transforms, not introduced by export.

The physical retrieval/launch probe reproduced this on a stationary LandCarrier2. Immediately after catapult release, `CenterGearCollider` contacted a bevel triangle in `CarrierModel/InteriorSurfaceCollision` near carrier-local z=74 m. Its normal was approximately (0, 0.770, -0.638), with a roughly 22.6 kN s upward / 22.9 kN s backward impulse. The ensuing pitch-up put the vertical stabilizer into the deck. The existing release grace suppressed carrier damage only; it did not prevent that impulse.

`CarrierIslandIntegration.gd` combined interior walking surfaces and the rendered flight deck into a backface-enabled triangle collider on both the general physics layer and the dedicated walking layer. This duplicated the compound-hull runway and exposed visual bow bevels to aircraft wheels.

## Fix

The flight-deck triangles now have their own `FlightDeckWalkingCollision`, on the dedicated interior/walking layer only. Interior/island surfaces retain their previous general physical collision. Aircraft continue to contact the compound carrier hull; no launch force, aircraft handling, or damage-grace values were changed.

## Validation

`Tests/CarrierLaunchContactProbe.tscn` runs real hangar retrieval and catapult launch, logging per-contact shape names, normals and impulses plus aircraft motion and tow errors. Use `-- --aircraft=1`, `2`, or `5` (default 5). It checks speed retention and vertical velocity for the first 0.5 s after release, survival through 1.25 s, collision layers, and a commander-layer ray onto the flight deck.

| Aircraft | Release speed | Minimum exit speed | Maximum absolute vertical speed, first 0.5 s |
| --- | ---: | ---: | ---: |
| 1 | 65.54 m/s | 65.54 m/s | 0.42 m/s |
| 2 | 59.94 m/s | 59.94 m/s | 0.56 m/s |
| 5 | 64.61 m/s | 64.61 m/s | 0.69 m/s |

All three headless physical launch checks passed. Logs: `captures/carrier_launch_contact_baseline.log`, `captures/carrier_launch_contact_fixed.log`, and `captures/carrier_launch_contact_aircraft_{1,2,5}.log`. These are stationary-carrier focused checks, not full moving-scenario or rendered flight validation. Existing carrier asset/shutdown warnings remain in these fixtures.
