extends Node

## Global Flight Director
## Manages spectator mode, pilot handoff, and tracking all active aircraft.
##
## Controls:
##   LB / RB           - cycle target: Carrier -> Friendly aircraft
##   Y (switch_camera) - cycle cockpit / chase / cinematic for the viewed aircraft
##   Start             - toggle player / AI control for the viewed aircraft
##   Spacebar          - enter free camera / cycle free camera anchor target

enum Category { BRIDGE, FRIENDLY, ENEMY }

var current_category: Category = Category.BRIDGE
var friendly_index: int = 0
var enemy_index: int = 0

## 0 = COCKPIT, 1 = CHASE, 2 = CINEMATIC (maps to CameraController.CameraMode)
var aircraft_cam_mode: int = 0

## The CameraController we last handed control to (used for Y-button view cycling)
var active_controller_camera_system: Node = null

## The aircraft currently being viewed (null when on Carrier)
var current_viewed_aircraft: RigidBody3D = null

## Whether the player has taken manual control of an aircraft
var is_player_controlling: bool = false
var player_controlled_plane: RigidBody3D = null
@export var destroyed_plane_linger_s: float = 5.0
@export var free_camera_max_speed_mps: float = 100.0
@export var free_camera_look_sensitivity_deg: float = 120.0
@export var free_camera_pitch_limit_deg: float = 85.0
@export var enable_audio_debug_logging: bool = false
@export var enable_audio_test_tones: bool = false
@export var audio_debug_interval_s: float = 3.0

var _destroyed_plane_linger_active: bool = false
var _destroyed_plane_linger_until_s: float = 0.0
var _destroyed_plane_linger_camera: Camera3D = null
var _destroyed_plane_linger_aircraft: RigidBody3D = null
var _free_camera_active: bool = false
var _free_camera: Camera3D = null
var _free_camera_yaw: float = 0.0
var _free_camera_pitch: float = 0.0
var _status_overlay_layer: CanvasLayer = null
var _ai_status_label: Label = null
var _pilot_name_label: Label = null
var _ui_visible_aircraft: RigidBody3D = null

# Legacy - kept so AIToggle.register_aircraft still compiles
var active_aircraft: Array[RigidBody3D] = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_setup_status_overlay()
	call_deferred("_initial_view")

func _initial_view():
	_activate_view()

# Legacy registration (AIToggle calls these)

func register_aircraft(ac: RigidBody3D):
	if ac not in active_aircraft:
		active_aircraft.append(ac)
		if not ac.is_connected("destroyed", Callable(self, "_on_aircraft_destroyed").bind(ac)):
			ac.connect("destroyed", Callable(self, "_on_aircraft_destroyed").bind(ac))

func unregister_aircraft(ac: RigidBody3D):
	active_aircraft.erase(ac)
	if ac == player_controlled_plane:
		is_player_controlling = false
		player_controlled_plane = null
	if ac == current_viewed_aircraft:
		current_viewed_aircraft = null
		_activate_view()

func _on_aircraft_destroyed(ac: RigidBody3D):
	var was_viewed := ac == current_viewed_aircraft
	if ac == current_viewed_aircraft:
		current_viewed_aircraft = null
	unregister_aircraft(ac)
	if was_viewed:
		if _free_camera_active:
			_activate_view()
		else:
			_begin_destroyed_plane_linger(ac)

