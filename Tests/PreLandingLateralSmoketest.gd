extends SceneTree

const Sight = preload("res://AI/LandingSight.gd")

func _initialize() -> void:
	var failures: Array[String] = []
	var braking := Sight.pre_landing_lateral_accel(-130, 25, 0.6, 4)
	if braking >= 0: failures.append("fast inward drift is still accelerating toward the line")
	if not is_equal_approx(braking, -Sight.pre_landing_lateral_accel(130, -25, 0.6, 4)):
		failures.append("left and right behavior differs")
	if Sight.pre_landing_lateral_accel(0, 0, 0.6, 4) != 0:
		failures.append("settled centreline requests a turn")
	for side in [-1.0, 1.0]:
		var late_accel := Sight.pre_landing_lateral_accel(-400.0 * side, 25.0 * side, 0.6, 4.0, 5.0)
		if late_accel * side >= 0.0:
			failures.append("large offset keeps accelerating sideways too close to handoff")
		var x: float = -300.0 * side
		var v := 0.0
		var a := 0.0
		for i in 1200:
			var request := Sight.pre_landing_lateral_accel(x, v, 0.6, 4.0, 20.0 - i / 60.0)
			a = lerpf(a, request, 1.0 - exp(-1.0 / 60.0 / 0.6))
			v += a / 60.0
			x += v / 60.0
		if absf(v) > 1.0 or absf(x) >= 300.0:
			failures.append("handoff did not reduce offset and settle drift: %s %s" % [x, v])
	for side in [-1.0, 1.0]:
		var x: float = side * 250.0
		var v: float = side * 10.0
		var actual_accel := 0.0
		var crossed := false
		for i in range(2400):
			var request := Sight.pre_landing_lateral_accel(x, v, 0.6, 4)
			actual_accel = lerpf(actual_accel, request, 1.0 - exp(-1.0 / 60.0 / 0.6))
			v += actual_accel / 60.0
			x += v / 60.0
			if x * side < -1.0: crossed = true
		if absf(x) > 1.0 or absf(v) > 0.3 or crossed:
			failures.append("lagged lateral model did not settle without overshoot: %s %s" % [x, v])
	print("PRE_LANDING_LATERAL ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
