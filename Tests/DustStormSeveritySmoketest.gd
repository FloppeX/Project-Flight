extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _health(aircraft: Node) -> float:
	var parts := aircraft.get_node_or_null("PartDamageModel")
	return float(parts.get_zone_health(&"fuselage")) if parts != null else float(aircraft.current_health)

func expose(front: Node3D, aircraft: Node3D, seconds: float) -> void:
	aircraft.process_mode = Node.PROCESS_MODE_INHERIT
	aircraft.set("_last_damage_ms", 0)
	aircraft.linear_velocity = front.get_wind_at(aircraft.global_position) + Vector3(100, 0, 0)
	front._apply_exposure_damage(seconds)
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED

func _run() -> void:
	await process_frame
	root.get_node("FloatingOrigin").set("enabled", false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var front := load("res://Weather/DustFront.gd").new() as Node3D
	front.automatic_start = false
	scene.add_child(front)
	front.set_physics_process(false)
	front.start_at(Vector3.ZERO, Vector3.BACK)
	front.elapsed_s = 120.0
	front.strength = 1.0
	var core := Vector3(0, 500, 0)
	var previous_visibility := INF
	var previous_wind := 0.0
	for level in range(1, 6):
		front.severity = level
		check(front.get_visibility_m(core) < previous_visibility, "Visibility must decrease at each strength")
		check(front.get_wind_at(core).length() > previous_wind, "Wind must increase at each strength")
		previous_visibility = front.get_visibility_m(core)
		previous_wind = front.get_wind_at(core).length()
		check((front.get_damage_fraction_per_second(core, 100.0) > 0.0) == (level >= 4), "Only severe/extreme dust directly damages aircraft")
	check(is_equal_approx(front.get_visibility_m(core), 30.0), "Extreme core targets 30 m contrast visibility")
	check(front.get_damage_fraction_per_second(Vector3(0, 500, 5000), 100.0) == 0.0, "No abrasion outside the front")
	front.enabled = false
	check(front.get_damage_fraction_per_second(core, 100.0) == 0.0, "Disabled storm cannot damage aircraft")
	front.enabled = true
	for path in ["res://Aircraft/Aircraft_1.tscn", "res://Aircraft/Aircraft_11.tscn"]:
		var aircraft := load(path).instantiate() as RigidBody3D
		aircraft.freeze = true
		aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		aircraft.position = core
		scene.add_child(aircraft)
		await process_frame
		await process_frame
		await physics_frame
		aircraft.linear_velocity = front.get_wind_at(core) + Vector3(100, 0, 0)
		var initial := _health(aircraft)
		front.severity = 2
		expose(front, aircraft, 10.0)
		check(is_equal_approx(_health(aircraft), initial), "Moderate storm leaves aircraft intact: " + path)
		front.severity = 5
		aircraft.hide()
		expose(front, aircraft, 2.0)
		check(is_equal_approx(_health(aircraft), initial * 0.9), "Extreme storm damages real aircraft at the intended rate: " + path)
		aircraft.show()
		var roof := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(40, 2, 40)
		collision.shape = shape
		roof.add_child(collision)
		roof.position = core + Vector3.UP * 15.0
		scene.add_child(roof)
		await physics_frame
		await physics_frame
		var sheltered_health := _health(aircraft)
		expose(front, aircraft, 5.0)
		check(is_equal_approx(_health(aircraft), sheltered_health), "Hangar roof protects aircraft: " + path)
		roof.free()
		await physics_frame
		expose(front, aircraft, 20.0)
		check(_health(aircraft) <= 0.0 and bool(aircraft.get("_critical_damage_active")), "Extreme exposure triggers actual critical failure: " + path)
		aircraft.queue_free()
		await process_frame
	print("DUST_STORM_SEVERITY_OK levels=5 fixed_wing=true helicopter=true shelter=true" if failures.is_empty() else "DUST_STORM_SEVERITY_FAILED " + str(failures))
	quit(0 if failures.is_empty() else 1)