var _audio_debug_timer: float = 0.0
var _audio_test_player: AudioStreamPlayer = null
var _audio_test_started: bool = false
func _process(delta: float) -> void:
	_sync_viewed_aircraft_ui()
	_update_ai_status_overlay()
	_update_pilot_name_overlay()
	if enable_audio_test_tones and not _audio_test_started:
		_audio_test_started = true
		_start_audio_test()
	if enable_audio_debug_logging:
		_audio_debug_timer += delta
		if _audio_debug_timer >= maxf(audio_debug_interval_s, 0.1):
			_audio_debug_timer = 0.0
			_print_audio_debug()
	else:
		_audio_debug_timer = 0.0
	if _free_camera_active:
		_update_free_camera(delta)
	if not _destroyed_plane_linger_active:
		return
	if Time.get_ticks_msec() / 1000.0 < _destroyed_plane_linger_until_s:
		return
	_finish_destroyed_plane_linger()

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		if not _destroyed_plane_linger_active:
			_toggle_free_camera()
		get_viewport().set_input_as_handled()
		return

	if _destroyed_plane_linger_active:
		return

	if _free_camera_active:
		if _is_action_pressed_event(event, "toggle_player_control"):
			_exit_free_camera()
			toggle_player_control()
			get_viewport().set_input_as_handled()
		return

	# Shoulder buttons cycle targets only while spectating.
	if not is_player_controlling:
		if _is_action_pressed_event(event, "spectate_next"):
			cycle_target(1)
			get_viewport().set_input_as_handled()
			return
		elif _is_action_pressed_event(event, "spectate_prev"):
			cycle_target(-1)
			get_viewport().set_input_as_handled()
			return

	if _is_action_pressed_event(event, "switch_camera"):
		_cycle_aircraft_view()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		command_closest_friendly_to_land()
		get_viewport().set_input_as_handled()
		return

	if _is_action_pressed_event(event, "toggle_player_control"):
		toggle_player_control()
		get_viewport().set_input_as_handled()

func _is_action_pressed_event(event: InputEvent, action: StringName) -> bool:
	return event != null and event.is_action_pressed(action, false, true)

func _get_friendly_aircraft() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("friendlies"):
		if node is RigidBody3D and is_instance_valid(node) and _node_has_cameras(node):
			result.append(node)
	return result

func _get_enemy_aircraft() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is RigidBody3D and is_instance_valid(node) and _node_has_cameras(node):
			result.append(node)
	return result

func _node_has_cameras(node: Node) -> bool:
	return node.get_node_or_null("CameraChase") != null \
		or node.get_node_or_null("CameraCockpit") != null \
		or node.find_child("CameraController", true, false) != null

func _has_bridge_camera() -> bool:
	return get_tree().get_nodes_in_group("carrier_cam").size() > 0

## Advance or retreat through Carrier -> Friendly[0..n] -> Carrier ...
func cycle_target(direction: int):
	var friendlies := _get_friendly_aircraft()
	var has_bridge := _has_bridge_camera()

	var slots: Array = []
	if has_bridge:
		slots.append({"cat": Category.BRIDGE, "idx": -1})
	for i in range(friendlies.size()):
		slots.append({"cat": Category.FRIENDLY, "idx": i})

	if slots.is_empty():
		return

	var cur := 0
	for i in range(slots.size()):
		var s = slots[i]
		if s.cat == current_category:
			if s.cat == Category.BRIDGE:
				cur = i
				break
			elif s.cat == Category.FRIENDLY and s.idx == friendly_index:
				cur = i
				break

	cur = (cur + direction + slots.size()) % slots.size()
	var next = slots[cur]

	current_category = next.cat
	if current_category == Category.FRIENDLY:
		friendly_index = clampi(next.idx, 0, friendlies.size() - 1)

	# Reset to cockpit when switching aircraft targets.
	aircraft_cam_mode = 0
	_activate_view()

func _cycle_aircraft_view():
	if current_category == Category.BRIDGE:
		return
	aircraft_cam_mode = (aircraft_cam_mode + 1) % 3
	_activate_view()

func _activate_view():
	if _free_camera_active:
		_sync_view_target_for_free_camera()
		return

	var cc := _get_player_camera_controller()

	match current_category:
		Category.BRIDGE:
			current_viewed_aircraft = null
			if cc and cc.has_method("switch_to_camera"):
				cc.switch_to_camera(3)
				active_controller_camera_system = cc

		Category.FRIENDLY:
			var friendlies := _get_friendly_aircraft()
			if friendlies.is_empty():
				current_category = Category.BRIDGE
				_activate_view()
				return
			friendly_index = clampi(friendly_index, 0, friendlies.size() - 1)
			var ac := friendlies[friendly_index] as RigidBody3D
			_view_aircraft(ac)

		Category.ENEMY:
			current_category = Category.BRIDGE
			_activate_view()
			return

