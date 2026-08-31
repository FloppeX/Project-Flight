extends SceneTree

const AIRCRAFT_SCENES: Array[String] = [
	"res://Aircraft/Aircraft_1.tscn",
	"res://Aircraft/Aircraft_2.tscn",
	"res://Aircraft/Aircraft_3.tscn",
	"res://Aircraft/Aircraft_4.tscn",
	"res://Aircraft/Aircraft_5.tscn",
	"res://Aircraft/Aircraft_6.tscn",
	"res://Aircraft/Aircraft_7.tscn",
	"res://Aircraft/Aircraft_8.tscn",
]
const AIRCRAFT_14_SCENE := "res://Aircraft/Aircraft_14.tscn"
const ZONE_COLLIDERS: Dictionary = {
	&"left_wing": "LeftWingDamageCollider",
	&"right_wing": "RightWingDamageCollider",
	&"fuselage": "FuselageDamageCollider",
	&"cockpit": "CockpitDamageCollider",
	&"horizontal_stabilizer": "HorizontalStabilizerDamageCollider",
	&"vertical_stabilizer": "VerticalStabilizerDamageCollider",
}
const FOLD_CONTROLLERS: Dictionary = {
	1: "WingFold",
	2: "WingFold",
	5: "WingFold5",
}
const AIRCRAFT_3_BREAKAWAY_PATHS: Dictionary = {
	&"left_wing": [
		NodePath("../Aircraft 3/broken left wing section"),
	],
	&"right_wing": [
		NodePath("../Aircraft 3/broken right wing section"),
	],
	&"cockpit": [NodePath("../Aircraft 3/broken cockpit section")],
	&"horizontal_stabilizer": [NodePath("../Aircraft 3/broken horizontal stabilizer section")],
	&"vertical_stabilizer": [NodePath("../Aircraft 3/broken vertical stabilizer section")],
}
const AIRCRAFT_3_VISUAL_PROPERTY_BY_ZONE: Dictionary = {
	&"left_wing": &"left_wing_visual_paths",
	&"right_wing": &"right_wing_visual_paths",
	&"cockpit": &"cockpit_visual_paths",
	&"horizontal_stabilizer": &"horizontal_stabilizer_visual_paths",
	&"vertical_stabilizer": &"vertical_stabilizer_visual_paths",
}
const AIRCRAFT_3_DEBRIS_NAME_BY_ZONE: Dictionary = {
	&"left_wing": "DetachedLeftWing",
	&"right_wing": "DetachedRightWing",
	&"cockpit": "DetachedCockpit",
	&"horizontal_stabilizer": "DetachedHorizontalStabilizer",
	&"vertical_stabilizer": "DetachedVerticalStabilizer",
}

var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	for aircraft_number in range(1, AIRCRAFT_SCENES.size() + 1):
		await _check_aircraft(host, aircraft_number, AIRCRAFT_SCENES[aircraft_number - 1])
	await _check_uncontrolled_wing_loss_roll(host, AIRCRAFT_14_SCENE, "Aircraft 14")
	host.free()
	if _failures.is_empty():
		print("FIXED_WING_PART_DAMAGE_COLLIDER_SMOKETEST_OK")
		quit(0)
		return
	for failure in _failures:
		push_error("[FixedWingPartDamageColliderSmoketest] %s" % failure)
	quit(1)


