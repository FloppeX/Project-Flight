extends RefCounted
## Shared ground-vehicle support. Drawing policy is deliberately independent.

var rest_bases: Array[Basis] = []
var hits: Array[Dictionary] = []
var coarse_timer := 0.0
var previous_detail := -1
var last_probe_count := 0
var support_center := Vector3.ZERO
var support_normal := Vector3.UP
var wheel_points := PackedVector3Array()
var wheel_normals := PackedVector3Array()

func setup(host) -> void:
	rest_bases.clear()
	host._wheel_contact_local_positions.clear()
	for i in host._all_wheel_nodes.size():
		var wheel: Node3D = host._all_wheel_nodes[i]
		rest_bases.append(wheel.basis)
		host._wheel_contact_local_positions.append(_rest_contact(host, i))
	coarse_timer = float(host.get_instance_id() % 15) / 100.0

func _rest_contact(host, i: int) -> Vector3:
	var marker: Node3D = host._wheel_contact_nodes[i]
	var offset := marker.position if is_instance_valid(marker) else Vector3(0, -host.WHEEL_RADIUS, 0)
	return host._wheel_nominal_positions[i] + host._all_wheel_nodes[i].basis * offset

func steer(host, angle: float) -> void:
	for wheel in host._front_wheels:
		var i: int = host._all_wheel_nodes.find(wheel)
		if i >= 0 and i < rest_bases.size():
			wheel.basis = Basis(Vector3.UP, angle) * rest_bases[i]
			host._wheel_contact_local_positions[i] = _rest_contact(host, i)

func invalidate(host) -> void:
	hits.clear()
	host._suspension_probe_ready = false
	previous_detail = -1

func refresh(host, physical_only: bool = false, coarse: bool = false) -> void:
	hits.clear()
	last_probe_count = 0
	var params := PhysicsRayQueryParameters3D.new()
	params.exclude = [host.get_rid()]
	var count: int = host._all_wheel_nodes.size()
	var coarse_indices := [0, maxi(count / 2 - 1, 0), count / 2]
	for i in count:
		if coarse and not i in coarse_indices: continue
		var contact: Vector3 = host.to_global(host._wheel_contact_local_positions[i])
		params.from = contact + Vector3.UP * 5.0
		params.to = contact - Vector3.UP * host.wheel_probe_down_m
		var hit: Dictionary = host.get_world_3d().direct_space_state.intersect_ray(params)
		last_probe_count += 1
		if not hit.is_empty():
			var body: Variant = hit.get("collider")
			var sample := {"position": hit.position, "normal": hit.normal, "wheel": i}
			if body is Node3D:
				sample["body"] = weakref(body)
				sample["local_position"] = body.to_local(hit.position)
				sample["local_normal"] = body.global_basis.transposed() * hit.normal
			hits.append(sample)
		elif not physical_only:
			var h: float = TerrainNavGrid.sample_height(contact.x, contact.z)
			if h > TerrainNavGrid.IMPASSABLE * 0.5:
				hits.append({"position": Vector3(contact.x, h, contact.z), "normal": Vector3.UP, "wheel": i})
	host._suspension_probe_ready = true
	_update_targets(host)

func _live_hit(sample: Dictionary) -> Dictionary:
	if not sample.has("body"): return sample
	var body: Variant = sample.body.get_ref()
	if not is_instance_valid(body) or not body.is_inside_tree(): return {}
	return {"position": body.to_global(sample.local_position),
		"normal": (body.global_basis.inverse().transposed() * sample.local_normal).normalized(), "wheel": sample.wheel}

func _update_targets(host) -> void:
	var points: Array[Dictionary] = []
	var center := Vector3.ZERO
	var normal := Vector3.ZERO
	for sample in hits:
		var live := _live_hit(sample)
		if live.is_empty(): continue
		points.append(live)
		center += live.position
		normal += live.normal
	host._suspension_has_ground = not points.is_empty()
	host._cached_corner_target_ys.clear()
	host._cached_wheel_target_ys.clear()
	if points.is_empty():
		for nominal in host._wheel_nominal_positions: host._cached_wheel_target_ys.append(nominal.y - host.wheel_max_extension_m)
		return
	center /= points.size()
	normal = normal.normalized()
	# Least-squares support plane, shared by chassis and coarse wheel poses.
	var xx := 0.0
	var zz := 0.0
	var xz := 0.0
	var xy := 0.0
	var zy := 0.0
	for point in points:
		var d: Vector3 = point.position - center
		xx += d.x * d.x
		zz += d.z * d.z
		xz += d.x * d.z
		xy += d.x * d.y
		zy += d.z * d.y
	var det := xx * zz - xz * xz
	if points.size() >= 3 and det > 0.001:
		normal = Vector3(-(xy * zz - zy * xz) / det, 1, -(zy * xx - xy * xz) / det).normalized()
	if normal.y < 0.1: normal = Vector3.UP
	support_center = center
	support_normal = normal
	var yaw: float = atan2(host.global_basis.z.x, host.global_basis.z.z)
	var flat := Basis(Vector3.UP, yaw)
	for corner in host._corner_probes:
		var point: Vector3 = host.global_position + flat * corner
		var h := center.y - (normal.x * (point.x - center.x) + normal.z * (point.z - center.z)) / normal.y
		host._cached_corner_target_ys.append(h + host.chassis_ride_height_m)
	wheel_points.resize(host._all_wheel_nodes.size())
	wheel_normals.resize(host._all_wheel_nodes.size())
	wheel_points.fill(center)
	wheel_normals.fill(normal)
	for sample in points:
		wheel_points[sample.wheel] = sample.position
		wheel_normals[sample.wheel] = sample.normal
	_project_wheels(host)

