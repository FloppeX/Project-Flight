extends SceneTree
## Regression coverage for pooled cockpit pilots retaining their live piloting
## pose when the pause-menu photo camera takes over.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var pause_menu := root.get_node_or_null("PauseMenu")
	var flight_director := root.get_node_or_null("FlightDirector")
	_expect(pause_menu != null, "PauseMenu autoload is available")
	_expect(flight_director != null, "FlightDirector autoload is available")
	if pause_menu == null or flight_director == null:
		_finish()
		return

	var world := Node3D.new()
	world.name = "PhotoPilotWorld"
	root.add_child(world)
	current_scene = world
	var packed := load("res://Aircraft/Aircraft_1.tscn") as PackedScene
	var aircraft := packed.instantiate() as RigidBody3D if packed != null else null
	_expect(aircraft != null, "Aircraft 1 can be instantiated")
	if aircraft == null:
		_finish()
		return
	world.add_child(aircraft)
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")
	flight_director.set("current_category", 1)
	flight_director.call("_view_aircraft", aircraft)
	await process_frame
	await process_frame

	var mount := aircraft.get_node_or_null("CockpitPilot") as Node3D
	var pilot := mount.call("get_pilot_visual") as Node3D if mount != null else null
	var skeleton := _find_skeleton(pilot)
	var player := pilot.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer \
			if pilot != null else null
	_expect(mount != null and pilot != null and skeleton != null and player != null,
		"viewed aircraft has a complete pooled cockpit pilot")
	if mount == null or pilot == null or skeleton == null or player == null:
		_finish()
		return
	_expect(player.active and player.is_playing() and player.current_animation == "piloting",
		"cockpit pilot begins in the live piloting animation")
	var before := _pose_signature(skeleton)

	pause_menu.call("_open")
	pause_menu.call("enter_photo_mode")
	# This is the visual-budget behavior that previously reapplied every exported
	# pose control and left the paused skeleton in its standing fallback.
	for _repeat in range(3):
		mount.call("set_presentation_active", true)
	for _frame in range(10):
		await process_frame
	var after := _pose_signature(skeleton)
	_expect(bool(pause_menu.call("is_photo_mode_active")), "photo mode remains active")
	_expect(player.active and player.is_playing() and player.current_animation == "piloting",
		"piloting animation remains selected in photo mode")
	_expect(before == after, "photo mode preserves the evaluated seated pilot skeleton")

	pause_menu.call("exit_photo_mode")
	pause_menu.call("_close")
	world.queue_free()
	await process_frame
	_finish()


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


func _pose_signature(skeleton: Skeleton3D) -> String:
	var parts: PackedStringArray = []
	for bone_name in [
		&"spine_01.x", &"arm.l", &"forearm.l", &"thigh_stretch.l", &"leg_stretch.l"
	]:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var pose := skeleton.get_bone_global_pose(index)
		parts.append("%s:%s:%s" % [
			bone_name,
			pose.origin.snapped(Vector3.ONE * 0.001),
			pose.basis.get_euler().snapped(Vector3.ONE * 0.001),
		])
	return "|".join(parts)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error("[PhotoModePilotPoseSmoketest] FAIL %s" % description)


func _finish() -> void:
	paused = false
	if _failures.is_empty():
		print("[PhotoModePilotPoseSmoketest] PASS clip=piloting seated_pose_preserved=true repeated_activation=idempotent")
		quit(0)
		return
	quit(1)
