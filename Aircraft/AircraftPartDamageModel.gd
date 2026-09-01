extends Node
class_name AircraftPartDamageModel

## Localized aircraft damage routed from the owning CollisionObject3D's shape index.
## Visual nodes that are separate meshes can be released as physical debris when
## their zone reaches zero health.

signal zone_damaged(zone: StringName, damage_amount: float, health: float, max_health: float)
signal zone_destroyed(zone: StringName)

const ZONE_LEFT_WING: StringName = &"left_wing"
const ZONE_RIGHT_WING: StringName = &"right_wing"
const ZONE_FUSELAGE: StringName = &"fuselage"
const ZONE_COCKPIT: StringName = &"cockpit"
const ZONE_HORIZONTAL_STABILIZER: StringName = &"horizontal_stabilizer"
const ZONE_VERTICAL_STABILIZER: StringName = &"vertical_stabilizer"
const ZONE_TAIL_SECTION: StringName = &"tail_section"
const ZONE_ORDER: Array[StringName] = [
	ZONE_LEFT_WING,
	ZONE_RIGHT_WING,
	ZONE_FUSELAGE,
	ZONE_COCKPIT,
	ZONE_HORIZONTAL_STABILIZER,
	ZONE_VERTICAL_STABILIZER,
]

@export_group("Collision zones")
@export var left_wing_collider_path: NodePath = NodePath("../LeftWingDamageCollider")
@export var right_wing_collider_path: NodePath = NodePath("../RightWingDamageCollider")
@export var fuselage_collider_path: NodePath = NodePath("../FuselageDamageCollider")
@export var cockpit_collider_path: NodePath = NodePath("../CockpitDamageCollider")
@export var horizontal_stabilizer_collider_path: NodePath = NodePath("../HorizontalStabilizerDamageCollider")
@export var vertical_stabilizer_collider_path: NodePath = NodePath("../VerticalStabilizerDamageCollider")

@export_group("Detachable visuals")
@export var left_wing_visual_paths: Array[NodePath] = []
@export var right_wing_visual_paths: Array[NodePath] = []
@export var cockpit_visual_paths: Array[NodePath] = []
@export var horizontal_stabilizer_visual_paths: Array[NodePath] = []
@export var vertical_stabilizer_visual_paths: Array[NodePath] = []
## Optional common tail structure. It is not a seventh damage pool: it breaks
## away only after both stabilizer regions have been destroyed.
@export var tail_section_visual_paths: Array[NodePath] = []
@export var align_companion_wing_visuals_to_outer_fold: bool = false

@export_group("Zone health")
@export_range(0.05, 2.0, 0.05) var region_health_fraction_of_legacy_total: float = 0.5

@export_group("Failure behavior")
@export var detached_part_lifetime_s: float = 20.0
@export var detached_part_impulse_mps: float = 7.0
@export var single_wing_loss_roll_torque_per_kg: float = 36.0
@export var wing_loss_max_roll_rate_deg_s: float = 180.0
@export var wing_loss_max_pitch_rate_deg_s: float = 120.0
@export var wing_loss_max_yaw_rate_deg_s: float = 90.0
@export_range(0.0, 1.0, 0.05) var wing_loss_roll_authority_scale: float = 0.0
## Optional terminal wing-loss behavior for aircraft whose remaining geometry
## cannot plausibly retain any useful flight control.
@export var wing_loss_disable_all_control_inputs: bool = true
@export var wing_loss_drag_accel_at_100_mps: float = 7.0
@export var wing_loss_max_drag_accel_mps2: float = 24.0
@export var wing_loss_turbulence_torque_per_kg: float = 0.9
@export_range(0.0, 1.0, 0.05) var wing_loss_buffet_intensity: float = 0.9
@export var wing_loss_pitch_tumble_torque_per_kg: float = 14.0
@export var wing_loss_yaw_spin_torque_per_kg: float = 11.0
@export var wing_loss_side_accel_at_100_mps: float = 6.0
@export var wing_loss_sink_accel_at_100_mps: float = 5.0
@export var wing_loss_max_departure_accel_mps2: float = 18.0
@export_range(0.0, 1.0, 0.05) var horizontal_stabilizer_control_scale: float = 0.1
@export_range(0.0, 1.0, 0.05) var vertical_stabilizer_control_scale: float = 0.1

