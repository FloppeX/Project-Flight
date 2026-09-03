extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_1.tscn")
const CATAPULT_SCRIPT: Script = preload("res://LandCarrier/Catapult.gd")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_expect(aircraft != null, "Aircraft 1 did not instantiate")
	if aircraft == null:
		_finish()
		return
	aircraft.freeze = true
	add_child(aircraft)
	await get_tree().process_frame

	var wing_fold := aircraft.get_node_or_null("WingFold") as WingFold1
	var left := aircraft.get_node_or_null("LeftWingDamageCollider") as CollisionShape3D
	var right := aircraft.get_node_or_null("RightWingDamageCollider") as CollisionShape3D
	var nose := aircraft.get_node_or_null("CenterGearCollider") as CollisionShape3D
	var main_left := aircraft.get_node_or_null("LeftGearCollider") as CollisionShape3D
	_expect(wing_fold != null, "Aircraft 1 has no wing-fold controller")
	_expect(left != null and right != null, "Aircraft 1 has no localized wing colliders")
	_expect(nose != null and main_left != null, "Aircraft 1 has incomplete launch gear")
	if wing_fold == null or left == null or right == null or nose == null or main_left == null:
		aircraft.free()
		_finish()
		return

	wing_fold.set_process(false)
	for fold_fraction in [1.0, 0.5, 0.0]:
		wing_fold.set_fold_fraction_immediate(fold_fraction)
		await get_tree().process_frame
		_print_collider(fold_fraction, "left", left)
		_print_collider(fold_fraction, "right", right)

	var lowest_wheel_y := minf(nose.position.y, main_left.position.y)
	var left_shape := left.shape as BoxShape3D
	var right_shape := right.shape as BoxShape3D
	var left_bottom := left.position.y - left_shape.size.y * 0.5
	var right_bottom := right.position.y - right_shape.size.y * 0.5
	_expect(
		left_bottom > lowest_wheel_y + 0.25 and right_bottom > lowest_wheel_y + 0.25,
		"unfolded wing collision extends down to the carrier deck before the wheels clear"
	)

	# Catapult ownership ends while the tail is still over the deck. The explicit
	# release grace must reject that residual carrier-body contact, then expire.
	aircraft.linear_velocity = Vector3(0.0, 0.0, 68.0)
	aircraft.set_meta("controls_disabled", true)
	var catapult := Node3D.new()
	catapult.set_script(CATAPULT_SCRIPT)
	catapult.set("launch_carrier_contact_grace_s", 0.75)
	catapult.set("_aircraft", aircraft)
	catapult.call("_release")
	_expect(not aircraft.has_meta("controls_disabled"), "catapult release did not restore aircraft controls")
	aircraft.call("_handle_carrier_body_contact", null)
	_expect(not bool(aircraft.get("_has_exploded")), "release-frame carrier contact destroyed Aircraft 1")
	aircraft.set_meta("carrier_launch_contact_grace_until_msec", Time.get_ticks_msec() - 1)
	aircraft.call("_handle_carrier_body_contact", null)
	_expect(bool(aircraft.get("_has_exploded")), "expired release grace still suppressed a carrier impact")

	catapult.free()
	aircraft.free()
	_finish()


func _print_collider(fold_fraction: float, label: String, collider: CollisionShape3D) -> void:
	var box := collider.shape as BoxShape3D
	print("[Aircraft1LaunchCollisionSmoketest] fold=%.2f %s center=%s size=%s bottom=%.3f" % [
		fold_fraction,
		label,
		collider.position,
		box.size,
		collider.position.y - box.size.y * 0.5,
	])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AIRCRAFT_1_LAUNCH_COLLISION_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft1LaunchCollisionSmoketest] %s" % failure)
	get_tree().quit(1)
