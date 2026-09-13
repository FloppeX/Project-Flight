extends Node
## Three rigid vehicle-relative poses. Aircraft are independent; ground presets shared.
const Rig = preload("res://Recording/RecordingCamera.gd")
const FREE := 3
const ANCHORED := 4
const PILOT := 5
const VIEW_COUNT := 6
const VIEW_NAMES := ["CAMERA 1", "CAMERA 2", "CAMERA 3", "FREE CAM", "FREE CAM ANCHORED", "COCKPIT / PILOT"]
var camera: Camera3D
var active := false
var piloting := false
var subject: Node3D
var slot := 0
var banks: Dictionary = {}
var _previous: Camera3D
var _previous_mouse := Input.MOUSE_MODE_VISIBLE
var _look := Vector2.ZERO
var _editing := false
var _label: Label
var _focus_node: Node3D
var _focus_offset := Vector3.ZERO
var _orbit_offset := Vector3.ZERO
var _orbit_roll := 0.0
var _pad_device := -1
var _pad_axes: Dictionary = {}
var _pad_buttons: Dictionary = {}
var _presented_subject: WeakRef

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 900
	add_to_group("trailer_aircraft_cameras")
	add_to_group("origin_shifter")
	add_to_group("target_camera_focus_provider")
	Input.joy_connection_changed.connect(_on_pad_connection)
	camera = Rig.new()
	camera.name = "TrailerAircraftCamera"
	add_child(camera)
	camera.interpolated_target = true
	var canvas := CanvasLayer.new()
	canvas.layer = 31
	add_child(canvas)
	_label = Label.new()
	_label.text = "←/→ vehicle · ↑/↓ camera · Space pause/play · AltGr record"
	_label.position = Vector2(20, 168)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_outline_size", 6)
	canvas.add_child(_label)

func aircraft_list() -> Array[Node3D]:
	return _list_groups(["aircraft", "ai_aircraft"])

func vehicle_list() -> Array[Node3D]:
	return _list_groups(["aircraft", "ai_aircraft", "ground_vehicles", "carrier", "friendlies", "enemies"])

