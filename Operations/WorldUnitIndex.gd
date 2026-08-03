extends Node

## Shared spatial directory for materialized combat units and abstract formations.
##
## The index does not own units or decide their missions. It provides cheap
## nearby-unit queries, remembers reported observations, and exposes the current
## virtual/materialized state of flights and platoons. Existing systems remain
## authoritative and can fall back to SceneTree group scans when this is disabled.

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")
const GROUP_BITS: Dictionary = {
	"aircraft": 1 << 0,
	"ai_aircraft": 1 << 1,
	"ground_vehicles": 1 << 2,
	"carrier": 1 << 3,
	"enemies": 1 << 4,
	"friendlies": 1 << 5,
}

@export var enabled: bool = true
@export var spatial_queries_enabled: bool = true
@export var formation_tracking_enabled: bool = true
@export var formation_relevance_enabled: bool = true
@export var observation_cache_enabled: bool = true
@export var engagement_tracking_enabled: bool = true
@export var cell_size_m: float = 100.0
@export var coarse_cell_size_m: float = 800.0
@export var fine_query_max_radius_m: float = 300.0
@export var position_refresh_interval_s: float = 0.10
@export var fallback_group_rescan_interval_s: float = 5.0
@export var observation_prune_interval_s: float = 1.0

var _units: Dictionary = {} # instance id -> Node3D
var _unit_group_masks: Dictionary = {} # instance id -> known group bit mask
var _unit_cells: Dictionary = {} # instance id -> Vector2i
var _cells: Dictionary = {} # Vector2i -> Dictionary(instance id -> true)
var _unit_coarse_cells: Dictionary = {} # instance id -> Vector2i
var _coarse_cells: Dictionary = {} # Vector2i -> Dictionary(instance id -> true)
var _formations: Dictionary = {} # instance id -> record Dictionary
var _observations: Dictionary = {} # "observer_id:target_id" -> record Dictionary
var _engagements_by_controller: Dictionary = {} # controller id -> weak controller/target record
var _engagement_controller_ids_by_target: Dictionary = {} # target id -> Dictionary(controller id -> true)

var _position_refresh_timer_s: float = 0.0
var _group_rescan_timer_s: float = 0.0
var _observation_prune_timer_s: float = 0.0

var _query_count: int = 0
var _candidate_count: int = 0
var _returned_count: int = 0
var _full_group_rescan_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	var tree := get_tree()
	if tree != null:
		tree.node_added.connect(_on_tree_node_added)
		tree.node_removed.connect(_on_tree_node_removed)
	call_deferred("_rescan_indexable_groups")


func _process(delta: float) -> void:
	if not enabled:
		return
	var profiler_start: int = FrameProfiler.begin("WorldUnitIndex.process")
	_position_refresh_timer_s -= maxf(delta, 0.0)
	_group_rescan_timer_s -= maxf(delta, 0.0)
	_observation_prune_timer_s -= maxf(delta, 0.0)

	if _position_refresh_timer_s <= 0.0:
		_position_refresh_timer_s = maxf(position_refresh_interval_s, 0.02)
		_refresh_unit_positions()
		_refresh_formation_records()
	if _group_rescan_timer_s <= 0.0:
		_group_rescan_timer_s = maxf(fallback_group_rescan_interval_s, 0.2)
		_rescan_indexable_groups()
	if _observation_prune_timer_s <= 0.0:
		_observation_prune_timer_s = maxf(observation_prune_interval_s, 0.2)
		_prune_observations()
		_prune_engagements()
	FrameProfiler.end("WorldUnitIndex.process", profiler_start)


