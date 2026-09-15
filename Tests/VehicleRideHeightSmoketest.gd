extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(100, 1, 100)
	collision.position.y = 99.5
	floor_body.add_child(collision)
	var ground := MeshInstance3D.new()
	ground.mesh = BoxMesh.new()
	ground.mesh.size = Vector3(100, 1, 100)
	ground.position.y = 99.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.38, 0.28)
	ground.material_override = material
	floor_body.add_child(ground)
	world.add_child(floor_body)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.22, 0.25, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.shadow_enabled = true
	world.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 35.0
	world.add_child(camera)
	camera.position = Vector3(10, 104, 11)
	camera.look_at(Vector3(0, 101.5, 0))
	camera.make_current()
	var cases := [["buggy", 0.9, 0.6], ["pickup", 0.95, 1.1], ["battle_bus", 1.15, 1.3]]
	for entry in cases:
		var vehicle: Node3D = load("res://GroundVehicle/vehicle_enemy_%s.tscn" % entry[0]).instantiate()
		vehicle.position = Vector3(0, 101, 0)
		world.add_child(vehicle)
		stop(vehicle)
		await physics_frame
		await process_frame
		stop(vehicle)
		check(is_equal_approx(vehicle.chassis_ride_height_m, entry[2]), "%s authored height" % entry[0])
		for phase in 2:
			vehicle.chassis_ride_height_m = entry[phase + 1]
			vehicle._spring_initialized = false
			vehicle._wheel_support.refresh(vehicle, true)
			for tick in 240:
				vehicle.position.y += vehicle._spring_velocity_y / 60.0
				vehicle._wheel_support.update(vehicle, 1.0 / 60.0, true, true)
			var error := 0.0
			for marker in vehicle._wheel_contact_nodes:
				if marker != null: error = maxf(error, absf(marker.global_position.y - 100.0))
			check(error < 0.015, "%s %d wheel contact" % [entry[0], phase])
			check(absf(vehicle.position.y - 100.0 - entry[phase + 1]) < 0.01, "%s settles at requested height" % entry[0])
			print("RIDE_HEIGHT %s phase=%d height=%.3f contact_error=%.6f" % [entry[0], phase, vehicle.position.y - 100, error])
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://captures/ride_height_%s_%s.png" % [entry[0], "before" if phase == 0 else "after"])
		vehicle.free()
		await process_frame
	print("VEHICLE_RIDE_HEIGHT_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func stop(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): stop(child)

func check(value: bool, label: String) -> void:
	if not value: failures.append(label)
