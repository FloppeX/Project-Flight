extends SceneTree


class FakeFlightDeck extends Node:
	var stored_aircraft: Array[Dictionary] = [{
		"name": "Aircraft_12",
		"scene_file": "res://Aircraft/Aircraft_12.tscn",
		"current_health": 55.0,
		"loadout_state": {"old_weapon": true},
		"metadata": {"aircraft_role": "attack_helicopter", "is_helicopter": true},
	}]

	func _stored_aircraft_is_helicopter(entry: Dictionary) -> bool:
		return bool((entry.get("metadata", {}) as Dictionary).get("is_helicopter", false))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := load("res://UI/TechnicalIndexCatalog.gd") as Script
	var catalogued_as_helicopter := false
	for entry in catalog.entries_for("HELICOPTERS"):
		if str(entry.get("scene", "")) == "res://Aircraft/Aircraft_13.tscn" \
				and str((entry.get("stats", {}) as Dictionary).get("CLASS", "")) == "ROTARY-WING":
			catalogued_as_helicopter = true
			break
	if not catalogued_as_helicopter:
		_fail("Aircraft_13 is not listed as a rotary-wing aircraft in the Technical Index")
		return
	var scene := load("res://Aircraft/Aircraft_13.tscn") as PackedScene
	if scene == null:
		_fail("scene did not load")
		return
	var aircraft := scene.instantiate() as RigidBody3D
	if aircraft == null:
		_fail("scene is not a RigidBody3D")
		return
	var template_scene := load("res://Aircraft/Aircraft_11.tscn") as PackedScene
	var template := template_scene.instantiate() as RigidBody3D if template_scene != null else null
	if template == null:
		_fail("Aircraft_11 template did not load")
		return
	var flight := aircraft.get_node("SimpleAero")
	var template_flight := template.get_node("SimpleAero")
	var pilot := aircraft.get_node("HelicopterPilot")
	var template_pilot := template.get_node("HelicopterPilot")
	if aircraft.mass >= template.mass \
			or float(flight.get("max_lift_multiplier")) >= float(template_flight.get("max_lift_multiplier")) \
			or float(flight.get("max_forward_speed_mps")) >= float(template_flight.get("max_forward_speed_mps")) \
			or float(pilot.get("cruise_speed_mps")) >= float(template_pilot.get("cruise_speed_mps")) \
			or float(flight.get("low_speed_cyclic_response")) <= float(template_flight.get("low_speed_cyclic_response")):
		_fail("Aircraft_13 handling does not match its light, responsive, slower role")
		return
	template.free()
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(aircraft)
	await process_frame
	var panel_mount := aircraft.get_node_or_null("InstrumentPanel") as Node3D
	var panel_mesh := aircraft.get_node_or_null("aircraft_13/instrument panel") as MeshInstance3D
	var aircraft_5 := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate() as RigidBody3D
	var reference_mount := aircraft_5.get_node_or_null("InstrumentPanel") as Node3D if aircraft_5 != null else null
	if panel_mount == null or panel_mesh == null or reference_mount == null:
		_fail("Aircraft 13 or Aircraft 5 instrument panel is missing")
		return
	if panel_mount.call("get_effective_module_layout") != reference_mount.call("get_effective_module_layout"):
		_fail("Aircraft 13 does not use Aircraft 5's instrument layout")
		return
	aircraft_5.free()
	if not bool(panel_mount.get("render_to_model_surface")) \
			or panel_mount.call("resolve_model_panel_mesh") != panel_mesh \
			or panel_mesh.mesh == null or panel_mesh.mesh.get_surface_count() != 3:
		_fail("Aircraft 13's authored instrument panel surface is not configured")
		return
	var authored_material := panel_mesh.mesh.surface_get_material(2)
	if authored_material == null or authored_material.resource_name != "instrument panel material":
		_fail("Aircraft 13's display face is not assigned the instrument panel material")
		return
	var cockpit_camera := aircraft.get_node_or_null("CameraCockpit/Camera3D") as Camera3D
	if cockpit_camera != null:
		cockpit_camera.current = true
	panel_mount.call("set_view_updates_active", true)
	await process_frame
	var live_panel := panel_mount.call("get_live_panel") as Node3D
	if live_panel == null or live_panel.get("model_panel_mesh") != panel_mesh \
			or live_panel.get("model_panel_surface_indices") != PackedInt32Array([2]) \
			or not panel_mesh.get_surface_override_material(2) is ShaderMaterial:
		_fail("Aircraft 13's live instrument display did not bind to the model material")
		return
	var display_material := panel_mesh.get_surface_override_material(2) as ShaderMaterial
	if display_material.get_shader_parameter("panel_texture") == null:
		_fail("Aircraft 13's display surface has no live instrument texture")
		return
	if DisplayServer.get_name() != "headless":
		await process_frame
		await process_frame
		var capture := root.get_texture().get_image()
		var capture_path := "user://aircraft13_instrument_panel.png"
		if capture == null or capture.save_png(capture_path) != OK:
			_fail("Aircraft 13 instrument panel screenshot could not be saved")
			return
		print("[Aircraft13SceneSmoketest] screenshot=%s" % ProjectSettings.globalize_path(capture_path))
	panel_mount.call("set_view_updates_active", false)
	if panel_mesh.get_surface_override_material(2) != null:
		_fail("Aircraft 13's instrument panel material was not restored after release")
		return
	var model := aircraft.get_node_or_null("aircraft_13")
	var rotor := aircraft.get_node_or_null("RotorAssembly/UpperRotor")
	var tail := aircraft.get_node_or_null("aircraft_13/tail rotor") as MeshInstance3D
	var engine := aircraft.get_node_or_null("Engine")
	var doors := aircraft.get_node_or_null("SwingDoors")
	if model == null or rotor == null or tail == null or engine == null or doors == null:
		_fail("model, rotor, tail rotor, engine, or doors missing")
		return
	var blades: Array[Node] = []
	for child in rotor.get_children():
		if child.name.begins_with("Blade"):
			blades.append(child)
	if blades.size() != 2:
		_fail("expected two main blades, found %d" % blades.size())
		return
	if doors.get("_left_door") == null or doors.get("_right_door") == null:
		_fail("imported doors were not connected to their hinges")
		return
	if engine.get("propeller") != tail:
		_fail("engine is not driving imported tail rotor")
		return
	var rotor_assembly := aircraft.get_node("RotorAssembly")
	var yaws: PackedFloat32Array = rotor_assembly.get("upper_blade_yaws_deg")
	if yaws.size() != 2 or not is_equal_approx(absf(yaws[1] - yaws[0]), 180.0):
		_fail("main blades are not 180 degrees apart")
		return
	rotor_assembly.set("_fold_t", 0.0)
	rotor_assembly.call("_apply_fold_pose")
	var first_direction := (blades[0] as Node3D).transform.basis.z.normalized()
	var second_direction := (blades[1] as Node3D).transform.basis.z.normalized()
	if first_direction.dot(second_direction) > -0.95:
		_fail("deployed blade meshes do not point in opposite directions")
		return
	var scenario := (load("res://Scenario/GroundCombatTestMode.gd") as Script).new() as Node3D
	var deck := FakeFlightDeck.new()
	scenario.set("_report_path", "res://.godot/aircraft13_smoke_no_report.log")
	scenario.set("_fdm", deck)
	if not bool(scenario.call("_ensure_support_aircraft_hangar_stock")):
		_fail("ground-combat support hangar could not be stocked")
		return
	var stored := deck.stored_aircraft[0]
	if str(stored.get("scene_file", "")) != scene.resource_path \
			or stored.get("scene") != scene \
			or stored.has("current_health") or stored.has("loadout_state"):
		_fail("ground-combat support still uses a different aircraft scene")
		return
	scenario.free()
	deck.free()
	var passenger_seat := aircraft.get_node_or_null("Passenger1") as Node3D
	var passenger_paths: Array = pilot.get("passenger_position_paths")
	if passenger_seat == null or int(pilot.get("passenger_capacity")) != 1 \
			or passenger_paths.size() != 1 \
			or pilot.get_node_or_null(passenger_paths[0]) != passenger_seat:
		_fail("Aircraft_13 must have exactly one configured passenger seat")
		return
	var rescued_pilot := Node3D.new()
	rescued_pilot.set_meta("pilot_callsign", "Dragonfly Passenger")
	var first_accepted := bool(pilot.call("add_passenger", rescued_pilot))
	rescued_pilot.free()
	var seated_passenger := passenger_seat.get_node_or_null("SeatedPassenger1") as Node3D
	if not first_accepted or seated_passenger == null \
			or not seated_passenger.transform.is_equal_approx(Transform3D.IDENTITY) \
			or str(seated_passenger.get_meta("pilot_callsign", "")) != "Dragonfly Passenger":
		_fail("Aircraft_13 did not seat its first rescued passenger at Passenger1")
		return
	var extra_pilot := Node3D.new()
	var second_accepted := bool(pilot.call("add_passenger", extra_pilot))
	extra_pilot.free()
	if second_accepted or bool(pilot.call("can_accept_passenger")) \
			or int(pilot.call("get_passenger_count")) != 1:
		_fail("Aircraft_13 accepted more than one passenger")
		return
	print("[Aircraft13SceneSmoketest] PASS")
	aircraft.queue_free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[Aircraft13SceneSmoketest] FAIL: " + reason)
	quit(1)