var _aircraft: RigidBody3D
var _zone_health: Dictionary = {}
var _zone_max_health: Dictionary = {}
var _zone_colliders: Dictionary = {}
var _zone_visual_paths: Dictionary = {}
var _destroyed_zones: Dictionary = {}
var _turbulence_phase_s: float = 0.0
var _tail_section_detached: bool = false


func _ready() -> void:
	_aircraft = get_parent() as RigidBody3D
	if _aircraft == null:
		push_error("[AircraftPartDamageModel] Parent must be a RigidBody3D aircraft")
		set_physics_process(false)
		return
	_cache_configuration()
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _aircraft == null or not is_instance_valid(_aircraft):
		set_physics_process(false)
		return
	var lost_wing_count := int(is_zone_destroyed(ZONE_LEFT_WING)) \
		+ int(is_zone_destroyed(ZONE_RIGHT_WING))
	if lost_wing_count <= 0:
		_set_structural_airflow_feedback(0.0, 0.0)
		set_physics_process(false)
		return
	if wing_loss_disable_all_control_inputs:
		_neutralize_all_flight_control_inputs()
	var imbalance := 0.0
	if is_zone_destroyed(ZONE_LEFT_WING):
		imbalance -= 1.0
	if is_zone_destroyed(ZONE_RIGHT_WING):
		imbalance += 1.0
	_aircraft.set_meta("wing_failure_roll_direction", imbalance)
	var velocity := _aircraft.linear_velocity
	var speed := velocity.length()
	var forward_axis := _aircraft.global_transform.basis.z.normalized()
	var right_axis := _aircraft.global_transform.basis.x.normalized()
	var up_axis := _aircraft.global_transform.basis.y.normalized()
	_limit_wing_failure_angular_velocity()
	if not is_zero_approx(imbalance):
		# In the rendered aircraft convention, a missing right wing rolls around
		# +local Z; a missing left wing mirrors it around -local Z.
		var expected_roll_rate := _aircraft.angular_velocity.dot(forward_axis) * imbalance
		var roll_torque_scale := clampf(
			(
				deg_to_rad(wing_loss_max_roll_rate_deg_s)
				- expected_roll_rate
			) / deg_to_rad(60.0),
			0.0,
			1.0
		)
		_aircraft.apply_torque(
			(
				forward_axis * imbalance * single_wing_loss_roll_torque_per_kg
				* roll_torque_scale * _aircraft.mass
			)
		)
	var drag_accel := 0.0
	if speed > 0.1:
		drag_accel = minf(
			wing_loss_drag_accel_at_100_mps * pow(speed / 100.0, 2.0) * float(lost_wing_count),
			wing_loss_max_drag_accel_mps2
		)
		_aircraft.apply_central_force(-velocity.normalized() * drag_accel * _aircraft.mass)
	_aircraft.set_meta("structural_damage_drag_accel_mps2", drag_accel)
	_turbulence_phase_s += delta
	var turbulence_speed_scale := clampf(speed / 45.0, 0.2, 1.6)
	var pitch_tumble_wave := 0.72 + sin(_turbulence_phase_s * 5.7 + imbalance * 0.8) * 0.28
	var yaw_spin_wave := imbalance * 0.7 + sin(_turbulence_phase_s * 7.9 + 1.1) * 0.3
	_aircraft.apply_torque(
		(
			right_axis * pitch_tumble_wave * wing_loss_pitch_tumble_torque_per_kg
			+ up_axis * yaw_spin_wave * wing_loss_yaw_spin_torque_per_kg
		) * turbulence_speed_scale * _aircraft.mass
	)
	var departure_speed_scale := clampf(pow(speed / 100.0, 2.0), 0.0, 3.0)
	var side_accel := minf(
		wing_loss_side_accel_at_100_mps * departure_speed_scale * float(lost_wing_count),
		wing_loss_max_departure_accel_mps2
	)
	var sink_accel := minf(
		wing_loss_sink_accel_at_100_mps * departure_speed_scale * float(lost_wing_count),
		wing_loss_max_departure_accel_mps2
	)
	var departure_acceleration := right_axis * imbalance * side_accel - up_axis * sink_accel
	_aircraft.apply_central_force(departure_acceleration * _aircraft.mass)
	_aircraft.set_meta("wing_failure_departure_acceleration", departure_acceleration)
	var turbulence := (
		forward_axis * sin(_turbulence_phase_s * 19.0)
		+ right_axis * sin(_turbulence_phase_s * 13.0 + 1.7) * 0.45
		+ up_axis * sin(_turbulence_phase_s * 23.0 + 0.6) * 0.3
	) * wing_loss_turbulence_torque_per_kg * turbulence_speed_scale * _aircraft.mass
	_aircraft.apply_torque(turbulence)
	_set_structural_airflow_feedback(drag_accel, wing_loss_buffet_intensity)


