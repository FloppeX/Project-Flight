extends SceneTree
## Renders representative poses from the shared baked pilot animation library.
## Run with:
##   Godot --headless --path <project> --audio-driver Dummy --script res://tools/PilotAnimationCatalogPreview.gd

const PILOT_SCENE := "res://Models/Characters/pilot/PilotCharacter.tscn"
const OUTPUT_PATH := "res://screenshots/pilot_animation_catalog.png"
const PREVIEW_SIZE := Vector2i(2000, 1800)
const COLUMNS := 4
const CELL_WORLD_SIZE := Vector2(2.45, 2.55)
const CLIPS := [
	{"name": &"idle_breathing", "label": "IDLE BREATHING", "sample": 0.42},
	{"name": &"idle_neutral", "label": "IDLE NEUTRAL", "sample": 0.42},
	{"name": &"walk", "label": "WALK", "sample": 0.42},
	{"name": &"run", "label": "RUN", "sample": 0.42},
	{"name": &"turn_left", "label": "TURN LEFT", "sample": 0.48},
	{"name": &"turn_right", "label": "TURN RIGHT", "sample": 0.48},
	{"name": &"sit_1", "label": "SIT 1  (LOOP)", "sample": 0.42},
	{"name": &"sit_2", "label": "SIT 2  (LOOP)", "sample": 0.42},
	{"name": &"piloting", "label": "PILOTING", "sample": 0.42},
	{"name": &"salute", "label": "SALUTE", "sample": 0.52},
	{"name": &"wave", "label": "WAVE", "sample": 0.48},
	{"name": &"die", "label": "DIE", "sample": 0.65},
	{"name": &"parachute", "label": "PARACHUTE", "sample": 0.42},
]


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
	_add_camera(world)

	var rows := ceili(float(CLIPS.size()) / float(COLUMNS))
	for index in range(CLIPS.size()):
		var clip: Dictionary = CLIPS[index]
		var column := index % COLUMNS
		var row := index / COLUMNS
		var x := (float(column) - (float(COLUMNS) - 1.0) * 0.5) * CELL_WORLD_SIZE.x
		var y := ((float(rows) - 1.0) * 0.5 - float(row)) * CELL_WORLD_SIZE.y
		var pilot := packed.instantiate() as Node3D
		if pilot == null:
			_fail("could not instantiate %s preview" % clip["name"])
			return
		pilot.name = String(clip["name"])
		pilot.position = Vector3(x, y, 0.0)
		pilot.set("hide_head_in_cockpit", false)
		world.add_child(pilot)
		await process_frame
		pilot.set_process(false)
		var skeleton := _find_skeleton(pilot.get_node_or_null("Pilot"))
		if skeleton == null:
			_fail("canonical skeleton is unavailable: %s" % clip["name"])
			return
		# PilotCharacter starts in its authored cockpit sitting pose. Runtime
		# retargeting resets the rig before applying a motion frame, so do the same
		# before previewing the equivalent baked tracks.
		var player := pilot.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
		if player == null or not player.has_animation(clip["name"]):
			_fail("preview clip is unavailable: %s" % clip["name"])
			return
		var animation := player.get_animation(clip["name"])
		if not bool(pilot.call("play_baked_animation", clip["name"])):
			_fail("preview clip did not start: %s" % clip["name"])
			return
		player.seek(animation.length * float(clip["sample"]), true)
		player.advance(0.0)
		pilot.call("_apply_seated_pose_corrections", clip["name"])
		player.pause()
		_add_ground_pad(world, Vector3(x, y, 0.0))

	_add_labels(viewport, rows)
	for frame in range(4):
		await process_frame
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
	print("[PilotAnimationCatalogPreview] PASS clips=%d output=%s" % [
		CLIPS.size(), ProjectSettings.globalize_path(OUTPUT_PATH),
	])
	quit(0)


func _add_environment(parent: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101722")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c4d8")
	environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	parent.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	key.light_color = Color("f7e8d2")
	key.light_energy = 2.4
	key.shadow_enabled = true
	parent.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 155.0, 0.0)
	fill.light_color = Color("8fbce9")
	fill.light_energy = 1.1
	parent.add_child(fill)


func _add_camera(parent: Node3D) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 10.5
	camera.position = Vector3(0.0, 0.75, 12.0)
	parent.add_child(camera)
	camera.look_at(Vector3(0.0, 0.45, 0.0), Vector3.UP)
	camera.current = true


func _add_ground_pad(parent: Node3D, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.15, 0.035, 1.15)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("303c4b")
	material.roughness = 0.92
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.position = at + Vector3(0.0, -0.04, 0.0)
	parent.add_child(ground)


func _add_labels(viewport: SubViewport, rows: int) -> void:
	var cell_pixels := Vector2(
		float(PREVIEW_SIZE.x) / float(COLUMNS),
		float(PREVIEW_SIZE.y) / float(rows)
	)
	for index in range(CLIPS.size()):
		var clip: Dictionary = CLIPS[index]
		var column := index % COLUMNS
		var row := index / COLUMNS
		var label := Label.new()
		label.text = String(clip["label"])
		label.position = Vector2(float(column) * cell_pixels.x, float(row) * cell_pixels.y + 18.0)
		label.size = Vector2(cell_pixels.x, 45.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 23)
		label.add_theme_color_override("font_color", Color("e7edf5"))
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		viewport.add_child(label)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	push_error("[PilotAnimationCatalogPreview] FAIL %s" % reason)
	quit(1)
