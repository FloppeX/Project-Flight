extends RefCounted
## Exact derived-data cache. Never deserialize objects, and validate before use.
const VERSION := 1
const DIRECTORY := "user://navigation_grids"

static func fingerprint(grid, terrain: Node3D) -> String:
	# Unknown/custom providers must explicitly remain uncached: their hidden state
	# need not be determined by exported properties.
	if terrain.get_script() != load("res://Environment/LowPolyTerrain.gd"): return ""
	var settings: Array = [VERSION, Engine.get_version_info().string,
		FileAccess.get_sha256("res://Environment/LowPolyTerrain.gd"),
		FileAccess.get_sha256("res://Environment/HighlandsProfile.gd"),
		FileAccess.get_sha256("res://Environment/TerrainNavGrid.gd"),
		terrain.global_transform, grid._bake_center_x, grid._bake_center_z,
		grid.bake_half_extent_m, grid.cell_size_m, grid.query_grid_enabled,
		grid.query_cell_size_m, grid.query_edge_radius_cells, grid.prefer_batch_height_sampling]
	for property in terrain.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			var value: Variant = terrain.get(property.name)
			if value is Object: return "" # fail closed if a future exported resource is added
			settings.append([property.name, value])
	# Include initialized noise configuration, not just its nominal seed inputs.
	for noise_name in terrain._noises:
		var noise: Resource = terrain._noises[noise_name]
		for property in noise.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE:
				var value: Variant = noise.get(property.name)
				if value is Object: return ""
				settings.append([noise_name, property.name, value])
	return digest(var_to_bytes(settings))

static func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func cache_path(key: String) -> String:
	return DIRECTORY.path_join(key + ".bin")

static func read(key: String, coarse_count: int, query_count: int) -> Dictionary:
	if key.is_empty() or not FileAccess.file_exists(cache_path(key)): return {}
	var file := FileAccess.open(cache_path(key), FileAccess.READ)
	if file == null: return {}
	var expected_max := (coarse_count + query_count * 3) * 4 + 4096
	if file.get_length() > expected_max or file.get_length() < 80: return {}
	if file.get_line() != "NAVGRID1": return {}
	var checksum := file.get_line()
	var bytes := file.get_buffer(file.get_length() - file.get_position())
	if digest(bytes) != checksum: return {}
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary: return {}
	if value.get("key") != key or value.get("version") != VERSION: return {}
	for name in ["heights", "query", "variation", "maxima"]:
		if not value.get(name) is PackedFloat32Array: return {}
		if value[name].size() != (coarse_count if name == "heights" else query_count): return {}
	if typeof(value.get("minimum")) != TYPE_FLOAT: return {}
	return value

static func write(key: String, grid) -> bool:
	if key.is_empty(): return false
	var bytes := var_to_bytes({"version": VERSION, "key": key,
		"heights": grid._heights, "query": grid._query_heights,
		"variation": grid._query_height_variation, "maxima": grid._query_max_heights,
		"minimum": grid._h_min_passable})
	if DirAccess.make_dir_recursive_absolute(DIRECTORY) != OK: return false
	var path := cache_path(key)
	var temporary := path + ".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_line("NAVGRID1")
	file.store_line(digest(bytes))
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	return DirAccess.rename_absolute(temporary, path) == OK
