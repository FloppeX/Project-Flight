# Evasive flight and observed-contact reacquisition

Implementation follow-up to `EVASIVE_FLIGHT_DESIGN_2026-09-09.md` and
`DOGFIGHT_GROUND_PROBE_AND_ESCAPE_2026-09-09.md`.

## Implemented scope

- Fixed-wing pilots can issue a short defensive flight-path request in SEARCH,
  TRANSIT, DOGFIGHT and ENGAGE. Recovery/landing, launch and deck-owned controls
  are excluded. Terrain and imminent separation retain priority. Offensive gun
  bursts are suppressed throughout the maneuver, including safety preemption.
- `EvasiveFlight.gd` is a node-free intent model. Source-aware projectile impacts
  can raise danger without an attacker identity or position. `ProjectileNew`
  routes aircraft hits through the new entry point; regional wing/cockpit/etc.
  hits therefore do not depend on hull-health loss. Generic landing/contact
  damage does not raise incoming-fire evidence. The old generic-damage callback's
  nearest-enemy awareness boost was removed.
- A visual threat requires a fresh, currently observed rear/abeam track, plausible
  closing attack geometry within 750 m, and persistent evidence. Velocity is an
  approximation of attacker aim, not knowledge that its gun is firing. Reaction
  delay ranges from 0.8 to 0.3 seconds with skill.
- A break requests at most 65 degrees bank and 2.5 G for up to four seconds, then
  a four-second extension requests at most 25 degrees and 1.2 G, with full power.
  Low-energy pilots extend immediately. Eight seconds of cooldown and bounded
  commitment prevent repeated hits from sustaining a permanent defensive turn.
  These are temporary pilot requests through existing flight-path/surface
  controllers, not changes to airframe forces, thrust or actuator authority.
- Descending requests are allowed only with clearance and pass through the
  existing dive guard and terrain floor. Ordinary physical collisions remain
  enabled. Actual achieved bank/load can differ from the requested limits.
- SEARCH no longer chases the live position of a hidden enemy. It looks toward
  observed memory, then briefly searches an expanding uncertain area; that area
  expires after 18 seconds without a new observation and cannot authorize firing.
- The alternative remembered-sector reset is restricted to the period after a
  real separation/evasive break. Ordinary crossing capture keeps its prior reset
  schedule. Brief shoulder checks (up to 1.2 seconds in a six-second cycle) can
  look toward a recent remembered bearing. They retain the belly blind sector,
  existing ray occlusion and finite memory; an unseen target moving elsewhere is
  not revealed. The same bounded contact-scan budget is used.

No GA, aircraft physics retuning, projectile near-miss sensor, or new controller
warning channel is included. The latter two were explicitly later stages in the
design, not prerequisites of the damage/visual first slice. A near miss alone is
not yet an evasive stimulus.

## Measurement and rejected experiments

The controlled bench uses an ordinary Aircraft 3 attacking a projectile-immune
Aircraft 5, which follows a fixed mission heading using normal controls plus the
production defensive supervisor. No defender gunfire. Physical/terrain crashes
remain real failures; projectile immunity is not a survival claim. Each trial is
90 simulated seconds with normal attacker gun behavior. Hit counters are now
attached before the first burst. Temporary occlusion is a real sensor-layer
collision body, not a fabricated pilot observation.

The initial unrestricted-bank/short-extension version reduced two-degree nose
exposure from 90 to 39 seconds but increased received hits from 266 to 662. It
lost energy and allowed closer pursuit. That version was rejected. The bounded,
full-power version reduced the same controlled case to 102 hits and 28 seconds
of exposure, with one eight-second episode. Minimum speed still fell to about
60 m/s during the complete return-to-mission flight, so this does not establish
that energy handling is solved.

An initial remembered-sector reset applied to every visual loss coincided with
both crossing captures failing (zero shots). Narrowing it to actual post-break
recovery did not by itself restore capture. The subsequent control-path trace
found the independent legacy pitch-floor conflict described below. Removing
hidden-target steering is intentional; restoring omniscient SEARCH is not a
valid way to improve a benchmark.

### Crossing capture: trace the complete control path

The terrain-less tracking gym supplied no height provider. NaN clearance flowed
through the suicide-dive guard as zero permissible drop, flattening otherwise
legitimate downward pursuit. Unknown terrain now leaves the already angle-limited
request intact; real terrain-height and independent safety checks retain their
authority. The tracking gym explicitly supplies flat ground at zero, as the duel
harness already does. Known-ground and unknown-height cases have unit coverage.