func _sync_view_target_for_free_camera() -> void:
	match current_category:
		Category.BRIDGE:
			current_viewed_aircraft = null

		Category.FRIENDLY:
			var friendlies := _get_friendly_aircraft()
			if friendlies.is_empty():
				current_category = Category.BRIDGE
				current_viewed_aircraft = null
				return
			friendly_index = clampi(friendly_index, 0, friendlies.size() - 1)
			current_viewed_aircraft = friendlies[friendly_index] as RigidBody3D

		Category.ENEMY:
			current_category = Category.BRIDGE
			current_viewed_aircraft = null

func _view_aircraft(ac: RigidBody3D):
	current_viewed_aircraft = ac

	# FlightDeckManager disables these on AI aircraft. Re-enable them for viewing.
	_set_aircraft_view_ui_enabled(ac, true)

	var ac_cc := ac.find_child("CameraController", true, false) as Node
	if ac_cc and ac_cc.has_method("switch_to_camera"):
		ac_cc.switch_to_camera(aircraft_cam_mode)
		active_controller_camera_system = ac_cc
		return

	var player_cc := _get_player_camera_controller()
	if player_cc and player_cc.has_method("switch_to_aircraft_and_mode"):
		player_cc.switch_to_aircraft_and_mode(ac, aircraft_cam_mode)
		active_controller_camera_system = player_cc
	elif player_cc and player_cc.has_method("switch_to_camera"):
		player_cc.switch_to_camera(aircraft_cam_mode)
		active_controller_camera_system = player_cc

func _get_player_camera_controller() -> Node:
	var ccs := get_tree().get_nodes_in_group("camera_controller")
	if ccs.size() > 0:
		return ccs[0]
	return null

func toggle_player_control():
	if is_player_controlling:
		_return_control_to_ai()
		return

	var target := _get_toggle_target_aircraft()
	if not is_instance_valid(target):
		return

	var friendlies := _get_friendly_aircraft()
	var target_index := friendlies.find(target)
	if target_index == -1:
		return

	current_category = Category.FRIENDLY
	friendly_index = target_index
	current_viewed_aircraft = target
	_activate_view()

	var ai_toggle = target.get_node_or_null("AIToggle")
	if ai_toggle and ai_toggle.has_method("disable_ai"):
		ai_toggle.disable_ai()

	is_player_controlling = true
	player_controlled_plane = target
	print("[FlightDirector] Player took control of: ", target.name)

func _return_control_to_ai() -> void:
	# Returning to spectator mode must not change focus or camera mode.
	if is_instance_valid(player_controlled_plane):
		var ai_toggle = player_controlled_plane.get_node_or_null("AIToggle")
		if ai_toggle and ai_toggle.has_method("enable_ai"):
			ai_toggle.enable_ai()
		print("[FlightDirector] Returned control to AI: ", player_controlled_plane.name)
	is_player_controlling = false
	player_controlled_plane = null

func _get_toggle_target_aircraft() -> RigidBody3D:
	if is_instance_valid(player_controlled_plane):
		return player_controlled_plane
	if not is_instance_valid(current_viewed_aircraft):
		return null
	var friendlies := _get_friendly_aircraft()
	if current_viewed_aircraft in friendlies:
		return current_viewed_aircraft
	return null

