# Fleet change coverage

Audited the 13 authored aircraft scenes: fixed-wing Aircraft 1–8 and 14, and helicopters 9–12.

## Gaps repaired

- Progressive Advanced control authority was enabled only by Aircraft 5. It is now the default in shared SimpleAero, so all nine fixed-wing aircraft inherit the speed-squared control response and associated damping schedule. Existing per-aircraft power, stall and high-speed settings are preserved. The existing 100 m/s reference remains configurable; this is not a claim that it is optimal for every airframe.
- HelicopterFlight did not sample WindField. Rotor speed scheduling, fuselage drag and vertical-stabilizer response now use air-relative velocity. Its wind query API also lets shared aircraft instruments and turbulence handling recognize the physical wind integration, avoiding the legacy duplicate gust impulses. Rotor authority at hover remains governed by helicopter physics.

## Shared coverage and intentional exceptions

- All 13 scenes use the shared ControlSteering module. Adaptive rudder correction applies to Advanced fixed-wing flight; manual input priority and the helicopter control path remain distinct.
- Fixed-wing wind and gust forces use SimpleAero. AI turn/approach corrections use the shared AIPilot. Formation coordination uses Flight state gates rather than an aircraft-number restriction.
- White dust-style steam belongs to Catapult and therefore applies to any aircraft launched by it. Tractor pause and routing behavior belong to SimpleTractorBot, not individual aircraft scenes.
- Ejection presentation changes apply wherever the existing EjectionSequence is fitted: Aircraft 1, 2, 5, 7, 8, 12 and 14. Aircraft 3, 4, 6, 9, 10 and 11 currently have no such sequence. This audit does not add ejection hardware to those aircraft.
- Authored wing-fold pivots, gear geometry and Aircraft 2's minimum launch speed remain aircraft-specific.

## Evidence and limits

- FixedWingFleetHandlingSmoketest passes all nine authored profiles, progressive envelope checks and adaptive-assist availability. Its stale Aircraft 2 expectations were updated to the already-authored roll/yaw power and surface rates; aircraft tuning was not changed to match the test.
- FleetWindCoverageSmoketest passes all 13 airframe configurations. It checks wind-relative velocity and calm fallback, plus physical crosswind drift for all four helicopters on isolated rigid bodies.
- Aircraft 14's 100 m/s paired runtime autorudder test passes with progressive controls enabled: the reproduced positive-bank oscillation settles, with late mean ball error about 0.0004 g versus 0.2000 g with adaptive assist disabled.

These are focused configuration/physics checks, not a complete takeoff-to-landing campaign for every airframe. The previously documented AI turn-in/recovery problem remains unresolved. Helicopter gust response now acts through drag and tail-fin physics; spatial rotor-disc gust loading is not modeled by this change. Headless runs may report object/resource leaks during shutdown.
