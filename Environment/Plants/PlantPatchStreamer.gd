extends Node3D
class_name PlantPatchStreamer

const DEFAULT_PLANT_SCENE: PackedScene = preload("res://Environment/Plants/Cactus.tscn")
const LAYOUT_VERSION := 5

@export_group("Plant")
@export var streaming_enabled: bool = false
@export var plant_scene: PackedScene = DEFAULT_PLANT_SCENE
@export var seed: int = 424242
@export var layout_save_path: String = "user://plant_patch_layouts/cactus_patches_v5.json"
@export var regenerate_layout_on_start: bool = false
@export var resnap_loaded_positions_to_terrain: bool = true
@export var center_layout_on_nav_area: bool = true

@export_group("Patch Layout")
@export var patch_count: int = 36
@export var spawn_radius_m: float = 6500.0
@export var inner_exclusion_m: float = 450.0
@export var near_start_patch_count: int = 5
@export var near_start_min_radius_m: float = 300.0
@export var near_start_max_radius_m: float = 1100.0
@export var patch_radius_m: float = 34.0
@export var plants_per_patch_min: int = 12
@export var plants_per_patch_max: int = 18
@export var plant_spacing_min_m: float = 5.0
@export var plant_spacing_max_m: float = 10.0
@export var placement_attempts_per_patch: int = 120

@export_group("Ground Fit")
@export var max_slope_deg: float = 18.0
@export var slope_sample_m: float = 3.0
@export var ground_sink_m: float = 0.12

@export_group("Variation")
@export var min_scale: float = 1.6
@export var max_scale: float = 2.4
@export var max_lean_deg: float = 3.0

@export_group("Streaming")
@export var stream_radius_m: float = 2200.0
@export var despawn_radius_m: float = 2500.0
@export var update_interval_s: float = 0.4
@export var max_visible_plants: int = 320

var _terrain: LowPolyTerrain
var _layout_ready := false
var _records: Array[Dictionary] = []
var _patch_local_centers: Array[Dictionary] = []
var _active: Dictionary = {}
var _update_timer := 0.0
var _layout_center_local: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("origin_shifter")
	add_to_group("plant_patch_streamer")
	if not streaming_enabled:
		set_process(false)
		_clear_active_plants()
		return
	call_deferred("_try_initialize_layout")


func _process(delta: float) -> void:
	if not streaming_enabled:
		_clear_active_plants()
		set_process(false)
		return
	if not _layout_ready:
		_try_initialize_layout()
		return

	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = maxf(update_interval_s, 0.05)
	_update_streamed_plants()


func apply_origin_shift(_offset: Vector3) -> void:
	if not streaming_enabled:
		return
	_update_timer = 0.0


func is_layout_ready() -> bool:
	return streaming_enabled and _layout_ready


func get_patch_map_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if not streaming_enabled:
		return markers
	for patch in _patch_local_centers:
		var local_pos := patch["position"] as Vector3
		markers.append({
			"patch": int(patch["patch"]),
			"count": int(patch["count"]),
			"position": to_global(local_pos),
		})
	return markers


func _try_initialize_layout() -> void:
	if not streaming_enabled:
		return
	if _layout_ready:
		return
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("terrain_provider") as LowPolyTerrain
		if _terrain == null:
			return
	if center_layout_on_nav_area and not TerrainNavGrid.is_ready():
		return

	_refresh_layout_center()

	if not regenerate_layout_on_start and _load_layout():
		_rebuild_patch_center_cache()
		_layout_ready = true
		_update_streamed_plants()
		return

	_generate_layout()
	_rebuild_patch_center_cache()
	_save_layout()
	_layout_ready = true
	_update_streamed_plants()


func _generate_layout() -> void:
	_records.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var next_id := 0
	var patch_index := 0

	for _i in range(clampi(near_start_patch_count, 0, patch_count)):
		var patch_records := _generate_near_start_patch(patch_index, rng, next_id)
		if patch_records.is_empty():
			continue
		for record in patch_records:
			_records.append(record)
		next_id += patch_records.size()
		patch_index += 1

	while patch_index < maxi(patch_count, 0):
		var patch_records := _generate_patch(patch_index, rng, next_id)
		if not patch_records.is_empty():
			for record in patch_records:
				_records.append(record)
			next_id += patch_records.size()
		patch_index += 1


