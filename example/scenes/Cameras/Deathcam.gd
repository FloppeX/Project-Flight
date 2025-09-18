extends Node3D

@export var target_position: Vector3 = Vector3.ZERO
@export var radius: float = 15.0
@export var height: float = 5.0
@export var speed: float = 1.0
@export var duration: float = 10.0
@export var look_offset: Vector3 = Vector3(0, 1, 0)

var _time: float = 0.0
var _camera: Camera3D

func _ready():
	_camera = get_node_or_null("Camera3D")
	if not _camera:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	_camera.current = true
	# Ensure independence from any parent transform hierarchy
	top_level = true

func set_target_position(pos: Vector3) -> void:
	target_position = pos

func _process(delta: float) -> void:
	_time += delta
	var angle = _time * speed
	var offset = Vector3(cos(angle) * radius, height, sin(angle) * radius)
	global_position = target_position + offset
	look_at(target_position + look_offset, Vector3.UP)
	if _time >= duration:
		queue_free()



