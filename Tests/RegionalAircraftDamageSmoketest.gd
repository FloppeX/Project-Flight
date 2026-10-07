extends Node

var failures: Array[String] = []
var host: Node3D

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func spawn(number: int) -> Aircraft:
	var craft := load("res://Aircraft/Aircraft_%d.tscn" % number).instantiate() as Aircraft
	craft.freeze = true
	craft.position.y = 1500.0
	craft.prevent_below_terrain = false
	host.add_child(craft)
	for node in craft.find_children("*", "Node", true, false):
		if node.name in ["AIPilot", "AIToggle", "ControlEngine", "ControlSteering", "EjectionSequence"]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
		if node.name == "EjectionSequence": node.set("auto_start_on_critical_damage", false)
	return craft

func _run() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		push_error("REGIONAL_DAMAGE_TEST_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	for number in [1,2,3,4,5,6,7,8,14,16]:
		var craft := spawn(number)
		await get_tree().process_frame
		var model := craft.get_node("PartDamageModel") as AircraftPartDamageModel
		var aero := craft.get_node("SimpleAero")
		var engine := craft.get_node("Engine") as AircraftModule_Engine
		var base_roll: float = aero.roll_power
		var base_thrust := engine.get_effective_power_factor()
		model.damage_zone(&"left_wing", model.get_zone_max_health(&"left_wing") * 0.5)
		check(aero.roll_power < base_roll and aero.roll_power > 0.0, "%d partial wing authority" % number)
		check(aero.damage_left_lift_scale < aero.damage_right_lift_scale, "%d asymmetric lift" % number)
		check(is_equal_approx(engine.get_effective_power_factor(),base_thrust), "%d wing hit changed engine" % number)
		model.damage_zone(&"engine", model.get_zone_max_health(&"engine") * 0.5)
		check(engine.get_effective_power_factor() < base_thrust and engine.get_effective_power_factor() > 0, "%d engine power" % number)
		model.damage_zone(&"fuselage", model.get_zone_max_health(&"fuselage") * 0.6)
		check(model.systems.fuel_leak_rate > 0.0, "%d fuel leak" % number)
		model.damage_zone(&"cockpit", model.get_zone_max_health(&"cockpit") * 0.7)
		check(bool(craft.get_meta("pilot_wounded", false)) and not bool(craft.get_meta("pilot_dead", false)), "%d cockpit wound" % number)
		var saved := model.get_damage_state()
		var other := spawn(number)
		var restored := other.get_node("PartDamageModel") as AircraftPartDamageModel
		restored.restore_damage_state(saved)
		check(is_equal_approx(other.get_node("SimpleAero").roll_power,aero.roll_power), "%d restored controls" % number)
		check(is_equal_approx(other.get_node("Engine").get_effective_power_factor(),engine.get_effective_power_factor()), "%d restored thrust" % number)
		other.free()
		model.damage_zone(&"engine", model.get_zone_max_health(&"engine"))
		engine.engine_set_power(1.0)
		check(engine.damage_disabled and not engine.is_engine_working and engine.get_effective_power_factor() == 0.0, "%d destroyed engine restart" % number)
		check(not craft._critical_damage_active and not craft._has_exploded and aero.roll_power > 0.0, "%d engine failure prevented gliding" % number)
		var tail_visual := model.get_node_or_null(model.tail_section_visual_paths[0]) as MeshInstance3D
		check(tail_visual != null and tail_visual.visible, "%d capped tail mesh" % number)
		check(has_fracture_cap(tail_visual) and has_fracture_cap(tail_visual.get_parent()), "%d missing tail or stump cap" % number)
		var tail_collider := craft.get_node("HorizontalStabilizerDamageCollider") as CollisionShape3D
		var tail_shape := -1
		for owner_id in craft.get_shape_owners():
			if craft.shape_owner_get_owner(owner_id) == tail_collider:
				tail_shape = craft.shape_owner_get_shape_index(owner_id, 0)
		var hit_zone := craft.take_damage_at(model.get_zone_max_health(&"tail"), tail_collider.global_position, tail_shape)
		check(hit_zone == &"tail", "%d stabilizer projectile did not route to full tail" % number)
		check(tail_visual != null and not tail_visual.visible, "%d tail still attached" % number)
		check(host.get_node_or_null("DetachedTailSection") != null, "%d no tail debris" % number)
		check(aero.pitch_power == 0.0 and aero.roll_power == 0.0 and aero.yaw_power == 0.0, "%d tail retains controls" % number)
		var restored_tail := spawn(number)
		var body_count := host.get_child_count()
		restored_tail.get_node("PartDamageModel").restore_damage_state(model.get_damage_state())
		check(host.get_child_count() == body_count, "%d restoring tail spawned fresh debris" % number)
		check(restored_tail.get_node("PartDamageModel").is_zone_destroyed(&"tail") and restored_tail.get_node("SimpleAero").roll_power == 0.0, "%d restored tail lost failure behavior" % number)
		restored_tail.free()
		craft.freeze = false
		craft.linear_velocity = Vector3(0,0,85)
		for frame in 120:
			await get_tree().physics_frame
			if not is_instance_valid(craft): break
			var local_rate := craft.global_basis.orthonormalized().transposed() * craft.angular_velocity
			check(absf(local_rate.x) <= deg_to_rad(125), "%d unbounded tail pitch" % number)
		if is_instance_valid(craft):
			var local_rate := craft.global_basis.orthonormalized().transposed() * craft.angular_velocity
			print("TAIL_RATE ",number," local=",local_rate," speed=",craft.linear_velocity.length()," active=",model.is_physics_processing())
			check(local_rate.x > 0.2 and absf(local_rate.x) > absf(local_rate.z), "%d tail did not tumble about X" % number)
			craft.free()
		for child in host.get_children(): child.queue_free()
		await get_tree().process_frame
		print("REGIONAL_DAMAGE_AIRCRAFT_DONE ",number)
	for failure in failures: push_error(failure)
	print("REGIONAL_AIRCRAFT_DAMAGE_%s fleet=10 partial=controls+engine+fuel+cockpit save_restore=true tail_axis=X" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func has_fracture_cap(node: Node) -> bool:
	if not node is MeshInstance3D or node.mesh == null: return false
	for index in node.mesh.get_surface_count():
		var material: Material = node.mesh.surface_get_material(index)
		if material != null and material.resource_name == "FractureInterior": return true
	return false
