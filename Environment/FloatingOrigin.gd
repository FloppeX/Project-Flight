extends Node

## Floating Origin Manager
## Shifts the world occasionally to keep the camera close to (0,0,0) and avoid float32 precision loss.

signal origin_shifted(offset: Vector3)

@export var enabled: bool = true
@export var threshold_m: float = 4000.0
@export var debug_print: bool = false

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

	# RigidBody3D transforms are owned by the physics server. Moving a scene-root
	# parent updates the visible Node3D hierarchy immediately, but a live body can
	# retain its pre-shift physics transform and snap back there on the next tick.
	# Capture the exact translated body transforms before moving the hierarchy so
	# every body is shifted once, including newly-instantiated aircraft that have
	# not reached their _ready() registration yet.
	var rigid_body_targets: Dictionary = {}
	var rigid_bodies: Array[RigidBody3D] = []
	_collect_rigid_bodies(root, rigid_bodies)
	for body in rigid_bodies:
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var target_transform := body.global_transform
		target_transform.origin -= offset
		rigid_body_targets[body] = target_transform
	
	if debug_print:
		print("[FloatingOrigin] Shifting world origin by offset: ", offset)
	# Shift every Node3D child of current_scene
	for child in root.get_children():
		if child is Node3D:
			var old_pos = child.global_position
			child.global_position -= offset
			if child.has_method("reset_physics_interpolation"):
				child.reset_physics_interpolation()
			if debug_print:
				print("[FloatingOrigin]   shifted child '%s' from %s to %s" % [child.name, str(old_pos), str(child.global_position)])

	# Push the translated transforms to both the scene nodes and PhysicsServer3D
	# before another physics step can restore an old position. This is deliberately
	# centralized rather than relying only on per-aircraft group callbacks: group
	# membership begins in _ready(), while an origin shift can happen sooner.
	for body_variant in rigid_body_targets.keys():
		var body := body_variant as RigidBody3D
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var target_transform: Transform3D = rigid_body_targets[body]
		body.global_transform = target_transform
		PhysicsServer3D.body_set_state(
			body.get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM,
			target_transform
		)
		body.reset_physics_interpolation()
	
	# Notify all systems that cache global coordinates about the shift
	origin_shifted.emit(offset)
	get_tree().call_group("origin_shifter", "apply_origin_shift", offset)


func _collect_rigid_bodies(node: Node, bodies: Array[RigidBody3D]) -> void:
	if node is RigidBody3D:
		bodies.append(node as RigidBody3D)
	for child in node.get_children():
		_collect_rigid_bodies(child, bodies)
