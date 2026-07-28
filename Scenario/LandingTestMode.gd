extends Node3D
## Landing test harness (scenario 5). Spawns Aircraft_5 aircraft near the carrier whose only job is to
## LAND. In the normal path-development mode one aircraft at a time spawns at a random point
## 5-6 km from the carrier at 450-2000 m altitude and flies the complete recovery path. The optional
## genetic mode retains its deterministic close-final curriculum. Once an aircraft catches a wire (CAUGHT) or
## bolters/waves off (BOLTER), or crashes/times out (CRASH/TIMEOUT), its outcome is logged and it is
## despawned. Outcome records are structured for a future genetic-algorithm tuner.

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
const LANDING_GA_SCRIPT: Script = preload("res://AI/LandingGeneticTuner.gd")
const REPORT_PATH := "user://landing_test_report.log"

# Every candidate in a generation sees the same six cases. Five catches promote the population to
# the next level, preserving useful genes while shortening and dirtying the entry in modest steps.
# Coordinates are carrier-relative: positive behind_m is on the approach side; lateral_m is deck-right;
# altitude is above the carrier root. Altitudes approximate the 5.9deg slope with deliberate errors.
const GA_CURRICULA := [
	[
		{"behind_m": 1000.0, "lateral_m": 0.0, "alt_m": 105.0, "heading_offset_deg": 0.0},
		{"behind_m": 950.0, "lateral_m": 40.0, "alt_m": 108.0, "heading_offset_deg": -3.0},
		{"behind_m": 950.0, "lateral_m": -40.0, "alt_m": 90.0, "heading_offset_deg": 3.0},
		{"behind_m": 900.0, "lateral_m": 60.0, "alt_m": 104.0, "heading_offset_deg": -4.0},
		{"behind_m": 900.0, "lateral_m": -60.0, "alt_m": 84.0, "heading_offset_deg": 4.0},
		{"behind_m": 850.0, "lateral_m": 70.0, "alt_m": 96.0, "heading_offset_deg": -5.0},
	],
	[
		{"behind_m": 900.0, "lateral_m": 0.0, "alt_m": 94.0, "heading_offset_deg": 0.0},
		{"behind_m": 850.0, "lateral_m": 60.0, "alt_m": 96.0, "heading_offset_deg": -4.0},
		{"behind_m": 850.0, "lateral_m": -60.0, "alt_m": 80.0, "heading_offset_deg": 4.0},
		{"behind_m": 800.0, "lateral_m": 75.0, "alt_m": 94.0, "heading_offset_deg": -5.0},
		{"behind_m": 800.0, "lateral_m": -75.0, "alt_m": 72.0, "heading_offset_deg": 5.0},
		{"behind_m": 750.0, "lateral_m": 85.0, "alt_m": 88.0, "heading_offset_deg": -6.0},
	],
	[
		{"behind_m": 800.0, "lateral_m": 0.0, "alt_m": 84.0, "heading_offset_deg": 0.0},
		{"behind_m": 750.0, "lateral_m": 75.0, "alt_m": 88.0, "heading_offset_deg": -5.0},
		{"behind_m": 750.0, "lateral_m": -75.0, "alt_m": 68.0, "heading_offset_deg": 5.0},
		{"behind_m": 700.0, "lateral_m": 90.0, "alt_m": 86.0, "heading_offset_deg": -6.0},
		{"behind_m": 700.0, "lateral_m": -90.0, "alt_m": 62.0, "heading_offset_deg": 6.0},
		{"behind_m": 650.0, "lateral_m": 100.0, "alt_m": 80.0, "heading_offset_deg": -7.0},
	],
	[
		{"behind_m": 700.0, "lateral_m": 0.0, "alt_m": 73.0, "heading_offset_deg": 0.0},
		{"behind_m": 650.0, "lateral_m": 90.0, "alt_m": 80.0, "heading_offset_deg": -6.0},
		{"behind_m": 650.0, "lateral_m": -90.0, "alt_m": 60.0, "heading_offset_deg": 6.0},
		{"behind_m": 600.0, "lateral_m": 105.0, "alt_m": 76.0, "heading_offset_deg": -7.0},
		{"behind_m": 600.0, "lateral_m": -105.0, "alt_m": 54.0, "heading_offset_deg": 7.0},
		{"behind_m": 550.0, "lateral_m": 100.0, "alt_m": 70.0, "heading_offset_deg": -8.0},
	],
	[
		{"behind_m": 600.0, "lateral_m": 0.0, "alt_m": 63.0, "heading_offset_deg": 0.0},
		{"behind_m": 550.0, "lateral_m": 90.0, "alt_m": 70.0, "heading_offset_deg": -7.0},
		{"behind_m": 550.0, "lateral_m": -90.0, "alt_m": 50.0, "heading_offset_deg": 7.0},
		{"behind_m": 500.0, "lateral_m": 90.0, "alt_m": 62.0, "heading_offset_deg": -8.0},
		{"behind_m": 500.0, "lateral_m": -90.0, "alt_m": 46.0, "heading_offset_deg": 8.0},
		{"behind_m": 450.0, "lateral_m": 80.0, "alt_m": 56.0, "heading_offset_deg": -8.0},
	],
]

@export var spawn_interval_s: float = 20.0
@export var max_simultaneous: int = 1
@export var spawn_dist_min_m: float = 5000.0
@export var spawn_dist_max_m: float = 6000.0
@export var spawn_alt_min_m: float = 450.0
@export var spawn_alt_max_m: float = 900.0  # Develop the complete route first; high-energy recovery can be expanded later
@export var spawn_speed_mps: float = 90.0
@export var genetic_spawn_speed_mps: float = 55.0
@export var genetic_spawn_fpa_deg: float = 5.9
@export var spawn_heading_jitter_deg: float = 25.0    # random yaw off the carrier bearing
@export var attempt_timeout_s: float = 360.0          # includes terrain holding plus the long outbound intercept
@export var compare_flows: bool = false               # true = alternate new-recovery / old-direct per spawn; false = all recovery (the flow we're tuning)
@export var summary_interval_s: float = 10.0
@export var spawn_min_agl_m: float = 350.0            # never spawn closer to the terrain than this (terrain 5km out can be far higher than at the carrier)
@export var teleport_recycle_dist_m: float = 15000.0  # a live test aircraft farther than this got origin-shift-flung; recycle it instead of wasting its timeout
@export var transform_trace_duration_s: float = 25.0  # trace the first lander through the reported t~10 failure and the first origin shift
@export var transform_trace_interval_s: float = 0.5
@export var transform_trace_jump_m: float = 100.0
@export var genetic_tuning_enabled: bool = false
@export var genetic_population_size: int = 8
@export var genetic_elite_count: int = 2
@export var genetic_mutations_per_child: int = 4
@export var genetic_mutation_scale: float = 1.0
@export var genetic_trial_timeout_s: float = 90.0
@export var genetic_freeze_carrier: bool = true
@export var freeze_carrier_for_test: bool = true
@export var remove_bombs_from_test_aircraft: bool = true

var _play_area_center: Vector3 = Vector3.ZERO
var _elapsed_s: float = 0.0
var _spawn_timer: float = 0.0
var _summary_timer: float = 0.0
var _spawn_index: int = 0
var _started: bool = false
var _waiting_for_carrier_placement: bool = false
var _ga_tuner: Node = null
var _focused_final_diagnostic: bool = false
# name -> {node, flow, spawn_t, spawn_pos, spawn_alt, spawn_dist, outcome}
var _attempts: Dictionary = {}
# Aggregate tally per flow: flow -> {"CAUGHT":n, "BOLTER":n, "CRASH":n, "TIMEOUT":n}
var _tally: Dictionary = {"recovery": {}, "direct": {}}