func take_damage_at(
	damage_amount: float,
	world_position: Vector3 = Vector3.INF,
	local_shape_index: int = -1
) -> StringName:
	var zone := resolve_zone_from_hit(world_position, local_shape_index)
	if zone == StringName():
		zone = ZONE_FUSELAGE
	damage_zone(zone, damage_amount)
	return zone


func damage_zone(zone: StringName, damage_amount: float) -> bool:
	if damage_amount <= 0.0 or not _zone_health.has(zone) or is_zone_destroyed(zone):
		return false
	var zone_max := float(_zone_max_health[zone])
	var previous_health := float(_zone_health[zone])
	var applied_damage := minf(damage_amount, previous_health)
	var new_health := maxf(previous_health - damage_amount, 0.0)
	_zone_health[zone] = new_health
	zone_damaged.emit(zone, applied_damage, new_health, zone_max)

	if new_health <= 0.0:
		_destroy_zone(zone)
	return true


func resolve_zone_from_hit(world_position: Vector3, local_shape_index: int = -1) -> StringName:
	var shape_node := _shape_node_for_local_index(local_shape_index)
	if shape_node != null:
		var indexed_zone := _zone_for_collider(shape_node)
		if indexed_zone != StringName() and not is_zone_destroyed(indexed_zone):
			return indexed_zone

	if not _is_finite_position(world_position):
		return ZONE_FUSELAGE
	var best_zone: StringName = StringName()
	var best_distance := INF
	for zone in ZONE_ORDER:
		if is_zone_destroyed(zone):
			continue
		var collider := _zone_colliders.get(zone) as CollisionShape3D
		if collider == null or not is_instance_valid(collider) or collider.disabled or collider.shape == null:
			continue
		var distance := _distance_to_collider(world_position, collider)
		if distance < best_distance:
			best_distance = distance
			best_zone = zone
	return best_zone


func get_zone_health(zone: StringName) -> float:
	return float(_zone_health.get(zone, 0.0))


func get_zone_max_health(zone: StringName) -> float:
	return float(_zone_max_health.get(zone, 0.0))


func is_zone_destroyed(zone: StringName) -> bool:
	return bool(_destroyed_zones.get(zone, false))


func get_damage_state() -> Dictionary:
	var state: Dictionary = {}
	for zone in ZONE_ORDER:
		state[zone] = {
			"health": get_zone_health(zone),
			"max_health": get_zone_max_health(zone),
			"destroyed": is_zone_destroyed(zone),
		}
	return state


