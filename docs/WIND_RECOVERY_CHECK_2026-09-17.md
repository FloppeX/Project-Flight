# Wind and recovery check — 2026-09-17

**Four successful takeoffs; zero confirmed landings. Full-cycle recovery failed validation.**

## Results

| Run | Takeoffs | Wire catches | Stored | Outcome |
|---|---:|---:|---:|---|
| Default wind, gusts and turbulence | 2/2 | 0/2 | 0/2 | Both alive at 100% health after 900 seconds of recovery attempts; repeatedly went around. |
| Calm comparison | 2/2 | 0/2 | 0/2 | Both collided with terrain during RTB, at simulation times 320.32 and 321.17 seconds. |

The wind case produced 6 rejected final handoffs. At roughly 1 km remaining, the aircraft were 176–425 m off-centre and 267–301 m above the required path. The gates allowed approximately 55 m lateral error and at most 37 m above the path. The go-around decision was appropriate. Both aircraft retained approximately 29% fuel when the bounded run ended.

In calm air, both losses were recorded through `_evaluate_terrain_impact`, with fuselage contacts against terrain chunks. Neither aircraft reached final approach. The recovery problem therefore cannot be attributed solely to wind.

## Weather measurements

Default mean air velocity: `(4, 0, 2)` m/s. Gust amplitudes: `(3, 1.5, 3)` m/s. Turbulence amplitudes: `(1.5, 1, 1.5)` m/s.

- Sampled local wind speed: **0.93–8.38 m/s**.
- Largest sampled airspeed/ground-speed magnitude difference: **7.63 m/s**.
- Largest sampled differential gust torque: **1645 N·m**.
- Calm comparison: zero wind velocity, zero wind-induced airspeed difference and zero differential gust torque.

This confirms weather affects aerodynamic inputs and moments. It does not establish acceptable landing behaviour in wind.

## Method and limits

`Tests/WindyFullRecoveryProbe.gd` extends the existing full-scenario observer. It uses the real main scene, normal hangar/elevator/catapult launches, carrier navigation, flight recall, recovery routing, final gates, arresting wires and storage signals. Both airframes in each run were actually `Aircraft_5.tscn`; the historical hangar names do not reliably identify the underlying scene.

These were accelerated **headless physical simulation** runs at 60 physics ticks/second, not rendered visual acceptance tests. Both used placement seed 20260911 and normal `open_canyons` terrain. Carrier movement and recovery supervision remained active, so subsequent trajectories and carrier travel differed; this is an operational comparison, not a perfectly matched trajectory experiment.

Enemy operations/base spawning were disabled only in the diagnostic harness, and neither clean run recorded combat damage. An earlier normal-world trial suffered enemy attacks and is excluded above. Autosaving was disabled. No flight tuning, forced catches, aircraft repositioning or relaxed final gates were used.

RTB terrain avoidance and approach capture/stabilisation need investigation before weakening final gates or attributing failures to wind strength. No aircraft landed, so arresting-wire behaviour and the post-landing tractor/storage handoff remain unverified by these runs. Production flight settings were left unchanged.

## Evidence

- [Wind console](../captures/wind_isolated.log), [detailed events](../captures/wind_isolated_events.jsonl), [final status](../captures/wind_isolated_status.json)
- [Calm console](../captures/calm_isolated.log), [detailed events](../captures/calm_isolated_events.jsonl), [final status](../captures/calm_isolated_status.json)

Run `Tests/WindyFullRecoveryProbe.gd` with Godot `--headless --path . --fixed-fps 60 --script res://Tests/WindyFullRecoveryProbe.gd -- --label=wind_isolated`. For the control, use `--label=calm_isolated --calm` after `--`. The probe requires a confirmed wire catch and storage for both aircraft to pass; loss, timeout or incomplete recovery fails.