func configure(play_area_center: Vector3) -> void:
	_play_area_center = play_area_center


func _ready() -> void:
	_focused_final_diagnostic = OS.get_cmdline_user_args().has("--landing-final-diagnostic")
	if _focused_final_diagnostic:
		max_simultaneous = 1
		spawn_interval_s = minf(spawn_interval_s, 2.0)
		attempt_timeout_s = 75.0
		spawn_min_agl_m = 60.0
	if genetic_tuning_enabled:
		# Sequential trials avoid deck-clearance queue time contaminating fitness. The tuner saves
		# after every result, so this can safely run unattended and resume after a restart.
		max_simultaneous = 1
		spawn_interval_s = minf(spawn_interval_s, 2.0)
		spawn_speed_mps = genetic_spawn_speed_mps
		# The selected carrier heading verifies the nominal glideslope itself clears terrain. The broad
		# exploratory test's 350 m AGL spawn clamp would move these controlled final starts far off-slope.
		spawn_min_agl_m = 60.0
		attempt_timeout_s = genetic_trial_timeout_s
		_ga_tuner = Node.new()
		_ga_tuner.name = "LandingGeneticTuner"
		_ga_tuner.set_script(LANDING_GA_SCRIPT)
		_ga_tuner.set("population_size", genetic_population_size)
		_ga_tuner.set("elite_count", genetic_elite_count)
		_ga_tuner.set("mutations_per_child", genetic_mutations_per_child)
		_ga_tuner.set("mutation_scale", genetic_mutation_scale)
		_ga_tuner.set("case_count", (GA_CURRICULA[0] as Array).size())
		_ga_tuner.set("curriculum_level_count", GA_CURRICULA.size())
		add_child(_ga_tuner)
	else:
		var truncate: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
		if truncate != null:
			truncate.close()
	_log("START landing test: Aircraft_5 every %.0fs up to %d, %.0f-%.0fm out, %.0f-%.0fm alt" % [
		spawn_interval_s, max_simultaneous, spawn_dist_min_m, spawn_dist_max_m, spawn_alt_min_m, spawn_alt_max_m])
	if genetic_tuning_enabled and is_instance_valid(_ga_tuner):
		_log("GA_ENABLED curricula=%d deterministic_cases_per_level=%d status=%s" % [
			GA_CURRICULA.size(), (GA_CURRICULA[0] as Array).size(), JSON.stringify(_ga_tuner.call("get_status"))])
	_suppress_carrier_air_ops()
	_clear_scene_clutter()
	# LandCarrier starts hidden at the scene origin while its asynchronous NavGraph job
	# chooses the real patrol start (often tens of kilometres away). Spawning before it
	# becomes visible strands test aircraft at the temporary origin; the first camera-
	# driven origin shift then makes that look like an aircraft teleport.
	_waiting_for_carrier_placement = true
	_log("WAITING for carrier initial placement")


func _suppress_carrier_air_ops() -> void:
	# Stop AirOps/Enemy/Ground ops so nothing else spawns/launches into the test.
	for autoload_name in ["AirOpsManager", "EnemyOpsManager", "GroundOpsManager"]:
		var node: Node = get_node_or_null("/root/" + autoload_name)
		if node != null:
			node.set_process(false)
			node.set_physics_process(false)
			_log("SUPPRESSED %s" % autoload_name)


func shutdown() -> void:
	## Toggled off (L key): despawn all test aircraft, log the final tally, and restore the ops managers.
	_started = false
	_log("SHUTDOWN — final tally:")
	_log_summary()
	for name in _attempts.keys():
		var a: Dictionary = _attempts[name]
		var node: Variant = a.get("node")
		if is_instance_valid(node):
			(node as Node).queue_free()
	_attempts.clear()
	for autoload_name in ["AirOpsManager", "EnemyOpsManager", "GroundOpsManager"]:
		var node: Node = get_node_or_null("/root/" + autoload_name)
		if node != null:
			node.set_process(true)
			node.set_physics_process(true)
	_log("ops managers restored")


func _clear_scene_clutter() -> void:
	var clutter_groups: Array[String] = [
		# GroundOpsManager owns the friendly platoon controller nodes for the
		# lifetime of the application. Removing those nodes leaves stale entries
		# in its platoons dictionary after the landing test ends. Clearing the
		# actual ground vehicles is sufficient to keep the landing test empty.
		"buildings", "enemy_bases", "ground_vehicles",
		"gun_emplacements", "wind_turbines", "wind_turbine_proxies", "enemy_aircraft_spawner",
	]
	var removed: int = 0
	for group_name in clutter_groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node):
				node.queue_free()
				removed += 1
	for node in get_tree().get_nodes_in_group("ai_aircraft"):
		if is_instance_valid(node):
			node.queue_free()
			removed += 1
	_log("SCENE_CLEARED removed=%d clutter nodes" % removed)


func _physics_process(delta: float) -> void:
	if not _started:
		_try_start_after_carrier_placement()
		return
	_elapsed_s += delta
	_trace_first_lander()
	_sample_ga_metrics()
	_poll_outcomes()
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = maxf(spawn_interval_s, 1.0)
		if _live_count() < max_simultaneous:
			_spawn_lander()
	_summary_timer -= delta
	if _summary_timer <= 0.0:
		_summary_timer = maxf(summary_interval_s, 1.0)
		_log_summary()


func _try_start_after_carrier_placement() -> void:
	if not _waiting_for_carrier_placement:
		return
	var carrier := _carrier()
	if not is_instance_valid(carrier):
		return
	if carrier.has_method("is_initial_placement_complete") \
			and not bool(carrier.call("is_initial_placement_complete")):
		return
	if not carrier.visible:
		return
	if freeze_carrier_for_test or genetic_tuning_enabled:
		if not _prepare_landing_test_carrier(carrier):
			# Do not generate meaningless HOLD timeouts when no safe approach heading exists.
			_waiting_for_carrier_placement = false
			return
	_waiting_for_carrier_placement = false
	_started = true
	_log("READY carrier placed at %s" % _vec3_text(carrier.global_position))


func _prepare_landing_test_carrier(carrier: Node3D) -> bool:
	var should_freeze: bool = freeze_carrier_for_test or (genetic_tuning_enabled and genetic_freeze_carrier)
	if should_freeze and carrier.has_method("set_heli_test_stationary"):
		carrier.call("set_heli_test_stationary", true)
	var fdm := get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm == null or not fdm.has_method("_landing_path_clear_of_terrain"):
		_log("Landing-test carrier frozen; landing-path terrain verifier unavailable")
		return true
	var terrain: Node = get_tree().get_first_node_in_group("terrain_provider")
	if terrain == null or not terrain.has_method("get_height"):
		_log("Landing-test carrier frozen; terrain height provider unavailable")
		return true

	# A legal footprint does not imply a legal 4.5 km glideslope. Search deterministic nearby
	# poses, nearest first, and validate both the tread footprint and the complete tapered landing
	# corridor before spawning a pilot. Rotating in place alone failed when the carrier happened to
	# start in a basin surrounded by ridges.
	var original_transform: Transform3D = carrier.global_transform
	var original_ground_m: float = float(terrain.call("get_height", original_transform.origin))
	var ride_height_m: float = original_transform.origin.y - original_ground_m
	if not is_finite(ride_height_m) or ride_height_m < 10.0 or ride_height_m > 100.0:
		ride_height_m = 40.0
	var position_offsets: Array[Vector3] = [Vector3.ZERO]
	for radius_m in [400.0, 800.0, 1200.0, 1800.0, 2600.0, 3600.0, 4800.0]:
		for bearing_deg in range(0, 360, 45):
			position_offsets.append(
				Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(float(bearing_deg))) * radius_m
			)
	var original_heading_rad: float = original_transform.basis.get_euler().y
	var poses_tested: int = 0
	for position_offset in position_offsets:
		var candidate_xz: Vector3 = original_transform.origin + position_offset
		var candidate_ground_m: float = float(terrain.call("get_height", candidate_xz))
		if not is_finite(candidate_ground_m):
			continue
		var candidate_position := Vector3(
			candidate_xz.x,
			candidate_ground_m + ride_height_m,
			candidate_xz.z
		)
		for heading_step_deg in range(0, 360, 10):
			var candidate_heading_rad: float = original_heading_rad + deg_to_rad(float(heading_step_deg))
			var candidate_basis := Basis(Vector3.UP, candidate_heading_rad)
			if not _landing_test_carrier_surface_is_flat(candidate_position, candidate_basis, terrain):
				continue
			carrier.global_transform = Transform3D(candidate_basis, candidate_position)
			poses_tested += 1
			if bool(fdm.call("_landing_path_clear_of_terrain", true)):
				if should_freeze and carrier.has_method("set_heli_test_stationary"):
					carrier.call("set_heli_test_stationary", true)
				_log("Landing-test carrier staged pos=%s heading=%.0fdeg moved=%.0fm poses=%d corridor=clear" % [
					_vec3_text(candidate_position),
					rad_to_deg(candidate_heading_rad),
					Vector2(position_offset.x, position_offset.z).length(),
					poses_tested,
				])
				return true
	carrier.global_transform = original_transform
	_log("LANDING_BLOCKED no flat pose with a terrain-clear landing corridor; poses=%d" % poses_tested)
	return false


