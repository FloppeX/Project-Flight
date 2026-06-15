extends RigidBody3D

@export var walk_speed: float = 3.8
@export var run_speed: float = 5.5
@export var rescue_board_distance: float = 3.0
@export var clearing_search_radius_m: float = 80.0
@export var clearing_flat_radius_m: float = 12.0
@export var clearing_max_height_var_m: float = 2.0
@export var clearing_candidate_attempts: int = 40
@export var rescue_heli_max_agl_m: float = 4.0

enum Phase {
	FIND_CLEARING,
	WAIT_RESCUE,
	RUN_TO_HELI,
	RESCUED,
}

var _phase: Phase = Phase.FIND_CLEARING
var _model_node: Node3D = null
var _pilot_pose: Node = null        # PilotPose node
var _anim_player: AnimationPlayer = null
var _running_anim_name: String = ""
var _clearing_target: Vector3 = Vector3.ZERO
var _rescue_heli: Node3D = null
var _is_running: bool = false


func _ready() -> void:
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 4
	collision_mask = 513
	freeze = true

	_model_node = get_node_or_null("Model")
	_pilot_pose = get_node_or_null("PilotPose")

	# Load the running animation into the model's AnimationPlayer so PilotPose
	# can play it. The sitting GLB shares the same Mixamo skeleton as the running FBX.
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	var run_fbx_path := "res://Models/Characters/Pilot 2 - running.fbx"
	if _anim_player != null and ResourceLoader.exists(run_fbx_path):
		var run_scene := load(run_fbx_path) as PackedScene
		if run_scene != null:
			var run_inst := run_scene.instantiate()
			var run_ap := run_inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if run_ap != null:
				for lib_name in run_ap.get_animation_library_list():
					var lib := run_ap.get_animation_library(lib_name)
					if not _anim_player.has_animation_library(lib_name):
						_anim_player.add_animation_library(lib_name, lib)
					else:
						var existing := _anim_player.get_animation_library(lib_name)
						for anim_name in lib.get_animation_list():
							if not existing.has_animation(anim_name):
								existing.add_animation(anim_name, lib.get_animation(anim_name))
				# Find a run/jog animation name
				for lib_name in _anim_player.get_animation_library_list():
					var lib2 := _anim_player.get_animation_library(lib_name)
					for anim_name in lib2.get_animation_list():
						var full := (str(lib_name) + "/" + str(anim_name)) if str(lib_name) != "" else str(anim_name)
						if _running_anim_name == "" or "run" in full.to_lower() or "jog" in full.to_lower():
							_running_anim_name = full
			run_inst.queue_free()

	_clearing_target = _find_clearing()
	print("[DownedPilot] %s spawned — walking to clearing at %s" % [name, str(_clearing_target.snapped(Vector3.ONE))])


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _phase == Phase.RESCUED:
		return

	match _phase:
		Phase.FIND_CLEARING:
			_walk_toward(_clearing_target, walk_speed, delta)
			var flat_dist := Vector2(global_position.x - _clearing_target.x, global_position.z - _clearing_target.z).length()
			if flat_dist < 2.0:
				_phase = Phase.WAIT_RESCUE
				_set_running(false)
				print("[DownedPilot] %s reached clearing — waiting for rescue" % name)

		Phase.WAIT_RESCUE:
			_set_running(false)
			var heli := _find_rescue_heli_with_open_doors()
			if heli != null:
				_rescue_heli = heli
				_phase = Phase.RUN_TO_HELI
				print("[DownedPilot] %s sees rescue heli %s — running to board" % [name, heli.name])

		Phase.RUN_TO_HELI:
			if not is_instance_valid(_rescue_heli):
				_rescue_heli = null
				_phase = Phase.WAIT_RESCUE
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
					return
				_walk_toward(_rescue_heli.global_position, run_speed, delta)

	_snap_to_terrain()


func _walk_toward(target: Vector3, speed: float, delta: float) -> void:
	var diff_xz := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var dist := diff_xz.length()
	if dist < 0.5:
		_set_running(false)
		return
	var dir := diff_xz / dist
	global_position.x += dir.x * speed * delta
	global_position.z += dir.z * speed * delta
	if _model_node != null:
		var target_basis := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.UP, PI)
		_model_node.quaternion = _model_node.quaternion.slerp(target_basis.get_rotation_quaternion(), 8.0 * delta)
	_set_running(true)


func _set_running(running: bool) -> void:
	if running == _is_running:
		return
	_is_running = running
	if _anim_player == null:
		return
	if running:
		if _running_anim_name != "":
			_anim_player.active = true
			_anim_player.play(_running_anim_name)
			var anim := _anim_player.get_animation(_running_anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
		# Stop PilotPose from fighting the animation
		if _pilot_pose != null and _pilot_pose.has_method("set_process"):
			_pilot_pose.set_process(false)
	else:
		_anim_player.stop()
		_anim_player.active = false
		# Restore PilotPose so it holds the grounded pose
		if _pilot_pose != null:
			if _pilot_pose.has_method("set_process"):
				_pilot_pose.set_process(true)
			if _pilot_pose.has_method("set_ejection_pose"):
				_pilot_pose.call("set_ejection_pose", &"grounded", 0.3)


func _snap_to_terrain() -> void:
	var terrain_nav = get_node_or_null("/root/TerrainNavGrid")
	var ground_y := 0.0
	if terrain_nav != null and terrain_nav.has_method("sample_height"):
		ground_y = float(terrain_nav.call("sample_height", global_position.x, global_position.z))
	if is_nan(ground_y) or ground_y < -9000.0:
		ground_y = 0.0
	global_position.y = ground_y


# --- Rescue helicopter detection ---

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
	_phase = Phase.RESCUED
	print("[DownedPilot] %s boarding %s" % [name, heli.name])

	var callsign: String = str(get_meta("pilot_callsign")) if has_meta("pilot_callsign") else "Downed Pilot"
	var radio = get_node_or_null("/root/RadioComms")
	if radio != null and radio.has_method("transmit"):
		radio.call("transmit", callsign, "Citadel", "Aboard rescue helicopter. Returning to carrier.")

	var heli_pilot := heli.find_child("HelicopterPilot", true, false)
	if heli_pilot != null and heli_pilot.has_method("add_passenger"):
		heli_pilot.call("add_passenger", self)

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
