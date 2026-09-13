extends SceneTree

## Real rendered aircraft and FlightDirector transitions; frozen flight removes
## combat/control variance. This isolates presentation, not full-map streaming.
class BridgeProbe extends Node3D:
	var camera: Camera3D
	func get_camera() -> Camera3D: return camera
	func get_camera_for_mode(_mode: int) -> Camera3D: return camera
	func activate_view_mode(_mode: int) -> Camera3D:
		camera.current = true
		return camera
	func get_view_mode_count() -> int: return 1
	func is_control_room_camera(cam: Camera3D) -> bool: return cam == camera
	func is_carrier_camera(cam: Camera3D) -> bool: return cam == camera

var label := "baseline"
var rows: Array = []
var phase := "setup"
var last_us := 0
var recording := false
var director: Node
var failures: Array[String] = []
var phase_scopes: Dictionary = {}
var render_trace := preload("res://Tests/Fixtures/TransitionRenderTrace.gd").new()
var terrain: Node3D

func _initialize() -> void: call_deferred("_run")

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and last_us > 0:
		var ms := (now - last_us) / 1000.0
		var row := {"phase": phase, "time_us": now, "frame_ms": ms,
			"scopes": FrameProfiler.summarize_scope_events(last_us, now, 12) if ms > 25 else [],
			"render": render_trace.sample(),
			"transition_phase": int(director.get("_aircraft_transition_phase")),
			"transition_active": bool(director.call("is_aircraft_view_transition_active"))}
		if is_instance_valid(terrain): row["terrain"] = terrain.call("get_streaming_stats")
		rows.append(row)
	last_us = now
	return false

func _run() -> void:
	render_trace.attach(self)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.get_slice("=", 1)
	DisplayServer.window_set_title("Vehicle Transition Performance - " + label)
	for manager_name in ["AirOpsManager", "EnemyOpsManager", "GroundOpsManager", "OperationsCoordinator", "TerrainNavGrid", "NavGraph", "FloatingOrigin"]:
		var manager := root.get_node_or_null(manager_name)
		if manager: manager.process_mode = Node.PROCESS_MODE_DISABLED
	director = root.get_node("FlightDirector")
	director.set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.5, 0.65)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.8
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 25, 0)
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24000, 24000)
	ground.mesh = plane
	scene.add_child(ground)
	var bridge := BridgeProbe.new()
	scene.add_child(bridge)
	bridge.add_to_group("carrier_cam")
	bridge.position = Vector3(0, 60, 0)
	bridge.camera = Camera3D.new()
	bridge.add_child(bridge.camera)
	bridge.camera.current = true
	var craft_list: Array[RigidBody3D] = []
	for model in [1, 5, 11]:
		var craft := (load("res://Aircraft/Aircraft_%d.tscn" % model) as PackedScene).instantiate() as RigidBody3D
		craft.freeze = true
		craft.position = Vector3(200 + craft_list.size() * 300, 150, 100)
		if model == 5: craft.position = Vector3(8000, 600, 4000)
		root.get_node("EnemyVisualBudget").call("prepare_ai_aircraft_for_tree_entry", craft)
		scene.add_child(craft)
		craft.set("team", 1)
		for node_name in ["AIPilot", "HelicopterPilot", "AIToggle", "SimpleAero", "HelicopterFlight"]:
			var flight_node := craft.find_child(node_name, true, false)
			if flight_node: flight_node.process_mode = Node.PROCESS_MODE_DISABLED
		craft.set_physics_process(false)
		craft_list.append(craft)
	# Exclude resource loading / common pool startup from transition samples.
	await create_timer(4.0).timeout
	# Deferred AI startup may have released the initial freeze before disabling.
	for craft in craft_list:
		craft.freeze = true
		craft.linear_velocity = Vector3.ZERO
		craft.angular_velocity = Vector3.ZERO
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Engine.max_fps = 60
	# Window resize/render-target allocation is fixture setup, not a handoff.
	await create_timer(1.0).timeout
	director.set_process(true)
	FrameProfiler.set_report_capture_enabled(true, "transition_probe")
	FrameProfiler.configure_scope_event_capture(0.1, 4096)
	for pass_index in range(2):
		for i in range(craft_list.size()):
			phase = "%s_to_%d" % ["first" if pass_index == 0 else "repeat", [1,5,11][i]]
			print("TRANSITION_PROBE_BEGIN ", phase)
			var phase_started := Time.get_ticks_usec()
			recording = true
			director.call("_view_aircraft", craft_list[i])
			var deadline := Time.get_ticks_msec() + 15000
			while bool(director.call("is_aircraft_view_transition_active")) and Time.get_ticks_msec() < deadline:
				await process_frame
			if bool(director.call("is_aircraft_view_transition_active")): failures.append(phase + ":timeout")
			await create_timer(2.0).timeout
			var mount := craft_list[i].find_child("InstrumentPanel", true, false)
			if mount == null or mount.call("get_live_panel") == null: failures.append(phase + ":panel_missing")
			recording = false
			phase_scopes[phase] = FrameProfiler.summarize_scope_events(phase_started, Time.get_ticks_usec(), 30)
			print("TRANSITION_PROBE_END ", phase)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://transition_%s_%s.png" % [label, phase])
			# Quarantine GPU readback / PNG encoding from the next timing window.
			for _frame in range(3): await process_frame
		phase = "return_bridge_%d" % pass_index
		recording = true
		director.call("_begin_bridge_camera_transition", bridge.camera)
		var deadline := Time.get_ticks_msec() + 15000
		while bool(director.call("is_aircraft_view_transition_active")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if bool(director.call("is_aircraft_view_transition_active")): failures.append(phase + ":timeout")
		await create_timer(1.0).timeout
		recording = false
	var sources := {}
	for path in ["res://HUD/InstrumentPanelPool.gd", "res://HUD/instrument_panel.gd", "res://HUD/heads_up_display.gd", "res://HUD/PanelSurfaceCache.gd", "res://Tests/VehicleTransitionPerformance.gd", "res://Tests/Fixtures/TransitionRenderTrace.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var result := {"status": "COMPLETE" if failures.is_empty() else "FAILED", "failures": failures, "label": label, "renderer": RenderingServer.get_current_rendering_method(), "rows": rows, "sources": sources, "phase_scopes": phase_scopes,
		"pool": root.get_node("InstrumentPanelPool").call("get_pool_stats")}
	var file := FileAccess.open("user://transition_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("TRANSITION_PROBE_COMPLETE ", label)
	quit(0 if failures.is_empty() else 1)