func _landing_test_carrier_surface_is_flat(position: Vector3, basis: Basis, terrain: Node) -> bool:
	var forward := Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var min_height_m: float = INF
	var max_height_m: float = -INF
	for longitudinal_m in [-150.0, 0.0, 150.0]:
		for lateral_m in [-55.0, 0.0, 55.0]:
			var probe: Vector3 = position + forward * float(longitudinal_m) + right * float(lateral_m)
			var height_m: float = float(terrain.call("get_height", probe))
			if not is_finite(height_m):
				return false
			min_height_m = minf(min_height_m, height_m)
			max_height_m = maxf(max_height_m, height_m)
	return max_height_m - min_height_m <= 8.0


func _live_count() -> int:
	var n: int = 0
	for name in _attempts.keys():
		var a: Dictionary = _attempts[name]
		if a.get("outcome", "") == "" and is_instance_valid(a.get("node")):
			n += 1
	return n


func _carrier() -> Node3D:
	return get_tree().get_first_node_in_group("carrier") as Node3D


func _spawn_lander() -> void:
	var carrier := _carrier()
	if not is_instance_valid(carrier):
		return
	var craft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	if craft == null:
		_log("ERROR could not instantiate Aircraft_5")
		return
	_spawn_index += 1
	var flow: String = "recovery"
	if compare_flows and (_spawn_index % 2 == 0):
		flow = "direct"
	if _focused_final_diagnostic:
		flow = "direct"
	var ga_assignment: Dictionary = {}
	if genetic_tuning_enabled and is_instance_valid(_ga_tuner):
		ga_assignment = _ga_tuner.call("next_assignment") as Dictionary
	if not ga_assignment.is_empty():
		flow = "direct"
	var craft_name: String
	if not ga_assignment.is_empty():
		craft_name = "Land_L%d_G%03d_C%02d_S%d" % [
			int(ga_assignment.get("curriculum", 0)),
			int(ga_assignment.get("generation", 0)),
			int(ga_assignment.get("candidate", 0)),
			int(ga_assignment.get("case", 0)),
		]
	else:
		craft_name = "Land_%03d_%s" % [_spawn_index, flow]
	craft.name = craft_name

	var bearing: float
	var dist: float
	var alt: float
	var heading_offset_deg: float
	var spawn_pos: Vector3
	if _focused_final_diagnostic:
		var carrier_forward := carrier.global_transform.basis.z
		carrier_forward.y = 0.0
		carrier_forward = carrier_forward.normalized() if carrier_forward.length_squared() > 0.001 else Vector3.FORWARD
		var behind_m := 1000.0
		alt = behind_m * tan(deg_to_rad(maxf(genetic_spawn_fpa_deg, 0.0)))
		heading_offset_deg = 0.0
		spawn_pos = carrier.global_position - carrier_forward * behind_m
		spawn_pos.y = carrier.global_position.y + alt
		dist = behind_m
		bearing = atan2(spawn_pos.x - carrier.global_position.x, spawn_pos.z - carrier.global_position.z)
	elif not ga_assignment.is_empty():
		var curriculum_index := clampi(int(ga_assignment.get("curriculum", 0)), 0, GA_CURRICULA.size() - 1)
		var curriculum_cases: Array = GA_CURRICULA[curriculum_index]
		var case_index := clampi(int(ga_assignment.get("case", 0)), 0, curriculum_cases.size() - 1)
		var spawn_case: Dictionary = curriculum_cases[case_index]
		var carrier_forward := carrier.global_transform.basis.z
		var carrier_right := carrier.global_transform.basis.x
		carrier_forward.y = 0.0
		carrier_right.y = 0.0
		carrier_forward = carrier_forward.normalized() if carrier_forward.length_squared() > 0.001 else Vector3.FORWARD
		carrier_right = carrier_right.normalized() if carrier_right.length_squared() > 0.001 else Vector3.RIGHT
		var behind_m := float(spawn_case["behind_m"])
		var lateral_m := float(spawn_case["lateral_m"])
		alt = float(spawn_case["alt_m"])
		heading_offset_deg = float(spawn_case["heading_offset_deg"])
		spawn_pos = carrier.global_position - carrier_forward * behind_m + carrier_right * lateral_m
		spawn_pos.y = carrier.global_position.y + alt
		dist = Vector2(spawn_pos.x - carrier.global_position.x, spawn_pos.z - carrier.global_position.z).length()
		bearing = atan2(spawn_pos.x - carrier.global_position.x, spawn_pos.z - carrier.global_position.z)
	else:
		# Legacy exploratory mode retains broad randomized spawns when the GA is disabled.
		bearing = randf() * TAU
		dist = randf_range(spawn_dist_min_m, spawn_dist_max_m)
		var dir: Vector3 = Vector3(sin(bearing), 0.0, cos(bearing))
		alt = randf_range(spawn_alt_min_m, spawn_alt_max_m)
		heading_offset_deg = randf_range(-spawn_heading_jitter_deg, spawn_heading_jitter_deg)
		spawn_pos = carrier.global_position + dir * dist
		spawn_pos.y = carrier.global_position.y + alt
	# Terrain clamp: altitude is picked relative to the CARRIER, but terrain 5-6km out can be much higher
	# -- low spawns were appearing right on ridge tops and crashing in seconds. Never spawn below
	# terrain + spawn_min_agl_m.
	var terrain: Node = get_tree().get_first_node_in_group("terrain_provider")
	if terrain != null and terrain.has_method("get_height"):
		var th: float = float(terrain.call("get_height", spawn_pos))
		if is_finite(th):
			spawn_pos.y = maxf(spawn_pos.y, th + spawn_min_agl_m)

	# Keep it out of the "aircraft" group (FlightDeckManager grabs that as the player).
	if craft.is_in_group("aircraft"):
		craft.remove_from_group("aircraft")
	craft.add_to_group("friendlies")
	craft.set("team", 1)
	craft.set_meta("carrier_transport_mode", false)
	craft.set_meta("controls_disabled", false)
	craft.set_meta("landing_test_aircraft", true)
	craft.freeze = false
	get_tree().current_scene.add_child(craft)
	var removed_bomb_mass_kg := 0.0
	if remove_bombs_from_test_aircraft:
		removed_bomb_mass_kg = _remove_bombs(craft)
	craft.global_position = spawn_pos
	# Face roughly toward the carrier with some heading jitter.
	var look: Vector3 = carrier.global_position
	look.y = spawn_pos.y
	craft.look_at(look, Vector3.UP)
	craft.rotate_y(PI)  # Aircraft_5 nose is +Z; look_at aims -Z.
	var jitter: float = deg_to_rad(heading_offset_deg)
	craft.rotate_y(jitter)
	# Aircraft_5 flies nose-first along local +Z. After look_at()+PI above, +Z points
	# at the carrier; using -Z here launched the test aircraft tail-first, causing an
	# immediate airspeed loss, stall, and near-vertical dive.
	var spawn_velocity_dir: Vector3 = craft.global_transform.basis.z.normalized()
	if not ga_assignment.is_empty():
		# Deterministic final-approach cases begin with the FPV already on the nominal slope. Starting
		# level this close to the carrier turns every trial into an artificial dive-capture transient.
		spawn_velocity_dir.y = -tan(deg_to_rad(maxf(genetic_spawn_fpa_deg, 0.0)))
		spawn_velocity_dir = spawn_velocity_dir.normalized()
	craft.linear_velocity = spawn_velocity_dir * spawn_speed_mps
	craft.angular_velocity = Vector3.ZERO
	# Push the spawn transform into the physics server -- setting global_position on a RigidBody3D far
	# from origin doesn't update the server's authoritative transform, so it snaps/teleports on the next
	# physics step. Sync it explicitly (velocity is set separately above / preserved).
	PhysicsServer3D.body_set_state(craft.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, craft.global_transform)
	craft.reset_physics_interpolation()

	var ai_toggle: Node = craft.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("enable_ai"):
		ai_toggle.call("enable_ai")

	var pilot: Node = craft.find_child("AIPilot", true, false)
	if pilot != null:
		if not ga_assignment.is_empty() and is_instance_valid(_ga_tuner):
			_ga_tuner.call("apply_genome", pilot, ga_assignment.get("genome", {}))
		pilot.set("dogfight_enabled", false)
		pilot.set("ground_attack_enabled", false)
		pilot.set("land_after_launch", false)
		pilot.set("rtb_health_threshold", 0.0)
		pilot.set("rtb_fuel_threshold", 0.0)
		pilot.set("carrier_position", carrier.global_position)
		# Kick off the chosen landing flow next frame (after the pilot's own _ready has run).
		call_deferred("_begin_landing_flow", pilot, flow)

	_attempts[craft_name] = {
		"node": craft,
		"spawn_index": _spawn_index,
		"flow": flow,
		"spawn_t": _elapsed_s,
		"spawn_pos": spawn_pos,
		"spawn_alt": alt,
		"spawn_dist": dist,
		"outcome": "",
		"ga_assignment": ga_assignment.duplicate(true),
		"reached_glideslope": false,
		"reached_final": false,
		"min_remaining_m": INF,
		"min_lateral_m": INF,
		"min_vertical_m": INF,
		"final_samples": 0,
		"fpv_yaw_error_integral": 0.0,
		"fpv_pitch_error_integral": 0.0,
		"cone_capture_logged": false,
		"cone_gate_logged": false,
		"final_settled_logged": false,
		"cone_capture_remaining_m": NAN,
		"cone_capture_behind_m": NAN,
		"final_settled_remaining_m": NAN,
		"final_settled_behind_m": NAN,
		"cone_gate_passed": false,
		"cone_latest_status": {},
		"trace_next_t": 0.0,
		"trace_last_global": craft.global_position,
		"trace_last_parent_id": craft.get_parent().get_instance_id() if craft.get_parent() != null else 0,
	}
	if craft.has_signal("destroyed"):
		craft.connect("destroyed", Callable(self, "_on_craft_destroyed").bind(craft_name))
	if craft.has_signal("crashed"):
		craft.connect("crashed", Callable(self, "_on_craft_crashed").bind(craft_name))
	_log("SPAWN %s flow=%s dist=%.0f alt=%.0f bearing=%.0fdeg bomb_mass_removed=%.0fkg mass=%.0fkg ga=%s" % [
		craft_name, flow, dist, alt, rad_to_deg(bearing), removed_bomb_mass_kg, craft.mass,
		JSON.stringify(ga_assignment)])


