extends SceneTree

const TERRAIN_SCRIPT: Script = preload("res://Environment/LowPolyTerrain.gd")
const SESSION_SCRIPT: Script = preload("res://GameSession.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session: Node = SESSION_SCRIPT.new() as Node
	session.call(
		"configure_new_game",
		"Pathfinder",
		Color.WHITE,
		Color.BLACK,
		0,
		0,
		"layered_badlands"
	)
	_expect(str(session.get("selected_map_id")) == "layered_badlands", "new-game map selection was not retained")
	session.call("reset_to_defaults")
	_expect(str(session.get("selected_map_id")) == "open_canyons", "map selection did not reset to the default")
	session.free()

	var terrain := TERRAIN_SCRIPT.new() as LowPolyTerrain
	terrain.generate_on_ready = false
	terrain.use_streaming = false
	terrain.cell_size_m = 36.0
	terrain.seed = 22551
	terrain.base_height_offset_m = 220.0
	terrain.quant_step_m = 3.0
	terrain.set_map_profile("layered_badlands")
	root.add_child(terrain)

	var validation_started_ms := Time.get_ticks_msec()
	var validation: Dictionary = terrain.validate_profile_routes(20.0, 36.0)
	var validation_elapsed_ms := Time.get_ticks_msec() - validation_started_ms
	_expect(bool(validation.get("valid", false)), "protected route exceeded the 20-degree grade cap: %s" % str(validation))
	_expect(int(validation.get("route_count", 0)) == 3, "expected three protected cross-map routes")
	_expect(int(validation.get("connector_count", 0)) == 4, "expected four protected route cross-connectors")

	var main_midpoint := terrain.get_profile_route_local_position(0.5, 0)
	var east_midpoint := terrain.get_profile_route_local_position(0.5, 1)
	var west_midpoint := terrain.get_profile_route_local_position(0.5, 2)
	_expect(east_midpoint.x - main_midpoint.x >= 6000.0, "eastern route does not diverge meaningfully")
	_expect(main_midpoint.x - west_midpoint.x >= 6000.0, "western route does not diverge meaningfully")
	_expect(east_midpoint.y - main_midpoint.y >= 200.0, "eastern route lacks meaningful vertical separation")
	_expect(main_midpoint.y - west_midpoint.y >= 70.0, "western route lacks meaningful vertical separation")
	var main_north := terrain.get_profile_route_local_position(0.0, 0)
	var main_south := terrain.get_profile_route_local_position(1.0, 0)
	for route_index in range(1, 3):
		var route_north := terrain.get_profile_route_local_position(0.0, route_index)
		var route_south := terrain.get_profile_route_local_position(1.0, route_index)
		_expect(main_north.distance_to(route_north) <= 0.1, "route %d does not reconnect at the north edge" % route_index)
		_expect(main_south.distance_to(route_south) <= 0.1, "route %d does not reconnect at the south edge" % route_index)
	for connector_index in range(4):
		var connector_start := terrain.get_profile_connector_local_position(0.0, connector_index)
		var connector_end := terrain.get_profile_connector_local_position(1.0, connector_index)
		_expect(connector_start.distance_to(connector_end) >= 2500.0, "connector %d is too short to create a meaningful choice" % connector_index)

	var min_height := INF
	var max_height := -INF
	for z in range(-20000, 20001, 4000):
		for x in range(-20000, 20001, 4000):
			var height := terrain.get_height(Vector3(float(x), 0.0, float(z)))
			min_height = minf(min_height, height)
			max_height = maxf(max_height, height)
	_expect(max_height - min_height >= 450.0, "terrain lacks the requested vertical variation")

	print("LAYERED_MAP_PROFILE_SMOKETEST ", JSON.stringify({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"max_grade_degrees": validation.get("max_grade_degrees", -1.0),
		"validation_ms": validation_elapsed_ms,
		"height_span_m": max_height - min_height,
		"east_separation_m": east_midpoint.x - main_midpoint.x,
		"west_separation_m": main_midpoint.x - west_midpoint.x,
		"east_height_difference_m": east_midpoint.y - main_midpoint.y,
		"west_height_difference_m": main_midpoint.y - west_midpoint.y,
		"failures": _failures,
	}))
	terrain.queue_free()
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[LayeredMapProfileSmoketest] %s" % message)