func register_unit(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var unit_id: int = unit.get_instance_id()
	_units[unit_id] = unit
	_unit_group_masks[unit_id] = _group_mask_for_node(unit)
	_move_unit_to_cell(unit_id, _cell_for_position(unit.global_position))
	_move_unit_to_coarse_cell(unit_id, _coarse_cell_for_position(unit.global_position))


func unregister_unit(unit: Node) -> void:
	if unit == null:
		return
	_unregister_unit_id(unit.get_instance_id())


func query_nodes_in_groups(
	center: Vector3,
	radius_m: float,
	group_names: Array,
	excluded_groups: Array = [],
	excluded_nodes: Array = []
) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not enabled or not spatial_queries_enabled or radius_m < 0.0:
		return result
	_query_count += 1
	var use_coarse_grid: bool = radius_m > maxf(fine_query_max_radius_m, 0.0)
	var query_cell_size: float = maxf(coarse_cell_size_m if use_coarse_grid else cell_size_m, 10.0)
	var query_cells: Dictionary = _coarse_cells if use_coarse_grid else _cells
	var min_cell_x: int = floori((center.x - radius_m) / query_cell_size)
	var max_cell_x: int = floori((center.x + radius_m) / query_cell_size)
	var min_cell_y: int = floori((center.z - radius_m) / query_cell_size)
	var max_cell_y: int = floori((center.z + radius_m) / query_cell_size)
	var radius_sq: float = radius_m * radius_m
	var required_mask: int = _group_mask_for_names(group_names)
	var excluded_mask: int = _group_mask_for_names(excluded_groups)
	var required_groups_known: bool = _all_group_names_known(group_names)
	var excluded_groups_known: bool = _all_group_names_known(excluded_groups)
	var excluded_ids: Dictionary = {}
	for excluded in excluded_nodes:
		if typeof(excluded) != TYPE_OBJECT or not is_instance_valid(excluded):
			continue
		excluded_ids[(excluded as Object).get_instance_id()] = true

	for cell_x in range(min_cell_x, max_cell_x + 1):
		for cell_y in range(min_cell_y, max_cell_y + 1):
			var cell_key := Vector2i(cell_x, cell_y)
			var bucket_value: Variant = query_cells.get(cell_key, null)
			if not (bucket_value is Dictionary):
				continue
			var bucket: Dictionary = bucket_value
			for unit_id_value in bucket.keys():
				var unit_id: int = int(unit_id_value)
				_candidate_count += 1
				if excluded_ids.has(unit_id):
					continue
				var unit_value: Variant = _units.get(unit_id, null)
				if typeof(unit_value) != TYPE_OBJECT or not is_instance_valid(unit_value):
					continue
				var unit := unit_value as Node3D
				if unit == null or not unit.is_inside_tree():
					continue
				var unit_group_mask: int = int(_unit_group_masks.get(unit_id, 0))
				if not group_names.is_empty():
					if required_groups_known:
						if (unit_group_mask & required_mask) == 0:
							continue
					elif not _node_matches_any_group(unit, group_names):
						continue
				if not excluded_groups.is_empty():
					if excluded_groups_known:
						if (unit_group_mask & excluded_mask) != 0:
							continue
					elif _node_matches_any_group(unit, excluded_groups):
						continue
				if center.distance_squared_to(unit.global_position) > radius_sq:
					continue
				result.append(unit)
	_returned_count += result.size()
	return result


func nearest_node_in_groups(
	center: Vector3,
	max_radius_m: float,
	group_names: Array,
	excluded_groups: Array = [],
	excluded_nodes: Array = []
) -> Node3D:
	var best: Node3D = null
	var best_sq: float = max_radius_m * max_radius_m
	for candidate in query_nodes_in_groups(center, max_radius_m, group_names, excluded_groups, excluded_nodes):
		var distance_sq: float = center.distance_squared_to(candidate.global_position)
		if distance_sq <= best_sq:
			best_sq = distance_sq
			best = candidate
	return best


func nearest_friendly_distance(center: Vector3, max_radius_m: float) -> float:
	var nearest := nearest_node_in_groups(
		center,
		max_radius_m,
		["carrier", "aircraft", "ai_aircraft", "friendlies", "ground_vehicles"],
		["enemies"]
	)
	if nearest == null:
		return INF
	return center.distance_to(nearest.global_position)


func report_target_engagement(controller: Node, target: Node3D) -> void:
	## Cheap shared target-allocation picture. Controllers report only when their
	## selected target changes, so selection can avoid dogpiling without scanning
	## every turret in the scene.
	if not enabled or not engagement_tracking_enabled \
			or controller == null or not is_instance_valid(controller):
		return
	var controller_id := controller.get_instance_id()
	_clear_target_engagement_id(controller_id)
	if target == null or not is_instance_valid(target):
		return
	var target_id := target.get_instance_id()
	_engagements_by_controller[controller_id] = {
		"controller_ref": weakref(controller),
		"target_ref": weakref(target),
		"target_id": target_id,
	}
	var bucket_variant: Variant = _engagement_controller_ids_by_target.get(target_id, {})
	var bucket: Dictionary = bucket_variant if bucket_variant is Dictionary else {}
	bucket[controller_id] = true
	_engagement_controller_ids_by_target[target_id] = bucket


func clear_target_engagement(controller: Node) -> void:
	if controller == null:
		return
	_clear_target_engagement_id(controller.get_instance_id())


func get_target_engagement_count(target: Node, excluded_controller: Node = null) -> int:
	if not enabled or not engagement_tracking_enabled \
			or target == null or not is_instance_valid(target):
		return 0
	var target_id := target.get_instance_id()
	_prune_target_engagement_bucket(target_id)
	var bucket_variant: Variant = _engagement_controller_ids_by_target.get(target_id, {})
	if not (bucket_variant is Dictionary):
		return 0
	var count := (bucket_variant as Dictionary).size()
	if excluded_controller != null and is_instance_valid(excluded_controller) \
			and (bucket_variant as Dictionary).has(excluded_controller.get_instance_id()):
		count -= 1
	return maxi(count, 0)


func should_materialize_formation(center: Vector3, activate_range_m: float, deactivate_range_m: float) -> bool:
	if not enabled or not formation_relevance_enabled:
		return false
	var player_node := _get_player_relevance_node()
	var player_distance: float = INF
	if player_node != null and is_instance_valid(player_node):
		player_distance = center.distance_to(player_node.global_position)
	else:
		player_distance = nearest_friendly_distance(center, deactivate_range_m)
	if player_distance <= activate_range_m:
		return true
	return player_distance <= deactivate_range_m \
		and nearest_friendly_distance(center, activate_range_m) <= activate_range_m


func should_dematerialize_formation(center: Vector3, deactivate_range_m: float) -> bool:
	if not enabled or not formation_relevance_enabled:
		return false
	var player_node := _get_player_relevance_node()
	if player_node != null and is_instance_valid(player_node):
		return center.distance_to(player_node.global_position) > deactivate_range_m
	return nearest_friendly_distance(center, deactivate_range_m) > deactivate_range_m


func register_formation(formation: Node, kind: String, display_name: String) -> void:
	if not formation_tracking_enabled or formation == null or not is_instance_valid(formation):
		return
	var formation_id: int = formation.get_instance_id()
	_formations[formation_id] = {
		"node": formation,
		"kind": kind,
		"name": display_name,
		"position": Vector3.ZERO,
		"count": 0,
		"state": -1,
		"active_member_ids": PackedInt64Array(),
	}
	_refresh_formation_record(formation_id)


func unregister_formation(formation: Node) -> void:
	if formation == null:
		return
	_formations.erase(formation.get_instance_id())


func get_formation_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record_value in _formations.values():
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var copy := record.duplicate(true)
		copy.erase("node")
		result.append(copy)
	return result


func report_observation(observer: Node, target: Node3D, visible: bool, ttl_s: float = 1.0) -> void:
	if not observation_cache_enabled or observer == null or target == null:
		return
	if not is_instance_valid(observer) or not is_instance_valid(target):
		return
	var observer_id: int = observer.get_instance_id()
	var target_id: int = target.get_instance_id()
	_observations[_observation_key(observer_id, target_id)] = {
		"observer_id": observer_id,
		"target_id": target_id,
		"visible": visible,
		"target_position": target.global_position,
		"expires_at_ms": Time.get_ticks_msec() + int(maxf(ttl_s, 0.05) * 1000.0),
	}


func get_cached_observation(observer: Node, target: Node) -> Dictionary:
	if not observation_cache_enabled or observer == null or target == null:
		return {}
	if not is_instance_valid(observer) or not is_instance_valid(target):
		return {}
	var key := _observation_key(observer.get_instance_id(), target.get_instance_id())
	var record_value: Variant = _observations.get(key, null)
	if not (record_value is Dictionary):
		return {}
	var record: Dictionary = record_value
	if int(record.get("expires_at_ms", 0)) < Time.get_ticks_msec():
		_observations.erase(key)
		return {}
	return record.duplicate(true)


func get_report_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"units": _units.size(),
		"cells": _cells.size(),
		"coarse_cells": _coarse_cells.size(),
		"formations": _formations.size(),
		"observations": _observations.size(),
		"engagements": _engagements_by_controller.size(),
		"queries": _query_count,
		"candidates": _candidate_count,
		"returned": _returned_count,
		"group_rescans": _full_group_rescan_count,
	}


