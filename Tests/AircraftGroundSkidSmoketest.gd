extends "res://Tests/RoughLandingDamageSmoketest.gd"

func _run() -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		push_error("GROUND_SKID_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	add_ground()
	if camera == null:
		camera = Camera3D.new()
		host.add_child(camera)
	camera.make_current()
	for number in [5, 16]:
		for mode in ["wheels", "belly", "tail"]:
			await skid_case(number, mode)
	await excluded_surfaces()
	for failure in failures: push_error(failure)
	print("AIRCRAFT_GROUND_SKID_%s cases=6 aero_enabled=true dust=contact_only" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func skid_case(number: int, mode: String) -> void:
	var craft := spawn(number)
	while not craft.runtime_initialized: await get_tree().process_frame
	craft.position = Vector3(0, 3.0 if mode == "wheels" else 1.3, 0)
	craft.get_node("Engine").engine_stop()
	var aero := craft.get_node("SimpleAero")
	aero.set_flight_model_override_for_testing(1)
	var model := craft.get_node("PartDamageModel") as AircraftPartDamageModel
	if mode != "wheels": craft.get_node("LandingGear").shear_from_damage(false)
	if mode == "tail":
		craft.set_meta("ground_contact_frame", Engine.get_physics_frames())
		model.damage_zone(&"tail", model.get_zone_max_health(&"tail"))
	var dust := craft.get_node("GroundDust") as DustEffect
	dust.require_camera_frustum = false
	craft.freeze = false
	craft.linear_velocity = Vector3(0,-2,35)
	var supported := false
	var last_heading := 0.0
	var late_rotation := 0.0
	var late_max_rate := 0.0
	var resting_puffs := 0
	for frame in 720:
		await get_tree().physics_frame
		if not is_instance_valid(craft) or craft._has_exploded: break
		camera.position = craft.position + Vector3(19,12,-26)
		camera.look_at(craft.position + Vector3(0,0,-8))
		camera.make_current()
		if aero._has_body_ground_contact():
			supported = true
			check(not aero._is_airborne_for_stall_effects(), "belly contact still permits stall torques")
		if frame == 120 and mode != "wheels": craft.angular_velocity = Vector3(0.2, 0.8, 0.25)
		if frame == 600: resting_puffs = dust.get("emitted_puffs")
		if frame > 600:
			late_rotation += absf(angle_difference(last_heading, craft.rotation.y))
			late_max_rate = maxf(late_max_rate, craft.angular_velocity.length())
		last_heading = craft.rotation.y
		if frame == 180 and number == 5 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/ground_skid"))
			get_viewport().get_texture().get_image().save_png("res://captures/ground_skid/%s.png" % mode)
	var survived := is_instance_valid(craft) and not craft._has_exploded
	check(survived, "%d %s landing did not survive" % [number,mode])
	if survived:
		check(dust.get("emitted_wheel_puffs" if mode == "wheels" else "emitted_skid_puffs") > 12, "%d %s no sustained contact dust" % [number, mode])
		if mode != "wheels":
			check(resting_puffs == dust.get("emitted_puffs"), "stopped wreck continued emitting dust")
			check(supported, "%d %s no body support" % [number,mode])
			check(late_max_rate < 0.05 and late_rotation < deg_to_rad(3.0), "%d %s persistent spin: rate=%.3f rotation=%.2fdeg" % [number,mode,late_max_rate,rad_to_deg(late_rotation)])
		print("GROUND_SKID_CASE ",number," ",mode," rate=",late_max_rate," rotation_deg=",rad_to_deg(late_rotation)," puffs=",dust.get("emitted_puffs")," speed=",craft.linear_velocity.length())
		check(dust._puff_pool.size() <= 128, "dust pool exceeded budget")
		# Contact effects must expire when the craft leaves the surface.
		craft.position.y = 80.0
		craft.linear_velocity = Vector3(0,0,25)
		for frame in 5: await get_tree().physics_frame
		check(not aero._has_body_ground_contact(), "body support persisted in flight")
		var emitted: int = dust.get("emitted_puffs")
		for frame in 30: await get_tree().physics_frame
		check(emitted == dust.get("emitted_puffs"), "dust emitted in flight")
	await clear_aircraft()

func excluded_surfaces() -> void:
	var craft := spawn(5)
	while not craft.runtime_initialized: await get_tree().process_frame
	var dust := craft.get_node("GroundDust") as DustEffect
	dust.require_camera_frustum = false
	var handler := CONTACT.new()
	craft._regional_ground_contact = handler
	craft.linear_velocity = Vector3(0,0,35)
	var deck := StaticBody3D.new()
	deck.add_to_group("carrier")
	host.add_child(deck)
	check(not handler.is_dirt_surface(deck), "carrier classified as dirt")
	deck.remove_from_group("carrier")
	deck.add_to_group("runway_surface")
	check(not handler.is_dirt_surface(deck), "runway classified as dirt")
	handler.suspension_touchdown(0, Vector3.UP, Vector3.ZERO, 0, false)
	handler.update(craft, 1.0/60.0)
	check(handler.dust_contacts.is_empty(), "hard surface queued dirt dust")
	deck.queue_free()
	await clear_aircraft()