func _cache_configuration() -> void:
	var legacy_total_health := 100.0
	if "max_health" in _aircraft:
		legacy_total_health = maxf(float(_aircraft.get("max_health")), 1.0)
	var regional_health := maxf(
		legacy_total_health * region_health_fraction_of_legacy_total,
		1.0
	)
	_zone_max_health = {
		ZONE_LEFT_WING: regional_health,
		ZONE_RIGHT_WING: regional_health,
		ZONE_FUSELAGE: regional_health,
		ZONE_COCKPIT: regional_health,
		ZONE_HORIZONTAL_STABILIZER: regional_health,
		ZONE_VERTICAL_STABILIZER: regional_health,
	}
	_zone_health = _zone_max_health.duplicate(true)
	_destroyed_zones.clear()
	_zone_colliders = {
		ZONE_LEFT_WING: get_node_or_null(left_wing_collider_path),
		ZONE_RIGHT_WING: get_node_or_null(right_wing_collider_path),
		ZONE_FUSELAGE: get_node_or_null(fuselage_collider_path),
		ZONE_COCKPIT: get_node_or_null(cockpit_collider_path),
		ZONE_HORIZONTAL_STABILIZER: get_node_or_null(horizontal_stabilizer_collider_path),
		ZONE_VERTICAL_STABILIZER: get_node_or_null(vertical_stabilizer_collider_path),
	}
	_zone_visual_paths = {
		ZONE_LEFT_WING: left_wing_visual_paths,
		ZONE_RIGHT_WING: right_wing_visual_paths,
		ZONE_COCKPIT: cockpit_visual_paths,
		ZONE_HORIZONTAL_STABILIZER: horizontal_stabilizer_visual_paths,
		ZONE_VERTICAL_STABILIZER: vertical_stabilizer_visual_paths,
		ZONE_TAIL_SECTION: tail_section_visual_paths,
	}
	_tail_section_detached = false
	_aircraft.set_meta("regional_damage_enabled", true)
	_aircraft.set_meta("legacy_total_hit_points", legacy_total_health)
	_aircraft.set_meta("region_max_hit_points", regional_health)
	for zone in ZONE_ORDER:
		var collider := _zone_colliders.get(zone) as CollisionShape3D
		if collider == null:
			push_warning("[AircraftPartDamageModel] Missing collider for %s" % zone)
			continue
		collider.set_meta("damage_zone", zone)


func _shape_node_for_local_index(local_shape_index: int) -> CollisionShape3D:
	if _aircraft == null or local_shape_index < 0:
		return null
	var owner_id := _aircraft.shape_find_owner(local_shape_index)
	if owner_id < 0:
		return null
	return _aircraft.shape_owner_get_owner(owner_id) as CollisionShape3D


func _zone_for_collider(collider: CollisionShape3D) -> StringName:
	if collider == null:
		return StringName()
	var meta_zone: Variant = collider.get_meta("damage_zone", StringName())
	if meta_zone is StringName and meta_zone != StringName():
		return meta_zone as StringName
	if meta_zone is String and not String(meta_zone).is_empty():
		return StringName(meta_zone)
	for zone in ZONE_ORDER:
		if _zone_colliders.get(zone) == collider:
			return zone
	return StringName()