func _on_tree_node_added(node: Node) -> void:
	# A node may be queued and freed again before this deferred callback runs.
	# Passing the typed Node directly makes argument conversion touch that freed
	# Object before _consider_node() can validate it. WeakRef keeps the callback safe.
	call_deferred("_consider_node_ref", weakref(node))


func _consider_node_ref(node_ref: WeakRef) -> void:
	if node_ref == null:
		return
	var node_value: Variant = node_ref.get_ref()
	if not (node_value is Node) or not is_instance_valid(node_value):
		return
	_consider_node(node_value as Node)


func _on_tree_node_removed(node: Node) -> void:
	if node == null:
		return
	var node_id: int = node.get_instance_id()
	_unregister_unit_id(node_id)
	_formations.erase(node_id)


func _consider_node(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is Node3D and _is_indexable_unit(node):
		register_unit(node as Node3D)


func _is_indexable_unit(node: Node) -> bool:
	return node.is_in_group("aircraft") \
		or node.is_in_group("ai_aircraft") \
		or node.is_in_group("ground_vehicles") \
		or node.is_in_group("carrier") \
		or node.is_in_group("enemies") \
		or node.is_in_group("friendlies")


func _rescan_indexable_groups() -> void:
	if not enabled:
		return
	var tree := get_tree()
	if tree == null:
		return
	_full_group_rescan_count += 1
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "ground_vehicles", "carrier", "enemies", "friendlies"]:
		for node_value in tree.get_nodes_in_group(group_name):
			if not (node_value is Node3D) or not is_instance_valid(node_value):
				continue
			var unit := node_value as Node3D
			var unit_id: int = unit.get_instance_id()
			if seen.has(unit_id):
				continue
			seen[unit_id] = true
			register_unit(unit)


