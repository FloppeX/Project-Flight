extends Node

const AirTaskModel: Script = preload("res://AI/AirTask.gd")
const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

## Global Flight Director
## Manages spectator mode, pilot handoff, and tracking all active aircraft.
##
## Controls:
##   LB / RB           - cycle target: Carrier -> Friendly aircraft
##   Y (switch_camera) - cycle cockpit / chase / cinematic for the viewed aircraft
##   Start             - toggle player / AI control for the viewed aircraft
##   Spacebar          - enter free camera / cycle free camera anchor target
##   W                 - place a wind turbine at the free camera position

enum Category { BRIDGE, FRIENDLY, ENEMY }
enum AircraftTransitionPhase { NONE, EGRESS, TRANSFER, WAITING_FOR_PRESENTATION, ARRIVAL }

const WIND_TURBINE_SCENE: PackedScene = preload("res://Buildings/building_wind_turbine.tscn")

var current_category: Category = Category.BRIDGE
var friendly_index: int = 0
var enemy_index: int = 0

## 0 = COCKPIT, 1 = CHASE, 2 = CINEMATIC (maps to CameraController.CameraMode)
var aircraft_cam_mode: int = 0
## 0 = control room, 1 = carrier chase, 2 = carrier cinematic
var carrier_cam_mode: int = 0

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
@export var bridge_free_camera_rear_distance_m: float = 2.5
@export var bridge_free_camera_above_focus_m: float = 1.25
@export var bridge_free_camera_focus_height_m: float = 1.05
@export var enable_audio_debug_logging: bool = false
@export var enable_audio_test_tones: bool = false
@export var audio_debug_interval_s: float = 3.0
@export_group("Aircraft View Transition")
@export var aircraft_view_transition_enabled: bool = true
@export_range(0.1, 1.5, 0.05) var aircraft_transition_egress_s: float = 0.50
@export_range(0.1, 1.5, 0.05) var aircraft_transition_arrival_s: float = 0.70
@export_range(0.1, 2.0, 0.05) var aircraft_transition_min_transfer_s: float = 0.70
@export_range(0.5, 5.0, 0.05) var aircraft_transition_max_transfer_s: float = 3.40
@export_range(100.0, 100000.0, 100.0) var aircraft_transition_full_duration_distance_m: float = 15000.0
@export_range(1.0, 30.0, 0.5) var aircraft_transition_gate_behind_m: float = 7.0
@export_range(0.5, 15.0, 0.25) var aircraft_transition_gate_above_m: float = 3.0
@export_range(0.25, 5.0, 0.25) var aircraft_transition_canopy_clearance_m: float = 1.5
@export_range(1.0, 30.0, 0.5) var helicopter_transition_gate_ahead_m: float = 10.0
@export_range(0.5, 15.0, 0.25) var helicopter_transition_gate_above_m: float = 4.0
@export_range(0.25, 8.0, 0.25) var helicopter_transition_clearance_m: float = 2.5
@export_range(0.0, 25.0, 0.5) var aircraft_transition_max_fov_boost_deg: float = 8.0
@export_group("")

var _destroyed_plane_linger_active: bool = false
var _destroyed_plane_linger_until_s: float = 0.0
var _destroyed_plane_linger_camera: Camera3D = null
var _destroyed_plane_linger_aircraft: RigidBody3D = null
var _free_camera_active: bool = false
var _free_camera: Camera3D = null
var _free_camera_yaw: float = 0.0
var _free_camera_pitch: float = 0.0
var _photo_mode_camera_active: bool = false
var _photo_mode_started_free_camera: bool = false
var _status_overlay_layer: CanvasLayer = null
var _ai_status_label: Label = null
var _pilot_name_label: Label = null
var _ui_visible_aircraft: RigidBody3D = null
var _aircraft_transition_active: bool = false
var _aircraft_transition_phase: AircraftTransitionPhase = AircraftTransitionPhase.NONE
var _aircraft_transition_camera: Camera3D = null
var _aircraft_transition_source: RigidBody3D = null
var _aircraft_transition_target: RigidBody3D = null
var _aircraft_transition_source_endpoint: Node3D = null
var _aircraft_transition_target_endpoint: Node3D = null
var _aircraft_transition_source_category: Category = Category.BRIDGE
var _aircraft_transition_target_category: Category = Category.FRIENDLY
var _aircraft_transition_source_camera: Camera3D = null
var _aircraft_transition_bridge_camera: Camera3D = null
var _aircraft_transition_phase_elapsed_s: float = 0.0
var _aircraft_transition_transfer_duration_s: float = 0.0
var _aircraft_transition_transfer_distance_m: float = 0.0
var _aircraft_transition_source_start_local: Transform3D = Transform3D.IDENTITY
var _aircraft_transition_transfer_start: Transform3D = Transform3D.IDENTITY
var _aircraft_transition_arrival_start_local: Transform3D = Transform3D.IDENTITY
var _aircraft_transition_base_fov: float = 75.0
var _aircraft_transition_presentation_complete: bool = true

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
		if ac.has_signal("destroyed") and not ac.is_connected("destroyed", Callable(self, "_on_aircraft_destroyed").bind(ac)):
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
	if _aircraft_camera_was_replaced(ac):
		active_aircraft.erase(ac)
		if ac == player_controlled_plane:
			is_player_controlling = false
			player_controlled_plane = null
		if ac == current_viewed_aircraft:
			var replacement := _get_ejected_pilot_replacement(ac)
			current_viewed_aircraft = replacement
			if is_instance_valid(replacement):
				current_category = Category.FRIENDLY
				_select_friendly_index_for(replacement)
				_activate_view()
		return

	var was_viewed := ac == current_viewed_aircraft
	if ac == current_viewed_aircraft:
		current_viewed_aircraft = null
	unregister_aircraft(ac)
	if was_viewed:
		if _free_camera_active:
			_activate_view()
		else:
			_begin_destroyed_plane_linger(ac)

func replace_aircraft_with_ejected_pilot(old_aircraft: RigidBody3D, ejected_body: RigidBody3D) -> void:
	if not is_instance_valid(ejected_body):
		return
	ejected_body.add_to_group("ejected_pilots")
	ejected_body.set_meta("ejected_pilot_camera_target", true)
	ejected_body.set_meta("player_control_locked", true)
	register_aircraft(ejected_body)

	if is_instance_valid(old_aircraft):
		active_aircraft.erase(old_aircraft)
		old_aircraft.set_meta("camera_abandoned", true)
		old_aircraft.set_meta("camera_replaced_by_ejected_pilot", true)
		old_aircraft.set_meta("ejected_pilot_body", ejected_body.get_path())

	is_player_controlling = false
	if player_controlled_plane == old_aircraft:
		player_controlled_plane = null

	current_category = Category.FRIENDLY
	current_viewed_aircraft = ejected_body
	_select_friendly_index_for(ejected_body)
	aircraft_cam_mode = 0
	_destroyed_plane_linger_active = false
	_cleanup_destroyed_plane_linger_camera()
	_activate_view()


func retire_aircraft_after_ejection(old_aircraft: RigidBody3D) -> void:
	if not is_instance_valid(old_aircraft):
		return
	active_aircraft.erase(old_aircraft)
	if player_controlled_plane == old_aircraft:
		is_player_controlling = false
		player_controlled_plane = null
	if current_viewed_aircraft != old_aircraft:
		return

	var replacement := _get_ejected_pilot_replacement(old_aircraft)
	current_viewed_aircraft = replacement
	if is_instance_valid(replacement):
		current_category = Category.FRIENDLY
		_select_friendly_index_for(replacement)
	_activate_view()

var _audio_debug_timer: float = 0.0
var _audio_test_player: AudioStreamPlayer = null
var _audio_test_started: bool = false
func _process(delta: float) -> void:
	_update_aircraft_camera_transition(delta)
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
	if not _destroyed_plane_linger_active:
		return
	if Time.get_ticks_msec() / 1000.0 < _destroyed_plane_linger_until_s:
		return
	_finish_destroyed_plane_linger()

func _physics_process(delta: float) -> void:
	if _free_camera_active:
		_update_free_camera(delta)