func _setup_status_overlay() -> void:
	if _status_overlay_layer != null:
		return
	_status_overlay_layer = CanvasLayer.new()
	_status_overlay_layer.name = "FlightDirectorOverlay"
	_status_overlay_layer.layer = 100
	add_child(_status_overlay_layer)

	_ai_status_label = Label.new()
	_ai_status_label.name = "AIStatusLabel"
	_ai_status_label.text = "AI"
	_ai_status_label.visible = false
	_ai_status_label.anchor_left = 0.5
	_ai_status_label.anchor_right = 0.5
	_ai_status_label.anchor_top = 1.0
	_ai_status_label.anchor_bottom = 1.0
	_ai_status_label.offset_left = -60.0
	_ai_status_label.offset_right = 60.0
	_ai_status_label.offset_top = -48.0
	_ai_status_label.offset_bottom = -18.0
	_ai_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ai_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ai_status_label.add_theme_font_size_override("font_size", 24)
	_ai_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 1.0))
	_ai_status_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_ai_status_label.add_theme_constant_override("outline_size", 3)
	_status_overlay_layer.add_child(_ai_status_label)

	_pilot_name_label = Label.new()
	_pilot_name_label.name = "PilotNameLabel"
	_pilot_name_label.text = ""
	_pilot_name_label.visible = false
	_pilot_name_label.anchor_left = 0.5
	_pilot_name_label.anchor_right = 0.5
	_pilot_name_label.anchor_top = 1.0
	_pilot_name_label.anchor_bottom = 1.0
	_pilot_name_label.offset_left = -260.0
	_pilot_name_label.offset_right = 260.0
	_pilot_name_label.offset_top = -78.0
	_pilot_name_label.offset_bottom = -46.0
	_pilot_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pilot_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pilot_name_label.add_theme_font_size_override("font_size", 20)
	_pilot_name_label.add_theme_color_override("font_color", Color(0.88, 1.0, 0.88, 1.0))
	_pilot_name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_pilot_name_label.add_theme_constant_override("outline_size", 3)
	_status_overlay_layer.add_child(_pilot_name_label)

func _update_ai_status_overlay() -> void:
	if _ai_status_label == null:
		return
	var show_ai := not _free_camera_active and is_instance_valid(current_viewed_aircraft) and _is_aircraft_ai_controlled(current_viewed_aircraft)
	_ai_status_label.visible = show_ai

func _update_pilot_name_overlay() -> void:
	if _pilot_name_label == null:
		return

	var show_label := false
	var display_text := ""

	if not _free_camera_active and not _destroyed_plane_linger_active:
		var active_camera := _get_current_active_camera()
		var camera_aircraft := _get_aircraft_for_camera(active_camera)
		if is_instance_valid(camera_aircraft) and _camera_is_in_cockpit_mount(active_camera):
			display_text = _pilot_display_from_aircraft(camera_aircraft)
			show_label = display_text != ""

	_pilot_name_label.visible = show_label
	if show_label:
		_pilot_name_label.text = display_text

func _camera_is_in_cockpit_mount(camera: Camera3D) -> bool:
	if not is_instance_valid(camera):
		return false
	var node: Node = camera
	while node != null:
		if node.name == "CameraCockpit":
			return true
		node = node.get_parent()
	return false

func _get_aircraft_for_camera(camera: Camera3D) -> RigidBody3D:
	if not is_instance_valid(camera):
		return null
	var node: Node = camera
	while node != null:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null

func _pilot_display_from_aircraft(aircraft: RigidBody3D) -> String:
	if not is_instance_valid(aircraft):
		return ""
	if aircraft.has_meta("pilot_display_name"):
		return str(aircraft.get_meta("pilot_display_name"))
	var rank := str(aircraft.get_meta("pilot_rank", ""))
	var callsign := str(aircraft.get_meta("pilot_callsign", ""))
	var surname := str(aircraft.get_meta("pilot_name", ""))
	if rank == "" and callsign == "" and surname == "":
		return ""
	return "%s \"%s\" %s" % [rank, callsign, surname]

func _is_aircraft_ai_controlled(ac: RigidBody3D) -> bool:
	if not is_instance_valid(ac):
		return false
	var ai_toggle := ac.get_node_or_null("AIToggle")
	if ai_toggle == null:
		return false
	if "ai_active" in ai_toggle:
		return bool(ai_toggle.ai_active)
	return false

func _sync_viewed_aircraft_ui() -> void:
	var desired_aircraft: RigidBody3D = null
	if not _free_camera_active and is_instance_valid(current_viewed_aircraft):
		desired_aircraft = current_viewed_aircraft

	if _ui_visible_aircraft != desired_aircraft:
		if is_instance_valid(_ui_visible_aircraft):
			_set_aircraft_view_ui_enabled(_ui_visible_aircraft, false)
		_ui_visible_aircraft = desired_aircraft

	if is_instance_valid(_ui_visible_aircraft):
		_set_aircraft_view_ui_enabled(_ui_visible_aircraft, true)

