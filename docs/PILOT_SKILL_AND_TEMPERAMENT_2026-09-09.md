# Pilot competence and temperament

## Implemented first skill slice

`AI/PilotSkillProfile.gd` defines perception competence independently of aircraft
physics and personality. Existing five roster skill names are unchanged.

| Tier | Recognition evidence | Motion response rate | Turn-estimate response rate | Shoulder-check interval |
| --- | ---: | ---: | ---: | ---: |
| Recruit | 1.00 s | 1.2 /s | 2 /s | 10 s |
| Rookie | 0.75 s | 2 /s | 3 /s | 8 s |
| Experienced | 0.45 s | 4 /s | 6 /s | 6 s |
| Veteran | 0.25 s | 6 /s | 9 /s | 4.5 s |
| Elite | 0.15 s | 9 /s | 12 /s | 3 s |

These are initial game-design values, not measured human-pilot parameters. Rate
fields retain the project's `hz` naming convention but are exponential response
coefficients, not an additional physics update cadence.

- Clear visual rays provide glimpses. Recognition accumulates across successive
  observations; interruptions longer than one second reset that evidence. Pending
  recognition does not publish a fresh position/velocity. Reacquisition after a
  long interruption preserves only the old, aging memory until recognition.
  An explicitly assigned contact with a fresh pending glimpse gets a brief
  own-course hold, without target-position steering or firing. A missed visual
  scan cancels that grace after 0.25 s; normal safety still preempts it.
- Once recognized, visible position is still sampled directly. Velocity and turn
  estimates respond gradually to changes, more slowly for less-skilled pilots.
  This first slice adds no random aim offsets or position/range estimation noise.
  Steady-target motion can be learned accurately by every tier.
- The same perceived motion feeds steering, ballistic lead and firing assessment.
  There is no second perfect target-motion feed vetoing every novice miss. Actual
  projectiles, damage and occlusion remain physical.
- Shoulder checks remain directed toward remembered sectors, not omniscient
  searches. Skill changes their frequency/duration, not canopy visibility or the
  maximum four-ray scan budget. Existing skill-dependent memory duration and
  evasive reaction delay remain.
- Skill presets no longer write `dogfight_corner_speed_mps`; the aircraft's
  authored value survives every tier change. All tiers use the established
  Experienced aiming gains (pitch 26, yaw 14, PID scale 0.55). The first matrix
  exposed persistent pitch offsets with the old recruit/rookie gains: no shots
  for recruits and only one for rookies against the gentle-turn target. That
  version was rejected. All tiers now also share the Experienced firing policy:
  minimum perceived hit chance 0.72, precision blend 0.90, burst 0.55 s, cooldown
  0.22 s. Air-kill bonuses no longer change these four values. The final head-on
  checks exposed the old elite thresholds as a shot-delay disadvantage; shot
  patience belongs to future temperament preferences, not competence.
  Other legacy skill-specific tactical settings, including upward aiming limits
  and missile-use probability, remain; this is not yet a complete separation of
  every historical skill knob from tactical preference.
- Landing, terrain safety, separation and physical surface authority are unchanged.

The old awareness accumulator is not restored as a second competing knowledge
gate. Recognition belongs to the observed-contact model that actually controls
target availability. Its legacy awareness-rate exports still exist but should not
be treated as the operative skill knobs for this new path.

## Test setup correction

`GunsOnlyDuel` now accepts independent `--duel-skill-a=0..4` and
`--duel-skill-b=0..4`. The pristine pilot receives the requested skill preset
before its settings are snapshotted/restored around the legacy harness. Actual
settings are checked after initialization and included in the final report.
`GunneryTrackingBaseline` accepts `--gunnery-skill=0..4` and records the effective
skill/perception profile. Both harnesses hash the new skill-profile source.

The focused skill test verifies all five recognition delays, ordered response to
an observed velocity change, no hidden-position leak during delayed reacquisition,
finite memory, floating-origin rebasing and idempotent preset application without
overwriting aircraft corner speed. Full-flight results are recorded below.

## Temperament: separate tactical preferences, design only

The roster already carries 18 labels through `pilot_temperament` metadata. No
flight behavior consumes that metadata yet. This pass deliberately does not
silently assign combat advantages based on a descriptive personality adjective.

Skill answers **how well the pilot executes and understands a situation**.
Temperament answers **which acceptable option the pilot prefers**. A recruit can
be aggressive; an elite can be careful. Neither personality changes eyesight,
reaction-processing capability, projectile spread, thrust or control authority.

Use a small tactical-preference profile rather than 18 separate AI controllers:

- Commitment: how readily to begin an attack and how much initiative to take.
- Risk appetite: acceptable tactical disadvantage before declining/extending.
- Persistence: how long to try a marginal plan before selecting another.
- Fire patience: preference for a closer/steadier shot versus an earlier snapshot.

