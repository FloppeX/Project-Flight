extends "res://Tests/FullScenarioFiveAircraftRecovery.gd"
## Visible, serial, repeating production RTB trials. No saved-game writes.

const MODELS := [1, 2, 5, 14]
var trial := 0
var active_id := 0
var subject: WeakRef
var display: Label
var test_camera: Camera3D
var camera_mode := "follow"
var totals := {}
var last_result := "Waiting for first aircraft"
var skip_requested := false
var max_trials := 0
var trial_timeout_s := 900.0
var initial_stock: Array = []
var batch_model := 0
var batch_case := {}

class Viewer extends Node:
	var runner: SceneTree
	func _process(delta: float) -> void: runner._update_view(delta)

func _run() -> void:
	label = "continuous_rtb_%s" % Time.get_datetime_string_from_system().replace(":", "-")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trials="): max_trials = maxi(int(arg.get_slice("=", 1)), 0)
		if arg.begins_with("--trial-timeout="): trial_timeout_s = maxf(float(arg.get_slice("=", 1)), 5.0)
		if arg.begins_with("--batch-model="): batch_model = int(arg.get_slice("=", 1))
	if batch_model != 0 and batch_model not in MODELS:
		push_error("Unsupported batch aircraft")
		quit(2)
		return
	for manager_name in ["EnemyOpsManager", "EnemyBaseManager"]:
		var manager := root.get_node(manager_name)
		manager.set("_disabled_for_test", true)
		manager.set_process(false)
		manager.set_physics_process(false)
	await super._run()

func _run_diagnostic_override() -> bool:
	DisplayServer.window_set_title("Continuous RTB - Aircraft 1 / 2 / 5 / 14")
	initial_stock = deck.stored_aircraft.duplicate(true)
	for model in MODELS: totals[model] = {"trials": 0, "stowed": 0, "failed": 0}
	if DisplayServer.get_name() != "headless": _build_view()
	while max_trials == 0 or trial < max_trials:
		await _fly_trial(batch_model if batch_model != 0 else MODELS[trial % MODELS.size()])
		trial += 1
		await create_timer(4.0, false).timeout
	super._finish("requested_trials_complete")
	return true

