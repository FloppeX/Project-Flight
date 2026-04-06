extends Node

## Floating Origin Manager
## Shifts the world occasionally to keep the camera close to (0,0,0) and avoid float32 precision loss.

signal origin_shifted(offset: Vector3)

@export var enabled: bool = true
@export var threshold_m: float = 4000.0

func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	
	var viewport := get_viewport()
	if not viewport:
		return
	
	var cam := viewport.get_camera_3d()
	if not cam:
		return
	
	var pos := cam.global_position
	var dist_sq := pos.x * pos.x + pos.z * pos.z
	
	if dist_sq > threshold_m * threshold_m:
		var offset := Vector3(pos.x, 0.0, pos.z)
		shift_origin(offset)

func shift_origin(offset: Vector3) -> void:
	var root := get_tree().current_scene
	if not root:
		return
	
	# Shift every Node3D child of current_scene
	for child in root.get_children():
		if child is Node3D:
			child.global_position -= offset
			if child.has_method("reset_physics_interpolation"):
				child.reset_physics_interpolation()
	
	# Notify all systems that cache global coordinates about the shift
	origin_shifted.emit(offset)
	get_tree().call_group("origin_shifter", "apply_origin_shift", offset)