Bound these preferences with mission orders, available energy, and the same
terrain/separation priorities. Fearless must not mean ignoring the deck or flying
through another aircraft. Careful must not mean permanently refusing combat.
Skill governs estimation/execution; temperament governs choice using that estimate.

Proposed interpretation of every existing label (not implemented or calibrated):

| Existing temperament | Tactical interpretation |
| --- | --- |
| steady | Balanced commitment; sticks with a workable plan |
| confident | Commits readily; moderate persistence |
| eager | Starts attacks early; less patient about setup |
| aggressive | Presses closer and accepts more tactical risk |
| cool | Low tendency to abandon a plan after a transient threat cue |
| practical | Prefers attainable opportunities over prolonged pursuit |
| bold | Willing to attempt a difficult attack geometry |
| spirited | More initiative; moderate appetite for changing the attack |
| methodical | Values setup and stable firing windows; persists once established |
| decisive | Commits firmly after choosing; avoids rapid reconsideration |
| dry | Neutral flight preferences; primarily dialogue/presentation |
| careful | Larger tactical margin; extends earlier when disadvantaged |
| intense | Strong persistence on the selected opponent |
| fearless | Low tactical threat aversion, with normal safety constraints |
| precise | Prefers a steadier firing window; no accuracy or sensor bonus |
| restless | Lower persistence when a plan makes little progress |
| resourceful | More willingness to choose an alternate feasible plan |
| sharp | Opportunistic target preference; no faster sensing by fiat |

"Measured" need not replace a roster label: methodical, steady and cool already
cover different aspects of it. Avoid inventing strong numerical differences for
labels such as dry where personality alone does not imply a flight style.

## Follow-up sequencing and acceptance

1. Validate skill first with neutral tactical preferences: same-airframe pursuit
   against immortal targets, all five tiers, then mirrored mixed-skill duels.
2. Before motor-control tuning, investigate existing small-error pitch reversals.
   Do not deliberately introduce unstable control loops as a novice personality.
3. Implement a small bounded temperament slice for attack commitment and fire
   patience, keeping perception fixed. Compare aggressive/careful/neutral at the
   same skill before expanding to every label.
   The legacy skill-dependent gun thresholds have already been neutralized;
   apply personality preferences once, without stacking undocumented multipliers.
4. Test the crossed cases: aggressive recruit, careful recruit, aggressive elite,
   careful elite. Skill should improve execution on average; no temperament should
   universally dominate or force endless escape. Then expand aircraft/seed coverage.

Measure recognition latency, tracking error, ammunition per hit, energy lost,
reacquisition, terrain/collision losses, and timeouts. A stationary easy shot must
remain dangerous even from a novice. Win counts alone mix aircraft, starting
geometry, damage locations, skill and temperament.

Performance estimate: one small profile dictionary per existing contact scan,
scalar recognition timers and a few filtered vector operations per successful
observation. No extra ray budget, per-projectile search, or slower physics control
loop. This is a scaling estimate, not a measured frame-time result.

The scheduled landing monitor remains paused. These are finite, directly launched
tests; no new scheduled task is created.

## Intermediate first-slice results (before recognition course hold)

`skill_v2_*` source, headless fixed 60 FPS, Aircraft 5 shooter, immortal
scripted target, 90 seconds per tracking trial. All five tier reports COMPLETE,
valid, and source-hash verified; effective tier/profile recorded in each report.

| Skill | Gentle-turn hits / shots | Hit fraction | Time within 1 degree and 900 m |
| --- | ---: | ---: | ---: |
| Recruit | 26 / 92 | 28% | 14.37 s |
| Rookie | 188 / 437 | 43% | 67.65 s |
| Experienced | 435 / 468 | 93% | 75.60 s |
| Veteran | 462 / 472 | 98% | 76.75 s |
| Elite | 466 / 467 | 99.8% | 77.77 s |

This is one geometry per tier, not a statistical ranking over all dogfights.
The main gap is recruit/rookie versus experienced; veteran and elite separation
is small in this predictable steady-turn case. It should be tested against
reversals and intermittent visibility before increasing any artificial penalties.

No-threat controls, also COMPLETE/valid/hash-verified:

- Recruit tail chase: 447/459 hits/shots, 76.23 s within aim tolerance.
- Experienced tail chase: 465/471, 81.98 s within tolerance.
- Experienced crossing left: 279/283, 59.12 s within tolerance.

The recruit can learn steady motion and hold a useful firing position. Comparison
with the old no-recognition baseline includes a changed acquisition trajectory;
do not claim an isolated accuracy improvement from total shot counts alone.