func _input(event):
	# Photo mode owns the face buttons while this camera remains available for
	# continuous stick input in _physics_process().
	if _photo_mode_camera_active:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		if _aircraft_transition_active:
			get_viewport().set_input_as_handled()
			return
		if not _destroyed_plane_linger_active:
			_toggle_free_camera()
		get_viewport().set_input_as_handled()
		return

	# Space is the sole direct gameplay key handled here. All other keyboard
	# controls must be assigned through the Input Map.
	if event is InputEventKey:
		return

	if _destroyed_plane_linger_active:
		# Any view-cycling or camera input cancels the linger so the player
		# isn't forced to watch the explosion to completion.
		var cancels := false
		if event is InputEventJoypadButton and event.pressed:
			var btn := (event as InputEventJoypadButton).button_index
			# LB=9 / RB=10 (cycle viewed unit) or Y=3/Triangle (cycle camera mode)
			cancels = btn in [9, 10, 3]
		if _is_action_pressed_event(event, "cycle_camera_mode"):
			cancels = true
		if cancels:
			_finish_destroyed_plane_linger()
			# Don't return — let the input fall through to normal handling below
		else:
			return

	# Target cycling may retarget a transition already in flight. Camera-mode and
	# possession changes wait for the short handoff to finish so they cannot make
	# the temporary camera select or control the source aircraft by accident.
	if _aircraft_transition_active:
		if not is_player_controlling:
			if _is_action_pressed_event(event, "spectate_next"):
				cycle_target(1)
				get_viewport().set_input_as_handled()
				return
			elif _is_action_pressed_event(event, "spectate_prev"):
				cycle_target(-1)
				get_viewport().set_input_as_handled()
				return
		if _is_action_pressed_event(event, "switch_camera") \
		or _is_action_pressed_event(event, "toggle_player_control"):
			get_viewport().set_input_as_handled()
			return

	if _free_camera_active:
		if _is_action_pressed_event(event, "change_weapon"):
			_spawn_debug_exploded_aircraft5()
			get_viewport().set_input_as_handled()
			return
		if _is_action_pressed_event(event, "toggle_player_control"):
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

	if _is_action_pressed_event(event, "toggle_player_control"):
		toggle_player_control()
		get_viewport().set_input_as_handled()

func _is_action_pressed_event(event: InputEvent, action: StringName) -> bool:
	# Some optional/test actions are not present in the shipping InputMap. Godot
	# logs an error every time is_action_pressed() receives a missing action, so a
	# held stick could otherwise turn one harmless compatibility check into a
	# high-volume error stream.
	return event != null and InputMap.has_action(action) \
		and event.is_action_pressed(action, false, true)

func _is_refill_ordnance_key_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	return key_event.unicode == 229 or key_event.unicode == 197

func _refill_player_plane_ordnance() -> bool:
	if not is_instance_valid(player_controlled_plane):
		return false

	var control_weapons := player_controlled_plane.find_child("ControlWeapons", true, false) as ControlWeapons
	if control_weapons == null:
		return false

	control_weapons.find_hardpoints()
	var previous_weapon_type: String = control_weapons.selected_weapon_type
	var refilled_any: bool = false

	for hardpoint in control_weapons.hardpoints:
		if not is_instance_valid(hardpoint):
			continue
		if hardpoint.mounted_weapon == null:
			continue
		var weapon := hardpoint.weapon_instance
		if weapon == null:
			continue
		if weapon is BombRack or weapon is BombHolder or weapon is RocketPod:
			hardpoint.mount_weapon_from_scene(hardpoint.mounted_weapon)
			refilled_any = true

	if not refilled_any:
		return false

	control_weapons.find_hardpoints()
	control_weapons.categorize_weapons()

	if previous_weapon_type != "" and control_weapons.weapon_types.has(previous_weapon_type):
		control_weapons.selected_weapon_type = previous_weapon_type
		control_weapons.selected_weapon_type_index = control_weapons.weapon_types.find(previous_weapon_type)
	elif not control_weapons.weapon_types.is_empty():
		control_weapons.selected_weapon_type_index = clampi(control_weapons.selected_weapon_type_index, 0, control_weapons.weapon_types.size() - 1)
		control_weapons.selected_weapon_type = control_weapons.weapon_types[control_weapons.selected_weapon_type_index]
	else:
		control_weapons.selected_weapon_type = ""
		control_weapons.selected_weapon_type_index = 0

	print("[FlightDirector] Refilled bombs and rockets on ", player_controlled_plane.name)
	return true


func command_viewed_helicopter_to_return_to_carrier() -> bool:
	var target: RigidBody3D = player_controlled_plane if is_instance_valid(player_controlled_plane) else current_viewed_aircraft
	if not is_instance_valid(target):
		target = _get_toggle_target_aircraft()
	if not is_instance_valid(target):
		return false
	var ai_toggle: Node = target.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("command_helicopter_return_to_carrier_and_land"):
		var commanded: bool = bool(ai_toggle.call("command_helicopter_return_to_carrier_and_land"))
		if commanded:
			is_player_controlling = false
			if player_controlled_plane == target:
				player_controlled_plane = null
			print("[FlightDirector] Commanded helicopter RTB landing: ", target.name)
		return commanded
	var helicopter_pilot: Node = target.find_child("HelicopterPilot", true, false)
	if helicopter_pilot != null and helicopter_pilot.has_method("command_return_to_carrier_and_land"):
		var commanded_direct: bool = bool(helicopter_pilot.call("command_return_to_carrier_and_land"))
		if commanded_direct:
			print("[FlightDirector] Commanded helicopter RTB landing: ", target.name)
		return commanded_direct
	return false


func _save_manual_log_for_viewed_aircraft() -> bool:
	var target: RigidBody3D = player_controlled_plane if is_instance_valid(player_controlled_plane) else current_viewed_aircraft
	if not is_instance_valid(target):
		target = _get_toggle_target_aircraft()
	if not is_instance_valid(target):
		print("[FlightDirector] F10: No active aircraft found to log.")
		return false

	var helicopter_pilot: Node = target.find_child("HelicopterPilot", true, false)
	if helicopter_pilot != null and helicopter_pilot.has_method("save_manual_log"):
		helicopter_pilot.call("save_manual_log", "Manual log triggered by user via F10")
		return true

	print("[FlightDirector] Viewed aircraft has no HelicopterPilot or save_manual_log method: ", target.name)
	return false


func _get_friendly_aircraft() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("friendlies"):
		if node is RigidBody3D and is_instance_valid(node) and not _is_camera_cycle_excluded(node) and _node_has_cameras(node):
			result.append(node)
	for node in get_tree().get_nodes_in_group("ejected_pilots"):
		if node is RigidBody3D and is_instance_valid(node) and not result.has(node) and _node_has_cameras(node):
			result.append(node)
	return result

func _get_enemy_aircraft() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is RigidBody3D and is_instance_valid(node) and not _is_camera_cycle_excluded(node) and _node_has_cameras(node):
			result.append(node)
	return result

func _is_camera_cycle_excluded(node: Node) -> bool:
	return node != null and (
		bool(node.get_meta("camera_abandoned", false))
		or (
			bool(node.get_meta("visual_budget_presentation_staging", false))
			and (not _aircraft_transition_active or node != _aircraft_transition_target)
		)
	)

func _select_friendly_index_for(target: RigidBody3D) -> void:
	var friendlies := _get_friendly_aircraft()
	var idx := friendlies.find(target)
	if idx >= 0:
		friendly_index = idx

func _aircraft_camera_was_replaced(ac: RigidBody3D) -> bool:
	return is_instance_valid(ac) and bool(ac.get_meta("camera_replaced_by_ejected_pilot", false))

func _get_ejected_pilot_replacement(ac: RigidBody3D) -> RigidBody3D:
	if not is_instance_valid(ac) or not ac.has_meta("ejected_pilot_body"):
		return null
	var replacement_path := NodePath(str(ac.get_meta("ejected_pilot_body")))
	var replacement := get_node_or_null(replacement_path) as RigidBody3D
	if is_instance_valid(replacement):
		return replacement
	return null

func _node_has_cameras(node: Node) -> bool:
	if node != null and bool(node.get_meta("ejected_pilot_camera_target", false)):
		return true
	if node != null and bool(node.get_meta("presentation_dormant_camera_capable", false)):
		return true
	return node.get_node_or_null("CameraChase") != null \
		or node.get_node_or_null("CameraCockpit") != null \
		or node.find_child("CameraController", true, false) != null

func _has_bridge_camera() -> bool:
	return get_tree().get_nodes_in_group("carrier_cam").size() > 0

## Advance or retreat through Carrier -> Friendly[0..n] -> Carrier ...
func cycle_target(direction: int):
	var friendlies := _get_friendly_aircraft()
	var has_bridge := _has_bridge_camera()
	var navigation_aircraft: RigidBody3D = _aircraft_transition_target \
		if _aircraft_transition_active and is_instance_valid(_aircraft_transition_target) \
		else current_viewed_aircraft

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
			elif s.cat == Category.FRIENDLY:
				var ac = friendlies[s.idx] if s.idx < friendlies.size() else null
				if is_instance_valid(navigation_aircraft) and ac == navigation_aircraft:
					cur = i
					break
				elif s.idx == friendly_index and not is_instance_valid(current_viewed_aircraft):
					cur = i
					break

	cur = (cur + direction + slots.size()) % slots.size()
	var next = slots[cur]

	current_category = next.cat
	if current_category == Category.FRIENDLY:
		friendly_index = clampi(next.idx, 0, friendlies.size() - 1)

	# Reset to the first view mode when switching targets.
	aircraft_cam_mode = 0
	carrier_cam_mode = 0
	_activate_view()

