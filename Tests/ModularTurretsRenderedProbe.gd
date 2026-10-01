extends SceneTree

const GUNS := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
const OUTPUT := "res://captures/modular_turrets"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("354452")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("cedce8")
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -35, 0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 45
	var lineup := Node3D.new()
	lineup.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(lineup)
	for i in range(GUNS.CALIBERS.size()):
		var assembly := (load("res://LandCarrier/CarrierDefenseTurretAssembly.tscn") as PackedScene).instantiate() as Node3D
		assembly.set("gun_profile_override", GUNS.get_profile(GUNS.CALIBERS[i]))
		assembly.position.x = (i - 2) * 3.5
		lineup.add_child(assembly)
		var label := Label3D.new()
		label.text = "%d mm" % GUNS.CALIBERS[i]
		label.position = assembly.position + Vector3(0, 2.5, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 52
		lineup.add_child(label)
	camera.position = Vector3(7, 9, 24)
	camera.look_at(Vector3(0, 1, 1))
	await capture("five_barrels")
	lineup.hide()
	var vehicle := (load("res://GroundVehicle/vehicle_friendly_light.tscn") as PackedScene).instantiate() as Node3D
	# Retain the actual vehicle geometry and controller while omitting navigation.
	vehicle.set_script(null)
	vehicle.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(vehicle)
	camera.position = Vector3(8, 7, 12)
	camera.look_at(Vector3(0, 2, 0))
	await capture("friendly_vehicle")
	var vehicle_turret: Node3D = vehicle.get_node("Body/TurretController").get("turret")
	for i in range(120):
		vehicle_turret.call("tick", 1.0 / 60.0, Vector3(10, 40, 70))
	camera.position = Vector3(4, 4, 6)
	camera.look_at(Vector3(0, 3.5, 0.5))
	await capture("friendly_vehicle_elevated")
	vehicle.hide()
	var source := (load("res://LandCarrier/LandCarrier2.tscn") as PackedScene).instantiate()
	var carrier := Node3D.new()
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	# Render the real authored model and build sites without starting a campaign.
	for child in source.get_children():
		if child.name == "CarrierModel" or child.has_method("build_turret"):
			child.owner = null
			source.remove_child(child)
			carrier.add_child(child)
	source.free()
	world.add_child(carrier)
	var hull := carrier.get_node("CarrierDefenseTurretPosition")
	var island := carrier.get_node("TurretPosition 3")
	hull.call("build_turret", 25)
	island.call("build_turret", 40)
	var center: Vector3 = (hull.get("built_turret") as Node3D).global_position + Vector3.UP
	camera.position = center + Vector3(11, 7, 10)
	camera.look_at(center)
	await capture("hull_mount")
	center = (island.get("built_turret") as Node3D).global_position + Vector3.UP
	camera.position = center + Vector3(-11, 8, 12)
	camera.look_at(center)
	await capture("island_mount")
	print("MODULAR_TURRETS_RENDERED_PROBE_OK")
	quit(0)

func capture(label: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var result := root.get_texture().get_image().save_png("%s/%s.png" % [OUTPUT, label])
	if result != OK:
		push_error("Failed to save turret render: " + label)
		quit(1)
