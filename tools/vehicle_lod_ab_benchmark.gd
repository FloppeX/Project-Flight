extends SceneTree

## Rendered A/B benchmark for ground-vehicle LOD. Run windowed, not headless:
## godot --windowed --resolution 1280x720 --path . --script tools/vehicle_lod_ab_benchmark.gd

const VEHICLE_SCENES: Array[String] = [
	"res://GroundVehicle/GroundVehicle.tscn",
	"res://GroundVehicle/vehicle_enemy_buggy.tscn",
	"res://GroundVehicle/vehicle_enemy_pickup.tscn",
	"res://GroundVehicle/vehicle_enemy_battle_bus.tscn",
	"res://GroundVehicle/vehicle_friendly_light.tscn",
]
const VEHICLE_COUNT := 30
const WARMUP_S := 1.5
const SAMPLE_S := 3.0

var _world: Node3D = null
var _camera: Camera3D = null
var _vehicles: Array[Node3D] = []
var _mesh_off_results: Array[Dictionary] = []
var _mesh_on_results: Array[Dictionary] = []
var _sim_off_results: Array[Dictionary] = []
var _sim_on_results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	_build_world()
	await _spawn_vehicles()
	print("[VehicleLODBenchmark] vehicles=%d renderer=%s" % [_vehicles.size(), RenderingServer.get_current_rendering_driver_name()])

	# Rendering comparison: same visible simulation, only mesh policy changes.
	_camera.look_at(Vector3(0.0, 2.0, -700.0), Vector3.UP)
	_set_simulation_lod(true)
	_set_mesh_lod(false)
	await _measure_phase("render_cache_warmup")
	for enabled in [false, true, true, false]:
		_set_mesh_lod(enabled)
		var result := await _measure_phase("mesh_%s" % ("on" if enabled else "off"))
		if enabled:
			_mesh_on_results.append(result)
		else:
			_mesh_off_results.append(result)

	# Simulation comparison: vehicles are behind the camera, so render work is absent.
	_camera.look_at(Vector3(0.0, 2.0, 700.0), Vector3.UP)
	_set_mesh_lod(true)
	for enabled in [false, true, true, false]:
		_set_simulation_lod(enabled)
		var result := await _measure_phase("simulation_%s" % ("on" if enabled else "off"))
		if enabled:
			_sim_on_results.append(result)
		else:
			_sim_off_results.append(result)

	_print_comparison("VISIBLE_MESH", _average_results(_mesh_off_results), _average_results(_mesh_on_results))
	_print_comparison("OFFSCREEN_SIM", _average_results(_sim_off_results), _average_results(_sim_on_results))
	_world.queue_free()
	await process_frame
	quit(0)

func _build_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_camera = Camera3D.new()
	_camera.far = 3000.0
	_camera.fov = 70.0
	_world.add_child(_camera)
	_camera.global_position = Vector3(0.0, 70.0, 0.0)
	_camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.38, 0.45)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.65, 0.65)
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	_world.add_child(environment_node)
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(2500.0, 1.0, 2500.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	floor_body.position = Vector3(0.0, -0.5, -600.0)
	_world.add_child(floor_body)
	var floor_visual := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(2500.0, 2500.0)
	floor_visual.mesh = floor_mesh
	floor_visual.position = Vector3(0.0, 0.01, -600.0)
	floor_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.24, 0.22, 0.18)
	floor_visual.material_override = floor_material
	_world.add_child(floor_visual)

func _spawn_vehicles() -> void:
	var packed_scenes: Array[PackedScene] = []
	for path in VEHICLE_SCENES:
		var packed := load(path) as PackedScene
		if packed != null:
			packed_scenes.append(packed)
	for i in range(VEHICLE_COUNT):
		var vehicle = packed_scenes[i % packed_scenes.size()].instantiate()
		_world.add_child(vehicle)
		var column := i % 6
		var row := i / 6
		vehicle.global_position = Vector3((float(column) - 2.5) * 42.0, 1.0, -300.0 - float(row) * 200.0)
		vehicle.rotation.y = float(i % 4) * PI * 0.5
		if "max_speed" in vehicle:
			vehicle.max_speed = 0.0
		if "acceleration" in vehicle:
			vehicle.acceleration = 0.0
		if "use_waypoint_pathfinding" in vehicle:
			vehicle.use_waypoint_pathfinding = false
		if "team" in vehicle:
			vehicle.team = 1
		for turret in vehicle.find_children("*", "TurretController", true, false):
			turret.team = 1
		_vehicles.append(vehicle)
	await process_frame
	await process_frame

