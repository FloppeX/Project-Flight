extends Node
## Permanent strategic-map exploration state.
##
## The exploration grid is aligned one-to-one with TerrainNavGrid. Friendly
## vehicles reveal cells as they move; revealed cells never become unknown
## again during the current play-area bake.

signal exploration_changed

@export_group("Reveal Radii")
@export var aircraft_reveal_radius_m: float = 3000.0
@export var helicopter_reveal_radius_m: float = 2000.0
@export var ground_vehicle_reveal_radius_m: float = 800.0
@export var carrier_reveal_radius_m: float = 3000.0

@export_group("Updates")
@export_range(0.05, 2.0, 0.05) var observer_update_interval_s: float = 0.25
@export_range(0.01, 0.5, 0.01) var observer_reveal_step_fraction: float = 0.08

var _explored: PackedByteArray = PackedByteArray()
var _mask_image: Image = null
var _mask_texture: ImageTexture = null
var _cols: int = 0
var _rows: int = 0
var _origin_x: float = 0.0
var _origin_z: float = 0.0
var _cell_size_m: float = 1.0
var _observer_elapsed_s: float = 0.0
var _observer_last_cells: Dictionary = {}
var _texture_dirty: bool = false
var _initialized: bool = false
var _placement_carrier: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("origin_shifter")
	if not TerrainNavGrid.bake_complete.is_connected(_on_navgrid_bake_complete):
		TerrainNavGrid.bake_complete.connect(_on_navgrid_bake_complete)
	if TerrainNavGrid.is_ready():
		_initialize_from_navgrid()


func _process(delta: float) -> void:
	if not TerrainNavGrid.is_ready():
		if _initialized:
			_clear_state()
		return
	if not _initialized or not _geometry_matches_navgrid():
		_initialize_from_navgrid()
		return
	# The carrier is authored at a temporary scene position, then relocated once
	# the terrain grid is ready. Since exploration is permanent, revealing even a
	# single frame at that temporary position leaves an unexplained clear patch.
	if not _is_initial_placement_ready():
		return
	_observer_elapsed_s -= maxf(delta, 0.0)
	if _observer_elapsed_s > 0.0:
		return
	_observer_elapsed_s = maxf(observer_update_interval_s, 0.05)
	_reveal_friendly_observers()


func _on_navgrid_bake_complete() -> void:
	_initialize_from_navgrid()


func apply_origin_shift(offset: Vector3) -> void:
	_origin_x -= offset.x
	_origin_z -= offset.z


func _initialize_from_navgrid() -> void:
	_cols = TerrainNavGrid._cols
	_rows = TerrainNavGrid._rows
	_origin_x = TerrainNavGrid._origin_x
	_origin_z = TerrainNavGrid._origin_z
	_cell_size_m = maxf(TerrainNavGrid.cell_size_m, 1.0)
	_initialized = _cols > 1 and _rows > 1
	_observer_elapsed_s = 0.0
	_observer_last_cells.clear()
	_explored = PackedByteArray()
	_mask_image = null
	_mask_texture = null
	_texture_dirty = false
	if not _initialized:
		exploration_changed.emit()
		return
	_explored.resize(_cols * _rows)
	_explored.fill(0)
	_mask_image = Image.create(_cols, _rows, false, Image.FORMAT_L8)
	_mask_image.fill(Color.BLACK)
	_mask_texture = ImageTexture.create_from_image(_mask_image)
	if _is_initial_placement_ready():
		_reveal_friendly_observers()
	exploration_changed.emit()


func _clear_state() -> void:
	_initialized = false
	_cols = 0
	_rows = 0
	_origin_x = 0.0
	_origin_z = 0.0
	_cell_size_m = 1.0
	_observer_elapsed_s = 0.0
	_observer_last_cells.clear()
	_explored = PackedByteArray()
	_mask_image = null
	_mask_texture = null
	_texture_dirty = false
	exploration_changed.emit()


func _geometry_matches_navgrid() -> bool:
	return (
		_initialized
		and _cols == TerrainNavGrid._cols
		and _rows == TerrainNavGrid._rows
		and is_equal_approx(_cell_size_m, maxf(TerrainNavGrid.cell_size_m, 1.0))
		and is_equal_approx(_origin_x, TerrainNavGrid._origin_x)
		and is_equal_approx(_origin_z, TerrainNavGrid._origin_z)
	)