func _fly_trial(model: int) -> void:
	records.clear()
	live.clear()
	skip_requested = false
	stage = "spawning"
	var craft: RigidBody3D = load("res://Aircraft/Aircraft_%d.tscn" % model).instantiate()
	craft.name = "RTB_%d_Aircraft_%d" % [trial + 1, model]
	craft.freeze = true
	for key in ["parking_brake", "carrier_transport_mode", "controls_disabled"]:
		craft.set_meta(key, false)
	craft.position = carrier.global_position + Vector3.UP * 1500.0
	current_scene.add_child(craft)
	var pilot: Node = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	for i in 3: await physics_frame
	pilot.aircraft = craft
	pilot.carrier_position = carrier.global_position
	pilot._find_approach_waypoints()
	var frame: Dictionary = pilot._get_recovery_carrier_frame()
	var forward: Vector3 = frame.forward
	var right: Vector3 = frame.right
	# Each model gets both sides on successive rounds, with modest range variation.
	var round_index := trial / MODELS.size()
	var side := 1.0 if (int(round_index) + trial % 2) % 2 == 0 else -1.0
	var spawn_position: Vector3 = frame.origin - forward * (3200.0 + float(trial % 3) * 400.0) + right * side * 1400.0
	var terrain: Node = current_scene.get_node("LowPolyTerrainPrototype")
	spawn_position.y = maxf(float(frame.deck_y) + 500.0, terrain.get_height(spawn_position) + 400.0)
	var direction: Vector3 = (frame.origin - spawn_position).slide(Vector3.UP).normalized()
	var speed := maxf(float(pilot.stall_speed_mps) + 25.0, 75.0)
	if batch_model != 0:
		# Identical five arrival profiles for every model, five repetitions each.
		# Weather and controller evolution are live, not checkpoint-restored.
		var cases := [
			{"name": "near_outbound", "behind": 450.0, "lateral": 900.0, "height": 260.0, "speed": 60.0, "heading": 180.0},
			{"name": "standard_inbound", "behind": 3200.0, "lateral": 1400.0, "height": 500.0, "speed": 75.0, "heading": 0.0},
			{"name": "high_fast", "behind": 4500.0, "lateral": 1800.0, "height": 800.0, "speed": 100.0, "heading": 0.0},
			{"name": "crossing", "behind": 2200.0, "lateral": 2400.0, "height": 450.0, "speed": 80.0, "heading": 90.0},
			{"name": "low_return", "behind": 4000.0, "lateral": 700.0, "height": 300.0, "speed": 65.0, "heading": 0.0}]
		batch_case = cases[trial % cases.size()].duplicate()
		side = 1.0 if (int(trial / cases.size()) + trial % cases.size()) % 2 == 0 else -1.0
		batch_case["side"] = side
		batch_case["repeat"] = int(trial / cases.size()) + 1
		spawn_position = frame.origin - forward * float(batch_case.behind) + right * side * float(batch_case.lateral)
		spawn_position.y = _batch_spawn_height(frame, spawn_position, batch_case)
		direction = (frame.origin - spawn_position).slide(Vector3.UP).normalized().rotated(Vector3.UP, deg_to_rad(float(batch_case.heading) * side))
		speed = maxf(float(batch_case.speed), float(pilot.stall_speed_mps) + 15.0)
	craft.global_position = spawn_position
	craft.global_basis = Basis.looking_at(direction, Vector3.UP, true)
	craft.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(craft.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, craft.global_transform)
	craft.reset_physics_interpolation()
	craft.get_node("AIToggle").enable_ai()
	craft.freeze = false
	craft.linear_velocity = direction * speed
	PhysicsServer3D.body_set_state(craft.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, craft.linear_velocity)
	pilot.change_state(pilot.State.SEARCH)
	_on_launch(pilot)
	active_id = craft.get_instance_id()
	records[active_id]["initial_health"] = craft.current_health
	records[active_id]["missed_approaches"] = 0
	records[active_id]["strict_handoffs"] = 0
	records[active_id]["press_handoffs"] = 0
	subject = weakref(craft)
	recall_at = elapsed()
	stage = "recovering"
	totals[model].trials += 1
	air_ops.order_rtb(records[active_id].flight)
	_event("RTB_TRIAL", {"trial": trial + 1, "model": model, "side": side,
		"position": spawn_position, "speed_mps": speed, "order": "AirOps.order_rtb", "case": batch_case})
	while true:
		_sample()
		var record: Dictionary = records[active_id]
		if record.stowed or record.destroyed or record.unavailable: break
		# Never delete an aircraft out from under an active deck recovery job.
		if not record.caught and (skip_requested or elapsed() - recall_at >= trial_timeout_s): break
		await create_timer(1.0, false).timeout
	var result: Dictionary = records[active_id]
	var outcome := "STOWED" if result.stowed else ("LOST" if result.destroyed or result.unavailable else ("SKIPPED" if skip_requested else "TIMEOUT"))
	totals[model]["stowed" if result.stowed else "failed"] += 1
	last_result = "Aircraft %d: %s after %.0fs" % [model, outcome, elapsed() - recall_at]
	_event("RTB_TRIAL_RESULT", {"trial": trial + 1, "model": model, "outcome": outcome,
		"duration_s": elapsed() - recall_at, "record": result, "totals": totals, "case": batch_case})
	stage = "next aircraft"
	if is_instance_valid(craft):
		deck.release_landing_clearance(craft)
		craft.queue_free()
	await process_frame
	await process_frame
	# Keep the temporary test hangar from accumulating unlimited stored entries.
	deck.stored_aircraft.assign(initial_stock.duplicate(true))
	subject = null
	_write_status("RUNNING", last_result)

