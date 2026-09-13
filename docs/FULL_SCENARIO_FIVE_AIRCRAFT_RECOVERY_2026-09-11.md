# Full-scenario five-aircraft recovery — 2026-09-11

## Outcome

Four of five aircraft caught arresting wires, stopped and were stowed at 100 health. The fifth was destroyed airborne during recovery approach, before final. This is encouraging evidence for stationary-deck recovery, not proof that recovery is generally fixed.

The carrier travelled approximately 1,250 m after receiving waypoints but was already stationary before recall. Its route remained active. The reason for stopping was not captured; this run does **not** validate moving-carrier touchdowns, and the stop cannot confidently be attributed to recovery constraints.

## Scope and method

- Visible normal `Main_Scene.tscn`, scenario 0, Open Canyons; normal terrain, enemies, combat, defenses and flight physics.
- Five real hangar/catapult launches. All five used `Aircraft_5.tscn`, the current normal hangar stock. Inventory names below are not model numbers.
- Carrier received legal player-route waypoints through the normal route API.
- All occupied cohort flights received return-to-base orders at 154.934 seconds, approximately one minute after the fifth launch.
- Diagnostic harness disabled campaign autosave and automatic mission tasking to prevent unrelated launches or reassignment; recovery supervision and flight mission execution remained enabled.
- No teleportation, forced catches, invulnerability, aircraft tuning or production AI/physics changes.
- Initial attempt queued aircraft while the carrier was held. Terrain-clearance launch blocking prevented any launch; that attempt was stopped and the harness adjusted to issue its waypoint immediately after queuing.

Harness: [FullScenarioFiveAircraftRecovery.gd](../Tests/FullScenarioFiveAircraftRecovery.gd).

## Recorded results

Times are elapsed seconds from harness start. First-touchdown sink values are contact telemetry, not a complete measure of landing quality.

| Inventory name | Launch | Approach begins | Wire catch | First touchdown sink | Stowed | Outcome |
| --- | ---: | ---: | --- | ---: | ---: | --- |
| Aircraft_1_1 | 26.660 | 155.949 | 288.730, wire 1 | 6.05 m/s | 329.746 | 100 health; hard but non-damaging contact |
| Aircraft_2_2 | 45.278 | 350.083 | 491.839, wire 1 | 2.78 m/s | 533.538 | 100 health |
| Aircraft_3_3 | 60.278 | 554.408 | 665.266, wire 2 | 0.02 m/s; later contact 2.91 m/s | 700.864 | 100 health; late wave-off before catch |
| Aircraft_5_5 | 93.898 | 684.501 | 804.328, wire 1 | 4.88 m/s | 845.892 | 100 health; hard but non-damaging contact |
| Aircraft_4_4 | 78.893 | 850.211 | None | No touchdown | — | Destroyed airborne at 878.325 |

No cohort aircraft emitted a crash signal. The four recovered aircraft had no damaging touchdown contacts. The run completed at 878.676 seconds (14 minutes 39 seconds); the last successful stow was 11 minutes 31 seconds after recall.

## Findings worth following up

### 1. Very late wave-off followed by a successful catch

Aircraft_3_3 switched to `MISSED_APPROACH` at about 664.17 seconds for `escape_deadline_no_reachable_wire`. The wire predictor reported no reachable wire while the deck-footprint prediction remained safe. At 665.266 seconds it touched down and caught wire 2, then stowed normally.

This warrants a focused review of the wire-reach prediction and wave-off deadline. It is not enough evidence to simply remove the safety check: the command itself may have changed the trajectory. Log the predicted hook path, wire intersection and available escape time beside the actual catch.

### 2. Long queue leaves the last aircraft exposed

Aircraft_4_4 remained in recovery hold from 170.181 to 850.211 seconds: approximately 11 minutes 20 seconds. Catch-to-stow took roughly 36–42 seconds for successful recoveries; the gaps between catches were approximately 203, 173 and 139 seconds.

Investigate whether approach preparation can overlap earlier aircraft stow operations while retaining exclusive final/deck clearance. Queue location and protection also matter in a full combat scenario.

### 3. The fifth loss was not a touchdown failure; its initial damage source is unresolved

Enemy engagement messages named Aircraft_4_4 at 809.6 and 820.0 seconds. At 869.53 seconds it was in `RECOVERY_APPROACH`, healthy and approximately 640 m above the carrier reference. At 870.54 seconds health had fallen to zero, followed by critical-damage deterioration and destruction at 878.325 seconds, still airborne.

Enemy fire is plausible, but the harness did not record source-tagged damage, so combat, collision or another cause cannot be conclusively distinguished. `CombatLog` counts generic `damaged` notifications, including critical-damage bleed: its “9 hits taken” summary must not be interpreted as nine projectile impacts. Add `combat_damage_received` and collision-cause logging before attributing this loss.

### 4. Moving-carrier recovery remains untested here

Carrier speed was already zero in the 120-second sample, before the 154.934-second recall, despite an active route. Instrument the navigation stop reason and establish sustained carrier movement in a follow-up before drawing conclusions about moving-deck recovery.

## Artifacts and limitations

Godot user-data folder: `C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier/`.

- `five_aircraft_recovery_travel_20260911.jsonl`: event and one-second flight telemetry.
- `five_aircraft_recovery_travel_20260911_status.json`: completed cohort summary.
- `five_aircraft_recovery_travel_20260911.log`: engine and combat output.
- `five_aircraft_recovery_20260911.*`: initial held-carrier attempt, before any launches.

No script/parse errors were found in the completed run log. Godot subsequently crashed with signal 11 during renderer teardown, after the complete result had been saved; process shutdown was therefore not clean. Campaign save sizes and modification times remained unchanged. No Godot process remained after completion.

Re-run from the project directory:

```powershell
& 'C:/Godot/Godot_v4.6.2-stable_win64_console.exe' --path . --windowed --script res://Tests/FullScenarioFiveAircraftRecovery.gd --log-file 'C:/Users/jonto/AppData/Roaming/Godot/app_userdata/Land Carrier/five_aircraft_recovery_followup.log' -- --test-scenario=0 --disable-campaign-autosave --label=five_aircraft_recovery_followup
```

Use a fresh label/log filename to preserve earlier evidence. This command repeats the diagnostic; it does not guarantee the carrier stays moving.
