extends "res://Scenario/GunneryGym.gd"

## Opt-in measurement harness. Does not apply the old optimizer's gain/spread overrides.
const BASELINE_CASES := [
	{"name": "tail_chase", "path": "straight", "target_offset": [0, 0, 520], "target_velocity": [0, 0, 78]},
	{"name": "crossing_left", "path": "straight", "target_offset": [360, 25, 560], "target_velocity": [-62, 0, 48]},
	{"name": "crossing_right", "path": "straight", "target_offset": [-360, -25, 560], "target_velocity": [62, 0, 48]},
	{"name": "gentle_left", "path": "circle", "target_offset": [0, 0, 580], "target_speed_mps": 84, "turn_radius_m": 480, "turn_sign": 1},
	{"name": "hard_left", "path": "circle", "target_offset": [0, 0, 560], "target_speed_mps": 80, "turn_radius_m": 220, "turn_sign": 1},
	{"name": "hard_right", "path": "circle", "target_offset": [0, -20, 560], "target_speed_mps": 80, "turn_radius_m": 220, "turn_sign": -1},
]

class ImmortalTarget:
	extends RigidBody3D
	var team := 2
	var current_health := 100.0
	var max_health := 100.0
	var damage_events := 0
	func take_damage(_amount: float) -> void:
		damage_events += 1 # Never subtract health or destroy the target.

var baseline_duration_s := 180.0
var baseline_output := "user://gunnery_tracking_baseline.json"
var baseline_results: Array = []
var baseline_hashes := {}
var baseline_skill := -1
var trace_interval_frames := 6

func _ready() -> void:
	add_to_group("origin_shifter")
	super._ready()

func apply_origin_shift(offset: Vector3) -> void:
	# FloatingOrigin moves the bodies, but scripted paths are cached world-space
	# coordinates. Rebase them too or the next target update undoes its shift.
	for trial in _trials:
		trial.target_initial_pos -= offset
		trial.circle_center -= offset
		trial["origin_shift_count"] = int(trial.get("origin_shift_count", 0)) + 1
		if trial.has("diagnostic_previous"):
			trial.diagnostic_previous.target_position -= offset

func _spawn_trial(candidate: Dictionary, candidate_index: int, gun_case: Dictionary, case_index: int, warmup_s: float) -> void:
	super._spawn_trial(candidate, candidate_index, gun_case, case_index, warmup_s)
	_set_baseline_altitude(_trials.back())

func _reset_trial_for_case(trial: Dictionary, gun_case: Dictionary, case_index: int, warmup_s: float) -> void:
	super._reset_trial_for_case(trial, gun_case, case_index, warmup_s)
	_set_baseline_altitude(trial)

func _set_baseline_altitude(trial: Dictionary) -> void:
	# Keep the exercise below the production 1400m combat ceiling without
	# disabling that tactical rule. The legacy gym spawned at 2600m.
	var shift := Vector3(0, 1000.0 - float(trial.start_altitude_m), 0)
	trial.shooter.global_position += shift
	trial.target.global_position += shift
	trial.target_initial_pos += shift
	trial.circle_center += shift
	trial.start_altitude_m = 1000.0

