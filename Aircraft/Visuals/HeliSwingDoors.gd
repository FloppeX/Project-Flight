extends AircraftModule

const PILOT_STATE_IDLE := 0
const PILOT_MISSION_AT_LZ := 1
const PILOT_MISSION_RESCUE := 4

@export var door_left_mesh_path: NodePath = NodePath("aircraft_11/Door Left")
@export var door_right_mesh_path: NodePath = NodePath("aircraft_11/Door Right")
@export var hinge_left_path: NodePath = NodePath("DoorHingeLeft_1")
@export var hinge_left_axis_path: NodePath = NodePath("DoorHingeLeft_2")
@export var hinge_right_path: NodePath = NodePath("DoorHingeRight_1")
@export var hinge_right_axis_path: NodePath = NodePath("DoorHingeRight_2")
@export var swing_angle_deg: float = 90.0
@export var animation_duration_s: float = 1.2
@export var toggle_key: Key = KEY_O
@export var only_player_controlled: bool = true
@export var debug_enabled: bool = false

var _left_door: MeshInstance3D
var _right_door: MeshInstance3D
var _left_hinge: Node3D
var _left_hinge_axis: Vector3 = Vector3.UP
var _right_hinge: Node3D
var _right_hinge_axis: Vector3 = Vector3.UP

var _open_target: bool = false
var _open_t: float = 0.0
var _initialized: bool = false
var _toggle_key_was_down: bool = false
var _is_landed_idle: bool = false


func _ready() -> void:
	ReceiveInput = true
	ProcessRender = true
	if aircraft == null and get_parent() != null:
		aircraft = get_parent()
		call_deferred("_setup_doors")


func setup(aircraft_node):
	aircraft = aircraft_node
	call_deferred("_setup_doors")


func receive_input(event: InputEvent) -> void:
	if not _initialized or not _is_this_aircraft_player_controlled():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == toggle_key:
			toggle_doors("manual")
			_toggle_key_was_down = true
			get_viewport().set_input_as_handled()


func process_render_frame(delta: float) -> void:
	if not _initialized:
		return
	
	if _is_this_aircraft_player_controlled():
		_poll_toggle_key()
	else:
		if _should_auto_open_at_lz():
			if not _is_landed_idle:
				_is_landed_idle = true
				open_doors("lz_idle")
				if debug_enabled:
					print("[HeliSwingDoors] %s doors opening: landing idle detected" % [aircraft.name])
		else:
			if _is_landed_idle:
				_is_landed_idle = false
				if _open_target:
					close_doors("leaving_lz_idle")
					if debug_enabled:
						print("[HeliSwingDoors] %s doors closing: takeoff/transition detected" % [aircraft.name])

	var target_t := 1.0 if _open_target else 0.0
	_open_t = move_toward(_open_t, target_t, delta / maxf(animation_duration_s, 0.01))
	_apply_door_pose()


func _poll_toggle_key() -> void:
	var key_down := Input.is_physical_key_pressed(toggle_key)
	if key_down and not _toggle_key_was_down and _is_this_aircraft_player_controlled():
		toggle_doors("manual")
	_toggle_key_was_down = key_down


func open_doors(reason: String = "script") -> void:
	set_doors_open(true, reason)


func close_doors(reason: String = "script") -> void:
	set_doors_open(false, reason)


func toggle_doors(reason: String = "script") -> void:
	set_doors_open(not _open_target, reason)


func set_doors_open(open: bool, reason: String = "script") -> void:
	if _open_target == open:
		return
	_open_target = open
	if debug_enabled:
		var craft_name: String = String(aircraft.name) if is_instance_valid(aircraft) else String(name)
		print("[HeliSwingDoors] %s doors target: open=%s reason=%s" % [craft_name, str(_open_target), reason])


func _setup_doors() -> void:
	if _initialized:
		return
	if not is_instance_valid(aircraft):
		return
	
	_left_door = aircraft.get_node_or_null(door_left_mesh_path) as MeshInstance3D
	_right_door = aircraft.get_node_or_null(door_right_mesh_path) as MeshInstance3D
	_left_hinge = aircraft.get_node_or_null(hinge_left_path) as Node3D
	_right_hinge = aircraft.get_node_or_null(hinge_right_path) as Node3D
	var left_axis_node := aircraft.get_node_or_null(hinge_left_axis_path) as Node3D
	var right_axis_node := aircraft.get_node_or_null(hinge_right_axis_path) as Node3D

	if _left_door == null or _right_door == null or _left_hinge == null or _right_hinge == null:
		push_warning("HeliSwingDoors: Missing door meshes or hinges on %s" % [aircraft.name])
		return

	# Compute each hinge axis in the hinge's local space from the two authored marker nodes.
	if left_axis_node != null:
		var world_axis := (left_axis_node.global_position - _left_hinge.global_position)
		if world_axis.length_squared() > 0.0001:
			_left_hinge_axis = (_left_hinge.global_basis.inverse() * world_axis).normalized()
	if right_axis_node != null:
		var world_axis := (right_axis_node.global_position - _right_hinge.global_position)
		if world_axis.length_squared() > 0.0001:
			_right_hinge_axis = (_right_hinge.global_basis.inverse() * world_axis).normalized()

	# Reparent Left Door to Left Hinge
	var left_global_trans = _left_door.global_transform
	_left_door.get_parent().remove_child(_left_door)
	_left_hinge.add_child(_left_door)
	_left_door.global_transform = left_global_trans
	_left_door.owner = _left_hinge.owner

	# Reparent Right Door to Right Hinge
	var right_global_trans = _right_door.global_transform
	_right_door.get_parent().remove_child(_right_door)
	_right_hinge.add_child(_right_door)
	_right_door.global_transform = right_global_trans
	_right_door.owner = _right_hinge.owner

	_initialized = true
	_apply_door_pose()
	if debug_enabled:
		print("[HeliSwingDoors] %s doors setup complete: left=%s, right=%s" % [aircraft.name, _left_door.name, _right_door.name])


func _apply_door_pose() -> void:
	var t := _smoothstep(clampf(_open_t, 0.0, 1.0))
	var angle_rad := deg_to_rad(swing_angle_deg) * t

	if _left_hinge != null:
		_left_hinge.basis = Basis(_left_hinge_axis, angle_rad)
	if _right_hinge != null:
		_right_hinge.basis = Basis(_right_hinge_axis, -angle_rad)


func _smoothstep(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


func _is_this_aircraft_player_controlled() -> bool:
	if not only_player_controlled:
		return true
	if not is_instance_valid(aircraft):
		return false
	var director := get_node_or_null("/root/FlightDirector")
	if director != null:
		var controlled = director.get("player_controlled_plane")
		if is_instance_valid(controlled) and controlled == aircraft:
			return true
		var viewed = director.get("current_viewed_aircraft")
		if is_instance_valid(viewed) and viewed == aircraft:
			return true
		return false
	var ai_toggle = aircraft.get_node_or_null("AIToggle")
	if ai_toggle != null and "ai_active" in ai_toggle:
		return not ai_toggle.ai_active
	return true


func _should_auto_open_at_lz() -> bool:
	if not is_instance_valid(aircraft):
		return false
	var pilot = aircraft.find_child("HelicopterPilot", true, false)
	if not is_instance_valid(pilot):
		return false
	if int(pilot.get("state")) != PILOT_STATE_IDLE:
		return false
	var phase := int(pilot.get("mission_phase"))
	return phase == PILOT_MISSION_AT_LZ or phase == PILOT_MISSION_RESCUE
