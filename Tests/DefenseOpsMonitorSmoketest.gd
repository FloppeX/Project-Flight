extends SceneTree

const OPS := preload("res://LandCarrier/DefenseOps.gd")
var failures: Array[String] = []

class Gun:
	extends Node3D
	var current_target: Variant
	var defense_coordinator: Node
	var candidates: Array[Node3D] = []
	func get_defense_candidates() -> Array[Node3D]:
		return candidates
	func set_defense_assignment(coordinator: Node, target: Variant) -> void:
		defense_coordinator = coordinator
		current_target = target

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var targets: Array[Node3D] = []
	for index in range(2):
		var target := Node3D.new()
		target.add_to_group("enemies")
		target.position = Vector3(0, 10, 100 + 100 * index)
		world.add_child(target)
		root.get_node("WorldUnitIndex").call("register_unit", target)
		targets.append(target)
	var guns: Array[Gun] = []
	for index in range(4):
		var gun := Gun.new()
		if index == 3:
			gun.candidates.append(targets[0])
		else:
			gun.candidates.assign(targets)
		world.add_child(gun)
		guns.append(gun)
	var ops := OPS.new()
	ops.name = "DefenseOps"
	world.add_child(ops)
	ops.coordinate_defense()
	check(guns[3].current_target == targets[0], "constrained gun lost its only reachable target")
	var first_count := 0
	var assignments: Array = []
	for gun in guns:
		if gun.current_target == targets[0]:
			first_count += 1
		assignments.append(gun.current_target)
	check(first_count == 2, "four guns did not spread evenly across two threats")
	ops.coordinate_defense()
	for index in range(4):
		check(guns[index].current_target == assignments[index], "unchanged defense assignments oscillated")
	guns[3].candidates.clear()
	ops.coordinate_defense()
	check(guns[3].current_target == null, "unreachable target was retained")
	check(ops.get_available_targets().size() == 2, "camera roster omitted a detected contact")

	var rig := (load("res://LandCarrier/CarrierTargetCamera.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(rig)
	var monitor := (load("res://LandCarrier/MonitorStation.tscn") as PackedScene).instantiate() as Node3D
	world.add_child(monitor)
	var commander := (load("res://LandCarrier/Commander.tscn") as PackedScene).instantiate() as Node3D
	commander.set("computer_camera_transition_s", 0.0)
	commander.set("computer_screen_focus_s", 0.0)
	world.add_child(commander)
	await process_frame
	await process_frame
	commander.set_physics_process(false)
	var camera := commander.get_node("Camera3D") as Camera3D
	var anchor := monitor.get_node("InteractionTarget") as Node3D
	camera.global_position = anchor.global_position + anchor.global_basis.z * 2.0
	camera.look_at(anchor.global_position + Vector3.UP, Vector3.UP)
	check(float(monitor.call("get_interaction_score", camera)) == -INF, "look-away still offered monitor use")
	camera.look_at(anchor.global_position, Vector3.UP)
	check(float(monitor.call("get_interaction_score", camera)) > -INF, "looking at monitor did not offer use")
	var standing := camera.transform
	var use := InputEventJoypadButton.new()
	use.button_index = JOY_BUTTON_A
	use.pressed = true
	commander.call("_input", use)
	check(bool(commander.call("is_using_computer_station")), "A did not enter monitor")
	check(not bool(root.get_node("CarrierConsole").call("is_open")), "monitor opened tactical UI")
	check(camera.fov < 50, "monitor did not zoom into screen")
	var full_camera := rig.get_node("FullscreenMastCamera") as Camera3D
	var feed := rig.get_node("CarrierTargetCameraViewport") as SubViewport
	var hud := rig.get_node("MastCameraHUD") as CanvasLayer
	check(root.get_camera_3d() == full_camera and full_camera.get_viewport() == camera.get_viewport(), "mast did not take over the main-resolution viewport")
	check(feed.size == Vector2i(640, 360) and feed.render_target_update_mode == SubViewport.UPDATE_DISABLED, "full-screen use duplicated the scene render")
	check(hud.visible and (hud.get_child(0) as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "full-screen HUD is missing or intercepts input")
	var initial_yaw := float(rig.get("_free_yaw"))
	var stick_event := InputEventJoypadMotion.new()
	stick_event.axis = JOY_AXIS_LEFT_X
	stick_event.axis_value = 1.0
	Input.parse_input_event(stick_event.duplicate())
	Input.flush_buffered_events()
	monitor.call("update_station_control", 0.1)
	check(is_equal_approx(float(rig.get("_free_yaw")), initial_yaw), "left stick still steers mast camera")
	stick_event.axis_value = 0.0
	Input.parse_input_event(stick_event.duplicate())
	Input.flush_buffered_events()
	stick_event.axis = JOY_AXIS_RIGHT_X
	stick_event.axis_value = 1.0
	Input.parse_input_event(stick_event.duplicate())
	Input.flush_buffered_events()
	monitor.call("update_station_control", 0.1)
	check(float(rig.get("_free_yaw")) < initial_yaw, "right stick did not steer mast camera")
	stick_event.axis_value = 0.0
	Input.parse_input_event(stick_event.duplicate())
	Input.flush_buffered_events()
	var initial_basis := full_camera.global_basis
	rig.call("apply_manual_input", Vector2(1, -1), 1.0, 0.5)
	rig.set("_refresh_accumulator_s", 0.0)
	rig.call("_process", 0.01)
	check(not full_camera.global_basis.is_equal_approx(initial_basis), "mast aim still waits for the 15 Hz preview timer")
	check(float(rig.get("_free_yaw")) < initial_yaw and float(rig.get("_free_pitch")) > 0, "stick did not rotate/tilt mast camera")
	check(float(rig.get("_manual_fov")) < 52, "right trigger did not zoom in")
	var zoomed := float(rig.get("_manual_fov"))
	rig.call("apply_manual_input", Vector2.ZERO, -1.0, 0.5)
	check(float(rig.get("_manual_fov")) > zoomed, "left trigger did not zoom out")
	use.button_index = JOY_BUTTON_DPAD_RIGHT
	commander.call("_input", use)
	check(rig.get("current_target") == targets[0], "D-pad did not select DefenseOps contact")
	check(guns[0].current_target == assignments[0], "observation selection altered defense assignments")
	use.button_index = JOY_BUTTON_B
	commander.call("_input", use)
	check(not bool(commander.call("is_using_computer_station")), "B did not release monitor")
	check(camera.transform.is_equal_approx(standing), "B did not restore standing view")
	check(not bool(rig.get("_controlled")), "B retained mast control")
	check(root.get_camera_3d() == camera and not hud.visible, "B did not restore the room camera and hide mast HUD")
	# Also exercise real-duration transitions, cancellation, and repeated entry.
	commander.set("computer_camera_transition_s", 0.05)
	commander.set("computer_screen_focus_s", 0.05)
	var standing_fov := camera.fov
	use.button_index = JOY_BUTTON_A
	commander.call("_input", use)
	check(root.get_camera_3d() == camera, "mast activated before the screen zoom completed")
	await create_timer(0.25).timeout
	check(root.get_camera_3d() == full_camera, "completed zoom did not hand off to mast")
	use.button_index = JOY_BUTTON_B
	commander.call("_input", use)
	check(root.get_camera_3d() == camera, "back-out tween did not start at physical monitor")
	await create_timer(0.15).timeout
	check(camera.transform.is_equal_approx(standing) and is_equal_approx(camera.fov, standing_fov), "back-out tween failed to restore standing pose/FOV")
	check(feed.render_target_update_mode != SubViewport.UPDATE_DISABLED, "room preview did not resume after B")
	use.button_index = JOY_BUTTON_A
	commander.call("_input", use)
	use.button_index = JOY_BUTTON_B
	commander.call("_input", use)
	await create_timer(0.2).timeout
	check(root.get_camera_3d() == camera and not hud.visible, "cancelled entry activated a delayed fullscreen handoff")
	# External camera changes must retain ownership and release station controls.
	rig.call("begin_control")
	rig.call("begin_fullscreen_view")
	var external_camera := Camera3D.new()
	world.add_child(external_camera)
	external_camera.make_current()
	rig.call("_process", 0.01)
	check(root.get_camera_3d() == external_camera and not hud.visible and not bool(rig.get("_controlled")), "external camera takeover was overridden")
	camera.make_current()
	commander.set("computer_camera_transition_s", 0.0)
	commander.set("computer_screen_focus_s", 0.0)
	use.button_index = JOY_BUTTON_A
	commander.call("_input", use)
	monitor.queue_free()
	await process_frame
	await process_frame
	commander.call("_physics_process", 0.016)
	check(root.get_camera_3d() == camera and not hud.visible \
		and not bool(commander.call("is_using_computer_station")), "removed monitor stranded the player in mast view")
	# Exercise the actual turret controller contract, including its local scan.
	var real_mount := (load("res://LandCarrier/CarrierDefenseTurret.tscn") as PackedScene).instantiate()
	real_mount.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(real_mount)
	var real_gun := real_mount.get_node("TurretController")
	targets[0].add_to_group("enemies")
	check(bool(real_gun.call("can_engage_defense_target", targets[0])), "real turret rejected reachable hostile")
	real_gun.call("set_defense_assignment", ops, targets[0])
	real_gun.call("find_and_set_best_target")
	check(real_gun.get("current_target") == targets[0], "real turret local scan overrode DefenseOps")
	targets[0].position.z = 5000
	check(not bool(real_gun.call("can_engage_defense_target", targets[0])), "real turret accepted out-of-range target")
	targets[0].position.z = 100
	targets[0].remove_from_group("enemies")
	check(not bool(real_gun.call("can_engage_defense_target", targets[0])), "real turret accepted unidentified neutral")
	targets[0].queue_free()
	check(ops.get_available_targets().size() == 1, "queued-for-deletion contact remained available")
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("[DefenseOpsMonitorSmoketest] PASS coverage=true stable=true constraints=true screen_gaze=true A_B=true controls=true independent_observation=true fullscreen=true return_tween=true cancellation=true teardown=true")
	quit(0 if failures.is_empty() else 1)