func _refresh_unit_positions() -> void:
	var stale_ids: Array[int] = []
	for unit_id_value in _units.keys():
		var unit_id: int = int(unit_id_value)
		var unit_value: Variant = _units.get(unit_id, null)
		if typeof(unit_value) != TYPE_OBJECT or not is_instance_valid(unit_value):
			stale_ids.append(unit_id)
			continue
		var unit := unit_value as Node3D
		if unit == null or not unit.is_inside_tree():
			stale_ids.append(unit_id)
			continue
		_move_unit_to_cell(unit_id, _cell_for_position(unit.global_position))
		_move_unit_to_coarse_cell(unit_id, _coarse_cell_for_position(unit.global_position))
	for unit_id in stale_ids:
		_unregister_unit_id(unit_id)


func _move_unit_to_cell(unit_id: int, new_cell: Vector2i) -> void:
	var old_cell_value: Variant = _unit_cells.get(unit_id, null)
	if old_cell_value is Vector2i and old_cell_value == new_cell:
		return
	if old_cell_value is Vector2i:
		_remove_unit_from_cell(unit_id, old_cell_value)
	var bucket_value: Variant = _cells.get(new_cell, null)
	var bucket: Dictionary = bucket_value if bucket_value is Dictionary else {}
	bucket[unit_id] = true
	_cells[new_cell] = bucket
	_unit_cells[unit_id] = new_cell


func _remove_unit_from_cell(unit_id: int, cell: Vector2i) -> void:
	var bucket_value: Variant = _cells.get(cell, null)
	if not (bucket_value is Dictionary):
		return
	var bucket: Dictionary = bucket_value
	bucket.erase(unit_id)
	if bucket.is_empty():
		_cells.erase(cell)
	else:
		_cells[cell] = bucket


func _move_unit_to_coarse_cell(unit_id: int, new_cell: Vector2i) -> void:
	var old_cell_value: Variant = _unit_coarse_cells.get(unit_id, null)
	if old_cell_value is Vector2i and old_cell_value == new_cell:
		return
	if old_cell_value is Vector2i:
		_remove_unit_from_coarse_cell(unit_id, old_cell_value)
	var bucket_value: Variant = _coarse_cells.get(new_cell, null)
	var bucket: Dictionary = bucket_value if bucket_value is Dictionary else {}
	bucket[unit_id] = true
	_coarse_cells[new_cell] = bucket
	_unit_coarse_cells[unit_id] = new_cell


