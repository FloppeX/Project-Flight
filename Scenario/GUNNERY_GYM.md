# Gunnery Gym

> **Document status:** Specialist test reference. It describes the gunnery harness rather than current project status; reproduce a baseline before treating older optimizer results as current. See the [README](../README.md#development-and-verification).

`GunneryGym.tscn` evaluates the production `Aircraft_5` and `AIPilot` against frozen-physics targets that follow exact analytic paths. It is intended to tune tracking, bank scheduling, pitch/rudder precision aiming, and firing—not aircraft physics.

The default cases include a tail chase, crossing passes, and sustained left/right turns. Targets have deterministic position and velocity, infinite health, zero gun spread is used during tuning, and trials are separated by 14 km so candidates cannot interact.

The fitness strongly rewards real bullet hits, then hit ratio and time spent in a valid ballistic solution. Continuous alignment and predicted miss-distance terms provide a gradient even when a candidate scores zero hits. It penalizes collisions, excessive banking during low-LOS-rate fine tracking, roll reversals, altitude departure, energy loss, and indiscriminate firing. Candidate fitness is 80% mean case score plus 20% worst-case score.

Run a baseline evaluation:

```powershell
python tools/optimize_gunnery_controller.py --evaluate-only
```

Run CMA-ES:

```powershell
python tools/optimize_gunnery_controller.py --generations 8 --population 8
```

Artifacts are written to a new timestamped directory under `gunnery_optimizer_runs/`. `best_gunnery_gains.json` is only a candidate. Compare it with current defaults and then validate it in the continuous carrier intercept scenario before changing production defaults:

```powershell
python tools/optimize_gunnery_controller.py --compare gunnery_optimizer_runs\TIMESTAMP\best_gunnery_gains.json
```

The pilot exposes `get_dogfight_gunnery_metrics()`. The same style of continuous geometry, predicted miss, release-window, and real-impact scoring can be reused for rockets, bombs, and strafing against deterministic ground paths.