func _set_aircraft_view_ui_enabled(ac: RigidBody3D, enabled: bool) -> void:
	if not is_instance_valid(ac):
		return
	for node_name in ["CameraController", "HeadsUpDisplay", "InstrumentPanel"]:
		var node := ac.find_child(node_name, true, false) as Node
		if node == null:
			continue
		node.set_process(enabled)
		node.set_physics_process(enabled)
		node.set_process_input(enabled)
		if node is CanvasItem:
			(node as CanvasItem).visible = enabled
		elif node is Node3D:
			(node as Node3D).visible = enabled

func _find_closest_friendly_aircraft() -> RigidBody3D:
	var friendlies := _get_friendly_aircraft()
	if friendlies.is_empty():
		return null

	if is_instance_valid(current_viewed_aircraft) and current_viewed_aircraft in friendlies:
		return current_viewed_aircraft

	var reference_position := _get_focus_position()
	var best_aircraft: RigidBody3D = friendlies[0] as RigidBody3D
	var best_distance := INF

	for node in friendlies:
		var ac := node as RigidBody3D
		if not is_instance_valid(ac):
			continue
		var distance := ac.global_position.distance_squared_to(reference_position)
		if distance < best_distance:
			best_distance = distance
			best_aircraft = ac

	return best_aircraft

func command_closest_friendly_to_land() -> void:
	var target := _find_closest_friendly_aircraft_to_carrier()
	if not is_instance_valid(target):
		print("[FlightDirector] L: no eligible friendly aircraft available for landing command")
		return

	var ai_toggle = target.get_node_or_null("AIToggle")
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()

	var ai_pilot = target.find_child("AIPilot", true, false)
	if not ai_pilot or not ai_pilot.has_method("start_landing"):
		print("[FlightDirector] L: no AIPilot found on ", target.name)
		return

	var ok: bool = ai_pilot.start_landing()
	if ok:
		print("[FlightDirector] L: landing commanded for ", target.name)
	else:
		print("[FlightDirector] L: approach waypoints not found for ", target.name)

func _is_aircraft_in_landing_flow(aircraft: RigidBody3D) -> bool:
	var ai_pilot := aircraft.find_child("AIPilot", true, false) as AIPilot
	if ai_pilot == null:
		return false
	return ai_pilot.current_state in [AIPilot.State.APPROACH, AIPilot.State.LANDING, AIPilot.State.MISSED_APPROACH]

func _find_closest_friendly_aircraft_to_carrier() -> RigidBody3D:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		return null

	var best_aircraft: RigidBody3D = null
	var best_distance := INF

	for node in _get_friendly_aircraft():
		var aircraft := node as RigidBody3D
		if not is_instance_valid(aircraft):
			continue
		if aircraft.get_meta("carrier_transport_mode", false):
			continue
		if aircraft.get_meta("parking_brake", false):
			continue
		if aircraft.get_meta("arresting_engaged", false):
			continue
		if _is_aircraft_in_landing_flow(aircraft):
			continue
		var ai_pilot = aircraft.find_child("AIPilot", true, false)
		if not ai_pilot or not ai_pilot.has_method("start_landing"):
			continue
		var distance := aircraft.global_position.distance_squared_to(carrier.global_position)
		if distance < best_distance:
			best_distance = distance
			best_aircraft = aircraft

	return best_aircraft

func _get_focus_position() -> Vector3:
	if _free_camera_active and is_instance_valid(_free_camera):
		return _free_camera.global_position

	if is_instance_valid(current_viewed_aircraft):
		return current_viewed_aircraft.global_position

	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier:
		return carrier.global_position

	var cc := _get_player_camera_controller()
	if cc and cc.has_method("get_current_camera"):
		var cam = cc.get_current_camera()
		if cam and cam is Camera3D:
			return (cam as Camera3D).global_position

	return Vector3.ZERO

func is_destroyed_plane_linger_active() -> bool:
	return _destroyed_plane_linger_active