func _cycle_aircraft_view():
	if current_category == Category.BRIDGE:
		_cycle_bridge_view()
		return
	aircraft_cam_mode = (aircraft_cam_mode + 1) % 3
	if is_instance_valid(current_viewed_aircraft) and current_viewed_aircraft.is_in_group("ejected_pilots"):
		var cc := _get_player_camera_controller()
		if cc != null and cc.has_method("switch_to_aircraft_and_mode"):
			cc.switch_to_aircraft_and_mode(current_viewed_aircraft, aircraft_cam_mode)
			active_controller_camera_system = cc
			return
	# Camera-mode cycling must preserve the aircraft already on screen. The
	# friendly group can be reordered when aircraft spawn or return to the deck,
	# so friendly_index is only a navigation cursor, not stable identity.
	if current_category == Category.FRIENDLY and is_instance_valid(current_viewed_aircraft):
		var friendlies := _get_friendly_aircraft()
		if current_viewed_aircraft in friendlies:
			_select_friendly_index_for(current_viewed_aircraft)
			_view_aircraft(current_viewed_aircraft)
			return
	_activate_view()

func _activate_view():
	if _free_camera_active:
		_sync_view_target_for_free_camera()
		return

	var cc := _get_player_camera_controller()

	match current_category:
		Category.BRIDGE:
			if _aircraft_transition_active:
				var transition_bridge_cam := _activate_bridge_camera_mode(carrier_cam_mode)
				if _aircraft_transition_target_category != Category.BRIDGE:
					_retarget_bridge_camera_transition(transition_bridge_cam)
				return
			var bridge_cam := _activate_bridge_camera_mode(carrier_cam_mode)
			if _should_transition_to_bridge(bridge_cam):
				_begin_bridge_camera_transition(bridge_cam)
				return
			_activate_bridge_view_now(bridge_cam, cc)

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
	if _aircraft_transition_active:
		if ac != _aircraft_transition_target:
			_retarget_aircraft_camera_transition(ac)
		return
	if _should_transition_to_aircraft(ac):
		_begin_aircraft_camera_transition(ac)
		return
	_activate_aircraft_view_now(ac)


func _activate_aircraft_view_now(ac: RigidBody3D) -> void:
	current_viewed_aircraft = ac
	_ensure_aircraft_presentation_attached(ac)

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


func _activate_bridge_view_now(bridge_cam: Camera3D, fallback_controller: Node = null) -> void:
	current_viewed_aircraft = null
	if is_instance_valid(bridge_cam):
		_force_current_camera(bridge_cam)
		active_controller_camera_system = fallback_controller
	elif fallback_controller and fallback_controller.has_method("switch_to_camera"):
		fallback_controller.switch_to_camera(3)
		active_controller_camera_system = fallback_controller


func _should_transition_to_aircraft(ac: RigidBody3D) -> bool:
	if not aircraft_view_transition_enabled \
	or _free_camera_active \
	or _destroyed_plane_linger_active \
	or not is_instance_valid(ac) \
	or ac == current_viewed_aircraft:
		return false
	# Ejected bodies use the player aircraft's camera controller as a remote
	# focus target and do not have a cockpit envelope of their own.
	if ac.is_in_group("ejected_pilots") \
	or (is_instance_valid(current_viewed_aircraft) and current_viewed_aircraft.is_in_group("ejected_pilots")):
		return false
	var viewport := get_viewport()
	if viewport == null or not is_instance_valid(viewport.get_camera_3d()):
		return false
	return is_instance_valid(current_viewed_aircraft) \
		or _is_carrier_camera(viewport.get_camera_3d())


func _should_transition_to_bridge(bridge_cam: Camera3D) -> bool:
	if not aircraft_view_transition_enabled \
	or _free_camera_active \
	or _destroyed_plane_linger_active \
	or not is_instance_valid(bridge_cam) \
	or not is_instance_valid(current_viewed_aircraft) \
	or current_viewed_aircraft.is_in_group("ejected_pilots"):
		return false
	var viewport := get_viewport()
	return viewport != null and is_instance_valid(viewport.get_camera_3d())


func _begin_aircraft_camera_transition(ac: RigidBody3D) -> void:
	_begin_view_camera_transition(ac, Category.FRIENDLY, ac, null)


func _begin_bridge_camera_transition(bridge_cam: Camera3D) -> void:
	var provider := _get_bridge_camera_provider() as Node3D
	if not is_instance_valid(provider) or not is_instance_valid(bridge_cam):
		_activate_bridge_view_now(bridge_cam, _get_player_camera_controller())
		return
	_begin_view_camera_transition(provider, Category.BRIDGE, null, bridge_cam)


func _begin_view_camera_transition(
	target_endpoint: Node3D,
	target_category: Category,
	target_aircraft: RigidBody3D,
	bridge_camera: Camera3D
) -> void:
	var viewport := get_viewport()
	var source_camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if not is_instance_valid(source_camera):
		if target_category == Category.FRIENDLY and is_instance_valid(target_aircraft):
			_activate_aircraft_view_now(target_aircraft)
		elif target_category == Category.BRIDGE:
			_activate_bridge_view_now(bridge_camera, _get_player_camera_controller())
		return

	_aircraft_transition_active = true
	_aircraft_transition_source = current_viewed_aircraft
	_aircraft_transition_target = target_aircraft
	_aircraft_transition_source_category = Category.FRIENDLY \
		if is_instance_valid(current_viewed_aircraft) else Category.BRIDGE
	_aircraft_transition_target_category = target_category
	_aircraft_transition_source_endpoint = current_viewed_aircraft \
		if is_instance_valid(current_viewed_aircraft) \
		else _get_bridge_camera_provider() as Node3D
	_aircraft_transition_target_endpoint = target_endpoint
	_aircraft_transition_source_camera = source_camera
	_aircraft_transition_bridge_camera = bridge_camera
	_aircraft_transition_phase_elapsed_s = 0.0
	_aircraft_transition_base_fov = source_camera.fov
	_aircraft_transition_presentation_complete = true

	var transition_camera := _get_or_create_aircraft_transition_camera()
	_copy_camera_settings(source_camera, transition_camera)
	transition_camera.global_transform = source_camera.global_transform
	_force_current_camera(transition_camera)

	if is_instance_valid(_ui_visible_aircraft):
		_set_aircraft_view_ui_enabled(_ui_visible_aircraft, false)
	_ui_visible_aircraft = null
	if is_instance_valid(target_aircraft):
		_begin_aircraft_transition_presentation(target_aircraft)

	if is_instance_valid(_aircraft_transition_source_endpoint) \
	and _camera_requires_transition_egress(source_camera, _aircraft_transition_source_category):
		_aircraft_transition_source_start_local = \
			_aircraft_transition_source_endpoint.global_transform.affine_inverse() \
			* source_camera.global_transform
		_aircraft_transition_phase = AircraftTransitionPhase.EGRESS
	else:
		_begin_aircraft_transition_transfer()


func _retarget_aircraft_camera_transition(ac: RigidBody3D) -> void:
	if not _aircraft_transition_active or not is_instance_valid(ac):
		return
	_release_aircraft_transition_presentation(_aircraft_transition_target)
	_aircraft_transition_target = ac
	_aircraft_transition_target_endpoint = ac
	_aircraft_transition_target_category = Category.FRIENDLY
	_aircraft_transition_bridge_camera = null
	_aircraft_transition_presentation_complete = true
	_begin_aircraft_transition_presentation(ac)
	_begin_aircraft_transition_transfer()


func _retarget_bridge_camera_transition(bridge_cam: Camera3D) -> void:
	if not _aircraft_transition_active or not is_instance_valid(bridge_cam):
		return
	var provider := _get_bridge_camera_provider() as Node3D
	if not is_instance_valid(provider):
		return
	_release_aircraft_transition_presentation(_aircraft_transition_target)
	_aircraft_transition_target = null
	_aircraft_transition_target_endpoint = provider
	_aircraft_transition_target_category = Category.BRIDGE
	_aircraft_transition_bridge_camera = bridge_cam
	_aircraft_transition_presentation_complete = true
	_begin_aircraft_transition_transfer()


func _get_or_create_aircraft_transition_camera() -> Camera3D:
	if is_instance_valid(_aircraft_transition_camera):
		return _aircraft_transition_camera
	var camera := Camera3D.new()
	camera.name = "AircraftViewTransitionCamera"
	var parent: Node = get_tree().current_scene if get_tree().current_scene != null else self
	parent.add_child(camera)
	_aircraft_transition_camera = camera
	return camera


func _copy_camera_settings(source: Camera3D, destination: Camera3D) -> void:
	if not is_instance_valid(source) or not is_instance_valid(destination):
		return
	destination.projection = source.projection
	destination.fov = source.fov
	destination.size = source.size
	destination.near = source.near
	destination.far = source.far
	destination.keep_aspect = source.keep_aspect
	destination.cull_mask = source.cull_mask
	destination.environment = source.environment
	destination.attributes = source.attributes
	destination.doppler_tracking = source.doppler_tracking


