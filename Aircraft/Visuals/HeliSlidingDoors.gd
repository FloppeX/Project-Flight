extends AircraftModule

@export var door_mesh_path: NodePath = NodePath("aircraft_9/Door")
@export var toggle_key: Key = KEY_O
@export var lateral_slide_m: float = 0.1
@export var rear_travel_widths: float = 1.0
@export var rear_travel_override_m: float = 0.0
@export var rear_axis: Vector3 = Vector3(0.0, 0.0, -1.0)
@export_range(0.05, 0.95, 0.01) var lateral_phase: float = 0.32
@export var animation_duration_s: float = 1.2
@export var split_x: float = 0.0
@export var only_player_controlled: bool = true

var _source_door: MeshInstance3D
var _left_door: MeshInstance3D
var _right_door: MeshInstance3D
var _left_rest_position: Vector3 = Vector3.ZERO
var _right_rest_position: Vector3 = Vector3.ZERO
var _left_rear_travel_m: float = 0.75
var _right_rear_travel_m: float = 0.75
var _open_target: bool = false
var _open_t: float = 0.0
var _initialized: bool = false
var _toggle_key_was_down: bool = false
var _is_landed_idle: bool = false
var _idle_time_s: float = 0.0


func _ready() -> void:
	ReceiveInput = true
	ProcessRender = true
	if aircraft == null and get_parent() != null:
		aircraft = get_parent()
		call_deferred("_setup_doors")


func setup(aircraft_node):
	aircraft = aircraft_node
	call_deferred("_setup_doors")


func receive_input(event: InputEvent) -> void:
	if not _initialized or not _is_this_aircraft_player_controlled():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == toggle_key:
			_open_target = not _open_target
			print("[HeliSlidingDoors] %s manual door toggle: open_target=%s" % [aircraft.name, _open_target])
			get_viewport().set_input_as_handled()


func process_render_frame(delta: float) -> void:
	if not _initialized:
		return
	
	if _is_this_aircraft_player_controlled():
		_poll_toggle_key()
	else:
		var pilot = aircraft.find_child("HelicopterPilot", true, false) if is_instance_valid(aircraft) else null
		if is_instance_valid(pilot) and pilot.get("state") == 0: # State.IDLE
			if not _is_landed_idle:
				_is_landed_idle = true
				_idle_time_s = 0.0
				_open_target = true
				print("[HeliSlidingDoors] %s doors opening: landing idle detected" % [aircraft.name])
			else:
				_idle_time_s += delta
				if _idle_time_s >= 10.0 and _open_target:
					_open_target = false
					print("[HeliSlidingDoors] %s doors closing: idle time limit reached" % [aircraft.name])
		else:
			if _is_landed_idle:
				_is_landed_idle = false
				if _open_target:
					_open_target = false
					print("[HeliSlidingDoors] %s doors closing: takeoff/transition detected" % [aircraft.name])
				
	var target_t := 1.0 if _open_target else 0.0
	_open_t = move_toward(_open_t, target_t, delta / maxf(animation_duration_s, 0.01))
	_apply_door_pose()


func _poll_toggle_key() -> void:
	var key_down := Input.is_physical_key_pressed(toggle_key)
	if key_down and not _toggle_key_was_down and _is_this_aircraft_player_controlled():
		_open_target = not _open_target
		print("[HeliSlidingDoors] %s manual door toggle: open_target=%s" % [aircraft.name, _open_target])
	_toggle_key_was_down = key_down