func _distance_to_collider(world_position: Vector3, collider: CollisionShape3D) -> float:
	var local_point := collider.global_transform.affine_inverse() * world_position
	var shape := collider.shape
	var local_distance := local_point.length()
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5
		var outside := Vector3(
			maxf(absf(local_point.x) - half_size.x, 0.0),
			maxf(absf(local_point.y) - half_size.y, 0.0),
			maxf(absf(local_point.z) - half_size.z, 0.0)
		)
		local_distance = outside.length()
	elif shape is SphereShape3D:
		local_distance = maxf(local_point.length() - (shape as SphereShape3D).radius, 0.0)
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var segment_half := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		var closest_y := clampf(local_point.y, -segment_half, segment_half)
		local_distance = maxf(local_point.distance_to(Vector3(0.0, closest_y, 0.0)) - capsule.radius, 0.0)
	elif shape is ConvexPolygonShape3D:
		var points := (shape as ConvexPolygonShape3D).points
		if not points.is_empty():
			var bounds := AABB(points[0], Vector3.ZERO)
			for point_index in range(1, points.size()):
				bounds = bounds.expand(points[point_index])
			var bounds_end := bounds.end
			var outside := Vector3(
				maxf(maxf(bounds.position.x - local_point.x, local_point.x - bounds_end.x), 0.0),
				maxf(maxf(bounds.position.y - local_point.y, local_point.y - bounds_end.y), 0.0),
				maxf(maxf(bounds.position.z - local_point.z, local_point.z - bounds_end.z), 0.0)
			)
			local_distance = outside.length()
	var collider_scale := collider.global_transform.basis.get_scale().abs()
	return local_distance * minf(collider_scale.x, minf(collider_scale.y, collider_scale.z))


func _destroy_zone(zone: StringName) -> void:
	if is_zone_destroyed(zone):
		return
	_destroyed_zones[zone] = true
	var collider := _zone_colliders.get(zone) as CollisionShape3D
	if collider != null and is_instance_valid(collider):
		collider.set_deferred("disabled", true)
	if _aircraft != null and is_instance_valid(_aircraft):
		_aircraft.set_meta("destroyed_part_%s" % zone, true)
	_detach_zone_visuals(zone)
	_apply_zone_failure(zone)
	_try_detach_tail_section()
	zone_destroyed.emit(zone)


func _try_detach_tail_section() -> void:
	if _tail_section_detached or tail_section_visual_paths.is_empty():
		return
	if not is_zone_destroyed(ZONE_HORIZONTAL_STABILIZER) \
	or not is_zone_destroyed(ZONE_VERTICAL_STABILIZER):
		return
	_tail_section_detached = true
	if _aircraft != null and is_instance_valid(_aircraft):
		_aircraft.set_meta("destroyed_part_tail_section", true)
	_detach_zone_visuals(ZONE_TAIL_SECTION)


func _detach_zone_visuals(zone: StringName) -> void:
	var paths_variant: Variant = _zone_visual_paths.get(zone, [])
	if not (paths_variant is Array):
		return
	var visuals: Array[MeshInstance3D] = []
	for path_variant in paths_variant:
		var path := path_variant as NodePath
		var visual := get_node_or_null(path) as MeshInstance3D
		if visual == null or not is_instance_valid(visual) or not visual.visible:
			continue
		visuals.append(visual)
		if zone == ZONE_COCKPIT:
			var canopy_visibility := _aircraft.get_node_or_null("CockpitCanopyVisibility")
			if canopy_visibility != null and canopy_visibility.has_method("release_canopy"):
				canopy_visibility.call("release_canopy", visual)
	if visuals.is_empty():
		return
	_align_wing_break_sections(zone, visuals)
	_spawn_visual_debris(visuals, zone)
	for visual in visuals:
		visual.visible = false
		visual.set_meta("damage_detached", true)
		_hide_decals_following(visual)


func _align_wing_break_sections(zone: StringName, visuals: Array[MeshInstance3D]) -> void:
	if not align_companion_wing_visuals_to_outer_fold:
		return
	if zone != ZONE_LEFT_WING and zone != ZONE_RIGHT_WING:
		return
	if visuals.size() < 2:
		return
	var outer_wing := visuals[0]
	var wing_parent := outer_wing.get_parent() as Node3D
	if wing_parent == null:
		return
	var rest_local_variant: Variant = outer_wing.get_meta("livery_rest_transform_local", outer_wing.transform)
	if not (rest_local_variant is Transform3D):
		return
	var rest_global := wing_parent.global_transform * (rest_local_variant as Transform3D)
	var fold_motion := outer_wing.global_transform * rest_global.affine_inverse()
	for visual_index in range(1, visuals.size()):
		var companion := visuals[visual_index]
		companion.global_transform = fold_motion * companion.global_transform