That correction exposed, but did not fix, the remaining pitch conflict. At 50.08 s
in `evasion_pitch_trace.json`, target AoA was -18 degrees and the coordinated
controller requested -1.14 pitch (clamped to -1 at output). A legacy bank-only
pull floor changed the aiming request to +1. Blending those at 0.672 precision
produced +0.344 pitch before any final safety guard. The wing was carrying 1.32 G,
and the requested descent was -20.65 m/s versus an actual -1.12 m/s. Thus the
positive command did not originate in the downstream safety guards.

The legacy turn-pull bias/floor is now excluded when the coordinated dogfight
controller owns the maneuver. Its positive-load and terrain protections remain.
The experimental symmetric AoA derivative clamp had no measurable effect and
was removed; it must not be credited as a fix. No recovery controller was changed.

The fixed-60-FPS follow-up crossing tests scored 45/51 and 97/106 hits/shots,
with maximum altitude errors of 38.4 m and 20.4 m respectively, instead of zero
shots and a climb hundreds of metres above the target. This restores useful
capture, not promptly settled precision: first continuous acquisition still takes
roughly a minute. The old no-height-provider baseline is not a clean apples-to-apples
performance control for the corrected environment.

The ordinary-time tracking harness waits for idle and physics initialization.
Fixed-FPS duels and ordinary-time gunnery runs are kept separate: the existing
weapon cooldown advances on idle frames and raw shot counts depend on cadence.
Source hashes cover the new intent module and the actual projectile dispatcher,
as well as the pilot, flight model and relevant harnesses.

## Remaining limits

The close-parallel dogfight remains a stress case, not a solved safety or
reacquisition guarantee. Enemy non-target traffic sensing was not redesigned.
Damage-source reporting currently covers the direct projectile path, not every
explosion/environmental damage producer. No synthetic "nearest attacker" fallback
is used for those uncategorized events.

The added per-pilot work samples at most four cached tracks and adds no more
than the existing four visual occlusion checks per scan. Building the cached
track-values array still scales with that pilot's contact count, so the whole
operation is not strictly constant-time. This is a scaling estimate, not a
measured frame-time result. Near-miss broad-phase sensing remains
deferred until it can be profiled under actual projectile load.

Headless full-airframe runs still emit existing dummy-renderer/resource cleanup
errors at shutdown. Passing behavioral assertions does not imply clean shutdown
or rendered/feel verification.

Artifacts are under `C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier/`:
`evasion_v1_*` and `evasion_v2_*` are intermediate experiments;
`evasion_accept_tracking_*` records the rejected broad-reset regression;
later acceptance artifacts and their exact metrics are recorded below.

## Release-source verification

All four ordinary-time tracking reports are COMPLETE, input-hash verified,
valid, and record zero evasive episodes (a no-threat regression control).
Targets survive the entire 90-second measurement plus projectile settling.

| Tracking case | Hits / shots | Within aim tolerance | First acquisition | Max altitude error |
| --- | ---: | ---: | ---: | ---: |
| Tail chase | 747 / 749 | 89.03 s | 0.98 s | 2.65 m |
| Gentle left | 610 / 617 | 87.05 s | 0.98 s | 10.01 m |
| Crossing left | 49 / 56 | 36.95 s | 71.07 s | 38.47 m |
| Crossing right | 76 / 79 | 40.68 s | 67.88 s | 19.85 m |

Artifacts: `evasion_release_tracking_*.json`. The table's tolerance is one degree
within 900 m; first acquisition requires a continuous half second. It is not the
first-shot timestamp. The left crossing is already at 340 m by 40 s, but pitch
alternates around the one-degree boundary, delaying sustained acquisition. Fine
aim settling is the next target, not range closure in this specific case. The
direct aimer's minimum 0.15 pitch command is a candidate to test, not a proven
cause. Counts are not pooled with fixed-FPS runs.

Normal-health, fixed-60-FPS head-on duels, both starting sides and two seeds:

| Pair / seed | Hits A / B | Duration | Result |
| --- | ---: | ---: | --- |
| 5 vs 3 / 20260909 | 8 / 18 | 18.87 s | Aircraft 5 gun victory |
| 5 vs 3 / 20260910 | 5 / 13 | 18.62 s | Aircraft 5 gun victory |
| 3 vs 5 / 20260909 | 23 / 9 | 19.13 s | Aircraft 3 gun victory |
| 3 vs 5 / 20260910 | 8 / 5 | 18.48 s | Aircraft 5 gun victory |

