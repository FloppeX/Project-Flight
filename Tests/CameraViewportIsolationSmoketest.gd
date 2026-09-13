extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var switcher := preload("res://Tests/Fixtures/SchematicCameraControllerFixture.gd").new()
	world.add_child(switcher)
	var previous := Camera3D.new()
	world.add_child(previous)
	previous.make_current()
	var next := Camera3D.new()
	world.add_child(next)
	var secondary := SubViewport.new()
	secondary.own_world_3d = true
	world.add_child(secondary)
	var monitor_camera := Camera3D.new()
	secondary.add_child(monitor_camera)
	monitor_camera.make_current()
	var console := root.get_node("CarrierConsole")
	var page: Control = console.get("_carrier_page")
	var schematic: Control = page.get("_wireframe_view")
	var schematic_camera: Camera3D = schematic.get("_preview_camera")
	switcher.call("_deactivate_all_cameras")
	switcher.call("_force_current_camera", next)
	await process_frame
	await process_frame
	if root.get_camera_3d() != next or previous.is_current():
		push_error("Main viewport failed to switch gameplay cameras")
		quit(1)
		return
	if secondary.get_camera_3d() != monitor_camera or not schematic_camera.is_current():
		push_error("Gameplay camera switch interrupted a secondary viewport")
		quit(1)
		return
	print("CAMERA_VIEWPORT_ISOLATION_SMOKETEST_OK gameplay_switched=true monitor_preserved=true schematic_preserved=true")
	quit(0)