func _begin_aircraft_transition_presentation(ac: RigidBody3D) -> void:
	var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
	if visual_budget == null \
	or not visual_budget.has_method("begin_aircraft_view_transition_staging"):
		return
	var result: Dictionary = visual_budget.call("begin_aircraft_view_transition_staging", ac)
	_aircraft_transition_presentation_complete = bool(result.get("complete", true))


func _advance_aircraft_transition_presentation() -> void:
	if _aircraft_transition_presentation_complete \
	or not is_instance_valid(_aircraft_transition_target):
		return
	var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
	if visual_budget == null \
	or not visual_budget.has_method("restore_next_staged_aircraft_presentation_root"):
		_aircraft_transition_presentation_complete = true
		return
	var profiler_start: int = FrameProfiler.begin("FlightDirector.aircraft_transition_stage_root")
	var result: Dictionary = visual_budget.call(
		"restore_next_staged_aircraft_presentation_root",
		_aircraft_transition_target
	)
	var root_name := str(result.get("root_name", "unknown")).to_snake_case()
	FrameProfiler.end("FlightDirector.aircraft_transition_stage_%s" % root_name, profiler_start)
	_aircraft_transition_presentation_complete = bool(result.get("complete", true))


func _release_aircraft_transition_presentation(aircraft_variant: Variant) -> void:
	# A transition target can be freed before the cancellation path releases its
	# presentation lock. Keep the argument untyped until after validation: Godot
	# rejects a freed Object while binding a typed Object-derived parameter, before
	# this function body (and its validity guard) can run.
	if not is_instance_valid(aircraft_variant):
		return
	var ac := aircraft_variant as RigidBody3D
	if ac == null:
		return
	var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
	if visual_budget != null \
	and visual_budget.has_method("release_aircraft_presentation_keep_attached"):
		visual_budget.call("release_aircraft_presentation_keep_attached", ac)


func _update_aircraft_camera_transition(delta: float) -> void:
	if not _aircraft_transition_active:
		return
	if not is_instance_valid(_aircraft_transition_camera) \
	or not is_instance_valid(_aircraft_transition_target_endpoint):
		_cancel_aircraft_camera_transition(true)
		return

	_advance_aircraft_transition_presentation()
	match _aircraft_transition_phase:
		AircraftTransitionPhase.EGRESS:
			_update_aircraft_transition_egress(delta)
		AircraftTransitionPhase.TRANSFER:
			_update_aircraft_transition_transfer(delta)
		AircraftTransitionPhase.WAITING_FOR_PRESENTATION:
			_update_aircraft_transition_waiting()
		AircraftTransitionPhase.ARRIVAL:
			_update_aircraft_transition_arrival(delta)
		_:
			_cancel_aircraft_camera_transition(true)


func _update_aircraft_transition_egress(delta: float) -> void:
	if not is_instance_valid(_aircraft_transition_source_endpoint):
		_begin_aircraft_transition_transfer()
		return
	_aircraft_transition_phase_elapsed_s += maxf(delta, 0.0)
	var duration := maxf(aircraft_transition_egress_s, 0.01)
	var linear_t := clampf(_aircraft_transition_phase_elapsed_s / duration, 0.0, 1.0)
	var eased_t := _aircraft_transition_smootherstep(linear_t)
	var gate_local := _get_transition_gate_local(
		_aircraft_transition_source_endpoint,
		_aircraft_transition_source_category
	)
	var start_position := _aircraft_transition_source_start_local.origin
	var clearance := _get_transition_clearance_m(
		_aircraft_transition_source_endpoint,
		_aircraft_transition_source_category
	)
	var first_control := _get_transition_interior_control_position(
		start_position,
		gate_local.origin,
		clearance,
		_aircraft_transition_source_endpoint,
		_aircraft_transition_source_category
	)
	var second_control := gate_local.origin + Vector3.UP * clearance * 0.5
	var local_position := start_position.bezier_interpolate(
		first_control,
		second_control,
		gate_local.origin,
		eased_t
	)
	var local_basis := _aircraft_transition_source_start_local.basis.orthonormalized().slerp(
		gate_local.basis.orthonormalized(),
		eased_t
	)
	var local_transform := Transform3D(local_basis, local_position)
	_aircraft_transition_camera.global_transform = \
		_aircraft_transition_source_endpoint.global_transform * local_transform
	# Keep the cockpit's very small near plane while crossing the transparent
	# canopy, then adopt a stable exterior value before the fast transfer.
	_aircraft_transition_camera.near = lerpf(
		_aircraft_transition_camera.near,
		maxf(_aircraft_transition_camera.near, 0.1),
		eased_t
	)
	if linear_t >= 1.0:
		_begin_aircraft_transition_transfer()


func _begin_aircraft_transition_transfer() -> void:
	if not is_instance_valid(_aircraft_transition_camera) \
	or not is_instance_valid(_aircraft_transition_target_endpoint):
		_cancel_aircraft_camera_transition(true)
		return
	_aircraft_transition_phase = AircraftTransitionPhase.TRANSFER
	_aircraft_transition_phase_elapsed_s = 0.0
	_aircraft_transition_transfer_start = _aircraft_transition_camera.global_transform
	var target_gate := _get_transition_gate_world(
		_aircraft_transition_target_endpoint,
		_aircraft_transition_target_category
	)
	_aircraft_transition_transfer_distance_m = \
		_aircraft_transition_transfer_start.origin.distance_to(target_gate.origin)
	_aircraft_transition_transfer_duration_s = _calculate_aircraft_transition_transfer_duration(
		_aircraft_transition_transfer_distance_m
	)
	_begin_transition_terrain_prefetch()
	print("[FlightDirector] View transition source=%s target=%s distance_m=%.1f transfer_s=%.2f" % [
		_aircraft_transition_source_endpoint.name if is_instance_valid(_aircraft_transition_source_endpoint) else "none",
		_aircraft_transition_target_endpoint.name,
		_aircraft_transition_transfer_distance_m,
		_aircraft_transition_transfer_duration_s,
	])


func _update_aircraft_transition_transfer(delta: float) -> void:
	_aircraft_transition_phase_elapsed_s += maxf(delta, 0.0)
	var duration := maxf(_aircraft_transition_transfer_duration_s, 0.01)
	var linear_t := clampf(_aircraft_transition_phase_elapsed_s / duration, 0.0, 1.0)
	var eased_t := _aircraft_transition_smootherstep(linear_t)
	var start_position := _aircraft_transition_transfer_start.origin
	var target_gate := _get_transition_gate_world(
		_aircraft_transition_target_endpoint,
		_aircraft_transition_target_category
	)
	var end_position := target_gate.origin
	var displacement := end_position - start_position
	var distance_m := maxf(displacement.length(), 0.001)
	var direction := displacement / distance_m
	var clearance := clampf(_aircraft_transition_transfer_distance_m * 0.08, 8.0, 400.0)
	var first_control := start_position + direction * distance_m * 0.28 + Vector3.UP * clearance
	var second_control := end_position - direction * distance_m * 0.22 + Vector3.UP * clearance
	var camera_position := start_position.bezier_interpolate(
		first_control,
		second_control,
		end_position,
		eased_t
	)
	var focus_position := _get_transition_focus_world(
		_aircraft_transition_target_endpoint,
		_aircraft_transition_target_category
	)
	var look_basis := _aircraft_transition_look_basis(
		camera_position,
		focus_position,
		_aircraft_transition_transfer_start.basis
	)
	var turn_t := _aircraft_transition_smootherstep(clampf(linear_t / 0.3, 0.0, 1.0))
	var camera_basis := _aircraft_transition_transfer_start.basis.orthonormalized().slerp(
		look_basis,
		turn_t
	)
	_aircraft_transition_camera.global_transform = Transform3D(camera_basis, camera_position)
	var distance_fraction := clampf(
		_aircraft_transition_transfer_distance_m \
			/ maxf(aircraft_transition_full_duration_distance_m, 1.0),
		0.0,
		1.0
	)
	var fov_boost := sin(linear_t * PI) \
		* aircraft_transition_max_fov_boost_deg \
		* sqrt(distance_fraction)
	_aircraft_transition_camera.fov = _aircraft_transition_base_fov + fov_boost
	_aircraft_transition_camera.near = maxf(_aircraft_transition_camera.near, 0.1)

	if linear_t < 1.0:
		return
	if _is_aircraft_transition_destination_ready():
		_begin_aircraft_transition_arrival()
	else:
		_aircraft_transition_phase = AircraftTransitionPhase.WAITING_FOR_PRESENTATION
		_aircraft_transition_phase_elapsed_s = 0.0


