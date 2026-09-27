# Visible continuous RTB test

Run `Tests/ContinuousRTBTest.gd` with Godot's `--script` option. The test uses the normal main scene, authored aircraft scenes, AirOps RTB orders, recovery routing, wire capture and carrier stow. It loops Aircraft 1, 2, 5, 14 serially. Each model alternates sides on successive rounds; spawn range varies from 3.2 to 4 km behind the carrier with a 1.4 km lateral offset and terrain-aware altitude. Initial speed is at least 75 m/s or stall speed plus 25 m/s. Weather and aircraft handling retain their normal settings.

The overlay provides Follow aircraft, Carrier view, Pause/Resume and Skip aircraft. Close the test window to stop. Each uncaught aircraft has a 900-second simulated-time budget. Skip and timeout wait for a caught aircraft to finish stowing rather than deleting it during a deck-owned recovery job; a stalled deck job can therefore stall the loop and remains visible. No success is inferred from a mere wire contact: the tally counts completed stows. Losses, skips and timeouts count separately from stows in the event records.

Enemy spawning and automatic mission tasking are disabled, and autosaving is off. This is a temporary test world. Stored inventory is restored to its initial test-world snapshot after each trial to prevent indefinite growth. It is not a launch, combat, or concurrent recovery-queue test.

Example PowerShell launch:

```powershell
& 'C:\Godot\Godot_v4.6.2-stable_win64.exe' --path 'C:\Godot projects\Project-Flight' --script res://Tests/ContinuousRTBTest.gd -- --label=continuous_rtb_visible
```

Events and current status are written under `%APPDATA%\Godot\app_userdata\Land Carrier\`, using the label plus `.jsonl` and `_status.json`. The current visible run also redirects output to `logs/continuous_rtb_visible.log` and `logs/continuous_rtb_visible_errors.log`.

For a bounded plumbing check, use `--headless --fixed-fps 60` and user arguments `--trials=4 --trial-timeout=5 --label=continuous_rtb_smoke`. All four models spawned, received normal RTB orders, advanced and exited without script errors in that check. Its intentionally short timeouts do not test landing success. The visible run is intended for observing that behavior.

## Headless 100-attempt assessment

Use `--batch-model=1` (or 2, 5, 14), `--trials=25`, `--trial-timeout=900`, and a unique `--label` with `--headless --fixed-fps 60`. Each model runs the same five profiles five times: near outbound, standard inbound, high/fast, crossing and low return, with alternating sides. The low profile is lifted to at least 200 m above local terrain at spawn. Weather remains live. The headless path omits the test overlay/follow camera, and keeps all outcomes/transitions plus five-second diagnostic snapshots.

The active batch directory is recorded in `logs/active_rtb_batch.txt`; its manifest records workers, settings and source hashes. `python tools/summarize_rtb_batch.py` refreshes JSON, CSV and Markdown results, including failures in denominators and successful-only timing statistics. This is a baseline measurement; gameplay code is not changed mid-batch. A quiet task follow-up checks completion and worker health every ten minutes.
