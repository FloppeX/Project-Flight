extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var passed := true
	for model in [1, 2, 3, 4, 5, 6, 7, 8, 14]:
		var packed := load("res://Aircraft/Aircraft_%d.tscn" % model) as PackedScene
		var craft := packed.instantiate() as RigidBody3D
		craft.freeze = true
		root.add_child(craft)
		craft.set_physics_process(false)
		var aero := craft.get_node("SimpleAero")
		aero.set_physics_process(false)
		var pilot := craft.get_node("AIPilot")
		pilot.set_physics_process(false)
		await process_frame
		var flaps := craft.get_node("Flaps")
		var gear := craft.get_node("ControlLandingGear")
		gear.set("gear_down_state", true)
		pilot.set("aircraft", craft)
		pilot.set("control_gear", gear)
		pilot.call("_deploy_landing_gear")
		flaps.call("process_physic_frame", 1.1)
		var detected: bool = aero.call("_is_flaps_deployed")
		var stall: float = aero.call("get_effective_stall_speed_mps")
		print("FLAP_WIRING Aircraft_%d actual=1 detected=%s stall=%.1f cache=%s" % [model, detected, stall, aero.get("_flaps_module")])
		passed = passed and detected
		passed = passed and is_equal_approx(stall, float(aero.get("stall_speed")) * float(aero.get("flaps_stall_speed_factor")))
		gear.set("gear_down_state", false)
		pilot.call("_stow_landing_config")
		flaps.call("process_physic_frame", 1.1)
		passed = passed and not bool(aero.call("_is_flaps_deployed"))
		flaps.call("flap_set_position", 1.0)
		flaps.call("flap_set_position", 0.0)
		passed = passed and is_zero_approx(float(flaps.get("target_flap_position")))
		craft.free()
	print("LANDING_FLAP_WIRING_SMOKETEST %s" % ("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