func _remove_bombs(craft: RigidBody3D) -> float:
	# Landing trials should measure the approach controller rather than a strike loadout. Leave guns,
	# rockets, and normal-game aircraft untouched; only unmount bomb weapons from this test instance.
	var loaded_mass_kg := craft.mass
	for node in craft.find_children("*", "Hardpoint", true, false):
		var hardpoint := node as Hardpoint
		if hardpoint == null or not is_instance_valid(hardpoint.weapon_instance):
			continue
		var weapon := hardpoint.weapon_instance
		if str(weapon.get("weapon_name")) != "Bomb":
			continue
		if craft.has_method("clear_payload_mass"):
			craft.call("clear_payload_mass", weapon)
		hardpoint.mounted_weapon = null
		weapon.queue_free()
		hardpoint.weapon_instance = null
	return maxf(loaded_mass_kg - craft.mass, 0.0)


func _begin_landing_flow(pilot: Node, flow: String) -> void:
	# aircraft.gd intentionally completes initialization one process frame after _ready(). A deferred
	# call still runs before that await resumes, leaving current_health at its default 0 and making the
	# deck manager correctly reject the fresh aircraft as stale.
	await get_tree().process_frame
	if pilot == null or not is_instance_valid(pilot):
		return
	var initialized_craft_variant: Variant = pilot.get("aircraft")
	var initialized_craft := initialized_craft_variant as RigidBody3D
	# aircraft.gd adds this group during its delayed initialization. Keep the isolated test aircraft
	# out of the player-aircraft lookup, as intended by _spawn_one().
	if is_instance_valid(initialized_craft) and initialized_craft.is_in_group("aircraft"):
		initialized_craft.remove_from_group("aircraft")
	# Put the pilot into a clean flying state first -- a freshly-spawned AIPilot defaults to IDLE/LAUNCHING
	# (waiting for a catapult that never comes), which would swallow the landing command.
	if pilot.has_method("change_state"):
		pilot.call("change_state", 4)  # State.SEARCH
	var started: Variant = null
	if flow == "recovery" and pilot.has_method("start_recovery"):
		started = pilot.call("start_recovery")
	elif pilot.has_method("start_straight_in_landing"):
		started = pilot.call("start_straight_in_landing")
	var craft_variant: Variant = pilot.get("aircraft")
	var craft := craft_variant as RigidBody3D
	var managers := get_tree().get_nodes_in_group("flight_deck_manager")
	_log("FLOW_BEGIN craft=%s flow=%s started=%s deck_managers=%d" % [
		craft.name if is_instance_valid(craft) else "invalid",
		flow,
		str(started),
		managers.size(),
	])
	for manager in managers:
		var holder_variant: Variant = manager.get("_landing_clearance_aircraft")
		var holder := holder_variant as RigidBody3D
		var stale := bool(manager.call("_is_landing_clearance_aircraft_stale", craft)) \
				if is_instance_valid(craft) and manager.has_method("_is_landing_clearance_aircraft_stale") else true
		_log("  FLOW_DECK path=%s holder=%s stale=%s health=%.1f exploded=%s inside=%s cdist=%.0f" % [
			str(manager.get_path()),
			holder.name if is_instance_valid(holder) else "none",
			str(stale),
			float(craft.get("current_health")) if is_instance_valid(craft) else -1.0,
			str(bool(craft.get("_has_exploded"))) if is_instance_valid(craft) else "invalid",
			str(craft.is_inside_tree()) if is_instance_valid(craft) else "false",
			craft.global_position.distance_to(_carrier().global_position) if is_instance_valid(craft) and is_instance_valid(_carrier()) else -1.0,
		])


