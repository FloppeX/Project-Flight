extends SceneTree


func _initialize() -> void:
	var sight: Variant = load("res://AI/LandingSight.gd")
	var pilot := Node.new()
	pilot.set_script(load("res://AI/AIPilot.gd"))
	var passed := true
	var far: float = pilot.call("_lineup_capture_bank_limit_for_remaining", 1950.0, 1.0)
	var midway: float = pilot.call("_lineup_capture_bank_limit_for_remaining", 1300.0, 1.0)
	var gate: float = pilot.call("_lineup_capture_bank_limit_for_remaining", 1000.0, 1.0)
	var centered: float = pilot.call("_lineup_capture_bank_limit_for_remaining", 1950.0, 0.0)
	passed = passed and is_equal_approx(far, 35.0) and midway < far and midway > gate
	passed = passed and is_equal_approx(gate, 12.0) and centered < 5.0
	for bank in [5.0, 12.0, 35.0]:
		for support in [3.5, 9.81, 12.0]:
			var limited: float = sight.bounded_lineup_lateral_acceleration(137.6, support, deg_to_rad(bank))
			passed = passed and absf(limited - support * tan(deg_to_rad(bank))) < 0.001
			passed = passed and is_equal_approx(-limited,
				sight.bounded_lineup_lateral_acceleration(-137.6, support, deg_to_rad(bank)))
	passed = passed and is_equal_approx(sight.bounded_lineup_lateral_acceleration(0.5, 9.81, deg_to_rad(35.0)), 0.5)
	passed = passed and is_zero_approx(sight.bounded_lineup_lateral_acceleration(100.0, 9.81, 0.0))
	pilot.free()
	print("LINEUP_CAPTURE_AUTHORITY_SMOKETEST %s early=35deg gate=12deg centered<5deg force_bounded=true" % ("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
