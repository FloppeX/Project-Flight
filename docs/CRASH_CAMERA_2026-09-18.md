# Crash camera handoff

FlightDirector previously copied the destroyed aircraft's chase-camera transform,
which could be rolled or below terrain. It now creates an independent upright
camera 45 m horizontally and at least 24 m above the impact focus, sampling terrain
along the sight line. The transform is assigned after scene attachment so a
translated scene root does not offset the shot. In-flight camera transitions are
cancelled before the shot takes ownership.

The shot lasts the existing five-second default, then selects the carrier bridge.
Changing cameras cancels the pending return; deferred activation cannot reclaim a
manually selected camera. Free camera can start directly from the crash shot.

Verification: CrashCameraSmoketest destroys a real Aircraft_1 with an inverted
attitude and underground chase camera over elevated fixture terrain. It checks
framing, upright placement, aircraft lifetime, timeout destination, same-frame
manual override and free-camera cancellation. The test passed headless and a
Forward+ rendered run confirmed the explosion was visible above ground. Existing
ejection, freed-target and free-camera handoff tests passed. Shutdown resource
warnings remain. This is a controlled crash fixture, not a full campaign crash
reproduction or exhaustive terrain-occlusion test.
