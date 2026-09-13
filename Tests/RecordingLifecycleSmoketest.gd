extends SceneTree
const Take = preload("res://Recording/SceneTake.gd")
const Focus = preload("res://Effects/VisualFocus.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var mode := root.get_node("RecordingMode")
	mode.process_mode = Node.PROCESS_MODE_ALWAYS
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var carrier := Node3D.new()
	scene.add_child(carrier)
	carrier.add_to_group("carrier")
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.make_current()
	mode.enter()
	var actors: Array[Node3D] = [carrier]
	check(mode.start_recording(actors), "start")
	paused = true
	var craft := Node3D.new()
	scene.add_child(craft)
	craft.add_to_group("aircraft")
	craft.position = Vector3(100, 20, 30)
	var wing := MeshInstance3D.new()
	wing.mesh = BoxMesh.new()
	craft.add_child(wing)
	mode._discover_subjects()
	check(mode.take.subjects.size() == 2, "spawn discovered")
	check(Focus.is_node_in_target_camera_focus(wing, wing), "recorded descendants receive detail focus")
	mode.take.sample(1.0)
	var part := MeshInstance3D.new()
	part.mesh = SphereMesh.new()
	craft.add_child(part)
	craft.position.x = 120
	mode.take.sample(2.0)
	check(mode.take.copies.size() == 4, "late visual attached exactly once")
	mode.take.sample(2.5)
	check(mode.take.copies.size() == 4, "discovery does not duplicate tracks")
	craft.free()
	mode.take.sample(3.0)
	mode.elapsed = 3.0
	carrier.position.z = 7.0
	mode.stop_recording()
	check(mode.take.frames.size() == 5 and mode.take.times.size() == 5, "stop refresh does not duplicate timestamps")
	check(mode.take.frames.back().poses[0].origin.z == 7.0, "stop refreshes an already-sampled endpoint")
	check(not Focus.is_node_in_target_camera_focus(carrier, carrier), "focus released after capture")
	mode.enter_replay()
	for time in [0.0, 0.99, 1.0, 1.5, 2.0, 2.99, 3.0, 1.0, 0.0]:
		mode.seek(time)
		check(mode.take.subjects[1].visible == (time >= 1.0 and time < 3.0), "actor lifecycle at %.2f" % time)
		check(mode.take.copies[3].is_visible_in_tree() == (time >= 2.0 and time < 3.0), "late part lifecycle at %.2f" % time)
	mode.seek(2.99)
	check(mode.take.subjects[1].global_position.x == 120, "despawn has no origin interpolation")
	var directory: String = mode.save_take()
	var loaded := Take.new()
	check(loaded.load_from(directory), "v2 reload")
	root.add_child(loaded.world)
	loaded.seek(0.5)
	check(not loaded.subjects[1].visible, "saved birth hidden before spawn")
	loaded.seek(1.5)
	check(loaded.subjects[1].visible and absf(loaded.subjects[1].global_position.x - 110) < 0.001, "saved interpolation after birth")
	loaded.seek(3.0)
	check(not loaded.subjects[1].visible, "saved despawn")
	loaded.dispose()
	mode.leave_replay()
	# Capacity rejection is atomic and does not change IDs of existing tracks.
	var count: int = mode.take.copies.size()
	var huge := Node3D.new()
	scene.add_child(huge)
	for index in range(Take.MAX_TRACKS):
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		huge.add_child(mesh)
	check(not mode.take.add_actor(huge), "oversized actor rejected")
	check(mode.take.copies.size() == count and not mode.take.warning.is_empty(), "limit retains take and reports omission")
	mode.exit()
	mode.clear_take()
	var snapshotter := Take.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 16)
	root.add_child(viewport)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_texture = viewport.get_texture()
	quad.material = material
	screen.mesh = quad
	var screen_copy: MeshInstance3D = snapshotter._visual(screen)
	check(screen_copy.mesh.material.albedo_texture is ImageTexture, "embedded viewport material becomes a still image")
	check(screen_copy.get_active_material(0).albedo_texture is ImageTexture, "display override has no live viewport")
	check(material.albedo_texture is ViewportTexture, "live display material untouched")
	var shader_material := ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = "shader_type spatial; uniform sampler2D monitor; void fragment() { ALBEDO = texture(monitor, UV).rgb; }"
	shader_material.set_shader_parameter("monitor", viewport.get_texture())
	var shader_copy: Material = snapshotter._snapshot_material(shader_material)
	check(shader_copy.get_shader_parameter("monitor") is ImageTexture, "shader viewport uniform becomes a still image")
	screen_copy.free()
	screen.free()
	viewport.queue_free()
	var terrain_scene := Node3D.new()
	root.add_child(terrain_scene)
	var anchor := Node3D.new()
	terrain_scene.add_child(anchor)
	anchor.position.x = 10000.0
	var chunk := MeshInstance3D.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(9990, 0, -10), Vector3(10010, 0, -10), Vector3(10000, 0, 10)])
	var chunk_mesh := ArrayMesh.new()
	chunk_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	chunk.mesh = chunk_mesh
	terrain_scene.add_child(chunk)
	var terrain_take := Take.new()
	var terrain_actors: Array[Node3D] = [anchor]
	check(terrain_take.build(terrain_scene, terrain_actors, anchor.position, 100.0), "offset terrain fixture builds")
	check(terrain_take.world.get_child_count() == 2, "terrain selected by mesh bounds rather than distant node origin")
	terrain_take.dispose()
	terrain_scene.queue_free()
	var legacy_pointer := "res://captures/recording/preview_take_path.txt"
	if FileAccess.file_exists(legacy_pointer):
		var legacy := Take.new()
		check(legacy.load_from(FileAccess.get_file_as_string(legacy_pointer).strip_edges()), "previous flyby take remains readable")
		legacy.dispose()
	print("[RecordingLifecycleSmoketest] %s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)
