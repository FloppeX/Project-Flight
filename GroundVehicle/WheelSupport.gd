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
var rolling_wheels: Array[Dictionary] = []

func setup(host) -> void:
	rest_bases.clear()
	rolling_wheels.clear()
	host._wheel_contact_local_positions.clear()
	for i in host._all_wheel_nodes.size():
		var wheel: Node3D = host._all_wheel_nodes[i]
		rest_bases.append(wheel.basis)
		host._wheel_contact_local_positions.append(_rest_contact(host, i))
		rolling_wheels.append(_prepare_rolling_wheel(host, wheel, i))
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
	for wheel in rolling_wheels:
		wheel["sampled"] = false

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
	_update_wheel_spin(host, delta)


func _prepare_rolling_wheel(host, wheel: Node3D, index: int) -> Dictionary:
	var visuals: Array[Node3D] = []
	var transforms: Array[Transform3D] = []
	var bounds := AABB()
	var has_bounds := false
	# Preserve authored node paths (LOD/replay uses them). Move only branches
	# containing wheel meshes, never the steering pivot or ground-contact marker.
	for child in wheel.get_children():
		if not child is Node3D or child == host._wheel_contact_nodes[index]:
			continue
		var meshes := child.find_children("*", "MeshInstance3D", true, false)
		if child is MeshInstance3D:
			meshes.append(child)
		if meshes.is_empty():
			continue
		visuals.append(child)
		transforms.append(child.transform)
		for mesh: MeshInstance3D in meshes:
			if mesh.mesh == null:
				continue
			var local_transform := wheel.global_transform.affine_inverse() * mesh.global_transform
			var box := local_transform * mesh.mesh.get_aabb()
			bounds = bounds.merge(box) if has_bounds else box
			has_bounds = true
	var center := bounds.get_center() if has_bounds else Vector3.ZERO
	var radius := maxf(bounds.size.y, bounds.size.z) * 0.5 if has_bounds else float(host.WHEEL_RADIUS)
	return {"visuals": visuals, "rest": transforms, "center": center,
		"radius": maxf(radius, 0.01), "angle": 0.0, "sampled": false,
		"axle_in_host": host._wheel_nominal_positions[index] + wheel.basis * center}


func _update_wheel_spin(host, delta: float) -> void:
	if delta <= 0.0:
		return
	for i in rolling_wheels.size():
		var state: Dictionary = rolling_wheels[i]
		var pivot: Node3D = host._all_wheel_nodes[i]
		# Sample a fixed chassis point: suspension travel and stationary steering
		# must not masquerade as rolling, but inner/outer wheels turn differently.
		var axle: Vector3 = host.global_transform * state.axle_in_host
		var support: Variant = null
		for hit in hits:
			if hit.has("body") and (support == null or int(hit.wheel) == i):
				support = hit.body.get_ref()
				if int(hit.wheel) == i:
					break
		if not is_instance_valid(support) or not support.is_inside_tree():
			support = null
		var previous_support: Variant = state.get("support")
		if previous_support is WeakRef:
			previous_support = previous_support.get_ref()
		var distance := 0.0
		if bool(state.sampled) and previous_support == support and host._suspension_has_ground:
			var previous: Vector3 = state.previous_position
			if support != null:
				previous = support.to_global(state.previous_local)
			var displacement := axle - previous
			# Explicit origin invalidation handles normal shifts; this also rejects
			# teleports/reset placement without multiplying the wheel phase wildly.
			if displacement.length() <= maxf(10.0, float(host.max_speed) * delta * 3.0):
				distance = displacement.dot(pivot.global_basis.z.normalized())
		state["previous_position"] = axle
		state["previous_local"] = support.to_local(axle) if support != null else axle
		state["support"] = weakref(support) if support != null else null
		state["sampled"] = true
		if absf(distance) < 0.00001:
			continue
		var radius: float = state.radius * pivot.global_basis.y.length()
		state.angle = fposmod(float(state.angle) + distance / maxf(radius, 0.01), TAU)
		var spin := Basis(Vector3.RIGHT, float(state.angle))
		var center: Vector3 = state.center
		var rotation_about_axle := Transform3D(spin, center - spin * center)
		for j in state.visuals.size():
			var visual: Node3D = state.visuals[j]
			if is_instance_valid(visual):
				visual.transform = rotation_about_axle * state.rest[j]

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
