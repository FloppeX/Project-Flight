extends SceneTree

const OUTPUT := "res://captures/aircraft6_breakaway"
var world: Node3D
var camera: Camera3D


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This probe requires a rendered Godot process")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.content_scale_size = Vector2i(1600, 1000)
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("273340")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d3e1f2")
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.8
	light.shadow_enabled = true
	camera = Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.5
	camera.position = Vector3(10, 11, 14)
	camera.look_at(Vector3(0, 0, -2))
	var original := (load("res://Models/Aircraft_6/aircraft_6.glb") as PackedScene).instantiate() as Node3D
	world.add_child(original)
	await capture("01_original")
	original.free()
	var model := (load("res://Models/Aircraft_6/aircraft_6_breakaway.glb") as PackedScene).instantiate() as Node3D
	world.add_child(model)
	await capture("02_intact")
	model.get_node("OuterWingLeft").position.x += 1.3
	model.get_node("OuterWingRight").position.x -= 1.3
	model.get_node("HorizontalTipLeft").position.x += 0.8
	model.get_node("HorizontalTipRight").position.x -= 0.8
	model.get_node("VerticalTip").position.y += 1.0
	await capture("03_exploded_geometry")
	camera.size = 5.0
	camera.position = Vector3(8, 3, 2)
	camera.look_at(Vector3(4.5, 0.7, -0.1))
	await capture("04_wing_fracture")
	camera.size = 6.0
	camera.position = Vector3(6, 4, -10)
	camera.look_at(Vector3(0, 0.5, -5.3))
	await capture("05_tail_fractures")
	model.free()
	# Render an actual damage event too, with the owner fixed only for framing.
	var aircraft := (load("res://Aircraft/Aircraft_6.tscn") as PackedScene).instantiate() as RigidBody3D
	aircraft.freeze = true
	world.add_child(aircraft)
	await process_frame
	await process_frame
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	var damage := aircraft.get_node("PartDamageModel")
	for zone: StringName in [&"left_wing", &"right_wing", &"horizontal_stabilizer", &"vertical_stabilizer"]:
		damage.call("damage_zone", zone, damage.call("get_zone_max_health", zone))
	for tick in range(30):
		await physics_frame
	for child in world.get_children():
		if child is RigidBody3D:
			child.freeze = true
	camera.size = 19
	camera.position = Vector3(11, 10, 13)
	camera.look_at(Vector3(0, -0.5, -2.5))
	await capture("06_runtime_damage")
	print("AIRCRAFT6_BREAKAWAY_RENDERED_OK ", OUTPUT)
	quit()


func capture(label: String) -> void:
	camera.make_current()
	await create_timer(0.2).timeout
	camera.make_current()
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png")
	assert(error == OK)
