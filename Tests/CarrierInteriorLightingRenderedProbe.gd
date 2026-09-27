extends SceneTree

const OUTPUT_DIR := "res://captures/carrier_interior_lighting_probe"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "CarrierInteriorLightingRenderedProbe"
	root.add_child(scene)
	current_scene = scene

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color("05080a")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color("9aabb1")
	environment_resource.ambient_light_energy = 0.35
	environment_resource.glow_enabled = true
	environment_resource.glow_normalized = true
	environment_resource.glow_intensity = 0.45
	environment_resource.glow_strength = 0.85
	environment_resource.glow_bloom = 0.05
	environment_resource.glow_hdr_threshold = 1.5
	environment_resource.glow_hdr_scale = 1.4
	environment_resource.glow_hdr_luminance_cap = 8.0
	environment.environment = environment_resource
	scene.add_child(environment)

	var carrier_scene := load("res://Models/LandCarrier/Land carrier 4.glb") as PackedScene
	if carrier_scene == null:
		push_error("[CarrierInteriorLightingRenderedProbe] carrier model unavailable")
		quit(1)
		return
	var carrier_model := carrier_scene.instantiate() as Node3D
	carrier_model.rotation.y = PI
	scene.add_child(carrier_model)

	var lighting_scene := load("res://LandCarrier/CarrierInteriorLighting.tscn") as PackedScene
	if lighting_scene == null:
		push_error("[CarrierInteriorLightingRenderedProbe] lighting scene unavailable")
		quit(1)
		return
	scene.add_child(lighting_scene.instantiate())

	var station_scene := load("res://Models/computer station.glb") as PackedScene
	if station_scene == null:
		push_error("[CarrierInteriorLightingRenderedProbe] computer station model unavailable")
		quit(1)
		return
	_add_station(scene, station_scene, Vector3(-22.357641, 8.863214, 3.0476203), PI)
	_add_station(scene, station_scene, Vector3(-19.861603, 8.863214, 3.0476203), PI)
	_add_station(scene, station_scene, Vector3(-18.63801, 13.318354, -7.422716), -PI * 0.5)
	_add_station(scene, station_scene, Vector3(-18.63801, 13.318354, -5.030582), -PI * 0.5)
	await process_frame
	_print_vertical_surfaces(carrier_model, Vector2(-21.048, 1.22), "command_room_fixture")
	_print_vertical_surfaces(carrier_model, Vector2(-21.048, -6.296), "air_ops_fixture")

	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 72.0
	scene.add_child(camera)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await process_frame
	await process_frame

	camera.global_position = Vector3(-21.1, 10.35, -2.5)
	camera.look_at(Vector3(-21.1, 9.95, 3.25), Vector3.UP)
	await RenderingServer.frame_post_draw
	_save_frame("command_room_lit.png")

	camera.global_position = Vector3(-22.4, 14.75, -6.22)
	camera.look_at(Vector3(-18.2, 14.15, -6.22), Vector3.UP)
	await RenderingServer.frame_post_draw
	_save_frame("air_ops_lit.png")

	print(
		"[CarrierInteriorLightingRenderedProbe] PASS output=%s"
		% ProjectSettings.globalize_path(OUTPUT_DIR)
	)
	quit(0)


func _add_station(parent: Node3D, station_scene: PackedScene, position: Vector3, yaw: float) -> void:
	var station := station_scene.instantiate() as Node3D
	station.position = position
	station.rotation.y = yaw
	parent.add_child(station)


func _save_frame(file_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUTPUT_DIR, file_name]
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("[CarrierInteriorLightingRenderedProbe] could not save %s" % file_name)


func _print_vertical_surfaces(model_root: Node3D, world_xz: Vector2, label: String) -> void:
	var heights: Array[float] = []
	var mesh_nodes := model_root.find_children("*", "MeshInstance3D", true, false)
	for node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var triangle_count := int(
				(indices.size() if not indices.is_empty() else vertices.size()) / 3
			)
			for triangle_index in range(triangle_count):
				var triangle: Array[Vector3] = []
				for corner in range(3):
					var source_index := triangle_index * 3 + corner
					var vertex_index := indices[source_index] if not indices.is_empty() else source_index
					triangle.append(mesh_instance.to_global(vertices[vertex_index]))
				var height := _vertical_triangle_height(world_xz, triangle[0], triangle[1], triangle[2])
				if is_finite(height):
					heights.append(height)
	heights.sort()
	var unique_heights: Array[float] = []
	for height in heights:
		if unique_heights.is_empty() or absf(height - unique_heights[-1]) > 0.02:
			unique_heights.append(height)
	print("[CarrierInteriorLightingRenderedProbe] %s vertical_surfaces=%s" % [label, unique_heights])


func _vertical_triangle_height(point: Vector2, a: Vector3, b: Vector3, c: Vector3) -> float:
	var denominator := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(denominator) <= 0.000001:
		return INF
	var a_weight := ((b.z - c.z) * (point.x - c.x) + (c.x - b.x) * (point.y - c.z)) / denominator
	var b_weight := ((c.z - a.z) * (point.x - c.x) + (a.x - c.x) * (point.y - c.z)) / denominator
	var c_weight := 1.0 - a_weight - b_weight
	if a_weight < -0.0001 or b_weight < -0.0001 or c_weight < -0.0001:
		return INF
	return a.y * a_weight + b.y * b_weight + c.y * c_weight
