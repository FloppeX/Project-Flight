#!/usr/bin/env python3
"""CMA-ES tuner for the real Aircraft_5 / AIPilot coordinated-turn controller."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

import numpy as np


PARAMETERS = (
    ("load_kp", 0.05, 0.90, 0.74211577),
    ("load_ki", 0.02, 1.20, 0.32882861),
    ("vertical_accel_gain", 0.04, 8.00, 5.0),
    ("vertical_accel_damping", 0.50, 8.00, 5.0),
    ("pitch_rate_damping", 0.00, 0.40, 0.105681),
    ("aoa_soft_deg", 12.0, 22.0, 18.16582181),
    ("aoa_margin_deg", 2.0, 12.0, 3.26345533),
    ("aoa_relief_gain", 0.02, 0.60, 0.0609993),
    ("sideslip_kp", 0.10, 7.00, 4.0),
    ("sideslip_kd", 0.00, 0.25, 0.25),
    ("max_load_g", 2.00, 4.50, 4.5),
)

TRAINING_CASES = (
    {"name": "left_corner", "bank_deg": -72.0, "speed_mps": 82.0},
    {"name": "right_slow", "bank_deg": 72.0, "speed_mps": 65.0},
    {"name": "left_fast", "bank_deg": -72.0, "speed_mps": 105.0},
)

VALIDATION_CASES = (
    {"name": "left_corner", "bank_deg": -72.0, "speed_mps": 82.0},
    {"name": "right_corner", "bank_deg": 72.0, "speed_mps": 82.0},
    {"name": "left_fast", "bank_deg": -72.0, "speed_mps": 105.0},
    {"name": "right_slow", "bank_deg": 72.0, "speed_mps": 65.0},
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Evolve AIPilot coordinated-turn gains against real Godot aircraft physics."
    )
    parser.add_argument("--generations", type=int, default=8)
    parser.add_argument("--population", type=int, default=8)
    parser.add_argument("--duration", type=float, default=7.0, help="Seconds per training case.")
    parser.add_argument("--warmup", type=float, default=1.5)
    parser.add_argument("--sigma", type=float, default=0.22, help="Initial CMA step in normalized space.")
    parser.add_argument("--seed", type=int, default=20260725)
    parser.add_argument("--timeout", type=float, default=240.0, help="Godot timeout per generation.")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--godot",
        type=Path,
        default=Path(r"C:\Godot\Godot_v4.6.2-stable_win64.exe"),
    )
    parser.add_argument(
        "--userdata",
        type=Path,
        default=Path(os.environ.get("APPDATA", ".")) / "Godot" / "app_userdata" / "Land Carrier",
    )
    parser.add_argument("--no-validation", action="store_true")
    parser.add_argument(
        "--evaluate-only",
        action="store_true",
        help="Evaluate the current in-code gains; do not evolve.",
    )
    parser.add_argument(
        "--compare",
        type=Path,
        help="Evaluate current defaults against a best_turn_gains.json candidate; do not evolve.",
    )
    return parser.parse_args()


def normalized_baseline() -> np.ndarray:
    return np.array(
        [(default - low) / (high - low) for _, low, high, default in PARAMETERS],
        dtype=float,
    )


def decode(vector: np.ndarray) -> dict[str, float]:
    raw: dict[str, float] = {}
    for value, (name, low, high, _) in zip(vector, PARAMETERS):
        raw[name] = low + float(np.clip(value, 0.0, 1.0)) * (high - low)
    margin = raw.pop("aoa_margin_deg")
    raw["aoa_hard_deg"] = raw["aoa_soft_deg"] + margin
    return {key: round(value, 8) for key, value in raw.items()}


def with_duration(cases: tuple[dict[str, Any], ...], duration: float) -> list[dict[str, Any]]:
    return [{**case, "duration_s": duration} for case in cases]


class TurnGym:
    def __init__(self, args: argparse.Namespace, run_dir: Path) -> None:
        self.args = args
        self.run_dir = run_dir
        self.batch_path = args.userdata / "turn_gym_batch.json"
        self.result_path = args.userdata / "turn_gym_result.json"
        args.userdata.mkdir(parents=True, exist_ok=True)

    def evaluate(
        self,
        label: str,
        gain_sets: list[dict[str, float]],
        cases: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        candidates = [
            {"id": f"{label}_{index:03d}", "gains": gains}
            for index, gains in enumerate(gain_sets)
        ]
        batch = {
            "schema_version": 1,
            "candidates": candidates,
            "cases": cases,
            "warmup_s": self.args.warmup,
        }
        self.batch_path.write_text(json.dumps(batch, indent=2), encoding="utf-8")
        old_mtime = self.result_path.stat().st_mtime_ns if self.result_path.exists() else -1
        log_path = self.run_dir / f"{label}_godot.log"
        command = [
            str(self.args.godot),
            "--headless",
            "--path",
            str(self.args.project),
            "--scene",
            "res://Scenario/TurnGym.tscn",
            "--log-file",
            str(log_path),
        ]
        started = time.monotonic()
        completed = subprocess.run(
            command,
            cwd=self.args.project,
            timeout=self.args.timeout,
            check=False,
        )
        wall_s = time.monotonic() - started
        if completed.returncode != 0:
            raise RuntimeError(
                f"Godot returned {completed.returncode}; inspect {log_path}"
            )
        if not self.result_path.exists() or self.result_path.stat().st_mtime_ns <= old_mtime:
            raise RuntimeError(f"Godot produced no fresh result; inspect {log_path}")
        output = json.loads(self.result_path.read_text(encoding="utf-8"))
        results = output.get("candidate_results", [])
        expected_ids = [candidate["id"] for candidate in candidates]
        actual_ids = [result.get("id") for result in results]
        if actual_ids != expected_ids:
            raise RuntimeError(
                f"Result IDs do not match batch: expected {expected_ids}, got {actual_ids}"
            )
        (self.run_dir / f"{label}_result.json").write_text(
            json.dumps(output, indent=2), encoding="utf-8"
        )
        print(f"{label}: {len(candidates)} candidates in {wall_s:.1f}s")
        return results


def print_ranked(results: list[dict[str, Any]], limit: int = 5) -> None:
    ranked = sorted(results, key=lambda item: float(item.get("fitness", -math.inf)), reverse=True)
    for rank, result in enumerate(ranked[:limit], start=1):
        print(
            f"  {rank:>2}. {result.get('id')}: "
            f"fitness={float(result.get('fitness', -1000.0)):.3f}"
        )


def main() -> int:
    args = parse_args()
    if not args.godot.exists():
        print(f"Godot executable not found: {args.godot}", file=sys.stderr)
        return 2
    if args.population < 2 and not (args.evaluate_only or args.compare):
        print("--population must be at least 2", file=sys.stderr)
        return 2
    if args.generations < 1 and not (args.evaluate_only or args.compare):
        print("--generations must be at least 1", file=sys.stderr)
        return 2

    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = args.project / "turn_optimizer_runs" / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    gym = TurnGym(args, run_dir)
    baseline_vector = normalized_baseline()
    baseline_gains = decode(baseline_vector)

    if args.compare:
        candidate_document = json.loads(args.compare.read_text(encoding="utf-8"))
        candidate_gains = candidate_document.get("gains", candidate_document)
        if not isinstance(candidate_gains, dict):
            raise ValueError(f"No gains object found in {args.compare}")
        results = gym.evaluate(
            "comparison",
            [baseline_gains, candidate_gains],
            with_duration(VALIDATION_CASES, args.duration),
        )
        print("Comparison (current defaults, supplied candidate):")
        print_ranked(results, limit=2)
        comparison = {"baseline": results[0], "candidate": results[1]}
        (run_dir / "comparison.json").write_text(
            json.dumps(comparison, indent=2), encoding="utf-8"
        )
        print(f"Results: {run_dir}")
        return 0

    if args.evaluate_only:
        results = gym.evaluate(
            "baseline",
            [baseline_gains],
            with_duration(VALIDATION_CASES, args.duration),
        )
        print_ranked(results)
        (run_dir / "best_turn_gains.json").write_text(
            json.dumps({"fitness": results[0]["fitness"], "gains": baseline_gains}, indent=2),
            encoding="utf-8",
        )
        print(f"Results: {run_dir}")
        return 0

    dimension = len(PARAMETERS)
    population = args.population
    parents = population // 2
    weights = np.log(parents + 0.5) - np.log(np.arange(1, parents + 1))
    weights /= weights.sum()
    mueff = 1.0 / np.square(weights).sum()
    cc = (4.0 + mueff / dimension) / (dimension + 4.0 + 2.0 * mueff / dimension)
    cs = (mueff + 2.0) / (dimension + mueff + 5.0)
    c1 = 2.0 / ((dimension + 1.3) ** 2 + mueff)
    cmu = min(
        1.0 - c1,
        2.0 * (mueff - 2.0 + 1.0 / mueff) / ((dimension + 2.0) ** 2 + mueff),
    )
    damps = 1.0 + 2.0 * max(0.0, math.sqrt((mueff - 1.0) / (dimension + 1.0)) - 1.0) + cs
    chi_n = math.sqrt(dimension) * (
        1.0 - 1.0 / (4.0 * dimension) + 1.0 / (21.0 * dimension * dimension)
    )

    rng = np.random.default_rng(args.seed)
    mean = baseline_vector.copy()
    sigma = args.sigma
    covariance = np.eye(dimension)
    pc = np.zeros(dimension)
    ps = np.zeros(dimension)
    best_fitness = -math.inf
    best_gains = baseline_gains
    history: list[dict[str, Any]] = []
    training_cases = with_duration(TRAINING_CASES, args.duration)

    for generation in range(args.generations):
        eigenvalues, basis = np.linalg.eigh(covariance)
        scales = np.sqrt(np.maximum(eigenvalues, 1e-12))
        transform = basis @ np.diag(scales)
        normal_steps = rng.standard_normal((dimension, population))
        correlated_steps = transform @ normal_steps
        vectors = np.clip(mean[:, None] + sigma * correlated_steps, 0.0, 1.0)
        gain_sets = [decode(vectors[:, index]) for index in range(population)]
        label = f"generation_{generation:03d}"
        results = gym.evaluate(label, gain_sets, training_cases)
        fitness = np.array([float(item["fitness"]) for item in results])
        order = np.argsort(fitness)[::-1]
        print_ranked(results)

        old_mean = mean.copy()
        selected_vectors = vectors[:, order[:parents]]
        mean = np.clip(selected_vectors @ weights, 0.0, 1.0)
        selected_steps = (selected_vectors - old_mean[:, None]) / max(sigma, 1e-12)
        weighted_step = selected_steps @ weights
        invsqrt = basis @ np.diag(1.0 / scales) @ basis.T
        ps = (1.0 - cs) * ps + math.sqrt(cs * (2.0 - cs) * mueff) * (invsqrt @ weighted_step)
        norm_ps = np.linalg.norm(ps)
        hsig_threshold = (1.4 + 2.0 / (dimension + 1.0)) * chi_n
        hsig_denominator = math.sqrt(1.0 - (1.0 - cs) ** (2.0 * (generation + 1)))
        hsig = 1.0 if norm_ps / max(hsig_denominator, 1e-12) < hsig_threshold else 0.0
        pc = (1.0 - cc) * pc + hsig * math.sqrt(cc * (2.0 - cc) * mueff) * weighted_step
        rank_mu = sum(
            weight * np.outer(selected_steps[:, index], selected_steps[:, index])
            for index, weight in enumerate(weights)
        )
        covariance = (
            (1.0 - c1 - cmu) * covariance
            + c1 * (np.outer(pc, pc) + (1.0 - hsig) * cc * (2.0 - cc) * covariance)
            + cmu * rank_mu
        )
        covariance = (covariance + covariance.T) * 0.5
        sigma *= math.exp((cs / damps) * (norm_ps / chi_n - 1.0))
        sigma = float(np.clip(sigma, 0.025, 0.6))

        winner_index = int(order[0])
        generation_best = float(fitness[winner_index])
        if generation_best > best_fitness:
            best_fitness = generation_best
            best_gains = gain_sets[winner_index]
        history.append(
            {
                "generation": generation,
                "best_fitness": generation_best,
                "mean_fitness": float(fitness.mean()),
                "sigma": sigma,
                "best_gains": gain_sets[winner_index],
            }
        )
        checkpoint = {
            "seed": args.seed,
            "parameters": PARAMETERS,
            "history": history,
            "best_training_fitness": best_fitness,
            "best_gains": best_gains,
        }
        (run_dir / "checkpoint.json").write_text(
            json.dumps(checkpoint, indent=2), encoding="utf-8"
        )

    validation: dict[str, Any] = {}
    if not args.no_validation:
        validation_results = gym.evaluate(
            "validation",
            [baseline_gains, best_gains],
            with_duration(VALIDATION_CASES, max(args.duration, 7.0)),
        )
        print("Validation (current defaults, evolved winner):")
        print_ranked(validation_results, limit=2)
        validation = {
            "baseline": validation_results[0],
            "evolved": validation_results[1],
        }

    final = {
        "seed": args.seed,
        "generations": args.generations,
        "population": args.population,
        "best_training_fitness": best_fitness,
        "gains": best_gains,
        "validation": validation,
        "note": "Candidate only; validate in the integrated combat scenario before changing defaults.",
    }
    best_path = run_dir / "best_turn_gains.json"
    best_path.write_text(json.dumps(final, indent=2), encoding="utf-8")
    print(f"Best candidate: {best_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