func _check_aircraft(host: Node3D, aircraft_number: int, scene_path: String) -> void:
	var label := "Aircraft %d" % aircraft_number
	var packed := load(scene_path) as PackedScene
	_expect(packed != null, "%s scene did not load" % label)
	if packed == null:
		return
	var aircraft := packed.instantiate() as RigidBody3D
	_expect(aircraft != null, "%s did not instantiate as RigidBody3D" % label)
	if aircraft == null:
		return
	aircraft.freeze = true
	host.add_child(aircraft)
	await process_frame
	await process_frame

	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	var broad_wing_collider := aircraft.get_node_or_null("WingCollider") as CollisionShape3D
	_expect(damage_model != null, "%s is missing PartDamageModel" % label)
	_expect(
		broad_wing_collider != null and broad_wing_collider.disabled,
		"%s obsolete full-span wing collider is active or missing" % label
	)
	if damage_model != null:
		_expect(is_equal_approx(float(damage_model.get("single_wing_loss_roll_torque_per_kg")), 40.0), "%s does not use the shared rapid wing-loss roll torque" % label)
		_expect(is_zero_approx(float(damage_model.get("wing_loss_roll_authority_scale"))), "%s retains roll authority after wing loss" % label)
		_expect(bool(damage_model.get("wing_loss_disable_all_control_inputs")), "%s does not disable every control input after wing loss" % label)
		var expected_region_health := float(aircraft.get("max_health")) * 0.5
		for zone: StringName in ZONE_COLLIDERS:
			var collider_name := String(ZONE_COLLIDERS[zone])
			var collider := aircraft.get_node_or_null(collider_name) as CollisionShape3D
			_expect(collider != null, "%s is missing %s" % [label, collider_name])
			if collider == null:
				continue
			_expect(collider.shape != null, "%s %s has no shape" % [label, collider_name])
			_expect(not collider.disabled, "%s %s starts disabled" % [label, collider_name])
			_expect(is_equal_approx(
				float(damage_model.call("get_zone_max_health", zone)),
				expected_region_health
			), "%s %s does not have half the legacy HP" % [label, zone])
			var shape_index := _local_shape_index_for(aircraft, collider)
			_expect(shape_index >= 0, "%s %s has no physics shape index" % [label, collider_name])
			if shape_index >= 0:
				var resolved: StringName = damage_model.call(
					"resolve_zone_from_hit",
					collider.global_position,
					shape_index
				)
				_expect(resolved == zone, "%s %s resolves as %s" % [label, zone, resolved])

	_check_detachable_paths(damage_model, label)
	if FOLD_CONTROLLERS.has(aircraft_number):
		await _check_folding_colliders(
			aircraft,
			String(FOLD_CONTROLLERS[aircraft_number]),
			label
		)
		await _check_detachable_left_wing(aircraft, damage_model, host, label)
	else:
		_expect(
			aircraft.get_node_or_null("WingDamageColliderFollower") == null,
			"%s unexpectedly has a folding-collider follower" % label
		)
	if aircraft_number == 3:
		await _check_aircraft_3_breakaway_wiring(aircraft, damage_model, host, label)

	aircraft.free()
	await process_frame
	await _check_uncontrolled_wing_loss_roll(host, scene_path, label)


func _check_detachable_paths(damage_model: Node, label: String) -> void:
	if damage_model == null:
		return
	for property_name: StringName in [
		&"left_wing_visual_paths",
		&"right_wing_visual_paths",
		&"cockpit_visual_paths",
		&"horizontal_stabilizer_visual_paths",
		&"vertical_stabilizer_visual_paths",
		&"tail_section_visual_paths",
	]:
		var paths: Array = damage_model.get(property_name)
		for path_variant in paths:
			var path := path_variant as NodePath
			var visual := damage_model.get_node_or_null(path) as MeshInstance3D
			_expect(
				visual != null,
				"%s detachable path %s does not resolve to a mesh" % [label, path]
			)


