extends SceneTree

class AtmosphereProbe extends Node:
	var ambient_visibility_m := 10000.0
	var dust_layer_top_m := 2000.0
	var dust_deck_vertical_offset_m := -800.0
	var dust_deck_upper_vertical_offset_m := 0.0
	func _ready() -> void: add_to_group("day_night_cycle")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	await process_frame
	if "--main" in OS.get_cmdline_user_args():
		await _run_main()
		return
	root.get_node("FloatingOrigin").enabled = false
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var field := load("res://Weather/WindField.gd").new() as Node3D
	scene.add_child(field)
	field.set_physics_process(false)
	var atmosphere := AtmosphereProbe.new()
	scene.add_child(atmosphere)
	var director := load("res://Weather/WeatherDirector.gd").new() as Node
	director.automatic_hazards = false
	scene.add_child(director)
	director.set_physics_process(false)
	var clear: Dictionary = director.get_snapshot()
	check(clear.visibility_m > 6500.0, "Initial clear weather preserves the 5/5 view-distance range")
	check(is_equal_approx(atmosphere.dust_layer_top_m, 2000.0), "Initial dust upper altitude is deck-relative 2000 m")
	check(is_equal_approx(atmosphere.dust_deck_vertical_offset_m, -800.0), "Initial dust lower altitude is deck-relative 1200 m")
	var target: Dictionary = director._target.duplicate()
	target.wind_x = -12.0
	target.wind_z = 1.0
	target.visibility = 2600.0
	target.lower = 850.0
	target.upper = 1650.0
	target.turbulence = 2.0
	director._target = target
	director._next_change_s = 99999.0
	director._physics_process(180.0)
	var changed: Dictionary = director.get_snapshot()
	check(changed.visibility_m < clear.visibility_m and changed.visibility_m > 2600.0,
		"Weather visibility changes smoothly rather than jumping")
	check(atmosphere.ambient_visibility_m == changed.visibility_m,
		"Fog range receives the regional visibility limit")
	check(atmosphere.dust_layer_top_m < 2000.0 and atmosphere.dust_layer_top_m > 1650.0,
		"Dust layer height follows the same transition")
	check(field.prevailing_velocity_mps.x < 4.0 and field.gust_amplitude_mps.x > 3.0,
		"Wind direction and gust strength follow the same transition")
	var sample := Vector3(170.0, 120.0, -80.0)
	var before: Vector3 = field.get_velocity_at(sample)
	field.prevailing_velocity_mps += Vector3(2.0, 0.0, 0.0)
	field._physics_process(0.1)
	var after: Vector3 = field.get_velocity_at(sample)
	check((after - before).length() < 4.0, "Wind advection does not jump when prevailing wind changes")
	var saved: Dictionary = director.capture_save_state()
	director._state.visibility = 800.0
	director.restore_save_state(saved)
	check(is_equal_approx(float(director.get_snapshot().visibility_m), float(changed.visibility_m)),
		"Saved weather restores its visibility and transition state")
	var front := load("res://Weather/DustFront.gd").new() as Node3D
	scene.add_child(front)
	front.set_physics_process(false)
	front.start_at(Vector3(1200.0, -400.0, 500.0), Vector3.RIGHT)
	front.elapsed_s = 90.0
	front.strength = 1.0
	front.severity = 4
	var with_front: Dictionary = director.capture_save_state()
	front.global_position = Vector3.ZERO
	front.severity = 1
	director.restore_save_state(with_front)
	check(front.global_position.is_equal_approx(Vector3(1200.0, -400.0, 500.0)) and front.severity == 4,
		"Active dust front position and severity survive weather save/restore")
	var carrier := Node3D.new()
	scene.add_child(carrier)
	carrier.global_position = Vector3(0.0, 500.0, 0.0)
	var manual_position := front.global_position
	director._spawn_dust(carrier)
	check(front.global_position.is_equal_approx(manual_position), "Automatic weather does not replace an active manual storm")
	front.elapsed_s = front.lifetime_s
	director._spawn_dust(carrier)
	check(front.elapsed_s == 0.0 and front.initialized, "An expired front can be reused by regional weather")
	director._spawn_twister(carrier)
	check(get_nodes_in_group("twister").size() == 1, "Regional weather can create a twister")
	director._spawn_electrical(carrier)
	check(get_nodes_in_group("electrical_storm").size() == 1, "Regional weather can create an electrical cell")
	var electrical := load("res://Weather/ElectricalStorm.gd").new() as Node3D
	scene.add_child(electrical)
	electrical.set_physics_process(false)
	electrical.start_at(Vector3(0.0, 0.0, 0.0), Vector3.RIGHT)
	electrical._strike()
	var electrical_lower: float = electrical._get_dust_layer_heights().x
	check(absf(electrical.get_node("ChargedDustLayer/CloudSparks").global_position.y
		- (electrical_lower - 85.0)) < 0.01,
		"Cloud sparks stay attached to the moving dust-layer underside")
	check(electrical._last_strike_origin.y >= electrical_lower - 65.0
		and Vector2(electrical._last_strike_impact.x, electrical._last_strike_impact.z).length()
		<= electrical.cloud_radius_m * 0.82 + 0.01,
		"Random lightning begins at the dust layer and lands within its dark area")
	check(electrical.get_node("LightningFlash").visible and electrical.get_node("LightningSkyFlash").visible
		and electrical.get_node("LightningImpactHalo").visible
		and electrical.get_node("LightningBolt").get_child_count() == 20,
		"Electrical storm builds ground and sky glow around a layered bolt")
	var bolt := electrical.get_node("LightningBolt")
	var core_segment := bolt.get_child(1) as MeshInstance3D
	check((core_segment.mesh.material as StandardMaterial3D).albedo_color.is_equal_approx(Color.WHITE)
		and electrical.get_node("LightningFlash").light_color.b > electrical.get_node("LightningFlash").light_color.r,
		"Lightning has a white core and an icy blue glow")
	electrical._physics_process(0.5)
	check(is_equal_approx(electrical.get_node("LightningFlash").light_energy, 14.0)
		and is_equal_approx(core_segment.transparency, 0.0),
		"Strike remains fully visible for half a second")
	electrical._physics_process(0.5)
	check(absf(electrical.get_node("LightningFlash").light_energy - 7.0) < 0.01
		and absf(core_segment.transparency - 0.5) < 0.01,
		"Bolt and light fade together over the following second")
	electrical._physics_process(0.5)
	check(not electrical.get_node("LightningFlash").visible and not electrical.get_node("LightningImpactHalo").visible,
		"Bolt and glow clear after the full 1.5-second strike")
	if failures.is_empty():
		print("WEATHER_DIRECTOR_SMOKETEST_OK")
	quit(0 if failures.is_empty() else 1)