func _begin_destroyed_plane_linger(ac: RigidBody3D) -> void:
	_cleanup_destroyed_plane_linger_camera()
	var source_camera: Camera3D = _get_aircraft_camera(ac, "CameraChase")
	if source_camera == null:
		source_camera = _get_current_active_camera()
	if source_camera == null:
		return

	var linger_camera: Camera3D = Camera3D.new()
	linger_camera.name = "DestroyedPlaneLingerCamera"
	linger_camera.global_transform = source_camera.global_transform
	linger_camera.fov = source_camera.fov
	linger_camera.near = source_camera.near
	linger_camera.far = source_camera.far
	linger_camera.keep_aspect = source_camera.keep_aspect
	linger_camera.projection = source_camera.projection
	get_tree().current_scene.add_child(linger_camera)
	_force_current_camera(linger_camera)

	_destroyed_plane_linger_camera = linger_camera
	_destroyed_plane_linger_aircraft = ac
	_destroyed_plane_linger_active = true
	_destroyed_plane_linger_until_s = Time.get_ticks_msec() / 1000.0 + maxf(destroyed_plane_linger_s, 0.1)

func _finish_destroyed_plane_linger() -> void:
	_cleanup_destroyed_plane_linger_camera()
	_destroyed_plane_linger_active = false
	_destroyed_plane_linger_until_s = 0.0
	_destroyed_plane_linger_aircraft = null
	_activate_view()

func _cleanup_destroyed_plane_linger_camera() -> void:
	if is_instance_valid(_destroyed_plane_linger_camera):
		_destroyed_plane_linger_camera.queue_free()
	_destroyed_plane_linger_camera = null

func _get_aircraft_camera(ac: RigidBody3D, tripod_name: String) -> Camera3D:
	if not is_instance_valid(ac):
		return null
	var camera := ac.get_node_or_null(tripod_name + "/Camera3D") as Camera3D
	if camera:
		return camera
	var tripod := ac.get_node_or_null(tripod_name) as Node3D
	if tripod:
		return tripod.find_child("Camera3D", true, false) as Camera3D
	return null

func _get_current_active_camera() -> Camera3D:
	if _free_camera_active and is_instance_valid(_free_camera) and _free_camera.current:
		return _free_camera

	var bridge_cam := _get_bridge_camera()
	if bridge_cam and bridge_cam.current:
		return bridge_cam

	for node in get_tree().get_nodes_in_group("camera_controller"):
		if node and node.has_method("get_current_camera"):
			var cam: Camera3D = node.get_current_camera()
			if cam and cam is Camera3D:
				return cam as Camera3D

	if is_instance_valid(current_viewed_aircraft):
		for tripod_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
			var cam: Camera3D = _get_aircraft_camera(current_viewed_aircraft, tripod_name)
			if cam and cam.current:
				return cam

	var viewport := get_viewport()
	if viewport:
		var viewport_camera := viewport.get_camera_3d()
		if viewport_camera and viewport_camera is Camera3D:
			return viewport_camera as Camera3D
	return null

func _toggle_free_camera() -> void:
	if _free_camera_active:
		_exit_free_camera()
		return

	_enter_free_camera()

func _enter_free_camera() -> void:
	if is_player_controlling:
		_return_control_to_ai()

	var source_camera: Camera3D = _get_current_active_camera()
	var free_camera := _get_or_create_free_camera()
	if source_camera:
		free_camera.global_transform = source_camera.global_transform
		free_camera.fov = source_camera.fov
		free_camera.near = source_camera.near
		free_camera.far = source_camera.far
		free_camera.keep_aspect = source_camera.keep_aspect
		free_camera.projection = source_camera.projection
	else:
		free_camera.global_position = _get_focus_position() + Vector3(0.0, 20.0, 0.0)

	_free_camera = free_camera
	_free_camera_active = true
	_sync_free_camera_angles()
	_force_current_camera(_free_camera)

func _exit_free_camera() -> void:
	if not _free_camera_active:
		return

	_free_camera_active = false
	if is_instance_valid(_free_camera):
		_free_camera.current = false
	_activate_view()

func _get_or_create_free_camera() -> Camera3D:
	if is_instance_valid(_free_camera):
		return _free_camera

	var camera := Camera3D.new()
	camera.name = "FreeCamera"
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else self
	parent.add_child(camera)
	_free_camera = camera
	return camera