func _generate_patch(patch_index: int, rng: RandomNumberGenerator, start_id: int) -> Array[Dictionary]:
	for _center_attempt in 50:
		var center := _random_patch_center(rng)
		var records := _generate_patch_from_center(patch_index, rng, start_id, center)
		if not records.is_empty():
			return records

	return []


func _generate_near_start_patch(patch_index: int, rng: RandomNumberGenerator, start_id: int) -> Array[Dictionary]:
	for _center_attempt in 80:
		var center := _random_near_start_patch_center(rng)
		var records := _generate_patch_from_center(patch_index, rng, start_id, center)
		if not records.is_empty():
			return records
	return []


func _generate_patch_from_center(patch_index: int, rng: RandomNumberGenerator, start_id: int, center: Vector2) -> Array[Dictionary]:
	var center_y := _sample_valid_ground_y(center.x, center.y)
	if is_nan(center_y):
		return []

	var target_count := rng.randi_range(
		maxi(plants_per_patch_min, 1),
		maxi(plants_per_patch_max, plants_per_patch_min)
	)
	var points: Array[Vector2] = [center]
	var tries := 0
	while points.size() < target_count and tries < max(placement_attempts_per_patch, target_count * 10):
		tries += 1
		var anchor: Vector2 = points[rng.randi_range(0, points.size() - 1)]
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(plant_spacing_min_m, plant_spacing_max_m)
		var candidate := anchor + Vector2(cos(angle), sin(angle)) * distance

		if candidate.distance_to(center) > patch_radius_m:
			continue
		if not _has_minimum_spacing(candidate, points):
			continue
		if is_nan(_sample_valid_ground_y(candidate.x, candidate.y)):
			continue
		points.append(candidate)

	if points.size() < plants_per_patch_min:
		return []

	var records: Array[Dictionary] = []
	for point_index in range(points.size()):
		var point := points[point_index]
		var y := _sample_valid_ground_y(point.x, point.y)
		if is_nan(y):
			continue
		records.append(_make_record(start_id + records.size(), patch_index, point, y, rng))
	return records


func _make_record(id: int, patch_index: int, point: Vector2, ground_y: float, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"id": id,
		"patch": patch_index,
		"position": Vector3(point.x, ground_y - ground_sink_m, point.y),
		"yaw": rng.randf() * TAU,
		"lean_x": deg_to_rad(rng.randf_range(-max_lean_deg, max_lean_deg)),
		"lean_z": deg_to_rad(rng.randf_range(-max_lean_deg, max_lean_deg)),
		"scale": rng.randf_range(min_scale, max_scale),
	}


func _random_patch_center(rng: RandomNumberGenerator) -> Vector2:
	var radius := sqrt(rng.randf()) * maxf(spawn_radius_m, inner_exclusion_m)
	radius = maxf(radius, inner_exclusion_m)
	var angle := rng.randf() * TAU
	return Vector2(_layout_center_local.x, _layout_center_local.z) + Vector2(cos(angle), sin(angle)) * radius


func _random_near_start_patch_center(rng: RandomNumberGenerator) -> Vector2:
	var min_radius := maxf(near_start_min_radius_m, 0.0)
	var max_radius := maxf(near_start_max_radius_m, min_radius)
	var radius := rng.randf_range(min_radius, max_radius)
	var angle := rng.randf() * TAU
	return Vector2(_layout_center_local.x, _layout_center_local.z) + Vector2(cos(angle), sin(angle)) * radius


func _has_minimum_spacing(candidate: Vector2, points: Array[Vector2]) -> bool:
	var min_spacing := maxf(plant_spacing_min_m, 0.1)
	for point in points:
		if candidate.distance_to(point) < min_spacing:
			return false
	return true


