extends Node3D
class_name CarrierCollisionSetup

## Replaces the old solid carrier box with a compound hull that leaves a real
## vertical opening for the aircraft elevator. Generated shapes are simple boxes:
## stable for Jolt, cheap, and directly owned by the carrier CollisionObject3D.

@export var legacy_main_collision_path: NodePath = NodePath("../MainCollision")
@export var elevator_path: NodePath = NodePath("../Elevator")
## Every lift needs its own vertical opening. The legacy elevator_path remains a
## fallback for older carrier scenes that have only one elevator.
@export var elevator_paths: Array[NodePath] = [
	NodePath("../Elevator"),
	NodePath("../Elevator2"),
]
## Extra space on every horizontal side of the authored elevator platform.
@export_range(0.0, 3.0, 0.05) var shaft_clearance_m: float = 0.5
## Space between the elevator platform bottom and the lower hull at full descent.
@export_range(0.0, 2.0, 0.05) var lower_hull_clearance_m: float = 0.25

const GENERATED_COLLISION_PREFIX := "ElevatorHullCollision"

var _compound_shapes: Array[CollisionShape3D] = []
var _hull_bounds_local := AABB()
var _shaft_bounds_local := AABB()
var _shaft_bounds_locals: Array[AABB] = []


func _ready() -> void:
	# The carrier is still constructing its authored children while child _ready()
	# callbacks run, so sibling CollisionShape3Ds cannot be added safely yet.
	setup_collision_shapes.call_deferred()


func setup_collision_shapes() -> bool:
	var carrier := get_parent() as CollisionObject3D
	var legacy_collision := get_node_or_null(legacy_main_collision_path) as CollisionShape3D
	var elevators := _resolve_elevators()
	if carrier == null or legacy_collision == null or elevators.is_empty():
		push_warning("CarrierCollisionSetup: keeping legacy collider; carrier, MainCollision, or elevators are missing")
		return false
	var legacy_box := legacy_collision.shape as BoxShape3D
	if legacy_box == null:
		push_warning("CarrierCollisionSetup: keeping legacy collider; MainCollision is not a BoxShape3D")
		return false

	# Keep the authored fallback live until every replacement shape has actually
	# been parented to the carrier's CollisionObject3D.
	legacy_collision.disabled = false
	_clear_generated_shapes(carrier)
	_hull_bounds_local = _box_bounds_in_carrier_space(carrier, legacy_collision, legacy_box)
	var hull_min := _hull_bounds_local.position
	var hull_max := _hull_bounds_local.end
	var openings: Array[Rect2] = []
	_shaft_bounds_locals.clear()
	var shaft_bottom_y := hull_max.y
	for elevator in elevators:
		if not ("platform_size" in elevator) or not ("shaft_depth" in elevator):
			push_warning("CarrierCollisionSetup: keeping legacy collider; elevator dimensions are unavailable")
			_clear_generated_shapes(carrier)
			return false
		var platform_size_variant: Variant = elevator.get("platform_size")
		if not (platform_size_variant is Vector3):
			_clear_generated_shapes(carrier)
			return false
		var platform_size := platform_size_variant as Vector3
		var elevator_center := carrier.to_local(elevator.global_position)
		var shaft_depth := maxf(float(elevator.get("shaft_depth")), platform_size.y)
		var opening_half := Vector2(platform_size.x, platform_size.z) * 0.5 \
				+ Vector2.ONE * shaft_clearance_m
		var opening_min := Vector2(elevator_center.x, elevator_center.z) - opening_half
		var opening_max := Vector2(elevator_center.x, elevator_center.z) + opening_half
		opening_min.x = clampf(opening_min.x, hull_min.x, hull_max.x)
		opening_min.y = clampf(opening_min.y, hull_min.z, hull_max.z)
		opening_max.x = clampf(opening_max.x, hull_min.x, hull_max.x)
		opening_max.y = clampf(opening_max.y, hull_min.z, hull_max.z)
		if opening_max.x - opening_min.x <= 0.1 or opening_max.y - opening_min.y <= 0.1:
			push_warning("CarrierCollisionSetup: keeping legacy collider; an elevator opening lies outside the hull")
			_clear_generated_shapes(carrier)
			return false
		var elevator_shaft_bottom_y := maxf(
			hull_min.y,
			elevator_center.y - shaft_depth - platform_size.y * 0.5 - lower_hull_clearance_m
		)
		shaft_bottom_y = minf(shaft_bottom_y, elevator_shaft_bottom_y)
		var opening := Rect2(opening_min, opening_max - opening_min)
		openings.append(opening)
		_shaft_bounds_locals.append(AABB(
			Vector3(opening_min.x, elevator_shaft_bottom_y, opening_min.y),
			Vector3(opening.size.x, hull_max.y - elevator_shaft_bottom_y, opening.size.y)
		))

	_shaft_bounds_local = _shaft_bounds_locals[0]
	for i in range(1, _shaft_bounds_locals.size()):
		_shaft_bounds_local = _shaft_bounds_local.merge(_shaft_bounds_locals[i])

	# A full lower hull supports the hangar floor. Above it, split the deck into a
	# rectangular grid and omit only cells inside either shaft. This produces a
	# stable, non-overlapping compound collider for diagonally offset openings.
	_add_box(carrier, "LowerHull", hull_min, Vector3(hull_max.x, shaft_bottom_y, hull_max.z))
	var x_breaks: Array[float] = [hull_min.x, hull_max.x]
	var z_breaks: Array[float] = [hull_min.z, hull_max.z]
	for opening in openings:
		x_breaks.append(opening.position.x)
		x_breaks.append(opening.end.x)
		z_breaks.append(opening.position.y)
		z_breaks.append(opening.end.y)
	x_breaks.sort()
	z_breaks.sort()
	var cell_index := 0
	for x_index in range(x_breaks.size() - 1):
		for z_index in range(z_breaks.size() - 1):
			var min_x := x_breaks[x_index]
			var max_x := x_breaks[x_index + 1]
			var min_z := z_breaks[z_index]
			var max_z := z_breaks[z_index + 1]
			if max_x - min_x <= 0.01 or max_z - min_z <= 0.01:
				continue
			var centre := Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
			if _point_inside_any_opening(centre, openings):
				continue
			_add_box(
				carrier,
				"DeckCell%02d" % cell_index,
				Vector3(min_x, shaft_bottom_y, min_z),
				Vector3(max_x, hull_max.y, max_z)
			)
			cell_index += 1

	if _compound_shapes.size() < 2:
		_clear_generated_shapes(carrier)
		push_warning("CarrierCollisionSetup: keeping legacy collider; compound hull creation was incomplete")
		return false
	legacy_collision.disabled = true
	print(
		"Carrier collision compound ready: hull=%s shaft=%s shapes=%d" % [
			str(_hull_bounds_local),
			str(_shaft_bounds_local),
			_compound_shapes.size(),
		]
	)
	return not _compound_shapes.is_empty()


