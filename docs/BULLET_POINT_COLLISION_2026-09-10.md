# Bullet collision overhaul: swept points

## Contract

Bullets are collision pinpoints (zero radius), not 5 cm spheres. Each active
bullet advances with the existing manual gravity/velocity integration, then
casts a ray over its full previous-to-current segment against actual physics
colliders. Player, aircraft AI and turret rounds inherit the same implementation.
All five gun profiles and the legacy heavy-round scene use this path.

There is no bullet contact-monitor path, target-bounding-sphere assistance,
assist broadphase/candidate scan or terrain-height fallback. The three shared
ammunition scenes no longer contain physical collision spheres. Bullet-specific
assist staggering/LOD settings and the alternate rigid-body movement toggle
were removed. Runtime changes to the legacy assist settings cannot enable an
extra collision path for a Bullet subclass.

The RigidBody3D root is retained as a frozen, shapeless compatibility shell for
existing velocity, weapon and pool APIs. This is not a complete conversion of
every projectile to Node3D. Other projectile families retain their separate
collision behavior and the generic base's legacy facilities.

Tracer dimensions, brightness, spread, muzzle velocity, cadence, ammo use and
heavy-round explosive splash are unchanged. A visible tracer is not a hitbox;
an explosive round still detonates after an actual direct collision.

## Correctness details

- World origin is a valid sweep start; no first segment is dropped there.
- A hit reports the actual body, surface position and collider shape index to
  the existing localized damage code, once per projectile.
- The ray ignores the source body and retries the same segment past any source
  child bodies. The usual path is one query. Retries are bounded at 32; exceeding
  that pathological overlap budget retires the bullet without invented damage.
- A launch inside real, non-source geometry is an immediate collision.
- World-origin shifts translate cached sweep positions along with live bullets.
  Inactive pooled bullets leave the shift group and rejoin on reuse.
- Pool reuse resets launch state and lifetime. Bullets no longer allocate a
  temporary physical self-collision-exception timer for each shot.

## Validation

`BulletPointCollisionSmoketest` passes 61 checks across all five gun profiles and
the legacy heavy scene. Tests include first-frame 2,000 m/s sweeps through 2 cm
plates, 5 cm-clear near misses despite forced legacy assist settings, nearest
surface occlusion, actual component attribution, duplicate-hit prevention,
pool reuse/expiry, source-child exclusions, inside-geometry launches, a real
floating-origin shift, zero-thickness terrain triangles, and unchanged rocket
physical contact support. Heavy splash is disabled only in the isolated direct
damage fixtures so those assertions measure one contact, not area damage.

The production-pilot integration run completed 45.02 simulation seconds: 41
rounds released, 19 target-damage events (190 damage), first damage at 16.73 s,
and the aircraft survived. This is a functional check, not a before/after hit-rate
comparison. The report is `user://bullet_point_guns_integration.json`; source
hashes verified at completion and against current files, with no GDScript
parse/runtime/invalid-call/access errors. Sources were held fixed during it.

The bullet optimization/pooling regression now requires the former assist-only
shot to miss. Tracer/cadence, gunnery harness, rocket-predictor (6 checks) and bomb
separation (9 checks) regressions also pass. Headless checks validate behavior,
not rendered appearance. Existing engine shutdown/resource warnings remain.

## Costs and limitations

### Target-hit feedback follow-up

Real target impacts now emit six short white-hot/yellow sparks for ordinary and
heavy bullets alike. Sparks use the swept hit position/normal, inherit target
point velocity, and shrink out over 0.18-0.30 seconds. Ground hits retain dirt;
near misses and virtual cosmetic impacts do not emit confirmation sparks.
No damage, collision or firing rules changed. The existing 96-active-debris
budget, pooling and distance/frustum culling bound the work; no per-hit lights
were added. Reuse resets emissive materials so dirt/metal cannot inherit glow.

Forward+ daylight and night captures were visually inspected. The focused spark
test covers actual-hit spawning, brightness, surface placement, expiry, reuse,
effect caps, heavy rounds, misses and ground exclusion; point collision (61)
and existing bullet pooling/impact regressions remain covered. Captures are
`user://bullet_hit_sparks_day.png` and `user://bullet_hit_sparks_night.png`.

### Collision model

Expected CPU work is one segment query per moving bullet per tick, with rare
source-child retries. Removed work includes target-list/shape assist queries,
unused collision shapes and per-shot collision-exception timers. No FPS gain is
claimed without a matched benchmark; visuals, damage effects and pooling still
have their existing costs.

The ray tests collider positions at the physics tick, not a continuous relative
sweep of each moving target. A fast target crossing completely between ticks
can still escape detection. Terrain must have a loaded physics collider; the
current LowPolyTerrain generates concave mesh collision by default, and bullets
no longer invent hits from height data if that collider is absent. Curved travel
is represented by one short chord per tick, as before.

Previously reported gunnery hit rates used target-sphere assistance and are not
an equivalent accuracy baseline for these point bullets. Future AI aiming work
should measure true collider hits; do not reintroduce oversized target envelopes
or change firing timing to recover the old scores.