func _run() -> void:
	var selected_case := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gunnery-duration="):
			baseline_duration_s = clampf(float(arg.get_slice("=", 1)), 5.0, 600.0)
		elif arg.begins_with("--gunnery-output="):
			baseline_output = arg.trim_prefix("--gunnery-output=")
		elif arg.begins_with("--gunnery-case="):
			selected_case = arg.trim_prefix("--gunnery-case=")
		elif arg.begins_with("--gunnery-skill="):
			baseline_skill = clampi(int(arg.get_slice("=", 1)), 0, 4)
		elif arg.begins_with("--gunnery-trace-hz="):
			trace_interval_frames = maxi(1, roundi(60.0 / clampf(float(arg.get_slice("=", 1)), 1.0, 60.0)))
	for path in ["res://AI/AIPilot.gd", "res://Aircraft/Aircraft_5.tscn", "res://Aircraft/SimpleAero.gd", "res://Aircraft/aircraft.gd",
			"res://AI/EvasiveFlight.gd", "res://Projectiles/ProjectileNew/projectile_new.gd",
			"res://AI/VisualContactTrack.gd", "res://AI/PilotSkillProfile.gd",
			"res://Scenario/GunneryGym.gd", "res://Scenario/GunneryTrackingBaseline.gd",
			"res://Weapons/Autocannon/autocannon.gd", "res://Projectiles/Bullet/bullet.gd",
			"res://project.godot", "res://Environment/FloatingOrigin.gd", "res://AI/FlightPathFollower.gd",
			"res://addons/simplified_flightsim/aircraft_modules/Engine/Engine.gd",
			"res://addons/simplified_flightsim/aircraft_modules/Controls/ControlEngine.gd"]:
		baseline_hashes[path] = FileAccess.get_sha256(path)
	_write_baseline("RUNNING")
	for index in BASELINE_CASES.size():
		var gun_case: Dictionary = BASELINE_CASES[index].duplicate(true)
		if not selected_case.is_empty() and gun_case.name != selected_case:
			continue
		seed(20260909 + index)
		# Fresh production aircraft per case prevents damage, filters and previous
		# pursuit/ballistic caches from leaking between scenarios.
		_spawn_trial({"id": "production_aircraft_5"}, 0, gun_case, index, 1.0)
		# Aircraft._ready resumes on an idle frame before binding controls/modules.
		# Physics frames alone can race that setup under ordinary headless timing.
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		var trial: Dictionary = _trials[0]
		_finalize_trial_setup(trial)
		_reset_trial_for_case(trial, gun_case, index, 1.0)
		trial["duration_s"] = baseline_duration_s
		trial["tracking"] = {"samples": 0, "on_target_s": 0.0, "streak_s": 0.0,
			"longest_streak_s": 0.0, "first_acquire_s": -1.0, "bore_hit_s": 0.0,
			"bore_streak_s": 0.0, "longest_bore_streak_s": 0.0, "sum_error_sq": 0.0,
			"errors": [], "blocks": [], "states": {}, "trace": []}
		print("GUNNERY_BASELINE_START case=%s duration=%.0f target_health=unlimited" % [gun_case.name, baseline_duration_s])
		var elapsed := 0.0
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		while elapsed < baseline_duration_s:
			_update_target(trial, elapsed)
			await get_tree().physics_frame
			elapsed += dt
			_sample_trial(trial, dt, elapsed)
			if not is_instance_valid(trial.shooter) or not is_instance_valid(trial.target):
				trial["invalid"] = true
				break
		# Stop the pilot as well as guns: otherwise it can restart fire during drain.
		if is_instance_valid(trial.pilot):
			trial.pilot.set_physics_process(false)
		_stop_trial_fire(trial)
		for tick in range(ceili(8.0 / dt)):
			_update_target(trial, elapsed + tick * dt)
			await get_tree().physics_frame
		var result := _score_trial(trial)
		result["duration_s"] = elapsed
		result["target_alive"] = is_instance_valid(trial.target)
		result["target_health"] = trial.target.current_health
		result["damage_events"] = trial.target.damage_events
		result["origin_shift_count"] = trial.get("origin_shift_count", 0)
		result["target_motion_error_max_mps"] = trial.get("target_motion_error_max_mps", 0.0)
		result["target_motion_valid"] = float(result.target_motion_error_max_mps) <= 1.0
		if not result.target_motion_valid:
			result["invalid"] = true
		result["settings"] = trial.settings
		var tracking: Dictionary = trial.tracking.duplicate(true)
		var errors: Array = tracking.errors
		errors.sort()
		tracking["rms_aim_error_deg"] = sqrt(float(tracking.sum_error_sq) / maxf(float(tracking.samples), 1.0))
		tracking["p95_aim_error_deg"] = errors[mini(floori(errors.size() * 0.95), errors.size() - 1)] if not errors.is_empty() else null
		tracking.erase("errors")
		result["tracking"] = tracking
		baseline_results.append(result)
		print("GUNNERY_BASELINE_CASE case=%s shots=%d hits=%d on_target_s=%.2f longest_s=%.2f acquire_s=%.2f" % [
			gun_case.name, result.get("shots", 0), result.get("hits", 0), tracking.on_target_s,
			tracking.longest_streak_s, tracking.first_acquire_s])
		_write_baseline("RUNNING")
		if is_instance_valid(trial.shooter):
			trial.shooter.queue_free()
		if is_instance_valid(trial.target):
			trial.target.queue_free()
		await get_tree().process_frame
		_trials.clear()
	_write_baseline("COMPLETE")
	print("GUNNERY_BASELINE_COMPLETE output=%s" % baseline_output)
	get_tree().quit(0)

