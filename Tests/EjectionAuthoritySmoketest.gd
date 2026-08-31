extends SceneTree


var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "EjectionAuthoritySmoketest"
	root.add_child(scene)
	current_scene = scene

	var flight_director := root.get_node_or_null("FlightDirector")
	if flight_director == null:
		_fail("FlightDirector autoload missing")
		return

	var sequence_script := load("res://Aircraft/EjectionSequence.gd") as Script
	if sequence_script == null:
		_fail("EjectionSequence script did not load")
		return

	var player_aircraft := _make_aircraft(scene, "PlayerAircraft", false)
	var player_sequence := _make_sequence(player_aircraft, sequence_script)
	_expect(is_equal_approx(float(player_sequence.get("ai_ejection_delay_min_s")), 1.0),
			"default AI ejection minimum is not 1 second")
	_expect(is_equal_approx(float(player_sequence.get("ai_ejection_delay_max_s")), 4.0),
			"default AI ejection maximum is not 4 seconds")

	flight_director.set("current_viewed_aircraft", player_aircraft)
	flight_director.set("player_controlled_plane", player_aircraft)
	flight_director.set("is_player_controlling", true)
	player_sequence.call("_on_aircraft_damaged", 100.0, 0.0)
	_expect(bool(player_sequence.get("_manual_ejection_required")),
			"fatal damage did not preserve player ownership for manual ejection")
	_expect(not bool(player_sequence.get("_ai_ejection_scheduled")),
			"player-controlled aircraft scheduled an automatic ejection")
	flight_director.call("force_release_player_control_for", player_aircraft)
	_expect(bool(player_sequence.call("_should_accept_player_ejection_input")),
			"manual ejection input was rejected after fatal damage released flight controls")
	await create_timer(0.12).timeout
	_expect(not bool(player_sequence.get("_has_started")),
			"player-controlled aircraft ejected without manual input")

	player_sequence.call("start_ejection")
	await process_frame
	_expect(bool(player_sequence.get("_has_started")), "manual player ejection did not start")
	_expect(is_instance_valid(player_aircraft) and not player_aircraft.is_queued_for_deletion(),
			"source aircraft despawned when the player ejected")

	flight_director.set("current_viewed_aircraft", null)
	flight_director.set("player_controlled_plane", null)
	flight_director.set("is_player_controlling", false)

	var ai_aircraft := _make_aircraft(scene, "AIAircraft", true)
	var ai_sequence := _make_sequence(ai_aircraft, sequence_script)
	ai_sequence.set("ai_ejection_delay_min_s", 0.08)
	ai_sequence.set("ai_ejection_delay_max_s", 0.08)
	ai_sequence.call("_on_aircraft_damaged", 100.0, 0.0)
	_expect(bool(ai_sequence.get("_ai_ejection_scheduled")),
			"AI fatal damage did not schedule an ejection")
	_expect(is_equal_approx(float(ai_sequence.get("_scheduled_ai_ejection_delay_s")), 0.08),
			"AI ejection did not use its configured delay")
	_expect(not bool(ai_sequence.get("_has_started")), "AI ejected immediately")
	await create_timer(0.03).timeout
	_expect(not bool(ai_sequence.get("_has_started")), "AI ejected before its delay elapsed")
	await create_timer(0.08).timeout
	_expect(bool(ai_sequence.get("_has_started")), "AI did not eject after its delay elapsed")
	_expect(is_instance_valid(ai_aircraft) and not ai_aircraft.is_queued_for_deletion(),
			"source aircraft despawned when the AI ejected")

	if _failed:
		quit(1)
		return
	print("[EjectionAuthoritySmoketest] PASS player=manual_only ai_delay=1_to_4s source_retained=true")
	flight_director.set("active_aircraft", [])
	scene.free()
	quit(0)


func _make_aircraft(scene: Node3D, aircraft_name: String, is_ai: bool) -> RigidBody3D:
	var aircraft := RigidBody3D.new()
	aircraft.name = aircraft_name
	aircraft.add_to_group("aircraft")
	aircraft.add_to_group("ai_aircraft" if is_ai else "friendlies")
	var seat := Node3D.new()
	seat.name = "EjectionSeat"
	aircraft.add_child(seat)
	scene.add_child(aircraft)
	return aircraft


func _make_sequence(aircraft: RigidBody3D, sequence_script: Script) -> Node:
	var sequence := Node.new()
	sequence.set_script(sequence_script)
	sequence.name = "EjectionSequence"
	sequence.set("canopy_optional", true)
	sequence.set("seat_launch_delay_s", 0.0)
	sequence.set("seat_burn_duration_s", 0.0)
	aircraft.add_child(sequence)
	return sequence


func _expect(condition: bool, reason: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[EjectionAuthoritySmoketest] FAIL %s" % reason)


func _fail(reason: String) -> void:
	push_error("[EjectionAuthoritySmoketest] FAIL %s" % reason)
	quit(1)
