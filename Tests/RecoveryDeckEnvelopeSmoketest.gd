extends SceneTree

class CollisionSetup:
	extends Node
	func get_hull_bounds_local() -> AABB:
		return AABB(Vector3(-25, -20, -75), Vector3(50, 20, 150))

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var sight: Variant = load("res://AI/LandingSight.gd")
	_check(sight.bolter_clearance_fpa_floor_rad(5.0, 60.0, 15.0) > 0.09, "deck escape must command positive clearance")
	_check(is_zero_approx(sight.bolter_clearance_fpa_floor_rad(30.0, 60.0, 15.0)), "clearance cue releases above deck")
	var hull := AABB(Vector3(-25, -20, -75), Vector3(50, 20, 150))
	for side in [-1.0, 1.0]:
		_check(sight.bolter_clear_of_hull(Vector3(side * 100, 20, 0), Vector3(side * 40, 0, 0), hull),
			"sideways outward escape may rejoin without ever passing bow")
		_check(not sight.bolter_clear_of_hull(Vector3(side * 100, 20, 0), Vector3(-side * 100, 0, 0), hull),
			"safe endpoints must not hide a response path through the hull")
		_check(sight.bolter_clear_of_hull(Vector3(0, 20, side * 150), Vector3(0, 0, side * 40), hull),
			"outward bow and stern escapes are symmetric")
	_check(not sight.bolter_clear_of_hull(Vector3(0, 10, 0), Vector3(0, 0, 50), hull),
		"low aircraft over deck must keep wings level")
	_check(sight.bolter_clear_of_hull(Vector3(0, 80, 0), Vector3(0, 0, 50), hull),
		"adequate overhead clearance permits rejoin")
	_check(not sight.bolter_clear_of_hull(Vector3(0, 80, 0), Vector3(0, -30, 0), hull),
		"rapid descent into clearance envelope prevents early turn")
	_check(not sight.bolter_clear_of_hull(Vector3(NAN, 0, 0), Vector3.ZERO, hull), "unknown clearance is not clear")
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var carrier := Node3D.new()
	carrier.add_to_group("carrier")
	scene.add_child(carrier)
	var setup := CollisionSetup.new()
	setup.name = "CollisionSetup"
	carrier.add_child(setup)
	var craft := RigidBody3D.new()
	craft.freeze = true
	scene.add_child(craft)
	var pilot := Node.new()
	pilot.set_script(load("res://AI/AIPilot.gd"))
	craft.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.set("aircraft", craft)
	for heading in [0.0, 1.2, PI, -1.8]:
		carrier.rotation.y = heading
		carrier.position = Vector3(230, 522, -440)
		craft.global_position = carrier.to_global(Vector3(-500, 100, -250))
		craft.linear_velocity = carrier.global_basis * Vector3(-100, 0, 0)
		_check(pilot.call("_is_bolter_clear_of_carrier"), "logged sideways escape releases at every carrier heading")
		craft.global_position = carrier.to_global(Vector3(0, 10, 0))
		craft.linear_velocity = carrier.global_basis * Vector3(0, 0, 50)
		_check(not pilot.call("_is_bolter_clear_of_carrier"), "live low deck escape retains clearance protection")
		craft.global_position = carrier.to_global(Vector3(0, 10, -170))
		craft.linear_velocity = carrier.global_basis * Vector3(0, -8, 50)
		var guard: Dictionary = pilot.call("_landing_sight_stern_guard",
			{"valid": true, "position": craft.global_position}, Vector3.UP, carrier.global_basis.z)
		_check(guard.get("valid", false), "finite stern guard must resolve at every carrier heading")
		_check(absf(float(guard.get("distance_m", INF)) - 100.0) < 0.01, "guard must use hull stern plus inside margin")
		_check(absf(float(guard.get("height_m", INF)) - 10.0) < 0.01, "guard must use world-space hull height")
		_check(float(guard.get("sink_floor_mps", -INF)) > -3.0, "unsafe descent must receive a clearance cue")
		craft.global_position = carrier.to_global(Vector3(0, 10, -65))
		guard = pilot.call("_landing_sight_stern_guard", {"valid": true, "position": craft.global_position},
			Vector3.UP, carrier.global_basis.z)
		_check(not guard.get("valid", true), "stern constraint must release once wheels are inside the deck")
	for side in [-1.0, 1.0]:
		var wheel := CollisionShape3D.new()
		wheel.name = "LeftGearCollider" if side < 0.0 else "RightGearCollider"
		var shape := SphereShape3D.new()
		shape.radius = 0.5
		wheel.shape = shape
		wheel.position = Vector3(side * 3.0, -1.0, 0.0)
		craft.add_child(wheel)
	craft.rotation.z = 0.3
	var sensor: Dictionary = pilot.call("_get_landing_sight_main_gear_sensor", Vector3.UP)
	_check(sensor.get("valid", false), "authored main wheels must supply the clearance sensor")
	_check(Vector3(sensor.lowest_position).y < Vector3(sensor.position).y - 0.8,
		"stern safety must use lower wheel rather than average wheel height when banked")
	setup.queue_free()
	scene.free()
	print("RECOVERY_DECK_ENVELOPE_SMOKETEST %s headings=4" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
