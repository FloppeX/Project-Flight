# Carrier damage control — first playable slice

Implemented 2026-09-09. Values below are initial tuning, not combat-balanced acceptance criteria.

## Damage

- `LandCarrier2.tscn` owns one `CarrierDamageControl` node. The carrier exposes projectile-compatible damage entry points and `get_system_capability`.
- Structure starts at 2,000; exterior armor subtracts 20, clamped to zero. Internal fire damage bypasses armor. Zero structure irreversibly disables carrier capabilities for that run; the wreck and command UI remain. Saving is blocked after loss, preserving the previous checkpoint. There is no cinematic game-over/evacuation flow yet.
- Localized wear is 30% of penetrating structure damage. The nearest authored subsystem mesh bounds within six meters select the region, favoring smaller overlapping parts. Unmapped impacts damage structure only. This is approximate compartment localization, not physical armor penetration or internal ray traversal.
- Penetrating damage >= 40 can start a fire: probability `(damage - 40 + 20) / 300`, capped at 65%. One external event makes one incident roll. Condition <= 30 means offline; 30–75 degraded; >= 75 operational. Fire and manual isolation hold operation regardless of condition.
- Impact and splash from supported shared-projectile/rocket/autocannon paths carry a common event ID. The strongest component counts once against the carrier, after a short collection window. Explosion falloff samples the nearest compound-hull box rather than the carrier origin. Physics results are deduplicated by carrier, not collision shape. Other actors retain existing impact/blast handling.
- Each built turret gets a stable `mount:<site path>` state; dismantled sites stop generating repair jobs. A damaged mount does not disable its neighbors.
- Exposed island/turret meshes have authored-bounds projectile-only StaticBody hit volumes on layer 20. Projectile rays and blast queries include that layer; normal aircraft/officer collision masks do not. These volumes follow their mesh parents.

## Response and materials

- Two logical teams (Alpha and Bravo), not individually pathfinding crew characters. Simulation updates at 4 Hz; geometry bounds refresh at 0.5 Hz. Closing the tab does not stop repairs. No per-frame mesh rebuild is performed for unchanged schematic status.
- Fire suppression always outranks repairs, even if repairs are paused or plasteel is exhausted. Unisolated fires grow at 0.3 intensity/s, damage condition by 0.15/s, and cost up to 1 structure/s. Each team suppresses 2 intensity/s. Isolation halts escalation and secondary damage, but the team still has to extinguish the fire. Reconnection is blocked until extinguished; it is manual afterward.
- Each new component hit supplies a limited emergency-patch allowance (30% of condition lost, capped at 25). Patches recover at 1 condition/s up to 65 condition without materials; repeated isolation cannot replenish this allowance.
- Permanent component repairs recover 0.5 condition/s for 1 plasteel/condition. Structure repairs recover 1 point/s for 2 plasteel/point, only below 0.5 m/s and at least 15 seconds after the last penetrating hit.
- Default reserve: 100 plasteel; UI options 0, 100, 250. No spending below the reserve. Doctrine biases survival, flight operations, mobility or defenses; a single urgent selection outranks doctrine but never fire response.
- Integrity, condition, fires, patch allowances, isolation, doctrine, reserve, repair switch and RNG state persist. Teams deterministically redispatch after load. Old checkpoints without damage data start healthy. Early pending-load restoration prevents temporary healthy state during initialization.

## Operational scope

- Drive: degraded speed/turn requests halved, offline stopped using normal deceleration.
- Defenses: degraded tracking/firing cadence reduced; offline mounts excluded from DefenseOps allocation and stop firing.
- Island: carrier radar range reduced/disabled; independent aircraft sensor reports and command controls remain available.
- Flight deck/catapults: hold new launches; a damage-held launch retries after service restoration. Flight-deck failure holds new landing clearances, not already-granted approaches.
- Hangar/elevators: hold new retrievals and queued launches. Already-running transfers finish; recovery storage remains available in this conservative first integration. Catapults and elevators currently share condition by subsystem category, not independent lane/lift condition.
- Vehicle bay: new deployment requests refused while offline. Existing deployments/ground units remain unaffected.
- Reactor, replicator, habitation and stores have condition/fire tracking, but no detailed power allocation, production, injuries, specialists or secondary inventory loss yet. The selected-system panel explicitly states these limitations. No world-space fire/crew animation is included yet.

## Interface and verification

- Carrier tab: live integrity bar, all twelve subsystem states, color-coded authored geometry, markers for built turret sites, per-mount selector, consequence text, fire intensity, repair costs, team jobs, conditional time estimates and live response controls. 720p uses a scrollable response column. Status text supplements color.
- `Tests/CarrierDamageControlSmoketest.gd`: armor, localized wear, event deduplication, material-free suppression, isolation/reconnection, reserves, structural speed gate, local turret failure, launch/recovery separation, real compound-body blast query, saves/pending-load, live UI callbacks and loss.
- `Tests/CarrierDamageControlRenderedProbe.gd`: rendered mixed healthy/degraded/burning state at 1920x1080 and 1280x720. Captures in `captures/carrier_damage_control/`. Run with `--max-fps 60` to allow the threaded schematic loader time to finish.
- Regressions: `tools/carrier_console_smoketest.gd`, `Tests/DefenseOpsSensorSmoketest.gd`, `Tests/ModularCarrierTurretsSmoketest.gd`, `Tests/StartupCameraSequenceSmoketest.tscn`.
- Existing ObjectDB shutdown warnings remain. The headless main-menu test also emits known material-null cleanup errors despite passing its assertions. A sustained combat/balance playtest remains necessary.