func _create_lightweight_target() -> RigidBody3D:
	var target := ImmortalTarget.new()
	target.collision_layer = 513
	target.collision_mask = 513
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 4.0
	collider.shape = shape
	target.add_child(collider)
	return target

func _configure_target(target: RigidBody3D) -> void:
	super._configure_target(target)
	# Kinematic freeze derives velocity from transform changes, interpreting a
	# world-origin rebase as a one-frame ~240 km/s target maneuver. The scripted
	# motion supplies its own velocity; static freeze keeps that value authoritative.
	target.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC

func _apply_candidate(trial: Dictionary) -> void:
	var pilot: AIPilot = trial.pilot
	if baseline_skill >= 0:
		pilot.skill = baseline_skill
		pilot.apply_skill_preset()
	pilot._terrain_height_callable = Callable(self, "_flat_baseline_ground")
	# Test isolation only: no mission reassignment, carrier leash or fuel RTB.
	# All pursuit, precision, turn, stall and collision-avoidance settings stay authored.
	pilot.engagement_radius_from_carrier_m = 0.0
	pilot.disengage_radius_from_carrier_m = 0.0
	pilot.rtb_health_threshold = 0.0
	pilot.rtb_fuel_threshold = 0.0
	pilot.change_state(AIPilot.State.SEARCH)
	pilot.set_target(trial.target)
	var gear: Node = trial.shooter.find_child("ControlLandingGear", true, false)
	if gear != null and gear.has_method("stow_gear"):
		gear.stow_gear()
	var settings := {}
	for property in pilot.get_property_list():
		var key := String(property.name)
		if key.begins_with("dogfight_"):
			settings[key] = pilot.get(key)
	trial["settings"] = {"pilot": settings, "guns": [], "skill": int(pilot.skill),
		"perception": pilot.get_combat_skill_profile()}

func _flat_baseline_ground(_position: Vector3) -> float:
	return 0.0

func _finalize_trial_setup(trial: Dictionary) -> void:
	var guns: Array[Node] = []
	_collect_guns(trial.shooter, guns)
	var spreads: Array = []
	for gun in guns:
		spreads.append(gun.get("spread_angle"))
		trial.settings.guns.append({"name": gun.name, "spread_deg": gun.get("spread_angle"),
			"muzzle_velocity": gun.get("muzzle_velocity"), "rounds_per_minute": gun.get("rounds_per_minute")})
	super._finalize_trial_setup(trial)
	for i in guns.size():
		guns[i].set("spread_angle", spreads[i])
		guns[i].set("ammo_count", 1000000)