Focused checks: skill profile/knowledge 45; evasion/source dispatch 62; physical
visual contact 27; pursuit 80; pitch ownership 2: zero failures. Gunnery fixture
PASS (1,000 immortal-target hits, 191 authored settings). Go-around response,
recovery route capture, recovery terrain escape and deck-footprint waveoff (136
checks) PASS. Existing dummy-renderer and resource cleanup messages persist at
headless shutdown; this does not claim clean shutdown or rendered flight validation.

Artifacts are under `C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier/`:
`skill_v1_gentle_*` is the rejected low-gain experiment;
`skill_v2_gentle_0..4.json`, `skill_v2_recruit_tail.json`,
`skill_v2_experienced_tail.json`, and `skill_v2_experienced_crossing.json` are the
intermediate tracking controls. Normal-health duel results follow below.

### Mirrored normal-health duels

Aircraft 5 on both sides, normal health/ammunition, same head-on geometry,
independently selected Recruit/Elite pilots. Both seeds and both skill assignments
verify their effective post-initialization settings and all recorded source hashes.

| Seed | A / B skill | Hits/shots A | Hits/shots B | Duration | Outcome |
| --- | --- | ---: | ---: | ---: | --- |
| 20260911 | Recruit / Elite | 4/9 | 7/7 | 240 s | Timeout, both hulls intact |
| 20260911 | Elite / Recruit | 8/10 | 3/4 | 92.48 s | Elite gun victory |
| 20260912 | Recruit / Elite | 16/22 | 7/7 | 240 s | Timeout, both alive |
| 20260912 | Elite / Recruit | 13/17 | 2/4 | 94.47 s | Elite gun victory |

The winning runs end with successive 10-point fuselage damage events and fuselage
destruction, not a terrain crash. Minimum center separations in the first seed
were 16.09 m and 12.32 m; the second elite-winning run reached 12.64 m. These near
passes remain a separation defect. Two wins and two timeouts establish neither
a calibrated skill win rate nor reliable prolonged fighting. The persistent
starting-side asymmetry is a reason to retain mirrored tests, not conceal draws.

Reports: `skill_v2_recruit_elite_{a,b,c,d}.log.json`, with `pilot_settings` and
`settings_verified` alongside source hashes. All are COMPLETE. The final settings
confirm identical 26-point pitch gain and 85 m/s authored corner speed for both
tiers, but 1.0 s versus 0.15 s recognition evidence. All finite runs finished.

The controlled evasive-defender harness also declares its intentional evasion
on/off override when checking post-initialization settings, so that override does
not mask accidental skill/gain drift or falsely invalidate the test. Its final
90-second integration run `skill_v2_evasion_harness.log.json` verified metadata but
scored zero hits and caused zero evasion episodes. It is therefore NOT a successful
evasion regression. It exposed an acquisition-transition defect: the pilot dropped
the explicitly assigned contact before recognition completed, began a patrol turn,
and lost enough speed that Aircraft 3 never returned to gun range. This prompted
the own-course recognition grace described above. No target-truth steering or
engine/airframe change was added.

## Intermediate source: recognition-transition correction

`skill_v3_*` includes the bounded own-course grace while processing a fresh glimpse.
The real visual-contact regression now tests this state transition and firing
suppression, while the pure track test checks that a missed glimpse ends the grace.
The Aircraft 3 attacker compatibility run now scores 72 hits from 112 shots, with
effective settings and source hashes verified. This exercises the evasive defender
again; it is still not a paired on/off effectiveness comparison.

This matrix predates the neutral firing-policy correction described below.

### Recognition-corrected tracking matrix

Same 90-second gentle-turn fixture, same Aircraft 5, fixed 60 FPS. All seven
V3 tracking reports are COMPLETE, valid and source-hash verified.

| Skill | Hits / shots | Hit fraction | Within aim tolerance | First continuous acquisition |
| --- | ---: | ---: | ---: | ---: |
| Recruit | 29 / 114 | 25% | 11.43 s | 3.50 s |
| Rookie | 229 / 526 | 44% | 75.38 s | 2.32 s |
| Experienced | 468 / 497 | 94% | 85.40 s | 1.73 s |
| Veteran | 482 / 490 | 98% | 86.32 s | 1.42 s |
| Elite | 481 / 483 | 99.6% | 86.85 s | 1.20 s |

Actual impacts differ much more than one-degree alignment for Recruit/Rookie:
the perceived motion can justify shooting while the real maneuver causes misses.
No weapon-spread change is involved. These numbers remain one initial geometry
per tier, not calibrated population statistics. Veteran/Elite are nearly equal
against this predictable target; their distinction needs harder perception tests.

The V3 Recruit tail control scores 589/592 hits/shots and 89.03 s within
tolerance. It acquires a steady easy target; this is not a universal hit penalty.
Experienced crossing left scores 241/253 and 55.73 s within tolerance, with first
continuous acquisition at 34.57 s. A changed initial course affects that result;
do not interpret all of the improvement as a better low-level aiming law.