func _remove_unit_from_coarse_cell(unit_id: int, cell: Vector2i) -> void:
	var bucket_value: Variant = _coarse_cells.get(cell, null)
	if not (bucket_value is Dictionary):
		return
	var bucket: Dictionary = bucket_value
	bucket.erase(unit_id)
	if bucket.is_empty():
		_coarse_cells.erase(cell)
	else:
		_coarse_cells[cell] = bucket


func _unregister_unit_id(unit_id: int) -> void:
	var old_cell_value: Variant = _unit_cells.get(unit_id, null)
	if old_cell_value is Vector2i:
		_remove_unit_from_cell(unit_id, old_cell_value)
	var old_coarse_cell_value: Variant = _unit_coarse_cells.get(unit_id, null)
	if old_coarse_cell_value is Vector2i:
		_remove_unit_from_coarse_cell(unit_id, old_coarse_cell_value)
	_unit_cells.erase(unit_id)
	_unit_coarse_cells.erase(unit_id)
	_unit_group_masks.erase(unit_id)
	_units.erase(unit_id)


func _cell_for_position(world_position: Vector3) -> Vector2i:
	var safe_cell_size: float = maxf(cell_size_m, 10.0)
	return Vector2i(floori(world_position.x / safe_cell_size), floori(world_position.z / safe_cell_size))


func _coarse_cell_for_position(world_position: Vector3) -> Vector2i:
	var safe_cell_size: float = maxf(coarse_cell_size_m, maxf(cell_size_m, 10.0))
	return Vector2i(floori(world_position.x / safe_cell_size), floori(world_position.z / safe_cell_size))


func _node_matches_any_group(node: Node, group_names: Array) -> bool:
	for group_value in group_names:
		if node.is_in_group(StringName(str(group_value))):
			return true
	return false


func _group_mask_for_node(node: Node) -> int:
	var mask: int = 0
	for group_name_value in GROUP_BITS.keys():
		var group_name: String = String(group_name_value)
		if node.is_in_group(StringName(group_name)):
			mask |= int(GROUP_BITS[group_name])
	return mask


func _group_mask_for_names(group_names: Array) -> int:
	var mask: int = 0
	for group_value in group_names:
		var group_name: String = str(group_value)
		if GROUP_BITS.has(group_name):
			mask |= int(GROUP_BITS[group_name])
	return mask


func _all_group_names_known(group_names: Array) -> bool:
	for group_value in group_names:
		if not GROUP_BITS.has(str(group_value)):
			return false
	return true


func _refresh_formation_records() -> void:
	if not formation_tracking_enabled:
		return
	var stale_ids: Array[int] = []
	for formation_id_value in _formations.keys():
		var formation_id: int = int(formation_id_value)
		var record_value: Variant = _formations.get(formation_id, null)
		if not (record_value is Dictionary):
			stale_ids.append(formation_id)
			continue
		var formation_value: Variant = (record_value as Dictionary).get("node", null)
		if typeof(formation_value) != TYPE_OBJECT or not is_instance_valid(formation_value):
			stale_ids.append(formation_id)
			continue
		var formation := formation_value as Node
		if formation == null or not formation.is_inside_tree():
			stale_ids.append(formation_id)
			continue
		_refresh_formation_record(formation_id)
	for formation_id in stale_ids:
		_formations.erase(formation_id)


func _refresh_formation_record(formation_id: int) -> void:
	var record_value: Variant = _formations.get(formation_id, null)
	if not (record_value is Dictionary):
		return
	var record: Dictionary = record_value
	var formation_value: Variant = record.get("node", null)
	if typeof(formation_value) != TYPE_OBJECT or not is_instance_valid(formation_value):
		return
	var formation := formation_value as Node
	if formation == null:
		return
	var position_value: Variant = formation.get("position")
	if position_value is Vector3:
		record["position"] = position_value
	var kind: String = String(record.get("kind", ""))
	if kind == "flight":
		record["count"] = int(formation.get("aircraft_count"))
		record["state"] = int(formation.get("vstate"))
		record["active_member_ids"] = _member_ids(formation.get("active_aircraft"))
	elif kind == "platoon":
		record["count"] = int(formation.get("vehicle_count"))
		record["state"] = int(formation.get("vstate"))
		record["active_member_ids"] = _member_ids(formation.get("_active_vehicles"))
	_formations[formation_id] = record


