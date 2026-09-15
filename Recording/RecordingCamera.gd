extends Camera3D
## Camera motion is independent of the subject and of the replay clock.
enum Attachment { WORLD, POSITION, HEADING, FULL }
var attachment := Attachment.WORLD
var target: Node3D
var aim_target: Node3D
var offset := Transform3D.IDENTITY
var move_speed := 25.0
var smoothing := 10.0
var motion := Vector3.ZERO
var interpolated_target := false
## Opt-in for live mounted filming: smoothing and yaw travel with the mount.
## Replay/free-camera behavior stays unchanged unless explicitly enabled.
var attachment_local_controls := false

func _init() -> void:
	# This camera follows a replay/process clock, not the live physics clock.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func anchor() -> Transform3D:
	if attachment == Attachment.WORLD or not is_instance_valid(target): return Transform3D.IDENTITY
	var target_frame := target.get_global_transform_interpolated() if interpolated_target else target.global_transform
	var basis := Basis.IDENTITY
	if attachment == Attachment.FULL:
		basis = target_frame.basis.orthonormalized()
	elif attachment == Attachment.HEADING:
		var forward := target_frame.basis.z
		basis = Basis(Vector3.UP, atan2(forward.x, forward.z))
	return Transform3D(basis, target_frame.origin)

func attach(subject: Node3D, mode: int) -> void:
	var previous := global_transform
	target = subject
	attachment = mode
	offset = anchor().affine_inverse() * previous
	global_transform = previous # Attachment changes never snap the shot.

func move_camera(direction: Vector3, look: Vector2, roll: float, delta: float) -> void:
	if attachment != Attachment.WORLD and not is_instance_valid(target):
		attach(null, Attachment.WORLD)
	var frame := anchor()
	if attachment_local_controls and attachment == Attachment.FULL and is_instance_valid(target):
		# Integrate only the operator's motion in the attachment frame. World
		# velocity smoothing lags behind a turning vehicle, while world-UP yaw
		# changes its meaning as the vehicle banks. Neither belongs in this rig.
		var wanted_local := offset.basis * direction.limit_length() * move_speed
		motion = motion.lerp(wanted_local, 1.0 - exp(-smoothing * delta))
		offset.origin += motion * delta
		offset.basis = Basis(Vector3.UP, -look.x) * offset.basis
		offset.basis = (offset.basis * Basis(Vector3.RIGHT, -look.y) * Basis(Vector3.BACK, roll * delta)).orthonormalized()
		global_transform = frame * offset
		return
	var pose := frame * offset
	var wanted := pose.basis * direction.limit_length() * move_speed
	motion = motion.lerp(wanted, 1.0 - exp(-smoothing * delta))
	pose.origin += motion * delta
	pose.basis = Basis(Vector3.UP, -look.x) * pose.basis
	pose.basis = pose.basis * Basis(Vector3.RIGHT, -look.y) * Basis(Vector3.BACK, roll * delta)
	pose.basis = pose.basis.orthonormalized()
	offset = frame.affine_inverse() * pose
	global_transform = pose
	if is_instance_valid(aim_target) and global_position.distance_squared_to(aim_target.global_position) > 0.01:
		var direction_to_target := (aim_target.global_position - global_position).normalized()
		if absf(direction_to_target.dot(Vector3.UP)) < 0.999:
			look_at(aim_target.global_position, Vector3.UP)
			offset = frame.affine_inverse() * global_transform

func shot_key(time: float, subject_index: int) -> Dictionary:
	return {"time": time, "pose": offset, "fov": fov, "mode": attachment,
		"subject": subject_index, "aim": is_instance_valid(aim_target)}

func apply_keys(keys: Array, time: float, subjects: Array) -> void:
	if keys.is_empty(): return
	var a: Dictionary = keys[0]
	var b: Dictionary = keys.back()
	for index in range(keys.size() - 1):
		if time <= float(keys[index + 1].time):
			a = keys[index]
			b = keys[index + 1]
			break
	if time >= float(keys.back().time): a = keys.back()
	var weight := clampf((time - float(a.time)) / maxf(float(b.time) - float(a.time), 0.0001), 0.0, 1.0)
	# Different attachment spaces represent a cut, not a nonsensical local blend.
	if a.mode != b.mode or a.subject != b.subject: weight = 0.0
	attachment = int(a.mode)
	var index := int(a.subject)
	target = subjects[index] if index >= 0 and index < subjects.size() else null
	aim_target = target if bool(a.aim) else null
	offset = (a.pose as Transform3D).interpolate_with(b.pose, weight)
	fov = lerpf(float(a.fov), float(b.fov), weight)
	motion = Vector3.ZERO
	move_camera(Vector3.ZERO, Vector2.ZERO, 0.0, 0.0)