func _sample_valid_ground_y(local_x: float, local_z: float) -> float:
	if _terrain == null:
		return NAN

	var y := _sample_ground_y(local_x, local_z)
	if is_nan(y):
		return NAN

	var hxp := _sample_ground_y(local_x + slope_sample_m, local_z)
	var hxn := _sample_ground_y(local_x - slope_sample_m, local_z)
	var hzp := _sample_ground_y(local_x, local_z + slope_sample_m)
	var hzn := _sample_ground_y(local_x, local_z - slope_sample_m)
	if is_nan(hxp) or is_nan(hxn) or is_nan(hzp) or is_nan(hzn):
		return NAN

	var slope_x := absf(hxp - hxn) / maxf(slope_sample_m * 2.0, 0.001)
	var slope_z := absf(hzp - hzn) / maxf(slope_sample_m * 2.0, 0.001)
	var max_slope_tan := tan(deg_to_rad(max_slope_deg))
	if maxf(slope_x, slope_z) > max_slope_tan:
		return NAN

	return y


func _sample_ground_y(local_x: float, local_z: float) -> float:
	var local_pos := Vector3(local_x, 0.0, local_z)
	var world_pos := to_global(local_pos)
	var world_y := _terrain.get_height(world_pos)
	if is_nan(world_y):
		return NAN
	return to_local(Vector3(world_pos.x, world_y, world_pos.z)).y


func _update_streamed_plants() -> void:
	if not streaming_enabled:
		_clear_active_plants()
		return
	var focus := _get_stream_focus()
	if focus == null:
		return

	var focus_local := to_local(focus.global_position)
	var stream_radius_sq := stream_radius_m * stream_radius_m
	var despawn_radius_sq := despawn_radius_m * despawn_radius_m

	for id in _active.keys():
		var plant := _active[id] as Node3D
		var record := _record_for_id(int(id))
		if plant == null or record.is_empty():
			_active.erase(id)
			continue
		var pos := record["position"] as Vector3
		if _distance_xz_sq(pos, focus_local) > despawn_radius_sq:
			plant.queue_free()
			_active.erase(id)

	var visible_count := _active.size()
	if visible_count >= max_visible_plants:
		return

	for record in _records:
		var id := int(record["id"])
		if _active.has(id):
			continue
		var pos := record["position"] as Vector3
		if _distance_xz_sq(pos, focus_local) > stream_radius_sq:
			continue
		_spawn_record(record)
		visible_count += 1
		if visible_count >= max_visible_plants:
			return


func _clear_active_plants() -> void:
	for id in _active.keys():
		var plant := _active[id] as Node
		if plant != null and is_instance_valid(plant):
			plant.queue_free()
	_active.clear()


func _spawn_record(record: Dictionary) -> void:
	if plant_scene == null:
		return
	var plant := plant_scene.instantiate() as Node3D
	if plant == null:
		return

	var plant_scale := float(record["scale"])
	if plant is PlantObject:
		var plant_object := plant as PlantObject
		plant_object.visual_scale = Vector3.ONE * plant_scale
	else:
		plant.scale = Vector3.ONE * plant_scale

	plant.name = "Cactus_%03d_%03d" % [int(record["patch"]), int(record["id"])]
	plant.position = record["position"] as Vector3
	plant.rotation = Vector3(float(record["lean_x"]), float(record["yaw"]), float(record["lean_z"]))
	add_child(plant)
	_active[int(record["id"])] = plant


func _get_stream_focus() -> Node3D:
	var viewport := get_viewport()
	if viewport != null:
		var active_camera := viewport.get_camera_3d()
		if active_camera != null:
			return active_camera
	var aircraft := get_tree().get_first_node_in_group("aircraft") as Node3D
	if aircraft != null:
		return aircraft
	return get_tree().get_first_node_in_group("carrier") as Node3D