func _setup_doors() -> void:
	if _initialized:
		return
	if is_instance_valid(aircraft):
		_source_door = aircraft.get_node_or_null(door_mesh_path) as MeshInstance3D
	else:
		_source_door = get_node_or_null(door_mesh_path) as MeshInstance3D
	if _source_door == null:
		var root: Node = aircraft.get_node_or_null(door_mesh_path) if is_instance_valid(aircraft) else get_node_or_null(door_mesh_path)
		if root != null:
			_source_door = _find_first_mesh_instance(root)
	if _source_door == null or _source_door.mesh == null:
		push_warning("HeliSlidingDoors could not find a mesh door at %s" % [door_mesh_path])
		return

	var split := _build_split_door_meshes(_source_door.mesh)
	var left_mesh := split.get("left") as ArrayMesh
	var right_mesh := split.get("right") as ArrayMesh
	if left_mesh == null or right_mesh == null:
		push_warning("HeliSlidingDoors could not split the door mesh into left/right halves")
		return

	_left_door = _make_door_clone("LeftSlidingDoor", left_mesh)
	_right_door = _make_door_clone("RightSlidingDoor", right_mesh)
	_source_door.visible = false

	_left_rest_position = _left_door.position
	_right_rest_position = _right_door.position
	var rear_travel := _get_rear_travel_distance()
	_left_rear_travel_m = rear_travel
	_right_rear_travel_m = rear_travel
	_initialized = true
	_apply_door_pose()
	print("[HeliSlidingDoors] %s doors setup complete: left=%s, right=%s" % [aircraft.name, _left_door.name, _right_door.name])


func _make_door_clone(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var clone := MeshInstance3D.new()
	clone.name = node_name
	clone.mesh = mesh
	clone.transform = _source_door.transform
	clone.cast_shadow = _source_door.cast_shadow
	clone.gi_mode = _source_door.gi_mode
	clone.visibility_range_begin = _source_door.visibility_range_begin
	clone.visibility_range_end = _source_door.visibility_range_end
	var parent := _source_door.get_parent()
	parent.add_child(clone)
	clone.owner = _source_door.owner
	return clone


func _apply_door_pose() -> void:
	var t := _smoothstep(clampf(_open_t, 0.0, 1.0))
	var lateral_t := clampf(t / maxf(lateral_phase, 0.001), 0.0, 1.0)
	var rear_t := clampf((t - lateral_phase) / maxf(1.0 - lateral_phase, 0.001), 0.0, 1.0)
	var rear_dir := rear_axis.normalized()

	if _left_door != null:
		_left_door.position = _left_rest_position \
			+ Vector3.RIGHT * lateral_slide_m * lateral_t \
			+ rear_dir * _left_rear_travel_m * rear_t
	if _right_door != null:
		_right_door.position = _right_rest_position \
			+ Vector3.LEFT * lateral_slide_m * lateral_t \
			+ rear_dir * _right_rear_travel_m * rear_t


func _build_split_door_meshes(source_mesh: Mesh) -> Dictionary:
	var left_mesh := ArrayMesh.new()
	var right_mesh := ArrayMesh.new()
	var left_surfaces := 0
	var right_surfaces := 0

	for surface_idx in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_idx)
		var material := source_mesh.surface_get_material(surface_idx)
		var left_arrays := _extract_surface_side(arrays, true)
		var right_arrays := _extract_surface_side(arrays, false)

		if not _surface_vertices_empty(left_arrays):
			left_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, left_arrays)
			left_mesh.surface_set_material(left_surfaces, material)
			left_surfaces += 1
		if not _surface_vertices_empty(right_arrays):
			right_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, right_arrays)
			right_mesh.surface_set_material(right_surfaces, material)
			right_surfaces += 1

	if left_surfaces == 0 or right_surfaces == 0:
		return {}
	return {
		"left": left_mesh,
		"right": right_mesh,
	}


