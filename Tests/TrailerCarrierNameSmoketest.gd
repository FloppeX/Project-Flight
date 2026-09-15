extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var result: Dictionary = root.get_node("SaveGameManager").prepare_trailer_scenario()
	assert(result.ok)
	var session := root.get_node("GameSession")
	assert(session.carrier_name == "Dune Strider")
	var livery := root.get_node("Livery")
	assert(livery.get("AIRCRAFT_UPPER_PATTERN_NAMES")[session.carrier_pattern_index] == "camo pattern")
	assert(session.carrier_primary_color.is_equal_approx(Color(0.36, 0.40, 0.44)))
	assert(session.carrier_secondary_color.is_equal_approx(Color(0.96, 0.93, 0.82)))
	var carrier := Node3D.new()
	root.add_child(carrier)
	var marker: Decal = load("res://LandCarrier/ShipNameMarker.gd").new()
	carrier.add_child(marker)
	session.apply_to_carrier(carrier)
	assert(livery.get("_player_custom_pattern_index") == 4)
	assert(livery.get_team_upper_color(1).is_equal_approx(session.carrier_primary_color))
	assert(livery._get_team_secondary_color(1).is_equal_approx(session.carrier_secondary_color))
	marker.refresh_ship_name()
	assert(carrier.get_meta("carrier_display_name") == "Dune Strider")
	assert(marker.get_ship_name_text() == "Dune Strider")
	assert(marker.get_node("_NameTexture").get_child(0).text == "Dune Strider")
	carrier.queue_free()
	await process_frame
	print("TRAILER_CARRIER_NAME_PASS")
	quit()