func _update_aircraft_transition_waiting() -> void:
	var gate := _get_transition_gate_world(
		_aircraft_transition_target_endpoint,
		_aircraft_transition_target_category
	)
	var focus := _get_transition_focus_world(
		_aircraft_transition_target_endpoint,
		_aircraft_transition_target_category
	)
	gate.basis = _aircraft_transition_look_basis(gate.origin, focus, gate.basis)
	_aircraft_transition_camera.global_transform = gate
	_aircraft_transition_camera.fov = _aircraft_transition_base_fov
	if _is_aircraft_transition_destination_ready():
		_begin_aircraft_transition_arrival()


func _begin_aircraft_transition_arrival() -> void:
	if not _is_aircraft_transition_destination_ready():
		_aircraft_transition_phase = AircraftTransitionPhase.WAITING_FOR_PRESENTATION
		return
	_aircraft_transition_phase = AircraftTransitionPhase.ARRIVAL
	_aircraft_transition_phase_elapsed_s = 0.0
	_aircraft_transition_arrival_start_local = \
		_aircraft_transition_target_endpoint.global_transform.affine_inverse() \
		* _aircraft_transition_camera.global_transform


func _update_aircraft_transition_arrival(delta: float) -> void:
	var destination_camera := _get_transition_destination_camera()
	if not is_instance_valid(destination_camera):
		_aircraft_transition_phase = AircraftTransitionPhase.WAITING_FOR_PRESENTATION
		return
	_aircraft_transition_phase_elapsed_s += maxf(delta, 0.0)
	var duration := maxf(aircraft_transition_arrival_s, 0.01)
	var linear_t := clampf(_aircraft_transition_phase_elapsed_s / duration, 0.0, 1.0)
	var eased_t := _aircraft_transition_smootherstep(linear_t)
	var destination_local := _aircraft_transition_target_endpoint.global_transform.affine_inverse() \
		* destination_camera.global_transform
	var start_position := _aircraft_transition_arrival_start_local.origin
	var clearance := _get_transition_clearance_m(
		_aircraft_transition_target_endpoint,
		_aircraft_transition_target_category
	)
	var first_control := start_position + Vector3.UP * clearance
	var second_control := _get_transition_interior_control_position(
		destination_local.origin,
		start_position,
		clearance,
		_aircraft_transition_target_endpoint,
		_aircraft_transition_target_category
	)
	var local_position := start_position.bezier_interpolate(
		first_control,
		second_control,
		destination_local.origin,
		eased_t
	)
	var local_basis := _aircraft_transition_arrival_start_local.basis.orthonormalized().slerp(
		destination_local.basis.orthonormalized(),
		eased_t
	)
	_aircraft_transition_camera.global_transform = _aircraft_transition_target_endpoint.global_transform \
		* Transform3D(local_basis, local_position)
	_aircraft_transition_camera.fov = lerpf(
		_aircraft_transition_base_fov,
		destination_camera.fov,
		eased_t
	)
	_aircraft_transition_camera.near = lerpf(
		maxf(_aircraft_transition_camera.near, 0.1),
		destination_camera.near,
		eased_t
	)
	if linear_t >= 1.0:
		_aircraft_transition_camera.global_transform = destination_camera.global_transform
		_aircraft_transition_camera.fov = destination_camera.fov
		_complete_aircraft_camera_transition()


func _complete_aircraft_camera_transition() -> void:
	var target_endpoint := _aircraft_transition_target_endpoint
	var target_category := _aircraft_transition_target_category
	var target_aircraft := _aircraft_transition_target
	var target_bridge_camera := _aircraft_transition_bridge_camera
	if not is_instance_valid(target_endpoint):
		_cancel_aircraft_camera_transition(true)
		return
	if target_category == Category.FRIENDLY and not is_instance_valid(target_aircraft):
		_cancel_aircraft_camera_transition(true)
		return
	_aircraft_transition_active = false
	_aircraft_transition_phase = AircraftTransitionPhase.NONE
	var profiler_start: int = FrameProfiler.begin("FlightDirector.aircraft_transition_final_handoff")
	if target_category == Category.FRIENDLY:
		current_category = Category.FRIENDLY
		current_viewed_aircraft = target_aircraft
		_select_friendly_index_for(target_aircraft)
		_release_aircraft_transition_presentation(target_aircraft)
		_activate_aircraft_view_now(target_aircraft)
	else:
		current_category = Category.BRIDGE
		_activate_bridge_view_now(target_bridge_camera, _get_player_camera_controller())
	_end_transition_terrain_prefetch()
	FrameProfiler.end("FlightDirector.aircraft_transition_final_handoff", profiler_start)
	print("[FlightDirector] View transition complete target=%s" % target_endpoint.name)
	_clear_aircraft_transition_references()


func _cancel_aircraft_camera_transition(restore_source_view: bool) -> void:
	if not _aircraft_transition_active:
		return
	var source := _aircraft_transition_source
	var source_category := _aircraft_transition_source_category
	var source_camera := _aircraft_transition_source_camera
	_release_aircraft_transition_presentation(_aircraft_transition_target)
	_aircraft_transition_active = false
	_aircraft_transition_phase = AircraftTransitionPhase.NONE
	if is_instance_valid(_aircraft_transition_camera):
		_aircraft_transition_camera.current = false
	_clear_aircraft_transition_references()
	if restore_source_view and source_category == Category.FRIENDLY and is_instance_valid(source):
		current_category = Category.FRIENDLY
		current_viewed_aircraft = source
		_select_friendly_index_for(source)
		_activate_aircraft_view_now(source)
	elif restore_source_view and source_category == Category.BRIDGE:
		current_viewed_aircraft = null
		current_category = Category.BRIDGE
		if is_instance_valid(source_camera):
			_force_current_camera(source_camera)
		else:
			_activate_view()
	elif restore_source_view:
		current_viewed_aircraft = null
		current_category = Category.BRIDGE
		_activate_view()
	_end_transition_terrain_prefetch()


func _begin_transition_terrain_prefetch() -> void:
	var stream_target: Node3D = _get_transition_destination_camera()
	if not is_instance_valid(stream_target):
		stream_target = _aircraft_transition_target_endpoint
	if not is_instance_valid(stream_target):
		return
	for terrain_variant in get_tree().get_nodes_in_group("terrain_streamer"):
		var terrain := terrain_variant as Node
		if terrain != null and terrain.has_method("begin_view_transition_streaming"):
			terrain.call("begin_view_transition_streaming", stream_target)


func _end_transition_terrain_prefetch() -> void:
	for terrain_variant in get_tree().get_nodes_in_group("terrain_streamer"):
		var terrain := terrain_variant as Node
		if terrain != null and terrain.has_method("end_view_transition_streaming"):
			terrain.call("end_view_transition_streaming")


func should_throttle_background_ai_during_view_transition(candidate: Node) -> bool:
	if not _aircraft_transition_active or candidate == null or not is_instance_valid(candidate):
		return false
	# Source and destination remain at full precision because the player can see
	# both ends of the move. Only unrelated aircraft use the temporary half-rate
	# budget while the cinematic camera is in flight.
	return candidate != _aircraft_transition_source \
		and candidate != _aircraft_transition_target \
		and candidate != current_viewed_aircraft \
		and candidate != player_controlled_plane


func _clear_aircraft_transition_references() -> void:
	_aircraft_transition_source = null
	_aircraft_transition_target = null
	_aircraft_transition_source_endpoint = null
	_aircraft_transition_target_endpoint = null
	_aircraft_transition_source_camera = null
	_aircraft_transition_bridge_camera = null


func _is_aircraft_transition_destination_ready() -> bool:
	return _aircraft_transition_presentation_complete \
		and is_instance_valid(_aircraft_transition_target_endpoint) \
		and is_instance_valid(_get_transition_destination_camera())


func _get_transition_destination_camera() -> Camera3D:
	if _aircraft_transition_target_category == Category.BRIDGE:
		return _aircraft_transition_bridge_camera
	return _get_aircraft_camera(_aircraft_transition_target, "CameraCockpit")


func _get_aircraft_cockpit_transform_local(ac: RigidBody3D) -> Transform3D:
	var cockpit_camera := _get_aircraft_camera(ac, "CameraCockpit")
	if is_instance_valid(cockpit_camera):
		return ac.global_transform.affine_inverse() * cockpit_camera.global_transform
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0))


func _get_aircraft_transition_gate_local(ac: RigidBody3D) -> Transform3D:
	return _get_transition_gate_local(ac, Category.FRIENDLY)


