# Aircraft 1 wider main gear

User requested a modest stance change after post-catch wing contacts and
rollovers. Moved each main gear outward by 0.30 m: lateral positions +/-1.5 m
become +/-1.8 m, increasing the main-wheel track from 3.0 to 3.6 m (20%).
Both Left/RightGearRig and their corresponding collision shapes move together.
Nose gear, fore/aft locations, heights, spring/damping settings, damage policy,
downforce, cables and other aircraft are unchanged by this edit.

Aircraft1MainGearStanceSmoketest passes headlessly and in Forward+ rendering:
track width, unchanged height/wheelbase, visual-to-physics bindings, deployment
visibility, suspension compression, safe-gear classification and physics shape
alignment. Inspected the rendered image; gear roots remain under the wings.
Preview: `user://aircraft_1_wider_main_gear.png`. Existing cleanup warnings remain.

Started four Aircraft 1 random-RTB trials, seed 20260908, zero-based cases 3–6.
These include the preceding batch's two losses and one severely damaged stop,
plus one clean case. Run: `random_rtb_20260909_094548_seed_20260908`.
Background runner PID 36388; output prefix `aircraft1_wide_gear_20260909_094547`
in the Land Carrier Godot user-data directory. Monitored input hashes are
captured by the existing runner. The existing landing-test-progress heartbeat
will pick up progress/completion. Results are pending: wider geometry alone
does not establish that the rollover issue is solved.