Artifacts: `skill_v3_gentle_recruit.json`, `skill_v3_gentle_1..4.json`,
`skill_v3_recruit_tail.json`, `skill_v3_experienced_crossing.json`.
The V3 evasive-defender compatibility run completes one 8.03-second defensive
episode and remains alive after 72 projectile hits. It validates that the new
recognition path can reach combat/evasion again, not a new survival estimate.

### Head-on inversion exposed by the corrected transition

The V3 mirrored duels did NOT reproduce the earlier two elite wins. Recruits won
three runs (18.22, 19.50 and 18.20 s); the fourth ended with both destroyed at
138.22 s after an 8.33 m minimum separation. All four reports verify source hashes
and effective settings. The first run shows repeated projectile fuselage damage
destroying the elite, not a landing/terrain accident. Recruits fired earlier while
elites waited for the legacy stricter firing gates. This indicates a tactical
policy confound rather than establishing that recruits have better perception.
Removing that skill-dependent policy is a necessary controlled comparison, not a
guarantee of an elite win in every duel.

Reports: `skill_v3_recruit_elite_{a,b,c,d}.log.json`. V3 focused checks: skill 50,
visual contact 29, evasion 62, pursuit 80, plus gunnery fixture and all four recovery
regressions PASS. These remain intermediate results, not final balance evidence.

## Final source: neutral firing policy

`skill_v4_*` retains the recognition-transition correction and uses identical
minimum gun-solution thresholds, burst length and cooldown at every tier. The
focused skill test now checks this explicitly (60 checks, zero failures).
All finite V4 runs finished. Tracking reports are COMPLETE/valid with verified
source hashes; duel/defender reports also verify their effective pilot settings.

| Skill | Gentle-turn hits / shots | Hit fraction | Within aim tolerance | First continuous acquisition |
| --- | ---: | ---: | ---: | ---: |
| Recruit | 21 / 61 | 34% | 11.55 s | 3.45 s |
| Rookie | 238 / 487 | 49% | 75.95 s | 2.32 s |
| Experienced | 468 / 497 | 94% | 85.40 s | 1.73 s |
| Veteran | 482 / 497 | 97% | 86.23 s | 1.42 s |
| Elite | 492 / 499 | 99% | 86.85 s | 1.20 s |

Recruit straight-tail control: 588 hits from 589 shots. This confirms a learnable
steady solution remains dangerous; the novice's difficulty is predominantly
changing motion, not an arbitrary constant chance to miss. These are 90-second
single-geometry tests, not general combat win-rate estimates.

| Seed | A / B skill | Hits/shots A | Hits/shots B | Duration | Outcome |
| --- | --- | ---: | ---: | ---: | --- |
| 20260911 | Recruit / Elite | 9/13 | 9/9 | 17.88 s | Elite wins |
| 20260911 | Elite / Recruit | 8/9 | 12/14 | 18.10 s | Recruit wins |
| 20260912 | Recruit / Elite | 11/12 | 9/9 | 240 s | Timeout, both alive |
| 20260912 | Elite / Recruit | 8/8 | 12/14 | 18.10 s | Recruit wins |

The neutral policy closes the large initial firing-time gap (first seed:
16.07/16.13 s and 16.10/16.00 s), but does NOT establish elite dominance. Normal-
health head-on results still depend strongly on starting side and damage location.
The first-seed elite loss destroys cockpit/fuselage while the recruit takes damage
across other parts. The timeout reaches 9.91 m center separation: collision
avoidance remains an unresolved defect. Reports can contain projectiles still in
flight at the death cutoff; hits/shots here are cutoff counts, not settled
shot-accuracy rankings. Do not tune competence solely to force these four winners.

The final Aircraft 3 attacker / immortal evasive-defender integration again scores
72/112 hits/shots, one 8.03-second defense episode, defender alive after 90 seconds.
Experienced behavior is unchanged by neutralizing the other tiers' gun presets.

Focused final-source regressions: skill 60 checks, physical visual contact 29,
evasion/source dispatch 62, pursuit 80, all zero failures; gunnery fixture PASS
(1,000 immortal hits, 191 settings preserved). Existing headless renderer/resource
cleanup warnings remain; no visual-playback or frame-time claim is made.
Final-source go-around response, recovery route capture, recovery terrain escape
and deck-footprint waveoff (136 checks) also PASS.

Artifacts: `skill_v4_gentle_0..4.json`, `skill_v4_recruit_tail.json`,
`skill_v4_recruit_elite_{a,b,c,d}.log.json`, `skill_v4_evasion.log.json` and its
`.defense.json` companion. The V4 results supersede V1/V2/V3 balance conclusions.

Next: validate perception on reversals/occlusion and longer-lived mixed-skill
encounters before calling the tiers balanced. Then add bounded commitment/fire-
patience temperament preferences and compare crossed skill/personality cases.
