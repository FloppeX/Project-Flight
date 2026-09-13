extends SceneTree

const Sight = preload("res://AI/LandingSight.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func wire(time: float, vertical: float, lateral: float = 0.0) -> Dictionary:
	return {"valid": true, "time_s": time, "vertical_m": vertical, "lateral_m": lateral,
		"half_span_m": 10.0, "lateral_margin_m": 1.0, "vertical_tolerance_m": 0.8, "wire_number": 2}

func reachable(wires: Array, sink: float = -3.3, up: float = 4.0) -> Dictionary:
	return Sight.reachable_wire_crossing(wires, sink, up, 2.0, 4.0, 12.0)

func _initialize() -> void:
	var logged := reachable([wire(4.9, -2.5, -9.8)])
	check(logged.reachable, "Aircraft 1 logged miss remains correctable after response delay")
	check(float(logged.up_accel_mps2) < 0.3, "small miss should need only a modest lift correction")
	check(not reachable([wire(1.0, -8.0)]).reachable, "late low approach is unreachable")
	check(not reachable([wire(1.0, 8.0)]).reachable, "late high approach is unreachable")
	check(not reachable([wire(1.0, 0.0, 30.0)]).reachable, "late lateral miss is unreachable")
	check(not reachable([wire(1.0, 0.0)], -20.0).reachable, "cannot fix excessive sink in available time")
	check(not reachable([wire(4.9, -2.5)], -3.3, 0.0).reachable, "no spare lift cannot correct low projection")
	check(reachable([wire(0.2, 0.2)]).reachable, "existing catch remains possible inside response delay")
	check(not reachable([wire(0.2, -2.0)]).reachable, "cannot invent instant actuator response")
	check(reachable([wire(1.0, -8.0), wire(4.9, -2.5)]).reachable, "consider later wires too")
	check(not reachable([wire(-1.0, 0.0)]).valid, "passed wire cannot create a future prediction")
	check(not reachable([wire(2.0, NAN)]).valid, "unknown data is not proof of impossibility")
	# Aircraft_3_3 at t=663.153 in the full-scenario run: wheels touch between
	# wires 1 and 2. The straight-line hook image falls through the deck.
	var supported := Sight.deck_supported_wire_crossing(
		[wire(1.791884, 1.347595), wire(2.172580, -1.461243)], 1.935348, -7.378205, true, true)
	check(supported.reachable, "logged wheel-supported wire 2 must remain possible")
	check(absf(float(supported.supported_vertical_m) - 0.289) < 0.02, "supported hook stays near deck height")
	check(not Sight.deck_supported_wire_crossing([wire(2.17, -1.46)], 1.94, -7.38, false, true).reachable,
		"unsafe footprint must never excuse a low crossing")
	check(not Sight.deck_supported_wire_crossing([wire(2.17, -1.46)], 1.94, -7.38, true, false).reachable,
		"excessive touchdown sink must not gain a supported catch")
	check(not Sight.deck_supported_wire_crossing([wire(1.0, -8.0)], 1.94, -7.38, true, true).reachable,
		"a wire before wheel support remains missed")
	check(not Sight.deck_supported_wire_crossing([wire(2.17, -1.46, 30)], 1.94, -7.38, true, true).reachable,
		"support does not correct lateral misses")
	check(not Sight.deck_supported_wire_crossing([wire(2.17, 8.0)], 1.94, -7.38, true, true).reachable,
		"support does not invent a dive for a high hook")
	print("WIRE_REACHABILITY_SMOKETEST %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