func _poll_outcomes() -> void:
	for name in _attempts.keys():
		var a: Dictionary = _attempts[name]
		if a.get("outcome", "") != "":
			continue
		var node: Variant = a.get("node")
		if not is_instance_valid(node):
			_finish(name, "GONE")   # freed without a signal (shouldn't normally happen)
			continue
		var craft := node as RigidBody3D
		# Origin-shift teleport victim: implausibly far from the carrier -> recycle (not a real outcome).
		var carrier := _carrier()
		if is_instance_valid(carrier) and craft.global_position.distance_to(carrier.global_position) > teleport_recycle_dist_m:
			_trace_crash(name, "TELEPORT_THRESHOLD")
			_finish(name, "TELEPORT")
			continue
		# CAUGHT: arresting hook engaged a wire.
		if craft.has_meta("arresting_engaged") and bool(craft.get_meta("arresting_engaged")):
			_finish(name, "CAUGHT")
			continue
		# BOLTER / wave-off: pilot flagged a go-around.
		var pilot: Node = craft.find_child("AIPilot", true, false)
		var go_around_active: bool = false
		if pilot != null:
			if pilot.has_method("is_landing_go_around_active"):
				go_around_active = bool(pilot.call("is_landing_go_around_active"))
			elif "_bolter_go_around" in pilot:
				go_around_active = bool(pilot.get("_bolter_go_around"))
		if go_around_active:
			_log_bolter_geometry(name, craft, pilot)
			_finish(name, "BOLTER")
			continue
		# TIMEOUT: took too long.
		if _elapsed_s - float(a.get("spawn_t", 0.0)) > attempt_timeout_s:
			_finish(name, "TIMEOUT")


func _sample_ga_metrics() -> void:
	if not genetic_tuning_enabled:
		return
	for craft_name in _attempts.keys():
		var attempt: Dictionary = _attempts[craft_name]
		if attempt.get("outcome", "") != "":
			continue
		var node: Variant = attempt.get("node")
		if not is_instance_valid(node):
			continue
		var craft := node as RigidBody3D
		var pilot: Node = craft.find_child("AIPilot", true, false)
		if pilot == null:
			continue
		var state := int(pilot.get("current_state"))
		if state == 14 and int(pilot.get("_recovery_phase")) >= 2:
			attempt["reached_glideslope"] = true
		if state == 16:
			attempt["reached_glideslope"] = true
			attempt["reached_final"] = true
		if pilot.has_method("_landing_track_error"):
			var track_variant: Variant = pilot.call("_landing_track_error", craft.global_position)
			if track_variant is Dictionary:
				var track := track_variant as Dictionary
				if bool(track.get("valid", false)):
					attempt["min_remaining_m"] = minf(float(attempt.get("min_remaining_m", INF)), absf(float(track.get("remaining_m", INF))))
					attempt["min_lateral_m"] = minf(float(attempt.get("min_lateral_m", INF)), absf(float(track.get("lateral_m", INF))))
					attempt["min_vertical_m"] = minf(float(attempt.get("min_vertical_m", INF)), absf(float(track.get("vertical_m", INF))))
		if pilot.has_method("get_landing_capture_cone_status"):
			var cone_variant: Variant = pilot.call("get_landing_capture_cone_status")
			if cone_variant is Dictionary and bool((cone_variant as Dictionary).get("valid", false)):
				var cone := (cone_variant as Dictionary).duplicate(true)
				attempt["cone_latest_status"] = cone
				if bool(cone.get("captured", false)) and not bool(attempt.get("cone_capture_logged", false)):
					attempt["cone_capture_logged"] = true
					attempt["cone_capture_remaining_m"] = float(cone.get("capture_remaining_m", NAN))
					attempt["cone_capture_behind_m"] = float(cone.get("capture_behind_carrier_m", NAN))
					_log("CONE_CAPTURE %s remaining=%.1f behind=%.1f lat=%+.1f/%0.1f vert=%+.1f/%0.1f track=%.1fdeg fpa_err=%.1fdeg bank=%.1f/%.1fdeg settle=%.2f ctrl=R%+.2f Y%+.2f speed=%.1f pitch=%+.1fdeg aoa=%+.1f/%.1fdeg path=%+.1fdeg" % [
						craft_name,
						float(cone.get("capture_remaining_m", NAN)),
						float(cone.get("capture_behind_carrier_m", NAN)),
						float(cone.get("lateral_m", NAN)),
						float(cone.get("allowed_lateral_m", NAN)),
						float(cone.get("vertical_m", NAN)),
						float(cone.get("allowed_vertical_m", NAN)),
						float(cone.get("track_yaw_error_deg", NAN)),
						float(cone.get("fpa_error_deg", NAN)),
						float(cone.get("bank_deg", NAN)),
						float(cone.get("commanded_bank_deg", NAN)),
						float(cone.get("bank_settle_scale", NAN)),
						float(cone.get("roll_input", NAN)),
						float(cone.get("yaw_input", NAN)),
						float(cone.get("speed_mps", NAN)),
						float(cone.get("body_pitch_deg", NAN)),
						float(cone.get("aoa_deg", NAN)),
						float(cone.get("target_aoa_deg", NAN)),
						float(cone.get("fpa_deg", NAN)),
					])
				if bool(cone.get("settled", false)) and not bool(attempt.get("final_settled_logged", false)):
					attempt["final_settled_logged"] = true
					attempt["final_settled_remaining_m"] = float(cone.get("settled_remaining_m", NAN))
					attempt["final_settled_behind_m"] = float(cone.get("settled_behind_carrier_m", NAN))
					_log("FINAL_SETTLED %s remaining=%.1f behind=%.1f lat=%+.1f track=%.1fdeg bank=%.1fdeg stable=%.2fs" % [
						craft_name,
						float(cone.get("settled_remaining_m", NAN)),
						float(cone.get("settled_behind_carrier_m", NAN)),
						float(cone.get("lateral_m", NAN)),
						float(cone.get("track_yaw_error_deg", NAN)),
						float(cone.get("bank_deg", NAN)),
						float(cone.get("settled_stable_s", NAN)),
					])
				if bool(cone.get("gate_checked", false)) and not bool(attempt.get("cone_gate_logged", false)):
					attempt["cone_gate_logged"] = true
					attempt["cone_gate_passed"] = bool(cone.get("gate_passed", false))
					_log("CONE_GATE %s result=%s remaining=%.1f behind=%.1f ratio=%.2f lat=%+.1f/%0.1f vert=%+.1f/%0.1f track=%.1fdeg fpa_err=%.1fdeg bank=%.1f/%.1fdeg settle=%.2f ctrl=R%+.2f Y%+.2f speed=%.1f pitch=%+.1fdeg aoa=%+.1f/%.1fdeg path=%+.1fdeg thr=%.2f/%.2f reason=%s" % [
						craft_name,
						"PASS" if bool(cone.get("gate_passed", false)) else "WAVE_OFF",
						float(cone.get("remaining_m", NAN)),
						float(cone.get("behind_carrier_m", NAN)),
						float(cone.get("ellipse_ratio", NAN)),
						float(cone.get("lateral_m", NAN)),
						float(cone.get("allowed_lateral_m", NAN)),
						float(cone.get("vertical_m", NAN)),
						float(cone.get("allowed_vertical_m", NAN)),
						float(cone.get("track_yaw_error_deg", NAN)),
						float(cone.get("fpa_error_deg", NAN)),
						float(cone.get("bank_deg", NAN)),
						float(cone.get("commanded_bank_deg", NAN)),
						float(cone.get("bank_settle_scale", NAN)),
						float(cone.get("roll_input", NAN)),
						float(cone.get("yaw_input", NAN)),
						float(cone.get("speed_mps", NAN)),
						float(cone.get("body_pitch_deg", NAN)),
						float(cone.get("aoa_deg", NAN)),
						float(cone.get("target_aoa_deg", NAN)),
						float(cone.get("fpa_deg", NAN)),
						float(cone.get("throttle_cmd", NAN)),
						float(cone.get("engine_power", NAN)),
						str(cone.get("waveoff_reason", "")),
					])
		if state == 16 and pilot.has_method("get_landing_fpv_yaw_error_deg") \
				and pilot.has_method("get_landing_fpv_pitch_error_deg"):
			var yaw_error := float(pilot.call("get_landing_fpv_yaw_error_deg"))
			var pitch_error := float(pilot.call("get_landing_fpv_pitch_error_deg"))
			if is_finite(yaw_error) and is_finite(pitch_error):
				attempt["final_samples"] = int(attempt.get("final_samples", 0)) + 1
				attempt["fpv_yaw_error_integral"] = float(attempt.get("fpv_yaw_error_integral", 0.0)) + absf(yaw_error)
				attempt["fpv_pitch_error_integral"] = float(attempt.get("fpv_pitch_error_integral", 0.0)) + absf(pitch_error)
			if pilot.has_method("get_landing_attitude_status"):
				var attitude_variant: Variant = pilot.call("get_landing_attitude_status")
				if attitude_variant is Dictionary:
					var attitude := attitude_variant as Dictionary
					var aoa_deg: float = float(attitude.get("aoa_deg", NAN))
					var target_aoa_deg: float = float(attitude.get("target_aoa_deg", NAN))
					if is_finite(aoa_deg) and is_finite(target_aoa_deg):
						attempt["aoa_error_integral"] = float(attempt.get("aoa_error_integral", 0.0)) \
							+ absf(target_aoa_deg - aoa_deg)
						attempt["aoa_integral"] = float(attempt.get("aoa_integral", 0.0)) + aoa_deg
						attempt["body_pitch_integral"] = float(attempt.get("body_pitch_integral", 0.0)) \
							+ float(attitude.get("body_pitch_deg", 0.0))
		_attempts[craft_name] = attempt


