# Finite corium deposits

New campaigns allocate eight permanent corium sites once, relative to the
carrier's initial position. They do not respawn, expire, migrate or replenish.
The 45-second seeping phase and 55–90-second dormant phase only control access
to the original finite reserve. Unharvested material remains for a later visit.

| Sites | Distance from start | Corium per site | Initially known |
| --- | --- | --- | --- |
| 1 | 350–1,100 m | 480 | Yes |
| 2 | 2–4 km | 640 | Yes, initial surveys |
| 2 | 6–10 km | 800 | No, scout to discover |
| 3 | 12–18 km | 1,120 | No, scout to discover |

The regional pool is 6,720 corium, plus the existing 1,000 starting stock.
The carrier retains its starting harvester; a replacement costs 18 corium and
120 plasteel. These are initial tuning values, not a measured campaign budget.
No individual deposit is a required objective. Cargo must still physically
return to the carrier before it enters stores.

Placement checks terrain stability, spacing and a ground navigation route.
Failed slots retry with at most one candidate per frame. Their original
anchor and attempt history persist across saves and floating-origin shifts.
Initial sectors spread opportunities; after repeated failures, candidates can
use another direction at the same distance band. Impossible terrain can still
delay placement; generated or exhausted slots are never replaced.

Completed older saves retain their original sites and quantities. They do not
receive new deposits or free refills. The new distribution applies to new
campaigns; incomplete placement can finish its missing slots.

The harvester panel shows only discovered reserves, nearest distance, selected
site distance and approximate full cargo loads remaining. Exhausted sites stay
on the tactical map; no remaining known reserves prompts reconnaissance.

Validation entry points:

- `Tests/CoriumDistributionSmoketest.tscn` (add `-- --terrain` for actual terrain/navigation placement)
- `Tests/CoriumResourceSmoketest.tscn` (extraction, cycles, danger, saves and mission intent)
- `Tests/CoriumPlanningRenderedProbe.tscn` (live planning panel captures)
