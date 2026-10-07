extends "res://Tests/RegionalAircraftDamageSmoketest.gd"

func _run() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	for number in [1,2,3,4,5,6,7,8,14,16]:
		var craft := spawn(number)
		while not craft.runtime_initialized: await get_tree().process_frame
		await get_tree().physics_frame
		var model := craft.get_node("PartDamageModel") as AircraftPartDamageModel
		var engine := craft.get_node("Engine") as AircraftModule_Engine
		engine.engine_stop()
		model.damage_zone(&"fuselage", model.get_zone_max_health(&"fuselage") * .8)
		craft.prepare_energy_system()
		var before: float = craft.available_energy.get("fuel", 0.0)
		for frame in 30: await get_tree().physics_frame
		craft.prepare_energy_system()
		check(float(craft.available_energy.get("fuel", 0.0)) < before - .1, "%d fuel leak did not drain tank" % number)
		var gear := craft.get_node("LandingGear") as AircraftModule_LandingGear
		var control := craft.get_node("ControlLandingGear")
		var deployed := gear.is_deployed
		if deployed: control.stow_gear()
		else: control.deploy_gear()
		check(gear.is_deployed == deployed, "%d gear jam bypassed by cockpit control" % number)
		gear.collapse_from_damage()
		var poses: Array[Transform3D] = []
		for visual in gear.gear_visuals:
			if is_instance_valid(visual): poses.append(visual.transform)
		gear.collapse_from_damage()
		var index := 0
		for visual in gear.gear_visuals:
			if is_instance_valid(visual):
				check(visual.transform.is_equal_approx(poses[index]), "%d repeated gear collapse moved mesh" % number)
				index += 1
		var saved := preload("res://Aircraft/AircraftRuntimeState.gd").capture(craft)
		var restored := spawn(number)
		while not restored.runtime_initialized: await get_tree().process_frame
		preload("res://Aircraft/AircraftRuntimeState.gd").restore(restored, saved)
		check(restored.get_node("LandingGear").damage_collapsed, "%d gear collapse not restored" % number)
		check("GEAR COLLAPSED" in restored.get_meta("damage_warnings", []), "%d restored gear warning absent" % number)
		restored.free()
		model.damage_zone(&"left_wing", model.get_zone_max_health(&"left_wing") * .8)
		var tested_stores := 0
		for node in craft.find_children("*", "Node3D", true, false):
			if node is Hardpoint and craft.to_local(node.global_position).x > .8:
				tested_stores += 1
				check(node.damage_disabled and not node.fire(), "%d disabled wing store fired" % number)
		# 1/3/14 carry only centreline or near-centreline stores.
		if number not in [1,3,14]: check(tested_stores > 0, "%d no wing hardpoint coverage" % number)
		if number == 5 or number == 16:
			await check_cockpit_page(craft, number)
		model.damage_zone(&"left_wing", model.get_zone_max_health(&"left_wing"))
		for node in craft.find_children("*", "Node3D", true, false):
			if node is Hardpoint and craft.to_local(node.global_position).x > .8:
				check(node.weapon_instance == null and not node.visible, "%d lost wing kept its stores" % number)
		if number == 2:
			model.damage_zone(&"tail", model.get_zone_max_health(&"tail"))
			check(engine.damage_disabled, "rear engine remained active after tail detachment")
			var propeller := craft.get_node("Aircraft 2 body/Aircraft 2 propeller")
			for mesh in propeller.find_children("*", "MeshInstance3D", true, false):
				check(not mesh.is_visible_in_tree(), "rear propeller left floating on aircraft")
		craft.set_meta("camera_replaced_by_ejected_pilot", true)
		model.damage_zone(&"cockpit", model.get_zone_max_health(&"cockpit"))
		check(not bool(craft.get_meta("pilot_dead", false)), "%d cockpit hit killed ejected pilot" % number)
		craft.free()
		for child in host.get_children(): child.queue_free()
		await get_tree().process_frame
		print("REGIONAL_SYSTEMS_CASE ", number)
	for failure in failures: push_error(failure)
	print("REGIONAL_DAMAGE_SYSTEMS_%s fleet=10 fuel+stores+gear+save+ejected_pilot cockpit_pages=5,16" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func check_cockpit_page(craft: Aircraft, number: int) -> void:
	var mount := craft.get_node("InstrumentPanel")
	mount.set_view_updates_active(true)
	await get_tree().process_frame
	var panel: Node = mount.get_live_panel()
	check(panel != null, "%d pooled cockpit panel missing" % number)
	if panel == null: return
	var tripod: Node = craft.find_child("CockpitCamera", true, false)
	if tripod == null:
		# Camera tripods use authored names, but all carry the same input script.
		for node in craft.get_children():
			if node.get_script() == preload("res://Camera/CockpitCamera.gd"): tripod = node
	check(tripod != null, "%d cockpit input handler missing" % number)
	if tripod == null: return
	var camera := tripod.find_child("Camera3D", true, false) as Camera3D
	camera.make_current()
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F10
	tripod._input(key)
	check(panel.mfd_modules[0]._current_mode() == "DAMAGE", "%d F10 did not select damage page" % number)
	key.physical_keycode = KEY_BRACKETRIGHT
	tripod._input(key)
	check(panel.mfd_modules[0]._current_mode() != "DAMAGE", "%d bracket did not cycle display" % number)
	for module in panel.instrument_modules:
		if module.module_id == "damage":
			check(module.interact(Vector2.ZERO), "%d structure readout did not open damage page" % number)
	key.physical_keycode = KEY_F10
	tripod._input(key)
	await get_tree().create_timer(.2).timeout
	var diagram: Control = panel.mfd_modules[0].mode_views["DAMAGE"]
	check(diagram._state.zones.fuselage.fraction < .25, "%d pooled damage page has stale aircraft data" % number)
	mount.set_view_updates_active(false)