func _check_aircraft_3_breakaway_wiring(
	aircraft: RigidBody3D,
	damage_model: Node,
	host: Node3D,
	label: String
) -> void:
	if damage_model == null:
		return
	var wing_marker := aircraft.get_node_or_null("InsigniaWing")
	var tail_marker := aircraft.get_node_or_null("InsigniaTail")
	var left_main_wing := aircraft.get_node_or_null("Aircraft 3/left wing") as MeshInstance3D
	var right_main_wing := aircraft.get_node_or_null("Aircraft 3/right wing") as MeshInstance3D
	var tail_visual := aircraft.get_node_or_null("Aircraft 3/tail") as MeshInstance3D
	_expect(
		wing_marker != null and wing_marker.get("follow_target_path") == NodePath("../Aircraft 3/left wing"),
		"%s wing insignia is not attached to the detachable left wing" % label
	)
	_expect(
		tail_marker != null and tail_marker.get("follow_target_path") == NodePath("../Aircraft 3/broken vertical stabilizer section"),
		"%s tail insignia is not attached to the detachable vertical stabilizer" % label
	)
	_expect(
		damage_model.get("tail_section_visual_paths") == [NodePath("../Aircraft 3/tail")],
		"%s common tail section is not configured as a breakaway visual" % label
	)
	for zone: StringName in [
		&"left_wing",
		&"right_wing",
		&"horizontal_stabilizer",
		&"vertical_stabilizer",
		&"cockpit",
	]:
		var expected_paths: Array = AIRCRAFT_3_BREAKAWAY_PATHS[zone]
		var property_name: StringName = AIRCRAFT_3_VISUAL_PROPERTY_BY_ZONE[zone]
		var configured_paths: Array = damage_model.get(property_name)
		_expect(
			configured_paths == expected_paths,
			"%s %s breakaway paths do not match the authored GLB pieces" % [label, zone]
		)
		damage_model.call("damage_zone", zone, damage_model.call("get_zone_max_health", zone))
		if zone == &"left_wing":
			_expect(left_main_wing != null and left_main_wing.visible, "%s main left wing detached with its broken outer section" % label)
			_expect(right_main_wing != null and right_main_wing.visible, "%s left-wing failure changed the main right wing" % label)
			var aero := aircraft.get_node_or_null("SimpleAero")
			var steering := aircraft.get_node_or_null("Steering")
			if aero != null:
				aero.set("pitch_input", 1.0)
				aero.set("roll_input", 1.0)
				aero.set("yaw_input", 1.0)
			if steering != null:
				steering.call("set_x", 1.0)
				steering.call("set_y", 1.0)
				steering.call("set_z", 1.0)
			damage_model.call("_physics_process", 0.1)
			_expect(is_equal_approx(float(damage_model.get("single_wing_loss_roll_torque_per_kg")), 40.0), "%s wing-loss roll torque is not configured for a fast roll" % label)
			_expect(bool(damage_model.get("wing_loss_disable_all_control_inputs")), "%s wing loss does not disable all flight-control inputs" % label)
			if aero != null:
				_expect(is_zero_approx(float(aero.get("pitch_power"))) and is_zero_approx(float(aero.get("roll_power"))) and is_zero_approx(float(aero.get("yaw_power"))), "%s retained SimpleAero control power after wing loss" % label)
				_expect(is_zero_approx(float(aero.get("pitch_input"))) and is_zero_approx(float(aero.get("roll_input"))) and is_zero_approx(float(aero.get("yaw_input"))), "%s retained SimpleAero pilot inputs after wing loss" % label)
			if steering != null:
				_expect(is_zero_approx(float(steering.get("axis_x"))) and is_zero_approx(float(steering.get("axis_y"))) and is_zero_approx(float(steering.get("axis_z"))), "%s retained legacy steering inputs after wing loss" % label)
		elif zone == &"right_wing":
			_expect(right_main_wing != null and right_main_wing.visible, "%s main right wing detached with its broken outer section" % label)
		if zone == &"horizontal_stabilizer":
			_expect(tail_visual != null and tail_visual.visible, "%s tail core detached after only one stabilizer failed" % label)
			_expect(host.get_node_or_null("DetachedTailSection") == null, "%s spawned tail-core debris before both stabilizers failed" % label)
		elif zone == &"vertical_stabilizer":
			_expect(tail_visual != null and not tail_visual.visible, "%s tail core stayed attached after both stabilizers failed" % label)
			var tail_debris := host.get_node_or_null("DetachedTailSection") as RigidBody3D
			_expect(tail_debris != null, "%s common tail section did not create physical debris" % label)
			if tail_debris != null:
				var tail_mesh_count := 0
				for tail_child in tail_debris.get_children():
					if tail_child is MeshInstance3D:
						tail_mesh_count += 1
				_expect(tail_mesh_count == 1, "%s common tail debris has the wrong mesh count" % label)
				tail_debris.free()
		for path_variant in expected_paths:
			var visual := damage_model.get_node_or_null(path_variant as NodePath) as MeshInstance3D
			_expect(visual != null and not visual.visible, "%s %s visual stayed attached after destruction" % [label, path_variant])
		var debris_name := String(AIRCRAFT_3_DEBRIS_NAME_BY_ZONE[zone])
		var debris := host.get_node_or_null(debris_name) as RigidBody3D
		_expect(debris != null, "%s %s did not create physical debris" % [label, zone])
		if debris != null:
			var mesh_count := 0
			for child in debris.get_children():
				if child is MeshInstance3D:
					mesh_count += 1
			_expect(mesh_count == expected_paths.size(), "%s %s debris has the wrong mesh count" % [label, zone])
			debris.free()


