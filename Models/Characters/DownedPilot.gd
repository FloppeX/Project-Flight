extends RigidBody3D

@export var walk_speed: float = 3.8
@export var run_speed: float = 5.5
@export var rescue_board_distance: float = 3.0
@export var clearing_search_radius_m: float = 80.0
@export var clearing_flat_radius_m: float = 12.0
@export var clearing_max_height_var_m: float = 2.0
@export var clearing_candidate_attempts: int = 40
@export var rescue_heli_max_agl_m: float = 4.0
@export_group("Animation")
@export var idle_animation: StringName = &"idle_breathing"
@export var walk_animation: StringName = &"walk"
@export var run_animation: StringName = &"run"
@export var turn_left_animation: StringName = &"turn_left"
@export var turn_right_animation: StringName = &"turn_right"
@export var wave_animation: StringName = &"wave"
@export var run_animation_threshold_mps: float = 4.6
@export var walk_animation_reference_speed_mps: float = 2.4
@export var run_animation_reference_speed_mps: float = 5.5
@export var turn_in_place_start_degrees: float = 25.0
@export var turn_in_place_finish_degrees: float = 5.0
@export var turn_speed_degrees_s: float = 90.0
@export_group("Rescue Signalling")
@export var helicopter_attention_range_m: float = 1000.0
@export var helicopter_scan_interval_s: float = 0.5
@export var wave_interval_s: float = 10.0
@export var wave_interval_jitter_s: float = 1.5

enum Phase {
	FIND_CLEARING,
	WAIT_RESCUE,
	RUN_TO_HELI,
	RESCUED,
}

var _phase: Phase = Phase.FIND_CLEARING
var _model_node: Node3D = null
var _clearing_target: Vector3 = Vector3.ZERO
var _rescue_heli: Node3D = null
var _attention_heli: Node3D = null
var _nearby_helicopter: Node3D = null
var _boardable_helicopter: Node3D = null
var _helicopter_scan_remaining_s: float = 0.0
var _animation_player: AnimationPlayer = null
var _current_animation: StringName = &""
var _turning_in_place: bool = false
var _wave_due: bool = false
var _wave_active: bool = false
var _wave_cooldown_s: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 4
	collision_mask = 513
	freeze = true

	_model_node = get_node_or_null("Model")
	if _model_node != null:
		_animation_player = _model_node.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
	_rng.randomize()
	_play_model_animation(idle_animation)

	_clearing_target = _find_clearing()
	print("[DownedPilot] %s spawned — walking to clearing at %s" % [name, str(_clearing_target.snapped(Vector3.ONE))])


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _phase == Phase.RESCUED:
		return
	_refresh_helicopter_candidates(delta)
	# Godot validates typed arguments before entering the called function. A
	# helicopter can be freed between scan ticks, so clear stale Object handles
	# before passing the cached reference to a Node3D-typed parameter.
	if not is_instance_valid(_nearby_helicopter):
		_nearby_helicopter = null
	if not is_instance_valid(_boardable_helicopter):
		_boardable_helicopter = null
	_update_helicopter_attention(_nearby_helicopter, delta)

	match _phase:
		Phase.FIND_CLEARING:
			_walk_toward(_clearing_target, walk_speed, delta)
			var flat_dist := Vector2(global_position.x - _clearing_target.x, global_position.z - _clearing_target.z).length()
			if flat_dist < 2.0:
				_phase = Phase.WAIT_RESCUE
				_turning_in_place = false
				_play_model_animation(idle_animation)
				print("[DownedPilot] %s reached clearing — waiting for rescue" % name)

		Phase.WAIT_RESCUE:
			var heli: Node3D = (
				_boardable_helicopter if is_instance_valid(_boardable_helicopter) else null
			)
			if heli != null:
				_rescue_heli = heli
				_phase = Phase.RUN_TO_HELI
				_wave_active = false
				print("[DownedPilot] %s sees rescue heli %s — running to board" % [name, heli.name])
			else:
				_update_waiting_animation(delta)

		Phase.RUN_TO_HELI:
			if not is_instance_valid(_rescue_heli):
				_rescue_heli = null
				_phase = Phase.WAIT_RESCUE
				_play_model_animation(idle_animation)
				return
			var diff := _rescue_heli.global_position - global_position
			var diff_xz := Vector3(diff.x, 0.0, diff.z)
			var dist := diff_xz.length()
			if dist <= rescue_board_distance:
				_board_helicopter(_rescue_heli)
			else:
				if not _heli_is_boardable(_rescue_heli):
					_rescue_heli = null
					_phase = Phase.WAIT_RESCUE
					_play_model_animation(idle_animation)
					return
				_walk_toward(_rescue_heli.global_position, run_speed, delta)

	_snap_to_terrain()


