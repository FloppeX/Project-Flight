extends Node3D
class_name WindTurbineDestroyed

@export var mesh_root_path: NodePath = ^"Mesh"
@export var rotor_node_name: StringName = &"Rotor"
@export var cleanup_after_s: float = 30.0
@export var breakup_impulse_mps: float = 0.0
@export var breakup_vertical_impulse_mps: float = 0.0
@export var breakup_extra_spin: float = 0.0
@export var debris_collision_layer: int = 513
@export var max_piece_neighbors: int = 4
@export var joint_connection_margin_m: float = 1.2
@export var joint_connection_max_distance_m: float = 12.0
@export var rotor_spin_deg_per_s: float = 90.0
@export var rotor_spin_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
@export var team: int = 2

var _mesh_root: Node = null
var _pending_rotor_global_transform: Transform3D
var _has_pending_rotor_transform: bool = false
var _pending_rotor_spin_deg_per_s: float = 90.0
var _pending_rotor_spin_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
var _broken_apart: bool = false
var _piece_bodies: Dictionary = {}
var _piece_joints: Dictionary = {}
var _ground_detached_piece_ids: Dictionary = {}

func _ready() -> void:
	_mesh_root = get_node_or_null(mesh_root_path)
	if _has_pending_rotor_transform:
		_apply_rotor_global_transform(_pending_rotor_global_transform)
	_apply_team_main_color()
	call_deferred("_break_apart")

func set_team(new_team: int) -> void:
	team = new_team
	if is_node_ready():
		_apply_team_main_color()

func set_rotor_global_transform(rotor_global_transform: Transform3D) -> void:
	_pending_rotor_global_transform = rotor_global_transform
	_has_pending_rotor_transform = true
	if is_node_ready():
		_apply_rotor_global_transform(rotor_global_transform)

func set_rotor_spin_state(rotor_global_transform: Transform3D, spin_deg_per_s: float, spin_axis: Vector3) -> void:
	_pending_rotor_spin_deg_per_s = spin_deg_per_s
	_pending_rotor_spin_axis = spin_axis
	set_rotor_global_transform(rotor_global_transform)

func _apply_rotor_global_transform(rotor_global_transform: Transform3D) -> void:
	var search_root: Node = _mesh_root if _mesh_root != null else self
	var rotor_nodes: Array[Node3D] = _resolve_rotor_nodes(search_root)
	for rotor in rotor_nodes:
		if rotor != null and is_instance_valid(rotor):
			rotor.global_basis = rotor_global_transform.basis

func _break_apart() -> void:
	if _broken_apart:
		return
	_broken_apart = true

	var search_root: Node = _mesh_root if _mesh_root != null else self
	var pieces: Array[MeshInstance3D] = []
	_collect_mesh_instances(search_root, pieces)
	if pieces.is_empty():
		queue_free()
		return

	var parent_node: Node = get_parent()
	if parent_node == null:
		return

	var piece_records: Array[Dictionary] = []
	var next_piece_id: int = 0
	for piece in pieces:
		if piece == null or not is_instance_valid(piece) or piece.mesh == null or not piece.visible:
			continue
		var rb := RigidBody3D.new()
		var piece_id: int = next_piece_id
		next_piece_id += 1
		rb.name = "%s_Debris" % piece.name
		rb.mass = _estimate_piece_mass(piece)
		rb.sleeping = false
		rb.contact_monitor = true
		rb.max_contacts_reported = 4
		rb.collision_layer = debris_collision_layer
		parent_node.add_child(rb)
		rb.global_transform = piece.global_transform

		var debris_mesh := MeshInstance3D.new()
		debris_mesh.mesh = piece.mesh
		debris_mesh.material_override = piece.material_override
		debris_mesh.cast_shadow = piece.cast_shadow
		rb.add_child(debris_mesh)
		if piece.mesh != null:
			for surface_idx in range(piece.mesh.get_surface_count()):
				var surface_override: Material = piece.get_surface_override_material(surface_idx)
				if surface_override != null:
					debris_mesh.set_surface_override_material(surface_idx, surface_override)

		var collider := CollisionShape3D.new()
		collider.shape = _build_piece_collision_shape(piece)
		collider.position = piece.get_aabb().position + piece.get_aabb().size * 0.5
		rb.add_child(collider)

		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.body_entered.connect(_on_piece_body_entered.bind(piece_id))
		_schedule_cleanup(rb)
		_piece_bodies[piece_id] = rb
		_piece_joints[piece_id] = []
		piece_records.append({
			"id": piece_id,
			"body": rb,
			"size": _get_piece_size(piece),
			"is_rotor": _is_rotor_piece_name(piece.name),
		})

	_create_piece_joints(piece_records)
	_apply_initial_rotor_spin(piece_records)
	if _mesh_root != null and is_instance_valid(_mesh_root):
		_mesh_root.queue_free()
	_schedule_cleanup(self)

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child as MeshInstance3D)
		_collect_mesh_instances(child, out)

