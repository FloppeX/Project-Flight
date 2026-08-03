extends SceneTree

const VEHICLE_COUNT := 30
const QUERY_PASSES := 120
const LOCAL_QUERY_RADIUS_M := 50.0
const VEHICLE_SCENES: Array[String] = [
	"res://GroundVehicle/vehicle_friendly_light.tscn",
	"res://GroundVehicle/vehicle_enemy_buggy.tscn",
	"res://GroundVehicle/vehicle_enemy_pickup.tscn",
	"res://GroundVehicle/vehicle_enemy_battle_bus.tscn",
]

var _world: Node3D = null
var _index: Node = null
var _vehicles: Array[Node3D] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_index = root.get_node_or_null("WorldUnitIndex")
	if _index == null:
		_fail("WorldUnitIndex autoload missing")
		return
	_build_world()
	await _spawn_vehicles()
	await create_timer(0.35).timeout

	var stats_before: Dictionary = _index.get_report_stats()
	if int(stats_before.get("units", 0)) < VEHICLE_COUNT:
		_fail("only %d/%d vehicles registered" % [int(stats_before.get("units", 0)), VEHICLE_COUNT])
		return

	var spacing_total: int = 0
	var turrets_with_targets: int = 0
	for vehicle in _vehicles:
		vehicle.call("_refresh_spacing_candidates")
		var spacing_value: Variant = vehicle.get("_cached_spacing_candidates")
		if spacing_value is Array:
			spacing_total += (spacing_value as Array).size()
		for turret_value in vehicle.find_children("*", "TurretController", true, false):
			var turret: Node = turret_value as Node
			turret.call("find_and_set_best_target")
			var target_value: Variant = turret.get("current_target")
			if target_value is Node3D and is_instance_valid(target_value):
				turrets_with_targets += 1

	var indexed_start_us: int = Time.get_ticks_usec()
	var indexed_result_count: int = 0
	for pass_idx in range(QUERY_PASSES):
		for vehicle in _vehicles:
			var nearby: Array = _index.query_nodes_in_groups(
				vehicle.global_position,
				LOCAL_QUERY_RADIUS_M,
				["ground_vehicles"],
				[],
				[vehicle]
			)
			indexed_result_count += nearby.size()
	var indexed_elapsed_ms: float = float(Time.get_ticks_usec() - indexed_start_us) * 0.001

	var naive_start_us: int = Time.get_ticks_usec()
	var naive_result_count: int = 0
	var all_ground: Array[Node] = get_nodes_in_group("ground_vehicles")
	var radius_sq: float = LOCAL_QUERY_RADIUS_M * LOCAL_QUERY_RADIUS_M
	for pass_idx in range(QUERY_PASSES):
		for vehicle in _vehicles:
			for other_value in all_ground:
				if other_value == vehicle or not (other_value is Node3D) or not is_instance_valid(other_value):
					continue
				if vehicle.global_position.distance_squared_to((other_value as Node3D).global_position) <= radius_sq:
					naive_result_count += 1
	var naive_elapsed_ms: float = float(Time.get_ticks_usec() - naive_start_us) * 0.001

	if indexed_result_count != naive_result_count:
		_fail("spatial query mismatch indexed=%d naive=%d" % [indexed_result_count, naive_result_count])
		return
	if spacing_total <= 0 or spacing_total >= VEHICLE_COUNT * (VEHICLE_COUNT - 1):
		_fail("spacing queries were not locally bounded: total=%d" % spacing_total)
		return
	if turrets_with_targets <= 0:
		_fail("no turret acquired a hostile through the index")
		return

	var stats_after: Dictionary = _index.get_report_stats()
	print("[WorldUnitIndexVehicleStress] PASS vehicles=%d spacing_candidates=%d turrets_targeting=%d indexed_queries=%d indexed_candidates=%d indexed_results=%d indexed_ms=%.3f naive_ms=%.3f" % [
		_vehicles.size(),
		spacing_total,
		turrets_with_targets,
		int(stats_after.get("queries", 0)) - int(stats_before.get("queries", 0)),
		int(stats_after.get("candidates", 0)) - int(stats_before.get("candidates", 0)),
		indexed_result_count,
		indexed_elapsed_ms,
		naive_elapsed_ms,
	])
	_world.queue_free()
	await process_frame
	quit(0)


func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "WorldUnitIndexVehicleStressWorld"
	root.add_child(_world)
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.global_position = Vector3(0.0, 120.0, 120.0)
	camera.look_at(Vector3(0.0, 0.0, -260.0), Vector3.UP)
	camera.current = true

	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(1200.0, 1.0, 1200.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	floor_body.position = Vector3(0.0, -0.5, -260.0)
	_world.add_child(floor_body)


func _spawn_vehicles() -> void:
	var scenes: Array[PackedScene] = []
	for scene_path in VEHICLE_SCENES:
		var scene := load(scene_path) as PackedScene
		if scene != null:
			scenes.append(scene)
	if scenes.is_empty():
		_fail("vehicle scenes failed to load")
		return
	for i in range(VEHICLE_COUNT):
		var scene_idx: int = 0 if i % 2 == 0 else 1 + ((i / 2) % maxi(scenes.size() - 1, 1))
		var vehicle := scenes[scene_idx].instantiate() as Node3D
		if vehicle == null:
			continue
		_world.add_child(vehicle)
		var column: int = i % 6
		var row: int = i / 6
		vehicle.global_position = Vector3((float(column) - 2.5) * 34.0, 1.2, -190.0 - float(row) * 38.0)
		if "max_speed" in vehicle:
			vehicle.set("max_speed", 0.0)
		if "acceleration" in vehicle:
			vehicle.set("acceleration", 0.0)
		if "use_waypoint_pathfinding" in vehicle:
			vehicle.set("use_waypoint_pathfinding", false)
		for turret_value in vehicle.find_children("*", "TurretController", true, false):
			(turret_value as Node).set_physics_process(false)
		_vehicles.append(vehicle)
	await process_frame
	await process_frame


func _fail(message: String) -> void:
	push_error("[WorldUnitIndexVehicleStress] FAIL: %s" % message)
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	quit(1)