func _get_transition_gate_local(endpoint: Node3D, category: Category) -> Transform3D:
	var authored_anchor := endpoint.get_node_or_null("CameraTransitionAnchor") as Node3D
	if is_instance_valid(authored_anchor):
		return endpoint.global_transform.affine_inverse() * authored_anchor.global_transform
	var endpoint_camera := _get_endpoint_camera(endpoint, category)
	var camera_local := endpoint.global_transform.affine_inverse() * endpoint_camera.global_transform \
		if is_instance_valid(endpoint_camera) \
		else Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0))
	var gate_position := camera_local.origin
	if category == Category.BRIDGE:
		gate_position += -camera_local.basis.z.normalized() * 12.0 + Vector3.UP * 3.0
	elif _is_helicopter_endpoint(endpoint):
		# Helicopter cockpits sit below the rotor. Exit over the nose rather than
		# backing through the cabin or rising through the rotor disc.
		gate_position += Vector3.BACK * helicopter_transition_gate_ahead_m \
			+ Vector3.UP * helicopter_transition_gate_above_m
	else:
		gate_position += Vector3.FORWARD * aircraft_transition_gate_behind_m \
			+ Vector3.UP * aircraft_transition_gate_above_m
	var gate_basis := _aircraft_transition_look_basis(
		gate_position,
		camera_local.origin,
		camera_local.basis
	)
	return Transform3D(gate_basis, gate_position)


func _get_aircraft_transition_gate_world(ac: RigidBody3D) -> Transform3D:
	return _get_transition_gate_world(ac, Category.FRIENDLY)


func _get_transition_gate_world(endpoint: Node3D, category: Category) -> Transform3D:
	return endpoint.global_transform * _get_transition_gate_local(endpoint, category)


func _get_aircraft_transition_focus_world(ac: RigidBody3D) -> Vector3:
	return _get_transition_focus_world(ac, Category.FRIENDLY)


func _get_transition_focus_world(endpoint: Node3D, category: Category) -> Vector3:
	var endpoint_camera := _get_endpoint_camera(endpoint, category)
	if is_instance_valid(endpoint_camera):
		return endpoint_camera.global_position
	return endpoint.global_position + endpoint.global_transform.basis.y.normalized() * 1.5


func _get_endpoint_camera(endpoint: Node3D, category: Category) -> Camera3D:
	if category == Category.BRIDGE:
		if endpoint == _aircraft_transition_target_endpoint \
		and is_instance_valid(_aircraft_transition_bridge_camera):
			return _aircraft_transition_bridge_camera
		if endpoint != null and endpoint.has_method("get_camera"):
			var camera_variant: Variant = endpoint.call("get_camera")
			if is_instance_valid(camera_variant) and camera_variant is Camera3D:
				return camera_variant as Camera3D
		return null
	return _get_aircraft_camera(endpoint as RigidBody3D, "CameraCockpit")


func _get_transition_clearance_m(endpoint: Node3D, category: Category) -> float:
	if category == Category.BRIDGE:
		return 3.0
	if _is_helicopter_endpoint(endpoint):
		return helicopter_transition_clearance_m
	return aircraft_transition_canopy_clearance_m


func _get_transition_interior_control_position(
	interior_position: Vector3,
	gate_position: Vector3,
	clearance_m: float,
	endpoint: Node3D,
	category: Category
) -> Vector3:
	var result := interior_position + Vector3.UP * clearance_m
	if category == Category.BRIDGE or _is_helicopter_endpoint(endpoint):
		var horizontal_offset := gate_position - interior_position
		horizontal_offset.y = 0.0
		result += horizontal_offset * 0.45
	return result


func _is_helicopter_endpoint(endpoint: Node3D) -> bool:
	return is_instance_valid(endpoint) and (
		bool(endpoint.get_meta("is_helicopter", false))
		or endpoint.find_child("HelicopterPilot", true, false) != null
	)


func _aircraft_transition_look_basis(
	from_position: Vector3,
	target_position: Vector3,
	fallback_basis: Basis
) -> Basis:
	var direction := target_position - from_position
	if direction.length_squared() < 0.0001:
		return fallback_basis.orthonormalized()
	var up := Vector3.UP
	if absf(direction.normalized().dot(up)) > 0.98:
		up = Vector3.FORWARD
	return Transform3D(Basis.IDENTITY, from_position).looking_at(target_position, up).basis


func _calculate_aircraft_transition_transfer_duration(distance_m: float) -> float:
	var minimum := maxf(aircraft_transition_min_transfer_s, 0.01)
	var maximum := maxf(aircraft_transition_max_transfer_s, minimum)
	var full_distance := maxf(aircraft_transition_full_duration_distance_m, 1.0)
	# Logarithmic growth lets very distant aircraft travel much faster in metres
	# per second without making nearby deck-to-deck switches abrupt.
	var fraction := log(1.0 + maxf(distance_m, 0.0) / 100.0) \
		/ log(1.0 + full_distance / 100.0)
	return lerpf(minimum, maximum, clampf(fraction, 0.0, 1.0))


