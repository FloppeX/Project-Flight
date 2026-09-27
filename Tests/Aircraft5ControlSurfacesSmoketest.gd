extends SceneTree

const EPSILON := 0.0001

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate()
	var controller := aircraft.get_node("MovingParts")
	var aero := aircraft.get_node("SimpleAero")
	_expect(controller.bind_surfaces(), "controller could not bind all five imported surfaces")
	var paths := {
		"left": "aircraft_5/outer wing left/aileron left",
		"right": "aircraft_5/outer wing right/aileron right",
		"elevator": "aircraft_5/world_001/body/elevator",
		"rudder_left": "aircraft_5/world_001/body/rudder left",
		"rudder_right": "aircraft_5/world_001/body/rudder right",
	}
	var surfaces: Dictionary = {}
	var rest: Dictionary = {}
	var rest_centers: Dictionary = {}
	for key in paths:
		var surface := aircraft.get_node_or_null(paths[key]) as Node3D
		_expect(surface != null, "%s surface is missing" % key)
		if surface != null:
			surfaces[key] = surface
			rest[key] = surface.transform.basis
			rest_centers[key] = _mesh_center_in_aircraft(surface)
	if surfaces.size() == 5:
		_check_rudder_hinge(surfaces.rudder_left)
		_check_rudder_hinge(surfaces.rudder_right)
		aero.actual_pitch_control = 1.0
		aero.actual_roll_control = 1.0
		aero.actual_yaw_control = 1.0
		controller._process(0.016)
		_expect(_basis_matches(surfaces.left.transform.basis, rest.left * Basis(Vector3.RIGHT, deg_to_rad(22.0))), "left aileron axis/sign is wrong")
		_expect(_basis_matches(surfaces.right.transform.basis, rest.right * Basis(Vector3.UP, deg_to_rad(22.0))), "right aileron axis/sign is wrong")
		_expect(_basis_matches(surfaces.elevator.transform.basis, rest.elevator * Basis(Vector3.RIGHT, deg_to_rad(18.0))), "elevator axis/sign is wrong")
		var expected_rudder: Basis = Basis(Vector3.UP, deg_to_rad(-25.0))
		_expect(_basis_matches(surfaces.rudder_left.transform.basis, rest.rudder_left * expected_rudder), "left rudder axis/sign is wrong")
		_expect(_basis_matches(surfaces.rudder_right.transform.basis, rest.rudder_right * expected_rudder), "right rudder axis/sign is wrong")
		_expect(_mesh_center_in_aircraft(surfaces.left).y > rest_centers.left.y, "positive roll did not raise the left aileron")
		_expect(_mesh_center_in_aircraft(surfaces.right).y < rest_centers.right.y, "positive roll did not lower the right aileron")
		_expect(_mesh_center_in_aircraft(surfaces.elevator).y > rest_centers.elevator.y, "positive pitch did not raise the elevator")
		_expect(_mesh_center_in_aircraft(surfaces.rudder_left).x > rest_centers.rudder_left.x, "positive yaw moved the left rudder the wrong way")
		_expect(_mesh_center_in_aircraft(surfaces.rudder_right).x > rest_centers.rudder_right.x, "positive yaw moved the right rudder the wrong way")
		controller.apply_control_surface_inputs(-1.0, -1.0, -1.0)
		_expect(_mesh_center_in_aircraft(surfaces.left).y < rest_centers.left.y, "negative roll did not lower the left aileron")
		_expect(_mesh_center_in_aircraft(surfaces.right).y > rest_centers.right.y, "negative roll did not raise the right aileron")
		_expect(_mesh_center_in_aircraft(surfaces.elevator).y < rest_centers.elevator.y, "negative pitch did not lower the elevator")
		for key in ["rudder_left", "rudder_right"]:
			_expect(_mesh_center_in_aircraft(surfaces[key]).x < rest_centers[key].x, "negative yaw moved %s the wrong way" % key)
		controller.apply_control_surface_inputs(0.0, 0.0, 0.0)
		for key in surfaces:
			_expect(_basis_matches(surfaces[key].transform.basis, rest[key]), "%s did not return to neutral" % key)
	_finish(aircraft)


func _check_rudder_hinge(surface: MeshInstance3D) -> void:
	var points: Array[Vector3] = []
	var low := INF
	var high := -INF
	for index in range(surface.mesh.get_surface_count()):
		for vertex: Vector3 in surface.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]:
			var point := surface.transform * vertex
			if not points.has(point):
				points.append(point)
			low = minf(low, point.y)
			high = maxf(high, point.y)
	var endpoints: Array[Vector3] = []
	for height in [low, high]:
		var forward := -INF
		for point in points:
			if absf(point.y - height) < EPSILON:
				forward = maxf(forward, point.z)
		var minimum_x := INF
		var maximum_x := -INF
		for point in points:
			if absf(point.y - height) < EPSILON and absf(point.z - forward) < EPSILON:
				minimum_x = minf(minimum_x, point.x)
				maximum_x = maxf(maximum_x, point.x)
		var endpoint := Vector3((minimum_x + maximum_x) * 0.5, height, forward)
		endpoints.append(endpoint)
		var local := surface.transform.affine_inverse() * endpoint
		for angle in [-25.0, 25.0]:
			var moved := surface.transform * (Basis(Vector3.UP, deg_to_rad(angle)) * local)
			_expect(moved.distance_to(endpoint) < EPSILON, "%s forward-edge hinge moves under yaw" % surface.name)
	_expect(surface.position.distance_to((endpoints[0] + endpoints[1]) * 0.5) < EPSILON,
		"%s pivot is not centred on its forward edge" % surface.name)


func _basis_matches(actual: Basis, expected: Basis) -> bool:
	return actual.x.distance_to(expected.x) < EPSILON \
		and actual.y.distance_to(expected.y) < EPSILON \
		and actual.z.distance_to(expected.z) < EPSILON


func _mesh_center_in_aircraft(surface: MeshInstance3D) -> Vector3:
	var accumulated := Transform3D.IDENTITY
	var current: Node = surface
	while current is Node3D:
		accumulated = (current as Node3D).transform * accumulated
		current = current.get_parent()
	return accumulated * surface.mesh.get_aabb().get_center()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(aircraft: Node) -> void:
	aircraft.free()
	if _failures.is_empty():
		print("AIRCRAFT5_CONTROL_SURFACES_PASS")
		quit()
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
