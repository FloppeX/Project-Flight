extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
const FLIGHT_DECK_MANAGER_SCRIPT: Script = preload("res://LandCarrier/FlightDeckManager.gd")

var _failures: PackedStringArray = []


func _ready() -> void:
	var deck := StaticBody3D.new()
	deck.name = "TestDeck"
	deck.collision_layer = 1
	deck.collision_mask = 1
	var deck_shape := CollisionShape3D.new()
	var deck_box := BoxShape3D.new()
	deck_box.size = Vector3(30.0, 1.0, 30.0)
	deck_shape.shape = deck_box
	deck_shape.position.y = -0.5
	deck.add_child(deck_shape)
	add_child(deck)

	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_check(aircraft != null, "Aircraft_5 should instantiate as RigidBody3D")
	if aircraft == null:
		_finish()
		return
	aircraft.freeze = true
	aircraft.gravity_scale = 0.0
	aircraft.position = Vector3(0.0, 10.0, 0.0)
	add_child(aircraft)

	# Allow Aircraft setup and the gear rig's deferred hierarchy construction.
	await get_tree().process_frame
	await get_tree().physics_frame

	var landing_gear := aircraft.get_node_or_null("LandingGear")
	_check(landing_gear != null, "Aircraft_5 should expose its LandingGear module")
	if landing_gear == null:
		aircraft.queue_free()
		_finish()
		return

	var colliders: Variant = landing_gear.get("gear_collision_shapes")
	_check(typeof(colliders) == TYPE_ARRAY and not colliders.is_empty(), "LandingGear should expose wheel colliders")
	if typeof(colliders) != TYPE_ARRAY or colliders.is_empty():
		aircraft.queue_free()
		_finish()
		return

	# Match FlightDeckManager's final frozen placement by putting the lowest
	# authored wheel origin directly on the deck. Contact-aligned compression
	# should keep every visible tire tangent to y=0 without moving the fixed upper
	# strut segment.
	var lowest_wheel_y := INF
	for collider_variant in colliders:
		var collider := collider_variant as Node3D
		if is_instance_valid(collider):
			lowest_wheel_y = minf(lowest_wheel_y, collider.global_position.y)
	aircraft.global_position.y -= lowest_wheel_y

	for _i in range(5):
		await get_tree().physics_frame

	var contacts: Variant = landing_gear.get("gear_has_contact")
	_check(typeof(contacts) == TYPE_ARRAY and contacts.size() == colliders.size(), "Each wheel should publish contact state")
	if typeof(contacts) == TYPE_ARRAY:
		for i in range(contacts.size()):
			_check(bool(contacts[i]), "Wheel %d should reach the test deck" % i)

	for rig_name in ["NoseGearRig", "LeftGearRig", "RightGearRig"]:
		var rig := aircraft.get_node_or_null(rig_name) as Node3D
		_check(rig != null, "%s should exist" % rig_name)
		if rig == null:
			continue
		var upper_pivot := rig.get_node_or_null("FrontGearPivot") as Node3D
		var lower_slide := rig.get_node_or_null("FrontGearPivot/LowerLegSlide") as Node3D
		var linkage_pivot := rig.get_node_or_null("FrontGearPivot/LowerLegSlide/RotationLinkagePivot") as Node3D
		var connector_pivot := rig.get_node_or_null("FrontGearPivot/LowerLegSlide/RotationLinkagePivot/LowerConnectorArmPivot") as Node3D
		_check(upper_pivot != null and lower_slide != null, "%s should build the telescoping hierarchy" % rig_name)
		if upper_pivot == null or lower_slide == null:
			continue

		var base_upper_position: Variant = rig.get("_base_front_position")
		var base_slide_position: Variant = rig.get("_base_slide_position")
		_check(
			base_upper_position is Vector3 and upper_pivot.position.is_equal_approx(base_upper_position as Vector3),
			"%s upper leg must remain fixed during compression" % rig_name
		)
		_check(
			base_slide_position is Vector3 and lower_slide.position.y > (base_slide_position as Vector3).y + 0.01,
			"%s lower leg should telescope upward" % rig_name
		)
		if linkage_pivot != null:
			var base_linkage_rotation: Variant = rig.get("_base_linkage_rotation")
			_check(
				base_linkage_rotation is Vector3 and linkage_pivot.rotation.is_equal_approx(base_linkage_rotation as Vector3),
				"%s linkage must not rotate from compression" % rig_name
			)
		if connector_pivot != null:
			var base_connector_rotation: Variant = rig.get("_base_connector_rotation")
			_check(
				base_connector_rotation is Vector3 and connector_pivot.rotation.is_equal_approx(base_connector_rotation as Vector3),
				"%s connector must not rotate from compression" % rig_name
			)

		var tire_bottom_y := _find_lowest_mesh_y(lower_slide)
		_check(
			is_finite(tire_bottom_y) and absf(tire_bottom_y) <= 0.004,
			"%s tire should remain on deck (bottom y=%.4f)" % [rig_name, tire_bottom_y]
		)

	# During a physics-driven rollout the main wheel sphere supports the aircraft
	# with its origin about 30 cm above the surface. The authored tire is slightly
	# smaller, so the telescope may extend a few centimetres to preserve visible
	# contact instead of leaving the wheel floating.
	aircraft.global_position.y += 0.3
	for _i in range(3):
		await get_tree().physics_frame
	for rig_name in ["LeftGearRig", "RightGearRig"]:
		var lower_slide := aircraft.get_node_or_null(
			"%s/FrontGearPivot/LowerLegSlide" % rig_name
		) as Node3D
		_check(lower_slide != null, "%s lower slide should remain available" % rig_name)
		if lower_slide != null:
			var tire_bottom_y := _find_lowest_mesh_y(lower_slide)
			_check(
				is_finite(tire_bottom_y) and absf(tire_bottom_y) <= 0.004,
				"%s rollout tire should remain on deck (bottom y=%.4f)" % [rig_name, tire_bottom_y]
			)

	# Exercise the actual fixed-wing deck-placement helper, then hand the body to
	# physics. Its frozen pose should already carry the static spring load, so the
	# first active frames must not lift the aircraft or visibly change its stance.
	var flight_deck_manager := FLIGHT_DECK_MANAGER_SCRIPT.new() as FlightDeckManager
	var placed_in_static_stance := flight_deck_manager._place_fixed_wing_in_static_suspension_pose(
		aircraft,
		0.0
	)
	_check(placed_in_static_stance, "FlightDeckManager should place Aircraft_5 in its static suspension stance")
	for _i in range(3):
		await get_tree().physics_frame

	var frozen_body_y := aircraft.global_position.y
	var frozen_compressions: Array[float] = []
	var compression_variant: Variant = landing_gear.get("gear_compressions")
	if typeof(compression_variant) == TYPE_ARRAY:
		for value in compression_variant:
			frozen_compressions.append(float(value))
	_check(
		frozen_compressions.size() == colliders.size(),
		"Static stance should initialize every wheel compression"
	)
	if frozen_compressions.size() >= 3:
		_check(
			frozen_compressions[1] >= 0.08 and frozen_compressions[2] >= 0.08,
			"Main struts should show noticeable static compression (%.3f, %.3f m)" % [
				frozen_compressions[1],
				frozen_compressions[2],
			]
		)

	for rig_name in ["NoseGearRig", "LeftGearRig", "RightGearRig"]:
		var lower_slide := aircraft.get_node_or_null(
			"%s/FrontGearPivot/LowerLegSlide" % rig_name
		) as Node3D
		if lower_slide != null:
			if rig_name != "NoseGearRig":
				var base_slide_position: Variant = aircraft.get_node(rig_name).get("_base_slide_position")
				_check(
					base_slide_position is Vector3 \
						and lower_slide.position.y - (base_slide_position as Vector3).y >= 0.06,
					"%s should visibly telescope in the static stance (travel=%.3f m)" % [
						rig_name,
						lower_slide.position.y - (base_slide_position as Vector3).y,
					]
				)
			var tire_bottom_y := _find_lowest_mesh_y(lower_slide)
			_check(
				is_finite(tire_bottom_y) and absf(tire_bottom_y) <= 0.004,
				"%s static-stance tire should remain on deck (bottom y=%.4f)" % [rig_name, tire_bottom_y]
			)

	aircraft.set_meta("controls_disabled", true)
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.gravity_scale = 1.0
	aircraft.freeze = false
	aircraft.sleeping = false
	var maximum_active_body_y := frozen_body_y
	for _i in range(60):
		await get_tree().physics_frame
		maximum_active_body_y = maxf(maximum_active_body_y, aircraft.global_position.y)
	_check(
		maximum_active_body_y - frozen_body_y <= 0.025,
		"Physics activation should not pop the aircraft upward (rise=%.4f m)" % (
			maximum_active_body_y - frozen_body_y
		)
	)
	_check(
		absf(aircraft.global_position.y - frozen_body_y) <= 0.04,
		"Physics activation should preserve deck stance height (delta=%.4f m)" % (
			aircraft.global_position.y - frozen_body_y
		)
	)

	flight_deck_manager.free()

	aircraft.queue_free()
	_finish()


func _find_lowest_mesh_y(root: Node) -> float:
	var lowest := INF
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var local_aabb := mesh_instance.get_aabb()
		for x_side in range(2):
			for y_side in range(2):
				for z_side in range(2):
					var corner := local_aabb.position + Vector3(
						local_aabb.size.x * float(x_side),
						local_aabb.size.y * float(y_side),
						local_aabb.size.z * float(z_side)
					)
					lowest = minf(lowest, (mesh_instance.global_transform * corner).y)
	for child in root.get_children():
		lowest = minf(lowest, _find_lowest_mesh_y(child))
	return lowest


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("LANDING_GEAR_STRUT_SMOKE PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("LANDING_GEAR_STRUT_SMOKE: %s" % failure)
	print("LANDING_GEAR_STRUT_SMOKE FAIL count=%d" % _failures.size())
	get_tree().quit(1)