func _spawn_visual_debris(sources: Array[MeshInstance3D], zone: StringName) -> void:
	if _aircraft == null or sources.is_empty():
		return
	var debris_parent := _aircraft.get_parent()
	if debris_parent == null:
		return
	var anchor := sources[0]
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var debris_basis := anchor.global_transform.basis.orthonormalized()
	var preliminary_origin := anchor.global_transform * anchor.get_aabb().get_center()
	var preliminary_transform := Transform3D(debris_basis, preliminary_origin)
	var combined_bounds := AABB()
	var has_bounds := false
	for source in sources:
		if source == null or not is_instance_valid(source) or source.mesh == null or not source.is_inside_tree():
			continue
		var source_in_preliminary := preliminary_transform.affine_inverse() * source.global_transform
		var source_bounds := source.get_aabb()
		for x_index in range(2):
			for y_index in range(2):
				for z_index in range(2):
					var corner := source_bounds.position + Vector3(
						source_bounds.size.x * float(x_index),
						source_bounds.size.y * float(y_index),
						source_bounds.size.z * float(z_index)
					)
					var point := source_in_preliminary * corner
					if not has_bounds:
						combined_bounds = AABB(point, Vector3.ZERO)
						has_bounds = true
					else:
						combined_bounds = combined_bounds.expand(point)
	if not has_bounds:
		return
	var debris_transform := preliminary_transform
	debris_transform.origin = preliminary_transform * combined_bounds.get_center()

	var debris := RigidBody3D.new()
	debris.name = "Detached%s" % _zone_display_name(zone)
	debris.collision_layer = 1
	debris.collision_mask = _aircraft.collision_mask
	debris.continuous_cd = true
	debris_parent.add_child(debris)
	debris.global_transform = debris_transform
	debris.add_collision_exception_with(_aircraft)

	var total_volume := 0.0
	var added_meshes := 0
	for source in sources:
		if source == null or not is_instance_valid(source) or source.mesh == null:
			continue
		var source_bounds := source.get_aabb()
		if source_bounds.size.length_squared() <= 0.0001:
			continue
		var source_in_debris := debris_transform.affine_inverse() * source.global_transform
		var detached_mesh := source.duplicate() as MeshInstance3D
		if detached_mesh == null:
			continue
		var source_label := String(source.name).to_pascal_case()
		detached_mesh.name = "%sMesh" % source_label
		detached_mesh.transform = source_in_debris
		detached_mesh.visible = true
		debris.add_child(detached_mesh)
		_copy_following_decals_to_debris(source, debris)

		var source_scale := source_in_debris.basis.get_scale().abs()
		var debris_shape := CollisionShape3D.new()
		debris_shape.name = "%sCollider" % source_label
		var box := BoxShape3D.new()
		box.size = source_bounds.size * source_scale
		debris_shape.shape = box
		debris_shape.transform = Transform3D(
			source_in_debris.basis.orthonormalized(),
			source_in_debris * source_bounds.get_center()
		)
		debris.add_child(debris_shape)
		total_volume += box.size.x * box.size.y * box.size.z
		added_meshes += 1
	if added_meshes == 0:
		debris.queue_free()
		return
	debris.mass = clampf(total_volume * 12.0, 8.0, 120.0)

	var offset := debris_transform.origin - _aircraft.global_position
	debris.linear_velocity = _aircraft.linear_velocity + _aircraft.angular_velocity.cross(offset)
	debris.angular_velocity = _aircraft.angular_velocity
	var outward := offset.normalized()
	if outward.length_squared() <= 0.0001:
		outward = Vector3.UP
	outward = (outward + Vector3.UP * 0.25).normalized()
	debris.apply_central_impulse(outward * detached_part_impulse_mps * debris.mass)

	if detached_part_lifetime_s > 0.0:
		var debris_ref: WeakRef = weakref(debris)
		get_tree().create_timer(detached_part_lifetime_s).timeout.connect(func() -> void:
			var debris_object: Object = debris_ref.get_ref()
			if debris_object is Node and is_instance_valid(debris_object):
				(debris_object as Node).queue_free()
		)


