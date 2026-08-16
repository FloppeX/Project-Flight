extends SceneTree

const EXPECTED_SIZE := Vector3(0.8, 1.85, 0.3)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "PilotPlaceholderSmoketest"
	root.add_child(scene)
	current_scene = scene

	var placeholder_scene := load("res://Models/Characters/PilotPlaceholder.tscn") as PackedScene
	if placeholder_scene == null:
		_fail("placeholder scene did not load")
		return
	var placeholder := placeholder_scene.instantiate() as Node3D
	var mesh_instance := placeholder.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var box_mesh := mesh_instance.mesh as BoxMesh if mesh_instance != null else null
	if box_mesh == null or not box_mesh.size.is_equal_approx(EXPECTED_SIZE):
		_fail("placeholder mesh was not 0.8 x 1.85 x 0.3 metres")
		return
	var material := box_mesh.material as StandardMaterial3D
	if material == null or not is_equal_approx(material.albedo_color.r, material.albedo_color.g) \
			or not is_equal_approx(material.albedo_color.g, material.albedo_color.b):
		_fail("placeholder material was not grey")
		return

	var downed_scene := load("res://Models/Characters/DownedPilot.tscn") as PackedScene
	var downed := downed_scene.instantiate() as Node3D if downed_scene != null else null
	if downed == null or downed.get_node_or_null("Model/MeshInstance3D") == null:
		_fail("downed pilot did not use the placeholder")
		return
	if downed.find_child("Skeleton3D", true, false) != null:
		_fail("downed pilot still contained a character skeleton")
		return
	var ground_head := downed.get_node_or_null("HeadCameraMount") as Marker3D
	if ground_head == null or not is_equal_approx(ground_head.position.y, 1.7):
		_fail("downed-pilot camera marker was not at head height")
		return
	var ground_camera_rig := Node3D.new()
	ground_camera_rig.name = "CameraCockpit"
	var ground_camera := Camera3D.new()
	ground_camera.name = "Camera3D"
	ground_camera.position = Vector3(0.1, -0.4, 0.2)
	ground_camera_rig.add_child(ground_camera)
	downed.add_child(ground_camera_rig)
	var sequence_script := load("res://Aircraft/EjectionSequence.gd") as Script
	var sequence := Node.new()
	sequence.set_script(sequence_script)
	scene.add_child(sequence)

	var cockpit_scene := load("res://Aircraft/CockpitPilot.tscn") as PackedScene
	var cockpit := cockpit_scene.instantiate() as Node3D if cockpit_scene != null else null
	if cockpit == null:
		_fail("cockpit pilot scene did not load")
		return
	var aircraft := RigidBody3D.new()
	aircraft.name = "CockpitVisibilityAircraft"
	var camera_rig := Node3D.new()
	camera_rig.name = "CameraCockpit"
	var cockpit_camera := Camera3D.new()
	cockpit_camera.name = "Camera3D"
	camera_rig.add_child(cockpit_camera)
	aircraft.add_child(camera_rig)
	aircraft.add_child(cockpit)
	scene.add_child(aircraft)
	cockpit_camera.current = true
	await process_frame
	var detailed_visual := cockpit.get_node_or_null("Pilot") as Node3D
	if detailed_visual == null or detailed_visual.visible:
		_fail("detailed pilot remained visible from the cockpit camera")
		return
	cockpit_camera.current = false
	await process_frame
	if not detailed_visual.visible:
		_fail("detailed pilot remained hidden after leaving the cockpit camera")
		return
	cockpit.call("set_ejection_pose", &"seat_firing", 0.0)
	var parachute_placeholder := cockpit.get_node_or_null("ParachutePlaceholder") as Node3D
	if not detailed_visual.visible or parachute_placeholder == null or parachute_placeholder.visible:
		_fail("seat ride did not retain the normal cockpit pilot")
		return
	cockpit.call("set_ejection_pose", &"falling", 0.0)
	if detailed_visual.visible or not parachute_placeholder.visible:
		_fail("pilot did not change to the placeholder at seat separation")
		return
	cockpit.call("set_ejection_pose", &"parachute", 0.0)
	if detailed_visual == null or detailed_visual.visible:
		_fail("detailed pilot remained visible under parachute")
		return
	if parachute_placeholder == null or not parachute_placeholder.visible:
		_fail("parachute placeholder was not visible")
		return

	scene.add_child(downed)
	sequence.call("_position_landed_camera_at_head", ground_camera_rig, downed)
	if ground_camera.global_position.distance_to(ground_head.global_position) > 0.001:
		_fail("landed look camera did not align to the pilot's head")
		return

	print("[PilotPlaceholderSmoketest] PASS size=%s" % str(box_mesh.size))
	placeholder.free()
	downed.free()
	scene.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[PilotPlaceholderSmoketest] FAIL %s" % reason)
	quit(1)
