extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _make_catapult(deck: Node3D) -> Node3D:
	var catapult := preload("res://LandCarrier/Catapult.gd").new()
	catapult.launch_steam_enabled = false
	catapult.shuttle = Node3D.new()
	catapult.latch_marker = Marker3D.new()
	catapult.release_marker = Marker3D.new()
	deck.add_child(catapult.shuttle)
	deck.add_child(catapult.latch_marker)
	deck.add_child(catapult.release_marker)
	catapult.release_marker.position.z = 50.0
	deck.add_child(catapult)
	catapult.set_physics_process(false)
	return catapult

func _load_aircraft(catapult: Node3D, deck: Node3D) -> RigidBody3D:
	var aircraft := RigidBody3D.new()
	deck.add_child(aircraft)
	aircraft.freeze = true
	catapult.set("_aircraft", aircraft)
	catapult.set("_latched", true)
	return aircraft

func _run() -> void:
	var deck := Node3D.new()
	root.add_child(deck)
	var first := _make_catapult(deck)
	var second := _make_catapult(deck)
	_load_aircraft(first, deck)
	var waiting := _load_aircraft(second, deck)
	_expect(first.call("_try_start_launch"), "first launch starts")
	_expect(not second.call("_try_start_launch"), "same-frame second launch blocked")
	_expect(waiting.freeze, "waiting aircraft remains restrained")
	first.call("_release")
	_expect(not second.call("_try_start_launch"), "release clearance gap enforced")
	first.call("_physics_process", 2.9)
	_expect(not second.call("_try_start_launch"), "clearance gap not shortened")
	first.call("_physics_process", 0.2)
	_expect(second.call("_try_start_launch"), "waiting aircraft launches after clearance")
	_load_aircraft(first, deck)
	waiting.free()
	second.call("_physics_process", 1.0 / 60.0)
	_expect(not first.call("_try_start_launch"), "destroyed launching aircraft retains brief clearance gap")
	second.call("_physics_process", 3.1)
	_expect(first.call("_try_start_launch"), "aircraft loss releases interlock")
	var other_deck := Node3D.new()
	root.add_child(other_deck)
	var independent := _make_catapult(other_deck)
	_load_aircraft(independent, other_deck)
	_expect(independent.call("_try_start_launch"), "different carriers launch independently")
	if failures.is_empty(): print("CATAPULT_LAUNCH_INTERLOCK_SMOKETEST_OK")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
