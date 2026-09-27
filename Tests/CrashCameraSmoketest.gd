extends SceneTree

class TerrainFixture extends Node3D:
	func get_height(_point: Vector3) -> float:
		return 100.0

class BridgeFixture extends Node3D:
	var camera: Camera3D
	func get_camera() -> Camera3D:
		return camera

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	scene.position = Vector3(250, 50, -100)
	var terrain := TerrainFixture.new()
	scene.add_child(terrain)
	terrain.add_to_group("terrain_provider")
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	ground.mesh = plane
	scene.add_child(ground)
	ground.global_position = Vector3(250, 100, -100)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.3, 0.2)
	ground.material_override = material
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees = Vector3(-55, -25, 0)
	var bridge := BridgeFixture.new()
	scene.add_child(bridge)
	bridge.add_to_group("carrier_cam")
	bridge.camera = Camera3D.new()
	bridge.add_child(bridge.camera)
	bridge.camera.global_position = Vector3(250, 130, -50)
	var director := Node.new()
	scene.add_child(director)
	director.set_script(load("res://AirOps/FlightDirector.gd"))
	director.set_process(false)
	director.set_physics_process(false)
	var aircraft := (load("res://Aircraft/Aircraft_1.tscn") as PackedScene).instantiate() as RigidBody3D
	aircraft.freeze = true
	scene.add_child(aircraft)
	aircraft.global_position = Vector3(250, 101, -100)
	await process_frame
	await process_frame
	aircraft.rotation.z = PI
	var bad_chase := aircraft.get_node("CameraChase/Camera3D") as Camera3D
	bad_chase.global_position = Vector3(250, 80, -100)
	bad_chase.make_current()
	director.register_aircraft(aircraft)
	director.current_viewed_aircraft = aircraft
	director.current_category = 1
	aircraft.explode()
	var shot: Camera3D = director._destroyed_plane_linger_camera
	_check(is_instance_valid(shot) and root.get_camera_3d() == shot, "destruction selects independent camera immediately")
	_check(shot.global_position.y > 102.0, "shot stays above elevated terrain")
	_check(shot.global_basis.y.dot(Vector3.UP) > 0.5, "inverted aircraft does not roll the shot")
	_check((-shot.global_basis.z).dot((Vector3(250, 103, -100) - shot.global_position).normalized()) > 0.99, "shot frames impact")
	await create_timer(0.3).timeout
	_check(not is_instance_valid(aircraft) and root.get_camera_3d() == shot, "shot survives freed aircraft")
	if "--rendered" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/crash_camera.png")
	director._destroyed_plane_linger_until_s = 0.0
	director._process(0.0)
	_check(root.get_camera_3d() == bridge.camera and director.current_category == 0, "timeout returns to carrier")
	await process_frame
	var next := RigidBody3D.new()
	scene.add_child(next)
	next.global_position = Vector3(250, 101, -100)
	director._begin_destroyed_plane_linger(next)
	var manual := Camera3D.new()
	scene.add_child(manual)
	manual.make_current()
	# Exercise same-frame manual switch before the deferred camera retry.
	await process_frame
	director._destroyed_plane_linger_until_s = 0.0
	director._process(0.0)
	_check(root.get_camera_3d() == manual and not director.is_destroyed_plane_linger_active(), "manual camera cancels return and deferred reclaim")
	director._begin_destroyed_plane_linger(next)
	var crash_transform: Transform3D = director._destroyed_plane_linger_camera.global_transform
	director._enter_free_camera()
	await process_frame
	_check(not director.is_destroyed_plane_linger_active() and director.is_free_camera_active(), "free camera cancels crash return")
	_check(director._free_camera.global_transform.is_equal_approx(crash_transform), "free camera starts from crash shot")
	next.free()
	for failure in failures:
		push_error(failure)
	print("CRASH_CAMERA ", "PASS" if failures.is_empty() else "FAIL", " terrain+inversion+explosion+freed_aircraft+carrier_return+manual_override")
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