func _find_named_node(root: Node, target_name: StringName) -> Node3D:
	if root == null:
		return null
	if StringName(root.name) == target_name and root is Node3D:
		return root as Node3D
	for child in root.get_children():
		var found: Node3D = _find_named_node(child, target_name)
		if found != null:
			return found
	return null

func _resolve_rotor_nodes(root: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var named_rotor: Node3D = _find_named_node(root, rotor_node_name)
	if _node_has_mesh_descendants(named_rotor):
		result.append(named_rotor)
		return result

	_collect_nodes_name_contains(root, "cone", result)
	if not result.is_empty():
		return result

	if named_rotor != null:
		result.append(named_rotor)
		return result

	_collect_nodes_name_contains(root, "rotor", result)
	return result

func _collect_nodes_name_contains(root: Node, text: String, out: Array[Node3D]) -> void:
	if root == null:
		return
	if root is Node3D and text in root.name.to_lower():
		out.append(root as Node3D)
	for child in root.get_children():
		_collect_nodes_name_contains(child, text, out)

func _node_has_mesh_descendants(node: Node) -> bool:
	if node == null:
		return false
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _node_has_mesh_descendants(child):
			return true
	return false

func _apply_team_main_color() -> void:
	var team_color: Color = _get_team_main_color()
	_apply_main_color_recursive(self, team_color)

func _get_team_main_color() -> Color:
	var fallback_color: Color = Color(0.78, 0.20, 0.15) if team == 2 else Color(0.22, 0.44, 0.76)
	var livery_node: Node = get_node_or_null("/root/Livery")
	if livery_node != null and livery_node.has_method("_get_team_upper_color"):
		var color_variant: Variant = livery_node.call("_get_team_upper_color", team)
		if color_variant is Color:
			return color_variant as Color
	if livery_node != null:
		var upper_variant: Variant = livery_node.get("upper_color")
		if upper_variant is Color:
			return upper_variant as Color
	return fallback_color

func _apply_main_color_recursive(node: Node, team_color: Color) -> void:
	if node is MeshInstance3D:
		_apply_main_color_to_mesh(node as MeshInstance3D, team_color)
	for child in node.get_children():
		_apply_main_color_recursive(child, team_color)

func _apply_main_color_to_mesh(mesh_instance: MeshInstance3D, team_color: Color) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	var surface_count: int = mesh.get_surface_count()
	for surface_idx in range(surface_count):
		var source_material: Material = mesh_instance.get_active_material(surface_idx)
		if source_material == null:
			source_material = mesh.surface_get_material(surface_idx)
		if source_material == null:
			continue

		var override_material: Material = source_material.duplicate()
		if override_material is StandardMaterial3D and _is_main_color_material(source_material):
			var standard_material := override_material as StandardMaterial3D
			standard_material.albedo_color = team_color
		elif override_material is ShaderMaterial:
			var shader_material := override_material as ShaderMaterial
			var changed_shader: bool = false
			changed_shader = _set_shader_color_if_declared(shader_material, "Main_Color", team_color) or changed_shader
			changed_shader = _set_shader_color_if_declared(shader_material, "main_color", team_color) or changed_shader
			changed_shader = _set_shader_color_if_declared(shader_material, "Main_Color_Dark", team_color.darkened(0.35)) or changed_shader
			changed_shader = _set_shader_color_if_declared(shader_material, "main_color_dark", team_color.darkened(0.35)) or changed_shader
			if not changed_shader:
				continue
		else:
			continue
		mesh_instance.set_surface_override_material(surface_idx, override_material)

func _is_main_color_material(material: Material) -> bool:
	if material == null:
		return false
	var material_name: String = String(material.resource_name).to_lower().replace("_", " ").replace("-", " ")
	if "main color" in material_name:
		return true
	if material is StandardMaterial3D:
		var standard_material := material as StandardMaterial3D
		var albedo_texture: Texture2D = standard_material.albedo_texture
		if albedo_texture != null:
			var texture_name: String = String(albedo_texture.resource_name).to_lower().replace("_", " ").replace("-", " ")
			var texture_path: String = String(albedo_texture.resource_path).to_lower().replace("_", " ").replace("-", " ")
			return "main color" in texture_name or "main color" in texture_path
	return false

func _set_shader_color_if_declared(shader_material: ShaderMaterial, parameter_name: String, value: Color) -> bool:
	if shader_material == null or shader_material.shader == null:
		return false
	var shader_code: String = shader_material.shader.code
	if shader_code.find(parameter_name) == -1:
		return false
	shader_material.set_shader_parameter(parameter_name, value)
	return true

func _build_piece_collision_shape(piece: MeshInstance3D) -> Shape3D:
	var aabb: AABB = piece.get_aabb()
	if aabb.size.length_squared() <= 0.0001 and piece.mesh != null:
		aabb = piece.mesh.get_aabb()
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		maxf(aabb.size.x, 0.2),
		maxf(aabb.size.y, 0.2),
		maxf(aabb.size.z, 0.2)
	)
	return shape