func _run_main() -> void:
	root.get_node("FloatingOrigin").enabled = false
	var scene := load("res://Main_Scene.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 20:
		await process_frame
	var director := scene.get_node_or_null("WeatherDirector")
	var atmosphere := scene.get_node_or_null("DayNightCycle")
	var wind := scene.get_node_or_null("ContinuousTurbulence/WindField")
	var legacy := scene.get_node_or_null("ContinuousTurbulence")
	check(director != null and director.enabled, "Normal scene starts with regional weather active")
	check(atmosphere != null and wind != null and legacy != null, "Normal scene has linked atmosphere and wind")
	if director != null and atmosphere != null and wind != null and legacy != null:
		var report: Dictionary = director.get_snapshot()
		check(is_equal_approx(atmosphere.ambient_visibility_m, float(report.visibility_m)),
			"Normal scene uses regional visibility")
		check(is_equal_approx(atmosphere.dust_layer_top_m, float(report.dust_upper_m)),
			"Normal scene uses regional dust-layer height")
		check(wind.prevailing_velocity_mps.is_equal_approx(report.wind_mps),
			"Normal scene uses regional prevailing wind")
		check(is_equal_approx(legacy.max_intensity, 3.0),
			"Normal scene preserves its authored helicopter turbulence baseline")
	print("WEATHER_MAIN_SCENE_", "OK" if failures.is_empty() else "FAILED")
	quit(0 if failures.is_empty() else 1)
