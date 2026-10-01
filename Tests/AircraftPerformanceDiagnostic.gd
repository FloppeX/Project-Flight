extends Node3D

class FlatTerrain:
	extends Node3D
	func get_height(_position: Vector3) -> float: return 0.0

## Rendered diagnostic; run without --headless. Uses real aircraft scenes with
## dormant cockpits. Rendering phases freeze simulation; simulation phases hide
## the same fleet. No campaign/save data is loaded or modified.
var fleet: Array[RigidBody3D] = []
var meshes: Array[MeshInstance3D] = []
var camera: Camera3D
var results: Array = []
var mesh_biases: Array[float] = []
var count := 16
var output := "res://logs/aircraft_performance_diagnostic.json"

func _ready() -> void:
	for key in ["FlightDirector", "AirOpsManager", "EnemyOpsManager", "GroundOpsManager", "OperationsCoordinator", "TerrainNavGrid", "EnemyBaseManager"]:
		get_node("/root/" + key).process_mode = Node.PROCESS_MODE_DISABLED
	get_node("/root/FloatingOrigin").set("enabled", false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fleet-count="): count = clampi(int(arg.get_slice("=", 1)), 1, 64)
		elif arg.begins_with("--output="): output = arg.get_slice("=", 1)
	call_deferred("run")

func run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var terrain := FlatTerrain.new()
	add_child(terrain)
	terrain.add_to_group("terrain_provider")
	get_node("/root/TerrainReference").terrain_node = terrain
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -20, 0)
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(0, 300, 0)
	camera.far = 10000
	camera.fov = 70
	add_child(camera)
	camera.make_current()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var budget := get_node("/root/EnemyVisualBudget")
	for i in count:
		var id: int = [10, 13, 15][i % 3]
		var craft := load("res://Aircraft/Aircraft_%d.tscn" % id).instantiate() as RigidBody3D
		craft.position = Vector3((i % 4 - 1.5) * 110, 220 + (i / 4) * 60, -1400)
		craft.freeze = true
		budget.prepare_ai_aircraft_for_tree_entry(craft)
		add_child(craft)
		await get_tree().process_frame
		craft.get_node("AIToggle").enable_ai()
		var pilot = craft.get_node("HelicopterPilot")
		pilot.command_hover(craft.position)
		craft.process_mode = Node.PROCESS_MODE_DISABLED
		fleet.append(craft)
	camera.make_current()
	await get_tree().process_frame
	for craft in fleet:
		budget._apply_budget_to_unit(craft, camera)
		for node in craft.find_children("*", "MeshInstance3D", true, false):
			meshes.append(node)
			mesh_biases.append(node.lod_bias)
	budget.process_mode = Node.PROCESS_MODE_DISABLED
	print("AIRCRAFT_PERF fleet=", count, " meshes=", meshes.size(), " driver=", RenderingServer.get_current_rendering_driver_name())
	for craft in fleet: craft.visible = false
	await measure("empty_view")
	for craft in fleet: craft.visible = true
	# ABBA ordering reduces warm-up and clock drift bias.
	for bias in [1.0, 0.2, 0.2, 1.0]:
		for i in meshes.size(): meshes[i].lod_bias = mesh_biases[i] * bias
		await measure("mesh_bias_" + str(bias))
	for craft in fleet:
		craft.visible = false
		craft.process_mode = Node.PROCESS_MODE_INHERIT
		var pilot: Node = craft.get_node("HelicopterPilot")
		var engine: Node = pilot.get("engine")
		var trim := float(pilot.call("_get_collective_trim"))
		engine.set("is_engine_working", true)
		engine.set("current_power", trim)
		engine.set("target_power", trim)
		pilot.set("_collective_cmd", trim)
		(pilot.get("control_engine") as Node).call("set_target_power", trim)
		craft.set_meta("parking_brake", false)
		craft.freeze = false
	await measure("hidden_fleet_simulation")
	var report := {"fleet": count, "meshes": meshes.size(), "results": results,
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"window_size": str(DisplayServer.window_get_size()),
		"viewport_size": str(get_viewport().get_visible_rect().size),
		"gpu": RenderingServer.get_video_adapter_name(),
		"complete": results.all(func(row): return row.live_aircraft == count)}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("AIRCRAFT_PERF_DONE ", output)
	for craft in fleet:
		if not is_instance_valid(craft): continue
		budget.release_aircraft_cache(craft, true)
		craft.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if report.complete else 1)

func measure(label: String) -> void:
	await get_tree().create_timer(8.0 if label == "hidden_fleet_simulation" else 2.0).timeout
	FrameProfiler.consume_report_rows(100)
	var wall: Array[float] = []
	var sums := {"process_ms": 0.0, "physics_ms": 0.0, "draws": 0.0, "primitives": 0.0, "render_cpu_ms": 0.0, "render_gpu_ms": 0.0}
	var previous := Time.get_ticks_usec()
	var until := previous + 4000000
	while Time.get_ticks_usec() < until:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		wall.append((now - previous) * 0.001)
		previous = now
		sums.process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000
		sums.physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000
		sums.draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		sums.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		sums.render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		sums.render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	for key in sums: sums[key] /= maxf(wall.size(), 1)
	var total := 0.0
	for value in wall: total += value
	wall.sort()
	sums.label = label
	sums.live_aircraft = fleet.filter(func(craft): return is_instance_valid(craft)).size()
	sums.frame_ms = total / maxf(wall.size(), 1)
	sums.p95_ms = wall[int(wall.size() * 0.95)]
	sums.scopes = FrameProfiler.consume_report_rows(16)
	results.append(sums)
	print("AIRCRAFT_PERF_PHASE ", JSON.stringify(sums))
