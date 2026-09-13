extends "res://Scenario/GunsOnlyDuel.gd"

var _audit := {}
var _ground_valid := false
var _audit_written := false
var _audit_hashes := {}

func _ready() -> void:
	_ground_valid = OS.get_cmdline_user_args().has("--audit-flat-ground")
	for path in ["res://AI/AIPilot.gd", "res://AI/FlightPathFollower.gd", "res://Aircraft/SimpleAero.gd",
			"res://Aircraft/Aircraft_3.tscn", "res://Aircraft/Aircraft_5.tscn"]:
		_audit_hashes[path] = FileAccess.get_sha256(path)
	super._ready()
	round_max_duration_s = 90.0

func _flat_ground(_position: Vector3) -> float:
	return 0.0

func _spawn_ai_fighter(scene: PackedScene, fighter_name: String, team: int, pos: Vector3,
		heading: float, speed_mps: float, skill_override: int = -1) -> RigidBody3D:
	var craft := super._spawn_ai_fighter(scene, fighter_name, team, pos, heading, speed_mps, skill_override)
	var pilot: Node = craft.find_child("AIPilot", true, false)
	if _ground_valid:
		pilot.set("_terrain_height_callable", Callable(self, "_flat_ground"))
	else:
		# Deliberately reproduce the old missing-contract case; parent now supplies it.
		pilot.set("_terrain_height_callable", Callable())
	var aero: Node = craft.get_node("SimpleAero")
	_audit[fighter_name] = {"samples": 0, "duration": 0.0, "energy_start": 0.0,
		"energy_end": 0.0, "thrust_work": 0.0, "drag_work": 0.0, "lift_work": 0.0,
		"alignment_work": 0.0, "power_max": 0.0, "drag_positive_samples": 0,
		"alignment_positive_samples": 0, "lift_power_abs_max": 0.0,
		"blind_samples": 0, "tracking_while_blind": 0, "unknown_ground_samples": 0,
		"trace": []}
	aero.force_audit_sample.connect(_sample_force.bind(craft, pilot, aero, fighter_name))
	return craft

func _sample_force(sample: Dictionary, craft: RigidBody3D, pilot: Node, aero: Node, name_key: String) -> void:
	if _elapsed_s < 2.0 or _round_over:
		return
	var record: Dictionary = _audit[name_key]
	var velocity: Vector3 = sample.velocity
	var weight := craft.mass * 9.8
	var thrust := Vector3.ZERO
	for engine in aero._get_engine_modules_for_report():
		if engine.is_engine_working:
			thrust += -engine.global_basis.z * engine.get_effective_power_factor() * engine.current_power
	var thrust_power := thrust.dot(velocity) / weight
	var drag_power: float = sample.drag.dot(velocity) / weight
	var lift_power: float = sample.lift.dot(velocity) / weight
	var alignment_power: float = sample.alignment.dot(velocity) / weight
	var energy := craft.global_position.y + velocity.length_squared() / 19.6
	if record.samples == 0:
		record.energy_start = energy
	record.energy_end = energy
	record.duration += sample.delta
	record.samples += 1
	record.thrust_work += thrust_power * sample.delta
	record.drag_work += drag_power * sample.delta
	record.lift_work += lift_power * sample.delta
	record.alignment_work += alignment_power * sample.delta
	record.drag_positive_samples += int(drag_power > 0.001)
	record.alignment_positive_samples += int(alignment_power > 0.001)
	record.lift_power_abs_max = maxf(record.lift_power_abs_max, absf(lift_power))
	var opponent: Variant = pilot.combat_target
	var awareness := 1.0
	if is_instance_valid(opponent):
		awareness = pilot._get_enemy_awareness(opponent)
		if awareness < pilot.dogfight_awareness_drop_threshold:
			record.blind_samples += 1
			record.tracking_while_blind += int(pilot.current_state == AIPilot.State.DOGFIGHT)
	var ground: float = pilot._get_ground_height_at_position(craft.global_position)
	record.unknown_ground_samples += int(is_nan(ground))
	if int(record.samples) % 60 == 0:
		var metrics: Dictionary = pilot.get_dogfight_gunnery_metrics()
		record.trace.append({"t": _elapsed_s, "alt": craft.global_position.y,
			"speed": velocity.length(), "vs": velocity.y, "desired_vs": metrics.desired_vertical_speed_mps,
			"aim_y": pilot.nav_waypoint.y, "ground_valid": not is_nan(ground), "advanced": sample.advanced,
			"awareness": awareness, "recovering": metrics.energy_recovering,
			"load": sample.load, "target_load": metrics.target_load_g,
			"thrust_n": thrust.length(), "induced_drag_n": sample.induced_drag_n,
			"thrust_power": thrust_power, "drag_power": drag_power,
			"alignment_power": alignment_power, "energy": energy})

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _round_over and not _audit_written:
		_audit_written = true
		var unchanged := true
		for path in _audit_hashes:
			unchanged = unchanged and FileAccess.get_sha256(path) == _audit_hashes[path]
		var file := FileAccess.open(duel_log_path + ".audit.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"status": "COMPLETE", "ground_provider": _ground_valid,
			"hashes_verified": unchanged, "input_hashes": _audit_hashes, "aircraft": _audit}, "\t"))
		file.close()
		_log("ENERGY_AUDIT_COMPLETE hashes_verified=%s" % unchanged)
		get_tree().quit()
