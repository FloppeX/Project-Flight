extends SceneTree
## Authored-frame height probe ONLY. The old trace did not record its floating
## origin terrain transform, so these heights cannot diagnose the original loss.

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	push_warning("Original terrain frame is unknown: these authored-frame heights are NOT original crash evidence.")
	var terrain: Variant = load("res://Environment/LowPolyTerrain.gd").new()
	var state := (load("res://Main_Scene.tscn") as PackedScene).get_state()
	for node_index in state.get_node_count():
		if state.get_node_name(node_index) != &"LowPolyTerrainPrototype": continue
		for property_index in state.get_node_property_count(node_index):
			var property := state.get_node_property_name(node_index, property_index)
			if property != &"script":
				terrain.set(property, state.get_node_property_value(node_index, property_index))
	terrain.generate_on_ready = false
	root.add_child(terrain)
	var points := [Vector3(254.7038, 751.7502, 1284.97), Vector3(20.68422, 739.6762, 1159.623),
		Vector3(-83.6629, 747.1042, 1069.774), Vector3(-138.1899, 751.7268, 1021.973),
		Vector3(-138.1899, 751.7268, 1021.973) + Vector3(-54.51456, 4.665282, -47.81554) * 0.230]
	for point in points:
		var height := float(terrain.get_height(point))
		print("RECOVERY_TERRAIN_REPLAY position=%s terrain_y=%.3f clearance=%.3f" % [point, height, point.y - height])
	# Let UI observers finish their deferred terrain configuration before cleanup.
	await process_frame
	terrain.queue_free()
	await process_frame
	quit()
