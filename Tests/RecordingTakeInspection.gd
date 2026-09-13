extends SceneTree
## Read-only diagnosis of a saved visual take. Pass its directory after --.
func _initialize() -> void:
	call_deferred("inspect_take")

func inspect_take() -> void:
	for node in root.get_children():
		node.process_mode = Node.PROCESS_MODE_DISABLED
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var take = load("res://Recording/SceneTake.gd").new()
	if not take.load_from(args[0]):
		push_error("Cannot load take")
		quit(1)
		return
	root.add_child(take.world)
	print("TAKE subjects=%d tracks=%d frames=%d duration=%.2f warning=%s" % [take.subjects.size(), take.copies.size(), take.frames.size(), take.duration(), take.warning])
	for subject in take.subjects:
		var index: int = take.copies.find(subject)
		var shown := 0
		for frame in take.frames:
			if index < frame.visible.size() and frame.visible[index]: shown += 1
		print("SUBJECT name=%s children=%d visible_frames=%d" % [subject.get_meta("display_name", subject.name), subject.get_child_count(), shown])
		if index == 0: continue
		var previous := Vector3.ZERO
		for frame_index in range(take.frames.size()):
			var frame: Dictionary = take.frames[frame_index]
			if index >= frame.poses.size() or not frame.visible[index]: continue
			var local: Transform3D = frame.poses[0].affine_inverse() * frame.poses[index]
			var dt: float = take.times[frame_index] - take.times[maxi(0, frame_index - 1)]
			var velocity := (local.origin - previous) / maxf(dt, 0.001)
			previous = local.origin
			if frame_index % 6 == 0:
				print("MOTION subject=%s t=%.2f local=%s vel=%s pitch=%.1f" % [subject.name, take.times[frame_index], local.origin, velocity, rad_to_deg(local.basis.get_euler().x)])
	for time in [0.0, take.duration() * 0.5, take.duration()]:
		take.seek(time)
		var visible_meshes := 0
		for copy in take.copies:
			if copy is MeshInstance3D and copy.is_visible_in_tree(): visible_meshes += 1
		print("FRAME time=%.2f visible_meshes=%d" % [time, visible_meshes])
	var model: Node = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	print("AIRCRAFT_5 authored_visual_tracks=%d" % count_visuals(model))
	model.free()
	take.dispose()
	quit()

func count_visuals(node: Node) -> int:
	if node is SubViewport: return 0
	var count := int(node is MeshInstance3D or node is MultiMeshInstance3D or node is Skeleton3D)
	for child in node.get_children(): count += count_visuals(child)
	return count
