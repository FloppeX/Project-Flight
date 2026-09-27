extends Node3D
## Imported centre-split door. Travel stays local to the moving carrier.

const CLIP_SHADER = preload("res://LandCarrier/CarrierDoor.gdshader")
const DISTANCE_EPSILON_M := 0.001
@export var approach_distance_m: float = 1.2
@export var hold_open_distance_m: float = 0.20
@export_range(-1.0, 1.0, 0.05) var facing_dot_min: float = 0.5
@export var travel_time_s: float = 0.40
var openness: float = 0.0
var occupied: bool = false
var _leaves: Array[Dictionary] = []
var _sensor: Area3D
var _width: float
var _height: float
var _aperture_center := Vector3.ZERO
var _aperture_base_y := 0.0
var _motion_audio: AudioStreamPlayer3D
var _motion_direction: float = 0.0

func _ready() -> void:
	_motion_audio = AudioStreamPlayer3D.new()
	_motion_audio.name = "DoorActuator"
	_motion_audio.stream = preload("res://Audio/mechanisms/door_slide.wav")
	_motion_audio.volume_db = -13.0
	_motion_audio.unit_size = 2.5
	_motion_audio.max_distance = 14.0
	_motion_audio.position.y = 1.0
	_motion_audio.add_to_group("3d_audio")
	_motion_audio.add_to_group("carrier_local_audio")
	add_child(_motion_audio)
	_width = float(get_meta("opening_width_m", 1.1))
	_height = float(get_meta("opening_height_m", 2.06))
	for child in get_children():
		if child is MeshInstance3D and not child.has_meta("open_offset_x_m"):
			var frame := child as MeshInstance3D
			var frame_bounds: AABB = frame.transform * frame.get_aabb()
			_aperture_center = frame_bounds.get_center()
			_aperture_center.y = 0.0
			_aperture_base_y = frame_bounds.position.y
			break
	for child in get_children():
		if not child is MeshInstance3D or not child.has_meta("open_offset_x_m"):
			continue
		var leaf := child as MeshInstance3D
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.collision_layer = 1 | (1 << 20)
		body.collision_mask = 0
		add_child(body)
		var carrier := get_parent().get_parent() as PhysicsBody3D
		if carrier:
			body.add_collision_exception_with(carrier)
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		body.add_child(shape)
		var materials: Array[ShaderMaterial] = []
		_leaves.append({"mesh": leaf, "closed": leaf.position,
			"travel": float(leaf.get_meta("open_offset_x_m")), "shape": shape, "materials": materials})
		for surface in leaf.mesh.get_surface_count():
			var original := leaf.get_active_material(surface) as StandardMaterial3D
			var material := ShaderMaterial.new()
			material.shader = CLIP_SHADER
			material.set_shader_parameter("aperture_half_width", _width * 0.5)
			material.set_shader_parameter("aperture_center_x", _aperture_center.x)
			if original:
				material.set_shader_parameter("plate_color", original.albedo_color)
				material.set_shader_parameter("plate_metallic", original.metallic)
				material.set_shader_parameter("plate_roughness", original.roughness)
				material.set_shader_parameter("plate_emission", original.emission * original.emission_energy_multiplier if original.emission_enabled else Color.BLACK)
			leaf.set_surface_override_material(surface, material)
			materials.append(material)
	_sensor = Area3D.new()
	_sensor.name = "CharacterProximity"
	_sensor.collision_layer = 0
	_sensor.collision_mask = 0xFFFFFFFF
	add_child(_sensor)
	var trigger := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_width + approach_distance_m * 2.0, _height, 4.4)
	trigger.shape = box
	trigger.position = Vector3(
		_aperture_center.x, _aperture_base_y + _height * 0.5, _aperture_center.z)
	_sensor.add_child(trigger)
	_apply_pose()

func _physics_process(delta: float) -> void:
	occupied = false
	var open_request := false
	var hold_open_request := false
	for body in _sensor.get_overlapping_bodies():
		if (body is CharacterBody3D and not body.is_ancestor_of(self)) or body.is_in_group("door_users"):
			var point := to_local(body.global_position)
			var distance := _distance_to_doorway(point)
			var facing := _is_facing_door(body as Node3D, point)
			open_request = open_request or (distance <= approach_distance_m + DISTANCE_EPSILON_M and facing)
			hold_open_request = hold_open_request or (distance <= hold_open_distance_m + DISTANCE_EPSILON_M or facing)
	occupied = hold_open_request
	# A closed door needs an intentional look within 1.2 metres. Once any leaf is
	# moving/open, proximity or continued attention keeps it open; it closes only
	# when every detected person is both over 20 cm away and facing elsewhere.
	var should_be_open := open_request if openness <= 0.0 else hold_open_request
	var target := 1.0 if should_be_open else 0.0
	var next := move_toward(openness, target, delta / maxf(travel_time_s, 0.01))
	var direction := signf(next - openness)
	if direction != 0.0 and direction != _motion_direction:
		_motion_audio.pitch_scale = 1.05 if direction > 0.0 else 0.95
		_motion_audio.play()
	_motion_direction = direction
	if next != openness:
		openness = next
		_apply_pose()

func _distance_to_doorway(point: Vector3) -> float:
	var nearest_x := clampf(
		point.x, _aperture_center.x - _width * 0.5, _aperture_center.x + _width * 0.5)
	return Vector2(point.x - nearest_x, point.z - _aperture_center.z).length()

func _is_facing_door(body: Node3D, point: Vector3) -> bool:
	var nearest_x := clampf(
		point.x, _aperture_center.x - _width * 0.5, _aperture_center.x + _width * 0.5)
	var toward := Vector3(nearest_x - point.x, 0.0, _aperture_center.z - point.z)
	if toward.length_squared() < 0.000001:
		return true
	var facing_basis := body.global_basis
	# The walking commander camera has a 180-degree local yaw. Use the view
	# direction for intentional door attention, not the character body's yaw.
	var view_camera := body.get_node_or_null("Camera3D") as Camera3D
	if view_camera != null and view_camera.current:
		facing_basis = view_camera.global_basis
	var forward := global_basis.orthonormalized().inverse() * (-facing_basis.z.normalized())
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return false
	return forward.normalized().dot(toward.normalized()) >= facing_dot_min

func get_aperture_center_local() -> Vector3:
	return _aperture_center

func _apply_pose() -> void:
	for entry in _leaves:
		var leaf: MeshInstance3D = entry.mesh
		leaf.position = entry.closed + Vector3.RIGHT * float(entry.travel) * smoothstep(0.0, 1.0, openness)
		for material in entry.materials:
			material.set_shader_parameter("door_offset_x", leaf.position.x)
		# Both rendering and collision retract into the jamb, even in thin walls.
		var bounds := leaf.get_aabb()
		var left := maxf(_aperture_center.x - _width * 0.5, leaf.position.x + bounds.position.x)
		var right := minf(_aperture_center.x + _width * 0.5, leaf.position.x + bounds.end.x)
		var collision: CollisionShape3D = entry.shape
		collision.disabled = openness >= 0.999 or right - left < 0.005
		var box := collision.shape as BoxShape3D
		box.size = Vector3(maxf(right - left, 0.001), _height - 0.015, 0.17)
		collision.position = Vector3((left + right) * 0.5, (_height + 0.015) * 0.5, 0.0)
