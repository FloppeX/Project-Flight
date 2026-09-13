# Deck-footprint wave-off guard — 2026-09-09

## Why

The wider-gear Aircraft 1 replay (`random_rtb_20260909_094548_seed_20260908`,
zero-based case 5) caught a wire approximately 18.1 m off centre, then crashed.
The log does not prove that its wheels initially went over the edge: the first
wing contact occurred at approximately 16.7 m lateral offset while it was moving
inward. Nevertheless, wire reachability alone does not establish a safe landing
and stopping footprint. The old lateral stern guard released after stern entry.

## Change

The shared AIPilot now checks an additional carrier-local outer-deck envelope:

- Obtain both main-wheel contact points and the projected main-gear contact time.
- Project the enabled aircraft body collision geometry into carrier-local XZ,
  including box, sphere, capsule and convex shapes at their current attitude.
- Use the authored carrier hull bounds, with a 1.5 m inset.
- Check wheel support and lateral body clearance at touchdown,
  brake onset, and through a finite arresting stroke. Use live wire payout and
  hard-stop slack (at least 20 m); retain lateral drift rather than assuming
  immediate cable centering.
- Reject an unsafe prediction within four seconds of contact, or earlier if the
  existing roll/lift escape-response budget needs more time. A predicted viable
  wire does not override this check. Existing actual-arrest and minimum-height
  guards remain; this does not command a wave-off after a real wire catch.
- Log `reason=unsafe_deck_footprint` with body and wheel clearance, contact time,
  stopping time and margin in `WAVE_OFF_DECISION`. The limiting constraint now
  includes wheel/body, carrier-local edge (`x_min/max`, `z_min/max`), phase and time.

Fore/aft body overhang is now diagnostic only: a tail beyond the stern does not
imply unsupported main wheels. Main wheels must still remain within both side and
fore/aft bounds through the stop; lateral body clearance remains enforced. This
does not replace the existing vertical stern-clearance guard or model body strikes.

A predicted crossing of the infinite deck-height plane before the stern is not
physical touchdown. Horizontal support checks therefore begin at the later of
that crossing and main-wheel deck entry. `support_start_s` and `entry_delay_s`
record this distinction. Existing vertical stern clearance and response-aware
wire reachability still decide whether descent can be corrected to reach the
deck; the horizontal guard does not assert that such a correction is possible.

No gear, mass, aerodynamic, cable-force or damage changes are included.

## Limits

This is a short-horizon conservative prediction, not a proof of landing safety.
It holds current aircraft attitude and lateral drift, uses a simplified finite
longitudinal braking model and accounts for current carrier-relative point
velocity. It does not integrate future carrier turns, aircraft angular motion,
suspension/roll dynamics, elevator openings or deck obstacles. The bounds are the
outer hull envelope, not a complete support-surface map. Unsupported/missing
geometry returns unknown and leaves the existing guards in control.

## Verification

- `DeckFootprintWaveoffSmoketest`: PASS, 136 checks. Includes all three actual
  Aircraft 1/2/5 scenes, three headings, carrier translation/yaw point velocity,
  both wheel support, wing clearance, outward/inward drift, stopping beyond the
  bow, reverse approach direction, unknown inputs, distant correction window,
  viable-wire override and real-arrest suppression. Added supported stern-entry
  fixtures with actual tail overhang for all three models, deferred deck entry,
  side rejection, and stopping-edge/phase diagnostic assertions. Combined tests
  prove that unreachable vertical undershoots are still rejected independently
  when the horizontal path is safe.
- `GoAroundResponseSmoketest`: PASS.
- `RecoveryDeckEnvelopeSmoketest`: PASS.
- `WireReachabilitySmoketest`: PASS.
- `LandingSightSmoketest`: PASS.
- `RandomRTBBatchSmoketest`: PASS (three models, ten matched starting cases).
- Godot reports existing ObjectDB/resource cleanup warnings on test exit; these
  are not asserted landing outcomes.

First runtime replay: `random_rtb_20260909_113551_seed_20260908`, Aircraft 1,
seed 20260908, zero-based case 5. TIMEOUT after 900 simulated seconds, five
wave-offs, no touchdown or damage. Four rejections were from this new guard;
three had positive wheel support but negative body clearance on near-centred
approaches. This exposed the overly restrictive full-body fore/aft test.
Input hashes verified; engine shutdown crash occurred after complete results.

Second replay: `random_rtb_20260909_120810_seed_20260908`, same Aircraft 1
seed/case. TIMEOUT, five wave-offs, no damage, hashes verified. The new edge log
showed wheel/z_min/touchdown rejections: linear deck-plane crossings short of the
stern, not lateral deck-edge misses. This motivated separating infinite-plane
crossing from physical deck entry.

Third replay: `random_rtb_20260909_121343_seed_20260908`, same Aircraft 1 seed/case,
after the deck-entry correction. CLEAN STOP after 280.7 simulated seconds,
one wave-off, no bolters, 2.02 s continuously stopped, no body contacts or damage
(including all six regional health snapshots). Touchdown class HARD at 3.17 m/s
downward; maximum arrest bank 0.55 degrees. Input hashes and starts verified.
Godot again crashed at shutdown after writing complete results. This is one
successful case, not a deterministic A/B proof or a fleet reliability estimate.

Follow-up launched: four matched cases (zero-based 3–6) per Aircraft 1/2/5,
12 total, seed 20260908, 900 simulated seconds per attempt. The existing
landing-test-progress heartbeat will report its progress and completion.
