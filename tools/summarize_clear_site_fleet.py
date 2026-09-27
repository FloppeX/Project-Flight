"""Preserve all outcomes from the bounded clear-site fleet assessment."""
import json
import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
directory = Path((ROOT / "logs/active_clear_site_fleet.txt").read_text().strip())
manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8-sig"))
userdata = Path(os.environ["APPDATA"]) / "Godot/app_userdata/Land Carrier"
workers = []
for worker in manifest["workers"]:
    events = []
    stdout = (directory / f"aircraft_{worker['model']}.log").read_text(encoding="utf-8", errors="replace")
    for line in stdout.splitlines():
        if line.startswith("RECOVERY_EVENT "):
            try:
                events.append(json.loads(line.removeprefix("RECOVERY_EVENT ")))
            except json.JSONDecodeError:
                pass
    results = [e["data"] for e in events if e["event"] == "RTB_TRIAL_RESULT"]
    checks = [e["data"] for e in events if e["event"] == "POSITION_CHECK"]
    completion = [e["data"] for e in events if e["event"] == "COMPLETE"]
    try:
        status = json.loads((userdata / (worker["label"] + "_status.json")).read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        status = {}
    stderr = (directory / f"aircraft_{worker['model']}_errors.log").read_text(encoding="utf-8", errors="replace")
    corridor_samples = {"clear": 0, "obstructed": 0, "unknown": 0}
    source_events = userdata / (worker["label"] + ".jsonl")
    if source_events.exists():
        for line in source_events.read_text(encoding="utf-8").splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get("event") == "SAMPLE":
                clear = event["data"].get("nominal_landing_corridor_clear")
                corridor_samples["clear" if clear is True else "obstructed" if clear is False else "unknown"] += 1
    handoffs = []
    for line in stdout.splitlines():
        if "[AIPilot RECOVERY_HANDOFF]" in line:
            values = re.findall(r"(remaining|lat|vert|track|bank|speed)=([+-]?[\d.]+)", line)
            handoffs.append({"decision": "press" if "press_commit" in line else "accepted" if "] accepted" in line else "rejected",
                             **{k: float(v) for k, v in values}})
    workers.append({**worker, "complete": bool(completion), "completion": completion,
                    "position_checks": checks, "corridor_samples": corridor_samples, "handoffs": handoffs,
                    "results": results, "status": status,
                    "script_errors": (stdout + stderr).count("SCRIPT ERROR")})
    if completion:
        for suffix in [".jsonl", "_status.json"]:
            source = userdata / (worker["label"] + suffix)
            if source.exists():
                shutil.copy2(source, directory / source.name)
summary = {"complete": all(w["complete"] and len(w["results"]) == manifest["trials_per_model"] for w in workers), "workers": workers}
(directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
lines = ["# Clear-site fleet recovery assessment", "",
         "Aircraft 1, 2, 5 and 14, two arrivals each; calm wind, identical clear carrier pose and heading. Uses the project aircraft settings recorded by the manifest source hashes. Each uncaught attempt has 900 simulated seconds. This is eight trials, not a fleet reliability estimate; launch, combat and concurrent recoveries are outside scope.", "",
         "| Aircraft | Arrival | Outcome | Health | Seconds to wire | Seconds to stow | Missed approaches | Strict / permissive handoffs |",
         "| --- | --- | --- | ---: | ---: | ---: | ---: | --- |"]
for worker in workers:
    for result in worker["results"]:
        r = result["record"]
        caught = f"{r['caught_at'] - r['launched_at']:.1f}" if r.get("caught") else "—"
        stowed = f"{r['stowed_at'] - r['launched_at']:.1f}" if r.get("stowed") else "—"
        lines.append(f"| {worker['model']} | {result['case']['name']} | {result['outcome']} | {r.get('health')} | {caught} | {stowed} | {r.get('missed_approaches')} | {r.get('strict_handoffs')} / {r.get('press_handoffs')} |")
lines += ["", "Complete: " + str(summary["complete"]), "",
          "The public recovery-site assessment checks the nominal final terrain corridor only. Its UI warning is advisory and does not change landing permission, steer the carrier, or guarantee the whole recovery circuit is clear. Raw events, placement validation and error counts are retained alongside this report."]
lines += ["", "## Corridor checks during recovery", "",
          "| Aircraft | Clear samples | Obstructed samples | Unknown samples | Script errors |",
          "| --- | ---: | ---: | ---: | ---: |"]
for worker in workers:
    c = worker["corridor_samples"]
    lines.append(f"| {worker['model']} | {c['clear']} | {c['obstructed']} | {c['unknown']} | {worker['script_errors']} |")
(directory / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps({"complete": summary["complete"], "workers": [{"model": w["model"], "complete": w["complete"], "sim_time": w["status"].get("elapsed_s"), "results": [(r["case"]["name"], r["outcome"]) for r in w["results"]], "script_errors": w["script_errors"]} for w in workers]}, indent=2))
