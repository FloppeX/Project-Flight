extends Node3D
class FieldFixture:
	extends "res://POI/ResourceField.gd"
	func _validated_salvage_position(at: Vector3, variant: int) -> Dictionary:
		return {"collection": at, "wreck": at + Vector3.RIGHT * (float(SALVAGE_VARIANTS[variant].radius) + 7.0)}
class Collector:
	extends Node3D
	const CAPACITY := 160.0
	var cargo := {"corium": 0.0, "plasteel": 0.0}
	func cargo_total() -> float: return cargo.plasteel
	func can_extract() -> bool: return true
	func load_cargo(material: String, amount: float) -> float:
		var accepted := minf(amount, CAPACITY - cargo_total())
		cargo[material] += accepted
		return accepted

var failures: Array[String] = []
func _ready() -> void: _run.call_deferred()
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SCATTERED_SALVAGE_FAIL: " + message)
func checkpoint(field: Node) -> Dictionary:
	return SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(field.capture_save_state()))))

func _run() -> void:
	for node in get_tree().root.get_children():
		if node != self: node.process_mode = Node.PROCESS_MODE_DISABLED
	TerrainNavGrid._is_baked = false
	TerrainNavGrid._query_is_baked = false
	NavGraph._is_ready = false
	var field := FieldFixture.new()
	add_child(field)
	field.set_process(false)
	for frame in range(6): field._seed_salvage(Vector3.ZERO)
	var partial := checkpoint(field)
	check(not field._salvage_seeded and not field.sources.is_empty(), "partial placement can be checkpointed")
	field.restore_save_state(partial)
	for frame in range(150): field._seed_salvage(Vector3(9000, 0, 9000))
	check(field._salvage_seeded and field.sources.size() == 12, "twelve finite wreck sites survive interrupted placement without duplicates")
	var counts := [0, 0, 0]
	var total := 0.0
	for source in field.sources:
		counts[int(source.ruin_variant)] += 1
		total += float(source.materials.plasteel)
		check(source.materials.corium == 0.0 and not source.discovered, "ambient wrecks contain only plasteel and require scouting")
		var root: Node3D = field._visuals[int(source.id)]
		var wreck := root.get_child(root.get_child_count() - 1) as Node3D
		var radius := float(field.SALVAGE_VARIANTS[int(source.ruin_variant)].radius)
		var actual_radius := 0.0
		var lowest_point := INF
		check(not wreck.find_children("*", "CollisionShape3D", true, false).is_empty(), "authored ruin retains physical collision")
		for mesh: MeshInstance3D in wreck.find_children("*", "MeshInstance3D", true, false):
			var bounds: AABB = (wreck.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
			lowest_point = minf(lowest_point, bounds.position.y)
			for corner in range(8):
				var point := bounds.get_endpoint(corner)
				actual_radius = maxf(actual_radius, Vector2(point.x, point.z).length())
		check(actual_radius <= radius + 0.01, "placement footprint encloses authored ruin: %s needs %.2f m" % [source.label, actual_radius])
		if int(source.ruin_variant) != 1:
			check(absf(lowest_point) < 0.01, "authored Blender ruin is seated on the ground")
		check((source.position as Vector3).distance_to(source.wreck_position) >= radius + 6.99, "collection patch lies outside the ruin")
	check(counts == [4, 4, 4] and total == 2560.0, "balanced mix of both building ruins and vehicle wrecks")
	check(field.plasteel_overview(Vector3.ZERO).sites == 0, "undiscovered salvage is not leaked to planning")
	var source: Dictionary = field.sources[0]
	source.discovered = true
	var collector := Collector.new()
	add_child(collector)
	collector.position = source.position
	field.extract(int(source.id), 500.0, collector)
	check(collector.cargo.plasteel == 160.0 and source.materials.plasteel == 80.0, "cargo is limited and deducted from the wreck")
	field.restore_save_state(checkpoint(field))
	var saved_source: Dictionary = field.get_source(int(source.id))
	check(saved_source.materials.plasteel == 80.0 and saved_source.wreck_position.is_equal_approx(source.wreck_position) and is_equal_approx(saved_source.wreck_yaw, source.wreck_yaw), "partial stock and exact authored ruin pose persist")
	collector.cargo.plasteel = 0.0
	field.extract(int(source.id), 500.0, collector)
	field.add_ruin_source(int(source.salvage_seed_slot), int(source.ruin_variant), source.position, source.wreck_position, source.wreck_yaw)
	for frame in range(100): field._seed_salvage(Vector3(16000, 0, 16000))
	check(saved_source.materials.plasteel == 0.0 and field.sources.size() == 12, "spent ruins never refill or respawn through repeated registration or travel")
	var visual: Node3D = field._visuals[int(source.id)]
	for child in visual.get_children():
		if child is MeshInstance3D: check(not child.visible, "loose salvage disappears when exhausted")
	field.restore_save_state(checkpoint(field))
	saved_source = field.get_source(int(source.id))
	check(saved_source.materials.plasteel == 0.0 and field.plasteel_overview(Vector3.ZERO).sites == 0, "exhaustion survives JSON reload and stays unavailable for harvesting")
	var before: Vector3 = saved_source.wreck_position
	field.apply_origin_shift(Vector3(200, 0, -600))
	check(saved_source.wreck_position == before - Vector3(200, 0, -600), "wreck and collection location shift together")
	check(get_tree().get_nodes_in_group("buildings").is_empty(), "scattered ruins do not register live enemy buildings")
	collector.free()
	field.reset()
	await get_tree().process_frame
	if "--rendered" in OS.get_cmdline_user_args():
		await _render(field)
	field.free()
	print("SCATTERED_SALVAGE_%s %s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _render(field: Node) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("687579")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9c6cd")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("80715d")
	floor_mesh.material_override = material
	add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 48.0
	add_child(camera)
	camera.make_current()
	var harvester := preload("res://GroundVehicle/Harvester.tscn").instantiate() as Node3D
	add_child(harvester)
	harvester.set_physics_process(false)
	for variant in range(3):
		var at := Vector3(variant * 70.0 - 70.0, 0, 0)
		var wreck_at := at + Vector3.RIGHT * (float(field.SALVAGE_VARIANTS[variant].radius) + 7.0)
		field.add_ruin_source(variant, variant, at, wreck_at, 0.3)
		harvester.position = at + Vector3(-4.5, 1.02, 0)
		var arm := harvester.get_node("Body")
		arm.arm_target = arm.to_local(at)
		arm.arm_extended = true
		arm.suction = true
		for frame in range(360): arm._process(1.0 / 60.0)
		var focus := at.lerp(wreck_at, 0.5) + Vector3(0, 2.5, 0)
		camera.position = focus + Vector3(-19, 14, 28) * (1.3 if variant == 2 else 1.0)
		camera.look_at(focus)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://captures/plasteel_ruin_%d.png" % variant)
