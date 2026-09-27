"""Summarize a running or completed headless RTB batch; preserve failures in denominators."""
import argparse
import csv
import json
import math
import os
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]


def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    index = (len(values) - 1) * fraction
    low = int(index)
    return values[low] + (values[min(low + 1, len(values) - 1)] - values[low]) * (index - low)


def wilson(successes, count):
    if not count:
        return [0, 1]
    z = 1.96
    p = successes / count
    scale = 1 + z * z / count
    center = (p + z * z / (2 * count)) / scale
    width = z * math.sqrt(p * (1 - p) / count + z * z / (4 * count * count)) / scale
    return [center - width, center + width]


def summarize(directory):
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8-sig"))
    rows, workers = [], []
    user_data = Path(os.environ["APPDATA"]) / "Godot/app_userdata/Land Carrier"
    for worker in manifest["workers"]:
        strict = press = 0
        minimum_health = None
        completed = False
        for line in Path(worker["stdout"]).read_text(encoding="utf-8", errors="replace").splitlines():
            if "[AIPilot RECOVERY_HANDOFF] accepted" in line:
                strict += 1
            elif "[AIPilot RECOVERY_HANDOFF] press_commit" in line:
                press += 1
            if not line.startswith("RECOVERY_EVENT "):
                continue
            try:
                event = json.loads(line[len("RECOVERY_EVENT "):])
            except json.JSONDecodeError:  # Live writer can leave a partial last line.
                continue
            data = event["data"]
            if event["event"] == "RTB_TRIAL":
                strict = press = 0
                minimum_health = None
            elif event["event"] == "HEALTH_CHANGE":
                health = data["health"]
                minimum_health = health if minimum_health is None else min(minimum_health, health)
            elif event["event"] == "COMPLETE":
                completed = True
            elif event["event"] == "RTB_TRIAL_RESULT":
                record = data["record"]
                initial = record["initial_health"]
                minimum = min(record["health"], initial if minimum_health is None else minimum_health)
                start = record["launched_at"]
                rows.append(dict(
                    model=data["model"], trial=data["trial"], profile=data["case"]["name"],
                    repeat=data["case"]["repeat"], side=data["case"]["side"], outcome=data["outcome"],
                    caught=record["caught"], stowed=record["stowed"], destroyed=record["destroyed"],
                    unavailable=record["unavailable"], initial_health=initial, minimum_health=minimum,
                    health_loss_percent=100 * (initial - minimum) / initial,
                    duration_s=data["duration_s"],
                    wire_s=record.get("caught_at", start) - start if record["caught"] else None,
                    stow_s=record.get("stowed_at", start) - start if record["stowed"] else None,
                    missed_approaches=record.get("missed_approaches", 0),
                    strict_handoffs=strict, press_handoffs=press,
                ))
        status_path = user_data / (worker["label"] + "_status.json")
        try:
            status = json.loads(status_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            status = {}
        errors = Path(worker["stderr"]).read_text(encoding="utf-8", errors="replace")
        workers.append(dict(model=worker["model"], complete=completed,
                            script_errors=errors.count("SCRIPT ERROR"), status=status))
    aggregate = []
    for model in [1, 2, 5, 14]:
        subset = [row for row in rows if row["model"] == model]
        stowed = [row for row in subset if row["stowed"]]
        aggregate.append(dict(model=model, completed=len(subset), caught=sum(r["caught"] for r in subset),
            stowed=len(stowed), undamaged_stowed=sum(r["health_loss_percent"] < 0.01 for r in stowed),
            lost=sum(r["outcome"] == "LOST" for r in subset),
            timeout=sum(r["outcome"] == "TIMEOUT" for r in subset),
            wire_median_s=median([r["wire_s"] for r in subset if r["caught"]]) if any(r["caught"] for r in subset) else None,
            stow_median_s=median([r["stow_s"] for r in stowed]) if stowed else None,
            stow_p90_s=percentile([r["stow_s"] for r in stowed], 0.9),
            retry_trials=sum(r["missed_approaches"] > 0 for r in subset),
            strict_handoffs=sum(r["strict_handoffs"] for r in subset),
            press_handoffs=sum(r["press_handoffs"] for r in subset),
            stow_wilson_95=wilson(len(stowed), len(subset))))
    output = dict(completed=len(rows), expected=4 * manifest["trials_per_model"],
                  all_workers_complete=all(w["complete"] for w in workers), models=aggregate, workers=workers, trials=rows)
    (directory / "summary.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    if rows:
        with (directory / "trials.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    lines = ["# RTB batch results", "", f"Completed: {len(rows)}/{output['expected']}.", "",
             "| Aircraft | Attempts | Caught | Stowed | Undamaged stows | Lost | Timeout | Median wire s | Median stow s | Retry trials | Strict / press handoffs |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |"]
    for item in aggregate:
        wire = "—" if item["wire_median_s"] is None else f"{item['wire_median_s']:.1f}"
        stow = "—" if item["stow_median_s"] is None else f"{item['stow_median_s']:.1f}"
        lines.append(f"| {item['model']} | {item['completed']} | {item['caught']} | {item['stowed']} | {item['undamaged_stowed']} | {item['lost']} | {item['timeout']} | {wire} | {stow} | {item['retry_trials']} | {item['strict_handoffs']} / {item['press_handoffs']} |")
    lines += ["", "Timing medians include successful catches/stows only; failures remain in the attempt counts. Undamaged means no recorded health loss during the trial, not merely repaired health at storage. Retry counts are sampled at 1 Hz; strict/press handoffs come from controller event logs.", "",
              "Five arrival profiles, five repeats per model, alternating sides. Normal 60 Hz physics at uncapped headless speed; authored handling and live weather. This is one carrier/terrain setup with fresh airborne spawns, not a random sample of all missions, a combat sortie, or a launch test. Models share the profile matrix but are not exact weather/trajectory replays. Wilson intervals in summary.json describe sample size only; correlated repeated cases limit population inference."]
    (directory / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"completed":len(rows), "models":aggregate,
                      "workers":[{"model":w["model"], "complete":w["complete"], "script_errors":w["script_errors"],
                                  "sim_time":w["status"].get("elapsed_s"), "state":w["status"].get("aircraft", [{}])[0].get("state")} for w in workers]}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", nargs="?")
    args = parser.parse_args()
    summarize(Path(args.directory) if args.directory else Path((ROOT / "logs/active_rtb_batch.txt").read_text().strip()))
