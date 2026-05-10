extends Building
class_name WindTurbine

@export var rotor_node_name: StringName = &"Rotor"
@export var rotor_pivot_path: NodePath = ^"RotorPivot"
@export var rotor_spin_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
@export var rotor_speed_deg_per_s: float = 90.0

var _rotor: Node3D = null
var _rotor_pivot: Node3D = null

func _ready() -> void:
	super._ready()
	_rotor_pivot = get_node_or_null(rotor_pivot_path) as Node3D
	_rotor = _setup_rotor_pivot()
	_apply_team_main_color()
	call_deferred("_apply_team_main_color")

func _process(delta: float) -> void:
	var rotor_target: Node3D = _rotor_pivot if _rotor_pivot != null and is_instance_valid(_rotor_pivot) else _rotor
	if rotor_target == null or not is_instance_valid(rotor_target):
		return
	var spin_axis: Vector3 = rotor_spin_axis.normalized()
	if spin_axis == Vector3.ZERO:
		spin_axis = Vector3(0.0, 0.0, 1.0)
	rotor_target.rotate_object_local(spin_axis, deg_to_rad(rotor_speed_deg_per_s) * delta)

func _destroy() -> void:
	is_destroyed = true
	EnemyOpsManager.on_turbine_destroyed()

	if destroyed_scene_path != "":
		var destroyed_scene: PackedScene = load(destroyed_scene_path)
		if destroyed_scene:
			var wreck := destroyed_scene.instantiate()
			get_tree().current_scene.add_child(wreck)
			wreck.global_transform = global_transform
			if wreck.has_method("set_team"):
				wreck.call("set_team", team)
			elif "team" in wreck:
				wreck.set("team", team)
			var rotor_transform: Transform3D = Transform3D.IDENTITY
			var has_rotor_transform: bool = false
			if _rotor_pivot != null and is_instance_valid(_rotor_pivot):
				rotor_transform = _rotor_pivot.global_transform
				has_rotor_transform = true
			elif _rotor != null and is_instance_valid(_rotor):
				rotor_transform = _rotor.global_transform
				has_rotor_transform = true
			if has_rotor_transform:
				if wreck.has_method("set_rotor_spin_state"):
					wreck.call("set_rotor_spin_state", rotor_transform, rotor_speed_deg_per_s, rotor_spin_axis)
				elif wreck.has_method("set_rotor_global_transform"):
					wreck.call("set_rotor_global_transform", rotor_transform)

	if _explosion_scene:
		var exp: Node3D = _explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position + Vector3(0, 8.0, 0)

	queue_free()

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

func _setup_rotor_pivot() -> Node3D:
	var visual_rotor: Node3D = _resolve_rotor_visual_node()
	if _rotor_pivot != null and is_instance_valid(_rotor_pivot):
		if visual_rotor != null and not _rotor_pivot.is_ancestor_of(visual_rotor):
			var visual_global: Transform3D = visual_rotor.global_transform
			visual_rotor.reparent(_rotor_pivot)
			visual_rotor.global_transform = visual_global
		return _rotor_pivot
	return visual_rotor

func _resolve_rotor_visual_node() -> Node3D:
	var named_rotor: Node3D = _find_named_node(self, rotor_node_name)
	if _node_has_mesh_descendants(named_rotor):
		return named_rotor

	var cone_node: Node3D = _find_node_name_contains(self, "cone")
	if cone_node != null:
		return cone_node

	if named_rotor != null:
		return named_rotor

	return _find_node_name_contains(self, "rotor")

func _find_node_name_contains(root: Node, text: String) -> Node3D:
	if root == null:
		return null
	if root is Node3D and text in root.name.to_lower():
		return root as Node3D
	for child in root.get_children():
		var found: Node3D = _find_node_name_contains(child, text)
		if found != null:
			return found
	return null

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
