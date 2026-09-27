extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene

	var ground := StaticBody3D.new()
	scene.add_child(ground)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)

	var helicopter := load("res://Aircraft/Aircraft_13.tscn").instantiate() as RigidBody3D
	helicopter.position = Vector3(0, 3, 0)
	scene.add_child(helicopter)
	helicopter.get_node("HelicopterPilot").set_physics_process(false)
	for frame in 180:
		await physics_frame

	var gear := helicopter.get_node("LandingGear")
	if "--baseline" in OS.get_cmdline_user_args():
		gear.skid_terrain_damping = 0.0
	var contacts := 0
	for contact in gear.gear_has_contact:
		if contact:
			contacts += 1
	if contacts < 3:
		_fail("skids did not settle on the terrain")
		return

	# Reproduce the slow slide/yaw seen after landing with the rotor idling.
	helicopter.set_meta("parking_brake", false)
	helicopter.get_node("ControlEngine").set("target_power", 0.2)
	var engine := helicopter.get_node("Engine")
	engine.set("is_engine_working", true)
	engine.set("target_power", 0.2)
	engine.set("current_power", 0.2)
	helicopter.linear_velocity = Vector3(0.45, 0, 0.35)
	helicopter.angular_velocity = Vector3(0, 0.18, 0)
	for frame in 90:
		await physics_frame
	var planar_speed := Vector2(helicopter.linear_velocity.x, helicopter.linear_velocity.z).length()
	var yaw_rate := absf(helicopter.angular_velocity.y)
	var displacement := Vector2(helicopter.global_position.x, helicopter.global_position.z).length()
	var power := float(engine.get("current_power"))
	var brake := bool(helicopter.get_meta("parking_brake", false))
	print("A13_SKID_GRIP planar=%.3f yaw=%.3f displacement=%.3f power=%.2f brake=%s contacts=%s" % [
		planar_speed, yaw_rate, displacement, power, str(brake), str(gear.gear_has_contact)])
	if "--baseline" in OS.get_cmdline_user_args():
		quit(0)
		return
	if power < 0.1 or brake:
		_fail("test lost its powered, unbraked landing state")
		return
	if planar_speed > 0.05 or yaw_rate > 0.03 or displacement > 0.10:
		_fail("skids kept sliding or rotating after touchdown")
		return
	print("A13_SKID_GRIP_PASS")
	quit(0)


func _fail(reason: String) -> void:
	push_error("A13_SKID_GRIP_FAIL %s" % reason)
	quit(1)
