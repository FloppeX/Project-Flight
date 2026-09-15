extends SceneTree

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Scenario/Trailer/timeline.json"))
	var event: Dictionary = data.events[1]
	var deck: Node = load("res://LandCarrier/FlightDeckManager.gd").new()
	for index in int(event.count):
		var aircraft: RigidBody3D = load("res://Aircraft/%s.tscn" % event.aircraft_model).instantiate()
		aircraft.freeze = true
		aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(aircraft)
		deck._apply_ai_loadout_profile(aircraft, str(event.loadout_profile))
		await process_frame
		var categories: Array[String] = []
		for station in ["Hardpoint1", "Hardpoint2", "Hardpoint3"]:
			var hardpoint: Node = aircraft.get_node(station)
			var weapon: Node = hardpoint.weapon_instance
			if not is_instance_valid(weapon):
				failures.append("missing weapon on " + station)
				continue
			categories.append(str(weapon.weapon_category) if not str(weapon.weapon_category).is_empty() else str(weapon.weapon_name))
			if int(weapon.ammo_count) <= 0: failures.append("empty weapon on " + station)
		var controls: Node = aircraft.find_child("ControlWeapons", true, false)
		print("TRAILER_LOADOUT plane=%d categories=%s selectable=%s" % [index + 1, categories, controls.weapon_types])
		for category in ["Guns", "Bomb", "Rocket Pod"]:
			if not categories.has(category): failures.append("missing category " + category)
			if not controls.weapon_types.has(category): failures.append("not selectable: " + category)
		if controls.weapon_types.size() != 3: failures.append("not all three weapon types selectable")
		aircraft.free()
	deck.free()
	print("TRAILER_AIRCRAFT_LOADOUT_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