func _check_uncontrolled_wing_loss_roll(
	host: Node3D,
	scene_path: String,
	label: String
) -> void:
	var packed := load(scene_path) as PackedScene
	var aircraft := packed.instantiate() as RigidBody3D if packed != null else null
	_expect(aircraft != null, "%s did not instantiate for uncontrolled-roll verification" % label)
	if aircraft == null:
		return
	aircraft.position = Vector3(0.0, 1000.0, 0.0)
	aircraft.gravity_scale = 0.0
	aircraft.freeze = false
	host.add_child(aircraft)
	await physics_frame
	await physics_frame
	var damage_model := aircraft.get_node_or_null("PartDamageModel")
	_expect(damage_model != null, "%s roll verification is missing PartDamageModel" % label)
	if damage_model == null:
		aircraft.free()
		return
	aircraft.linear_velocity = aircraft.global_transform.basis.z * 100.0
	aircraft.angular_velocity = Vector3.ZERO
	damage_model.call("damage_zone", &"left_wing", damage_model.call("get_zone_max_health", &"left_wing"))
	for _frame_index in range(45):
		await physics_frame
	var local_roll_rate := aircraft.angular_velocity.dot(
		aircraft.global_transform.basis.z.normalized()
	)
	_expect(
		local_roll_rate >= deg_to_rad(90.0),
		"%s damaged-wing roll was not fast enough: %.1f deg/s" % [label, rad_to_deg(local_roll_rate)]
	)
	var control_steering := aircraft.get_node_or_null("ControlSteering")
	_expect(
		control_steering == null or not bool(control_steering.get("ControlActive")),
		"%s player steering remained active after wing loss" % label
	)
	var detached := host.get_node_or_null("DetachedLeftWing")
	if detached != null:
		detached.free()
	aircraft.free()
	await process_frame


func _check_folding_colliders(
	aircraft: RigidBody3D,
	controller_name: String,
	label: String
) -> void:
	var controller := aircraft.get_node_or_null(controller_name)
	var follower := aircraft.get_node_or_null("WingDamageColliderFollower")
	var left := aircraft.get_node_or_null("LeftWingDamageCollider") as CollisionShape3D
	var right := aircraft.get_node_or_null("RightWingDamageCollider") as CollisionShape3D
	_expect(controller != null, "%s is missing %s" % [label, controller_name])
	_expect(follower != null, "%s is missing WingDamageColliderFollower" % label)
	if controller == null or follower == null or left == null or right == null:
		return
	controller.set_process(false)
	controller.call("set_technical_index_preview_fraction", 0.0)
	await process_frame
	var left_unfolded := left.transform
	var right_unfolded := right.transform
	controller.call("set_technical_index_preview_fraction", 1.0)
	await process_frame
	_expect(
		not left.transform.is_equal_approx(left_unfolded),
		"%s left-wing collider did not follow the folded geometry" % label
	)
	_expect(
		not right.transform.is_equal_approx(right_unfolded),
		"%s right-wing collider did not follow the folded geometry" % label
	)
	_expect(not left.disabled and not right.disabled, "%s folded wing colliders became disabled" % label)


func _check_detachable_left_wing(
	aircraft: RigidBody3D,
	damage_model: Node,
	host: Node3D,
	label: String
) -> void:
	if damage_model == null:
		return
	var paths: Array = damage_model.get("left_wing_visual_paths")
	var visuals: Array[MeshInstance3D] = []
	for path_variant in paths:
		var visual := damage_model.get_node_or_null(path_variant as NodePath) as MeshInstance3D
		if visual != null:
			visuals.append(visual)
	_expect(not visuals.is_empty(), "%s has no detachable left-wing visuals" % label)
	if visuals.is_empty():
		return
	damage_model.call(
		"damage_zone",
		&"left_wing",
		damage_model.call("get_zone_max_health", &"left_wing")
	)
	await process_frame
	var collider := aircraft.get_node_or_null("LeftWingDamageCollider") as CollisionShape3D
	_expect(collider != null and collider.disabled, "%s destroyed wing collider stayed active" % label)
	for visual in visuals:
		_expect(not visual.visible, "%s destroyed wing visual %s stayed attached" % [label, visual.name])
	var debris := host.get_node_or_null("DetachedLeftWing") as RigidBody3D
	_expect(debris != null, "%s destroyed wing did not create debris" % label)
	if debris != null:
		var mesh_count := 0
		for child in debris.get_children():
			if child is MeshInstance3D:
				mesh_count += 1
		_expect(mesh_count == visuals.size(), "%s wing debris omitted a configured mesh" % label)
		debris.free()


func _local_shape_index_for(aircraft: CollisionObject3D, collider: CollisionShape3D) -> int:
	for owner_id in aircraft.get_shape_owners():
		if aircraft.shape_owner_get_owner(owner_id) != collider:
			continue
		if aircraft.shape_owner_get_shape_count(owner_id) <= 0:
			return -1
		return aircraft.shape_owner_get_shape_index(owner_id, 0)
	return -1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
