extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "Aircraft9DeckGeometrySmoketest"
	root.add_child(scene)
	current_scene = scene

	var deck_marker := Marker3D.new()
	deck_marker.name = "DeckMarker"
	scene.add_child(deck_marker)

	var manager := Node.new()
	manager.name = "FlightDeckManager"
	scene.add_child(manager)
	manager.set_script(load("res://LandCarrier/FlightDeckManager.gd") as Script)
	manager.set("deck_marker", deck_marker)

	var aircraft := (load("res://Aircraft/Aircraft_9.tscn") as PackedScene).instantiate() as RigidBody3D
	aircraft.name = "Aircraft_9_DeckGeometryRegression"
	aircraft.freeze = true
	scene.add_child(aircraft)
	# Aircraft.setup() intentionally waits one process frame before binding its
	# modules, matching runtime-spawn behavior.
	await process_frame
	await process_frame

	var landing_gear := aircraft.get_node_or_null("LandingGear")
	if landing_gear == null:
		_fail("Aircraft_9 has no LandingGear module")
		return
	if int(landing_gear.get("nose_gear_index")) != -1:
		_fail("four-wheel helicopter still assigns all static front load to one wheel")
		return

	var ground_offset := float(manager.call("_get_gear_ground_offset", aircraft))
	if ground_offset < 2.2 or ground_offset > 2.4:
		_fail("elevator placement used %.3f m instead of Aircraft_9's tire-contact offset" % ground_offset)
		return

	var shapes: Variant = landing_gear.get("gear_collision_shapes")
	if not (shapes is Array) or (shapes as Array).size() != 4:
		_fail("Aircraft_9 did not expose four suspension wheels")
		return
	var first_shape := (shapes as Array)[0] as CollisionShape3D
	if first_shape == null or not (first_shape.shape is SphereShape3D):
		_fail("Aircraft_9 wheel safety collider is missing")
		return
	if (first_shape.shape as SphereShape3D).radius >= float(landing_gear.call("get_wheel_rest_height", 0)) - 0.1:
		_fail("wheel safety collider still blocks suspension before it can compress")
		return

	if not bool(manager.call("_place_aircraft_in_static_suspension_pose", aircraft, 0.0)):
		_fail("Aircraft_9 could not enter a loaded deck stance")
		return

	var compressions: Variant = landing_gear.get("gear_compressions")
	if not (compressions is Array) or (compressions as Array).size() != 4:
		_fail("Aircraft_9 static stance did not initialize all four struts")
		return
	for index in range(4):
		var compression := float((compressions as Array)[index])
		if compression < 0.20:
			_fail("Aircraft_9 strut %d did not visibly compress (%.3f m)" % [index, compression])
			return

	var contact_offset := float(landing_gear.get("deck_contact_visual_offset_m"))
	for index in range(4):
		var wheel := (shapes as Array)[index] as Node3D
		var contact_y := wheel.global_position.y - contact_offset
		if absf(contact_y) > 0.02:
			_fail("Aircraft_9 wheel %d missed the deck after static settle (%.3f m)" % [index, contact_y])
			return

	if not bool(manager.call("_landing_blocker_has_deck_contact", aircraft)):
		_fail("settled Aircraft_9 tire contact was not recognized")
		return
	aircraft.global_position.y += 0.20
	if bool(manager.call("_landing_blocker_has_deck_contact", aircraft)):
		_fail("Aircraft_9 was declared landed with tires 20 cm above the deck")
		return

	print("[Aircraft9DeckGeometrySmoketest] PASS elevator_offset=%.3f compression=4x%.3f contact=deck hover_rejected=0.20" % [
		ground_offset,
		float((compressions as Array)[0]),
	])
	quit(0)


func _fail(reason: String) -> void:
	push_error("[Aircraft9DeckGeometrySmoketest] FAIL %s" % reason)
	quit(1)
