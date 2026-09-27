# Aircraft 14 player autorudder response

The player reported side-to-side hunting with the revised autorudder. A paired real-physics harness reproduced sustained oscillation on Aircraft 14 at a 100 m/s target speed, holding a 20-degree bank after a 6 m/s lateral disturbance.

## Change

`ControlSteering.gd` now reduces Advanced fixed-wing slip feedback according to the aircraft's estimated rudder yaw response. A filtered slip derivative backs off correction as slip approaches centre. Accumulated turn trim unwinds three times faster when the error opposes it, without crossing zero in that accelerated step.

The extra gain reduction fades out as existing high-speed stiffening takes over. An initial version reduced steady turn coordination at 140 m/s; this adjustment restored the baseline result. Existing assist limits, manual-pedal priority, and Simplified/helicopter control paths remain in place.

## Verification

- `AutorudderAdaptiveResponseProbe.tscn`: paired old/new settings at target speeds 65, 100, and 140 m/s on Aircraft 14, with both bank directions, reversal, rollout, and an unconstrained-attitude case. All final matrices passed their relative regression checks.
- At 100 m/s and positive 20-degree held bank, late mean absolute ball error fell from approximately 0.210 g to 0.008 g. Peak-to-peak ball oscillation fell from 0.672 g to below 0.00005 g in the sampled late interval.
- The Aircraft 5 paired 100 m/s matrix and existing held-bank regression passed.
- `FixedWingYawAssistSmoketest` passed manual blending and assist bounds. `FixedWing14YawAssistRuntimeSmoketest` passed at 170 m/s, including full manual override.

The probe holds nonzero bank/pitch and adds only a forward speed-holding force; actual yaw and lateral translation remain simulated. Zero-bank cases leave attitude unconstrained. This reproduces a feedback instability but does not establish the feel of every player manoeuvre or gust condition. At 140 m/s, steady held-bank ball offset remains about 0.112 g, matching the prior high-speed protection behavior. Known shutdown object/resource leak warnings remain in these isolated scene runs.

Run the default matrix with:

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --fixed-fps 60 res://Tests/AutorudderAdaptiveResponseProbe.tscn -- --speed=100
```

Use `--model=5` for the Aircraft 5 comparison. Per-case samples are written under `captures/autorudder_adaptive_<model>_<speed>.jsonl`; result logs for Aircraft 14 are `captures/a14_adaptive<speed>_final.log`.