func _sample_trial(trial: Dictionary, dt: float, elapsed: float) -> void:
	if not is_instance_valid(trial.get("shooter")) or not is_instance_valid(trial.get("target")) \
			or not is_instance_valid(trial.get("pilot")):
		trial["invalid"] = true
		return
	super._sample_trial(trial, dt, elapsed)
	if bool(trial.get("invalid", false)) or elapsed < 1.0:
		return
	var pilot: AIPilot = trial.pilot
	var target: RigidBody3D = trial.target
	var shooter: RigidBody3D = trial.shooter
	var mount: Dictionary = pilot._get_selected_weapon_mount_info()
	var origin: Vector3 = mount.origin
	var forward: Vector3 = mount.forward
	var velocity: Vector3 = pilot._get_point_velocity_at_world_position(origin)
	var muzzle_speed := pilot._get_selected_gun_muzzle_velocity()
	# Read-only ballistic solver, NOT the optimistic production hit-chance metric.
	var solution: Dictionary = pilot._predict_ballistic_aim_solution(origin, velocity,
		target.global_position, target.linear_velocity, muzzle_speed)
	var direction: Vector3 = (Vector3(solution.aim_point) - origin).normalized()
	var error := rad_to_deg(acos(clampf(forward.normalized().dot(direction), -1.0, 1.0)))
	var impact: Vector3 = pilot._predict_dogfight_projectile_position(origin, velocity, forward.normalized(), muzzle_speed, solution.tof)
	var actual_bore_miss := impact.distance_to(Vector3(solution.intercept_point))
	var distance := origin.distance_to(target.global_position)
	var on_target := distance <= 900.0 and error <= 1.0
	var bore_hit := distance <= 900.0 and actual_bore_miss <= 4.0
	var tracking: Dictionary = trial.tracking
	tracking.samples += 1
	tracking.sum_error_sq += error * error
	tracking.errors.append(error)
	tracking.on_target_s += dt if on_target else 0.0
	tracking.streak_s = float(tracking.streak_s) + dt if on_target else 0.0
	tracking.longest_streak_s = maxf(tracking.longest_streak_s, tracking.streak_s)
	if tracking.first_acquire_s < 0.0 and tracking.streak_s >= 0.5:
		tracking.first_acquire_s = elapsed - float(tracking.streak_s)
	tracking.bore_hit_s += dt if bore_hit else 0.0
	tracking.bore_streak_s = float(tracking.bore_streak_s) + dt if bore_hit else 0.0
	tracking.longest_bore_streak_s = maxf(tracking.longest_bore_streak_s, tracking.bore_streak_s)
	var state := str(pilot.current_state)
	tracking.states[state] = float(tracking.states.get(state, 0.0)) + dt
	var block_index := floori((elapsed - 1.0) / 30.0)
	if tracking.blocks.size() <= block_index:
		tracking.blocks.append({"start_s": 1 + block_index * 30, "samples": 0, "on_target_s": 0.0, "sum_error_sq": 0.0,
			"shots_start": trial.shots, "hits_start": trial.hits, "shots_end": trial.shots, "hits_end": trial.hits})
	var block: Dictionary = tracking.blocks[block_index]
	block.samples += 1
	block.sum_error_sq += error * error
	block.on_target_s += dt if on_target else 0.0
	block.shots_end = trial.shots
	block.hits_end = trial.hits
	if tracking.samples % trace_interval_frames == 0:
		var sample := {"t": snappedf(elapsed, 0.01), "range_m": snappedf(distance, 0.1),
			"steering_error_deg": rad_to_deg(forward.angle_to(pilot.nav_waypoint - origin)),
			"aim_yaw_deg": rad_to_deg(atan2(direction.dot(shooter.global_basis.x), direction.dot(shooter.global_basis.z))),
			"aim_pitch_deg": rad_to_deg(atan2(direction.dot(shooter.global_basis.y), direction.dot(shooter.global_basis.z))),
			"steering_point": _diagnostic_vector(pilot.nav_waypoint),
			"ballistic_point": _diagnostic_vector(solution.aim_point),
			"aim_error_deg": snappedf(error, 0.01), "actual_bore_miss_m": snappedf(actual_bore_miss, 0.1),
			"state": pilot.current_state, "precision": pilot.get_dogfight_gunnery_metrics().get("precise_aim_blend", 0),
			"roll": pilot.roll_input, "pitch": pilot.pitch_input, "yaw": pilot.yaw_input,
			"shots": trial.shots, "hits": trial.hits}
		sample.merge(_pursuit_diagnostics(trial, elapsed))
		tracking.trace.append(sample)

