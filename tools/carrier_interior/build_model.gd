extends SceneTree
## Generate lightweight inherited overrides; geometry lives only in the GLB.

func _initialize() -> void:
	var base: Node3D = load("res://Models/LandCarrier/CarrierUnified.glb").instantiate()
	var lines := PackedStringArray([
		'[gd_scene load_steps=4 format=3]', '',
		'[ext_resource type="PackedScene" path="res://Models/LandCarrier/CarrierUnified.glb" id="1"]',
		'[ext_resource type="Script" path="res://LandCarrier/CarrierIslandIntegration.gd" id="2"]',
		'[ext_resource type="Script" path="res://LandCarrier/CarrierSlidingDoor.gd" id="3"]', '',
		'[node name="CarrierWithInterior" instance=ExtResource("1")]',
		'script = ExtResource("2")', 'metadata/island_baked = true', ''
	])
	append_overrides(base, base, lines)
	var file := FileAccess.open("res://Models/LandCarrier/CarrierWithInterior.tscn", FileAccess.WRITE)
	assert(file != null)
	file.store_string("\n".join(lines))
	file.close()
	print("CARRIER_INTERIOR_MODEL_BUILT ", base.get_child_count())
	base.free()
	quit()

func append_overrides(node: Node, base: Node, lines: PackedStringArray) -> void:
	var extras: Dictionary = node.get_meta("extras", {}).duplicate()
	for key in node.get_meta_list():
		if key != &"extras":
			extras[key] = node.get_meta(key)
	if node != base and not extras.is_empty():
		lines.append('[node name=%s parent=%s index="%d"]' % [var_to_str(String(node.name)), var_to_str(String(base.get_path_to(node.get_parent()))), node.get_index()])
		if extras.get("door_type", "") == "center_split_sliding":
			lines.append('script = ExtResource("3")')
		for key in extras:
			lines.append('metadata/%s = %s' % [key, var_to_str(extras[key])])
		lines.append('')
	for child in node.get_children():
		append_overrides(child, base, lines)
