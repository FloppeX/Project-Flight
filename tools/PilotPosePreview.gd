extends SceneTree
## Renders the three live non-cockpit states of the canonical pilot character.
## Run with:
##   Godot --headless --path <project> --script res://tools/PilotPosePreview.gd

const OUTPUT_PATH := "res://screenshots/pilot_character_states.png"
const PILOT_SCENE := "res://Models/Characters/pilot/PilotCharacter.tscn"
const PREVIEW_SIZE := Vector2i(1500, 700)


func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var packed := load(PILOT_SCENE) as PackedScene
	if packed == null:
		_fail("canonical pilot scene did not load")
		return

	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	_add_environment(world)
	_add_ground(world)
	_add_camera(world)

	var standing := _add_pilot(packed, world, "Standing", Vector3(-2.15, 0.0, 0.0))
	var parachuting := _add_pilot(packed, world, "Parachuting", Vector3.ZERO)
	var running := _add_pilot(packed, world, "Running", Vector3(2.15, 0.0, 0.0))
	if standing == null or parachuting == null or running == null:
		_fail("a pilot preview instance did not instantiate")
		return

	await process_frame
	standing.call("set_ejection_pose", &"grounded", 0.0)
	parachuting.call("set_ejection_pose", &"parachute", 0.0)
	running.call("set_locomotion_pose", true, 5.5)
	for frame in range(12):
		await process_frame

	_add_labels(viewport)
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("preview viewport produced no image")
		return
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		_fail("could not save preview (error %d)" % error)
		return
	print("[PilotPosePreview] PASS wrote %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	quit(0)


func _add_pilot(packed: PackedScene, parent: Node3D, pilot_name: String, at: Vector3) -> Node3D:
	var pilot := packed.instantiate() as Node3D
	if pilot == null:
		return null
	pilot.name = pilot_name
	pilot.position = at
	pilot.set("hide_head_in_cockpit", false)
	parent.add_child(pilot)
	return pilot


func _add_environment(parent: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111722")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aebbd0")
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	parent.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	key.light_color = Color("f6e9d6")
	key.light_energy = 2.4
	key.shadow_enabled = true
	parent.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 155.0, 0.0)
	fill.light_color = Color("8db8e8")
	fill.light_energy = 1.1
	parent.add_child(fill)


func _add_ground(parent: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 0.04, 2.2)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("303b49")
	material.roughness = 0.9
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.position.y = -0.04
	parent.add_child(ground)


func _add_camera(parent: Node3D) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 2.75
	camera.position = Vector3(0.0, 1.15, 7.5)
	parent.add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	camera.current = true


func _add_labels(viewport: SubViewport) -> void:
	var titles := ["STANDING", "PARACHUTING", "RUNNING"]
	for index in range(titles.size()):
		var label := Label.new()
		label.text = titles[index]
		label.position = Vector2(80.0 + float(index) * 500.0, 34.0)
		label.size = Vector2(340.0, 50.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 26)
		label.add_theme_color_override("font_color", Color("e6edf5"))
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		viewport.add_child(label)


func _fail(reason: String) -> void:
	push_error("[PilotPosePreview] FAIL %s" % reason)
	quit(1)
