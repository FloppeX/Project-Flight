extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_14.tscn")
const BULLET_SCENE: PackedScene = preload("res://Projectiles/Bullet/bullet.tscn")
const EXPLOSION_SCENE: PackedScene = preload("res://Projectiles/Explosion/explosion.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_zone_configuration_and_wing_detachment()
	await _check_right_wing_failure_direction()
	await _check_folded_wing_compound_detachment()
	await _check_projectile_shape_routing()
	await _check_explosion_damage_is_deduplicated()
	await _check_stabilizer_detachment_and_control_loss()
	await _check_cockpit_detachment()
	await _check_fuselage_failure()
	_finish()


func _spawn_aircraft() -> RigidBody3D:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	if aircraft == null:
		return null
	aircraft.freeze = true
	add_child(aircraft)
	return aircraft


func _check_zone_configuration_and_wing_detachment() -> void:
	var aircraft := _spawn_aircraft()
	_expect(aircraft != null, "Aircraft 14 did not instantiate for wing damage test")
	if aircraft == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	var broad_collider := aircraft.get_node_or_null("WingCollider") as CollisionShape3D
	var left_collider := aircraft.get_node_or_null("LeftWingDamageCollider") as CollisionShape3D
	var right_collider := aircraft.get_node_or_null("RightWingDamageCollider") as CollisionShape3D
	var fuselage_collider := aircraft.get_node_or_null("FuselageDamageCollider") as CollisionShape3D
	var cockpit_collider := aircraft.get_node_or_null("CockpitDamageCollider") as CollisionShape3D
	var horizontal_collider := aircraft.get_node_or_null("HorizontalStabilizerDamageCollider") as CollisionShape3D
	var vertical_collider := aircraft.get_node_or_null("VerticalStabilizerDamageCollider") as CollisionShape3D
	_expect(damage_model != null, "PartDamageModel is missing")
	_expect(broad_collider != null and broad_collider.disabled, "obsolete full-span wing collider is active")
	_expect(left_collider != null and left_collider.shape is BoxShape3D, "left-wing damage collider is missing or not a box")
	_expect(right_collider != null and right_collider.shape is BoxShape3D, "right-wing damage collider is missing or not a box")
	_expect(fuselage_collider != null and fuselage_collider.shape is CapsuleShape3D, "fuselage damage collider is missing or not a capsule")
	_expect(cockpit_collider != null and cockpit_collider.shape is BoxShape3D, "cockpit damage collider is missing or not a box")
	_expect(horizontal_collider != null and horizontal_collider.shape is BoxShape3D, "horizontal-stabilizer collider is missing or not a box")
	_expect(vertical_collider != null and vertical_collider.shape is BoxShape3D, "vertical-stabilizer collider is missing or not a box")
	if damage_model == null or left_collider == null:
		_cleanup_aircraft(aircraft)
		return

	for zone: StringName in [
		&"left_wing", &"right_wing", &"fuselage", &"cockpit",
		&"horizontal_stabilizer", &"vertical_stabilizer",
	]:
		_expect(is_equal_approx(
			float(damage_model.call("get_zone_max_health", zone)),
			float(aircraft.get("max_health")) * 0.5
		), "%s does not have half the legacy aircraft HP" % zone)

	var left_shape_index := _local_shape_index_for(aircraft, left_collider)
	_expect(left_shape_index >= 0, "left-wing shape owner did not resolve to a local shape index")
	var starting_zone_health := float(damage_model.call("get_zone_health", &"left_wing"))
	var resolved_zone: StringName = aircraft.call(
		"take_damage_at",
		10.0,
		left_collider.global_position,
		left_shape_index
	)
	_expect(resolved_zone == &"left_wing", "shape-index hit did not route to the left-wing zone")
	_expect(absf(float(damage_model.call("get_zone_health", &"left_wing")) - (starting_zone_health - 10.0)) < 0.001, "left-wing zone health did not receive routed damage")
	_expect(absf(float(damage_model.call("get_zone_health", &"right_wing")) - float(damage_model.call("get_zone_max_health", &"right_wing"))) < 0.001, "left-wing hit damaged the right wing")
	_expect(is_equal_approx(float(aircraft.get("current_health")), float(aircraft.get("max_health"))), "regional hit drained the retired shared hull pool")

	var left_visual := aircraft.get_node_or_null("aircraft_14/left wing") as MeshInstance3D
	var left_break_visual := aircraft.get_node_or_null("aircraft_14/broken left wing section") as MeshInstance3D
	var remaining_health := float(damage_model.call("get_zone_health", &"left_wing"))
	damage_model.call("damage_zone", &"left_wing", remaining_health)
	await get_tree().process_frame
	_expect(bool(damage_model.call("is_zone_destroyed", &"left_wing")), "left-wing zone did not enter destroyed state")
	_expect(left_collider.disabled, "destroyed left-wing collider stayed active")
	_expect(left_visual != null and not left_visual.visible, "destroyed left-wing visual stayed attached")
	_expect(left_break_visual != null and not left_break_visual.visible, "left-wing break section stayed attached")
	var left_debris := get_node_or_null("DetachedLeftWing") as RigidBody3D
	_expect(left_debris != null, "destroyed left wing did not spawn physical debris")
	_expect(_direct_child_count(left_debris, "MeshInstance3D") == 2, "left outer wing and break section did not share one debris body")
	_expect(_direct_child_count(left_debris, "CollisionShape3D") == 2, "left compound debris does not have both collision shapes")
	_expect(right_collider != null and not right_collider.disabled, "destroying left wing disabled right-wing collision")
	var aero := aircraft.get_node_or_null("SimpleAero")
	if aero != null:
		aircraft.linear_velocity = Vector3(0, 0, 100)
		damage_model.call("_physics_process", 0.1)
		_expect(is_equal_approx(float(aircraft.get_meta("wing_failure_roll_direction", 0.0)), 1.0), "left-wing loss did not produce the mirrored left-roll direction")
		_expect(is_zero_approx(float(aero.get("pitch_power"))) and is_zero_approx(float(aero.get("roll_power"))) and is_zero_approx(float(aero.get("yaw_power"))), "wing loss did not remove all flight-control authority")
		_expect(float(aero.get("structural_damage_drag_accel_mps2")) >= 6.9, "wing loss did not add speed-scaled structural drag")
		_expect(float(aero.get("structural_damage_buffet_intensity")) >= 0.89, "wing loss did not add severe airflow buffet")
	var control_steering := aircraft.get_node_or_null("ControlSteering")
	_expect(control_steering == null or not bool(control_steering.get("ControlActive")), "wing loss left player steering active")
	_expect(is_equal_approx(float(aircraft.get("current_health")), float(aircraft.get("max_health"))), "destroyed wing triggered shared-hull destruction")
	_cleanup_detached("DetachedLeftWing")
	_cleanup_aircraft(aircraft)
	await get_tree().process_frame


func _check_right_wing_failure_direction() -> void:
	var aircraft := _spawn_aircraft()
	_expect(aircraft != null, "Aircraft 14 did not instantiate for right-wing failure test")
	if aircraft == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	if damage_model == null:
		_expect(false, "right-wing failure damage model is missing")
		_cleanup_aircraft(aircraft)
		return
	damage_model.call("damage_zone", &"right_wing", damage_model.call("get_zone_max_health", &"right_wing"))
	aircraft.linear_velocity = Vector3(0, 0, 100)
	damage_model.call("_physics_process", 0.1)
	# SimpleAero's normal right-roll command applies torque around -local Z.
	_expect(is_equal_approx(float(aircraft.get_meta("wing_failure_roll_direction", 0.0)), -1.0), "right-wing loss did not produce a right-roll torque direction")
	_cleanup_detached("DetachedRightWing")
	_cleanup_aircraft(aircraft)
	await get_tree().process_frame


func _check_folded_wing_compound_detachment() -> void:
	var aircraft := _spawn_aircraft()
	_expect(aircraft != null, "Aircraft 14 did not instantiate for folded-wing break test")
	if aircraft == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	var wing_fold := aircraft.get_node_or_null("WingFold")
	if damage_model == null or wing_fold == null:
		_expect(false, "folded-wing break dependencies are missing")
		_cleanup_aircraft(aircraft)
		return
	wing_fold.call("set_technical_index_preview_fraction", 1.0)
	damage_model.call("damage_zone", &"left_wing", damage_model.call("get_zone_max_health", &"left_wing"))
	await get_tree().process_frame
	var debris := get_node_or_null("DetachedLeftWing") as RigidBody3D
	var outer_mesh := debris.get_node_or_null("LeftWingMesh") as MeshInstance3D if debris != null else null
	var break_mesh := debris.get_node_or_null("BrokenLeftWingSectionMesh") as MeshInstance3D if debris != null else null
	_expect(debris != null and outer_mesh != null and break_mesh != null, "folded wing did not create the expected compound debris meshes")
	if outer_mesh != null and break_mesh != null:
		var separation := _aabb_separation(
			_transformed_mesh_bounds(outer_mesh),
			_transformed_mesh_bounds(break_mesh)
		)
		_expect(separation <= 0.08, "folded outer wing separated from its authored break section")
	_cleanup_detached("DetachedLeftWing")
	_cleanup_aircraft(aircraft)
	await get_tree().process_frame


func _check_projectile_shape_routing() -> void:
	var aircraft := _spawn_aircraft()
	_expect(aircraft != null, "Aircraft 14 did not instantiate for projectile routing test")
	if aircraft == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	var left_collider := aircraft.get_node_or_null("LeftWingDamageCollider") as CollisionShape3D
	if damage_model == null or left_collider == null:
		_expect(false, "projectile routing dependencies are missing")
		_cleanup_aircraft(aircraft)
		return
	var left_health_before := float(damage_model.call("get_zone_health", &"left_wing"))
	var right_health_before := float(damage_model.call("get_zone_health", &"right_wing"))
	var bullet := BULLET_SCENE.instantiate() as RigidBody3D
	_expect(bullet != null, "bullet scene did not instantiate")
	if bullet == null:
		_cleanup_aircraft(aircraft)
		return
	add_child(bullet)
	bullet.global_position = left_collider.global_position + Vector3.UP * 2.0
	bullet.call("fire", Vector3.DOWN * 300.0, null)
	for _frame_index in range(8):
		await get_tree().physics_frame
	var left_health_after := float(damage_model.call("get_zone_health", &"left_wing"))
	var right_health_after := float(damage_model.call("get_zone_health", &"right_wing"))
	_expect(left_health_after < left_health_before, "real bullet ray did not damage the left-wing zone")
	_expect(absf(right_health_after - right_health_before) < 0.001, "left-wing bullet ray damaged the right-wing zone")
	if is_instance_valid(bullet):
		bullet.free()
	_cleanup_aircraft(aircraft)
	await get_tree().process_frame


func _check_explosion_damage_is_deduplicated() -> void:
	var aircraft := _spawn_aircraft()
	_expect(aircraft != null, "Aircraft 14 did not instantiate for explosion routing test")
	if aircraft == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	if damage_model == null:
		_expect(false, "explosion routing damage model is missing")
		_cleanup_aircraft(aircraft)
		return
	var total_zone_health_before := _total_zone_health(damage_model)
	var explosion := EXPLOSION_SCENE.instantiate() as Node3D
	_expect(explosion != null, "explosion scene did not instantiate")
	if explosion == null:
		_cleanup_aircraft(aircraft)
		return
	explosion.set("blast_radius", 10.0)
	explosion.set("max_damage", 10.0)
	explosion.set("min_damage", 10.0)
	explosion.set("use_line_of_sight", false)
	explosion.set("visual_effects_enabled", false)
	explosion.set("play_explosion_audio", false)
	explosion.set("knockback_impulse_at_center", 0.0)
	explosion.set("knockback_impulse_at_edge", 0.0)
	add_child(explosion)
	explosion.global_position = aircraft.global_position
	for _frame_index in range(4):
		await get_tree().process_frame
	var total_zone_damage := total_zone_health_before - _total_zone_health(damage_model)
	_expect(absf(total_zone_damage - 10.0) < 0.001, "one explosion damaged Aircraft 14 more than once through its six shapes")
	if is_instance_valid(explosion):
		explosion.free()
	_cleanup_aircraft(aircraft)
	await get_tree().process_frame


func _check_stabilizer_detachment_and_control_loss() -> void:
	var aircraft := _spawn_aircraft()
	_expect(aircraft != null, "Aircraft 14 did not instantiate for stabilizer damage test")
	if aircraft == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	var fixed_tail_visual := aircraft.get_node_or_null("aircraft_14/tail") as MeshInstance3D
	var horizontal_break_visual := aircraft.get_node_or_null("aircraft_14/broken horizontal stabiliser section") as MeshInstance3D
	var vertical_break_visual := aircraft.get_node_or_null("aircraft_14/broken vertical stabiliser section") as MeshInstance3D
	var horizontal_collider := aircraft.get_node_or_null("HorizontalStabilizerDamageCollider") as CollisionShape3D
	var vertical_collider := aircraft.get_node_or_null("VerticalStabilizerDamageCollider") as CollisionShape3D
	var aero := aircraft.get_node_or_null("SimpleAero")
	if damage_model == null or aero == null:
		_expect(false, "stabilizer damage dependencies are missing")
		_cleanup_aircraft(aircraft)
		return
	var original_pitch := float(aero.get("pitch_power"))
	var original_yaw := float(aero.get("yaw_power"))
	damage_model.call("damage_zone", &"horizontal_stabilizer", damage_model.call("get_zone_max_health", &"horizontal_stabilizer"))
	await get_tree().process_frame
	_expect(horizontal_collider != null and horizontal_collider.disabled, "destroyed horizontal-stabilizer collider stayed active")
	_expect(vertical_collider != null and not vertical_collider.disabled, "horizontal-stabilizer loss disabled the vertical collider")
	_expect(fixed_tail_visual != null and fixed_tail_visual.visible, "fixed tail mesh detached with a stabilizer section")
	_expect(horizontal_break_visual != null and not horizontal_break_visual.visible, "horizontal stabilizer break section stayed attached")
	_expect(vertical_break_visual != null and vertical_break_visual.visible, "horizontal-stabilizer loss detached the vertical stabilizer")
	var horizontal_debris := get_node_or_null("DetachedHorizontalStabilizer") as RigidBody3D
	_expect(horizontal_debris != null, "destroyed horizontal stabilizer did not spawn physical debris")
	_expect(_direct_child_count(horizontal_debris, "MeshInstance3D") == 1, "horizontal-stabilizer debris has the wrong mesh count")
	_expect(is_equal_approx(float(aero.get("pitch_power")), original_pitch * 0.1), "horizontal-stabilizer loss did not remove 90 percent of elevator authority")
	_expect(is_equal_approx(float(aero.get("yaw_power")), original_yaw), "horizontal-stabilizer loss changed rudder authority")
	_cleanup_detached("DetachedHorizontalStabilizer")

	damage_model.call("damage_zone", &"vertical_stabilizer", damage_model.call("get_zone_max_health", &"vertical_stabilizer"))
	await get_tree().process_frame
	_expect(vertical_collider != null and vertical_collider.disabled, "destroyed vertical-stabilizer collider stayed active")
	_expect(vertical_break_visual != null and not vertical_break_visual.visible, "vertical stabilizer break section stayed attached")
	var vertical_debris := get_node_or_null("DetachedVerticalStabilizer") as RigidBody3D
	_expect(vertical_debris != null, "destroyed vertical stabilizer did not spawn physical debris")
	_expect(_direct_child_count(vertical_debris, "MeshInstance3D") == 1, "vertical-stabilizer debris has the wrong mesh count")
	_expect(is_equal_approx(float(aero.get("pitch_power")), original_pitch * 0.1), "vertical-stabilizer loss changed elevator authority")
	_expect(is_equal_approx(float(aero.get("yaw_power")), original_yaw * 0.1), "vertical-stabilizer loss did not remove 90 percent of rudder authority")
	_cleanup_detached("DetachedVerticalStabilizer")
	_cleanup_aircraft(aircraft)
	await get_tree().process_frame


func _check_cockpit_detachment() -> void:
	var aircraft := _spawn_aircraft()
	_expect(aircraft != null, "Aircraft 14 did not instantiate for cockpit damage test")
	if aircraft == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var roster := get_node_or_null("/root/PilotRoster")
	if roster != null:
		roster.call("start_new_campaign", 1414)
		roster.call("assign_aircraft_to_callsign", aircraft, "Damage Test")
	var assigned_pilot_id := str(aircraft.get_meta("pilot_roster_id", ""))
	_expect(roster == null or assigned_pilot_id != "", "cockpit damage test could not assign a persistent pilot")
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	var canopy := aircraft.get_node_or_null("aircraft_14/broken canopy section") as MeshInstance3D
	var cockpit_collider := aircraft.get_node_or_null("CockpitDamageCollider") as CollisionShape3D
	var ejection_sequence := aircraft.get_node_or_null("EjectionSequence")
	if damage_model == null:
		_expect(false, "cockpit damage model is missing")
		_cleanup_aircraft(aircraft)
		return
	damage_model.call("damage_zone", &"cockpit", damage_model.call("get_zone_max_health", &"cockpit"))
	await get_tree().process_frame
	_expect(cockpit_collider != null and cockpit_collider.disabled, "destroyed cockpit collider stayed active")
	_expect(bool(damage_model.call("is_zone_destroyed", &"cockpit")), "cockpit zone did not enter destroyed state")
	_expect(bool(aircraft.get_meta("pilot_dead", false)), "cockpit destruction did not kill the pilot")
	_expect(bool(aircraft.get_meta("ejection_disabled", false)), "dead pilot can still eject")
	if roster != null and assigned_pilot_id != "":
		var killed_pilot: Dictionary = {}
		for pilot: Dictionary in roster.call("get_carrier_roster"):
			if str(pilot.get("id", "")) == assigned_pilot_id:
				killed_pilot = pilot
				break
		_expect(not killed_pilot.is_empty(), "killed pilot disappeared from the persistent roster")
		_expect(not bool(killed_pilot.get("is_alive", true)), "cockpit destruction did not persist pilot death")
		_expect(str(killed_pilot.get("status", "")) == "killed", "dead pilot is not reported as killed in the roster")
		_expect((roster.call("get_pilot_for_callsign", "Damage Test") as Dictionary).is_empty(), "dead pilot remained assigned to a flight callsign")
	if ejection_sequence != null:
		ejection_sequence.call("start_ejection")
		_expect(not bool(ejection_sequence.get("_has_started")), "dead pilot started an ejection")
	if canopy != null:
		_expect(not canopy.visible, "destroyed canopy visual stayed attached")
		var cockpit_debris := get_node_or_null("DetachedCockpit") as RigidBody3D
		_expect(cockpit_debris != null, "destroyed canopy did not spawn physical debris")
		_expect(_direct_child_count(cockpit_debris, "MeshInstance3D") == 1, "cockpit debris does not contain the canopy section")
		_cleanup_detached("DetachedCockpit")
	else:
		_expect(get_node_or_null("DetachedCockpit") == null, "cockpit debris spawned without a detachable canopy mesh")
	_cleanup_aircraft(aircraft)
	await get_tree().process_frame


func _check_fuselage_failure() -> void:
	var aircraft := _spawn_aircraft()
	_expect(aircraft != null, "Aircraft 14 did not instantiate for fuselage damage test")
	if aircraft == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	if damage_model == null:
		_expect(false, "fuselage damage model is missing")
		_cleanup_aircraft(aircraft)
		return
	damage_model.call("damage_zone", &"fuselage", damage_model.call("get_zone_max_health", &"fuselage"))
	_expect(bool(damage_model.call("is_zone_destroyed", &"fuselage")), "fuselage zone did not enter destroyed state")
	_expect(float(aircraft.get("current_health")) <= 0.0, "destroyed fuselage did not trigger critical aircraft damage")
	_expect(bool(aircraft.get("_critical_damage_active")), "destroyed fuselage did not start the delayed explosion sequence")
	_expect(not bool(aircraft.get("_has_exploded")), "destroyed fuselage exploded immediately instead of entering the fire phase")
	var damage_effects := aircraft.get_node_or_null("DamageEffects")
	_expect(damage_effects != null and int(damage_effects.get("_smoke_active_tier")) == 4, "destroyed fuselage did not enter the fire-and-smoke phase")
	_cleanup_aircraft(aircraft)
	await get_tree().process_frame


func _local_shape_index_for(aircraft: CollisionObject3D, collider: CollisionShape3D) -> int:
	for owner_id in aircraft.get_shape_owners():
		if aircraft.shape_owner_get_owner(owner_id) != collider:
			continue
		if aircraft.shape_owner_get_shape_count(owner_id) <= 0:
			return -1
		return aircraft.shape_owner_get_shape_index(owner_id, 0)
	return -1


func _total_zone_health(damage_model: Node) -> float:
	var total := 0.0
	for zone: StringName in [
		&"left_wing", &"right_wing", &"fuselage", &"cockpit",
		&"horizontal_stabilizer", &"vertical_stabilizer",
	]:
		total += float(damage_model.call("get_zone_health", zone))
	return total


func _direct_child_count(parent: Node, type_name: String) -> int:
	if parent == null:
		return 0
	var count := 0
	for child in parent.get_children():
		if child.is_class(type_name):
			count += 1
	return count


func _transformed_mesh_bounds(mesh_instance: MeshInstance3D) -> AABB:
	var source_bounds := mesh_instance.get_aabb()
	var transformed_bounds := AABB()
	var has_point := false
	for x_index in range(2):
		for y_index in range(2):
			for z_index in range(2):
				var corner := source_bounds.position + Vector3(
					source_bounds.size.x * float(x_index),
					source_bounds.size.y * float(y_index),
					source_bounds.size.z * float(z_index)
				)
				var point := mesh_instance.transform * corner
				if not has_point:
					transformed_bounds = AABB(point, Vector3.ZERO)
					has_point = true
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


func _aabb_separation(first: AABB, second: AABB) -> float:
	var first_end := first.end
	var second_end := second.end
	return Vector3(
		maxf(maxf(first.position.x - second_end.x, second.position.x - first_end.x), 0.0),
		maxf(maxf(first.position.y - second_end.y, second.position.y - first_end.y), 0.0),
		maxf(maxf(first.position.z - second_end.z, second.position.z - first_end.z), 0.0)
	).length()


func _cleanup_detached(node_name: StringName) -> void:
	var detached := get_node_or_null(NodePath(String(node_name)))
	if detached != null:
		detached.free()


func _cleanup_aircraft(aircraft: Node) -> void:
	if aircraft != null and is_instance_valid(aircraft):
		aircraft.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AIRCRAFT_14_PART_DAMAGE_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft14PartDamageSmoketest] %s" % failure)
	get_tree().quit(1)
