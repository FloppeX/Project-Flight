# Aircraft navigation and attack audit — 2026-09-29

The review traced flight orders into fixed-wing and helicopter navigation,
approach planning, flight controls, weapon aiming/release, and recovery. The
changes address reproduced failures; they are not a guarantee that every aircraft,
terrain layout, or combat situation is now reliable.

## Findings and changes

1. **Direct attack turns had weaker distant-point capture than ordinary navigation.**
   `AIPilot._get_3d_point_flight_path_guidance` now applies the existing bounded
   heading response during direct attack positioning. Formation slots, explicit
   attack-axis guidance, and prepared recovery approaches retain their own response.
2. **High, close approaches could commit an unusably steep gun pass.** The pilot
   now checks how much descent distance remains before the entry lane. When both
   height and approach steepness are excessive, it uses the existing straight
   extension to descend, then returns for a pass. The normal firing and physical
   pull-out gates remain in force. This can require a substantial setup leg.
   This extra descent setup applies to gun/rocket passes.
3. **Direct gun setup and corridor validation disagreed.** The old low setup point
   could fail the corridor's own clearance check even over flat ground. Direct
   gun setup now uses the existing corridor altitude solver, including egress.
4. **Crossing ground targets left a persistent lateral gun-aim error.** A bounded
   integral correction removes sustained error from a valid fine CCIP solution.
   It resets when that solution is lost, blocked, or no longer in fine acquisition.
5. **Rockets from one aircraft could collide with its other rockets.** A runtime
   trace confirmed rocket-to-rocket impacts near the helicopter, followed by blast
   damage to the helicopter. Same-launcher rockets now exclude one another from
   both body collisions and swept impact queries. Terrain and other targets remain
   collidable. Weak references and explicit removal handle a rocket disappearing
   before the rest of its salvo.

The diagnostic also needed repair: its million-round ammunition override added
real payload mass and invalidated the initial runs. Unlimited test firing already
had a separate mechanism. It now retains authored ammunition mass and records
mass, flight model, lift, angle of attack, and gun sight error. New options exercise
starting altitude, distance, and moving ground targets.

## Coverage and evidence

Reviewed paths include `AirOps/Flight.gd`, `AI/AIPilot.gd`, shared
`AI/FlightPathFollower.gd`, `AI/AttackPlanner.gd`, `AI/HelicopterPilot.gd`,
`Aircraft/SimpleAero.gd`, aircraft impact prediction, and weapon/projectile release.
Production edits for this audit are in `AI/AIPilot.gd` and
`Projectiles/Rocket/rocket.gd`. Existing unrelated workspace changes are preserved.

Representative production-physics results:

| Exercise | Result |
| --- | --- |
| Aircraft 5, stationary gun target, 180 simulated seconds | Alive; 37 rounds, 15 damage events. Baseline: 94 rounds, 17 events. |
| Aircraft 5, 1,400 m start altitude, target crossing at 12 m/s | Descended and re-entered; four rounds, four damage events, alive. First shot about 111 simulated seconds. Baseline had no shots or damage in 120 seconds. |
| Aircraft 10, ground attack | Alive; first target damage at about 47.5 simulated seconds. Earlier reproduction detonated salvo rockets near the launcher and destroyed the helicopter. |
| Aircraft 5, rocket attack | One six-rocket salvo, three target damage events, alive; no salvo-peer query errors. |
| Aircraft 5, bomb attack, 65 simulated seconds | One bomb, one target damage event, alive. |
| Air-to-air tail-entry duel | Attacker fired 24 rounds, recorded six hits, and destroyed its opponent; no tactical-reset delay. |
| Ordinary waypoint turns | All eight loaded/unloaded cases passed, including bearings of ±90 and ±170 degrees. |
| Two-aircraft attack ingress | Both passed; heading capture at about 15.6 and 19.2 simulated seconds. |
| Loaded four-waypoint patrol | Two full circuits: 0, 1, 2, 3, 0, 1, 2, 3, 0. |

Focused checks passed for attack planning (108 checks), rocket prediction/salvo
collisions and peer cleanup (10), waypoint guidance (34), loaded lift-vector
guidance (360), dogfight pursuit (80), dogfight pitch ownership (2), visual contact
(29), helicopter shoot-and-scoot and pop-up behavior, flight attack orders,
formation guidance, and patrol progression.

Acceptance outputs are under `logs/attack_audit_*release*`,
`logs/attack_audit_final_*`, and the named focused-test logs. Earlier `before`
and intermediate comparison files include rejected diagnostic/control versions;
they must not be treated as current acceptance results.

## Limits

These are headless tests using production physics and weapons, primarily Aircraft
5 and Aircraft 10, plus the duel's two fighters. The ground targets are durable
fixtures: damage events demonstrate hits, not target kills. The movement fixture
crosses on a straight line; it does not cover a real platoon's turns or occlusion.
Tests use fixed simulation steps while some existing game timers use wall time,
so their timings and hit counts are representative, not reproducible benchmarks.

The tests do not verify all aircraft types, mountainous approaches, formation
deconfliction, hostile fire, or a complete carrier launch-to-recovery mission.
Gun passes can still descend low and moving-target accuracy needs broader combat
testing. Several pre-existing headless tests report rendering/resource cleanup
warnings after their assertions pass; those runs are not clean engine-error runs.
The user's stopped game was not restarted or altered for this audit.