func _pursuit_diagnostics(trial: Dictionary, elapsed: float) -> Dictionary:
	# Read-only observer: compare requested motion, physical response and target
	# displacement. In particular, do not use the pilot's nominal target_speed
	# as evidence that an active throttle controller actually follows it.
	var shooter: RigidBody3D = trial.shooter
	var target: RigidBody3D = trial.target
	var pilot: AIPilot = trial.pilot
	var basis := shooter.global_basis
	var relative_position := target.global_position - shooter.global_position
	var relative_velocity := target.linear_velocity - shooter.linear_velocity
	var result := {
		"shooter_position": _diagnostic_vector(shooter.global_position),
		"target_position": _diagnostic_vector(target.global_position),
		"shooter_velocity": _diagnostic_vector(shooter.linear_velocity),
		"target_velocity": _diagnostic_vector(target.linear_velocity),
		"forward": _diagnostic_vector(basis.z),
		"speed_mps": shooter.linear_velocity.length(),
		"forward_speed_mps": shooter.linear_velocity.dot(basis.z),
		"closure_mps": -relative_velocity.dot(relative_position.normalized()),
		"throttle": pilot.throttle_input,
		"nominal_target_speed_mps": pilot.target_speed,
		"bank_deg": rad_to_deg(atan2(basis.x.y, basis.y.y)),
		"sustainable_bank_deg": rad_to_deg(pilot._get_dogfight_sustainable_bank_rad(shooter.linear_velocity.length(), basis)),
		"gunnery": pilot.get_dogfight_gunnery_metrics(),
		"aim_pitch_request": pilot._dogfight_aim_pitch_request,
		"turn_pitch_request": pilot._coordinated_turn_pitch_command,
		"pitch_before_guards": pilot._pitch_before_safety_guards,
		"engine_power": [],
		"angular_velocity_local": _diagnostic_vector(basis.inverse() * shooter.angular_velocity),
	}
	if is_instance_valid(pilot.control_engine):
		for engine in pilot.control_engine.engine_modules:
			result.engine_power.append(engine.get_throttle_ratio())
	if is_instance_valid(pilot.simple_aero):
		result["aoa_deg"] = pilot.simple_aero.get_estimated_angle_of_attack_deg()
		result["estimated_lift_g"] = pilot.simple_aero.get_estimated_lift_ratio()
		result["stall_severity"] = pilot.simple_aero.get_stall_severity()
		result["actual_yaw_control"] = pilot.simple_aero.actual_yaw_control
		result["actual_pitch_control"] = pilot.simple_aero.actual_pitch_control
		result["yaw_authority"] = pilot.simple_aero.current_yaw_authority
	if trial.has("diagnostic_previous"):
		var previous: Dictionary = trial.diagnostic_previous
		var sample_dt: float = elapsed - float(previous.t)
		var target_motion: Vector3 = (target.global_position - Vector3(previous.target_position)) / sample_dt
		var acceleration: Vector3 = (shooter.linear_velocity - Vector3(previous.shooter_velocity)) / sample_dt
		var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		result["target_displacement_velocity"] = _diagnostic_vector(target_motion)
		var expected_velocity: Vector3 = (Vector3(previous.target_velocity) + target.linear_velocity) * 0.5
		var motion_error: float = target_motion.distance_to(expected_velocity)
		result["target_motion_error_mps"] = motion_error
		trial["target_motion_error_max_mps"] = maxf(float(trial.get("target_motion_error_max_mps", 0.0)), motion_error)
		result["measured_load_g"] = (acceleration + Vector3.UP * gravity).dot(basis.y) / gravity
	trial["diagnostic_previous"] = {"t": elapsed, "target_position": target.global_position,
		"target_velocity": target.linear_velocity, "shooter_velocity": shooter.linear_velocity}
	return result

func _diagnostic_vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _collect_guns(node: Node, out: Array[Node]) -> void:
	# The older gym's capability check also collected rocket pods and bomb racks.
	for child in node.get_children():
		if child is Autocannon:
			out.append(child)
		_collect_guns(child, out)

func _write_baseline(status: String) -> void:
	var unchanged := true
	for path in baseline_hashes:
		unchanged = unchanged and FileAccess.get_sha256(path) == baseline_hashes[path]
	_write_json(baseline_output, {"status": status, "aircraft": "Aircraft_5", "duration_per_case_s": baseline_duration_s,
		"command_line": OS.get_cmdline_args(), "user_args": OS.get_cmdline_user_args(),
		"physics_hz": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale,
		"start_altitude_m": 1000.0,
		"target": "invulnerable 4m-radius sphere", "gun_spread": "authored", "ammo": "1000000 per gun",
		"target_motion": "scripted static-frozen body; origin-rebased path; sampled velocity error must remain below 1m/s",
		"on_target_definition": "within 1 degree of ballistic solution and within 900m; acquire requires 0.5s continuous",
		"actual_bore_miss_definition": "current gun direction projected at solved intercept time; estimate, not actual hit",
		"legacy_metrics_note": "inherited solution_fraction/ballistic_quality are legacy ideal-aim heuristics, not measured accuracy",
		"input_hashes": baseline_hashes, "input_hashes_verified": unchanged, "results": baseline_results})