func _set_mesh_lod(enabled: bool) -> void:
	for vehicle in _vehicles:
		vehicle.mesh_lod_enabled = enabled
		if vehicle._mesh_lod_controller != null:
			vehicle._mesh_lod_controller.force_refresh()

func _set_simulation_lod(enabled: bool) -> void:
	for vehicle in _vehicles:
		vehicle.performance_lod_enabled = enabled
		vehicle.multi_rate_vehicle_simulation_enabled = true
		vehicle._camera_visibility_timer_s = 0.0
		vehicle.reset_simulation_lod_schedule()
		for turret in vehicle.find_children("*", "TurretController", true, false):
			turret.performance_lod_enabled = enabled
			turret.multi_rate_tracking_enabled = true
			turret._targeting_visibility_timer_s = 0.0
			turret.reset_tracking_lod_schedule()

func _measure_phase(label: String) -> Dictionary:
	var warmup_end_us := Time.get_ticks_usec() + int(WARMUP_S * 1000000.0)
	while Time.get_ticks_usec() < warmup_end_us:
		await process_frame

	var frame_ms: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var render_objects: Array[float] = []
	var primitives: Array[float] = []
	var sample_end_us := Time.get_ticks_usec() + int(SAMPLE_S * 1000000.0)
	var last_frame_us := Time.get_ticks_usec()
	while Time.get_ticks_usec() < sample_end_us:
		await process_frame
		var now_us := Time.get_ticks_usec()
		frame_ms.append(float(now_us - last_frame_us) * 0.001)
		last_frame_us = now_us
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		render_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	var result := {
		"frame_ms": _mean(frame_ms),
		"frame_p95_ms": _percentile(frame_ms, 0.95),
		"fps": 1000.0 / maxf(_mean(frame_ms), 0.001),
		"process_ms": _mean(process_ms),
		"physics_ms": _mean(physics_ms),
		"draw_calls": _mean(draw_calls),
		"render_objects": _mean(render_objects),
		"primitives": _mean(primitives),
		"samples": frame_ms.size(),
	}
	print("[VehicleLODBenchmark] PHASE %s frame=%.3fms p95=%.3fms fps=%.1f process=%.3fms physics=%.3fms draws=%.0f objects=%.0f primitives=%.0f samples=%d" % [
		label,
		result.frame_ms,
		result.frame_p95_ms,
		result.fps,
		result.process_ms,
		result.physics_ms,
		result.draw_calls,
		result.render_objects,
		result.primitives,
		result.samples,
	])
	return result

func _average_results(results: Array[Dictionary]) -> Dictionary:
	var averaged := {}
	for key in ["frame_ms", "frame_p95_ms", "fps", "process_ms", "physics_ms", "draw_calls", "render_objects", "primitives"]:
		var values: Array[float] = []
		for result in results:
			values.append(float(result[key]))
		averaged[key] = _mean(values)
	return averaged

func _print_comparison(label: String, lod_off: Dictionary, lod_on: Dictionary) -> void:
	print("[VehicleLODBenchmark] RESULT %s off_frame=%.3fms on_frame=%.3fms frame_change=%+.1f%% off_physics=%.3fms on_physics=%.3fms physics_change=%+.1f%% off_draws=%.0f on_draws=%.0f draw_change=%+.1f%% off_primitives=%.0f on_primitives=%.0f primitive_change=%+.1f%%" % [
		label,
		lod_off.frame_ms,
		lod_on.frame_ms,
		_percent_change(lod_off.frame_ms, lod_on.frame_ms),
		lod_off.physics_ms,
		lod_on.physics_ms,
		_percent_change(lod_off.physics_ms, lod_on.physics_ms),
		lod_off.draw_calls,
		lod_on.draw_calls,
		_percent_change(lod_off.draw_calls, lod_on.draw_calls),
		lod_off.primitives,
		lod_on.primitives,
		_percent_change(lod_off.primitives, lod_on.primitives),
	])

func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(round((sorted.size() - 1) * percentile)), 0, sorted.size() - 1)
	return sorted[index]

func _percent_change(before: float, after: float) -> float:
	if absf(before) <= 0.000001:
		return 0.0
	return (after - before) / before * 100.0
