extends SceneTree


func _initialize() -> void:
	var passed := true
	var tested := 0
	for model in [1, 2, 3, 4, 5, 6, 7, 8, 14]:
		var scene := load("res://Aircraft/Aircraft_%d.tscn" % model) as PackedScene
		var craft := scene.instantiate()
		var aero := craft.get_node("SimpleAero")
		passed = passed and is_equal_approx(float(aero.get("configuration_forward_drag_scale")), 1.0)
		aero.set("configuration_forward_drag_scale", 2.0)
		var gear: float = aero.get("gear_drag_multiplier")
		var flaps: float = aero.get("flaps_drag_multiplier")
		var clean: float = aero.call("get_configuration_forward_drag_multiplier", 1.0)
		var gear_only: float = aero.call("get_configuration_forward_drag_multiplier", gear)
		var dirty: float = aero.call("get_configuration_forward_drag_multiplier", gear * flaps)
		passed = passed and is_equal_approx(clean, 1.0)
		passed = passed and gear_only > gear and dirty > gear * flaps
		passed = passed and is_equal_approx(dirty - 1.0, 2.0 * (gear * flaps - 1.0))
		aero.set("configuration_forward_drag_scale", 1.0)
		passed = passed and is_equal_approx(aero.call("get_configuration_forward_drag_multiplier", gear * flaps), gear * flaps)
		craft.free()
		tested += 1
	print("LANDING_CONFIGURATION_DRAG_SMOKETEST %s models=%d clean_unchanged=true extra_forward_drag=2x legacy_setting=1" % ["PASS" if passed else "FAIL", tested])
	quit(0 if passed else 1)