func _aircraft_transition_smootherstep(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	# Cubic smoothstep reaches useful speed earlier than quintic smootherstep,
	# avoiding the impression that the camera pauses at every phase boundary.
	return t * t * (3.0 - 2.0 * t)


func is_aircraft_view_transition_active() -> bool:
	return _aircraft_transition_active


func get_aircraft_view_transition_state() -> Dictionary:
	return {
		"active": _aircraft_transition_active,
		"phase": int(_aircraft_transition_phase),
		"source": _aircraft_transition_source,
		"target": _aircraft_transition_target,
		"source_endpoint": _aircraft_transition_source_endpoint,
		"target_endpoint": _aircraft_transition_target_endpoint,
		"source_category": int(_aircraft_transition_source_category),
		"target_category": int(_aircraft_transition_target_category),
		"transfer_distance_m": _aircraft_transition_transfer_distance_m,
		"transfer_duration_s": _aircraft_transition_transfer_duration_s,
		"presentation_complete": _aircraft_transition_presentation_complete,
	}


func _get_player_camera_controller() -> Node:
	var ccs := get_tree().get_nodes_in_group("camera_controller")
	if is_instance_valid(current_viewed_aircraft):
		for cc: Node in ccs:
			var controller_aircraft := _get_valid_camera_controller_aircraft(cc)
			if controller_aircraft == current_viewed_aircraft:
				return cc

	var first_valid_controller: Node = null
	for cc: Node in ccs:
		var controller_aircraft := _get_valid_camera_controller_aircraft(cc)
		if controller_aircraft == null:
			continue
		if first_valid_controller == null:
			first_valid_controller = cc
		if not controller_aircraft.is_in_group("ai_aircraft") \
				and not controller_aircraft.is_in_group("enemies"):
			return cc
	return first_valid_controller


func _get_valid_camera_controller_aircraft(camera_controller: Node) -> Node:
	if not is_instance_valid(camera_controller) or not ("aircraft" in camera_controller):
		return null
	var controller_aircraft_variant: Variant = camera_controller.get("aircraft")
	# A Variant can retain an Object reference after the object has been freed.
	# Validate it before `as Node`; attempting the cast itself raises a script error.
	if controller_aircraft_variant == null \
			or typeof(controller_aircraft_variant) != TYPE_OBJECT \
			or not is_instance_valid(controller_aircraft_variant):
		return null
	return controller_aircraft_variant as Node

func toggle_player_control():
	if is_player_controlling:
		_return_control_to_ai()
		return

	var target: RigidBody3D = _get_toggle_target_aircraft()
	if not is_instance_valid(target):
		return
	if target.has_meta("player_control_locked") and bool(target.get_meta("player_control_locked")):
		return

	var ai_toggle = target.get_node_or_null("AIToggle")
	if ai_toggle and ai_toggle.has_method("disable_ai"):
		ai_toggle.disable_ai()

	is_player_controlling = true
	player_controlled_plane = target
	# Taking control also makes this aircraft the authoritative camera target.
	# This reattaches and re-enables its cockpit presentation synchronously.
	current_category = Category.FRIENDLY
	current_viewed_aircraft = target
	_select_friendly_index_for(target)
	_view_aircraft(target)
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

func force_release_player_control_for(aircraft: RigidBody3D) -> void:
	if not is_player_controlling:
		return
	if not is_instance_valid(player_controlled_plane):
		is_player_controlling = false
		player_controlled_plane = null
		return
	if is_instance_valid(aircraft) and player_controlled_plane != aircraft:
		return
	is_player_controlling = false
	player_controlled_plane = null

func _get_toggle_target_aircraft() -> RigidBody3D:
	if is_instance_valid(player_controlled_plane):
		return player_controlled_plane

	# current_viewed_aircraft is the authoritative record of what's on screen.
	# Check it first — camera-based detection returns the camera owner (aircraft 1)
	# even when the player's camera controller is used to view a different aircraft.
	if is_instance_valid(current_viewed_aircraft):
		var friendlies: Array = _get_friendly_aircraft()
		if current_viewed_aircraft in friendlies:
			return current_viewed_aircraft

	# Fallback: camera ownership walk (works when aircraft has its own CameraController)
	var active_camera: Camera3D = _get_current_active_camera()
	var bridge_camera: Camera3D = _get_bridge_camera()
	if is_instance_valid(active_camera) and active_camera == bridge_camera:
		return null
	var camera_aircraft: RigidBody3D = _get_aircraft_for_camera(active_camera)
	if is_instance_valid(camera_aircraft):
		var visible_friendlies: Array = _get_friendly_aircraft()
		if camera_aircraft in visible_friendlies:
			return camera_aircraft

	if current_category == Category.FRIENDLY:
		var friendlies_from_cycle: Array = _get_friendly_aircraft()
		if friendlies_from_cycle.is_empty():
			return null
		friendly_index = clampi(friendly_index, 0, friendlies_from_cycle.size() - 1)
		return friendlies_from_cycle[friendly_index] as RigidBody3D
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
	var show_ai := not _free_camera_active \
		and not _aircraft_transition_active \
		and is_instance_valid(current_viewed_aircraft) \
		and _is_aircraft_ai_controlled(current_viewed_aircraft)
	_ai_status_label.visible = show_ai
	if show_ai and is_instance_valid(current_viewed_aircraft):
		_ai_status_label.text = "AI  %s" % current_viewed_aircraft.name

func _update_pilot_name_overlay() -> void:
	if _pilot_name_label == null:
		return

	var show_label := false
	var display_text := ""

	if not _free_camera_active \
	and not _destroyed_plane_linger_active \
	and not _aircraft_transition_active:
		var active_camera := _get_current_active_camera()
		if _camera_is_in_cockpit_mount(active_camera):
			# Use current_viewed_aircraft as authority; fall back to camera tree walk
			# so the correct pilot name shows even when using the player's camera to
			# view a different aircraft.
			var pilot_aircraft: RigidBody3D = current_viewed_aircraft \
				if is_instance_valid(current_viewed_aircraft) \
				else _get_aircraft_for_camera(active_camera)
			if is_instance_valid(pilot_aircraft):
				display_text = _pilot_display_from_aircraft(pilot_aircraft)
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


func _camera_requires_transition_egress(camera: Camera3D, source_category: Category) -> bool:
	if source_category == Category.FRIENDLY:
		return _camera_is_in_cockpit_mount(camera)
	var provider := _get_bridge_camera_provider()
	return provider != null \
		and provider.has_method("is_control_room_camera") \
		and bool(provider.call("is_control_room_camera", camera))


func _is_carrier_camera(camera: Camera3D) -> bool:
	if not is_instance_valid(camera):
		return false
	var provider := _get_bridge_camera_provider()
	if provider == null:
		return false
	if provider.has_method("is_carrier_camera"):
		return bool(provider.call("is_carrier_camera", camera))
	if provider.has_method("get_camera"):
		return provider.call("get_camera") == camera
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
	if not _free_camera_active \
	and not _aircraft_transition_active \
	and is_instance_valid(current_viewed_aircraft):
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
	if enabled:
		_ensure_aircraft_presentation_attached(ac)
	for node_name in [
		"CameraController",
		"CameraCockpit",
		"CameraChase",
		"CameraCinematic",
		"HeadsUpDisplay",
		"InstrumentPanel",
		"CockpitCanopyVisibility",
		"AudioManager3D",
	]:
		var node := ac.find_child(node_name, true, false) as Node
		if node == null:
			continue
		if node.has_method("set_view_updates_active"):
			node.call("set_view_updates_active", enabled)
		node.set_process(enabled)
		node.set_physics_process(enabled)
		node.set_process_input(enabled)
		if node is CanvasItem:
			(node as CanvasItem).visible = enabled
		elif node is Node3D:
			(node as Node3D).visible = enabled


func _ensure_aircraft_presentation_attached(ac: RigidBody3D) -> void:
	if not is_instance_valid(ac):
		return
	var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
	if visual_budget != null and visual_budget.has_method("ensure_aircraft_presentation_attached"):
		visual_budget.call("ensure_aircraft_presentation_attached", ac)

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
	if not ai_pilot or not ai_pilot.has_method("start_recovery"):
		print("[FlightDirector] L: no AIPilot found on ", target.name)
		return

	# Use the same staged recovery as autonomous RTB: queue for a clear, steady carrier corridor,
	# establish the inbound axis and glideslope, then hand the final segment to start_landing().
	var recovery_task: Variant = AirTaskModel.recover()
	var ok: bool = bool(ai_pilot.call("assign_air_task", recovery_task)) \
		if ai_pilot.has_method("assign_air_task") else ai_pilot.start_recovery()
	if ok:
		print("[FlightDirector] L: staged carrier recovery commanded for ", target.name)
	else:
		print("[FlightDirector] L: approach waypoints not found for ", target.name)

func _is_aircraft_in_landing_flow(aircraft: RigidBody3D) -> bool:
	var ai_pilot := aircraft.find_child("AIPilot", true, false) as AIPilot
	if ai_pilot == null:
		return false
	return ai_pilot.current_state in [
		AIPilot.State.RECOVERY_MARSHAL,
		AIPilot.State.RECOVERY_HOLD,
		AIPilot.State.RECOVERY_APPROACH,
		AIPilot.State.APPROACH,
		AIPilot.State.LANDING,
		AIPilot.State.MISSED_APPROACH,
	]

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
		if not ai_pilot or not ai_pilot.has_method("start_recovery"):
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
		if is_instance_valid(cam) and cam is Camera3D:
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

	var bridge_cam: Camera3D = _get_bridge_camera()
	if is_instance_valid(bridge_cam) and bridge_cam.current:
		return bridge_cam

	for node in get_tree().get_nodes_in_group("camera_controller"):
		if not is_instance_valid(node) or not node.has_method("get_current_camera"):
			continue
		var cam_variant: Variant = node.call("get_current_camera")
		if is_instance_valid(cam_variant) and cam_variant is Camera3D:
			return cam_variant as Camera3D

	if is_instance_valid(current_viewed_aircraft):
		for tripod_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
			var cam: Camera3D = _get_aircraft_camera(current_viewed_aircraft, tripod_name)
			if is_instance_valid(cam) and cam.current:
				return cam

	var viewport := get_viewport()
	if viewport:
		var viewport_camera: Variant = viewport.get_camera_3d()
		if is_instance_valid(viewport_camera) and viewport_camera is Camera3D:
			return viewport_camera as Camera3D
	return null

func _get_chase_camera_for_viewed_aircraft() -> Camera3D:
	# Priority 1: the viewed aircraft's own CameraController (has its own chase_camera)
	if is_instance_valid(current_viewed_aircraft):
		var ac_cc := current_viewed_aircraft.find_child("CameraController", true, false)
		if ac_cc and "chase_camera" in ac_cc:
			var cam_variant: Variant = ac_cc.get("chase_camera")
			if is_instance_valid(cam_variant) and cam_variant is Camera3D:
				return cam_variant as Camera3D
		# Priority 2: a bare CameraChase tripod (no CC, but camera tripod present)
		var chase_tripod := current_viewed_aircraft.get_node_or_null("CameraChase")
		if chase_tripod:
			var cam := (chase_tripod as Node).find_child("Camera3D", true, false) as Camera3D
			if is_instance_valid(cam):
				return cam
	# Priority 3: the player camera controller (works when player aircraft is viewed)
	var cc := _get_player_camera_controller()
	if cc and "chase_camera" in cc:
		var cam_variant: Variant = cc.get("chase_camera")
		if is_instance_valid(cam_variant) and cam_variant is Camera3D:
			return cam_variant as Camera3D
	return null

func _toggle_free_camera() -> void:
	if _free_camera_active:
		_exit_free_camera()
		return

	_enter_free_camera()

func _enter_free_camera(preserve_player_control: bool = false) -> void:
	if is_player_controlling and not preserve_player_control:
		_return_control_to_ai()

	var source_camera: Camera3D = _get_current_active_camera()
	var free_camera := _get_or_create_free_camera()
	if source_camera:
		var bridge_provider := _get_bridge_camera_provider()
		var is_bridge_control_room_camera := current_category == Category.BRIDGE \
			and bridge_provider != null \
			and bridge_provider.has_method("is_control_room_camera") \
			and bool(bridge_provider.call("is_control_room_camera", source_camera))
		# Cockpit cameras have a very small near plane (inside the aircraft mesh).
		# Starting free-look there makes the aircraft invisible and hides the pilot.
		# Instead, snap to the chase camera position so the cockpit is visible from outside.
		var is_cockpit_cam: bool = source_camera.near < 0.05
		if is_bridge_control_room_camera and bridge_provider is Node3D:
			_place_free_camera_behind_bridge_officer(
				free_camera,
				source_camera,
				bridge_provider as Node3D
			)
			free_camera.near = 0.1
			free_camera.fov = source_camera.fov
			free_camera.far = source_camera.far
			free_camera.keep_aspect = source_camera.keep_aspect
			free_camera.projection = source_camera.projection
		elif is_cockpit_cam:
			# Find the chase camera for the CURRENTLY VIEWED aircraft specifically.
			# _get_player_camera_controller() always returns aircraft 1's CC, so it gives
			# the wrong chase camera when viewing aircraft 2 through its own CameraController.
			var chase_cam: Camera3D = _get_chase_camera_for_viewed_aircraft()
			if chase_cam and is_instance_valid(chase_cam):
				free_camera.global_transform = chase_cam.global_transform
			elif is_instance_valid(current_viewed_aircraft):
				var basis: Basis = current_viewed_aircraft.global_transform.basis
				free_camera.global_position = current_viewed_aircraft.global_position \
					- basis.z * 15.0 + Vector3.UP * 4.0
				free_camera.look_at(current_viewed_aircraft.global_position + Vector3.UP * 1.5, Vector3.UP)
			else:
				free_camera.global_transform = source_camera.global_transform
			free_camera.near = 0.1
		else:
			free_camera.global_transform = source_camera.global_transform
			free_camera.near = source_camera.near
		free_camera.fov = source_camera.fov
		free_camera.far = source_camera.far
		free_camera.keep_aspect = source_camera.keep_aspect
		free_camera.projection = source_camera.projection
	else:
		free_camera.global_position = _get_focus_position() + Vector3(0.0, 20.0, 0.0)

	_free_camera = free_camera
	_free_camera_active = true
	_sync_free_camera_angles()
	_force_current_camera(_free_camera)


func _place_free_camera_behind_bridge_officer(
		free_camera: Camera3D,
		source_camera: Camera3D,
		officer: Node3D
) -> void:
	var rear_direction := source_camera.global_basis.z
	rear_direction.y = 0.0
	if rear_direction.length_squared() < 0.0001:
		rear_direction = officer.global_basis.z
		rear_direction.y = 0.0
	rear_direction = rear_direction.normalized()
	var focus_position := officer.global_position \
		+ Vector3.UP * bridge_free_camera_focus_height_m
	free_camera.global_position = focus_position \
		+ rear_direction * bridge_free_camera_rear_distance_m \
		+ Vector3.UP * bridge_free_camera_above_focus_m
	free_camera.look_at(focus_position, Vector3.UP)

func begin_photo_mode_camera() -> bool:
	if _photo_mode_camera_active:
		return _free_camera_active

	_photo_mode_camera_active = true
	_photo_mode_started_free_camera = not _free_camera_active
	if _photo_mode_started_free_camera:
		# The scene tree remains paused in photo mode, so retaining the current
		# player-control assignment cannot make the aircraft fly unattended.
		_enter_free_camera(true)

	if not _free_camera_active:
		_photo_mode_camera_active = false
		_photo_mode_started_free_camera = false
		return false
	return true

func end_photo_mode_camera() -> void:
	if not _photo_mode_camera_active:
		return

	var should_exit_free_camera := _photo_mode_started_free_camera
	_photo_mode_camera_active = false
	_photo_mode_started_free_camera = false
	if should_exit_free_camera:
		_exit_free_camera()

func is_photo_mode_camera_active() -> bool:
	return _photo_mode_camera_active

func is_free_camera_active() -> bool:
	return _free_camera_active

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
	var raw_len := move_input.length()
	if raw_len > 1.0:
		move_input /= raw_len  # clamp to unit circle, then ramp below
		raw_len = 1.0
	# Exponential ramp: small deflections → very slow; full stick → full speed.
	var ramped_len := pow(raw_len, 2.5)
	var move_dir := move_input / maxf(raw_len, 0.0001)
	move_input = move_dir * ramped_len

	var move_vector := (_free_camera.global_basis.x * move_input.x) + ((-_free_camera.global_basis.z) * move_input.y)
	
	var vertical_input := Input.get_action_strength("yaw_right") - Input.get_action_strength("yaw_left")
	var vertical_move := Vector3.UP * vertical_input * 10.0
	
	_free_camera.global_position += (move_vector * free_camera_max_speed_mps + vertical_move) * delta

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
	if camera == _aircraft_transition_camera and not _aircraft_transition_active:
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
	var provider := _get_bridge_camera_provider()
	if provider != null and provider.has_method("get_camera"):
		var cam: Variant = provider.call("get_camera")
		if is_instance_valid(cam) and cam is Camera3D:
			return cam as Camera3D
	return null

func _get_bridge_camera_provider() -> Node:
	for node in get_tree().get_nodes_in_group("carrier_cam"):
		if node != null and node.has_method("get_camera"):
			return node
	return null

func _get_bridge_view_mode_count() -> int:
	var provider := _get_bridge_camera_provider()
	if provider != null and provider.has_method("get_view_mode_count"):
		return maxi(int(provider.call("get_view_mode_count")), 1)
	return 1

func _cycle_bridge_view() -> void:
	var mode_count: int = _get_bridge_view_mode_count()
	carrier_cam_mode = (carrier_cam_mode + 1) % mode_count
	var bridge_cam := _activate_bridge_camera_mode(carrier_cam_mode)
	if is_instance_valid(bridge_cam):
		_force_current_camera(bridge_cam)

func _activate_bridge_camera_mode(mode: int) -> Camera3D:
	var provider := _get_bridge_camera_provider()
	if provider == null:
		return null
	if provider.has_method("activate_view_mode"):
		var activated: Variant = provider.call("activate_view_mode", mode)
		if is_instance_valid(activated) and activated is Camera3D:
			return activated as Camera3D
	if provider.has_method("get_camera_for_mode"):
		var camera_for_mode: Variant = provider.call("get_camera_for_mode", mode)
		if is_instance_valid(camera_for_mode) and camera_for_mode is Camera3D:
			return camera_for_mode as Camera3D
	if provider.has_method("get_camera"):
		var camera: Variant = provider.call("get_camera")
		if is_instance_valid(camera) and camera is Camera3D:
			return camera as Camera3D
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
	var test_a = load("res://Audio/engine/fixed_wing/airplane_propeller 1.wav")
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

func _spawn_wind_turbine_at_free_camera() -> void:
	if not is_instance_valid(_free_camera):
		return
	if WIND_TURBINE_SCENE == null:
		push_error("FlightDirector: could not load wind turbine scene")
		return

	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else self
	var turbine := WIND_TURBINE_SCENE.instantiate() as Node3D
	if turbine == null:
		return
	scene_root.add_child(turbine)
	var spawn_pos: Vector3 = _get_ground_position_below(_free_camera.global_position)
	turbine.global_position = spawn_pos
	print("[FlightDirector] Spawned wind turbine at grounded free camera position %s" % str(turbine.global_position))

func _get_ground_position_below(world_pos: Vector3) -> Vector3:
	var grounded_pos: Vector3 = world_pos
	var viewport := get_viewport()
	if viewport != null and viewport.world_3d != null:
		var world_3d: World3D = viewport.world_3d
		var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
		var ray_from: Vector3 = world_pos + Vector3.UP * 2000.0
		var ray_to: Vector3 = world_pos - Vector3.UP * 4000.0
		var params := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		params.collide_with_areas = false
		var hit: Dictionary = space_state.intersect_ray(params)
		if not hit.is_empty():
			var hit_pos: Variant = hit.get("position", world_pos)
			if hit_pos is Vector3:
				return hit_pos
	if TerrainNavGrid.is_ready():
		var terrain_y: float = TerrainNavGrid.sample_height(world_pos.x, world_pos.z)
		if terrain_y > TerrainNavGrid.IMPASSABLE * 0.5:
			grounded_pos.y = terrain_y
	return grounded_pos

func _spawn_debug_exploded_aircraft5() -> void:
	if not is_instance_valid(_free_camera):
		return
	var packed := load("res://Models/Aircraft_5/aircraft_5_exploded.glb") as PackedScene
	if packed == null:
		push_error("FlightDirector: could not load aircraft_5_exploded.glb")
		return

	var root := packed.instantiate() as Node3D
	if root == null:
		return

	# Spawn 10m in front of the free camera
	var spawn_pos: Vector3 = _free_camera.global_position + (-_free_camera.global_basis.z) * 25.0
	var scene_root := get_tree().current_scene
	scene_root.add_child(root)
	root.global_position = spawn_pos

	var parts: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			parts.append(child as MeshInstance3D)

	var part_mass: float = maxf(900.0 / maxf(parts.size(), 1), 5.0)

	for mesh_inst in parts:
		var world_xform: Transform3D = mesh_inst.global_transform
		var aabb: AABB = mesh_inst.get_aabb()

		root.remove_child(mesh_inst)

		var rb := RigidBody3D.new()
		rb.mass = part_mass
		rb.collision_layer = 0
		rb.collision_mask = 513  # layer 1 (default) + layer 10 (terrain)
		var phys_mat := PhysicsMaterial.new()
		phys_mat.bounce = 0.6
		phys_mat.friction = 0.3
		rb.physics_material_override = phys_mat

		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size.abs()
		col.shape = box
		rb.add_child(col)

		mesh_inst.transform = Transform3D.IDENTITY
		rb.add_child(mesh_inst)

		scene_root.add_child(rb)
		rb.global_transform = world_xform

		rb.linear_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(0.5, 3.0), randf_range(-2.0, 2.0))
		rb.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))

		var t := get_tree().create_timer(30.0)
		t.timeout.connect(func(): if is_instance_valid(rb): rb.queue_free())

	root.queue_free()
