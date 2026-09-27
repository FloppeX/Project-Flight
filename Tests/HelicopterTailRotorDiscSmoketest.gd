extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for aircraft_number in [10, 11, 13, 15]:
		var scene := load("res://Aircraft/Aircraft_%d.tscn" % aircraft_number) as PackedScene
		if scene == null:
			_fail(aircraft_number, "scene did not load")
			return
		var aircraft := scene.instantiate() as RigidBody3D
		if aircraft == null:
			_fail(aircraft_number, "scene has no aircraft root")
			return
		aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(aircraft)
		await process_frame
		var engine := aircraft.get_node("Engine")
		var rotor := engine.get("propeller") as Node3D
		var discs: Array = engine.get("_prop_disc_mesh_nodes")
		var blades: Array = engine.get("_prop_blade_mesh_nodes")
		if rotor == null or discs.is_empty() or blades.is_empty() or not bool(engine.get("GovernPropellerVisualSpeed")):
			_fail(aircraft_number, "tail rotor is missing its governed drive or disc")
			return
		var disc := discs[0] as MeshInstance3D
		if disc == null or disc.mesh == null or disc.visible:
			_fail(aircraft_number, "tail disc is not hidden when stopped")
			return

		engine.set("aircraft", null)
		engine.set("is_engine_working", true)
		engine.set("visual_budget_enabled", true)
		var stopped_transform := rotor.transform
		engine.set("current_power", 0.2)
		engine.call("process_physic_frame", 0.02)
		var low_throttle_transform := rotor.transform
		rotor.transform = stopped_transform
		engine.set("current_power", 0.9)
		engine.call("process_physic_frame", 0.02)
		if not rotor.transform.is_equal_approx(low_throttle_transform):
			_fail(aircraft_number, "tail rotor RPM changes with throttle")
			return
		engine.call("_update_propeller_blur_visuals", 0.2)
		if not disc.visible or disc.transparency > 0.01 or (blades[0] as MeshInstance3D).visible:
			_fail(aircraft_number, "tail disc does not replace the fast rotor visual")
			return
		engine.set("is_engine_working", false)
		engine.set("current_power", 0.0)
		rotor.transform = stopped_transform
		engine.call("process_physic_frame", 0.2)
		if not rotor.transform.is_equal_approx(stopped_transform) or disc.visible or not (blades[0] as MeshInstance3D).visible:
			_fail(aircraft_number, "tail rotor or disc remains active after stop")
			return
		aircraft.queue_free()
		await process_frame

	print("[HelicopterTailRotorDiscSmoketest] PASS helicopters=10,11,13,15")
	quit(0)


func _fail(aircraft_number: int, reason: String) -> void:
	push_error("[HelicopterTailRotorDiscSmoketest] Aircraft %d: %s" % [aircraft_number, reason])
	quit(1)
