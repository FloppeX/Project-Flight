extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft_scene := load("res://Aircraft/Aircraft_11.tscn") as PackedScene
	if aircraft_scene == null:
		_fail("Aircraft_11 scene could not be loaded")
		return
	var aircraft := aircraft_scene.instantiate() as RigidBody3D
	if aircraft == null:
		_fail("Aircraft_11 scene did not instantiate as a RigidBody3D")
		return
	var helicopter_pilot := aircraft.get_node_or_null("HelicopterPilot")
	if helicopter_pilot == null:
		aircraft.free()
		_fail("Aircraft_11 has no HelicopterPilot")
		return
	helicopter_pilot.set("aircraft", aircraft)

	for index in range(3):
		var rescued_pilot := Node3D.new()
		rescued_pilot.set_meta("pilot_callsign", "Passenger %d" % (index + 1))
		if not bool(helicopter_pilot.call("add_passenger", rescued_pilot)):
			rescued_pilot.free()
			aircraft.free()
			_fail("passenger %d was rejected before the cabin was full" % (index + 1))
			return
		rescued_pilot.free()
		var marker := aircraft.get_node_or_null("Passenger%d" % (index + 1)) as Node3D
		var visual := marker.get_node_or_null("SeatedPassenger%d" % (index + 1)) as Node3D if marker != null else null
		if visual == null or not visual.transform.is_equal_approx(Transform3D.IDENTITY):
			aircraft.free()
			_fail("passenger %d was not seated at its authored marker transform" % (index + 1))
			return
		if str(visual.get_meta("pilot_callsign", "")) != "Passenger %d" % (index + 1):
			aircraft.free()
			_fail("passenger metadata was not retained on the seated visual")
			return

	var overflow_pilot := Node3D.new()
	var overflow_accepted := bool(helicopter_pilot.call("add_passenger", overflow_pilot))
	overflow_pilot.free()
	if overflow_accepted or bool(helicopter_pilot.call("can_accept_passenger")) \
			or int(helicopter_pilot.call("get_passenger_count")) != 3:
		aircraft.free()
		_fail("Aircraft_11 did not enforce its three-passenger cabin capacity")
		return

	aircraft.free()
	print("[Aircraft11PassengerSmoketest] PASS capacity=3 markers=3 seated=true overflow_rejected=true")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[Aircraft11PassengerSmoketest] FAIL %s" % reason)
	quit(1)