func is_initialized() -> bool:
	return _initialized and TerrainNavGrid.is_ready() and _geometry_matches_navgrid()


func capture_save_state() -> Dictionary:
	if not is_initialized():
		return {}
	return {
		"cols": _cols,
		"rows": _rows,
		"origin_x": _origin_x,
		"origin_z": _origin_z,
		"cell_size_m": _cell_size_m,
		"explored": _explored,
	}


func restore_save_state(state: Dictionary) -> bool:
	if state.is_empty() or not TerrainNavGrid.is_ready():
		return false
	if not _initialized or not _geometry_matches_navgrid():
		_initialize_from_navgrid()
	if int(state.get("cols", -1)) != _cols or int(state.get("rows", -1)) != _rows:
		push_warning("[MapFogOfWar] Save geometry does not match the current map")
		return false
	if not is_equal_approx(float(state.get("cell_size_m", -1.0)), _cell_size_m):
		push_warning("[MapFogOfWar] Save cell size does not match the current map")
		return false
	if not is_equal_approx(float(state.get("origin_x", INF)), _origin_x) \
	or not is_equal_approx(float(state.get("origin_z", INF)), _origin_z):
		push_warning("[MapFogOfWar] Save origin does not match the current map")
		return false
	var explored_variant: Variant = state.get("explored", PackedByteArray())
	if not (explored_variant is PackedByteArray):
		return false
	var restored := explored_variant as PackedByteArray
	if restored.size() != _cols * _rows:
		return false
	_explored = restored.duplicate()
	_mask_image = Image.create(_cols, _rows, false, Image.FORMAT_L8)
	for row in range(_rows):
		for col in range(_cols):
			var value := float(_explored[row * _cols + col]) / 255.0
			_mask_image.set_pixel(col, row, Color(value, value, value, 1.0))
	_mask_texture = ImageTexture.create_from_image(_mask_image)
	_observer_last_cells.clear()
	_texture_dirty = false
	exploration_changed.emit()
	return true


func is_world_explored(world_pos: Vector3) -> bool:
	if not is_initialized():
		return false
	var cell := _world_to_cell(world_pos)
	if not _is_cell_in_bounds(cell):
		return false
	return _explored[cell.y * _cols + cell.x] != 0


func get_mask_texture() -> Texture2D:
	if not is_initialized():
		return null
	_upload_texture_if_dirty()
	return _mask_texture


func reveal_circle(world_pos: Vector3, radius_m: float) -> bool:
	if not _initialized:
		return false
	var center := _world_to_cell(world_pos)
	if not _is_cell_in_bounds(center):
		return false
	var cell_size: float = _cell_size_m
	var radius_cells: int = maxi(int(ceil(maxf(radius_m, 0.0) / cell_size)), 0)
	var radius_sq: float = pow(maxf(radius_m, 0.0) + cell_size * 0.5, 2.0)
	var changed := false
	for dz in range(-radius_cells, radius_cells + 1):
		var gz: int = center.y + dz
		if gz < 0 or gz >= _rows:
			continue
		for dx in range(-radius_cells, radius_cells + 1):
			var gx: int = center.x + dx
			if gx < 0 or gx >= _cols:
				continue
			var offset_x: float = float(dx) * cell_size
			var offset_z: float = float(dz) * cell_size
			if offset_x * offset_x + offset_z * offset_z > radius_sq:
				continue
			var idx: int = gz * _cols + gx
			if _explored[idx] != 0:
				continue
			_explored[idx] = 255
			_mask_image.set_pixel(gx, gz, Color.WHITE)
			changed = true
	if changed:
		_texture_dirty = true
		exploration_changed.emit()
	return changed


func _reveal_friendly_observers() -> void:
	if not _initialized:
		return
	var seen_ids: Dictionary = {}
	# Use the same friendly-aircraft population that the strategic map draws. The
	# broader aircraft group can briefly include hangar/retrieval bodies whose
	# transforms are not yet valid operational positions.
	for node_variant in get_tree().get_nodes_in_group("friendlies"):
		if not (node_variant is Node3D) or not is_instance_valid(node_variant):
			continue
		var aircraft := node_variant as Node3D
		var is_aircraft: bool = aircraft.is_in_group("aircraft") or aircraft.is_in_group("ai_aircraft")
		if not is_aircraft or not _is_friendly(aircraft) \
		or not _is_operational_aircraft_observer(aircraft):
			continue
		var radius: float = helicopter_reveal_radius_m if _is_helicopter(aircraft) else aircraft_reveal_radius_m
		_reveal_observer(aircraft, radius, seen_ids)
	for node_variant in get_tree().get_nodes_in_group("ground_vehicles"):
		if not (node_variant is Node3D) or not is_instance_valid(node_variant):
			continue
		var vehicle := node_variant as Node3D
		if _is_friendly(vehicle):
			_reveal_observer(vehicle, ground_vehicle_reveal_radius_m, seen_ids)
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier != null and is_instance_valid(carrier):
		_reveal_observer(carrier, carrier_reveal_radius_m, seen_ids)
	for id_variant in _observer_last_cells.keys():
		if not seen_ids.has(id_variant):
			_observer_last_cells.erase(id_variant)


