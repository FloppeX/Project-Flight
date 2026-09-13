# Ground pilot rescue — 2026-09-12

## Player workflow

On the tactical map, select a platoon, choose **RESCUE PILOT**, place the target on a downed-pilot marker, and confirm. The order selects the closest survivor within 250 m of the clicked position. A known survivor can be targeted outside explored terrain. Route validation remains mandatory.

This first version does not interrupt a helicopter already assigned or launching for that survivor, or another platoon's rescue reservation. Repeating the same platoon's existing assignment is harmless. One rescue objective per platoon is supported; collect one survivor, then return. Changing the platoon's order cancels its pickup reservation.

## Implemented behavior

- Air Ops checks idle deployed or stored platoons before assigning a new helicopter. Explicit movement, escort, and combat orders are not commandeered. Vehicles in combat, deployment, retrieval, or without passenger capacity are ineligible.
- GroundRescue asynchronously checks the production NavGraph route and the final terrain connection. A graph endpoint on another elevation or too far from the pilot is rejected. Failed routes have a 60-second per-pilot/per-platoon cooldown; another platoon can still be considered.
- Initial pickup-time estimates use ground route length / 15 m/s + 25 seconds boarding, plus 90 seconds if deployment is needed. Air estimates use distance / 50 m/s + 60 seconds for a nearby helicopter, or 180 seconds for launch. A helicopter that cannot currently launch is not treated as available.
- Known, detected enemies within 500 m of the ground route add 180 seconds each to its cost. Automatic dispatch rejects a ground route with a penalty of at least 300 seconds, or a total cost above 1.25 times estimated air pickup time. Manual orders bypass that cost preference, not route/capacity checks. These are initial tuning values, not measured tactical probabilities.
- One pickup vehicle closes on the survivor; other platoon members spread around the pickup area. Rescue driving uses a 6 m arrival tolerance and does not chase combat targets; weapon targeting itself is unchanged. Normal arrival tolerance is restored after cancellation or pickup.
- The pilot waits at the validated pickup location, walks to a stopped vehicle's side, and boards only at close range with a clear final walking connection. No long-range teleport pickup.
- Friendly light vehicles have two configurable passenger slots. The actual pilot node and identity are retained, hidden inside the opaque cabin. This does not add an interior mesh or a new vehicle cockpit camera.
- Boarding removes the pilot from the rescue board, reserves them in the roster as a passenger, orders carrier return, and requests retrieval when the vehicle bay is free. Actual vehicle-bay stow releases the pilot back to the roster. Passenger state blocks checkpoints until recovered.
- If the transport explodes, its passengers are released back into the downed-pilot rescue system. This initial rule preserves them rather than rolling passenger casualties. A subsequent helicopter rescue releases the same roster reservation at hangar stow.
- Stalled pickup jobs release after 120 seconds without progress or 600 seconds total, allowing Air Ops to reconsider. Weak references protect asynchronous route callbacks against freed survivors.

The coordinator has no idle work when there are no jobs/returns. Active jobs are checked twice per simulation second; graph searches are asynchronous and are not repeated every physics frame. Final footpath safety is checked only while boarding is nearby. No aircraft aerodynamics changed.

## Verification

Executed headless with Godot 4.6.2:

- `Tests/GroundRescueSmoketest.gd`: PASS. Route assignment, duplicate/conflicting orders, capacity and moving-vehicle rejection, wrong-elevation rejection, nearby-helicopter preference, order cancellation, destroyed-transport survivor release, freed-node pruning, busy-bay waiting, identity retention, and roster availability at unload.
- The same test includes the production vehicle and DownedPilot scenes on a flat physics surface: the vehicle drives from 150 m away and the pilot physically walks aboard. PASS with one passenger and a carrier retrieval request. The vehicle bay is a fixture recording that request; it does not simulate the full ramp sequence.
- `Tests/AirOpsRescueSmoketest.gd`: PASS, including stale helicopter references, launch callback, parked takeoff, and three successive pickups.
- `Tests/Aircraft11PassengerSmoketest.gd`: PASS, including three passenger positions, identity/presentation checks, and capacity overflow rejection.
- Scoped `git diff --check`: PASS.

Logs are in `captures/ground_rescue_smoketest.log`, `captures/ground_rescue_air_regression_console.log`, and `captures/ground_rescue_passenger_regression.log`. These runs retain the existing generic ObjectDB shutdown leak warning; the helicopter capacity test intentionally emits a full-capacity warning. No script errors were reported in the final runs.

## Next validation / limits

Run a full scenario with an actual carrier, deployed and stored platoons, canyon routes, and an inaccessible mesa survivor. Verify deployment, travel, walking/boarding presentation, return to a moving carrier, ramp retrieval, and the final personnel status. The focused test proves physical pickup and the retrieval handoff, not full-scenario or rendered reliability.

The first policy uses pickup-time estimates and known ground-route threats; it does not yet model helicopter-route threat exposure, detailed return-trip cost, changing carrier accessibility, medical urgency, or multi-survivor ground batching. Existing vehicle navigation and bay retrieval remain responsible for the return journey.
