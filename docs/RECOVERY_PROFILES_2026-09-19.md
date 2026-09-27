# Short recovery circuit and aircraft-specific settings

Aircraft need individual landing settings, but settings alone did not explain the failures. This repair keeps the 450 m recovery turn radius and existing final acceptance limits.

## Changes

- Recovery turn lift estimates now include the actual loaded mass and flap lift multiplier from SimpleAero. Previously the pilot could request a turn using unloaded wing capacity while the physics applied the loaded mass. The change is restricted to RECOVERY_APPROACH and PRE_LANDING.
- Straight-line capture starts immediately after the turn, independently of whether the landing sight can yet forecast a wire intersection. It brakes sideways motion before the final handoff, using the existing early-capture bank limit.
- The default retry cooldown is 20 seconds. Aircraft 14 can requeue after exhausting a retry batch instead of remaining indefinitely in recovery hold. An explicit zero still supports a supervised hold; retries do not grant deck clearance.
- Final throttle no longer treats the inactive formation speed cap (-1) as a commanded speed. Positive finite caps retain their existing meaning.
- Aircraft 2 has an individual recovery profile: AI clean stall reference 50 m/s, near-approach speed 62 m/s, final speed tapering from 66 to 62 m/s. Its flap drag multiplier is reduced from 3.55 to 2.0. This affects Aircraft 2 whenever its flaps are deployed, including manual flight; clean-flight drag is unchanged.

## Why Aircraft 2 differs

The tested Aircraft 2 weighs 2,200 kg with an unloaded lift-reference mass of 1,200 kg. Its loaded lift scale before flap augmentation is about 0.545, compared with approximately 0.783 for Aircraft 1, 0.643 for Aircraft 5, and 0.706 for Aircraft 14. A stall threshold by itself is not a sufficient landing speed: the wing must support the current weight at the intended approach attitude, with enough thrust left to sustain that speed.

At 62 m/s with gear and flaps, Aircraft 2's old forward-drag settings imply approximately 8.1 kN before additional drag, above its 7 kN engine thrust. The new flap multiplier reduces that component to approximately 4.6 kN. These are estimates from the game's equations, not a real-world aerodynamic certification or a guarantee under every load and wind condition.

## Investigation evidence

The earlier clear-site baseline is in `logs/clear_site_fleet_20260919_101352/report.md`: Aircraft 1 and 5 stowed 2/2 each, while Aircraft 2 and 14 timed out 2/2 each.

Candidate runs are retained, including failures:

- `logs/line_capture_20260919_122616`: independent line capture; Aircraft 14 stowed, Aircraft 2 timed out.
- `logs/handoff_braking_20260919_123020` and `logs/line_authority_20260919_123238`: handoff braking and existing bank authority trials.
- `logs/loaded_recovery_20260919_123654`: loaded-lift correction produced strict handoffs for both models, but Aircraft 2 lost speed and crashed at the stern; Aircraft 14 stowed undamaged.
- `logs/aircraft2_speed_20260919_123948`: higher speed commands alone did not resolve Aircraft 2's recovery.
- `logs/aircraft2_profile_20260919_124235`: reduced flap drag allowed Aircraft 2 to catch and stow undamaged after two retries, before correcting the inactive formation speed cap.

## Validation

Focused headless tests pass: RecoveryLineCaptureSmoketest, PreLandingLateralSmoketest, LandingSightSmoketest, RecoveryCatchOwnershipSmoketest, and CompactRecoveryVectorSmoketest. The loaded-lift and retry check loads all nine authored fixed-wing scenes. These checks do not establish full-flight reliability.

The final bounded comparison is `logs/recovery_profiles_20260919_124743/report.md`: two arrivals per aircraft, calm weather, a stationary carrier at the same clear pose as the baseline, 60 Hz fixed simulation. Source hashes and raw events are retained in that directory. The initial realtime workers were stopped and restarted with fixed simulation timing for faster execution; their partial logs are retained separately and excluded from the results.

All eight trials caught a wire and stowed at full health, with no script errors. Seven had no missed approaches; Aircraft 5's standard-inbound trial had one. Five handoffs passed the strict gate and three used the existing permissive gate, so universally stabilized final entry is still unfinished. Aircraft 2 took 80.0/159.4 seconds to wire and 116.6/197.8 seconds to stow. Source hashes matched throughout the final run.

This comparison does not cover wind, moving carriers, concurrent recovery queues, combat damage, alternate loads, or pilot feel. No claim of general landing reliability follows from eight trials.