func _estimate_piece_mass(piece: MeshInstance3D) -> float:
	var size: Vector3 = _get_piece_size(piece)
	var volume: float = maxf(size.x * size.y * size.z, 0.35)
	return clampf(volume * 6.0, 6.0, 180.0)

func _get_piece_size(piece: MeshInstance3D) -> Vector3:
	var aabb: AABB = piece.get_aabb()
	if aabb.size.length_squared() <= 0.0001 and piece.mesh != null:
		aabb = piece.mesh.get_aabb()
	return aabb.size

func _create_piece_joints(piece_records: Array[Dictionary]) -> void:
	var connected_pairs: Dictionary = {}
	for record in piece_records:
		var source_id: int = int(record.get("id", -1))
		var source_body := record.get("body", null) as RigidBody3D
		if source_body == null:
			continue

		var neighbor_candidates: Array[Dictionary] = []
		for other in piece_records:
			var other_id: int = int(other.get("id", -1))
			if other_id == source_id:
				continue
			var other_body := other.get("body", null) as RigidBody3D
			if other_body == null:
				continue
			var distance_m: float = source_body.global_position.distance_to(other_body.global_position)
			var connection_limit: float = _get_connection_distance(record, other)
			if distance_m <= connection_limit:
				neighbor_candidates.append({
					"id": other_id,
					"dist": distance_m,
				})

		neighbor_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("dist", INF)) < float(b.get("dist", INF))
		)

		var limit: int = mini(max_piece_neighbors, neighbor_candidates.size())
		for idx in range(limit):
			var other_id: int = int(neighbor_candidates[idx].get("id", -1))
			if other_id < 0:
				continue
			var pair_key: String = "%d:%d" % [mini(source_id, other_id), maxi(source_id, other_id)]
			if connected_pairs.has(pair_key):
				continue
			connected_pairs[pair_key] = true
			_create_joint_between(source_id, other_id)

func _create_joint_between(piece_a_id: int, piece_b_id: int) -> void:
	var body_a := _piece_bodies.get(piece_a_id, null) as RigidBody3D
	var body_b := _piece_bodies.get(piece_b_id, null) as RigidBody3D
	if body_a == null or body_b == null:
		return

	var joint := PinJoint3D.new()
	add_child(joint)
	joint.global_position = body_a.global_position.lerp(body_b.global_position, 0.5)
	joint.node_a = joint.get_path_to(body_a)
	joint.node_b = joint.get_path_to(body_b)
	joint.set_meta("piece_a_id", piece_a_id)
	joint.set_meta("piece_b_id", piece_b_id)

	var joints_a: Array = _piece_joints.get(piece_a_id, [])
	joints_a.append(joint)
	_piece_joints[piece_a_id] = joints_a
	var joints_b: Array = _piece_joints.get(piece_b_id, [])
	joints_b.append(joint)
	_piece_joints[piece_b_id] = joints_b

