extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := load("res://UI/TechnicalIndexCatalog.gd") as Script
	var listed := false
	for entry in catalog.entries_for("HELICOPTERS"):
		if str(entry.get("scene", "")) == "res://Aircraft/Aircraft_15.tscn":
			listed = true
			break
	if not listed:
		_fail("Aircraft 15 is missing from the helicopter catalog")
		return

	var scene := load("res://Aircraft/Aircraft_15.tscn") as PackedScene
	var template_scene := load("res://Aircraft/Aircraft_13.tscn") as PackedScene
	if scene == null or template_scene == null:
		_fail("helicopter scene did not load")
		return
	var aircraft := scene.instantiate() as RigidBody3D
	var template := template_scene.instantiate() as RigidBody3D
	if aircraft == null or template == null:
		_fail("helicopter root is not a RigidBody3D")
		return
	var flight := aircraft.get_node("SimpleAero")
	var template_flight := template.get_node("SimpleAero")
	if aircraft.mass <= template.mass or float(flight.get("max_lift_multiplier")) <= float(template_flight.get("max_lift_multiplier")) or float(flight.get("max_forward_speed_mps")) <= float(template_flight.get("max_forward_speed_mps")):
		_fail("Aircraft 15 is not heavier, more powerful, and faster than Aircraft 13")
		return
	if str(aircraft.get_meta("aircraft_role", "")) != "attack_helicopter":
		_fail("Aircraft 15's AI role is not recognized as an attack helicopter")
		return
	template.free()
	aircraft.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(aircraft)
	await process_frame

	var model := aircraft.get_node_or_null("aircraft_15")
	if model == null or model.scene_file_path != "res://Models/Aircraft_15/aircraft 15.blend":
		_fail("Aircraft 15 is not using its Blender source")
		return
	var tail := aircraft.get_node_or_null("aircraft_15/tail rotor")
	var engine := aircraft.get_node_or_null("Engine")
	if model == null or tail == null or engine.get("propeller") != tail:
		_fail("imported model or driven tail rotor is missing")
		return
	var rotor := aircraft.get_node_or_null("RotorAssembly/UpperRotor")
	var blade_count := 0
	for child in rotor.get_children():
		if child.name.begins_with("Blade"):
			blade_count += 1
	if blade_count != 4:
		_fail("main rotor should have four blades")
		return
	var doors := aircraft.get_node("SwingDoors")
	if doors.get("_left_door") == null or doors.get("_right_door") == null:
		_fail("imported doors did not bind to hinges")
		return

	var gear := aircraft.get_node("LandingGear")
	var colliders: Array = gear.get("gear_collision_shapes")
	var visuals: Array = gear.get("gear_visuals")
	if colliders.size() != 3 or visuals.size() != 3 or not bool(gear.get("lock_deployed")):
		_fail("authored three-wheel landing gear is not configured")
		return
	var wheel_names := ["WheelAndAxleFront", "WheelAndAxle left", "WheelAndAxle right"]
	for index in range(3):
		if not is_instance_valid(colliders[index]) or not is_instance_valid(visuals[index]) or visuals[index].name != wheel_names[index]:
			_fail("wheel %d does not use its imported visual and collider: %s" % [index, visuals])
			return
	if aircraft.get_node_or_null("SkidContactFL") != null:
		_fail("Aircraft 13 skid contact was left on the wheeled aircraft")
		return

	var weapons := aircraft.get_node("ControlWeapons")
	var hardpoints: Array = weapons.get("hardpoints")
	if hardpoints.size() != 2 or hardpoints[0].hardpoint_id != 1 or hardpoints[1].hardpoint_id != 2 or hardpoints[0].position.x * hardpoints[1].position.x >= 0.0:
		_fail("two opposing, numbered hardpoints are not connected")
		return
	if hardpoints[0].weapon_instance == null or hardpoints[1].weapon_instance == null:
		_fail("default hardpoint loadout did not mount")
		return

	var panel := aircraft.get_node("InstrumentPanel")
	var panel_mesh := aircraft.get_node_or_null("aircraft_15/instrument panel") as MeshInstance3D
	if panel_mesh == null or panel.call("resolve_model_panel_mesh") != panel_mesh:
		_fail("imported instrument panel is not connected")
		return
	var material_found := false
	for surface in range(panel_mesh.mesh.get_surface_count()):
		var material := panel_mesh.mesh.surface_get_material(surface)
		if material != null and material.resource_name == "instrument panel material.001":
			material_found = true
	if not material_found:
		_fail("instrument panel material is missing from the imported mesh")
		return

	print("[Aircraft15SceneSmoketest] PASS")
	aircraft.queue_free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[Aircraft15SceneSmoketest] FAIL: " + reason)
	quit(1)
