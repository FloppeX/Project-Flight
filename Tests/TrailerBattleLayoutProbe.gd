extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.get_node("SaveGameManager").prepare_trailer_scenario()
	change_scene_to_file("res://Main_Scene.tscn")
	var deadline := Time.get_ticks_msec() + 240000
	var director: Node
	while Time.get_ticks_msec() < deadline:
		await process_frame
		director = get_first_node_in_group("trailer_scenario")
		if director != null and bool(director.get("ready_to_run")): break
	if director == null or not bool(director.get("ready_to_run")):
		print("TRAILER_LAYOUT_FAILED restore")
		quit(1)
		return
	var carrier := get_first_node_in_group("carrier") as Node3D
	var terrain: Node = root.get_node("TerrainReference").get_terrain_node()
	var candidates: Array[Dictionary] = []
	for bearing in range(300, 361, 5):
		var forward := Vector3(sin(deg_to_rad(bearing)), 0, -cos(deg_to_rad(bearing)))
		var friendly := carrier.global_position + forward * 3000.0
		for enemy_bearing in range(0, 360, 15):
			var direction := Vector3(sin(deg_to_rad(enemy_bearing)), 0, -cos(deg_to_rad(enemy_bearing)))
			var enemy := friendly + direction * 2000.0
			if Vector2(enemy.x - carrier.global_position.x, enemy.z - carrier.global_position.z).length() < 3000: continue
			var right := direction.cross(Vector3.UP)
			var low := INF
			var high := -INF
			for index in 41:
				for across in [-150.0, 0.0, 150.0]:
					var point: Vector3 = friendly.lerp(enemy, index / 40.0) + right * float(across)
					var height := float(terrain.call("get_height", point))
					low = minf(low, height)
					high = maxf(high, height)
			candidates.append({"bearing": bearing, "enemy_bearing": enemy_bearing, "span": high-low, "ground": low, "friendly_offset": friendly-carrier.global_position, "enemy_offset": enemy-carrier.global_position})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return a.span < b.span)
	for candidate in candidates.slice(0, 12): print("TRAILER_LAYOUT ", candidate)
	print("TRAILER_LAYOUT_DONE carrier=", carrier.global_position)
	quit()