func _get_connection_distance(piece_a: Dictionary, piece_b: Dictionary) -> float:
	var size_a: Variant = piece_a.get("size", Vector3.ONE)
	var size_b: Variant = piece_b.get("size", Vector3.ONE)
	var len_a: float = (size_a as Vector3).length() if size_a is Vector3 else 1.0
	var len_b: float = (size_b as Vector3).length() if size_b is Vector3 else 1.0
	return minf(((len_a + len_b) * 0.25) + joint_connection_margin_m, joint_connection_max_distance_m)

func _apply_initial_rotor_spin(piece_records: Array[Dictionary]) -> void:
	if not _has_pending_rotor_transform:
		return
	var spin_axis_world: Vector3 = _pending_rotor_global_transform.basis * _pending_rotor_spin_axis.normalized()
	if spin_axis_world.length_squared() <= 0.000001:
		spin_axis_world = _pending_rotor_global_transform.basis * rotor_spin_axis.normalized()
	if spin_axis_world.length_squared() <= 0.000001:
		spin_axis_world = Vector3.FORWARD
	spin_axis_world = spin_axis_world.normalized()
	var angular_speed_rad: float = deg_to_rad(_pending_rotor_spin_deg_per_s if is_finite(_pending_rotor_spin_deg_per_s) else rotor_spin_deg_per_s)
	var rotor_origin: Vector3 = _pending_rotor_global_transform.origin

	for record in piece_records:
		if not bool(record.get("is_rotor", false)):
			continue
		var body := record.get("body", null) as RigidBody3D
		if body == null:
			continue
		var radial: Vector3 = body.global_position - rotor_origin
		radial -= spin_axis_world * radial.dot(spin_axis_world)
		var tangential: Vector3 = spin_axis_world.cross(radial) * angular_speed_rad
		body.linear_velocity += tangential
		body.angular_velocity = spin_axis_world * angular_speed_rad

func _on_piece_body_entered(body: Node, piece_id: int) -> void:
	if _ground_detached_piece_ids.has(piece_id):
		return
	if not _is_ground_or_terrain(body):
		return
	_ground_detached_piece_ids[piece_id] = true
	_detach_piece(piece_id)

func _detach_piece(piece_id: int) -> void:
	var joints: Array = _piece_joints.get(piece_id, [])
	for joint_var in joints:
		var joint := joint_var as Joint3D
		if joint == null or not is_instance_valid(joint):
			continue
		var piece_a_id: int = int(joint.get_meta("piece_a_id", -1))
		var piece_b_id: int = int(joint.get_meta("piece_b_id", -1))
		var other_id: int = piece_b_id if piece_a_id == piece_id else piece_a_id
		_remove_joint_from_piece(other_id, joint)
		joint.queue_free()
	_piece_joints[piece_id] = []

func _remove_joint_from_piece(piece_id: int, joint: Joint3D) -> void:
	var joints: Array = _piece_joints.get(piece_id, [])
	joints.erase(joint)
	_piece_joints[piece_id] = joints

func _is_ground_or_terrain(body: Node) -> bool:
	if body == null:
		return false
	if body.is_in_group("terrain") or body.is_in_group("ground") or body.is_in_group("runway_surface"):
		return true
	if body.is_in_group("buildings") or body.is_in_group("carrier"):
		return false
	var body_name: String = body.name.to_lower()
	if "terrain" in body_name or "ground" in body_name:
		return true
	return body is StaticBody3D

func _is_rotor_piece_name(piece_name: String) -> bool:
	var lowered: String = piece_name.to_lower()
	return "cone" in lowered or "rotor" in lowered or "blade" in lowered

func _schedule_cleanup(node: Node) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = cleanup_after_s
	timer.timeout.connect(node.queue_free)
	timer.timeout.connect(timer.queue_free)
	node.add_child(timer)
	timer.start()
