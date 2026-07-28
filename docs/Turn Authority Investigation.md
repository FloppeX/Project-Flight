# Turn Authority Investigation (unresolved as of 2026-07-24 night session)

## The actual complaint

User flew manual maneuvers to demonstrate the point: "its possible to fly MUCH tighter turns
than the ai currently does. Part of it is by allowing for a higher angle of attack." Later,
after AIPilot-side changes: "im watching right now and they are pulling 1.6 g" and after further
changes: "im seeing the same shit." This is a direct, in-game, ground-truth observation — not
inferred from logs.

## Ground truth established via direct g-force telemetry (added this session)

Added `_update_g_force_tracking()` to `Scenario/CarrierCombatTestMode.gd` — computes real load
factor the same way the in-cockpit slip ball does: `specific_force = acceleration - gravity`
(acceleration from frame-to-frame `linear_velocity` delta), projected onto the aircraft's local
up axis, divided by 9.80665, filtered with `lerpf(..., delta*4.0)`. Surfaced as `g=` in both
STATE-change diagnostics (`_aircraft_diagnostics`) and the 2s SUMMARY line (`_log_summary`).

**Confirmed via multiple live runs**: sustained ATTACK_POSITIONING turns at bank=50-73° over
60+ seconds show `g` sitting flat between roughly 0.7 and 1.5, NOT correlating with bank angle
at all. A turn at 50° showed the same g as a turn at 72°. Real turn g is NOT scaling with
commanded bank — this is the ground-truth version of "turns feel weak," independent of any
`pitch_input` telemetry (which had been misleading, since it's several steps removed from
actual lift).

## Changes made this session, in order (none independently confirmed to fix the root problem)

1. **`AI/AIPilot.gd`**: Added `turn_feedforward_pitch` as a genuine turn-performance pitch
   demand (not just lift-loss makeup), targeting `normal_flight_turn_target_g` (ended at 2.2)
   via `bank_load_factor = 1/cos(bank)`, scaled to `normal_flight_turn_pitch_max` (0.85).
   Confirmed via debug telemetry this DOES produce pitch_input up to ~0.85-0.9 in the right
   conditions (positive vs_err) but this doesn't matter if the airframe isn't converting
   pitch_input into real lift.
2. **`AI/AIPilot.gd`**: Found and fixed a real bug — this feedforward only applied when
   `in_normal_altitude_hold` (SEARCH/TRANSIT/CLIMBING/RTB), NOT `ATTACK_POSITIONING`/
   `ATTACK_INBOUND` (`in_attack_approach`) where the AI actually spends its hard-bank time.
   Confirmed via `state=` field added to debug prints — this was a genuine dead-code bug, now
   fixed (the condition list only excludes dive/carrier-approach/landing/dogfight/break-off/
   climbing, so ATTACK_POSITIONING is included).
3. **`AI/AIPilot.gd`**: Found the reactive altitude-hold term (`vs_err * pitch_gain *
   bank_compensation`) was persistently fighting/cancelling 50-70% of the turn feedforward
   whenever the aircraft needed even a small altitude correction (near-constant during real
   flight). Added `altitude_term_t` to fade the altitude term's authority (up to 70% reduction)
   as the turn feedforward demands more. Confirmed via debug telemetry this works as coded
   (raw_pitch rose to 0.85-0.9 when vs_err was near zero or positive, stayed lower ~0.1-0.3 when
   vs_err was strongly negative i.e. aircraft needs to descend).