func get_compound_collision_shapes() -> Array[CollisionShape3D]:
	return _compound_shapes.duplicate()


func get_hull_bounds_local() -> AABB:
	return _hull_bounds_local


func get_shaft_bounds_local() -> AABB:
	return _shaft_bounds_local


func get_shaft_bounds_locals() -> Array[AABB]:
	return _shaft_bounds_locals.duplicate()


func _resolve_elevators() -> Array[Node3D]:
	var resolved: Array[Node3D] = []
	var seen: Dictionary = {}
	var configured_paths := elevator_paths.duplicate()
	if configured_paths.is_empty() and elevator_path != NodePath():
		configured_paths.append(elevator_path)
	for path_variant in configured_paths:
		var path := path_variant as NodePath
		var elevator := get_node_or_null(path) as Node3D
		if elevator == null:
			continue
		var instance_id := elevator.get_instance_id()
		if seen.has(instance_id):
			continue
		seen[instance_id] = true
		resolved.append(elevator)
	# Preserve compatibility if a scene overrides elevator_paths with invalid or
	# absent entries but still provides the original single elevator_path.
	if resolved.is_empty() and elevator_path != NodePath():
		var fallback := get_node_or_null(elevator_path) as Node3D
		if fallback != null:
			resolved.append(fallback)
	return resolved


func _point_inside_any_opening(point: Vector2, openings: Array[Rect2]) -> bool:
	for opening in openings:
		if point.x > opening.position.x and point.x < opening.end.x \
				and point.y > opening.position.y and point.y < opening.end.y:
			return true
	return false


func _clear_generated_shapes(carrier: CollisionObject3D) -> void:
	_compound_shapes.clear()
	_shaft_bounds_locals.clear()
	for child in carrier.get_children():
		if child is CollisionShape3D and str(child.name).begins_with(GENERATED_COLLISION_PREFIX):
			child.free()


func _add_box(carrier: CollisionObject3D, suffix: String, min_corner: Vector3, max_corner: Vector3) -> void:
	var size := max_corner - min_corner
	if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		return
	var collision := CollisionShape3D.new()
	collision.name = "%s%s" % [GENERATED_COLLISION_PREFIX, suffix]
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position = (min_corner + max_corner) * 0.5
	carrier.add_child(collision)
	if collision.get_parent() != carrier:
		collision.free()
		return
	_compound_shapes.append(collision)


func _box_bounds_in_carrier_space(
		carrier: CollisionObject3D,
		collision: CollisionShape3D,
		box: BoxShape3D
) -> AABB:
	carrier.force_update_transform()
	collision.force_update_transform()
	var shape_to_carrier := carrier.global_transform.affine_inverse() * collision.global_transform
	var half_size := box.size * 0.5
	var min_corner := Vector3(INF, INF, INF)
	var max_corner := Vector3(-INF, -INF, -INF)
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var corner := shape_to_carrier * Vector3(
					half_size.x * x_sign,
					half_size.y * y_sign,
					half_size.z * z_sign
				)
				min_corner = min_corner.min(corner)
				max_corner = max_corner.max(corner)
	return AABB(min_corner, max_corner - min_corner)
