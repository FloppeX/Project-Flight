extends SceneTree

const ELEVATOR_SCRIPT: Script = preload("res://LandCarrier/CarrierElevator.gd")
const COLLISION_SETUP_SCRIPT: Script = preload("res://LandCarrier/CarrierCollisionSetup.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier := CharacterBody3D.new()
	carrier.name = "TestCarrier"

	var legacy_collision := CollisionShape3D.new()
	legacy_collision.name = "MainCollision"
	var legacy_box := BoxShape3D.new()
	legacy_box.size = Vector3(50.0, 26.0, 148.0)
	legacy_collision.shape = legacy_box
	legacy_collision.position = Vector3(0.0, -13.0, 0.0)
	carrier.add_child(legacy_collision)

	var elevator := ELEVATOR_SCRIPT.new() as CarrierElevator
	elevator.name = "Elevator"
	elevator.position = Vector3(-8.0, 0.0, 10.0)
	elevator.start_at_bottom = true
	elevator.move_speed = 3.0
	elevator.cover_slide_speed = 4.5
	carrier.add_child(elevator)
	var elevator_2 := ELEVATOR_SCRIPT.new() as CarrierElevator
	elevator_2.name = "Elevator2"
	elevator_2.position = Vector3(8.0, 0.0, -10.0)
	elevator_2.start_at_bottom = true
	elevator_2.move_speed = 3.0
	elevator_2.cover_slide_speed = 4.5
	carrier.add_child(elevator_2)

	var setup := COLLISION_SETUP_SCRIPT.new() as CarrierCollisionSetup
	setup.name = "CollisionSetup"
	carrier.add_child(setup)
	root.add_child(carrier)
	# CarrierCollisionSetup intentionally waits until the authored carrier has
	# finished constructing all of its children before installing sibling shapes.
	await process_frame
	await physics_frame
	await process_frame

	var compound_shapes := setup.get_compound_collision_shapes()
	_expect(compound_shapes.size() > 5, "dual-shaft compound hull setup failed")
	_expect(legacy_collision.disabled, "legacy solid hull collider remained enabled")
	var shaft_bounds_list := setup.get_shaft_bounds_locals()
	_expect(shaft_bounds_list.size() == 2, "expected two independent shaft bounds")
	for shaft_bounds in shaft_bounds_list:
		_expect(shaft_bounds.size.x >= 10.9 and shaft_bounds.size.z >= 15.9, "shaft did not clear its 10 x 15 m platform")
	_expect(not _point_is_inside_shapes(Vector3(-8.0, -5.0, 10.0), compound_shapes), "forward shaft centre remained physically blocked")
	_expect(not _point_is_inside_shapes(Vector3(8.0, -5.0, -10.0), compound_shapes), "aft shaft centre remained physically blocked")
	_expect(_point_is_inside_shapes(Vector3(0.0, -5.0, 0.0), compound_shapes), "deck collision between the two shafts was lost")
	_expect(_point_is_inside_shapes(Vector3(20.0, -0.05, 0.0), compound_shapes), "deck beside the shaft lost collision coverage")
	_expect(_point_is_inside_shapes(Vector3(0.0, -20.0, 0.0), compound_shapes), "lower hull lost collision coverage")

	var platform_body := elevator.get_platform_body()
	_expect(platform_body != null, "elevator platform is not an AnimatableBody3D")
	_expect(elevator.has_physical_platform(), "elevator platform has no collision shape")
	_expect(elevator.left_cover is AnimatableBody3D and elevator.right_cover is AnimatableBody3D, "elevator covers are not physical moving bodies")
	if platform_body != null:
		_expect(platform_body.collision_layer == 512 and platform_body.collision_mask == 512, "platform was not isolated from the carrier hull collision layer")
		var platform_visual_root := elevator.get_platform_visual_root()
		var platform_visual := platform_visual_root.get_node_or_null("PlatformVisual") as MeshInstance3D if platform_visual_root != null else null
		_expect(platform_visual != null and platform_visual.position.y > 0.0, "platform visual was left coplanar with the carrier deck")
		_expect(platform_visual_root != null and platform_visual_root.find_children("PerimeterMarking*", "MeshInstance3D", false, false).size() == 4, "platform perimeter markings are missing")
		_expect_hazard_perimeter(platform_visual_root, elevator.platform_size.x, elevator.platform_size.z, elevator.perimeter_marking_width_m, "platform")
		_expect(platform_visual_root != null and platform_visual_root.global_transform.is_equal_approx(platform_body.global_transform), "platform render root did not follow the physical body")
	var left_cover_visual_root := elevator.get_left_cover_visual_root()
	var left_cover_visual := left_cover_visual_root.get_node_or_null("LeftCoverVisual") as MeshInstance3D if left_cover_visual_root != null else null
	_expect(left_cover_visual != null and left_cover_visual.position.y > 0.0, "cover visual was left coplanar with the carrier deck")
	_expect(left_cover_visual_root != null and left_cover_visual_root.find_children("PerimeterMarking*", "MeshInstance3D", false, false).size() == 4, "cover perimeter markings are missing")
	_expect_hazard_perimeter(left_cover_visual_root, elevator.cover_size.x, elevator.cover_size.z, elevator.perimeter_marking_width_m, "cover")
	_expect(left_cover_visual_root != null and left_cover_visual_root.global_transform.is_equal_approx(elevator.left_cover.global_transform), "cover render root did not follow the physical body")

	var test_body := RigidBody3D.new()
	test_body.name = "PhysicsEnabledAircraftProxy"
	# Use a carrier-aircraft-scale mass so the joint is not only tested with a toy body.
	test_body.mass = 1200.0
	test_body.collision_layer = 513
	test_body.collision_mask = 513
	test_body.linear_damp = 1.5
	test_body.angular_damp = 4.0
	var body_collision := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(2.0, 1.0, 3.0)
	body_collision.shape = body_box
	test_body.add_child(body_collision)
	root.add_child(test_body)
	test_body.global_position = Vector3(-8.0, elevator.get_status()["platform_y"] + 1.0, 10.0)

	for _frame in range(45):
		await physics_frame
	var proxy_half_height := body_box.size.y * 0.5
	var bottom_expected_y := -elevator.shaft_depth + elevator.platform_size.y * 0.5 + proxy_half_height
	_expect(absf(test_body.global_position.y - bottom_expected_y) <= 0.35, "dynamic body did not settle on the physical platform at hangar level")
	var settled_bottom_y := test_body.global_position.y
	var original_layer := test_body.collision_layer
	var original_mask := test_body.collision_mask
	var restraint := elevator.create_platform_restraint(test_body)
	_expect(restraint != null, "elevator could not create a physical platform restraint")

	elevator.move_platform_up()
	var recessed_cover_y := -elevator.cover_size.y * 0.5 - elevator.cover_recess_depth_m
	var timeout_frames := 360
	while timeout_frames > 0 and elevator.current_state != CarrierElevator.ElevatorState.AT_TOP:
		timeout_frames -= 1
		# The real carrier can translate and turn during deck operations. Exercise
		# parent motion so the restraint must follow more than elevator-local Y.
		carrier.position += Vector3(0.025, 0.0, 0.01)
		carrier.rotation.y += 0.00075
		await physics_frame
	for _frame in range(120):
		await physics_frame
	await process_frame
	var top_expected_y := proxy_half_height
	_expect(timeout_frames > 0, "physical elevator did not reach the deck")
	_expect(absf(test_body.global_position.y - top_expected_y) <= 0.45, "physical platform did not carry the dynamic body to deck level")
	_expect(absf(elevator.get_cover_local_y() - recessed_cover_y) <= 0.03, "open covers did not remain beneath the flight deck")
	_expect(elevator.covers_are_open(), "covers were not fully open when the platform reached deck level")
	var platform_visual_root := elevator.get_platform_visual_root()
	_expect(platform_visual_root != null and platform_visual_root.global_transform.is_equal_approx(platform_body.global_transform), "platform render root stopped following during elevator travel")
	var platform_carrier_local := carrier.to_local(platform_body.global_position)
	_expect(Vector2(platform_carrier_local.x + 8.0, platform_carrier_local.z - 10.0).length() <= 0.05, "physical elevator did not remain at its authored offset on the moving carrier")
	_expect(absf(platform_carrier_local.y + elevator.platform_size.y * 0.5) <= 0.05, "physical elevator did not remain at carrier deck height")
	var body_carrier_local := carrier.to_local(test_body.global_position)
	_expect(Vector2(body_carrier_local.x + 8.0, body_carrier_local.z - 10.0).length() <= 0.5, "dynamic body slid off the moving/turning elevator")
	_expect(test_body.collision_layer == original_layer and test_body.collision_mask == original_mask, "elevator ride changed body collision settings")
	_expect(not test_body.freeze and test_body.gravity_scale > 0.0, "elevator ride disabled body physics")
	var settled_top_y := test_body.global_position.y

	# The live carrier is relocated after its children enter the tree. Reproduce a
	# large initial-placement jump so the lift cannot silently remain at its old
	# world origin while aircraft are spawned there.
	elevator.release_platform_restraint(test_body)
	carrier.position += Vector3(280.0, 35.0, -140.0)
	carrier.rotation.y += 0.7
	for _frame in range(2):
		await physics_frame
		await process_frame
	var relocated_platform_local := carrier.to_local(platform_body.global_position)
	_expect(relocated_platform_local.distance_to(Vector3(-8.0, -elevator.platform_size.y * 0.5, 10.0)) <= 0.05, "physical elevator remained behind after carrier relocation: %s" % relocated_platform_local)
	_expect(platform_visual_root != null and platform_visual_root.global_position.distance_to(platform_body.global_position) <= 0.05, "elevator visual remained behind after carrier relocation: body=%s visual=%s" % [platform_body.global_position, platform_visual_root.global_position if platform_visual_root != null else Vector3.INF])

	# On descent, the plates must slide together while recessed, then rise to form
	# a collision surface exactly flush with the surrounding flight deck.
	elevator.move_platform_down()
	var saw_recessed_closing := false
	var saw_cover_raise := false
	timeout_frames = 420
	while timeout_frames > 0 and elevator.current_state != CarrierElevator.ElevatorState.AT_BOTTOM:
		timeout_frames -= 1
		if elevator.current_state == CarrierElevator.ElevatorState.COVERS_CLOSING:
			saw_recessed_closing = saw_recessed_closing \
					or absf(elevator.get_cover_local_y() - recessed_cover_y) <= 0.03
		if elevator.current_state == CarrierElevator.ElevatorState.COVERS_RAISING:
			saw_cover_raise = true
		await physics_frame
	_expect(timeout_frames > 0, "elevator descent/cover sequence timed out")
	_expect(saw_recessed_closing, "covers did not slide into place beneath the flight deck")
	_expect(saw_cover_raise, "covers did not rise after sliding closed")
	_expect(elevator.covers_are_closed(), "closed covers did not finish flush with the flight deck")
	_expect(absf(elevator.get_cover_local_y() + elevator.cover_size.y * 0.5) <= 0.03, "closed cover surface was not at deck level")

	print("CARRIER_ELEVATOR_COLLISION_SMOKETEST ", JSON.stringify({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"compound_shapes": compound_shapes.size(),
		"shaft_count": shaft_bounds_list.size(),
		"bottom_body_y": settled_bottom_y,
		"top_body_y": settled_top_y,
		"platform_y": elevator.get_status()["platform_y"],
		"elevator_state": elevator.current_state,
		"elevator_physics_processing": elevator.is_physics_processing(),
		"collision_layer": test_body.collision_layer,
		"collision_mask": test_body.collision_mask,
		"failures": _failures,
	}))
	test_body.free()
	carrier.free()
	await physics_frame
	quit(0 if _failures.is_empty() else 1)


func _point_is_inside_shapes(point: Vector3, shapes: Array[CollisionShape3D]) -> bool:
	for collision in shapes:
		var box := collision.shape as BoxShape3D
		if box == null:
			continue
		var local_point := collision.transform.affine_inverse() * point
		var half_size := box.size * 0.5
		if absf(local_point.x) <= half_size.x \
				and absf(local_point.y) <= half_size.y \
				and absf(local_point.z) <= half_size.z:
			return true
	return false


func _expect_hazard_perimeter(root_node: Node3D, width: float, depth: float, expected_band_width: float, label: String) -> void:
	if root_node == null:
		return
	var front := root_node.get_node_or_null("PerimeterMarking0") as MeshInstance3D
	var side := root_node.get_node_or_null("PerimeterMarking2") as MeshInstance3D
	_expect(front != null and side != null, "%s warning band edges are missing" % label)
	if front == null or side == null:
		return
	var front_box := front.mesh as BoxMesh
	var side_box := side.mesh as BoxMesh
	_expect(front_box != null and side_box != null, "%s warning bands do not use box meshes" % label)
	if front_box == null or side_box == null:
		return
	_expect(
		absf(absf(front.position.z) + front_box.size.z * 0.5 - depth * 0.5) <= 0.001,
		"%s front warning band does not begin at the surface edge" % label
	)
	_expect(
		absf(absf(side.position.x) + side_box.size.x * 0.5 - width * 0.5) <= 0.001,
		"%s side warning band does not begin at the surface edge" % label
	)
	_expect(
		absf(front_box.size.z - expected_band_width) <= 0.001 \
				and absf(side_box.size.x - expected_band_width) <= 0.001,
		"%s warning band does not match the configured width" % label
	)
	var warning_material := front.material_override as ShaderMaterial
	_expect(
		warning_material != null and warning_material.shader != null \
				and warning_material.shader.resource_path.ends_with("carrier_elevator_hazard.gdshader"),
		"%s warning band is not using the diagonal hazard shader" % label
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[CarrierElevatorCollisionSmoketest] %s" % message)