func _walk_toward(target: Vector3, speed: float, delta: float) -> void:
	var diff_xz := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var dist := diff_xz.length()
	if dist < 0.5:
		_turning_in_place = false
		_play_model_animation(idle_animation)
		return
	var dir := diff_xz / dist
	if _turn_model_toward(dir, delta, turn_in_place_start_degrees):
		return
	global_position.x += dir.x * speed * delta
	global_position.z += dir.z * speed * delta
	if _model_node != null:
		var target_basis := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.UP, PI)
		_model_node.quaternion = _model_node.quaternion.slerp(target_basis.get_rotation_quaternion(), 8.0 * delta)
	_play_movement_animation(speed)


func _play_movement_animation(speed: float) -> void:
	var use_run := speed >= run_animation_threshold_mps
	var animation_name := run_animation if use_run else walk_animation
	var reference_speed := (
		run_animation_reference_speed_mps if use_run else walk_animation_reference_speed_mps
	)
	var playback_speed := clampf(speed / maxf(reference_speed, 0.1), 0.55, 1.6)
	_play_model_animation(animation_name, playback_speed)


func _play_model_animation(animation_name: StringName, speed_scale: float = 1.0) -> bool:
	if _model_node == null or animation_name == &"":
		return false
	_model_node.visible = true
	if _animation_player != null \
			and _current_animation == animation_name \
			and _animation_player.is_playing():
		_animation_player.speed_scale = maxf(speed_scale, 0.01)
		return true
	if _model_node.has_method("play_baked_animation") \
			and bool(_model_node.call("play_baked_animation", animation_name, speed_scale)):
		_current_animation = animation_name
		return true
	# Compatibility fallback for an older character scene without baked clips.
	if animation_name == walk_animation or animation_name == run_animation:
		if _model_node.has_method("set_locomotion_pose"):
			_model_node.call("set_locomotion_pose", true, speed_scale)
			_current_animation = animation_name
			return true
	elif _model_node.has_method("set_ejection_pose"):
		_model_node.call("set_ejection_pose", &"grounded", 0.0)
		_current_animation = animation_name
		return true
	return false


func _turn_model_toward(
		direction: Vector3,
		delta: float,
		start_threshold_degrees: float
) -> bool:
	if _model_node == null or direction.length_squared() < 0.000001:
		return false
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	var current_forward := _model_node.global_transform.basis.z
	current_forward.y = 0.0
	current_forward = current_forward.normalized()
	var signed_angle := atan2(
		current_forward.cross(flat_direction).dot(Vector3.UP),
		clampf(current_forward.dot(flat_direction), -1.0, 1.0)
	)
	var angle_degrees := absf(rad_to_deg(signed_angle))
	if _turning_in_place:
		if angle_degrees <= turn_in_place_finish_degrees:
			_turning_in_place = false
			return false
	elif angle_degrees <= start_threshold_degrees:
		return false

	_turning_in_place = true
	var target_basis := Basis.looking_at(flat_direction, Vector3.UP) * Basis(Vector3.UP, PI)
	var max_step := deg_to_rad(maxf(turn_speed_degrees_s, 1.0)) * maxf(delta, 0.0)
	var blend_weight := minf(max_step / maxf(absf(signed_angle), 0.0001), 1.0)
	_model_node.quaternion = _model_node.quaternion.slerp(
		target_basis.get_rotation_quaternion(), blend_weight
	)
	_play_model_animation(
		turn_left_animation if signed_angle > 0.0 else turn_right_animation
	)
	return true


func _update_helicopter_attention(heli: Node3D, delta: float) -> void:
	if heli != null and not is_instance_valid(heli):
		heli = null
	if _attention_heli != null and not is_instance_valid(_attention_heli):
		_attention_heli = null
	if heli != _attention_heli:
		_attention_heli = heli
		_wave_due = heli != null
		_wave_cooldown_s = 0.0
	if _attention_heli == null:
		_wave_due = false
		return
	_wave_cooldown_s = maxf(_wave_cooldown_s - delta, 0.0)
	if _wave_cooldown_s <= 0.0:
		_wave_due = true


