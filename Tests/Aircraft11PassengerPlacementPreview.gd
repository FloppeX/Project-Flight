extends SceneTree

const OUTPUT_PATH := "res://screenshots/aircraft_11_passenger_placement.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1400, 900)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("26313b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d7e5ee")
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	light.light_energy = 1.6
	light.shadow_enabled = true
	viewport.add_child(light)

	var packed := load("res://Aircraft/Aircraft_11.tscn") as PackedScene
	var aircraft := packed.instantiate() as Node3D if packed != null else null
	if aircraft == null:
		_fail("could not instantiate Aircraft_11")
		return
	viewport.add_child(aircraft)
	if aircraft is RigidBody3D:
		(aircraft as RigidBody3D).freeze = true
	await process_frame

	var helicopter_pilot := aircraft.get_node_or_null("HelicopterPilot")
	for index in range(3):
		var passenger := Node3D.new()
		if helicopter_pilot == null or not bool(helicopter_pilot.call("add_passenger", passenger)):
			_fail("passenger %d was rejected" % (index + 1))
			return
		passenger.free()

	var cockpit_mount := aircraft.get_node_or_null("CockpitPilot")
	if cockpit_mount != null:
		cockpit_mount.call("set_presentation_active", true)
	for index in range(3):
		var marker := aircraft.get_node_or_null("Passenger%d" % (index + 1))
		var mount := marker.get_node_or_null("SeatedPassenger%d" % (index + 1)) \
				if marker != null else null
		if mount != null:
			mount.call("set_presentation_active", true)
	await process_frame
	await process_frame

	_show_cutaway_geometry(aircraft, aircraft)

	var camera := Camera3D.new()
	camera.position = Vector3(4.7, 2.7, 4.7)
	camera.fov = 37.0
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, -0.25, 0.45), Vector3.UP)
	camera.current = true

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("viewport produced no image")
		return
	var save_error := image.save_png(OUTPUT_PATH)
	if save_error != OK:
		_fail("could not save preview (error %d)" % save_error)
		return
	print("[Aircraft11PassengerPlacementPreview] PASS output=%s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	quit(0)


func _show_cutaway_geometry(node: Node, aircraft: Node) -> void:
	if node is MeshInstance3D:
		var relative_path := str(aircraft.get_path_to(node)).to_lower()
		if "pilotvisual" not in relative_path:
			(node as MeshInstance3D).visible = (
				relative_path == "aircraft_11/seat"
				or relative_path == "aircraft_11/seat back row"
				or relative_path == "aircraft_11/instrument panel"
			)
	for child in node.get_children():
		_show_cutaway_geometry(child, aircraft)


func _fail(message: String) -> void:
	push_error("[Aircraft11PassengerPlacementPreview] FAIL %s" % message)
	quit(1)
