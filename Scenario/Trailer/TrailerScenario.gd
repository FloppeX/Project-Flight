extends Node
## Scene-owned director. The baseline is restored by the ordinary campaign loader.
const Timeline = preload("res://Scenario/Trailer/TrailerTimeline.gd")
const TIMELINE_PATH := "res://Scenario/Trailer/timeline.json"
var timeline := Timeline.new()
var anchor := Transform3D.IDENTITY
var ready_to_run := false
var started := false
var status := "Restoring baseline…"
var _packed: Dictionary = {}
var spawned_events: Dictionary = {}
var launch_requests: Array[Dictionary] = []
var _pending_launch_orders: Array[Dictionary] = []
var battle: RefCounted
var _label: Label
var _restarting := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Stage time-zero orders before normal deck physics can start idle cleanup.
	process_physics_priority = -100
	add_to_group("origin_shifter")
	add_to_group("trailer_scenario")
	DirectVideoCapture.capture_started.connect(_on_video_started)
	DirectVideoCapture.capture_stopped.connect(_on_video_stopped)
	SaveGameManager.campaign_loaded.connect(_on_baseline_loaded)
	SaveGameManager.save_failed.connect(_on_restore_failed)
	var canvas := CanvasLayer.new()
	canvas.layer = 30
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(20, 104)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_outline_size", 6)
	canvas.add_child(_label)
	add_child(load("res://Scenario/Trailer/TrailerAircraftCameras.gd").new())

func _on_baseline_loaded(_path: String) -> void:
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null:
		_on_restore_failed("Carrier missing")
		return
	# Fixed starting frame, not a target that moves with the carrier later.
	anchor = Transform3D(Basis(Vector3.UP, carrier.global_rotation.y), carrier.global_position)
	get_tree().paused = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIMELINE_PATH))
	if not timeline.configure(data):
		_on_restore_failed(timeline.error)
		return
	for event in timeline.events:
		if event.action != "spawn": continue
		var path := str(event.scene)
		if not _packed.has(path):
			var packed := load(path) as PackedScene
			if packed == null:
				_on_restore_failed("Could not load %s" % path)
				return
			_packed[path] = packed
	if data.get("startup") is Dictionary:
		battle = load("res://Scenario/Trailer/TrailerBattleSetup.gd").new()
		status = "Setting up the ground battle…"
		if not await battle.setup(self, data.startup):
			_on_restore_failed(str(battle.error))
			return
	# Issue time-zero orders after actors exist, before F6 starts simulation.
	for event in timeline.advance(0.0): _dispatch(event)
	ready_to_run = true
	status = "READY — Space pause/play · AltGr record + play/stop + pause · F7 restart"
	print("[Trailer] READY baseline=%s events=%d anchor=%s" % [_path, timeline.events.size(), anchor.origin])

func _on_restore_failed(message: String) -> void:
	ready_to_run = false
	status = "ERROR — %s" % message
	get_tree().paused = true
	push_error("[Trailer] %s" % message)

func _process(_delta: float) -> void:
	# Do not burn the director overlay into Recording Mode exports.
	_label.visible = not RecordingMode.active
	_label.text = "TRAILER  %05.1fs  %s\n%s" % [timeline.elapsed, "PAUSED" if get_tree().paused else "RUNNING", status]

func _on_video_started() -> void:
	if not ready_to_run: return
	started = true
	get_tree().paused = false

func _on_video_stopped() -> void:
	if ready_to_run: get_tree().paused = true

func toggle_pause() -> void:
	if not ready_to_run: return
	started = true
	get_tree().paused = not get_tree().paused