func _update_waiting_animation(delta: float) -> void:
	if _wave_active:
		if _animation_player != null \
				and _animation_player.assigned_animation == wave_animation \
				and _animation_player.is_playing():
			if is_instance_valid(_attention_heli):
				_rotate_model_toward_without_animation(
					_attention_heli.global_position - global_position, delta
				)
			return
		_wave_active = false

	if not is_instance_valid(_attention_heli):
		_turning_in_place = false
		_play_model_animation(idle_animation)
		return
	var to_helicopter := _attention_heli.global_position - global_position
	to_helicopter.y = 0.0
	if _turn_model_toward(to_helicopter, delta, turn_in_place_finish_degrees):
		return
	if _wave_due:
		_wave_due = false
		_wave_active = _play_model_animation(wave_animation)
		_wave_cooldown_s = _next_wave_interval()
		return
	_play_model_animation(idle_animation)


func _rotate_model_toward_without_animation(direction: Vector3, delta: float) -> void:
	if _model_node == null or direction.length_squared() < 0.000001:
		return
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	var target_basis := Basis.looking_at(flat_direction, Vector3.UP) * Basis(Vector3.UP, PI)
	var current_rotation := _model_node.quaternion
	var target_rotation := target_basis.get_rotation_quaternion()
	var angle := current_rotation.angle_to(target_rotation)
	var max_step := deg_to_rad(maxf(turn_speed_degrees_s, 1.0)) * maxf(delta, 0.0)
	_model_node.quaternion = current_rotation.slerp(
		target_rotation, minf(max_step / maxf(angle, 0.0001), 1.0)
	)


func _next_wave_interval() -> float:
	var jitter := maxf(wave_interval_jitter_s, 0.0)
	return maxf(wave_interval_s + _rng.randf_range(-jitter, jitter), 1.0)


func _snap_to_terrain() -> void:
	var terrain_nav = get_node_or_null("/root/TerrainNavGrid")
	var ground_y := 0.0
	if terrain_nav != null and terrain_nav.has_method("sample_height"):
		ground_y = float(terrain_nav.call("sample_height", global_position.x, global_position.z))
	if is_nan(ground_y) or ground_y < -9000.0:
		ground_y = 0.0
	global_position.y = ground_y


# --- Rescue helicopter detection ---

func _refresh_helicopter_candidates(delta: float) -> void:
	_helicopter_scan_remaining_s -= delta
	if _helicopter_scan_remaining_s > 0.0:
		return
	_helicopter_scan_remaining_s = maxf(helicopter_scan_interval_s, 0.0)
	_nearby_helicopter = _find_nearest_helicopter()
	_boardable_helicopter = _find_rescue_heli_with_open_doors()


func _find_nearest_helicopter() -> Node3D:
	var best: Node3D = null
	var best_distance_squared := pow(maxf(helicopter_attention_range_m, 0.0), 2.0)
	for node in get_tree().get_nodes_in_group("friendlies"):
		var friendly := node as Node3D
		if friendly == null or not friendly.has_meta("is_helicopter") \
				or not bool(friendly.get_meta("is_helicopter")):
			continue
		var distance_squared := global_position.distance_squared_to(friendly.global_position)
		if distance_squared <= best_distance_squared:
			best_distance_squared = distance_squared
			best = friendly
	return best


func _find_rescue_heli_with_open_doors() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("friendlies"):
		var friendly := node as Node3D
		if friendly == null:
			continue
		if not (friendly.has_meta("is_helicopter") and bool(friendly.get_meta("is_helicopter"))):
			continue
		if not _heli_is_boardable(friendly):
			continue
		var dist := global_position.distance_squared_to(friendly.global_position)
		if dist < best_dist:
			best_dist = dist
			best = friendly
	return best


func _heli_is_boardable(heli: Node3D) -> bool:
	if not is_instance_valid(heli):
		return false
	var heli_pilot := heli.find_child("HelicopterPilot", true, false)
	if heli_pilot != null and heli_pilot.has_method("can_accept_passenger") \
			and not bool(heli_pilot.call("can_accept_passenger")):
		return false
	var terrain_nav = get_node_or_null("/root/TerrainNavGrid")
	var ground_y := 0.0
	if terrain_nav != null and terrain_nav.has_method("sample_height"):
		ground_y = float(terrain_nav.call("sample_height", heli.global_position.x, heli.global_position.z))
	if is_nan(ground_y) or ground_y < -9000.0:
		ground_y = 0.0
	if heli.global_position.y - ground_y > rescue_heli_max_agl_m:
		return false
	var doors := heli.find_child("HeliSwingDoors", true, false)
	if doors != null and doors.get("_open_target") != null:
		return bool(doors.get("_open_target"))
	return true


