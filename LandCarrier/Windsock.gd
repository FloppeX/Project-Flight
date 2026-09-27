extends Node3D
## Cosmetic wind indicator. +X is the authored sock's mouth-to-tail axis.
@export var full_extension_speed_mps := 8.0
@export var response_s := 0.8
@export var flutter_enabled := true
@export_range(0.0, 0.3, 0.01) var fixed_cuff_fraction := 0.12

const CLOTH_SHADER = preload("res://LandCarrier/Windsock.gdshader")
var _swivel: Node3D
var _materials: Array[ShaderMaterial] = []
var _field: Node
var _carrier: Node3D
var _speed := 0.0
var _heading := 0.0
var _time := 0.0
var _mouth := Vector3.ZERO
var _length := 1.0

func _ready() -> void:
	var model := $Model as Node3D
	var sections: Array[MeshInstance3D] = []
	for child in model.get_children():
		if child is MeshInstance3D and child.name != "pole":
			sections.append(child)
	sections.sort_custom(func(a: Node3D, b: Node3D): return a.position.x < b.position.x)
	if sections.size() != 4:
		push_error("Windsock requires the four authored fabric sections")
		set_process(false)
		return
	var first := sections[0]
	_mouth = first.position
	_mouth.x = (first.transform * first.get_aabb()).position.x
	var last := sections[-1]
	_length = (last.transform * last.get_aabb()).end.x - _mouth.x
	_swivel = Node3D.new()
	_swivel.name = "WindSwivel"
	model.add_child(_swivel)
	_swivel.position = _mouth
	for section in sections:
		var rest := section.transform
		rest.origin -= _mouth
		for surface in section.mesh.get_surface_count():
			var original := section.get_active_material(surface) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = CLOTH_SHADER
			material.set_shader_parameter("rest_transform", rest)
			material.set_shader_parameter("rest_normal", rest.basis.inverse().transposed())
			material.set_shader_parameter("sock_length", _length)
			material.set_shader_parameter("fixed_cuff_fraction", fixed_cuff_fraction)
			if original:
				material.set_shader_parameter("cloth_color", original.albedo_color)
				material.set_shader_parameter("cloth_roughness", original.roughness)
			section.set_surface_override_material(surface, material)
			_materials.append(material)
		section.reparent(_swivel, false)
		section.transform = Transform3D.IDENTITY
		# Shader moves the imported vertices outside their original mesh bounds.
		section.custom_aabb = AABB(Vector3.ONE * -6.0, Vector3.ONE * 12.0)
	var ancestor := get_parent()
	while ancestor:
		if ancestor is PhysicsBody3D or ancestor.has_method("get_deck_reference_velocity_vector"):
			_carrier = ancestor as Node3D
			break
		ancestor = ancestor.get_parent()
	update_wind(0.0, true)

func _process(delta: float) -> void:
	update_wind(delta)

func get_relative_wind() -> Vector3:
	if not is_instance_valid(_field):
		_field = get_tree().get_first_node_in_group("atmospheric_wind")
	var wind := Vector3.ZERO
	if is_instance_valid(_field) and _field.has_method("get_velocity_at"):
		wind = _field.get_velocity_at(_swivel.global_position)
	if is_instance_valid(_carrier):
		var velocity := Vector3.ZERO
		var angular := Vector3.ZERO
		if _carrier.has_method("get_deck_reference_velocity_vector"):
			velocity = _carrier.get_deck_reference_velocity_vector()
			if _carrier.has_method("get_yaw_rate_rad_s"):
				angular = Vector3.UP * float(_carrier.get_yaw_rate_rad_s())
		elif _carrier is RigidBody3D:
			velocity = _carrier.linear_velocity
			angular = _carrier.angular_velocity
		elif _carrier is CharacterBody3D:
			velocity = _carrier.velocity
		wind -= velocity + angular.cross(_swivel.global_position - _carrier.global_position)
	return wind

func update_wind(delta: float, immediate := false) -> void:
	if not is_instance_valid(_swivel): return
	var wind := get_relative_wind()
	# Horizontal airflow determines the vane; weak wind retains its last heading.
	wind.y = 0.0
	var local_wind := global_basis.orthonormalized().inverse() * wind
	var blend := 1.0 if immediate else 1.0 - exp(-delta / maxf(response_s, 0.05))
	_speed = lerpf(_speed, wind.length(), blend)
	if wind.length() > 0.15:
		_heading = lerp_angle(_heading, atan2(-local_wind.z, local_wind.x), blend)
	_swivel.rotation.y = _heading
	_time += delta
	var extension := smoothstep(0.0, maxf(full_extension_speed_mps, 0.1), _speed)
	for material in _materials:
		material.set_shader_parameter("droop", 1.0 - extension)
		material.set_shader_parameter("flutter", (0.025 * extension) if flutter_enabled else 0.0)
		material.set_shader_parameter("phase", _time)
