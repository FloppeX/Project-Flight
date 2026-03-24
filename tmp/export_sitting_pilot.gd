extends SceneTree

var _inst: Node
var _skel: Skeleton3D
var _frame := 0

func _init():
	var scene = load("res://Pilot.glb")
	if not scene:
		print("ERROR: Could not load Pilot.glb")
		quit()
		return
	_inst = scene.instantiate()
	root.add_child(_inst)

	# Remove AnimationPlayer so it doesn't interfere
	var ap = _find_node(_inst, "AnimationPlayer") as AnimationPlayer
	if ap:
		ap.queue_free()

	_skel = _find_skeleton(_inst)
	if not _skel:
		print("ERROR: No Skeleton3D found")
		quit()
		return

func _process(_delta):
	_frame += 1

	if _frame == 2:
		# Apply sitting pose after one frame (skeleton is ready)
		_skel.reset_bone_poses()
		_apply_sitting_pose()
		print("Pose applied, waiting for skeleton update...")

	elif _frame == 4:
		# Export after pose has settled
		print("Exporting...")
		_export_glb()
		_inst.queue_free()
		quit()

func _apply_sitting_pose():
	# ---- LEGS ----
	# Upper legs: forward to sit (thighs ~horizontal)
	_rot("UpperLeg.L", 75, 0, -5)
	_rot("UpperLeg.R", 75, 0, 5)
	# Lower legs: bend at knee
	_rot("LowerLeg.L", 80, 0, 0)
	_rot("LowerLeg.R", 80, 0, 0)
	# Feet: point forward/flat (IK targets parented to Root)
	_rot("Foot.L", -30, 0, 0)
	_rot("Foot.R", -30, 0, 0)

	# ---- SPINE ----
	# Slight forward lean for natural seated posture
	_rot("Abdomen", 3, 0, 0)
	_rot("Torso", 2, 0, 0)
	_rot("Neck", -5, 0, 0)
	_rot("Head", -5, 0, 0)

	# ---- ARMS ----
	# Bring arms down from T-pose and forward, hands toward center
	_rot("Shoulder.L", 0, 0, 30)
	_rot("Shoulder.R", 0, 0, -30)
	_rot("UpperArm.L", 90, 0, 40)
	_rot("UpperArm.R", 90, 0, -40)
	_rot("LowerArm.L", 100, 0, 0)
	_rot("LowerArm.R", 100, 0, 0)

	# ---- WRISTS ----
	_rot("Wrist.L", 10, -10, 0)
	_rot("Wrist.R", 10, 10, 0)

	# ---- FINGERS (grip) ----
	for side in ["L", "R"]:
		for finger in ["Index", "Middle", "Ring", "Pinky"]:
			_rot("%s1.%s" % [finger, side], 20, 0, 0)
			_rot("%s2.%s" % [finger, side], 50, 0, 0)
			_rot("%s3.%s" % [finger, side], 40, 0, 0)
			_rot("%s4.%s" % [finger, side], 30, 0, 0)
		_rot("Thumb1.%s" % side, 20, 10, 0)
		_rot("Thumb2.%s" % side, 30, 0, 0)
		_rot("Thumb3.%s" % side, 20, 0, 0)

func _rot(bone_name: String, x_deg: float, y_deg: float, z_deg: float):
	var idx := _skel.find_bone(bone_name)
	if idx >= 0:
		_skel.set_bone_pose_rotation(idx, Quaternion.from_euler(Vector3(
			deg_to_rad(x_deg), deg_to_rad(y_deg), deg_to_rad(z_deg))))
	else:
		print("WARNING: Bone '%s' not found" % bone_name)

func _export_glb():
	var doc := GLTFDocument.new()
	var state := GLTFState.new()

	var err := doc.append_from_scene(_inst, state)
	if err != OK:
		print("ERROR: Failed to append scene: %s" % error_string(err))
		return

	var output_path := "res://Pilot_sitting.glb"
	err = doc.write_to_filesystem(state, output_path)
	if err != OK:
		print("ERROR: Failed to write GLB: %s" % error_string(err))
		return

	print("SUCCESS: Exported to %s" % output_path)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r: return r
	return null

func _find_node(node: Node, node_name: String) -> Node:
	if node.name == node_name: return node
	for c in node.get_children():
		var r = _find_node(c, node_name)
		if r: return r
	return null
