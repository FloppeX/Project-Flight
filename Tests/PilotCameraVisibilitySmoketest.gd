extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	await process_frame
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var cockpit := Node3D.new()
	cockpit.name = "CameraCockpit"
	scene.add_child(cockpit)
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	cockpit.add_child(eye)
	eye.make_current()
	var mount: Node3D = load("res://Aircraft/CockpitPilot.tscn").instantiate()
	scene.add_child(mount)
	mount.set_presentation_active(true)
	var pilot: Node3D = mount.get_pilot_visual()
	pilot.refresh_cockpit_visibility()
	check(pilot._last_head_hidden, "own actual cockpit hides pilot")
	paused = true
	var external := Camera3D.new()
	scene.add_child(external)
	external.set_meta(&"free_camera_view_source", eye)
	external.global_transform = eye.global_transform
	external.make_current()
	await check_visibility(pilot, false, "coincident free camera restores pilot while paused")
	var other_cockpit := Camera3D.new()
	scene.add_child(other_cockpit)
	other_cockpit.make_current()
	await check_visibility(pilot, false, "another aircraft cockpit must not hide this pilot")
	eye.make_current()
	await check_visibility(pilot, true, "returning to own cockpit hides pilot while paused")
	scene.remove_child(cockpit)
	external.make_current()
	await check_visibility(pilot, false, "detached dormant cockpit cannot hide pilot")
	cockpit.free()
	await check_visibility(pilot, false, "freed cockpit reference is safe")
	paused = false
	mount.set_presentation_active(false)
	scene.queue_free()
	await process_frame
	print("PILOT_CAMERA_VISIBILITY_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)

func check_visibility(pilot: Node3D, hidden: bool, label: String) -> void:
	if DisplayServer.get_name() == "headless": pilot._refresh_visibility_before_draw()
	else: await RenderingServer.frame_post_draw
	check(pilot._last_head_hidden == hidden, label)
	for mesh in pilot._cockpit_hidden_nodes:
		check(mesh.is_visible_in_tree() != hidden, label + " mesh")

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)
