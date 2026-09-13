# Aircraft 2 go-around response — 2026-09-08

## Changes

Shared AIPilot changes, enabled by `landing_bolter_response_control_enabled`:

- Apply escape controls and full commanded power in the wave-off's own update.
- Use the existing lift/AoA feedback controller for escape pitch instead of the
  approach's 0.42 input cap. Actuator output remains bounded to normal player
  inputs; useful aerodynamic lift and the 2.8G requested ceiling bound demand.
- A wings-level escape must be allowed to request more than 1G to arrest descent.
  The turn-roll-in blend previously suppressed such a request at zero bank.
- Estimate descent-arrest time/height using sink, roll response and available
  lift. When no viable catch is predicted, approaching this escape deadline can
  trigger a wave-off before the optimistic maximum-descent wire test does.
- Keep the initial escape straight until beyond the authored carrier hull's bow
  plus 30 m, as well as satisfying the existing altitude, speed and bank gates.
- Do not replace the lift-based escape with the old terrain-margin pitch servo
  merely because terrain lies beneath the aircraft. Actual imminent flight-path
  intersections retain the emergency override, but its pitch demand now uses the
  same lift/AoA feedback rather than switching to the old servo. Escape guidance itself samples
  forward terrain at 2/4/6-second horizons.

No aircraft mass, gear, aero, colliders, cables or damage rules changed. Earlier
route-capture experiments remain disabled. The new escape-budget calculation is
a heuristic, not proof that an already-upset or damaged aircraft can recover.

## Visible test

Run `tools/run_visible_go_around_test.ps1` from the project. It opens a normal-speed
Forward+ window with an external follow camera, live height/speed/vertical-speed/
bank/control overlay and per-case logs. It waits for the loading overlay to finish
before spawning. `-StartCase 6 -Cases 1` selects the touchdown bolter alone.

Each run has timestamped stdout/stderr, metadata, source snapshots and input hashes
under Godot userdata `Land Carrier/visible_go_around_YYYYMMDD_HHMMSS`.
The comparison must be rejected if any recorded input hash changes during it.

The first four cases issue an explicit wave-off shortly after spawn at nominal
50/50-steep/20/10 m heights. Actual trigger heights/speeds/sinks are logged (the
aircraft is already moving), and the automatic high-miss gate is disabled only
for these forced-response probes. A fifth case tests automatic high-miss handling.
The sixth uses a hook-up, higher approach. The seventh suppresses that automatic
miss gate in a low hook-up arrival so it can test actual last-wire bolter detection.
Only the tailhook is stowed; wheels, flaps, collision and damage remain active.

ESCAPED means go-around was observed, the aircraft is beyond the bow +30m, at least
35m above deck, bank below 15 degrees, not descending, and speed above stall+5m/s
continuously for two seconds. It does **not** mean it landed or completed another
circuit. Damage is reported separately. An early wave-off is not a tested bolter.

## Iteration evidence

- `191130`: stopped exploratory launch. Cases were running behind the loading
  screen and automatic aborts pre-empted the intended forced heights. Not a valid
  visible forced-height comparison.
- `191424`: completed six-case visible run, all recorded input hashes unchanged.
  Five clean escapes; the higher hook-up approach crashed after a wave-off and
  hard touchdown, before reaching a bolter. Forced trigger heights were 48.3,
  46.8, 18.4 and 8.4m; all four escaped without touchdown. The steep case arrested
  descent at approximately 39m. The failed case's lift telemetry froze while the
  old safety controller applied pitch; this motivated the terrain-ownership fix.
  Its original JSON still labels escape quality using the older landing-stop
  definition; interpret the explicit ESCAPED outcomes and zero damage fields.
- `191938`: completed seven-case visible comparison; all recorded inputs unchanged.
  Six clean escapes, including an actual bolter after a 1.18m/s touchdown (W0/B1).
  The high hook-up case still crashed, after a 0.99m/s touchdown. Its new telemetry
  established `safety=true` with frozen lift feedback throughout the critical
  descent: the imminent-threat branch still restored the old pitch servo. The
  final revision preserves emergency priority but uses lift feedback there too.
- `192415`: completed seven-case visible replay of that emergency-controller
  correction: **7/7 clean escapes**, zero health/part damage, all 19 tracked input
  hashes unchanged during the run. The formerly failing high hook-up case now
  escaped without touching the carrier; lowest sampled body height was about
  6.3m above deck. The actual bolter touched down at 0.97m/s, missed the wires
  with the intentionally stowed hook (W0/B1), and climbed clear. Durations below
  include approach time until the escape criteria held for two seconds.

| Case | Outcome | Duration | Touchdown |
| --- | --- | ---: | --- |
| Nominal 50m wave-off | Clean escape | 11.23s | None |
| Steeper 50m wave-off | Clean escape | 8.87s | None |
| Nominal 20m wave-off | Clean escape | 8.70s | None |
| Nominal 10m wave-off | Clean escape | 9.28s | None |
| Automatic high miss | Clean escape | 7.00s | None |
| Higher hook-up approach | Clean escape | 18.53s | None |
| Low touchdown bolter | Clean escape | 12.18s | Normal, 0.97m/s |

No script/parse errors or crash-handler signature were found in the final run.
Existing startup child-attachment errors, material warnings and shutdown resource/
texture lifetime warnings remain; this is not an error-free engine run.

The user correctly noticed the retracted tailhooks. Those are intentional in the
two hook-up cases; other aircraft also retract gear/hook/flaps during escape once
35m above the deck. After the completed run, the overlay was clarified to label
forced aborts and deliberately retracted hooks explicitly. This was a display-only
change; it does not relabel these escapes as successful landings.

This is one small controlled Aircraft 2 escape sample, not 7/7 landing success or
fleet validation. The next check is normal hook-down landings plus wave-off/retry
cycles, to ensure earlier escape decisions do not reject recoverable approaches.

## Logic checks

`GoAroundResponseSmoketest` passes same-update state/power/pitch takeover,
wings-level descent-arrest load, useful-lift limits, response-budget ordering,
viable-catch and real-catch precedence, terrain-margin ownership, and retained
imminent-terrain override. Deck-envelope and random-start generation smoke tests
also pass. These tests do not establish fleet landing reliability. Existing
resource/lifetime warnings remain distinct from their PASS results.
