extends SceneTree

var failures: Array[String] = []
var world: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	if not condition:
		failures.append(reason)
		push_error("AIRCRAFT16_RUNTIME: " + reason)

func disable_updates(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		disable_updates(child)

func spawn(index: int) -> RigidBody3D:
	var craft := load("res://Aircraft/Aircraft_%d.tscn" % index).instantiate() as RigidBody3D
	craft.freeze = true
	craft.position = Vector3(0, 1000, 0)
	world.add_child(craft)
	return craft

func _run() -> void:
	Engine.time_scale = 1.0
	for autoload_name in ["AirOpsManager", "FlightDirector"]:
		var autoload := root.get_node_or_null(autoload_name)
		if autoload:
			disable_updates(autoload)
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	await _compare_flight_response()
	await _wheel_contact()
	await _weapons_and_damage()
	await _carrier_fit()
	print("AIRCRAFT16_RUNTIME_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _compare_flight_response() -> void:
	var measurements := {}
	for number in [3, 16]:
		measurements[number] = {}
		for axis in ["roll", "pitch", "thrust"]:
			var craft := spawn(number)
			await process_frame
			disable_updates(craft)
			# Compare airframes with the same clean load, then exercise loaded flight separately.
			for hp in craft.get_node("ControlWeapons").hardpoints:
				if hp.weapon_instance != null:
					hp.weapon_instance.free()
					hp.weapon_instance = null
			craft.call("_refresh_payload_mass")
			var aero := craft.get_node("SimpleAero")
			aero.set_flight_model_override_for_testing(1)
			aero.airflow_feedback_enabled = false
			var engine := craft.get_node("Engine")
			engine.is_engine_working = true
			engine.current_power = 1.0 if axis == "thrust" else 0.0
			engine.target_power = engine.current_power
			engine.throttle_input = engine.current_power
			craft.freeze = false
			await physics_frame
			craft.linear_velocity = Vector3(0, 0, 80)
			craft.sleeping = false
			var peak := 0.0
			for tick in 75:
				craft.call("prepare_energy_system")
				aero.roll_input = 0.6 if axis == "roll" else 0.0
				aero.pitch_input = 0.35 if axis == "pitch" else 0.0
				aero.call("_physics_process", 1.0 / 60.0)
				engine.call("process_physic_frame", 1.0 / 60.0)
				await physics_frame
				var local_rate := craft.global_basis.inverse() * craft.angular_velocity
				peak = maxf(peak, absf(local_rate.z if axis == "roll" else local_rate.x))
			measurements[number][axis] = craft.linear_velocity.z if axis == "thrust" else peak
			check(craft.global_position.is_finite() and not craft.get("_has_exploded"), "flight became invalid")
			craft.queue_free()
			await process_frame
	print("AIRCRAFT16_RESPONSE ", measurements)
	check(measurements[16].roll < measurements[3].roll, "actual roll response was not slower")
	check(measurements[16].pitch < measurements[3].pitch, "actual pitch response was not slower")
	check(measurements[16].thrust > measurements[3].thrust, "full-power acceleration was not stronger")

func _wheel_contact() -> void:
	var deck := StaticBody3D.new()
	deck.name = "LandCarrierTestDeck"
	deck.add_to_group("carrier")
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	collision.shape = box
	collision.position.y = -1
	deck.add_child(collision)
	world.add_child(deck)
	var craft := spawn(16)
	await process_frame
	disable_updates(craft)
	var gear := craft.get_node("LandingGear")
	gear.airborne_suspension_budget_enabled = false
	craft.freeze = false
	await physics_frame
	# Taildragger stance from the three authored wheel contact points.
	craft.rotation.x = deg_to_rad(-10.3)
	craft.position = Vector3(0, 1.8, 0)
	craft.linear_velocity = Vector3(0, -0.5, 0)
	craft.freeze = false
	craft.sleeping = false
	var max_compression := 0.0
	for tick in 600:
		gear.call("process_physic_frame", 1.0 / 60.0)
		await physics_frame
		if not is_instance_valid(craft) or craft.is_queued_for_deletion():
			check(false, "aircraft destroyed while settling onto its wheels")
			break
		for compression in gear.gear_compressions:
			max_compression = maxf(max_compression, compression)
	if is_instance_valid(craft) and not craft.is_queued_for_deletion():
		var contacts := 0
		for value in gear.gear_has_contact:
			contacts += int(value)
		print("AIRCRAFT16_GEAR contacts=", contacts, " compression=", gear.gear_compressions,
			" velocity=", craft.linear_velocity, " rotation=", craft.rotation_degrees)
		check(contacts == 3, "all three wheels should support the resting aircraft")
		check(max_compression > 0.02, "suspension did not compress")
		check(craft.linear_velocity.length() < 0.5, "aircraft did not settle")
		check(not craft.get("_has_exploded") and not craft.get("_critical_damage_active"), "gentle wheel contact damaged the aircraft")
		for index in 3:
			var col: CollisionShape3D = gear.gear_collision_shapes[index]
			var visual: Node3D = gear.gear_visuals[index]
			var col_shift: Vector3 = col.position - gear.get("_collider_rest_positions")[index]
			var visual_shift: Vector3 = visual.position - gear.get("_visual_rest_positions")[index]
			check(col_shift.distance_to(visual_shift) < 0.01, "wheel visual and collider disagree under load")
		craft.queue_free()
	deck.queue_free()
	await process_frame

func _weapons_and_damage() -> void:
	var craft := spawn(16)
	await process_frame
	disable_updates(craft)
	var initial_mass := craft.mass
	var rack: Node = craft.get_node("Hardpoint1").weapon_instance
	check(rack.fire(), "bomb release failed")
	await physics_frame
	check(is_instance_valid(rack.last_bomb_dropped), "bomb projectile missing")
	check(absf(initial_mass - craft.mass - 50.0) < 0.01, "bomb release did not shed payload mass")
	for name in ["Hardpoint2", "Hardpoint3", "Hardpoint4", "Hardpoint5"]:
		var hp := craft.get_node(name)
		check(hp.fire(), name + " cannot fire")
		if hp.weapon_instance.has_method("cancel_burst"):
			hp.weapon_instance.cancel_burst()
	var hook := craft.get_node("TailHook")
	hook.deploy()
	for tick in 60:
		await physics_frame
	check(hook.get("_is_deployed") and hook.get("_mesh_node").visible, "tailhook did not deploy")
	var damage := craft.get_node("PartDamageModel")
	damage.damage_zone(&"left_wing", damage.get_zone_max_health(&"left_wing"))
	check(damage.is_zone_destroyed(&"left_wing"), "wing damage was not routed")
	check(not craft.get_node("Model/WingLeft").visible, "destroyed wing remains visible")
	check(not craft.get_node("Hardpoint2").visible and not craft.get_node("Hardpoint4").visible, "wing stores remained on a destroyed wing")
	await physics_frame
	check(craft.get_node("LeftWingRootDamageCollider").disabled, "destroyed inner wing collider remains enabled")
	craft.queue_free()
	await process_frame

func _carrier_fit() -> void:
	var carrier := load("res://LandCarrier/LandCarrier2.tscn").instantiate() as Node3D
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(carrier)
	await process_frame
	var manager := carrier.get_node("FlightDeckManager")
	var craft := spawn(16)
	craft.process_mode = Node.PROCESS_MODE_DISABLED
	craft.get_node("WingFold").set_technical_index_preview_fraction(1.0)
	for elevator_name in ["Elevator", "Elevator2"]:
		var lift := carrier.get_node(elevator_name) as Node3D
		var marker := carrier.get_node("elevator_marker" if elevator_name == "Elevator" else "elevator_marker_2") as Node3D
		manager.elevator = lift
		manager.elevator_pickup_marker = marker
		var pose: Dictionary = manager.call("_get_safe_elevator_parking_pose", craft, marker.global_position)
		check(pose.get("valid", false), elevator_name + " cannot accommodate Aircraft 16: " + str(pose))
		if pose.get("valid", false):
			craft.global_transform = Transform3D(Basis(Vector3.UP, manager.call("_get_carrier_forward_yaw")), pose.position)
			check(manager.call("_aircraft_footprint_inside_elevator", craft), elevator_name + " aircraft footprint crosses edge")
	craft.queue_free()
	carrier.queue_free()
	await process_frame
