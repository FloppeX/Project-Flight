extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	for model in ["Aircraft_1", "Aircraft_5"]:
		var craft: RigidBody3D = load("res://Aircraft/%s.tscn" % model).instantiate()
		craft.freeze = true
		craft.position.y = 100.0
		scene.add_child(craft)
		for frame in range(5):
			await physics_frame
			await process_frame
		var safe_names: Array[String] = []
		for collider in craft.get("safe_colliders"):
			safe_names.append(str(collider.name))
		print("COLLIDER_DIAG model=%s safe=%s" % [model, safe_names])
		for owner_id in craft.get_shape_owners():
			var owner: Object = craft.shape_owner_get_owner(owner_id)
			for shape_slot in range(craft.shape_owner_get_shape_count(owner_id)):
				var index := craft.shape_owner_get_shape_index(owner_id, shape_slot)
				var mapped_owner := craft.shape_find_owner(index)
				var old_name := "INVALID_OWNER"
				if craft.get_shape_owners().has(index):
					old_name = str(craft.shape_owner_get_owner(index).name)
				print("COLLIDER_MAP model=%s index=%d owner_id=%d actual=%s old_lookup=%s disabled=%s transform=%s" % [
					model, index, mapped_owner, owner.name, old_name, str(craft.is_shape_owner_disabled(owner_id)),
					str(craft.shape_owner_get_transform(owner_id))])
		craft.free()
	scene.free()
	for scenario in [
		["Aircraft_1", "RightGearCollider", true],
		["Aircraft_1", "LeftGearCollider", true],
		["Aircraft_1", "CenterGearCollider", true],
		["Aircraft_5", "RightGearCollider", false],
		["Aircraft_1", "RightGearCollider", false],
	]:
		await _reproduce_contact(scenario[0], scenario[1], scenario[2])
	print("COLLIDER_DIAGNOSTIC_COMPLETE")
	quit()


func _reproduce_contact(model: String, wheel_name: String, multi_panel: bool) -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var carrier := StaticBody3D.new()
	carrier.name = "LandCarrierDiagnostic"
	scene.add_child(carrier)
	var craft: RigidBody3D = load("res://Aircraft/%s.tscn" % model).instantiate()
	# Counterfactual changes exist only on this isolated diagnostic instance.
	craft.get_node("WingDamageColliderFollower").set("fit_multi_panel_bounds", multi_panel)
	craft.freeze = true
	craft.position.y = 100.0
	scene.add_child(craft)
	for frame in range(5):
		await physics_frame
		await process_frame
	var wheel := craft.get_node(wheel_name)
	var index := -1
	for owner_id in craft.get_shape_owners():
		if craft.shape_owner_get_owner(owner_id) == wheel:
			index = craft.shape_owner_get_shape_index(owner_id, 0)
	assert(index >= 0, "Diagnostic wheel not found")
	craft.linear_velocity = Vector3(0.0, -1.0, 45.0)
	craft.call("_on_Aircraft_body_shape_entered", carrier.get_rid(), carrier, 0, index)
	print("CONTACT_REPRO model=%s wheel=%s multi_panel=%s index=%d exploded=%s touchdown=%s" % [
		model, wheel_name, multi_panel, index, craft.get("_has_exploded"),
		craft.get_meta("last_touchdown_details", {})])
	scene.free()
	await process_frame
