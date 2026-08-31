extends SceneTree
## Verifies that cockpit pilots remain static until presented, then loop the
## baked piloting clip and hide only from the cockpit camera.

const COCKPIT_PILOT_SCENE := preload("res://Aircraft/CockpitPilot.tscn")
const PresentationDormancy := preload("res://Aircraft/AircraftPresentationDormancy.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pilot_pool := root.get_node_or_null("CockpitPilotPool")
	if pilot_pool == null or not pilot_pool.has_method("get_pool_stats"):
		_fail("cockpit pilot reserve autoload is missing")
		return
	var initial_pool_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(initial_pool_stats.get("created", 0)) != 2 \
			or int(initial_pool_stats.get("available", 0)) != 2:
		_fail("cockpit pilot reserve did not prewarm exactly two pilots")
		return
	if int(initial_pool_stats.get("animation_prepare_count", 0)) != 2:
		_fail("cockpit pilot reserve did not record both animation prewarms")
		return

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

	if cockpit_pilot.call("get_pilot_visual") != null:
		_fail("dormant cockpit mount checked out a reserve pilot")
		return
	var activation_started_usec := Time.get_ticks_usec()
	cockpit_pilot.call("set_presentation_active", true)
	var activation_ms := float(Time.get_ticks_usec() - activation_started_usec) / 1000.0
	await process_frame
	var active_pool_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(active_pool_stats.get("available", 0)) != 1 \
			or int(active_pool_stats.get("checked_out", 0)) != 1:
		_fail("presented cockpit did not borrow exactly one reserve pilot")
		return
	var pooled_visual := cockpit_pilot.call("get_pilot_visual") as Node3D
	var pilot_visual := pooled_visual.get_node_or_null("Pilot") as Node3D \
			if pooled_visual != null else null
	var skeleton := _find_skeleton(pilot_visual)
	var player := pooled_visual.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer \
			if pooled_visual != null else null
	if pooled_visual == null or pilot_visual == null or skeleton == null or player == null:
		_fail("presented cockpit mount did not check out a complete reserve pilot")
		return
	if player.current_animation != "piloting" or not player.is_playing():
		_fail("presented cockpit pilot did not start the piloting animation")
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

	var dormancy = PresentationDormancy.new(aircraft_host)
	if int(dormancy.detach()) <= 0 or aircraft_host.get_node_or_null("CockpitPilot") != null:
		_fail("presentation dormancy did not detach the cockpit pilot")
		return
	if player.is_playing():
		_fail("detached cockpit pilot kept evaluating its animation")
		return
	var dormant_pool_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(dormant_pool_stats.get("available", 0)) != 2:
		_fail("dormant cockpit did not return its pilot to the reserve")
		return
	dormancy.restore()
	pooled_visual = cockpit_pilot.call("get_pilot_visual") as Node3D
	player = pooled_visual.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer \
			if pooled_visual != null else null
	pilot_visual = pooled_visual.get_node_or_null("Pilot") as Node3D \
			if pooled_visual != null else null
	if aircraft_host.get_node_or_null("CockpitPilot") != cockpit_pilot \
			or player == null or not player.is_playing():
		_fail("restored cockpit pilot did not resume its animation")
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

	var second_host := Node3D.new()
	second_host.name = "SecondAircraftHost"
	root.add_child(second_host)
	var second_pilot := COCKPIT_PILOT_SCENE.instantiate() as Node3D
	second_host.add_child(second_pilot)
	second_pilot.call("set_presentation_active", true)
	var simultaneous_pool_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(simultaneous_pool_stats.get("created", 0)) != 2 \
			or int(simultaneous_pool_stats.get("available", 0)) != 0 \
			or int(simultaneous_pool_stats.get("checked_out", 0)) != 2:
		_fail("two presented aircraft did not borrow the two-pilot reserve")
		return
	if second_pilot.call("get_pilot_visual") == pooled_visual:
		_fail("two presented aircraft shared the same physical pilot")
		return
	var second_visual := second_pilot.call("get_pilot_visual") as Node3D
	var overflow_host := Node3D.new()
	overflow_host.name = "ExceptionalThirdPilotHost"
	root.add_child(overflow_host)
	var overflow_pilot := COCKPIT_PILOT_SCENE.instantiate() as Node3D
	overflow_host.add_child(overflow_pilot)
	overflow_pilot.call("set_presentation_active", true)
	var overflow_visual := overflow_pilot.call("get_pilot_visual") as Node3D
	var overflow_pool_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(overflow_pool_stats.get("created", 0)) != 3 \
			or int(overflow_pool_stats.get("checked_out", 0)) != 3 \
			or int(overflow_pool_stats.get("overflow_created_total", 0)) != 1 \
			or overflow_visual == pooled_visual or overflow_visual == second_visual:
		_fail("exceptional third request stole an already checked-out pilot")
		return
	overflow_host.free()
	second_host.free()

	aircraft_host.free()
	await process_frame
	var final_pool_stats: Dictionary = pilot_pool.call("get_pool_stats")
	if int(final_pool_stats.get("created", 0)) != 2 \
			or int(final_pool_stats.get("available", 0)) != 2 \
			or int(final_pool_stats.get("checked_out", 0)) != 0:
		_fail("released overflow did not settle back to a two-pilot reserve")
		return
	print("[CockpitPilotAnimationSmoketest] PASS reserve=2 simultaneous=2 overflow_safe=true returned=2 activation_ms=%.3f pooled=true deferred=true dormant_returned=true restored=true clip=piloting loop=true motion=%.2fdeg cockpit_hidden=true external_visible=true" % [
		activation_ms,
		rad_to_deg(motion_delta),
	])
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
