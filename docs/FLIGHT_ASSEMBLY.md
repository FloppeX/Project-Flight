# Flight assembly

The Flights tab now builds flights from individual stored aircraft. Each token is
one persistent airframe; its full ID is in the tooltip and a short ID is shown on
the token. Existing Aircraft 1–12 outlines are reused. Models 13–15 have an explicit
missing-outline label until artwork exists.

Drag an aircraft from the pool onto a flight, or click a token and then an empty
slot. A flight holds up to four aircraft of one model. Changing composition,
pilots, or loadout holds the flight; release it with the Held/Available to AirOps
button after reviewing it. Tactical orders and automatic dispatch respect this
hold. Existing unmanaged flights retain automatic behavior. Utility helicopters
remain in the rescue pool; this first assembly screen configures fixed-wing flights.

Loadout applies to the whole flight. The first version exposes compatible gun,
rocket, and bomb presets using existing hardpoint restrictions. Pilots can be
selected individually or auto-assigned. Reserved pilots cannot be selected by
another airframe or consumed by normal automatic roster selection.

Airframe IDs, flight composition, pilot reservations, loadouts, and current repair
health are saved. Launch selection uses exact airframe IDs, and recovery preserves
them. Airborne save restoration retains ammunition rather than applying a fresh
sortie loadout. Aircraft lost from a managed flight remain as removable Lost slots.

Stored aircraft automatically repair positive hull health at one full health bar
per 120 seconds. Repair stops if the hangar has no operating capability. Aircraft
under repair cannot be queued, and a managed flight waits for all its aircraft.
This is a basic hull-repair model with no material cost; it does not model individual
repair crews or a parts economy. Zero-health stock is marked Unserviceable.

Implementation: `AirOps/FlightAssembly.gd` owns configuration and repair servicing;
`UI/FlightAssemblyPage.gd` renders it. Existing deck operations still handle transport,
catapults, recovery, and the shared launch interlock.

Validation: `Tests/FlightAssemblySmoketest.tscn` covers individual inventory, same-type
rules, uniform loadouts and actual hardpoint mounting, pilot reservations, repair
blocking/completion, exact queue selection, recovery identity, save/load, loss slots,
real mouse drag-and-drop, and click-token/click-slot assignment. Its rendered run
writes Aircraft, Pilots, and Loadout previews under `logs/flight_assembly_*.png`.
Existing console, controller, scramble reservation, pilot roster, weapon policy,
and dual-catapult launch tests are also used. Full mission/recovery playtesting is
still separate from these focused checks.