func _distance_xz_sq(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


func _record_for_id(id: int) -> Dictionary:
	for record in _records:
		if int(record["id"]) == id:
			return record
	return {}


func _load_layout() -> bool:
	if layout_save_path.is_empty() or not FileAccess.file_exists(layout_save_path):
		return false

	var file := FileAccess.open(layout_save_path, FileAccess.READ)
	if file == null:
		return false

	var data = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		return false
	if int(data.get("version", 0)) != LAYOUT_VERSION:
		return false
	if int(data.get("seed", seed)) != seed:
		return false
	if int(data.get("patch_count", patch_count)) != patch_count:
		return false
	if int(data.get("near_start_patch_count", near_start_patch_count)) != near_start_patch_count:
		return false
	var saved_center_data: Array = data.get("layout_center", [])
	if saved_center_data.size() < 3:
		return false
	var saved_center := Vector3(
		float(saved_center_data[0]),
		float(saved_center_data[1]),
		float(saved_center_data[2])
	)
	if saved_center.distance_to(_layout_center_local) > 1.0:
		return false

	var plants: Array = data.get("plants", [])
	if plants.is_empty():
		return false

	_records.clear()
	for item in plants:
		if not (item is Dictionary):
			continue
		var record := _record_from_saved_dictionary(item as Dictionary)
		if record.is_empty():
			continue
		_records.append(record)

	return not _records.is_empty()


func _record_from_saved_dictionary(item: Dictionary) -> Dictionary:
	var position_data: Array = item.get("position", [])
	if position_data.size() < 3:
		return {}

	var position := Vector3(
		float(position_data[0]),
		float(position_data[1]),
		float(position_data[2])
	)
	if resnap_loaded_positions_to_terrain:
		var ground_y := _sample_valid_ground_y(position.x, position.z)
		if not is_nan(ground_y):
			position.y = ground_y - ground_sink_m

	return {
		"id": int(item.get("id", _records.size())),
		"patch": int(item.get("patch", 0)),
		"position": position,
		"yaw": float(item.get("yaw", 0.0)),
		"lean_x": float(item.get("lean_x", 0.0)),
		"lean_z": float(item.get("lean_z", 0.0)),
		"scale": float(item.get("scale", 1.0)),
	}


func _save_layout() -> void:
	if layout_save_path.is_empty():
		return

	var dir_path := layout_save_path.get_base_dir()
	var absolute_dir := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(absolute_dir)

	var plants: Array[Dictionary] = []
	for record in _records:
		var pos := record["position"] as Vector3
		plants.append({
			"id": int(record["id"]),
			"patch": int(record["patch"]),
			"position": [pos.x, pos.y, pos.z],
			"yaw": float(record["yaw"]),
			"lean_x": float(record["lean_x"]),
			"lean_z": float(record["lean_z"]),
			"scale": float(record["scale"]),
		})

	var payload := {
		"version": LAYOUT_VERSION,
		"seed": seed,
		"patch_count": patch_count,
		"near_start_patch_count": near_start_patch_count,
		"layout_center": [_layout_center_local.x, _layout_center_local.y, _layout_center_local.z],
		"plants": plants,
	}

	var file := FileAccess.open(layout_save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "\t"))


func _refresh_layout_center() -> void:
	if not center_layout_on_nav_area:
		_layout_center_local = Vector3.ZERO
		return
	var bake_center := TerrainNavGrid.get_bake_center()
	_layout_center_local = to_local(Vector3(bake_center.x, global_position.y, bake_center.z))


func _rebuild_patch_center_cache() -> void:
	_patch_local_centers.clear()
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for record in _records:
		var patch_id := int(record["patch"])
		var pos := record["position"] as Vector3
		sums[patch_id] = (sums.get(patch_id, Vector3.ZERO) as Vector3) + pos
		counts[patch_id] = int(counts.get(patch_id, 0)) + 1

	var patch_ids: Array = counts.keys()
	patch_ids.sort()
	for patch_id in patch_ids:
		var count := int(counts[patch_id])
		if count <= 0:
			continue
		_patch_local_centers.append({
			"patch": int(patch_id),
			"count": count,
			"position": (sums[patch_id] as Vector3) / float(count),
		})
