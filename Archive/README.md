# Project archive

Historical files retained for reference, excluded from Godot's asset scan by
`.gdignore`. This directory is versioned; nothing here is automatically deleted.
Archive date: 2026-09-18.

## Historical reports

`docs/` contains these files moved from their original locations:

- `LANDING_RECOVERY_PROBLEM_REPORT_2026-07-31.md` (formerly project root): dated
  investigation and August update; current recovery status is in the main README.
- `AI Pilot Ground Attack Handoff 2026-07-27.md` (formerly `docs/`): explicitly
  historical handoff whose line references and failure rates need fresh evidence.
- `Land Carrier Bridge Jitter Problem.md` (formerly `docs/`): explicitly resolved
  diagnostic record, dated 2026-03-21.

These reports retain useful evidence. Archiving does not imply that every issue
or acceptance criterion in them has been resolved.

## Retired maintenance tools

`tools/` retains `archive_report.ps1`, `move_to_archive.ps1`, `move_unused.ps1`,
`list_used_files.ps1`, `list_used_files.gd`, and its `.uid`, formerly in `tools/`.
Do not use them to determine which project files are safe to move. Their default
example scene no longer exists; scanning one scene's literal dependencies misses
autoloads, dynamically selected resources, tests, and source assets. The GDScript
scanner also expects parentheses in scene resource declarations instead of the
bracket syntax used by the project's `.tscn` files.

The original tool contents are preserved as historical code, not a supported
workflow. For log retention, use `tools/clean_project_logs.ps1` at the project root.

See [project organization notes](../docs/PROJECT_ORGANIZATION.md) for active
folders and files deliberately retained.