func _list_groups(groups: Array) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for group in groups:
		for node in get_tree().get_nodes_in_group(group):
			if not node is Node3D or node.is_queued_for_deletion() or result.has(node): continue
			if group in ["friendlies", "enemies"] and not node is GroundVehicle: continue
			if not node.is_visible_in_tree(): continue
			result.append(node)
	result.sort_custom(func(a: Node3D, b: Node3D): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return result

func _bank(aircraft: Node3D) -> Array:
	var id: Variant = "ground_shared" if _is_ground(aircraft) else aircraft.get_instance_id()
	if not banks.has(id):
		var key := _preset_key(aircraft)
		if GameSession.trailer_camera_presets.has(key):
			banks[id] = GameSession.trailer_camera_presets[key].duplicate(true)
			return banks[id]
		var poses: Array = []
		var positions := [Vector3(0, 4, -18), Vector3(12, 3, 0), Vector3(0, 2, 12)]
		var aim := Vector3(0, 1, 0)
		if _is_ground(aircraft): positions = [Vector3(0, 4, -12), Vector3(10, 3, 0), Vector3(0, 3, 12)]
		if aircraft.is_in_group("carrier"):
			positions = [Vector3(0, 65, -180), Vector3(150, 55, 0), Vector3(0, 55, 180)]
			aim = Vector3(0, 20, 0)
		for position in positions:
			poses.append({"pose": Transform3D(Basis.IDENTITY, position).looking_at(aim, Vector3.UP), "fov": 65.0})
		banks[id] = poses
	return banks[id]

func _preset_key(aircraft: Node3D) -> String:
	if _is_ground(aircraft): return "trailer::ground_shared"
	return "%s::%s" % [aircraft.get_meta("source_scene_path", aircraft.scene_file_path), aircraft.name]

func _is_ground(vehicle: Node3D) -> bool:
	return not vehicle.is_in_group("carrier") and (vehicle.is_in_group("ground_vehicles") or vehicle is GroundVehicle)

func view_count(vehicle: Variant = subject) -> int:
	if not is_instance_valid(vehicle) or not vehicle is RigidBody3D: return PILOT
	if not (vehicle.is_in_group("aircraft") or vehicle.is_in_group("ai_aircraft")): return PILOT
	return VIEW_COUNT if vehicle.has_node("AIToggle") and not bool(vehicle.get_meta("player_control_locked", false)) else PILOT

func select_slot(index: int, aircraft: Node3D = null) -> bool:
	if index < 0 or index >= VIEW_COUNT: return false
	if not is_instance_valid(aircraft): aircraft = subject
	if not is_instance_valid(aircraft) or aircraft.is_queued_for_deletion():
		var available := vehicle_list()
		if available.is_empty():
			_label.text = "No viewable vehicles yet — wait for scenario staging."
			return false
		var viewed: Variant = FlightDirector.current_viewed_aircraft
		aircraft = viewed if is_instance_valid(viewed) and available.has(viewed) else available[0]
	if index == PILOT:
		if view_count(aircraft) <= PILOT: return false
		release_camera(false)
		subject = aircraft
		if not FlightDirector.enter_trailer_pilot(aircraft): return select_slot(0, aircraft)
		slot = PILOT
		piloting = true
		return true
	if piloting:
		if FlightDirector.player_controlled_plane == subject: FlightDirector._return_control_to_ai()
		piloting = false
	_save_pose()
	var previous_view := camera if active else get_viewport().get_camera_3d()
	var opening_pose := previous_view.global_transform if is_instance_valid(previous_view) else Transform3D.IDENTITY
	var opening_fov := previous_view.fov if is_instance_valid(previous_view) else 65.0
	if active and subject != aircraft:
		# New vehicle: begin nearby rather than leaving a free view kilometres away.
		opening_pose = aircraft.global_transform * (_bank(aircraft)[0].pose as Transform3D)
	if not active:
		_previous = get_viewport().get_camera_3d()
		_previous_mouse = Input.mouse_mode
		if FlightDirector.is_player_controlling: FlightDirector._return_control_to_ai()
		if is_instance_valid(_previous): FlightDirector._copy_camera_view_state(_previous, camera)
		camera.near = 0.05
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		active = true
		FlightDirector.trailer_camera_active = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	subject = aircraft
	_present_occupants(subject)
	slot = index
	camera.aim_target = null
	if slot < FREE:
		var saved: Dictionary = _bank(subject)[slot]
		camera.target = subject
		camera.attachment = Rig.Attachment.FULL
		camera.offset = saved.pose
		camera.fov = saved.fov
	else:
		camera.target = null
		camera.attachment = Rig.Attachment.WORLD
		camera.offset = opening_pose
		camera.fov = opening_fov
	camera.motion = Vector3.ZERO
	camera.move_camera(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
	if slot == ANCHORED:
		_resolve_focus()
		_orbit_offset = camera.global_position - _focus_point()
		if _orbit_offset.length() < 0.3: _orbit_offset = camera.global_basis.z * 3.0
		var aimed := _orbit_basis()
		_orbit_roll = atan2(camera.global_basis.x.dot(aimed.y), camera.global_basis.x.dot(aimed.x))
		_move_anchored(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
	camera.make_current()
	var terrain := TerrainReference.get_terrain_node()
	if terrain != null and terrain.has_method("prioritize_camera_handoff"):
		terrain.call("prioritize_camera_handoff", camera)
	return true

func cycle_aircraft(step: int = 1) -> void:
	cycle_vehicle(step)

func cycle_vehicle(step: int = 1) -> void:
	var available := vehicle_list()
	if available.is_empty():
		select_slot(slot)
		return
	var index := available.find(subject)
	if index == -1:
		var next := available[0 if step > 0 else available.size() - 1]
		select_slot(mini(slot, view_count(next) - 1), next)
	else:
		var next := available[posmod(index + step, available.size())]
		select_slot(mini(slot, view_count(next) - 1), next)

func _save_pose() -> void:
	if active and slot < FREE and is_instance_valid(subject):
		_bank(subject)[slot] = {"pose": camera.offset, "fov": camera.fov}
		GameSession.trailer_camera_presets[_preset_key(subject)] = _bank(subject).duplicate(true)

func release_camera(restore_view: bool = true) -> void:
	if piloting:
		if FlightDirector.player_controlled_plane == subject: FlightDirector._return_control_to_ai()
		piloting = false
	if not active: return
	_save_pose()
	active = false
	_editing = false
	_look = Vector2.ZERO
	_clear_pad()
	_release_occupants()
	FlightDirector.trailer_camera_active = false
	Input.mouse_mode = _previous_mouse
	if restore_view:
		if is_instance_valid(_previous): FlightDirector._force_current_camera(_previous)
		else: FlightDirector._activate_view()
	_label.text = "←/→ vehicle · ↑/↓ camera · Space pause/play · AltGr record"

func _process(delta: float) -> void:
	_label.visible = not RecordingMode.active and not PauseMenu.visible and not PauseMenu.is_photo_mode_active()
	if piloting:
		_label.text = "COCKPIT / PILOT · Normal flight controls · ↑/↓ leave cockpit · AltGr record"
		if not is_instance_valid(subject) or FlightDirector.player_controlled_plane != subject: piloting = false
		return
	if not active: return
	if RecordingMode.active or PauseMenu.is_photo_mode_active():
		release_camera(false)
		return
	if slot != FREE and (not is_instance_valid(subject) or subject.is_queued_for_deletion()):
		release_camera()
		subject = null
		return
	if PauseMenu.visible:
		_editing = false
		_look = Vector2.ZERO
		_clear_pad()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		_clear_pad()
		_look = Vector2.ZERO
		return
	var direction := Vector3.ZERO
	var roll := 0.0
	if _editing:
		direction = Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		roll = float(Input.is_physical_key_pressed(KEY_C)) - float(Input.is_physical_key_pressed(KEY_Z))
	var pad := _pad_motion()
	direction += pad.move
	_look += pad.look * delta * 1.4
	roll += pad.roll
	var old_fov := camera.fov
	camera.fov = clampf(camera.fov + float(pad.zoom) * 40.0 * delta, 15.0, 110.0)
	camera.move_speed = 10.0 * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else (0.2 if Input.is_physical_key_pressed(KEY_CTRL) else 1.0))
	# No residual drift when the operator stops moving the rig.
	if direction.is_zero_approx(): camera.motion = Vector3.ZERO
	if slot == ANCHORED:
		_move_anchored(direction, _look, roll, delta)
	elif direction.is_zero_approx() and _look.is_zero_approx() and is_zero_approx(roll):
		# Preserve the authored local pose exactly, avoiding world/local rounding
		# drift while simply following a moving aircraft or crossing an origin shift.
		camera.global_transform = camera.anchor() * camera.offset
	else:
		camera.move_camera(direction, _look, roll, delta)
		_save_pose()
	if not is_equal_approx(old_fov, camera.fov): _save_pose()
	_look = Vector2.ZERO
	camera.make_current()
	if get_tree().paused:
		var terrain := TerrainReference.get_terrain_node()
		if terrain != null and terrain.has_method("update_paused_camera_stream"):
			terrain.call("update_paused_camera_stream", delta)
	_label.text = "%s · %s\n←/→ vehicle · ↑/↓ view · Space pause/play · AltGr record · Backspace exit\nRMB + mouse/WASD/QE: position · Z/C: roll · Wheel: zoom\nPad: LS move · RS aim/orbit · LB/RB down/up · D-pad ←/→ roll · LT/RT zoom out/in" % [subject.name if is_instance_valid(subject) else "World", VIEW_NAMES[slot]]

func _resolve_focus() -> void:
	_focus_node = subject
	_focus_offset = Vector3(0, 1.0, 0)
	if subject.is_in_group("carrier"):
		var commander := subject.get_node_or_null("Commander") as Node3D
		if commander != null:
			_focus_node = commander
			_focus_offset = Vector3(0, float(commander.get("eye_height_m")) if "eye_height_m" in commander else 1.8, 0)
	else:
		var mount := subject.get_node_or_null("CockpitPilot") as Node3D
		if mount != null:
			_focus_node = mount
			_focus_offset = Vector3(0, 1.2, 0)
			# Sample the head once. Track the seat, not every animated head bob.
			var visual: Node3D = mount.call("get_pilot_visual") if mount.has_method("get_pilot_visual") else null
			if visual != null and "_skeleton" in visual:
				var skeleton := visual.get("_skeleton") as Skeleton3D
				if skeleton != null:
					var head := skeleton.find_bone("head.x")
					if head >= 0: _focus_offset = mount.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(head).origin)
			return
		# Scriptless/legacy fixtures may provide only the cockpit eye marker.
		var cockpit := subject.get_node_or_null("CameraCockpit") as Node3D
		if cockpit != null:
			_focus_node = cockpit
			_focus_offset = Vector3.ZERO

func _present_occupants(vehicle: Node3D) -> void:
	if _presented_subject != null and _presented_subject.get_ref() == vehicle: return
	_release_occupants()
	if not (vehicle.is_in_group("aircraft") or vehicle.is_in_group("ai_aircraft")): return
	var budget := get_node_or_null("/root/EnemyVisualBudget")
	if budget != null:
		budget.set_recording_occupants_active(vehicle, true, &"trailer_camera")
		_presented_subject = weakref(vehicle)

func _release_occupants() -> void:
	var vehicle: Variant = _presented_subject.get_ref() if _presented_subject != null else null
	var budget := get_node_or_null("/root/EnemyVisualBudget")
	if is_instance_valid(vehicle) and budget != null:
		budget.set_recording_occupants_active(vehicle, false, &"trailer_camera")
	_presented_subject = null

func _focus_point() -> Vector3:
	if not is_instance_valid(_focus_node): _resolve_focus()
	var frame := _focus_node.get_global_transform_interpolated() if camera.interpolated_target else _focus_node.global_transform
	return frame * _focus_offset

func _orbit_basis() -> Basis:
	var direction := -_orbit_offset.normalized()
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
	return Basis.looking_at(direction, up)

func _move_anchored(direction: Vector3, look: Vector2, roll: float, delta: float) -> void:
	_orbit_offset = Basis(Vector3.UP, -look.x) * _orbit_offset
	var pitched := Basis(_orbit_basis().x, -look.y) * _orbit_offset
	if absf(pitched.normalized().dot(Vector3.UP)) < 0.995: _orbit_offset = pitched
	var moved: Vector3 = _orbit_offset + _orbit_basis() * direction.limit_length() * camera.move_speed * delta
	if moved.length() >= 0.3: _orbit_offset = moved
	_orbit_roll = wrapf(_orbit_roll + roll * delta, -PI, PI)
	camera.global_transform = Transform3D(_orbit_basis() * Basis(Vector3.BACK, _orbit_roll), _focus_point() + _orbit_offset)
	camera.offset = camera.global_transform

func _clear_pad() -> void:
	_pad_axes.clear()
	_pad_buttons.clear()
	_pad_device = -1

func _on_pad_connection(device: int, connected: bool) -> void:
	if not connected and device == _pad_device: _clear_pad()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_pad()
		_editing = false
		_look = Vector2.ZERO

func _pad_axis(axis: int, deadzone: float = 0.15) -> float:
	var value := float(_pad_axes.get(axis, 0.0))
	return signf(value) * maxf(0.0, (absf(value) - deadzone) / (1.0 - deadzone))

func _pad_motion() -> Dictionary:
	return {
		"move": Vector3(_pad_axis(JOY_AXIS_LEFT_X), float(_pad_buttons.get(JOY_BUTTON_RIGHT_SHOULDER, false)) - float(_pad_buttons.get(JOY_BUTTON_LEFT_SHOULDER, false)), _pad_axis(JOY_AXIS_LEFT_Y)),
		"look": Vector2(_pad_axis(JOY_AXIS_RIGHT_X), _pad_axis(JOY_AXIS_RIGHT_Y)),
		"roll": float(_pad_buttons.get(JOY_BUTTON_DPAD_RIGHT, false)) - float(_pad_buttons.get(JOY_BUTTON_DPAD_LEFT, false)),
		"zoom": maxf(0.0, _pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.05)) - maxf(0.0, _pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.05))}