func _extract_surface_side(arrays: Array, positive_x: bool) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = _typed_array_or_empty(arrays, Mesh.ARRAY_NORMAL)
	var colors: PackedColorArray = _typed_array_or_empty(arrays, Mesh.ARRAY_COLOR)
	var uvs: PackedVector2Array = _typed_array_or_empty(arrays, Mesh.ARRAY_TEX_UV)
	var uv2s: PackedVector2Array = _typed_array_or_empty(arrays, Mesh.ARRAY_TEX_UV2)
	var indices: PackedInt32Array = _typed_array_or_empty(arrays, Mesh.ARRAY_INDEX)

	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_colors := PackedColorArray()
	var out_uvs := PackedVector2Array()
	var out_uv2s := PackedVector2Array()

	var triangle_count := indices.size() / 3 if indices.size() > 0 else vertices.size() / 3
	for tri in range(triangle_count):
		var i0 := _surface_vertex_index(indices, tri * 3)
		var i1 := _surface_vertex_index(indices, tri * 3 + 1)
		var i2 := _surface_vertex_index(indices, tri * 3 + 2)
		if i0 < 0 or i1 < 0 or i2 < 0 or i0 >= vertices.size() or i1 >= vertices.size() or i2 >= vertices.size():
			continue

		var center_x := (vertices[i0].x + vertices[i1].x + vertices[i2].x) / 3.0
		if (center_x >= split_x) != positive_x:
			continue

		for src_i in [i0, i1, i2]:
			out_vertices.append(vertices[src_i])
			if normals.size() == vertices.size():
				out_normals.append(normals[src_i])
			if colors.size() == vertices.size():
				out_colors.append(colors[src_i])
			if uvs.size() == vertices.size():
				out_uvs.append(uvs[src_i])
			if uv2s.size() == vertices.size():
				out_uv2s.append(uv2s[src_i])

	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_vertices
	if out_normals.size() == out_vertices.size():
		out[Mesh.ARRAY_NORMAL] = out_normals
	if out_colors.size() == out_vertices.size():
		out[Mesh.ARRAY_COLOR] = out_colors
	if out_uvs.size() == out_vertices.size():
		out[Mesh.ARRAY_TEX_UV] = out_uvs
	if out_uv2s.size() == out_vertices.size():
		out[Mesh.ARRAY_TEX_UV2] = out_uv2s
	return out


func _surface_vertex_index(indices: PackedInt32Array, fallback_index: int) -> int:
	if indices.size() > 0:
		return indices[fallback_index]
	return fallback_index


func _typed_array_or_empty(arrays: Array, array_index: int) -> Variant:
	if array_index >= arrays.size() or arrays[array_index] == null:
		match array_index:
			Mesh.ARRAY_NORMAL:
				return PackedVector3Array()
			Mesh.ARRAY_COLOR:
				return PackedColorArray()
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
				return PackedVector2Array()
			Mesh.ARRAY_INDEX:
				return PackedInt32Array()
			_:
				return []
	return arrays[array_index]


func _surface_vertices_empty(arrays: Array) -> bool:
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return true
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return vertices.is_empty()


func _get_rear_travel_distance() -> float:
	if rear_travel_override_m > 0.0:
		return rear_travel_override_m * rear_travel_widths
	var rear_dir := rear_axis.normalized()
	if rear_dir.length_squared() <= 0.0 or _source_door == null or _source_door.mesh == null:
		return 0.75 * rear_travel_widths
	var aabb := _source_door.mesh.get_aabb()
	var min_projection := INF
	var max_projection := -INF
	for x in [aabb.position.x, aabb.position.x + aabb.size.x]:
		for y in [aabb.position.y, aabb.position.y + aabb.size.y]:
			for z in [aabb.position.z, aabb.position.z + aabb.size.z]:
				var parent_space_corner := _source_door.transform * Vector3(x, y, z)
				var projection := parent_space_corner.dot(rear_dir)
				min_projection = minf(min_projection, projection)
				max_projection = maxf(max_projection, projection)
	return maxf(max_projection - min_projection, 0.25) * rear_travel_widths


func _smoothstep(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


func _find_first_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for child in root.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


func _is_this_aircraft_player_controlled() -> bool:
	if not only_player_controlled:
		return true
	if not is_instance_valid(aircraft):
		return false
	var director := get_node_or_null("/root/FlightDirector")
	if director != null:
		var controlled = director.get("player_controlled_plane")
		if is_instance_valid(controlled) and controlled == aircraft:
			return true
		var viewed = director.get("current_viewed_aircraft")
		if is_instance_valid(viewed) and viewed == aircraft:
			return true
		return false
	var ai_toggle = aircraft.get_node_or_null("AIToggle")
	if ai_toggle != null and "ai_active" in ai_toggle:
		return not ai_toggle.ai_active
	return true
