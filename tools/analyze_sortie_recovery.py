"""Summarize the recorded sortie and its reconstructed terrain collision surface."""
import csv
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "logs"
data = json.loads((OUT / "sortie_terrain_reconstruction.json").read_text())

def vec(value):
    return tuple(float(x) for x in value.strip("()").split(","))

rows = []
for s in data["samples"]:
    p, v, rot = vec(s["position"]), vec(s["velocity"]), vec(s["rotation"])
    nav, controls = s["nav"], s["controls"]
    progress = nav["progress"]
    rows.append(dict(t=s["t"], x=p[0], y=p[1], z=p[2], speed=math.dist(v, (0, 0, 0)),
                     vertical_speed=v[1], bank_deg=math.degrees(rot[2]),
                     api_height=s["api_height"], mesh_height=s["ray_height"],
                     api_clearance=s["api_clearance"], mesh_clearance=s["mesh_clearance"],
                     revision=nav["flight_plan_revision"], leg=progress.get("index"),
                     cross_track=progress.get("cross_track_m"), remaining=progress.get("plan_remaining_m"),
                     checked_corridor=controls["checked_corridor"], terrain_vs_floor=controls["terrain_vs_floor_mps"],
                     pitch=controls["pitch"], roll=controls["roll"], reacquire=nav["reacquire_active"]))
with (OUT / "sortie_recovery_reconstruction.csv").open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=rows[0].keys())
    w.writeheader()
    w.writerows(rows)

final = [r for r in rows if r["t"] >= data["crash"]["t"] - 30]
fig, axes = plt.subplots(3, 1, figsize=(11, 10), constrained_layout=True)
axes[0].plot([r["x"] for r in rows], [r["z"] for r in rows], label="Aircraft path")
for s in data["samples"]:
    nav = s["nav"]
    if nav["progress"].get("valid"):
        start, end = vec(nav["progress"]["segment_start"]), vec(nav["progress"]["segment_end"])
        axes[0].plot([start[0], end[0]], [start[2], end[2]], color="gray", alpha=.08)
impact = vec(data["crash"]["data"]["position"])
axes[0].scatter(impact[0], impact[2], color="red", marker="x", s=80, label="Terrain collision")
axes[0].set(title="Recovery path and active route-leg chords (arcs shown as chords)", xlabel="World X (m)", ylabel="World Z (m)")
axes[0].axis("equal")
axes[0].legend(loc="upper right")
for key, label, style in [("y", "Aircraft origin", "-"), ("api_height", "Height API", "--"), ("mesh_height", "Rebuilt collision surface", "-")]:
    endpoint = {"y": impact[1], "api_height": data["impact_api_height"], "mesh_height": data["impact_mesh"]["height"]}[key]
    axes[1].plot([r["t"] for r in final] + [data["crash"]["t"]], [r[key] for r in final] + [endpoint], style, label=label)
axes[1].scatter(data["crash"]["t"], impact[1], color="red", marker="x")
axes[1].set(title="Final 30 seconds: height beneath the recorded aircraft position", ylabel="World height (m)")
axes[1].legend()
axes[2].plot([r["t"] for r in final], [r["vertical_speed"] for r in final], label="Vertical speed (m/s)")
axes[2].plot([r["t"] for r in final], [r["bank_deg"] for r in final], label="Euler roll (degrees)")
axes[2].axhline(0, color="gray", linewidth=.5)
axes[2].set(xlabel="Simulation time (s)", title="Flight response near impact")
axes[2].legend()
for ax in axes:
    ax.grid(alpha=.2)
fig.savefig(OUT / "sortie_recovery_reconstruction.png", dpi=140)

print("FINAL_30_SECONDS")
for r in final[::3] + final[-1:]:
    print(json.dumps(r))
print("IMPACT", json.dumps({k: data[k] for k in ["impact_api_height", "impact_mesh", "impact_chunk"]}))
for revision in sorted(set(r["revision"] for r in rows)):
    subset = [r for r in rows if r["revision"] == revision and r["cross_track"] is not None]
    if subset:
        print("ROUTE", json.dumps(dict(revision=revision, start=subset[0]["t"], end=subset[-1]["t"],
                                      max_cross_track=max(r["cross_track"] for r in subset),
                                      checked=sum(r["checked_corridor"] for r in subset), samples=len(subset))))
