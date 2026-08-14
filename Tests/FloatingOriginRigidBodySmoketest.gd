extends SceneTree

const FloatingOriginScript: Script = preload("res://Environment/FloatingOrigin.gd")
const SHIFT := Vector3(24000.0, 0.0, -7000.0)
const EPSILON_M := 0.05


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "FloatingOriginRigidBodySmoketest"
	root.add_child(scene)
	current_scene = scene

	# Keep the body below a shifted parent and deliberately do not put it in the
	# origin_shifter group. This covers the aircraft startup window that caused the
	# regression: the central shift must synchronize it without a ready callback.
	var branch := Node3D.new()
	branch.position = Vector3(24020.0, 100.0, -6970.0)
	scene.add_child(branch)
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.position = Vector3(8.0, 0.0, 12.0)
	branch.add_child(body)

	await physics_frame
	var before := body.global_position
	var expected := before - SHIFT
	var floating_origin: Node = FloatingOriginScript.new()
	floating_origin.set("enabled", false)
	scene.add_child(floating_origin)
	floating_origin.call("shift_origin", SHIFT)

	if body.global_position.distance_to(expected) > EPSILON_M:
		_fail("body was not translated immediately", body.global_position, expected)
		return

	# The historical failure appeared here: PhysicsServer3D restored the old
	# transform one tick after the visible hierarchy had moved.
	await physics_frame
	if body.global_position.distance_to(expected) > EPSILON_M:
		_fail("body snapped back after the physics tick", body.global_position, expected)
		return

	print("[FloatingOriginRigidBodySmoketest] PASS before=%s after=%s" % [
		str(before.snapped(Vector3.ONE * 0.01)),
		str(body.global_position.snapped(Vector3.ONE * 0.01)),
	])
	quit(0)


func _fail(reason: String, actual: Vector3, expected: Vector3) -> void:
	push_error("[FloatingOriginRigidBodySmoketest] FAIL %s actual=%s expected=%s" % [
		reason,
		str(actual),
		str(expected),
	])
	quit(1)