func _trace_first_lander() -> void:
	## Temporary, test-harness-only evidence for the reported t~10 coordinate-frame jump.
	## PhysicsServer3D is authoritative for a RigidBody3D, so compare it with the scene transform
	## while also recording the parent, carrier-relative position, and terrain clearance.
	for craft_name in _attempts.keys():
		var a: Dictionary = _attempts[craft_name]
		if int(a.get("spawn_index", -1)) != 1 or a.get("outcome", "") != "":
			continue
		var node: Variant = a.get("node")
		if not is_instance_valid(node):
			continue
		var craft := node as RigidBody3D
		var age: float = _elapsed_s - float(a.get("spawn_t", 0.0))
		if age > transform_trace_duration_s:
			continue

		var global_pos: Vector3 = craft.global_position
		var previous_pos: Vector3 = a.get("trace_last_global", global_pos)
		var parent: Node = craft.get_parent()
		var parent_id: int = parent.get_instance_id() if parent != null else 0
		var previous_parent_id: int = int(a.get("trace_last_parent_id", parent_id))
		var scene_jump_m: float = global_pos.distance_to(previous_pos)
		var physics_xform: Transform3D = PhysicsServer3D.body_get_state(
			craft.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		var physics_gap_m: float = global_pos.distance_to(physics_xform.origin)
		var due: bool = age + 0.0001 >= float(a.get("trace_next_t", 0.0))
		var anomalous: bool = scene_jump_m >= transform_trace_jump_m \
			or physics_gap_m >= transform_trace_jump_m \
			or parent_id != previous_parent_id
		if due or anomalous:
			_log_transform_trace(craft_name, craft, age, "ANOMALY" if anomalous else "SAMPLE", \
				physics_xform, scene_jump_m, physics_gap_m)
			if due:
				a["trace_next_t"] = age + maxf(transform_trace_interval_s, 0.1)
		a["trace_last_global"] = global_pos
		a["trace_last_parent_id"] = parent_id
		_attempts[craft_name] = a


func _log_transform_trace(craft_name: String, craft: RigidBody3D, age: float, reason: String,
		physics_xform: Transform3D, scene_jump_m: float, physics_gap_m: float) -> void:
	if not is_instance_valid(craft):
		return
	var carrier := _carrier()
	var carrier_pos: Vector3 = carrier.global_position if is_instance_valid(carrier) else Vector3.ZERO
	var relative_pos: Vector3 = craft.global_position - carrier_pos
	var terrain_y: float = NAN
	var terrain: Node = get_tree().get_first_node_in_group("terrain_provider")
	if terrain != null and terrain.has_method("get_height"):
		terrain_y = float(terrain.call("get_height", craft.global_position))
	var agl: float = craft.global_position.y - terrain_y if is_finite(terrain_y) else NAN
	var parent_path: String = str(craft.get_parent().get_path()) if craft.get_parent() != null else "<none>"
	var pilot: Node = craft.find_child("AIPilot", true, false)
	var state: int = int(pilot.get("current_state")) if pilot != null else -1
	_log("XFORM %s reason=%s age=%.2f state=%d parent=%s global=%s physics=%s rel=%s vel=%s terrain=%.1f agl=%.1f frame_jump=%.1f physics_gap=%.1f" % [
		craft_name, reason, age, state, parent_path, _vec3_text(craft.global_position),
		_vec3_text(physics_xform.origin), _vec3_text(relative_pos), _vec3_text(craft.linear_velocity),
		terrain_y, agl, scene_jump_m, physics_gap_m])


func _trace_crash(craft_name: String, reason: String, impact: Variant = null) -> void:
	if not _attempts.has(craft_name):
		return
	var node: Variant = _attempts[craft_name].get("node")
	if not is_instance_valid(node):
		_log("XFORM %s reason=%s node_invalid impact=%s" % [craft_name, reason, str(impact)])
		return
	var craft := node as RigidBody3D
	var physics_xform: Transform3D = PhysicsServer3D.body_get_state(
		craft.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	_log_transform_trace(craft_name, craft,
		_elapsed_s - float(_attempts[craft_name].get("spawn_t", 0.0)),
		"%s impact=%s" % [reason, str(impact)], physics_xform, 0.0,
		craft.global_position.distance_to(physics_xform.origin))


func _vec3_text(value: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [value.x, value.y, value.z]


func _log_bolter_geometry(craft_name: String, craft: RigidBody3D, pilot: Node) -> void:
	var remaining_m: float = NAN
	var lateral_m: float = NAN
	var vertical_m: float = NAN
	if pilot.has_method("_landing_track_error"):
		var track_variant: Variant = pilot.call("_landing_track_error", craft.global_position)
		if track_variant is Dictionary:
			var track := track_variant as Dictionary
			if bool(track.get("valid", false)):
				remaining_m = float(track.get("remaining_m", NAN))
				lateral_m = float(track.get("lateral_m", NAN))
				vertical_m = float(track.get("vertical_m", NAN))
	var deck_y: float = NAN
	if pilot.has_method("_get_approach_deck_y"):
		deck_y = float(pilot.call("_get_approach_deck_y"))
	var fdm := get_tree().get_first_node_in_group("flight_deck_manager")
	var deck_accepts: String = "unknown"
	if fdm != null and fdm.has_method("can_accept_landing"):
		deck_accepts = str(bool(fdm.call("can_accept_landing", craft)))
	var attitude: Dictionary = pilot.call("get_landing_attitude_status") \
		if pilot.has_method("get_landing_attitude_status") else {}
	var hook: Node3D = craft.get_node_or_null("TailHook") as Node3D
	var hook_alt: float = hook.global_position.y - deck_y if is_instance_valid(hook) else NAN
	var hook_down: bool = bool(hook.get("_is_deployed")) \
		if is_instance_valid(hook) and "_is_deployed" in hook else false
	var hook_area: Area3D = hook.get_node_or_null("HookArea") as Area3D if is_instance_valid(hook) else null
	var hook_monitoring: bool = hook_area.monitoring if is_instance_valid(hook_area) else false
	var sweep_seen: int = int(craft.get_meta("arrest_sweep_seen_count", 0))
	var sweep_diag: String = JSON.stringify(craft.get_meta("arrest_sweep_diag", {}))
	var wire_geometry: Array = []
	if is_instance_valid(hook_area):
		for cable_variant in get_tree().get_nodes_in_group("arresting_cable"):
			var cable := cable_variant as Node3D
			if not is_instance_valid(cable):
				continue
			var center: Vector3 = cable.global_position
			if cable.has_method("get_wire_center"):
				center = cable.call("get_wire_center")
			wire_geometry.append({
				"wire": cable.name,
				"center": _vec3_text(center),
				"hook": _vec3_text(hook_area.global_position),
				"hook_minus_wire_y": hook_area.global_position.y - center.y,
			})
	_log("BOLTER_DIAG %s remaining=%.1f lateral=%+.1f vertical=%+.1f deck_alt=%.1f aircraft_alt=%.1f speed=%.1f vs=%+.1f pitch=%+.1fdeg aoa=%+.1f/%.1fdeg path=%+.1fdeg thr=%.2f/%.2f hook_alt=%+.2f down=%s monitoring=%s sweep_seen=%d sweep=%s wires=%s deck_accepts=%s" % [
		craft_name, remaining_m, lateral_m, vertical_m, deck_y, craft.global_position.y,
		craft.linear_velocity.length(), craft.linear_velocity.y,
		float(attitude.get("body_pitch_deg", NAN)), float(attitude.get("aoa_deg", NAN)),
		float(attitude.get("target_aoa_deg", NAN)), float(attitude.get("fpa_deg", NAN)),
		float(attitude.get("throttle_cmd", NAN)), float(attitude.get("engine_power", NAN)),
		hook_alt, str(hook_down), str(hook_monitoring), sweep_seen, sweep_diag,
		JSON.stringify(wire_geometry), deck_accepts])


func _on_craft_destroyed(craft_name: String) -> void:
	if _attempts.has(craft_name) and _attempts[craft_name].get("outcome", "") == "":
		_trace_crash(craft_name, "DESTROYED")
		_finish(craft_name, "CRASH")


func _on_craft_crashed(impact, craft_name: String) -> void:
	if _attempts.has(craft_name) and _attempts[craft_name].get("outcome", "") == "":
		_trace_crash(craft_name, "CRASH_SIGNAL", impact)
		_finish(craft_name, "CRASH")


func _finish(craft_name: String, outcome: String) -> void:
	if not _attempts.has(craft_name):
		return
	var a: Dictionary = _attempts[craft_name]
	if a.get("outcome", "") != "":
		return
	a["outcome"] = outcome
	_attempts[craft_name] = a
	var flow: String = str(a.get("flow", "recovery"))
	var t: Dictionary = _tally.get(flow, {})
	t[outcome] = int(t.get(outcome, 0)) + 1
	_tally[flow] = t
	var dur: float = _elapsed_s - float(a.get("spawn_t", 0.0))
	var ga_fitness: float = NAN
	var ga_assignment_variant: Variant = a.get("ga_assignment", {})
	if genetic_tuning_enabled and is_instance_valid(_ga_tuner) \
			and ga_assignment_variant is Dictionary and not (ga_assignment_variant as Dictionary).is_empty():
		var final_samples := int(a.get("final_samples", 0))
		var trial_craft: Node = a.get("node") as Node
		var min_wire_vertical_m: float = float(trial_craft.get_meta("arrest_min_wire_vertical_m", INF)) \
			if is_instance_valid(trial_craft) else INF
		var ga_metrics := {
			"outcome": outcome,
			"duration_s": dur,
			"reached_glideslope": bool(a.get("reached_glideslope", false)),
			"reached_final": bool(a.get("reached_final", false)),
			"min_remaining_m": _finite_or_large(float(a.get("min_remaining_m", INF))),
			"min_lateral_m": _finite_or_large(float(a.get("min_lateral_m", INF))),
			"min_vertical_m": _finite_or_large(float(a.get("min_vertical_m", INF))),
			"min_wire_hook_vertical_m": _finite_or_large(min_wire_vertical_m),
			"final_samples": final_samples,
			"mean_fpv_yaw_error_deg": float(a.get("fpv_yaw_error_integral", 0.0)) / maxf(final_samples, 1),
			"mean_fpv_pitch_error_deg": float(a.get("fpv_pitch_error_integral", 0.0)) / maxf(final_samples, 1),
			"mean_aoa_error_deg": float(a.get("aoa_error_integral", 0.0)) / maxf(final_samples, 1),
			"mean_aoa_deg": float(a.get("aoa_integral", 0.0)) / maxf(final_samples, 1),
			"mean_body_pitch_deg": float(a.get("body_pitch_integral", 0.0)) / maxf(final_samples, 1),
			"cone_captured": bool(a.get("cone_capture_logged", false)),
			"cone_capture_remaining_m": float(a.get("cone_capture_remaining_m", -1.0)) \
				if is_finite(float(a.get("cone_capture_remaining_m", NAN))) else -1.0,
			"cone_capture_behind_m": float(a.get("cone_capture_behind_m", -1.0)) \
				if is_finite(float(a.get("cone_capture_behind_m", NAN))) else -1.0,
			"final_settled_remaining_m": float(a.get("final_settled_remaining_m", -1.0)) \
				if is_finite(float(a.get("final_settled_remaining_m", NAN))) else -1.0,
			"final_settled_behind_m": float(a.get("final_settled_behind_m", -1.0)) \
				if is_finite(float(a.get("final_settled_behind_m", NAN))) else -1.0,
			"cone_gate_passed": bool(a.get("cone_gate_passed", false)),
		}
		ga_fitness = float(_ga_tuner.call("record_result", ga_assignment_variant, ga_metrics))
	# GA-ready outcome line: flow, outcome, time, spawn geometry.
	_log("OUTCOME %s flow=%s result=%s dur=%.1f spawn_dist=%.0f spawn_alt=%.0f cone_capture=%.1f cone_gate=%s ga_fitness=%.1f" % [
		craft_name, flow, outcome, dur, float(a.get("spawn_dist", 0.0)), float(a.get("spawn_alt", 0.0)),
		float(a.get("cone_capture_behind_m", NAN)), str(bool(a.get("cone_gate_passed", false))), ga_fitness])
	# Despawn shortly after (let a CAUGHT settle on the wire first).
	var node: Variant = a.get("node")
	if is_instance_valid(node):
		var delay: float = 1.5 if outcome == "CAUGHT" else 0.3
		get_tree().create_timer(delay).timeout.connect(func():
			if is_instance_valid(node):
				var craft_node := node as Node
				if craft_node.has_meta("arresting_cable"):
					var cable: Variant = craft_node.get_meta("arresting_cable")
					if is_instance_valid(cable) and cable.has_method("manual_release"):
						cable.call("manual_release")
				craft_node.queue_free())


func _finite_or_large(value: float) -> float:
	return value if is_finite(value) else 1000000000.0


func _log_summary() -> void:
	var parts: Array[String] = []
	for flow in ["recovery", "direct"]:
		var t: Dictionary = _tally.get(flow, {})
		parts.append("%s{C=%d B=%d X=%d T=%d}" % [
			flow, int(t.get("CAUGHT", 0)), int(t.get("BOLTER", 0)),
			int(t.get("CRASH", 0)), int(t.get("TIMEOUT", 0))])
	_log("SUMMARY t=%.0f live=%d spawned=%d | %s" % [_elapsed_s, _live_count(), _spawn_index, " ".join(parts)])
	if genetic_tuning_enabled and is_instance_valid(_ga_tuner):
		_log("  GA %s" % JSON.stringify(_ga_tuner.call("get_status")))
	# Diagnostic: for each live aircraft, what state is it in + deck clearance/queue position?
	var fdm := get_tree().get_first_node_in_group("flight_deck_manager")
	if fdm != null and "current_state" in fdm:
		_log("  DECK state=%s" % str(fdm.get("current_state")))
	for name in _attempts.keys():
		var a: Dictionary = _attempts[name]
		if a.get("outcome", "") != "" or not is_instance_valid(a.get("node")):
			continue
		var craft := a["node"] as RigidBody3D
		var pilot: Node = craft.find_child("AIPilot", true, false)
		var st: int = int(pilot.get("current_state")) if pilot != null else -1
		var qpos: int = -99
		if fdm != null and fdm.has_method("get_landing_queue_position"):
			qpos = int(fdm.call("get_landing_queue_position", craft))
		var carrier := _carrier()
		var cd: float = craft.global_position.distance_to(carrier.global_position) if is_instance_valid(carrier) else -1.0
		var recovery_detail: String = ""
		if pilot != null and "_recovery_phase" in pilot and pilot.has_method("_get_recovery_carrier_frame"):
			var phase: int = int(pilot.get("_recovery_phase"))
			var frame_variant: Variant = pilot.call("_get_recovery_carrier_frame")
			if frame_variant is Dictionary:
				var frame := frame_variant as Dictionary
				var origin: Vector3 = frame.get("origin", carrier.global_position if is_instance_valid(carrier) else Vector3.ZERO)
				var forward: Vector3 = frame.get("forward", Vector3.FORWARD)
				forward.y = 0.0
				forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
				var to_carrier: Vector3 = origin - craft.global_position
				var behind_m: float = to_carrier.dot(forward)
				var rel_flat: Vector3 = craft.global_position - origin
				rel_flat.y = 0.0
				var cross_m: float = (rel_flat + forward * behind_m).length()
				var vel_flat := Vector3(craft.linear_velocity.x, 0.0, craft.linear_velocity.z)
				var align_dot: float = vel_flat.normalized().dot(forward) if vel_flat.length_squared() > 1.0 else -1.0
				recovery_detail = " phase=%d behind=%.0f cross=%.0f align=%.2f speed=%.0f" % [
					phase, behind_m, cross_m, align_dot, craft.linear_velocity.length()]
		if pilot != null and st == 14 and "_route_follow_debug" in pilot:
			var route_debug_variant: Variant = pilot.get("_route_follow_debug")
			if route_debug_variant is Dictionary and not (route_debug_variant as Dictionary).is_empty():
				var route_debug := route_debug_variant as Dictionary
				var route_index: int = int(route_debug.get("index", -1))
				var route_count: int = 0
				var route_waypoints_variant: Variant = pilot.get("waypoints")
				if route_waypoints_variant is Array:
					route_count = (route_waypoints_variant as Array).size()
				recovery_detail += " route=%d/%d role=%s wp_d=%.0f cap=%.0f proj=%.2f/%.0f decision=%s" % [
					route_index + 1,
					route_count,
					str(route_debug.get("role", "")),
					float(route_debug.get("distance_m", NAN)),
					float(route_debug.get("capture_m", NAN)),
					float(route_debug.get("projection_t", NAN)),
					float(route_debug.get("projection_cross_track_m", NAN)),
					str(route_debug.get("decision", "")),
				]
				var route_debug_tag: String = str(route_debug.get("debug_tag", ""))
				if not route_debug_tag.is_empty():
					recovery_detail += " tag=%s" % route_debug_tag
				var arc_remaining_m: float = float(route_debug.get("arc_remaining_m", NAN))
				if is_finite(arc_remaining_m):
					recovery_detail += " arc_rem=%.0f" % arc_remaining_m
				var straight_cross_track_m: float = float(route_debug.get("straight_cross_track_m", NAN))
				if is_finite(straight_cross_track_m):
					recovery_detail += " steer=(x=%+.0f rate=%+.1f accel=%+.1f bank=%+.1f/%+.1f roll=%+.2f yaw=%+.1f)" % [
						straight_cross_track_m,
						float(route_debug.get("straight_cross_track_rate_mps", NAN)),
						float(route_debug.get("straight_lateral_accel_mps2", NAN)),
						rad_to_deg(float(route_debug.get("current_bank_rad", 0.0))),
						rad_to_deg(float(route_debug.get("desired_bank_rad", 0.0))),
						float(route_debug.get("raw_roll", 0.0)),
						rad_to_deg(float(route_debug.get("guidance_yaw_error_rad", 0.0))),
					]
				var turn_target_g: float = float(route_debug.get("turn_target_g", NAN))
				if is_finite(turn_target_g):
					recovery_detail += " turn=(bank=%+.1f/%+.1f load=%.2f/%.2f avail=%.2f aoa=%.1f/%.1f pitch=%+.2f vs=%+.1f/%+.1f)" % [
						rad_to_deg(float(route_debug.get("current_bank_rad", 0.0))),
						rad_to_deg(float(route_debug.get("desired_bank_rad", 0.0))),
						float(route_debug.get("turn_measured_g", NAN)),
						turn_target_g,
						float(route_debug.get("turn_available_g", NAN)),
						float(route_debug.get("turn_measured_aoa_deg", NAN)),
						float(route_debug.get("turn_target_aoa_deg", NAN)),
						float(route_debug.get("turn_pitch_command", NAN)),
						float(route_debug.get("turn_vertical_speed_mps", NAN)),
						float(route_debug.get("turn_desired_vertical_speed_mps", NAN)),
					]
		if pilot != null and st == 16 \
				and pilot.has_method("get_landing_fpv_yaw_error_deg") \
				and pilot.has_method("get_landing_fpv_pitch_error_deg"):
			var fpv_yaw_deg: float = float(pilot.call("get_landing_fpv_yaw_error_deg"))
			var fpv_pitch_deg: float = float(pilot.call("get_landing_fpv_pitch_error_deg"))
			if not is_nan(fpv_yaw_deg) and not is_nan(fpv_pitch_deg):
				recovery_detail += " fpv_err=(yaw=%.1fdeg pitch=%.1fdeg)" % [fpv_yaw_deg, fpv_pitch_deg]
			if pilot.has_method("get_landing_predictive_fpv_yaw_error_deg") \
					and pilot.has_method("get_landing_track_rate_deg_s"):
				var predictive_yaw_deg: float = float(
					pilot.call("get_landing_predictive_fpv_yaw_error_deg")
				)
				var track_rate_deg_s: float = float(pilot.call("get_landing_track_rate_deg_s"))
				if is_finite(predictive_yaw_deg) and is_finite(track_rate_deg_s):
					recovery_detail += " yaw_lead=(cmd=%.1fdeg rate=%+.1fdeg/s)" % [
						predictive_yaw_deg,
						track_rate_deg_s,
					]
		_log("  DIAG %s state=%d qpos=%d cdist=%.0f alt=%.0f%s" % [
			name, st, qpos, cd, craft.global_position.y, recovery_detail])


func apply_origin_shift(offset: Vector3) -> void:
	_play_area_center -= offset


func _log(msg: String) -> void:
	print("[LandingTest] " + msg)
	var f: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		f.store_line("[%7.1f] %s" % [_elapsed_s, msg])
		f.close()
