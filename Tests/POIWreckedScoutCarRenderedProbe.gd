extends SceneTree

const WRECK_SCENE: PackedScene = preload("res://POI/World/WreckedScoutCarSite.tscn")
const OUTPUT_PATH := "user://poi_wrecked_scout_car_probe.png"
const OUTPOST_SCENE: PackedScene = preload("res://POI/World/AbandonedOutpostSite.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var probe_ruin := "--probe-ruin-building" in OS.get_cmdline_user_args()
	var scene := Node3D.new()
	scene.name = "POIWreckedScoutCarRenderedProbe"
	root.add_child(scene)
	current_scene = scene

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("667279")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c1c4")
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	scene.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	scene.add_child(sun)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(30.0, 30.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("9d856a")
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	scene.add_child(ground)

	var subject_scene := OUTPOST_SCENE if probe_ruin else WRECK_SCENE
	var subject := subject_scene.instantiate() as Node3D
	scene.add_child(subject)

	var camera := Camera3D.new()
	camera.fov = 48.0
	scene.add_child(camera)
	camera.look_at_from_position(
		Vector3(12.0, 7.0, 13.5) if probe_ruin else Vector3(7.5, 4.3, 8.5),
		Vector3(0.0, 2.0, 0.0) if probe_ruin else Vector3(0.0, 1.0, 0.0)
	)
	camera.current = true

	var notice := POIDecisionNotice.new()
	notice.setup(0, "Abandoned Outpost" if probe_ruin else "Wrecked Scout Car")
	root.add_child(notice)

	for _frame in range(20):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var output_path := "user://poi_ruin_building_probe.png" if probe_ruin else OUTPUT_PATH
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("[POIWreckedScoutCarRenderedProbe] screenshot failed: %s" % error_string(save_error))
		quit(1)
		return
	print("[POIWreckedScoutCarRenderedProbe] PASS %s" % ProjectSettings.globalize_path(output_path))
	quit(0)
