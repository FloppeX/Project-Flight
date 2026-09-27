# Local diagnostic logs

Project-side runtime logs belong here. Log files are ignored by Git and this
directory is excluded from Godot's asset scan. Normal `user://` logging remains
in Godot's user-data directory.

For manual smoke tests, redirect console output to `logs/<test-name>.log`.
Run `tools/clean_project_logs.ps1` to preview logs older than 14 days; add
`-Apply` to delete them. Use `-KeepDays 30` for a longer retention period.

Recordings/screenshots stay in `captures/` and `screenshots/`. Historical run
bundles stay in `run_archives/`; cleanup removes only their old `.log` files.
Optimizer JSON results and root champion JSON files are retained as tuning data.
