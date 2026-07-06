extends Node3D
class_name PlantObject

enum PlantVariant { CACTUS }

const GROUP_PLANT := "plant"
const GROUP_ENVIRONMENT_PROP := "environment_prop"

@export_group("Variant")
@export var plant_variant: PlantVariant = PlantVariant.CACTUS:
	set(value):
		plant_variant = value
		if is_inside_tree():
			build()
@export var cactus_scene: PackedScene = preload("res://Models/Vegetation/cactus.glb")
@export var visual_scale: Vector3 = Vector3.ONE:
	set(value):
		visual_scale = value
		if is_inside_tree():
			build()
@export var ground_offset_m: float = 0.0:
	set(value):
		ground_offset_m = value
		if is_inside_tree():
			build()

@export_group("Collision")
@export var collision_enabled: bool = true:
	set(value):
		collision_enabled = value
		if is_inside_tree():
			build()
@export var collision_radius_fraction: float = 0.32:
	set(value):
		collision_radius_fraction = value
		if is_inside_tree():
			build()
@export var collision_height_fraction: float = 0.92:
	set(value):
		collision_height_fraction = value
		if is_inside_tree():
			build()
@export var collision_base_sink_m: float = 0.08:
	set(value):
		collision_base_sink_m = value
		if is_inside_tree():
			build()
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		if is_inside_tree():
			build()
@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		if is_inside_tree():
			build()

var _visual_root: Node3D
var _collision_body: StaticBody3D


func _ready() -> void:
	add_to_group(GROUP_PLANT)
	add_to_group(GROUP_ENVIRONMENT_PROP)
	build()


func build() -> void:
	_clear_generated_children()

	var scene := _resolve_variant_scene()
	if scene == null:
		return

	var visual := scene.instantiate() as Node3D
	if visual == null:
		return

	visual.name = "Visual"
	visual.scale = visual_scale
	visual.position.y += ground_offset_m
	add_child(visual)
	_visual_root = visual

	if collision_enabled:
		var bounds := _get_visual_bounds()
		if bounds.size.length_squared() > 0.0001:
			_create_collision(bounds)


func _resolve_variant_scene() -> PackedScene:
	match plant_variant:
		PlantVariant.CACTUS:
			return cactus_scene
	return cactus_scene


func _clear_generated_children() -> void:
	for child in get_children():
		if child == _visual_root or child == _collision_body or child.name == "Visual" or child.name == "CollisionBody":
			remove_child(child)
			child.queue_free()
	_visual_root = null
	_collision_body = null


func _create_collision(bounds: AABB) -> void:
	var body := StaticBody3D.new()
	body.name = "CollisionBody"
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	body.add_to_group(GROUP_PLANT)
	body.add_to_group(GROUP_ENVIRONMENT_PROP)
	add_child(body)
	_collision_body = body

	var shape := CylinderShape3D.new()
	var radius_base := maxf(bounds.size.x, bounds.size.z)
	shape.radius = maxf(radius_base * collision_radius_fraction, 0.05)
	shape.height = maxf(bounds.size.y * collision_height_fraction, 0.1)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position = Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y + shape.height * 0.5 - collision_base_sink_m,
		bounds.position.z + bounds.size.z * 0.5
	)
	body.add_child(collision)


func _get_visual_bounds() -> AABB:
	var state := {
		"valid": false,
		"bounds": AABB(),
	}
	if _visual_root != null:
		_accumulate_mesh_bounds(_visual_root, _visual_root.transform, state)
	return state["bounds"] as AABB


func _accumulate_mesh_bounds(node: Node, local_xform: Transform3D, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var local_bounds := _transform_aabb(mesh_instance.mesh.get_aabb(), local_xform)
			if state["valid"] as bool:
				state["bounds"] = (state["bounds"] as AABB).merge(local_bounds)
			else:
				state["bounds"] = local_bounds
				state["valid"] = true

	for child in node.get_children():
		var child_xform := local_xform
		if child is Node3D:
			child_xform = local_xform * (child as Node3D).transform
		_accumulate_mesh_bounds(child, child_xform, state)


func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var result := AABB()
	var initialized := false
	for xi in [0.0, 1.0]:
		for yi in [0.0, 1.0]:
			for zi in [0.0, 1.0]:
				var corner := aabb.position + Vector3(
					aabb.size.x * xi,
					aabb.size.y * yi,
					aabb.size.z * zi
				)
				var point := xform * corner
				if initialized:
					result = result.expand(point)
				else:
					result = AABB(point, Vector3.ZERO)
					initialized = true
	return result
