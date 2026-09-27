extends Node3D

class Wind extends Node3D:
	var velocity := Vector3(15, 0, 0)
	func get_velocity_at(_position: Vector3) -> Vector3:
		return velocity

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var failures: Array[String] = []
	var wind := Wind.new()
	add_child(wind)
	wind.add_to_group("atmospheric_wind")
	for index in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14]:
		var packed: PackedScene = load("res://Aircraft/Aircraft_%d.tscn" % index)
		var authored := packed.instantiate()
		var source: Node = authored.get_node("SimpleAero")
		# Exercise each authored aerodynamic configuration on an isolated body.
		var aero: Node = source.duplicate()
		authored.free()
		var body := RigidBody3D.new()
		body.mass = 1000.0
		body.gravity_scale = 0.0
		add_child(body)
		aero.set("rb_path", NodePath(".."))
		if index in [9, 10, 11, 12]:
			aero.set("debug_overlay_enabled", false)
		else:
			aero.set("aero_report_enabled", false)
		body.add_child(aero)
		aero.set_physics_process(false)
		body.gravity_scale = 0.0
		aero.set("_wind_field", wind)
		body.linear_velocity = Vector3(0, 0, 30)
		if not aero.get_air_relative_velocity().is_equal_approx(Vector3(-15, 0, 30)):
			failures.append("Aircraft_%d does not sample wind" % index)
		if index in [9, 10, 11, 12]:
			body.linear_velocity = Vector3.ZERO
			for frame in 60:
				aero._apply_drag(15.0)
				await get_tree().physics_frame
			if body.linear_velocity.x <= 0.05:
				failures.append("Aircraft_%d wind did not move body" % index)
			body.linear_velocity = wind.velocity
			if aero.get_air_relative_velocity().length() > 0.001:
				failures.append("Aircraft_%d moving with wind still has airflow" % index)
		wind.velocity = Vector3.ZERO
		if not aero.get_air_relative_velocity().is_equal_approx(body.linear_velocity):
			failures.append("Aircraft_%d calm airflow changed" % index)
		wind.velocity = Vector3(15, 0, 0)
		body.queue_free()
		await get_tree().process_frame
	for failure in failures: push_error(failure)
	print("FLEET_WIND_COVERAGE_%s aircraft=13" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