4. **`AI/AIPilot.gd`**: Removed artificial pitch-input ceilings for maneuvering states per
   user's explicit principle: "im not sure why there are hard input limits at all. The ai
   should be able to use the full range of inputs... it should be a judgement call when to use
   them." Deleted `normal_flight_pitch_input_limit` (was 0.75-0.95), unified `pitch_limit` to
   1.0 for all non-precision states (dogfight's hardcoded 0.75 also removed). Precision states
   (carrier approach, formation) keep their own deliberately gentle limits — those are
   intentional, not timidity.
5. **`Aircraft/SimpleAero.gd`**: First lift-ceiling theory — raised `max_lift_ratio` 1.35→4.5,
   reasoning this was the hard cap on `commanded_lift_ratio`. **This theory was WRONG or at
   least incomplete** — `max_lift_ratio` is a ceiling that `aoa_lift_bonus_factor`'s much lower
   effective ceiling never actually reaches, so this change alone did nothing (confirmed: user
   still saw 1.6g after this change alone).
6. **`Aircraft/SimpleAero.gd`**: Second lift-ceiling theory — found
   `aoa_lift_scale = 1.0 + positive_alpha_t * aoa_lift_bonus_factor`, where `positive_alpha_t`
   caps at 1.0 once AoA reaches `aoa_lift_full_deg` (was 10°). With `aoa_lift_bonus_factor=0.6`,
   this caps lift at exactly 1.0+0.6=1.6g **regardless of pitch_input** once past just 10° AoA —
   matching the user's measured 1.6g exactly. Raised `aoa_lift_full_deg` 10°→18° (kept under
   `aoa_stall_start_deg`=22° so stall doesn't start biting before full bonus is reached) and
   `aoa_lift_bonus_factor` 0.6→2.4 (targeting ~3.4g potential, under the 4.5g `max_lift_ratio`
   ceiling). **This is the fix most likely to matter, but it was NOT confirmed to fix the real
   problem** — the very next test run after this change still showed flat ~1g g-force
   regardless of bank, i.e. user's "im seeing the same shit" was AFTER this fix landed.

## What's actually still unknown

- Whether real in-game `alpha_deg` (AoA) is reaching anywhere near the 18° needed to unlock the
  new lift bonus during these turns. Attempted to log this directly via
  `simple_aero.get("alpha_deg")` in the scenario script's diagnostics — **this attempt failed**:
  the property lookup returned null/absent despite `simple_aero` being confirmed as a valid
  `SimpleAero` (`class_name SimpleAero`) instance. Tried both the `in` operator
  (`"alpha_deg" in simple_aero_variant` — always false) and direct `.get()` with a null check
  (`simple_aero_variant.get("alpha_deg")` — returned null). Root cause of this specific
  telemetry failure was NOT found before stopping. `alpha_deg` and `commanded_lift_ratio` are
  genuinely declared as instance `var`s in `SimpleAero.gd` (not `@export`, not local-only)
  around line 167-169, so this lookup SHOULD work — something about how Godot exposes plain
  (non-exported) script member vars via `.get()`/`in` from an external script may be the
  culprit, or there may be a totally different explanation not yet considered.
- Whether the g-force measurement itself has a subtle flaw. The math is standard
  (specific-force-on-local-up, same approach as `HUD/Instruments/SlipBallModule.gd` and
  `ControlSteering.gd`'s rudder-assist slip estimator, both of which already exist and work in
  this codebase) but has NOT been cross-validated against a known-good case (e.g., logging g
  during a deliberate, controlled level 1g flight to confirm it reads ~1.0, or during a known
  dive pullout to confirm it spikes correctly). It DID show variation (0.65 during a bomb dive
  at fpa=-18°, 1.77 during climb) so it's not obviously broken, but a systematic bug that
  flattens the BANK-correlated component specifically (while leaving other accelerations
  visible) hasn't been ruled out.
- Whether AIPilot's commanded pitch_input is actually reaching the airframe as expected during
  ATTACK_POSITIONING specifically (confirmed reaching 0.85-0.9 in some frames) — if pitch_input
  is right but g still doesn't respond, the bug is squarely in SimpleAero.gd's lift chain, not
  AIPilot.

## Recommended next step

1. **Add a `print()` directly inside `SimpleAero.gd`'s `_physics_process`** (not via
   cross-script `.get()`), gated to the player's own aircraft or a debug flag, showing
   `alpha_deg`, `commanded_lift_ratio`, `positive_alpha_t`, and `aoa_lift_scale` every N frames.
   This bypasses the property-lookup mystery entirely and gives ground truth on whether AoA is
   reaching the new 18° threshold and whether the lift math computes what's expected.
2. Only after confirming AoA/lift math is behaving as designed should further AIPilot-side pitch
   tuning resume — there's no point tuning the AI's commanded pitch further if the airframe
   isn't converting it into lift correctly.
3. Consider whether `commanded_lift_ratio`'s clamp to `[0.0, lift_ceiling]` could be getting a
   near-zero `zero_aoa_lift_ratio` multiplier (speed-based,
   `pow(speed/aligned_level_speed, 2.0)`) that suppresses everything else — if the aircraft's
   speed during these turns is well under `aligned_level_speed_mps` (60.0), `zero_aoa_lift_ratio`
   could be small enough that even a large `aoa_lift_scale` multiplier doesn't produce much
   absolute lift. Observed turn speeds in logs were often 50-70 m/s, right around that
   threshold — worth checking `zero_aoa_lift_ratio`'s actual value directly too.

## Related note (different investigation, same conversation thread)

Earlier in the same session, a related but DIFFERENT problem (rudder/ball-centering) was
resolved by realizing the player's "Airplane Rudder Assist" setting defaults to OFF in the
pause menu — not relevant to this g-force problem, but easy to conflate since both came from the
same "turns feel wrong" conversation thread.