func _member_ids(members_value: Variant) -> PackedInt64Array:
	var ids := PackedInt64Array()
	if not (members_value is Array):
		return ids
	for member in members_value:
		if typeof(member) != TYPE_OBJECT or not is_instance_valid(member):
			continue
		ids.append((member as Object).get_instance_id())
	return ids


func _observation_key(observer_id: int, target_id: int) -> String:
	return "%d:%d" % [observer_id, target_id]


func _prune_observations() -> void:
	if _observations.is_empty():
		return
	var now_ms: int = Time.get_ticks_msec()
	var stale_keys: Array = []
	for key in _observations.keys():
		var record_value: Variant = _observations.get(key, null)
		if not (record_value is Dictionary) or int((record_value as Dictionary).get("expires_at_ms", 0)) < now_ms:
			stale_keys.append(key)
	for key in stale_keys:
		_observations.erase(key)


func _clear_target_engagement_id(controller_id: int) -> void:
	var record_variant: Variant = _engagements_by_controller.get(controller_id, {})
	_engagements_by_controller.erase(controller_id)
	if not (record_variant is Dictionary):
		return
	var target_id := int((record_variant as Dictionary).get("target_id", 0))
	if target_id == 0:
		return
	var bucket_variant: Variant = _engagement_controller_ids_by_target.get(target_id, {})
	if not (bucket_variant is Dictionary):
		return
	var bucket := bucket_variant as Dictionary
	bucket.erase(controller_id)
	if bucket.is_empty():
		_engagement_controller_ids_by_target.erase(target_id)
	else:
		_engagement_controller_ids_by_target[target_id] = bucket


func _prune_target_engagement_bucket(target_id: int) -> void:
	var bucket_variant: Variant = _engagement_controller_ids_by_target.get(target_id, {})
	if not (bucket_variant is Dictionary):
		return
	var stale_controller_ids: Array[int] = []
	for controller_id_variant in (bucket_variant as Dictionary).keys():
		var controller_id := int(controller_id_variant)
		var record_variant: Variant = _engagements_by_controller.get(controller_id, {})
		if not (record_variant is Dictionary):
			stale_controller_ids.append(controller_id)
			continue
		var record := record_variant as Dictionary
		var controller_ref: WeakRef = record.get("controller_ref", null)
		var target_ref: WeakRef = record.get("target_ref", null)
		var controller_variant: Variant = controller_ref.get_ref() if controller_ref != null else null
		var target_variant: Variant = target_ref.get_ref() if target_ref != null else null
		if not is_instance_valid(controller_variant) or not is_instance_valid(target_variant) \
				or int(record.get("target_id", 0)) != target_id:
			stale_controller_ids.append(controller_id)
	for controller_id in stale_controller_ids:
		_clear_target_engagement_id(controller_id)


func _prune_engagements() -> void:
	if _engagements_by_controller.is_empty():
		return
	var target_ids: Array[int] = []
	for target_id_variant in _engagement_controller_ids_by_target.keys():
		target_ids.append(int(target_id_variant))
	for target_id in target_ids:
		_prune_target_engagement_bucket(target_id)


func _get_player_relevance_node() -> Node3D:
	var viewport := get_viewport()
	if viewport != null:
		var camera: Camera3D = viewport.get_camera_3d()
		if camera != null and is_instance_valid(camera):
			var node: Node = camera
			while node != null:
				if node is Node3D and _is_player_relevance_root(node):
					return node as Node3D
				node = node.get_parent()
			return camera
	var flight_director: Node = get_node_or_null("/root/FlightDirector")
	if flight_director != null:
		var controlled_value: Variant = flight_director.get("player_controlled_plane")
		if controlled_value is Node3D and is_instance_valid(controlled_value):
			return controlled_value as Node3D
		var viewed_value: Variant = flight_director.get("current_viewed_aircraft")
		if viewed_value is Node3D and is_instance_valid(viewed_value):
			return viewed_value as Node3D
	return null


func _is_player_relevance_root(node: Node) -> bool:
	return node.is_in_group("aircraft") \
		or node.is_in_group("ai_aircraft") \
		or node.is_in_group("ground_vehicles") \
		or node.is_in_group("carrier") \
		or node.is_in_group("friendlies")
