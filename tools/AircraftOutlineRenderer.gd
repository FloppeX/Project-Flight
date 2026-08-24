extends Node
## Renders consistent top-down aircraft silhouettes from the authored 3D models.
## Run with:
##   Godot --path <project> res://tools/AircraftOutlineRenderer.tscn

const RENDER_SIZE := 1024
const OUTPUT_SIZE := 512
const FRAME_PADDING_FRACTION := 0.08
const OUTLINE_RADIUS_PX := 5
const ROTOR_RING_WIDTH_PX := 3.0
const FILL_COLOR := Color("d9ded7")
const OUTLINE_COLOR := Color("251f1b")
const OUTPUT_DIRECTORY := "res://Images/Aircraft Outlines"

const JOBS: Array[Dictionary] = [
	{"name": "aircraft_1", "scene": "res://Models/Aircraft_1/Aircraft_1.glb"},
	{"name": "aircraft_2", "scene": "res://Models/Aircraft_2/Aircraft 2 body.glb"},
	{"name": "aircraft_3", "scene": "res://Models/Aircraft_3/Aircraft 3.glb"},
	{"name": "aircraft_4", "scene": "res://Models/Aircraft_4/aircraft_4.glb"},
	{"name": "aircraft_5", "scene": "res://Models/Aircraft_5/aircraft_5.glb"},
	{"name": "aircraft_6", "scene": "res://Models/Aircraft_6/aircraft_6.glb"},
	{"name": "aircraft_7", "scene": "res://Models/Aircraft_7/aircraft_7.glb"},
	{"name": "aircraft_8", "scene": "res://Models/Aircraft_8/aircraft_8.glb"},
	{
		"name": "aircraft_9",
		"scene": "res://Aircraft/Aircraft_9.tscn",
		"include_paths": ["aircraft_9"],
		"rotor_disc_paths": ["RotorAssembly/UpperRotor", "RotorAssembly/LowerRotor"],
	},
	{
		"name": "aircraft_10",
		"scene": "res://Aircraft/Aircraft_10.tscn",
		"include_paths": ["aircraft_10", "TailRotor"],
		"rotor_disc_paths": ["RotorAssembly/UpperRotor"],
	},
	{
		"name": "aircraft_11",
		"scene": "res://Aircraft/Aircraft_11.tscn",
		"include_paths": ["aircraft_11", "TailRotor"],
		"rotor_disc_paths": ["RotorAssembly/UpperRotor"],
	},
	{
		"name": "aircraft_12",
		"scene": "res://Aircraft/Aircraft_12.tscn",
		"include_paths": ["aircraft_12"],
		"rotor_disc_paths": ["RotorAssembly/UpperRotor", "RotorAssembly/LowerRotor"],
	},
]

const EXCLUDED_MESH_PATH_FRAGMENTS: Array[String] = [
	"hardpoint",
	"weapon",
	"rocket",
	"gun",
	"rotor disc",
	"hud",
	"instrument panel",
	"pilot",
	"landing gear",
]

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_render_jobs")


func _render_jobs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIRECTORY))
	for job in JOBS:
		await _render_job(job)
	if _failures.is_empty():
		print("[AircraftOutlineRenderer] PASS count=%d" % JOBS.size())
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[AircraftOutlineRenderer] %s" % failure)
	get_tree().quit(1)


