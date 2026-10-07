extends SceneTree
## Friendly vehicle integration. Add -- --vehicle-1 for Explorer or --vehicle-3
## for Enforcer; omit --headless to also save assembled views.

const SCENE := "res://GroundVehicle/ground_vehicle_2.tscn"
const SCENE_1 := "res://GroundVehicle/ground_vehicle_1.tscn"
const SCENE_3 := "res://GroundVehicle/ground_vehicle_3.tscn"
const SPAWN_MENU_PATH := "res://UI/VehicleSpawnMenu.gd"
var failures: Array[String] = []
var vehicle_number := 2

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	vehicle_number = 1 if "--vehicle-1" in OS.get_cmdline_user_args() else 2
	if "--vehicle-3" in OS.get_cmdline_user_args(): vehicle_number = 3
	var scene_path: String = {1: SCENE_1, 2: SCENE, 3: SCENE_3}[vehicle_number]
	var wheel_count := 4 if vehicle_number == 1 else 6
	var ride_height := 0.98 if vehicle_number == 1 else 1.0
	var vehicle_name: String = {1: "KMV EXPLORER", 2: "KMV DEFENDER", 3: "KMV ENFORCER"}[vehicle_number]
	var caliber := 20 if vehicle_number == 3 else 10
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	create_timer(30.0).timeout.connect(func(): quit(2))
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	# Deterministic paint for readable renders; only this test process is changed.
	root.get_node("Livery").call("set_player_livery", Color("2876a8"), Color("eadb85"), 0)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ground := StaticBody3D.new()
	ground.position = Vector3(0, 99.5, -50)
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ground.add_child(collision)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	floor_mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("625f58")
	floor_mesh.material_override = material
	ground.add_child(floor_mesh)
	world.add_child(ground)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("354452")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 45
	world.add_child(camera)
	camera.make_current()
	var host = (load(scene_path) as PackedScene).instantiate()
	host.position = Vector3(0, 100 + ride_height, -100)
	host.performance_lod_enabled = false
	world.add_child(host)
	_check(host.get_script() == load("res://GroundVehicle/vehicle_friendly_light.gd"), "shares friendly vehicle implementation")
	_check(host._all_wheel_nodes.size() == wheel_count, "correct suspension wheel count")
	_check(host._front_wheels.size() == 2, "two steering wheels")
	_check(host.is_in_group("friendlies") and host.is_in_group("team_1"), "friendly team registration")
	var body_file := "enforcer_hull.glb" if vehicle_number == 3 else "ground_vehicle_%d.blend" % (3 - vehicle_number)
	_check(host.get_node("Body").scene_file_path.ends_with(body_file), "uses correct authored Blender scene")
	_check(host.get_meta("vehicle_number") == vehicle_number, "vehicle numbering")
	if vehicle_number == 3:
		var base = load(SCENE).instantiate()
		_check(host.max_health > base.max_health and is_equal_approx(host.current_health, host.max_health), "Enforcer starts with more durability than Sabretooth")
		_check(host.max_speed < base.max_speed and host.max_speed >= base.max_speed * 0.85, "Enforcer is only slightly slower than Sabretooth")
		_check(host.get_meta("vehicle_id") == "kmv_enforcer", "stable Enforcer identity")
		base.free()
	var controller = host.get_node("Body/TurretController")
	_check(controller.team == 1, "friendly gunner")
	_check(is_equal_approx(controller._get_effective_aim_skill(null), controller.FRIENDLY_GUNNER_SKILL), "friendly aiming skill")
	_check(controller.weapon_instance.gun_profile.caliber_mm == caliber, "correct weapon profile")
	var visible_caliber: int = controller.turret.receiver.caliber_mm if vehicle_number == 1 else controller.turret.mounted_caliber_mm
	_check(visible_caliber == caliber, "visible barrel matches ammunition")
	var painted := 0
	for mesh: MeshInstance3D in host.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_material(i).resource_name == "Upper fuselage":
				painted += 1
				var active: Material = mesh.get_active_material(i)
				_check(active != mesh.mesh.surface_get_material(i), "team livery overrides body paint")
				if active is StandardMaterial3D:
					_check(active.albedo_color.is_equal_approx(root.get_node("Livery").call("_get_team_upper_color", 1)), "friendly paint color")
				elif active is ShaderMaterial:
					_check(active.get_shader_parameter("base_color").is_equal_approx(root.get_node("Livery").call("_get_team_upper_color", 1)), "patterned friendly paint color")
	_check(painted >= 3, "body and both doors painted")
	var entries: Array[Dictionary] = load(SPAWN_MENU_PATH)._build_spawn_catalog()
	var found := false
	for entry in entries:
		if entry.get("scene", "") == scene_path:
			found = entry.get("category", "") == "GROUND VEHICLES"
			_check(entry.get("name", "") == vehicle_name, "named catalog entry")
	_check(found, "available through actual spawn catalog")
	if vehicle_number != 3:
		var recipe_id := "kmv_explorer" if vehicle_number == 1 else "light_combat_vehicle"
		var recipe: Dictionary = load("res://LandCarrier/ReplicatorCatalog.gd").recipe(recipe_id)
		_check(recipe.get("name", "") == vehicle_name and recipe.get("scene", "") == scene_path, "replicator uses correct vehicle")
	host.set_rescue_doors_open(true)
	for tick in 75:
		await physics_frame
	_check(host.is_rescue_door_open(), "authored doors animate for boarding")
	host.set_rescue_doors_open(false)
	for tick in 75:
		await physics_frame
	_check(not host.is_rescue_door_open(), "doors close")
	var start: Vector3 = host.global_position
	var waypoints: Array[Vector3] = [start + Vector3(0, 0, 75)]
	host.set_patrol_waypoints(waypoints)
	for tick in 480:
		await physics_frame
	var distance := Vector2(host.position.x - start.x, host.position.z - start.z).length()
	_check(distance > 25, "AI follows ground waypoint")
	_check(absf(host.position.y - 100 - ride_height) < 0.05, "chassis stays at ride height while driving")
	var contact_error := 0.0
	for marker: Node3D in host._wheel_contact_nodes:
		contact_error = maxf(contact_error, absf(marker.global_position.y - 100))
	_check(contact_error < 0.02, "all wheels rest on road")
	if vehicle_number == 3:
		controller.set_physics_process(false)
		var target: Vector3 = host.global_position + Vector3(100, 60, 150)
		controller.turret.aim_at_point(target)
		for tick in 180: controller.turret.tick(1.0 / 60.0, target)
		_check(controller.turret.get_aim_angle_to_target() < 0.5, "20 mm turret tracks in yaw and elevation")
		target = host.global_position + Vector3(0, 3, 300)
		controller.turret.aim_at_point(target)
		for tick in 180: controller.turret.tick(1.0 / 60.0, target)
	var weapon = controller.weapon_instance
	weapon.set_meta("next_fire_time_s", 0.0)
	_check(weapon.fire(), "mounted gun fires")
	_check(is_instance_valid(weapon.last_fired_projectile), "gun produces projectile")
	_check(is_equal_approx(controller.turret._barrel_recoil.distance_m, float(caliber) * 0.01), "caliber-scaled barrel recoil")
	if is_instance_valid(weapon.last_fired_projectile):
		weapon.last_fired_projectile.queue_free()
	for tick in 20:
		await physics_frame
	_stop(host)
	if DisplayServer.get_name() != "headless":
		await _capture(host, camera, Vector3(10, 7, 12), "front")
		await _capture(host, camera, Vector3(-11, 6, -10), "rear")
	print("VEHICLE_%d_SMOKETEST " % vehicle_number, JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures, "drive_distance_m": distance, "wheel_contact_error_m": contact_error}))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _capture(host: Node3D, camera: Camera3D, offset: Vector3, label: String) -> void:
	for mesh: MeshInstance3D in host.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = true
	camera.position = host.global_position + offset
	camera.look_at(host.global_position + Vector3(0, 1.8, 0.8))
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var output := "res://captures/vehicle_%d" % vehicle_number
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_check(root.get_texture().get_image().save_png("%s/%s.png" % [output, label]) == OK, "saved " + label + " preview")

func _stop(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_stop(child)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
