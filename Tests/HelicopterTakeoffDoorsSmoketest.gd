extends SceneTree

const HELICOPTERS: Array[Dictionary] = [
	{
		"scene": "res://Aircraft/Aircraft_9.tscn",
		"controller": "SlidingDoors",
	},
	{
		"scene": "res://Aircraft/Aircraft_11.tscn",
		"controller": "SwingDoors",
	},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for entry in HELICOPTERS:
		var packed := load(str(entry["scene"])) as PackedScene
		var aircraft := packed.instantiate() as RigidBody3D if packed != null else null
		if aircraft == null:
			_fail("could not instantiate %s" % str(entry["scene"]))
			return
		aircraft.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(aircraft)
		await process_frame

		var controller := aircraft.find_child(str(entry["controller"]), true, false)
		var pilot := aircraft.get_node_or_null("HelicopterPilot")
		if controller == null or pilot == null \
				or not controller.has_method("prepare_technical_index_preview"):
			aircraft.free()
			_fail("%s has no usable door controller or HelicopterPilot" % aircraft.name)
			return
		if not bool(controller.call("prepare_technical_index_preview")):
			aircraft.free()
			_fail("%s door controller did not initialize" % aircraft.name)
			return
		controller.call("set_technical_index_preview_fraction", 1.0)
		if float(controller.call("get_technical_index_preview_fraction")) < 0.99:
			aircraft.free()
			_fail("%s doors did not begin open" % aircraft.name)
			return

		pilot.set("aircraft", aircraft)
		pilot.set("state", 0) # State.IDLE
		pilot.call("change_state", 1) # State.TAKEOFF
		controller.call(
			"process_render_frame",
			float(controller.call("get_technical_index_preview_duration"))
		)
		if float(controller.call("get_technical_index_preview_fraction")) > 0.01:
			aircraft.free()
			_fail("%s doors remained open after TAKEOFF" % aircraft.name)
			return

		# A direct IDLE -> LOW_LEVEL_TRANSIT departure must use the same latch.
		controller.call("set_technical_index_preview_fraction", 1.0)
		pilot.set("state", 0) # State.IDLE
		pilot.call("change_state", 2) # State.LOW_LEVEL_TRANSIT
		controller.call(
			"process_render_frame",
			float(controller.call("get_technical_index_preview_duration"))
		)
		if float(controller.call("get_technical_index_preview_fraction")) > 0.01:
			aircraft.free()
			_fail("%s doors remained open after direct transit departure" % aircraft.name)
			return
		aircraft.free()
		await process_frame

	print("[HelicopterTakeoffDoorsSmoketest] PASS swing=true sliding=true takeoff=true direct_transit=true")
	quit(0)


func _fail(reason: String) -> void:
	push_error("[HelicopterTakeoffDoorsSmoketest] FAIL %s" % reason)
	quit(1)
