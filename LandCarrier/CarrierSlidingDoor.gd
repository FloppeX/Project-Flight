extends Node3D
## Imported centre-split door. Travel stays local to the moving carrier.

const CLIP_SHADER = preload("res://LandCarrier/CarrierDoor.gdshader")
@export var approach_distance_m: float = 0.80
@export var travel_time_s: float = 0.40
@export var close_delay_s: float = 0.45
var _previous_positions: Dictionary = {}
var openness: float = 0.0
var occupied: bool = false
var _delay: float = 0.0
var _leaves: Array[Dictionary] = []
var _sensor: Area3D
var _width: float
var _height: float
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
	add_child(_motion_audio)
	_width = float(get_meta("opening_width_m", 1.1))
	_height = float(get_meta("opening_height_m", 2.06))
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
	box.size = Vector3(_width + 1.0, _height, 4.4)
	trigger.shape = box
	trigger.position.y = _height * 0.5
	_sensor.add_child(trigger)
	_apply_pose()

func _physics_process(delta: float) -> void:
	occupied = false
	var approaching := false
	var positions: Dictionary = {}
	for body in _sensor.get_overlapping_bodies():
		if (body is CharacterBody3D and not body.is_ancestor_of(self)) or body.is_in_group("door_users"):
			# Measure actual movement relative to the door: the commander is moved
			# directly and reports zero velocity, even while walking. Carrier motion
			# must not count as a person approaching.
			var point := to_local(body.global_position)
			var id: int = body.get_instance_id()
			positions[id] = point
			if _previous_positions.has(id):
				var motion: Vector3 = (point - Vector3(_previous_positions[id])) / maxf(delta, 0.001)
				approaching = approaching or _is_approaching(point, motion)
			# Once opening, keep the leaves clear of a person in the threshold,
			# including someone who stops or turns around while passing through.
			occupied = occupied or (absf(point.x) < _width * 0.5 + 0.28 and absf(point.z) < 0.45)
	_previous_positions = positions
	if approaching or (openness > 0.0 and occupied):
		_delay = close_delay_s
	else:
		_delay = maxf(0.0, _delay - delta)
	var target := 1.0 if _delay > 0.0 else 0.0
	var next := move_toward(openness, target, delta / maxf(travel_time_s, 0.01))
	var direction := signf(next - openness)
	if direction != 0.0 and direction != _motion_direction:
		_motion_audio.pitch_scale = 1.05 if direction > 0.0 else 0.95
		_motion_audio.play()
	_motion_direction = direction
	if next != openness:
		openness = next
		_apply_pose()

func _is_approaching(point: Vector3, motion: Vector3) -> bool:
	if absf(point.z) > approach_distance_m or absf(point.x) > _width * 0.5 + 0.15:
		return false
	var planar_speed := Vector2(motion.x, motion.z).length()
	var toward_speed := -signf(point.z) * motion.z
	return toward_speed > 0.05 and toward_speed > planar_speed * 0.5

func _apply_pose() -> void:
	for entry in _leaves:
		var leaf: MeshInstance3D = entry.mesh
		leaf.position = entry.closed + Vector3.RIGHT * float(entry.travel) * smoothstep(0.0, 1.0, openness)
		for material in entry.materials:
			material.set_shader_parameter("door_offset_x", leaf.position.x)
		# Both rendering and collision retract into the jamb, even in thin walls.
		var bounds := leaf.get_aabb()
		var left := maxf(-_width * 0.5, leaf.position.x + bounds.position.x)
		var right := minf(_width * 0.5, leaf.position.x + bounds.end.x)
		var collision: CollisionShape3D = entry.shape
		collision.disabled = right - left < 0.005
		var box := collision.shape as BoxShape3D
		box.size = Vector3(maxf(right - left, 0.001), _height - 0.015, 0.17)
		collision.position = Vector3((left + right) * 0.5, (_height + 0.015) * 0.5, 0.0)