func _copy_following_decals_to_debris(source: Node3D, debris: RigidBody3D) -> void:
	if _aircraft == null:
		return
	for candidate: Node in _aircraft.find_children("*", "Decal", true, false):
		var decal := candidate as Decal
		if decal == null or not decal.visible:
			continue
		var follow_target: Variant = decal.get("_follow_target")
		if typeof(follow_target) != TYPE_OBJECT or follow_target != source:
			continue
		var decal_global := decal.global_transform
		var detached_decal := decal.duplicate() as Decal
		if detached_decal == null:
			continue
		detached_decal.name = "%sDebris" % decal.name
		detached_decal.set_script(null)
		detached_decal.set_process(false)
		debris.add_child(detached_decal)
		detached_decal.global_transform = decal_global
		detached_decal.visible = true


func _hide_decals_following(detached_visual: Node3D) -> void:
	if _aircraft == null:
		return
	for candidate: Node in _aircraft.find_children("*", "Decal", true, false):
		var decal := candidate as Decal
		if decal == null:
			continue
		var follow_target: Variant = decal.get("_follow_target")
		if typeof(follow_target) == TYPE_OBJECT and follow_target == detached_visual:
			decal.visible = false
			decal.set_process(false)


func _apply_zone_failure(zone: StringName) -> void:
	if _aircraft == null or not is_instance_valid(_aircraft):
		return
	var aero := _aircraft.get_node_or_null("SimpleAero")
	match zone:
		ZONE_LEFT_WING, ZONE_RIGHT_WING:
			var lost_wing_count := int(is_zone_destroyed(ZONE_LEFT_WING)) \
				+ int(is_zone_destroyed(ZONE_RIGHT_WING))
			if aero != null and lost_wing_count == 1:
				if wing_loss_disable_all_control_inputs:
					for power_property: StringName in [&"pitch_power", &"roll_power", &"yaw_power"]:
						if power_property in aero:
							aero.set(power_property, 0.0)
					if "simplified_pitch_power_override" in aero:
						aero.set("simplified_pitch_power_override", 0.0)
				else:
					if "roll_power" in aero:
						aero.set("roll_power", float(aero.get("roll_power")) * wing_loss_roll_authority_scale)
			if wing_loss_disable_all_control_inputs:
				var control_steering := _aircraft.get_node_or_null("ControlSteering")
				if control_steering != null and "ControlActive" in control_steering:
					control_steering.set("ControlActive", false)
				_disable_passive_stability_after_wing_loss(aero)
				_neutralize_all_flight_control_inputs()
			_set_structural_airflow_feedback(0.0, wing_loss_buffet_intensity)
			set_physics_process(true)
		ZONE_HORIZONTAL_STABILIZER:
			if aero != null:
				if "pitch_power" in aero:
					aero.set("pitch_power", float(aero.get("pitch_power")) * horizontal_stabilizer_control_scale)
				if "simplified_pitch_power_override" in aero and float(aero.get("simplified_pitch_power_override")) >= 0.0:
					aero.set("simplified_pitch_power_override", float(aero.get("simplified_pitch_power_override")) * horizontal_stabilizer_control_scale)
		ZONE_VERTICAL_STABILIZER:
			if aero != null:
				if "yaw_power" in aero:
					aero.set("yaw_power", float(aero.get("yaw_power")) * vertical_stabilizer_control_scale)
		ZONE_COCKPIT:
			var hud := _aircraft.get_node_or_null("HeadsUpDisplay") as Node3D
			if hud != null:
				hud.visible = false
			if _aircraft.has_method("kill_pilot_due_to_cockpit_damage"):
				_aircraft.call("kill_pilot_due_to_cockpit_damage")
			else:
				_aircraft.set_meta("pilot_dead", true)
				_aircraft.set_meta("ejection_disabled", true)
		ZONE_FUSELAGE:
			if "current_health" in _aircraft:
				_aircraft.set("current_health", 0.0)
			if _aircraft.has_method("_begin_critical_damage_sequence"):
				_aircraft.call("_begin_critical_damage_sequence")

