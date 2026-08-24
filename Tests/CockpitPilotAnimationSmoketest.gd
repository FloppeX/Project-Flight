extends SceneTree
## Verifies that cockpit pilots loop the baked piloting clip and are hidden only
## from the cockpit camera, not from chase/cinematic/external views.

const COCKPIT_PILOT_SCENE := preload("res://Aircraft/CockpitPilot.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft_host := Node3D.new()
	aircraft_host.name = "AircraftHost"
	root.add_child(aircraft_host)

	var cockpit_mount := Node3D.new()
	cockpit_mount.name = "CameraCockpit"
	aircraft_host.add_child(cockpit_mount)
	var cockpit_camera := Camera3D.new()
	cockpit_camera.name = "Camera3D"
	cockpit_mount.add_child(cockpit_camera)

	var external_camera := Camera3D.new()
	external_camera.name = "CameraExternal"
	aircraft_host.add_child(external_camera)

	var cockpit_pilot := COCKPIT_PILOT_SCENE.instantiate() as Node3D
	if cockpit_pilot == null:
		_fail("cockpit pilot scene did not instantiate")
		return
	aircraft_host.add_child(cockpit_pilot)
	await process_frame

	var pilot_visual := cockpit_pilot.get_node_or_null("Pilot") as Node3D
	var player := cockpit_pilot.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer
	var skeleton := _find_skeleton(pilot_visual)
	if pilot_visual == null or player == null or skeleton == null:
		_fail("cockpit pilot visual, player, or skeleton is missing")
		return
	if player.current_animation != "piloting" or not player.is_playing():
		_fail("cockpit pilot did not start the piloting animation")
		return
	var animation := player.get_animation(&"piloting")
	if animation == null or animation.loop_mode == Animation.LOOP_NONE:
		_fail("piloting animation is missing or not looping")
		return

	var arm_index := skeleton.find_bone("arm_stretch.l")
	if arm_index < 0:
		_fail("visible pilot arm deformation bone is missing")
		return
	player.seek(0.0, true)
	player.advance(0.0)
	var first_rotation := (
		skeleton.get_bone_global_pose(arm_index).basis.get_rotation_quaternion()
	)
	player.seek(animation.length * 0.47, true)
	player.advance(0.0)
	var later_rotation := (
		skeleton.get_bone_global_pose(arm_index).basis.get_rotation_quaternion()
	)
	var motion_delta := first_rotation.angle_to(later_rotation)
	if motion_delta < 0.01:
		_fail("piloting clip did not move the visible pilot arm")
		return

	cockpit_camera.make_current()
	for frame in range(2):
		await process_frame
	if pilot_visual.visible:
		_fail("pilot remained visible to the cockpit camera")
		return

	external_camera.make_current()
	for frame in range(2):
		await process_frame
	if not pilot_visual.visible:
		_fail("pilot remained hidden after switching to an external camera")
		return

	print("[CockpitPilotAnimationSmoketest] PASS clip=piloting loop=true motion=%.2fdeg cockpit_hidden=true external_visible=true" % [
		rad_to_deg(motion_delta),
	])
	aircraft_host.free()
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _fail(reason: String) -> void:
	push_error("[CockpitPilotAnimationSmoketest] FAIL %s" % reason)
	quit(1)
