# Direction-independent go-around clearance

## Evidence

The mixed run `random_rtb_20260909_121648_seed_20260908` completed with 11 clean
stops out of 12: Aircraft 1 and 5 each 4/4; Aircraft 2 3/4. Every successful stop
had zero overall and regional damage. Matched starts and input hashes verified.

Aircraft 2, zero-based case 3, aborted pre-landing for lack of progress, then
remained in MISSED_APPROACH until crossing the test's 40 km distance limit.
The TELEPORT outcome label was misleading: at termination the physics and node
positions agreed, the aircraft was moving about 102 m/s sideways, and no jump
was recorded. `_is_bolter_clear_of_carrier()` only accepted a carrier-local Z
position beyond the bow. A sideways departure could never satisfy that rule.

## Fix

Shared AIPilot clearance now uses authored hull bounds in carrier-local space:

- Clear overhead if both current position and a two-second linear prediction
  remain more than 50 m above the deck.
- Otherwise require the aircraft to be outside the hull's XZ footprint expanded
  by 30 m, with its entire two-second response segment outside that footprint.
  This permits outward/parallel side, stern and bow exits, while rejecting a
  segment that crosses the carrier even if both endpoints are outside.
- Subtract live carrier point velocity before projecting the response segment.
- Preserve the separate wings-level, recovered-speed, climb-altitude and terrain
  conditions before permitting compact re-entry. No unconditional timer escape,
  physics changes, or increase to the test's 40 km cutoff.
- Missing hull geometry uses conservative fallback bounds; nonfinite aircraft
  position/velocity does not grant clearance.

This short-horizon guard is not a full future-turn collision predictor. It uses
the main hull envelope and clearance margins rather than all deck obstacles.

## Checks

- RecoveryDeckEnvelopeSmoketest PASS: side/stern/bow exits, crossing segments,
  overhead/descent cases, invalid position, four carrier headings, low deck hold.
- GoAroundResponseSmoketest PASS: existing escape checks plus an actual Aircraft
  2 controller leaving sideways wings-level escape and reaching the normal
  re-entry/reference handling (the minimal fixture intentionally has no runway
  references, so it then enters hold).
- DeckFootprintWaveoffSmoketest PASS, 136 checks.
- RecoveryTerrainEscapeSmoketest PASS.
- Test shutdown still reports ObjectDB cleanup warnings; parallel tests also
  report shared diagnostic-log contention. No landing claim is inferred from
  those warnings.

Targeted replay `random_rtb_20260909_140128_seed_20260908`: Aircraft 2, seed
20260908, zero-based case 3. COMPLETE, clean stop after 547.1 simulated seconds,
2.02 s continuously below the stop threshold, zero overall/part damage and zero
body contacts. Maximum carrier distance 7.6 km rather than 40 km; maximum arrest
bank 0.78 degrees; touchdown descent 0.87 m/s. Input hashes and starts verified.
Godot still crashed at shutdown after complete results were saved.

Three wave-offs were recorded. The final wave-off was followed by a wire catch;
the aircraft remained in MISSED_APPROACH at the stopped-result snapshot. This
proves a physical clean stop, not completed deck handling or stow, and late
wave-off/catch state handling merits a separate follow-up. One replay does not
establish a fleet-wide recovery rate.
