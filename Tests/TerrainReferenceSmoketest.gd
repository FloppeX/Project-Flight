extends SceneTree

class Terrain:
	extends Node3D
	func get_height(_position: Vector3) -> float: return 0.0

class CountingReference:
	extends "res://Environment/TerrainReference.gd"
	var searches := 0
	func _find_terrain_node():
		searches += 1
		super._find_terrain_node()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	for i in 4000: scene.add_child(Node3D.new())
	var reference := CountingReference.new()
	scene.add_child(reference)
	# Same lookup pattern as a fleet repeatedly asking for ground height.
	var start := Time.get_ticks_usec()
	for i in 1000: assert(reference.get_terrain_node() == null)
	var cached_us := Time.get_ticks_usec() - start
	assert(reference.searches <= 2, "Missing terrain must be cached")
	start = Time.get_ticks_usec()
	for i in 1000: reference._find_terrain_node()
	var uncached_us := Time.get_ticks_usec() - start
	var terrain := Terrain.new()
	scene.add_child(terrain)
	assert(reference.get_terrain_node() == terrain, "Discover late untagged terrain")
	scene.remove_child(terrain)
	assert(reference.get_terrain_node() == null, "Do not return detached terrain")
	terrain.free()
	var grouped := Node3D.new()
	scene.add_child(grouped)
	assert(reference.get_terrain_node() == null)
	grouped.add_to_group("terrain_provider")
	assert(reference.get_terrain_node() == grouped, "Discover late group assignment")
	grouped.free()
	assert(reference.get_terrain_node() == null, "Do not return freed terrain")
	var replacement := Terrain.new()
	scene.add_child(replacement)
	assert(reference.get_terrain_node() == replacement)
	print("TERRAIN_REFERENCE_PASS cached_us=", cached_us, " uncached_us=", uncached_us)
	quit()
