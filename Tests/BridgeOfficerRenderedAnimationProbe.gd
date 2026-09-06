extends SceneTree


const OUTPUT_DIR := "res://captures/bridge_officer_animation_probe"
const DANCE_ANIMATIONS: Array[StringName] = [
	&"dance_belly",
	&"dance_booty_hip_hop",
	&"dance_chicken",
	&"dance_gangnam",
	&"dance_hip_hop",
	&"dance_locking_hip_hop",
	&"dance_northern_soul",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "BridgeOfficerRenderedAnimationProbe"
	root.add_child(scene)
	current_scene = scene

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.12, 0.15, 0.19)
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.8, 0.86, 1.0)
	environment_resource.ambient_light_energy = 1.2
	environment.environment = environment_resource
	scene.add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	light.light_energy = 1.4
	scene.add_child(light)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8.0, 8.0)
	floor.mesh = floor_mesh
	scene.add_child(floor)

	var commander_scene := load("res://LandCarrier/Commander.tscn") as PackedScene
	if commander_scene == null:
		push_error("[BridgeOfficerRenderedAnimationProbe] Commander scene unavailable")
		quit(1)
		return
	var commander := commander_scene.instantiate() as CharacterBody3D
	scene.add_child(commander)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.15, 4.0)
	camera.fov = 38.0
	scene.add_child(camera)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)

	await process_frame
	await process_frame
	commander.set_physics_process(false)
	commander.get_node("Camera3D").current = false
	camera.current = true
	commander.call("_activate_officer", 1)
	commander.call("_update_body_visibility", false)
	commander.set("officer_idle_animation", &"idle_6")
	commander.set("_officer_animation", &"")
	commander.call("_set_officer_moving", false)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	_save_frame("male_idle_6_start.png")
	await create_timer(1.7).timeout
	await RenderingServer.frame_post_draw
	_save_frame("male_idle_6_later.png")

	commander.call("_set_officer_moving", true)
	await create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	_save_frame("male_walk_0.png")
	for walk_index in range(1, 5):
		await create_timer(0.16).timeout
		await RenderingServer.frame_post_draw
		_save_frame("male_walk_%d.png" % walk_index)

	commander.call("_set_officer_moving", false)
	var male_animation_player := commander.get_node(
		"BodyVisualMale/BakedAnimationPlayer"
	) as AnimationPlayer
	for dance_name in DANCE_ANIMATIONS:
		if not bool(commander.call("_play_officer_dance", dance_name)):
			push_error("[BridgeOfficerRenderedAnimationProbe] could not play %s" % dance_name)
			quit(1)
			return
		var dance := male_animation_player.get_animation(dance_name)
		male_animation_player.seek(dance.length * 0.35, true)
		male_animation_player.advance(0.0)
		await create_timer(0.08).timeout
		await RenderingServer.frame_post_draw
		_save_frame("male_%s.png" % dance_name)
	print("[BridgeOfficerRenderedAnimationProbe] PASS officer=male dances=7 output=%s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _save_frame(file_name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var save_error := image.save_png("%s/%s" % [OUTPUT_DIR, file_name])
	if save_error != OK:
		push_error("[BridgeOfficerRenderedAnimationProbe] could not save %s" % file_name)