func _update_free_camera(delta: float) -> void:
	if not is_instance_valid(_free_camera):
		_free_camera_active = false
		return

	var look_yaw_input := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	var look_pitch_input := Input.get_action_strength("look_up") - Input.get_action_strength("look_down")
	_free_camera_yaw -= look_yaw_input * deg_to_rad(free_camera_look_sensitivity_deg) * delta
	_free_camera_pitch += look_pitch_input * deg_to_rad(free_camera_look_sensitivity_deg) * delta
	_free_camera_pitch = clamp(
		_free_camera_pitch,
		deg_to_rad(-free_camera_pitch_limit_deg),
		deg_to_rad(free_camera_pitch_limit_deg)
	)
	_free_camera.rotation = Vector3(_free_camera_pitch, _free_camera_yaw, 0.0)

	var forward_input := Input.get_action_strength("pitch_down") - Input.get_action_strength("pitch_up")
	var strafe_input := Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")
	var move_input := Vector2(strafe_input, forward_input)
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()

	var move_vector := (_free_camera.global_basis.x * move_input.x) + ((-_free_camera.global_basis.z) * move_input.y)
	_free_camera.global_position += move_vector * free_camera_max_speed_mps * delta

func _snap_free_camera_to_target() -> void:
	if not _free_camera_active or not is_instance_valid(_free_camera):
		return

	var source_camera := _get_free_camera_anchor_camera()
	if source_camera:
		_free_camera.global_transform = source_camera.global_transform
	else:
		_free_camera.global_position = _get_focus_position() + Vector3(0.0, 20.0, 0.0)
	_force_current_camera(_free_camera)
	_sync_free_camera_angles()

func _force_current_camera(camera: Camera3D) -> void:
	if not is_instance_valid(camera):
		return

	var viewport := get_viewport()
	if viewport:
		viewport.audio_listener_enable_3d = true
		var previous_camera := viewport.get_camera_3d()
		if previous_camera and previous_camera != camera:
			previous_camera.current = false

	# A straight current=true toggle has been unreliable for 3D audio listener
	# handoff in this project, so force a clean transition now and next frame.
	camera.current = false
	camera.current = true
	call_deferred("_force_current_camera_deferred", camera)

func _force_current_camera_deferred(camera: Camera3D) -> void:
	if not is_instance_valid(camera):
		return
	if camera == _free_camera and not _free_camera_active:
		return
	if camera == _destroyed_plane_linger_camera and not _destroyed_plane_linger_active:
		return

	var viewport := get_viewport()
	if viewport:
		viewport.audio_listener_enable_3d = true

	camera.current = false
	camera.current = true

func _get_free_camera_anchor_camera() -> Camera3D:
	if current_category == Category.BRIDGE:
		return _get_bridge_camera()

	if not is_instance_valid(current_viewed_aircraft):
		return null

	for tripod_name in ["CameraChase", "CameraCockpit", "CameraCinematic"]:
		var cam := _get_aircraft_camera(current_viewed_aircraft, tripod_name)
		if cam:
			return cam

	return null

func _sync_free_camera_angles() -> void:
	if not is_instance_valid(_free_camera):
		return

	var camera_rotation: Vector3 = _free_camera.global_rotation
	_free_camera_pitch = clamp(
		camera_rotation.x,
		deg_to_rad(-free_camera_pitch_limit_deg),
		deg_to_rad(free_camera_pitch_limit_deg)
	)
	_free_camera_yaw = camera_rotation.y
	_free_camera.rotation = Vector3(_free_camera_pitch, _free_camera_yaw, 0.0)

func _get_bridge_camera() -> Camera3D:
	for node in get_tree().get_nodes_in_group("carrier_cam"):
		if node != null and node.has_method("get_camera"):
			var cam = node.call("get_camera")
			if cam is Camera3D:
				return cam as Camera3D
	return null