func _zone_display_name(zone: StringName) -> String:
	match zone:
		ZONE_LEFT_WING:
			return "LeftWing"
		ZONE_RIGHT_WING:
			return "RightWing"
		ZONE_COCKPIT:
			return "Cockpit"
		ZONE_HORIZONTAL_STABILIZER:
			return "HorizontalStabilizer"
		ZONE_VERTICAL_STABILIZER:
			return "VerticalStabilizer"
		ZONE_TAIL_SECTION:
			return "TailSection"
		_:
			return "Fuselage"


func _set_structural_airflow_feedback(drag_accel_mps2: float, buffet_intensity: float) -> void:
	if _aircraft == null:
		return
	var aero := _aircraft.get_node_or_null("SimpleAero")
	if aero == null:
		return
	if "structural_damage_drag_accel_mps2" in aero:
		aero.set("structural_damage_drag_accel_mps2", maxf(drag_accel_mps2, 0.0))
	if "structural_damage_buffet_intensity" in aero:
		aero.set("structural_damage_buffet_intensity", clampf(buffet_intensity, 0.0, 1.0))


func _neutralize_all_flight_control_inputs() -> void:
	if _aircraft == null or not is_instance_valid(_aircraft):
		return
	var aero := _aircraft.get_node_or_null("SimpleAero")
	if aero != null:
		for input_property: StringName in [&"pitch_input", &"roll_input", &"yaw_input"]:
			if input_property in aero:
				aero.set(input_property, 0.0)
	if not _aircraft.has_method("find_modules_by_type"):
		return
	var steering_modules: Array = _aircraft.call("find_modules_by_type", "steering")
	for steering_module_variant in steering_modules:
		var steering_module := steering_module_variant as Node
		if steering_module == null:
			continue
		if steering_module.has_method("set_x"):
			steering_module.call("set_x", 0.0)
		if steering_module.has_method("set_y"):
			steering_module.call("set_y", 0.0)
		if steering_module.has_method("set_z"):
			steering_module.call("set_z", 0.0)


func _disable_passive_stability_after_wing_loss(aero: Node) -> void:
	if aero == null:
		return
	for stability_property: StringName in [
		&"stability_strength",
		&"directional_stability_strength",
		&"alignment_strength",
		&"alignment_low_speed_strength",
	]:
		if stability_property in aero:
			aero.set(stability_property, 0.0)


func _limit_wing_failure_angular_velocity() -> void:
	if _aircraft == null:
		return
	var basis := _aircraft.global_transform.basis.orthonormalized()
	var local_angular_velocity := basis.transposed() * _aircraft.angular_velocity
	local_angular_velocity.x = clampf(
		local_angular_velocity.x,
		-deg_to_rad(wing_loss_max_pitch_rate_deg_s),
		deg_to_rad(wing_loss_max_pitch_rate_deg_s)
	)
	local_angular_velocity.y = clampf(
		local_angular_velocity.y,
		-deg_to_rad(wing_loss_max_yaw_rate_deg_s),
		deg_to_rad(wing_loss_max_yaw_rate_deg_s)
	)
	local_angular_velocity.z = clampf(
		local_angular_velocity.z,
		-deg_to_rad(wing_loss_max_roll_rate_deg_s),
		deg_to_rad(wing_loss_max_roll_rate_deg_s)
	)
	_aircraft.angular_velocity = basis * local_angular_velocity


func _is_finite_position(position: Vector3) -> bool:
	return is_finite(position.x) and is_finite(position.y) and is_finite(position.z)