func _project_wheels(host) -> void:
	var transform: Transform3D = host.global_transform
	var axis := transform.basis.y
	var contacts: Array = host._wheel_contact_local_positions
	var nominal: Array = host._wheel_nominal_positions
	var extension: float = host.wheel_max_extension_m
	var compression: float = host.wheel_max_compression_m
	var targets: Array[float] = []
	for i in contacts.size():
		var contact: Vector3 = transform * contacts[i]
		var surface_point := wheel_points[i]
		var surface_normal := wheel_normals[i]
		var denominator := axis.dot(surface_normal)
		var travel: float = -extension
		if denominator > 0.1:
			travel = clampf((surface_point - contact).dot(surface_normal) / denominator,
				-extension, compression)
		targets.append(nominal[i].y + travel)
	host._cached_wheel_target_ys = targets

func update(host, delta: float, detailed: bool, physical_only: bool = false) -> void:
	var tier := 1 if detailed else 0
	if tier != previous_detail:
		host._suspension_probe_ready = false
		previous_detail = tier
	coarse_timer -= delta
	var due: bool = not host._suspension_probe_ready
	if detailed: due = due or host._should_refresh_suspension_probes()
	else: due = due or coarse_timer <= 0.0
	if due:
		refresh(host, physical_only, not detailed)
		coarse_timer = host.distant_support_interval_s
	elif physical_only:
		_update_targets(host)
	if not host._suspension_has_ground:
		host._spring_velocity_y = maxf(host._spring_velocity_y - host.GRAVITY * delta, -50.0)
		_apply_wheels(host, delta)
		return
	_integrate_chassis(host, delta)
	# Chassis integration changes the suspension axes. Reproject cached world
	# contacts now, not using stale local targets from the previous pose.
	if detailed: _project_wheels(host)
	_apply_wheels(host, delta)

func _apply_wheels(host, delta: float) -> void:
	var blend := 1.0 - exp(-host.wheel_suspension_smoothing * delta)
	for i in host._all_wheel_nodes.size():
		host._all_wheel_nodes[i].position.y = lerpf(host._all_wheel_nodes[i].position.y, host._cached_wheel_target_ys[i], blend)
	if host._body_node:
		host._body_node.position = host._body_rest_position
		host._body_node.rotation = host._body_rest_rotation

func _integrate_chassis(host, delta: float) -> void:
	var targets: Array = host._cached_corner_target_ys
	var target_y: float = (targets[0] + targets[1] + targets[2] + targets[3]) * 0.25
	var target_pitch: float = atan2((targets[2] + targets[3] - targets[0] - targets[1]) * 0.5, host._corner_half_z * 2.0)
	var target_roll: float = atan2((targets[1] + targets[3] - targets[0] - targets[2]) * 0.5, host._corner_half_x * 2.0)
	if not host._spring_initialized:
		host.global_position.y = target_y
		host._spring_velocity_y = 0.0
		host._spring_pitch_velocity = 0.0
		host._spring_roll_velocity = 0.0
		host._spring_initialized = true
	var yaw: float = atan2(host.global_basis.z.x, host.global_basis.z.z)
	var pitch: float = asin(clampf(-host.global_basis.z.y, -1.0, 1.0))
	var roll: float = atan2(host.global_basis.x.y, host.global_basis.y.y)
	# Preserve authored spring settings; substep coarse ticks for stability.
	var steps := maxi(int(ceil(delta / (1.0 / 60.0))), 1)
	var dt := delta / steps
	for _step in steps:
		host._spring_velocity_y += (-host.spring_stiffness * (host.global_position.y - target_y) - host.spring_damping * host._spring_velocity_y) * dt
		host._spring_velocity_y = clampf(host._spring_velocity_y, -50, 50)
		host._spring_pitch_velocity += (-host.spring_tilt_stiffness * (pitch - target_pitch) - host.spring_tilt_damping * host._spring_pitch_velocity) * dt
		host._spring_roll_velocity += (-host.spring_tilt_stiffness * (roll - target_roll) - host.spring_tilt_damping * host._spring_roll_velocity) * dt
		host._spring_pitch_velocity = clampf(host._spring_pitch_velocity, -5, 5)
		host._spring_roll_velocity = clampf(host._spring_roll_velocity, -5, 5)
		pitch += host._spring_pitch_velocity * dt
		roll += host._spring_roll_velocity * dt
	host.global_basis = Basis.from_euler(Vector3(pitch, yaw, roll), EULER_ORDER_YXZ).orthonormalized()
