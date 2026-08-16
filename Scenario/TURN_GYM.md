# Coordinated-turn optimizer

> **Document status:** Specialist test reference. It describes the turn-gym harness rather than current project status; reproduce a baseline before treating older optimizer results as current. See the [README](../README.md#development-and-verification).

`TurnGym.tscn` evaluates the production `AIPilot` coordinated-turn controller against the
real `Aircraft_5` rigid-body and `SimpleAero` physics. It bypasses mission decisions so the
score answers one narrow question: once a combat pilot has chosen a steep bank, how well do
elevator and rudder turn the aircraft while controlling altitude, sideslip, AoA, stall, and
energy loss?

The gym runs candidates and left/right cases simultaneously in an empty, widely spaced arena.
It exchanges machine-readable JSON through:

- `user://turn_gym_batch.json`
- `user://turn_gym_result.json`

## Run CMA-ES

From the project root:

```powershell
python tools/optimize_turn_controller.py --generations 8 --population 8
```

A short plumbing/smoke run:

```powershell
python tools/optimize_turn_controller.py --generations 1 --population 4 --duration 5 --no-validation
```

Evaluate only the current defaults:

```powershell
python tools/optimize_turn_controller.py --evaluate-only --duration 7
```

Compare a saved candidate against current defaults over all four validation cases:

```powershell
python tools/optimize_turn_controller.py --compare turn_optimizer_runs/<timestamp>/best_turn_gains.json --duration 7
```

Each run writes its inputs, raw per-case metrics, checkpoints, Godot logs, and
`best_turn_gains.json` beneath `turn_optimizer_runs/<timestamp>/`.

The optimizer searches load PI, vertical-speed correction, pitch-rate damping, AoA relief,
sideslip PD, and maximum requested load. Turn rate is the dominant reward. Bank error,
vertical motion, sideslip, load error, excessive AoA, stall, control chatter, saturation, and
large energy loss are penalties.

An evolved file is a candidate, not an automatic production change. Compare its four-case
validation block with the baseline, then copy promising gains into `AIPilot.gd` and run the
full ground-attack → dogfight → landing scenario. The isolated gym cannot measure target
selection, terrain avoidance, weapon employment, or recovery logic.
