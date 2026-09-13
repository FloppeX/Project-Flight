extends SceneTree

const OUTPUT := "res://captures/folding_aircraft_breakaway"
const SOURCES := {
	1: "res://Models/Aircraft_1/Aircraft_1.glb",
	2: "res://Models/Aircraft_2/aircraft 2 body.glb",
	5: "res://Models/Aircraft_5/aircraft_5.glb",
}
var world: Node3D
var camera: Camera3D


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
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
	for number: int in SOURCES:
		var model := (load(SOURCES[number]) as PackedScene).instantiate() as Node3D
		world.add_child(model)
		camera.size = 18.0 if number == 2 else 14.5
		camera.position = Vector3(10, 11, 14)
		camera.look_at(Vector3(0, 0, -1))
		await capture("%d_01_original" % number)
		camera.size = 6.5 if number == 1 else 10.0
		camera.position = Vector3(5, 4, -10)
		camera.look_at(Vector3(0, 0.2, -3.8))
		await capture("%d_02_original_tail" % number)
		model.free()
		if "--original-only" in OS.get_cmdline_user_args():
			continue
		model = (load("res://Models/Aircraft_%d/aircraft_%d_breakaway.glb" % [number, number]) as PackedScene).instantiate() as Node3D
		world.add_child(model)
		camera.size = 18.0 if number == 2 else 14.5
		camera.position = Vector3(10, 11, 14)
		camera.look_at(Vector3(0, 0, -1))
		await capture("%d_03_intact" % number)
		for node in model.find_children("*", "MeshInstance3D", true, false):
			match String(node.name):
				"OuterWingLeft": node.global_position.x += 1.2
				"OuterWingRight": node.global_position.x -= 1.2
				"HorizontalTipLeft": node.global_position.x += 0.7
				"HorizontalTipRight": node.global_position.x -= 0.7
				"HorizontalBridge": node.global_position.y += 1.7
				"VerticalTip", "VerticalTipLeft", "VerticalTipRight": node.global_position.y += 0.9
		await capture("%d_04_exploded" % number)
		camera.size = 7.5 if number == 1 else 10.0
		camera.position = Vector3(5, 4, -10)
		camera.look_at(Vector3(0, 0.6, -3.8))
		await capture("%d_05_tail_fractures" % number)
		model.free()
		var aircraft := (load("res://Aircraft/Aircraft_%d.tscn" % number) as PackedScene).instantiate() as RigidBody3D
		aircraft.freeze = true
		world.add_child(aircraft)
		await process_frame
		await process_frame
		aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		camera.size = 18.0 if number == 2 else 14.5
		camera.position = Vector3(10, 11, 14)
		camera.look_at(Vector3(0, 0, -1))
		var fold := aircraft.get_node("WingFold5" if number == 5 else "WingFold")
		fold.call("set_technical_index_preview_fraction", 1.0)
		await capture("%d_06_folded" % number)
		fold.call("set_technical_index_preview_fraction", 0.0)
		var damage := aircraft.get_node("PartDamageModel")
		for zone: StringName in [&"left_wing", &"right_wing", &"horizontal_stabilizer", &"vertical_stabilizer"]:
			damage.call("damage_zone", zone, damage.call("get_zone_max_health", zone))
		for tick in range(30):
			await physics_frame
		for child in world.get_children():
			if child is RigidBody3D:
				child.freeze = true
		camera.size = 21.0 if number == 2 else 18.0
		await capture("%d_07_runtime_damage" % number)
		for child in world.get_children():
			if child is RigidBody3D:
				child.free()
	print("FOLDING_AIRCRAFT_BREAKAWAY_RENDERED_OK")
	quit()


func capture(label: String) -> void:
	camera.make_current()
	await create_timer(0.2).timeout
	camera.make_current()
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK)
