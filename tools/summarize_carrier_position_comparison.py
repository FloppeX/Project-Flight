"""Summarize the small paired carrier-position experiment, including failed arrivals."""
import json
import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
directory = Path((ROOT / "logs/active_position_comparison.txt").read_text().strip())
manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8-sig"))
workers = []
for worker in manifest["workers"]:
    results, handoffs, checks, arrivals = [], [], [], []
    complete = False
    current_trial = 0
    for line in (directory / (worker["location"] + ".log")).read_text(encoding="utf-8", errors="replace").splitlines():
        if "[AIPilot RECOVERY_HANDOFF]" in line:
            values = dict(re.findall(r"(remaining|lat|vert|track|fpa_err|bank|speed)=([+-]?[\d.]+)", line))
            handoffs.append({"trial": current_trial, "kind": "press" if "press_commit" in line else "accepted" if "] accepted" in line else "rejected",
                             **{k: float(v) for k, v in values.items()}})
        if not line.startswith("RECOVERY_EVENT "):
            continue
        try:
            event = json.loads(line[len("RECOVERY_EVENT "):])
        except json.JSONDecodeError:
            continue
        if event["event"] == "POSITION_CHECK": checks.append(event["data"])
        if event["event"] == "RTB_TRIAL":
            arrivals.append(event["data"])
            current_trial = event["data"]["trial"]
        if event["event"] == "RTB_TRIAL_RESULT": results.append(event["data"])
        if event["event"] == "COMPLETE": complete = True
    status_file = Path(os.environ["APPDATA"]) / "Godot/app_userdata/Land Carrier" / (worker["label"] + "_status.json")
    try:
        status = json.loads(status_file.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        status = {}
    errors = (directory / (worker["location"] + "_errors.log")).read_text(encoding="utf-8", errors="replace")
    workers.append({"location": worker["location"], "complete": complete, "position_checks": checks,
                    "arrivals": arrivals, "results": results, "handoffs": handoffs,
                    "script_errors": errors.count("SCRIPT ERROR"), "status": status})
    if complete:
        for suffix in [".jsonl", "_status.json"]:
            source = status_file.parent / (worker["label"] + suffix)
            if source.exists(): shutil.copy2(source, directory / source.name)

summary = {"complete": all(w["complete"] for w in workers), "workers": workers}
(directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
lines = ["# Carrier-position comparison", "", "Aircraft 5; two arrival profiles at each of two positions. Wind field disabled in both, same carrier heading, shared above-deck spawn height, speed and relative heading. Authored flight-control settings unchanged. Physics runs at 60 Hz, uncapped headlessly.", "",
         "| Position | Arrival | Outcome | Caught | Stowed | Duration s | Missed approaches |", "| --- | --- | --- | --- | --- | ---: | ---: |"]
for worker in workers:
    for result in worker["results"]:
        record = result["record"]
        lines.append(f"| {worker['location']} | {result['case']['name']} | {result['outcome']} | {record['caught']} | {record['stowed']} | {result['duration_s']:.1f} | {record['missed_approaches']} |")
lines += ["", "## First handoff attempt per arrival", "",
          "| Position | Trial | Decision | Vertical error m | Lateral error m | Track error deg | Bank deg |",
          "| --- | ---: | --- | ---: | ---: | ---: | ---: |"]
for worker in workers:
    seen = set()
    for handoff in worker["handoffs"]:
        if handoff["trial"] in seen: continue
        seen.add(handoff["trial"])
        lines.append(f"| {worker['location']} | {handoff['trial']} | {handoff['kind']} | {handoff.get('vert', '—')} | {handoff.get('lat', '—')} | {handoff.get('track', '—')} | {handoff.get('bank', '—')} |")
lines += ["", "Position validation must show obstructed=false and clear=true for corridor_clear. The clear site is near (-144, 525, -2375); the obstructed site is near (-21, 522, 2). This is a four-attempt placement comparison, not a fleet reliability estimate or exact checkpoint replay. A clear nominal final corridor does not guarantee an aligned arc exit, a clear entire recovery circuit or successful flight control. Timeouts are 900 simulated seconds per uncaught attempt. Raw results, placement checks and handoff measurements are in summary.json."]
(directory / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps({"complete": summary["complete"], "workers": [{"location": w["location"], "complete": w["complete"], "results": [(r["case"]["name"], r["outcome"]) for r in w["results"]], "sim_time": w["status"].get("elapsed_s"), "script_errors": w["script_errors"]} for w in workers]}, indent=2))