func _input(event: InputEvent) -> void:
	if RecordingMode.active or PauseMenu.visible or PauseMenu.is_photo_mode_active(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			if key in [KEY_LEFT, KEY_RIGHT]:
				cycle_vehicle(-1 if key == KEY_LEFT else 1)
				get_viewport().set_input_as_handled()
				return
			if key in [KEY_UP, KEY_DOWN]:
				select_slot(posmod(slot + (-1 if key == KEY_UP else 1), view_count()))
				get_viewport().set_input_as_handled()
				return
			if key in [KEY_F1, KEY_F2, KEY_F3]:
				select_slot(int(key - KEY_F1))
				get_viewport().set_input_as_handled()
				return
			if key == KEY_F4:
				cycle_aircraft(-1 if event.shift_pressed else 1)
				get_viewport().set_input_as_handled()
				return
			if (active or piloting) and key == KEY_BACKSPACE:
				release_camera()
				get_viewport().set_input_as_handled()
				return
	if not active: return
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		if event is InputEventJoypadButton and event.button_index not in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]: return
		if _pad_device != event.device:
			_clear_pad()
			_pad_device = event.device
		if event is InputEventJoypadMotion: _pad_axes[event.axis] = event.axis_value
		else: _pad_buttons[event.button_index] = event.pressed
		# Own camera axes/buttons without swallowing the normal pause-menu button.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_editing = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _editing else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.fov = clampf(camera.fov + (-2.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 2.0), 15, 110)
			_save_pose()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _editing: _look += event.relative * 0.002
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_Z, KEY_C, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]: get_viewport().set_input_as_handled()

func is_target_camera_focusing_node(node: Node3D) -> bool:
	return active and is_instance_valid(subject) and node == subject

func apply_origin_shift(offset: Vector3) -> void:
	if active:
		camera.global_position -= offset
		if slot >= FREE: camera.offset.origin -= offset

func _exit_tree() -> void:
	_release_occupants()
	if active:
		_save_pose()
		FlightDirector.trailer_camera_active = false
		Input.mouse_mode = _previous_mouse