func _render_job(job: Dictionary) -> void:
	var output_name := str(job.get("name", "aircraft"))
	var scene_path := str(job.get("scene", ""))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("could not load %s" % scene_path)
		return

	var viewport := SubViewport.new()
	viewport.name = "AircraftOutlineViewport"
	viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var model := packed.instantiate() as Node3D
	if model == null:
		_failures.append("%s did not instantiate as Node3D" % scene_path)
		viewport.queue_free()
		return
	_strip_runtime_behavior(model)
	viewport.add_child(model)
	var rotor_disc := _measure_rotor_disc(model, job)
	_prepare_silhouette_geometry(model, model, job)

	var bounds := _top_down_bounds(model)
	if not rotor_disc.is_empty():
		var rotor_center: Vector2 = rotor_disc.get("center", Vector2.ZERO)
		var rotor_radius := float(rotor_disc.get("radius", 0.0))
		var rotor_bounds := Rect2(
			rotor_center - Vector2.ONE * rotor_radius,
			Vector2.ONE * rotor_radius * 2.0
		)
		bounds = bounds.merge(rotor_bounds)
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001:
		_failures.append("%s has no renderable top-down bounds" % scene_path)
		viewport.queue_free()
		return

	var camera := Camera3D.new()
	camera.name = "TopDownCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(bounds.size.x, bounds.size.y) * (1.0 + FRAME_PADDING_FRACTION * 2.0)
	var target := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
	camera.position = target + Vector3(0.0, maxf(camera.size, 10.0), 0.0)
	viewport.add_child(camera)
	# Aircraft models use +Z as the nose direction. Make +Z screen-up.
	camera.look_at(target, Vector3(0.0, 0.0, 1.0))
	camera.current = true

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		_failures.append("%s produced no rendered image" % scene_path)
		viewport.queue_free()
		return

	rendered.convert(Image.FORMAT_RGBA8)
	rendered.resize(OUTPUT_SIZE, OUTPUT_SIZE, Image.INTERPOLATE_LANCZOS)
	var outlined := _make_outlined_silhouette(rendered)
	if not rotor_disc.is_empty():
		var rotor_center: Vector2 = rotor_disc.get("center", Vector2.ZERO)
		var rotor_center_global := model.global_transform * Vector3(rotor_center.x, 0.0, rotor_center.y)
		var rotor_center_render_px := camera.unproject_position(rotor_center_global)
		var output_scale := float(OUTPUT_SIZE) / float(RENDER_SIZE)
		var rotor_center_output_px := rotor_center_render_px * output_scale
		var rotor_radius_output_px := float(rotor_disc.get("radius", 0.0)) / camera.size * float(OUTPUT_SIZE)
		_add_rotor_ring_behind(outlined, rotor_center_output_px, rotor_radius_output_px)
	var output_path := OUTPUT_DIRECTORY.path_join("%s.png" % output_name)
	var save_error := outlined.save_png(output_path)
	if save_error != OK:
		_failures.append("could not save %s (error %d)" % [output_path, save_error])
	else:
		print("[AircraftOutlineRenderer] wrote %s" % ProjectSettings.globalize_path(output_path))
	viewport.queue_free()
	await get_tree().process_frame


