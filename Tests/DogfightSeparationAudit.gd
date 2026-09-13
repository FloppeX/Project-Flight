extends "res://Scenario/GunsOnlyDuel.gd"

var _trace: Array = []
var _trace_tick := 0
var _previous_velocity := {}
var _trace_written := false

func _ready() -> void:
	super._ready()
	var path := "res://Tests/DogfightSeparationAudit.gd"
	_input_hashes[path] = FileAccess.get_sha256(path)

func _physics_process(delta: float) -> void:
	if _summary_written:
		return
	_trace_tick += 1
	for entry in _combatants:
		var craft: Variant = entry.node
		if not is_instance_valid(craft):
			continue
		var velocity: Vector3 = craft.linear_velocity
		var acceleration: Vector3 = (velocity - Vector3(_previous_velocity.get(entry.name, velocity))) / maxf(delta, 0.001)
		_previous_velocity[entry.name] = velocity
		if _trace_tick % 6 != 0:
			continue
		var pilot: Node = craft.get_node("AIPilot")
		var opponent: Variant = _combatants[1 if int(entry.team) == 1 else 0].node
		_trace.append({"t": _elapsed_s, "name": entry.name, "position": _v(craft.global_position),
			"velocity": _v(velocity), "acceleration": _v(acceleration), "forward": _v(craft.global_basis.z),
			"bank": rad_to_deg(atan2(craft.global_basis.x.y, craft.global_basis.y.y)),
			"inputs": [pilot.roll_input, pilot.pitch_input, pilot.yaw_input, pilot.throttle_input],
			"state": pilot.current_state, "owner": pilot._recovery_control_owner,
			"waypoint": _v(pilot.maneuver_waypoint), "escape": _v(pilot._dogfight_escape_direction),
			"separation": craft.global_position.distance_to(opponent.global_position) if is_instance_valid(opponent) else -1.0,
			"metrics": pilot.get_dogfight_gunnery_metrics()})
	super._physics_process(delta)
	if _summary_written and not _trace_written:
		_trace_written = true
		var file := FileAccess.open(duel_log_path + ".trace.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(_trace))
		file.close()

func _v(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]