func _is_initial_placement_ready() -> bool:
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier == null or not is_instance_valid(carrier):
		_placement_carrier = null
		return false
	if carrier != _placement_carrier:
		_placement_carrier = carrier
		if carrier.has_signal("initial_placement_completed"):
			var completed_callable := Callable(self, "_on_carrier_initial_placement_completed")
			if not carrier.is_connected("initial_placement_completed", completed_callable):
				carrier.connect("initial_placement_completed", completed_callable)
	if carrier.has_method("is_initial_placement_complete"):
		return bool(carrier.call("is_initial_placement_complete"))
	# Compatibility for test/custom carriers that do not use asynchronous startup
	# placement. The production LandCarrier always provides the method above.
	return true


func _on_carrier_initial_placement_completed() -> void:
	# Rebuild from fully unknown even if another startup observer briefly existed.
	# Placement completes before play begins, so no legitimate exploration is lost.
	if TerrainNavGrid.is_ready():
		_initialize_from_navgrid()


func _is_operational_aircraft_observer(aircraft: Node3D) -> bool:
	# Hangar/retrieval bodies join the friendly population before they are actually
	# launched. They must neither scout from the deck nor preserve a bad transient
	# transform as permanent exploration.
	for meta_name in [
		"carrier_transport_mode",
		"carrier_manual_transport",
		"physics_ready_for_launch",
		"controls_disabled",
		"parking_brake",
	]:
		if bool(aircraft.get_meta(meta_name, false)):
			return false
	if aircraft is RigidBody3D and (aircraft as RigidBody3D).freeze:
		return false
	return true


func _reveal_observer(observer: Node3D, radius_m: float, seen_ids: Dictionary) -> void:
	var id: int = observer.get_instance_id()
	seen_ids[id] = true
	var cell := _world_to_cell(observer.global_position)
	if not _is_cell_in_bounds(cell):
		_observer_last_cells.erase(id)
		return
	if _observer_last_cells.has(id):
		var previous: Vector2i = _observer_last_cells[id]
		var cell_size: float = _cell_size_m
		var min_step_cells: int = maxi(
			int(floor(maxf(radius_m, cell_size) * observer_reveal_step_fraction / cell_size)),
			1
		)
		if maxi(absi(cell.x - previous.x), absi(cell.y - previous.y)) < min_step_cells:
			return
	_observer_last_cells[id] = cell
	reveal_circle(observer.global_position, radius_m)


func _world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor((world_pos.x - _origin_x) / _cell_size_m)),
		int(floor((world_pos.z - _origin_z) / _cell_size_m))
	)


func _is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _cols and cell.y >= 0 and cell.y < _rows


func _is_friendly(node: Node3D) -> bool:
	if node.has_method("get_team"):
		return int(node.call("get_team")) == 1
	var team_variant = node.get("team")
	return team_variant != null and int(team_variant) == 1


func _is_helicopter(aircraft: Node3D) -> bool:
	if bool(aircraft.get_meta("is_helicopter", false)):
		return true
	return str(aircraft.get_meta("aircraft_role", "")).to_lower().contains("helicopter")


func _upload_texture_if_dirty() -> void:
	if not _texture_dirty or _mask_texture == null or _mask_image == null:
		return
	# Replacing the resource is intentional. ImageTexture.update() changes the
	# rendering-server texture in place, but the paused tactical overlay can keep
	# displaying its previously submitted canvas texture. A fresh resource makes
	# the changed fog pixels visible immediately when WorldMapOverlay polls the
	# mask, while uploads still occur only when the map actually requests it.
	_mask_texture = ImageTexture.create_from_image(_mask_image)
	_texture_dirty = false
