extends SceneTree
## Bake the chamber's construction geometry into an editable, articulated GLB.
## godot --headless --path . --script tools/export_replicator.gd
const OUTPUT := "res://Models/Replicator/replicator.glb"
var mesh_count := 0

func _initialize() -> void:
	_export.call_deferred()

func _export() -> void:
	await process_frame
	var source: Node3D = load("res://LandCarrier/ReplicatorChamber.gd").new()
	source.export_source = true
	root.add_child(source)
	var asset := Node3D.new()
	asset.name = "Replicator"
	var frame := _group(asset, "FabricationFrame")
	var room := _group(asset, "CarrierCompartment")
	var arms := _group(asset, "Arms")
	var excluded: Array[Node] = [source._platform, source._shield]
	for index in range(source._arms.size()):
		var arm: Dictionary = source._arms[index]
		var pose: Dictionary = source._motion.poses[index]
		source._pose_link(arm.upper, pose.shoulder, pose.elbow)
		source._pose_link(arm.forearm, pose.elbow, pose.wrist)
		arm.joint.position = pose.elbow
		arm.tool.position = pose.wrist
		var group := _group(arms, "Arm_%d" % index)
		for entry in [["upper", "Upper"], ["forearm", "Forearm"], ["joint", "Joint"], ["tool", "Tool"]]:
			var part: Node3D = arm[entry[0]]
			excluded.append(part)
			_copy_geometry(part, group, "%s_%d" % [entry[1], index])
		excluded.append(arm.laser)
		excluded.append(arm.glow)
	_copy_geometry(source._platform, asset, "TransferPlatform")
	_copy_geometry(source._shield, asset, "DescendingShield")
	var shield: Node3D = asset.get_node("DescendingShield")
	for index in range(shield.get_child_count()):
		shield.get_child(index).name = ("ShieldPanel_%02d" if index % 2 == 0 else "ShieldSeal_%02d") % (index / 2)
	var frame_index := 0
	var room_index := 0
	for child in source.get_children():
		if not child is MeshInstance3D or child in excluded:
			continue
		var machine: bool = absf(child.position.x) < 6.6 and child.position.z < 7.0 and child.position.z > -6.6
		var label: String
		if str(child.name).begins_with("BuildPad") or str(child.name).begins_with("UpperOctagon_") or str(child.name).begins_with("LowerOctagonRail_"):
			label = str(child.name)
		elif machine:
			label = "FramePart_%03d" % frame_index
		else:
			label = "CompartmentPart_%03d" % room_index
		if child.name == "CarrierCeiling":
			label = "CarrierCeiling"
		_copy_geometry(child, frame if machine else room, label)
		frame_index += 1 if machine else 0
		room_index += 0 if machine else 1
	_set_owners(asset, asset)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_scene(asset, state)
	if result == OK:
		result = document.write_to_filesystem(state, ProjectSettings.globalize_path(OUTPUT))
	if result != OK:
		push_error("REPLICATOR_EXPORT_FAIL: " + error_string(result))
	else:
		print("REPLICATOR_EXPORT_PASS meshes=%d file=%s" % [mesh_count, OUTPUT])
	asset.free()
	source.free()
	quit(0 if result == OK else 1)

func _group(parent: Node3D, label: String) -> Node3D:
	var result := Node3D.new()
	result.name = label
	parent.add_child(result)
	return result

func _copy_geometry(source: Node3D, parent: Node3D, label: String) -> void:
	var copy: Node3D
	if source is MeshInstance3D:
		var mesh := MeshInstance3D.new()
		mesh.mesh = source.mesh
		mesh.material_override = source.material_override
		mesh.cast_shadow = source.cast_shadow
		copy = mesh
		mesh_count += 1
	else:
		copy = Node3D.new()
	copy.name = label
	copy.transform = source.transform
	parent.add_child(copy)
	var detail := 0
	for child in source.get_children():
		if child is MeshInstance3D:
			var name_hint: String = str(child.name)
			_copy_geometry(child, copy, name_hint if not name_hint.begins_with("@") and name_hint != "MeshInstance3D" else "Detail_%02d" % detail)
			detail += 1

func _set_owners(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		_set_owners(child, owner_root)
