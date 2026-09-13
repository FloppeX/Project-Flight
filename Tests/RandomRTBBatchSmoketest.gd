extends SceneTree


func _initialize() -> void:
	var harness_script := load("res://Scenario/LandingTestMode.gd") as Script
	var harness := Node3D.new()
	harness.set_script(harness_script)
	var passed := true
	var profiles: Array[Node] = []
	for model in ["Aircraft_1", "Aircraft_2", "Aircraft_5"]:
		var scene: PackedScene = harness.call("_load_supported_aircraft_scene", model)
		var craft := scene.instantiate()
		profiles.append(craft)
		var pilot := craft.get_node("AIPilot")
		for flag in ["landing_final_energy_aware_throttle", "landing_sight_acceleration_guidance_enabled",
			"landing_sight_vertical_capture_enabled", "landing_sight_high_miss_waveoff_enabled"]:
			passed = passed and bool(pilot.get(flag))
		passed = passed and is_equal_approx(float(pilot.get("landing_bolter_retry_cooldown_s")), 20.0)
		passed = passed and is_equal_approx(float(craft.get_node("SimpleAero").get("flaps_drag_multiplier")), 3.55)
		for i in range(10):
			var entry: Dictionary = harness.call("_random_rtb_entry", i)
			seed(i * 13) # Unrelated scene randomness must not change the manifest.
			var again: Dictionary = harness.call("_random_rtb_entry", i)
			passed = passed and entry == again and int(entry.case_index) == i
			passed = passed and float(entry.distance_m) >= 0.0 and float(entry.distance_m) <= 8000.0
			passed = passed and float(entry.alt_m) >= 500.0 and float(entry.alt_m) <= 1000.0
			passed = passed and float(entry.heading_offset_deg) >= -180.0 and float(entry.heading_offset_deg) <= 180.0
	# All landing/recovery exports match the reference pilot, not just feature toggles.
	var reference := profiles[2].get_node("AIPilot")
	for craft in profiles:
		var pilot := craft.get_node("AIPilot")
		for property in reference.get_property_list():
			var key := str(property.name)
			if key.begins_with("landing_") or key.begins_with("recovery_"):
				if pilot.get(key) != reference.get(key):
					push_error("Recovery profile mismatch: %s %s" % [craft.name, key])
					passed = false
		craft.free()
	harness.free()
	print("RANDOM_RTB_BATCH_SMOKETEST %s models=3 matched_cases=10 bounds=500..1000m/8000m" % ("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
