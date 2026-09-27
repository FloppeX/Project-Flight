# Operations and persistence repairs — 2026-09-18

## Behavior

- `GameSession` resets scene-owned operation state when the current scene exits,
  and before configuring a new campaign. AirOps flights, ground platoons/rescue
  jobs, coordinator assignments and enemy intelligence/schedules are reset.
  Pending checkpoint data and user camera preferences survive scene teardown.
- Explicit flight recall and release-to-automatic supersede individual orders.
  Recovery, departure and direct player control retain their existing protection.
- Rejected recovery commands leave the previous task and recovery-attempt state
  intact. The pilot exposes readiness/resource APIs and owns navigation-leg setup;
  the operations adapter no longer writes its navigation state directly.
- Enemy flight slots preserve health, localized part damage, energy and weapon
  ammunition through virtualization and checkpoints. Restoration waits for
  aircraft initialization; it does not replay detached-part debris. Changing
  simulation detail preserves the strategic mission. Interrupted materialization
  retains unspawned slots without resurrecting lost aircraft.
- Enemy checkpoint validation happens before applying campaign runtime state.
  Malformed unit records, missing aircraft/vehicle scenes and invalid combat
  snapshots fail restoration rather than producing a successful partial load.
  Older checkpoints without combat snapshots still load using scene defaults.
- Deck frame waits tolerate scene teardown. Computer-station display attachment
  runs after parent scene construction.
- Enemy ground platoons retain individual vehicle models and health through
  virtualization and checkpoint reloads. Casualties remain removed, including
  losses during interrupted spawning. Legacy scene lists remain palettes, so
  vehicle counts may exceed the number of available models.
- Ground HOLD clears member navigation through a shared platoon method used by
  GroundOps, the operations adapter and enemy mission application. Enemy RTB
  materialization routes home; simulation detail changes preserve mission intent.
- Virtual ground path requests release their shared budget when cleared or when
  their owner leaves the tree. Request serials reject stale or repeated results.

## Verification

Godot 4.6.2 headless, with campaign autosave disabled:

- ArchitectureStateSmoketest: rejected-command preservation; a real Aircraft_1
  damaged/ammunition/fuel round trip through virtual state and JSON; interrupted
  materialization; invalid restore; actual SceneTree replacement; compatibility.
- OperationsMissionManagementSmoketest: existing coverage plus recall/release of
  an individually tasked member.
- EnemyGroundPersistenceSmoketest: real buggy/pickup scenes; legacy palette
  compatibility; survivor model/health JSON round trip; casualty and interrupted
  spawn preservation; HOLD/RTB routing; adapter HOLD; simulated pending path
  requests across scene detachment and stale/duplicate callback delivery.
- operations_contract_smoketest, GroundRescueSmoketest,
  enemy_investigation_smoketest, DeckTowPauseSmoketest,
  ComputerStationSmoketest and SaveStateSmoketest passed.

The save/load test still logs headless renderer null-material and shutdown
resource-leak diagnostics. Focused state tests do not establish visual correctness
or full mission-to-landing reliability. The ground persistence test also reports
a dummy-renderer mesh leak and ObjectDB instances at shutdown. Its terrain and
contact scanning are stubbed; it does not validate driving over real terrain.

## Repository cleanup

Generated `.godot` files and tracked `.log` files are removed from the Git index;
local files remain present and existing ignore rules cover subsequent changes.