func _print_audio_debug() -> void:
	var vp = get_viewport()
	var cam = vp.get_camera_3d() if vp else null
	var cam_name = cam.name if cam else "NONE"
	var cam_pos = cam.global_position if cam else Vector3.ZERO
	var audio_players_3d = get_tree().get_nodes_in_group("3d_audio")
	var bus_count = AudioServer.bus_count
	var bus_names: Array[String] = []
	for i in range(bus_count):
		var muted = AudioServer.is_bus_mute(i)
		var vol = AudioServer.get_bus_volume_db(i)
		bus_names.append("%s(vol=%.1f%s)" % [AudioServer.get_bus_name(i), vol, " MUTED" if muted else ""])
	print("=== AUDIO DEBUG ===")
	print("  Active camera: %s at %s (current=%s)" % [cam_name, str(cam_pos), str(cam.current) if cam else "N/A"])
	if cam:
		print("  Camera tree path: %s" % cam.get_path())
	print("  Viewport audio_listener_enable_3d: %s" % str(vp.audio_listener_enable_3d) if vp else "NO VP")
	# Check for AudioListener3D nodes that might override camera
	var listeners = []
	for node in get_tree().get_nodes_in_group(""):
		pass  # Can't iterate all nodes easily
	var listener_nodes := _find_nodes_of_type(get_tree().root, "AudioListener3D")
	print("  AudioListener3D nodes in scene: %d %s" % [listener_nodes.size(), str(listener_nodes)])
	print("  Audio buses: %s" % str(bus_names))
	print("  AudioServer output device: %s" % AudioServer.output_device)
	print("  3d_audio group members: %d" % audio_players_3d.size())
	# Print named players only (skip anonymous @AudioStreamPlayer3D@xxx)
	for player in audio_players_3d:
		if player is AudioStreamPlayer3D:
			var p := player as AudioStreamPlayer3D
			if p.name.begins_with("@"):
				continue
			var dist = cam_pos.distance_to(p.global_position) if cam else -1.0
			var stream_info := "null"
			if p.stream:
				var s = p.stream
				stream_info = "%s len=%.2f" % [s.get_class(), s.get_length()]
				if s is AudioStreamWAV:
					var wav := s as AudioStreamWAV
					stream_info += " fmt=%d rate=%d loop=%d stereo=%s data=%d" % [wav.format, wav.mix_rate, wav.loop_mode, wav.stereo, wav.data.size()]
			# Try force-play if not playing
			if not p.playing:
				p.play()
			print("    %s: bus=%s vol=%.1f playing=%s after_force_play=%s stream=[%s] dist=%.0f" % [p.name, p.bus, p.volume_db, p.playing, p.playing, stream_info, dist])

func _start_audio_test() -> void:
	# Test A: known-working sound (propeller)
	var test_a = load("res://Audio/airplane_propeller 1.wav")
	# Test B: carrier deck sound (not working)
	var test_b = load("res://Audio/Carrier/carrier_deck_sound.wav")

	if test_a:
		var player_a = AudioStreamPlayer.new()
		player_a.name = "AudioTestA_propeller"
		player_a.stream = test_a
		player_a.bus = "Master"
		player_a.volume_db = -10.0
		add_child(player_a)
		player_a.play()
		print("[AUDIO TEST A] propeller: class=%s len=%.2f playing=%s" % [test_a.get_class(), test_a.get_length(), player_a.playing])
	else:
		print("[AUDIO TEST A] FAILED to load propeller wav")

	if test_b:
		var player_b = AudioStreamPlayer.new()
		player_b.name = "AudioTestB_deck"
		player_b.stream = test_b
		player_b.bus = "Master"
		player_b.volume_db = -5.0
		add_child(player_b)
		player_b.play()
		print("[AUDIO TEST B] deck: class=%s len=%.2f playing=%s" % [test_b.get_class(), test_b.get_length(), player_b.playing])
	else:
		print("[AUDIO TEST B] FAILED to load deck wav")

func _find_nodes_of_type(node: Node, type_name: String) -> Array[String]:
	var result: Array[String] = []
	if node.get_class() == type_name:
		result.append(str(node.get_path()))
	for child in node.get_children():
		result.append_array(_find_nodes_of_type(child, type_name))
	return result