# --- Boarding ---

func _board_helicopter(heli: Node3D) -> void:
	var heli_pilot := heli.find_child("HelicopterPilot", true, false)
	if heli_pilot == null or not heli_pilot.has_method("add_passenger"):
		_rescue_heli = null
		_phase = Phase.WAIT_RESCUE
		return
	if heli_pilot.has_method("can_accept_passenger") \
			and not bool(heli_pilot.call("can_accept_passenger")):
		_rescue_heli = null
		_phase = Phase.WAIT_RESCUE
		return
	if not bool(heli_pilot.call("add_passenger", self)):
		_rescue_heli = null
		_phase = Phase.WAIT_RESCUE
		return
	_phase = Phase.RESCUED
	print("[DownedPilot] %s boarding %s" % [name, heli.name])

	var callsign: String = str(get_meta("pilot_callsign")) if has_meta("pilot_callsign") else "Downed Pilot"
	var radio = get_node_or_null("/root/RadioComms")
	if radio != null and radio.has_method("transmit"):
		radio.call("transmit", callsign, "Citadel", "Aboard rescue helicopter. Safe and secure.")

	var air_ops := get_node_or_null("/root/AirOpsManager")
	if air_ops != null and air_ops.has_method("notify_pilot_rescued"):
		air_ops.call("notify_pilot_rescued", self, heli)

	var flight_director := get_node_or_null("/root/FlightDirector")
	if flight_director != null:
		var was_viewed: bool = flight_director.get("current_viewed_aircraft") == self
		if was_viewed and is_instance_valid(heli):
			# Redirect view to rescue heli BEFORE unregistering so unregister_aircraft
			# doesn't see self as current_viewed_aircraft and fire its own _activate_view
			# with a freed node reference.
			flight_director.set("current_viewed_aircraft", heli)
		flight_director.call("unregister_aircraft", self)
		if was_viewed and is_instance_valid(heli):
			flight_director.set("current_category", 1) # Category.FRIENDLY
			flight_director.set("current_viewed_aircraft", heli)
			flight_director.call("_select_friendly_index_for", heli)
			# Reset the CameraController out of ejected-pilot mode so it can
			# build a full view-targets list for the helicopter.
			for cc in get_tree().get_nodes_in_group("camera_controller"):
				if cc != null and cc.has_method("release_ejected_pilot"):
					cc.call("release_ejected_pilot", heli)
			flight_director.call("_activate_view")

	queue_free()


# --- Clearing search ---

func _find_clearing() -> Vector3:
	var terrain_nav = get_node_or_null("/root/TerrainNavGrid")
	var origin := global_position
	var best_pos := origin
	var best_score := -INF
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for _i in range(clearing_candidate_attempts):
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(10.0, clearing_search_radius_m)
		var candidate := origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		if terrain_nav != null and terrain_nav.has_method("sample_height"):
			var cy := float(terrain_nav.call("sample_height", candidate.x, candidate.z))
			if is_nan(cy) or cy < -9000.0:
				continue
			candidate.y = cy

		var score := _score_clearing(candidate, terrain_nav)
		if score > best_score:
			best_score = score
			best_pos = candidate

	return best_pos


func _score_clearing(center: Vector3, terrain_nav) -> float:
	if terrain_nav == null or not terrain_nav.has_method("sample_height"):
		return 0.0
	var max_h := -INF
	var min_h := INF
	for i in range(8):
		var a := (float(i) / 8.0) * TAU
		var px := center.x + cos(a) * clearing_flat_radius_m
		var pz := center.z + sin(a) * clearing_flat_radius_m
		var h := float(terrain_nav.call("sample_height", px, pz))
		if is_nan(h) or h < -9000.0:
			return -INF
		max_h = maxf(max_h, h)
		min_h = minf(min_h, h)
	if max_h - min_h > clearing_max_height_var_m:
		return -INF
	var dist := Vector2(center.x - global_position.x, center.z - global_position.z).length()
	return -(abs(dist - clearing_search_radius_m * 0.5))