func toggle_recording() -> void:
	if ready_to_run: DirectVideoCapture.toggle_capture()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	if RecordingMode.active or PauseMenu.visible or PauseMenu.is_photo_mode_active(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	# AltGr is right Alt, including Windows' accompanying synthetic Ctrl flag.
	# Do not interpret left Ctrl+Alt as the recording key.
	if key == KEY_ALT and event.location == KEY_LOCATION_RIGHT:
		if event.pressed and not event.echo: toggle_recording()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_SPACE and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.pressed and not event.echo: toggle_pause()
		get_viewport().set_input_as_handled()
		return
	_unhandled_key_input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.ctrl_pressed or event.alt_pressed or event.shift_pressed or event.meta_pressed:
		return
	if RecordingMode.active or PauseMenu.visible or PauseMenu.is_photo_mode_active(): return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_F6:
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif key == KEY_F7:
		# Reload removes this director from the tree immediately.
		get_viewport().set_input_as_handled()
		restart()

func restart() -> void:
	if _restarting: return
	if DirectVideoCapture.recording or DirectVideoCapture.finalizing:
		status = "Stop video and wait for encoding before restarting."
		return
	if RecordingMode.recording or RecordingMode.replay:
		status = "Stop recording / leave replay before restarting. Save the take first."
		return
	var result := SaveGameManager.prepare_trailer_scenario()
	if not bool(result.get("ok", false)):
		_on_restore_failed(str(result.get("message")))
		return
	_restarting = true
	get_tree().paused = false
	LoadingScreen.begin_scenario_load()
	get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	if not ready_to_run or not started or get_tree().paused: return
	# Deck retrieval uses asynchronous waits. Do not start those while staging:
	# time spent framing a shot before F6 must not advance the launch machinery.
	for order in _pending_launch_orders: _request_launch(order)
	_pending_launch_orders.clear()
	if battle != null: battle.tick()
	for event in timeline.advance(delta):
		_dispatch(event)

func apply_origin_shift(offset: Vector3) -> void:
	anchor.origin -= offset

func _dispatch(event: Dictionary) -> void:
	print("[Trailer] EVENT id=%s scheduled=%.3f actual=%.3f action=%s" % [event.id, event.time, timeline.elapsed, event.action])
	status = "%s · Space pause · AltGr record · F7 restart" % str(event.get("text", event.id))
	match event.action:
		"launch":
			if get_tree().paused:
				_pending_launch_orders.append(event)
			else:
				_request_launch(event)
		"spawn":
			_spawn(event)

func _request_launch(event: Dictionary) -> void:
	var deck := get_tree().get_first_node_in_group("flight_deck_manager")
	var accepted := int(deck.call("queue_ai_flight", int(event.count), self, str(event.get("loadout_profile", "")), str(event.get("aircraft_model", "")))) if deck != null else 0
	launch_requests.append({"id": event.id, "accepted": accepted, "requested": int(event.count)})
	if accepted != int(event.count):
		status = "Launch requested %d, accepted %d — check hangar/deck" % [int(event.count), accepted]
	print("[Trailer] LAUNCH accepted=%d requested=%d" % [accepted, int(event.count)])

func _spawn(event: Dictionary) -> void:
	var position_values: Array = event.position
	var position := anchor * Vector3(position_values[0], position_values[1], position_values[2])
	var terrain := TerrainReference.get_terrain_node()
	if terrain == null or not terrain.has_method("get_height"):
		_on_restore_failed("No terrain provider for %s" % event.id)
		return
	var terrain_y := float(terrain.call("get_height", position))
	if not is_finite(terrain_y):
		_on_restore_failed("Invalid terrain at %s" % event.id)
		return
	if event.kind == "ground":
		position.y = terrain_y + float(position_values[1])
	elif position.y < terrain_y + 30.0:
		_on_restore_failed("%s aircraft position intersects terrain; edit its height" % event.id)
		return
	var vehicle := (_packed[str(event.scene)] as PackedScene).instantiate() as Node3D
	if vehicle == null:
		_on_restore_failed("Not a 3D vehicle: %s" % event.scene)
		return
	vehicle.name = "Trailer_%s" % event.id
	vehicle.set_meta("trailer_event_id", event.id)
	vehicle.set_meta("source_scene_path", event.scene)
	if "team" in vehicle: vehicle.set("team", int(event.team))
	var basis := anchor.basis * Basis(Vector3.UP, deg_to_rad(float(event.get("heading_deg", 0))))
	get_tree().current_scene.add_child(vehicle)
	vehicle.global_transform = Transform3D(basis, position)
	if vehicle is RigidBody3D:
		vehicle.linear_velocity = basis.z * float(event.get("speed_mps", 0))
		PhysicsServer3D.body_set_state(vehicle.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, vehicle.global_transform)
	vehicle.reset_physics_interpolation()
	spawned_events[str(event.id)] = {"time": timeline.elapsed, "position": position, "vehicle": weakref(vehicle)}
	# Some ground scenes author a default allegiance group in _ready(). Team is
	# already assigned before tree entry; reconcile the generic target groups too.
	vehicle.remove_from_group("friendlies" if int(event.team) == 2 else "enemies")
	vehicle.add_to_group("enemies" if int(event.team) == 2 else "friendlies")
	print("[Trailer] SPAWN id=%s position=%s team=%d" % [event.id, position, int(event.team)])
	if event.kind == "aircraft": _activate_aircraft(vehicle, int(event.team))
	elif vehicle.has_method("set_patrol_waypoints"):
		# Explicit initial holding point; normal local combat remains enabled.
		var points: Array[Vector3] = [position]
		vehicle.call("set_patrol_waypoints", points)

func _activate_aircraft(vehicle: Node3D, team: int) -> void:
	# Aircraft._ready() completes its group registration one frame late.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(vehicle) or not is_inside_tree(): return
	vehicle.remove_from_group("aircraft")
	vehicle.remove_from_group("friendlies" if team == 2 else "enemies")
	vehicle.add_to_group("enemies" if team == 2 else "friendlies")
	vehicle.add_to_group("ai_aircraft")
	var gear := vehicle.find_child("ControlLandingGear", true, false)
	if gear != null:
		gear.call("send_to_landing_gears", "stow")
		if gear.has_method("send_to_tailhooks"): gear.call("send_to_tailhooks", "stow")
		if gear.has_method("send_to_tailhook_simple"): gear.call("send_to_tailhook_simple", false)
		if "gear_down_state" in gear: gear.set("gear_down_state", false)
		if gear.has_method("_set_collider_disabled"): gear.call("_set_collider_disabled", true)
	var toggle := vehicle.get_node_or_null("AIToggle")
	if toggle != null: toggle.call("enable_ai")
	if team == 1: FlightDirector.register_aircraft(vehicle as RigidBody3D)

func notify_aircraft_launched(_pilot: Node) -> void:
	if battle != null: battle.on_launched(_pilot)
	print("[Trailer] Aircraft physically launched at %.3fs" % timeline.elapsed)