func _batch_spawn_height(frame: Dictionary, position: Vector3, profile: Dictionary) -> float:
	var terrain: Node = current_scene.get_node("LowPolyTerrainPrototype")
	return maxf(float(frame.deck_y) + float(profile.height), terrain.get_height(position) + 200.0)

func _sample() -> void:
	var previous := str(records.get(active_id, {}).get("state", ""))
	super._sample()
	if not records.has(active_id): return
	var record: Dictionary = records[active_id]
	if record.state == previous: return
	if record.state == "MISSED_APPROACH": record.missed_approaches += 1
	if record.state == "LANDING" and not record.caught:
		var pilot: Variant = live[active_id].pilot.get_ref()
		if is_instance_valid(pilot):
			record["press_handoffs" if pilot._recovery_press_final_active else "strict_handoffs"] += 1

func _event(kind: String, data: Dictionary, echo: bool = true) -> void:
	# Preserve every outcome/transition; five-second snapshots keep a long batch compact.
	if batch_model != 0 and kind == "SAMPLE" and int(elapsed()) % 5 != 0: return
	super._event(kind, data, echo)

func _build_view() -> void:
	var viewer := Viewer.new()
	viewer.runner = self
	viewer.process_mode = Node.PROCESS_MODE_ALWAYS
	current_scene.add_child(viewer)
	test_camera = Camera3D.new()
	test_camera.far = 30000.0
	test_camera.fov = 65.0
	viewer.add_child(test_camera)
	var canvas := CanvasLayer.new()
	canvas.layer = 200
	viewer.add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.scale = Vector2(1.5, 1.5)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	display = Label.new()
	display.add_theme_font_size_override("font_size", 19)
	box.add_child(display)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	for mode in ["Follow aircraft", "Carrier view", "Pause", "Skip aircraft"]:
		var button := Button.new()
		button.text = mode
		buttons.add_child(button)
		button.pressed.connect(func():
			if mode == "Follow aircraft": camera_mode = "follow"
			elif mode == "Carrier view": camera_mode = "carrier"
			elif mode == "Pause":
				paused = not paused
				button.text = "Resume" if paused else "Pause"
			elif mode == "Skip aircraft": skip_requested = true)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _update_view(_delta: float) -> void:
	if not is_instance_valid(carrier) or not is_instance_valid(test_camera): return
	var craft: Variant = subject.get_ref() if subject != null else null
	var target := carrier.global_position + Vector3.UP * 20.0
	var eye := target - carrier.global_basis.z * 130.0 + carrier.global_basis.x * 100.0 + Vector3.UP * 80.0
	if camera_mode == "follow" and is_instance_valid(craft):
		target = craft.global_position + craft.global_basis.z * 12.0
		eye = craft.global_position - craft.global_basis.z * 65.0 + craft.global_basis.x * 30.0 + Vector3.UP * 18.0
	var terrain: Node = current_scene.get_node("LowPolyTerrainPrototype")
	eye.y = maxf(eye.y, terrain.get_height(eye) + 8.0)
	test_camera.global_position = eye
	test_camera.look_at(target, Vector3.UP)
	test_camera.make_current()
	var state_name := stage
	var health := 0.0
	if records.has(active_id):
		state_name = records[active_id].state if stage == "recovering" else stage
		health = records[active_id].health
	var summary := ""
	for model in MODELS:
		summary += "  %d: %d/%d stowed" % [model, totals[model].stowed, totals[model].trials]
	display.text = "CONTINUOUS RTB  |  1 > 2 > 5 > 14\nTrial %d  |  Aircraft %d  |  %s\nElapsed %.0fs  |  Health %.0f%s\n%s\n%s" % [
		trial + 1, MODELS[trial % MODELS.size()], state_name, maxf(elapsed() - recall_at, 0.0), health,
		"  |  PAUSED" if paused else "", summary, last_result]

func _finish(reason: String) -> void:
	# The base one-shot scenario has a 30-minute watchdog; this requested soak is indefinite.
	if reason == "watchdog_timeout": return
	super._finish(reason)
