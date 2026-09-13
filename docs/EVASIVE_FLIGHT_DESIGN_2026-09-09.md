# Evasive flight: proposed first slice

Implementation and validation follow-up: `EVASIVE_FLIGHT_IMPLEMENTATION_2026-09-09.md`.
The text below preserves the original staged design; consult the follow-up for
what is implemented, tested or still deferred.

Design only; this document does not enable new defensive behavior. First make
close-range separation reliable enough that an evasive break can use the same
control path. Preserve the existing player-equivalent controls and measured
energy limits. Do not add force/attitude overrides or an omniscient attacker feed.

## Knowledge and triggers

- Visual threat: a recent observed track behind/abeam the aircraft, closing and
  pointing approximately toward it. Observed velocity is only an approximation
  of nose direction; it cannot prove the attacker is firing. Require persistence
  and confidence rather than an immediate response to every nearby contact.
- Damage: hull or component damage can raise danger without identifying an
  attacker. Component damage matters because many gun hits do not reduce hull
  health. A generic damage callback alone cannot distinguish bullets from ground
  contact: carry a damage-source category before calling this "taking fire."
- Near miss, later: a projectile segment near the aircraft may supply a coarse
  bearing, not the shooter's exact live transform. Avoid scanning every projectile
  against every aircraft. Use a local broad-phase query on projectile movement,
  merge repeated events per aircraft, and profile actual combat load first.
- Controller warning, later: delayed coarse report with timestamp/uncertainty;
  not a free visual lock or permission to shoot through occlusion.

Current `_on_aircraft_damaged` still contains a legacy nearest-enemy awareness
boost. Replace that inference when implementing damage-driven evasion. A hit
does not identify the nearest aircraft as its source.

## Small committed maneuver, not random per-frame jinking

Start with a break turn and an unloaded extension, not a full aerobatic repertoire.
Use a short reaction delay and a bounded maneuver commitment, with cooldown and
hysteresis. Skill can improve recognition/delay and energy judgment; it must not
expose hidden target transforms or permit impossible surface authority.

With an observed threat, choose a direction that increases angular motion across
its estimated line of fire while respecting separation. With an unknown source,
use own velocity, bank and clearance to choose a stable initial break; do not aim
toward an invented attacker position. Reassess only after the minimum commitment
or a genuine safety exception, rather than flipping sides every tick.

Flight-path requests go through the normal bank/load/vertical controller. Permit
a descending break with clearance; unload/extend when speed reserve is poor.
Do not add a universal climb bias. Suppress offensive gun bursts during a committed
break, then reacquire or return to the assigned mission after the danger subsides.

Control priority: terrain clearance, imminent aircraft separation, committed
evasion, energy recovery, offensive pursuit/mission navigation. One controller
must resolve the combined achievable request; multiple systems must not alternate
independent roll/pitch commands.

## Verification before enabling fleet-wide

1. Unit tests: unknown-source damage does not reveal a target; component hits
   produce a danger event; stale tracks expire; no reaction to ordinary landing
   contacts; hysteresis and commitment; no descent through the terrain floor.
2. Controlled attacker with an unlimited-health defender: sustained tail attack,
   side attack, brief visual occlusion, repeated near misses, and no-threat control.
   Measure time in the attacker's firing cone, tracking breaks, energy loss,
   reaction latency, separation and terrain clearance. Unlimited health prevents
   early kills from hiding pursuit/evasion behavior; it is not a survival result.
3. Paired normal-health duels across aircraft 3/5, both starting sides and multiple
   seeds. Count projectile hits and component damage separately; distinguish
   gun victories, collision/terrain losses and timeouts. Do not require every
   evasive maneuver to succeed, or optimize only for survival by permanent escape.
4. Re-run no-threat tail/gentle/crossing precision tests and recovery regressions.
   If these regress, narrow the threat trigger before tuning maneuver aggression.

The existing observation cadence and a few vector operations per tracked threat
should be modest work, but that is a scaling estimate, not measured performance.
Near-miss sensing is the potentially expensive addition and is deliberately
separate from the first slice. No GA until the knowledge and control invariants pass.