func _strip_runtime_behavior(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.get_script() != null:
		node.set_script(null)
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	for child in node.get_children():
		_strip_runtime_behavior(child)


func _measure_rotor_disc(model_root: Node3D, job: Dictionary) -> Dictionary:
	var rotor_disc_paths: Array = job.get("rotor_disc_paths", [])
	if rotor_disc_paths.is_empty():
		return {}
	var rotor_nodes: Array[Node3D] = []
	var center_sum := Vector2.ZERO
	var root_inverse := model_root.global_transform.affine_inverse()
	for rotor_path_variant in rotor_disc_paths:
		var rotor_path := NodePath(str(rotor_path_variant))
		var rotor := model_root.get_node_or_null(rotor_path) as Node3D
		if rotor == null:
			_failures.append("%s is missing rotor disc node %s" % [str(job.get("name", "aircraft")), rotor_path])
			continue
		rotor_nodes.append(rotor)
		var center_in_root := root_inverse * rotor.global_position
		center_sum += Vector2(center_in_root.x, center_in_root.z)
	if rotor_nodes.is_empty():
		return {}
	var center := center_sum / float(rotor_nodes.size())
	var radius := 0.0
	for rotor in rotor_nodes:
		var rotor_meshes: Array[MeshInstance3D] = []
		_collect_visible_meshes(rotor, rotor_meshes)
		for mesh_instance in rotor_meshes:
			var mesh_aabb := mesh_instance.get_aabb()
			var mesh_to_root := root_inverse * mesh_instance.global_transform
			for x_side in range(2):
				for y_side in range(2):
					for z_side in range(2):
						var corner := mesh_aabb.position + Vector3(
							mesh_aabb.size.x * float(x_side),
							mesh_aabb.size.y * float(y_side),
							mesh_aabb.size.z * float(z_side)
						)
						var in_root := mesh_to_root * corner
						radius = maxf(radius, Vector2(in_root.x, in_root.z).distance_to(center))
	if radius <= 0.001:
		_failures.append("%s has no measurable rotor radius" % str(job.get("name", "aircraft")))
		return {}
	return {"center": center, "radius": radius}


func _prepare_silhouette_geometry(node: Node, model_root: Node, job: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var should_render := mesh_instance.visible and mesh_instance.mesh != null \
				and _mesh_is_included(model_root, mesh_instance, job)
		mesh_instance.visible = should_render
		if should_render:
			var material := StandardMaterial3D.new()
			material.resource_name = "Aircraft Outline Matte"
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color.WHITE
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_instance.material_override = material
	for child in node.get_children():
		_prepare_silhouette_geometry(child, model_root, job)


func _mesh_is_included(model_root: Node, mesh_instance: MeshInstance3D, job: Dictionary) -> bool:
	var relative_path := str(model_root.get_path_to(mesh_instance))
	var normalized_path := relative_path.to_lower()
	for fragment in EXCLUDED_MESH_PATH_FRAGMENTS:
		if fragment in normalized_path:
			return false
	var include_paths: Array = job.get("include_paths", [])
	if include_paths.is_empty():
		return true
	for include_path_variant in include_paths:
		var include_path := str(include_path_variant)
		if relative_path == include_path or relative_path.begins_with(include_path + "/"):
			return true
	return false


func _top_down_bounds(root: Node3D) -> Rect2:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	var found_point := false
	var root_inverse := root.global_transform.affine_inverse()
	var meshes: Array[MeshInstance3D] = []
	_collect_visible_meshes(root, meshes)
	for mesh_instance in meshes:
		var mesh_aabb := mesh_instance.get_aabb()
		var mesh_to_root := root_inverse * mesh_instance.global_transform
		for x_side in range(2):
			for y_side in range(2):
				for z_side in range(2):
					var corner := mesh_aabb.position + Vector3(
						mesh_aabb.size.x * float(x_side),
						mesh_aabb.size.y * float(y_side),
						mesh_aabb.size.z * float(z_side)
					)
					var in_root := mesh_to_root * corner
					var projected := Vector2(in_root.x, in_root.z)
					min_point = min_point.min(projected)
					max_point = max_point.max(projected)
					found_point = true
	if not found_point:
		return Rect2()
	return Rect2(min_point, max_point - min_point)


func _collect_visible_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.is_visible_in_tree() and mesh_instance.mesh != null:
			result.append(mesh_instance)
	for child in node.get_children():
		_collect_visible_meshes(child, result)


func _make_outlined_silhouette(source: Image) -> Image:
	var result := Image.create_empty(OUTPUT_SIZE, OUTPUT_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(OUTPUT_SIZE):
		for x in range(OUTPUT_SIZE):
			var fill_alpha := source.get_pixel(x, y).a
			var expanded_alpha := fill_alpha
			for offset_y in range(-OUTLINE_RADIUS_PX, OUTLINE_RADIUS_PX + 1):
				for offset_x in range(-OUTLINE_RADIUS_PX, OUTLINE_RADIUS_PX + 1):
					if offset_x * offset_x + offset_y * offset_y > OUTLINE_RADIUS_PX * OUTLINE_RADIUS_PX:
						continue
					var sample_x := x + offset_x
					var sample_y := y + offset_y
					if sample_x < 0 or sample_y < 0 or sample_x >= OUTPUT_SIZE or sample_y >= OUTPUT_SIZE:
						continue
					expanded_alpha = maxf(expanded_alpha, source.get_pixel(sample_x, sample_y).a)
			var outline_alpha := expanded_alpha
			var combined_alpha := fill_alpha + outline_alpha * (1.0 - fill_alpha)
			if combined_alpha <= 0.0001:
				result.set_pixel(x, y, Color.TRANSPARENT)
				continue
			var fill_weight := fill_alpha
			var outline_weight := outline_alpha * (1.0 - fill_alpha)
			var rgb := (
				FILL_COLOR * fill_weight
				+ OUTLINE_COLOR * outline_weight
			) / combined_alpha
			result.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, combined_alpha))
	return result


func _add_rotor_ring_behind(image: Image, center: Vector2, radius: float) -> void:
	var antialias_width := 1.0
	var half_width := ROTOR_RING_WIDTH_PX * 0.5
	var outer_radius := radius + half_width + antialias_width
	var min_x := maxi(0, int(floor(center.x - outer_radius)))
	var max_x := mini(image.get_width() - 1, int(ceil(center.x + outer_radius)))
	var min_y := maxi(0, int(floor(center.y - outer_radius)))
	var max_y := mini(image.get_height() - 1, int(ceil(center.y + outer_radius)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pixel_center := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance_from_ring := absf(pixel_center.distance_to(center) - radius)
			var coverage := clampf(half_width + antialias_width - distance_from_ring, 0.0, 1.0)
			if coverage <= 0.0:
				continue
			var existing := image.get_pixel(x, y)
			var ring_alpha := coverage * FILL_COLOR.a
			var ring_weight := ring_alpha * (1.0 - existing.a)
			var combined_alpha := existing.a + ring_weight
			if combined_alpha <= 0.0001:
				continue
			var existing_rgb := Color(existing.r, existing.g, existing.b, 1.0)
			var ring_rgb := Color(FILL_COLOR.r, FILL_COLOR.g, FILL_COLOR.b, 1.0)
			var rgb := (existing_rgb * existing.a + ring_rgb * ring_weight) / combined_alpha
			image.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, combined_alpha))