All COMPLETE and hash-verified. Component and hull damage are separate in the
reports; hit counts alone do not predict the winner. These short opening-pass
fights do not validate extended evasion or establish statistically reliable
aircraft win rates. Artifacts: `evasion_release_{merge_a,merge_b,swap_a,swap_b}.log.json`.

Focused checks: evasive intent/source dispatch 62, visual contact 26, pursuit 80,
ground-probe traffic 10, and production dogfight pitch ownership 2: zero failures.
The pitch-ownership regression calls the actual DOGFIGHT path for both bank
directions and checks that downward aim remains an unload. Gunnery fixture PASS
with 1,000 immortal-target hits and all 191 authored dogfight settings preserved.
Go-around response, recovery route capture, recovery terrain escape, deck-footprint
waveoff (136 checks), and carrier damage-zone routing (9 models, 54 contacts) PASS.
No full carrier-landing batch or visible flight was run in this pass.

### Controlled evasion, corrected attacker

Fixed-60-FPS, 90 simulated seconds, identical source and initial geometry within
each on/off pair. All five reports COMPLETE, source-hash verified, defender alive.
The defender is projectile-immune; normal physical/terrain failures remain possible.

| Case | Received hits | Attacker two-degree cone time | Episodes | Minimum speed | Minimum center separation |
| --- | ---: | ---: | ---: | ---: | ---: |
| Tail, evasion off | 266 | 90.02 s | 0 | 80.37 m/s | 484.97 m |
| Tail, evasion on | 108 | 27.92 s | 2 | 59.57 m/s | 334.74 m |
| Side, evasion off | 466 | 83.23 s | 0 | 80.37 m/s | 389.95 m |
| Side, evasion on | 160 | 36.85 s | 2 | 80.37 m/s | 389.95 m |
| Tail, evasion on with occlusion | 102 | 18.88 s | 1 | 59.57 m/s | 484.79 m |

These are about 59% and 66% fewer received hits for the paired tail and side
trials, not general survival probabilities. Body-forward cone time is a geometry
proxy, not a ballistic firing solution. Reaction from first hit to maneuver is
0.55 s in these fixtures. Tail defense accumulated 8.23 s (a second episode began
near cutoff), side defense 16.07 s. Minimum defender altitude was 934.14 m in tail
evasion and 935.86 m in side evasion. The tail case's low minimum speed occurs
during the complete defensive/return-to-mission trajectory and remains a concern.

The real occluder blocked the visual ray during 15–20 s. Of 300 physics samples,
six retained the previously visible observation before the next sensor scan
(0.1 s latency); the remaining 294 reported not visible. This does not assert
instantaneous occlusion updates or erase permitted finite memory.

Artifacts: `evasion_release_{tail_on,tail_off,side_on,side_off,occlusion}.log.json`
and matching `.log.defense.json` traces. Repeated near misses remain explicitly
unsupported; the focused test proves they cannot fabricate a threat event.

### Longer post-break encounters

Final normal harness, fixed 60 FPS, normal health, seed 20260911:

- Aircraft 5 vs 3 perpendicular start: Aircraft 3 gun victory at 182.13 s,
  18 hits for Aircraft 3 and none for Aircraft 5; minimum center separation
  78.71 m. Both the source hashes and COMPLETE status verify. This is progress
  over the earlier normal-harness crossing timeout, not proof that every
  post-break encounter resolves.
- Aircraft 5 vs 5 close parallel: 240 s timeout, no shots, both at full hull
  health, minimum center separation 17.90 m. COMPLETE and hash-verified.
  The surviving near pass is still too close to treat separation as reliable.

Artifacts: `evasion_release_{crossing,parallel}.log.json`.

## Next contained step

Keep the implemented first slice available through `dogfight_evasion_enabled`
(currently enabled by default). Prioritize two unsolved behaviors before a GA or
additional defensive maneuvers: fine aiming's repeated small-error pitch reversals,
and the close-parallel pair's separation/reacquisition loop. Preserve the successful
no-threat tail/gentle controls and paired evasion hit measurements while changing
one controller behavior at a time. Near-miss sensing and external warning reports
remain later stages, not silently implemented knowledge sources.
