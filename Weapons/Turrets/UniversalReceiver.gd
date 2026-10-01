@tool
extends Node3D
## Modular visual assembly. +Z is forward; rotate this root around X for elevation.

const GUNS = preload("res://Weapons/Turrets/TurretGunCatalog.gd")
const RECOIL = preload("res://Weapons/Guns/BarrelRecoil.gd")
const REAR_RADII := {10: 0.052, 15: 0.067, 20: 0.082, 25: 0.101, 40: 0.137}

@export_enum("10 mm:10", "15 mm:15", "20 mm:20", "25 mm:25", "40 mm:40") var caliber_mm: int = 25:
	set(value):
		caliber_mm = value
		if is_node_ready():
			if Engine.is_editor_hint():
				_rebuild.call_deferred()
			else:
				_rebuild()

var mounted_barrel: Node3D
var muzzle: Marker3D
var _assembly: Node3D
var _recoil: Node

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_recoil):
		_recoil.reset()
		_recoil.free()
	if is_instance_valid(_assembly):
		_assembly.free()
	_assembly = Node3D.new()
	_assembly.name = "BarrelAssembly"
	add_child(_assembly)
	var model: Node3D = $ReceiverModel
	var socket: Node3D = model.find_child("BarrelSocket", true, false)
	var scene: PackedScene = GUNS.get_barrel_scene(caliber_mm)
	if socket == null or scene == null:
		return
	var socket_position := to_local(socket.global_position)
	mounted_barrel = scene.instantiate() as Node3D
	_assembly.add_child(mounted_barrel)
	var bounds := _mesh_bounds(mounted_barrel, Transform3D.IDENTITY)
	# Seat the rear inside the receiver; the artist-authored muzzle stays intact.
	mounted_barrel.position = socket_position - Vector3(bounds.get_center().x, bounds.get_center().y, bounds.position.z + 0.65)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	_assembly.add_child(muzzle)
	muzzle.position = mounted_barrel.position + Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)
	_add_adapter(socket_position, REAR_RADII[caliber_mm])
	if not Engine.is_editor_hint():
		_recoil = RECOIL.new()
		add_child(_recoil)
		var moving: Array[Node3D] = [mounted_barrel, muzzle]
		_recoil.configure(self, moving)

func _mesh_bounds(node: Node, parent_transform: Transform3D) -> AABB:
	var transform_in_receiver := parent_transform
	if node is Node3D:
		transform_in_receiver *= node.transform
	var result := AABB()
	if node is MeshInstance3D and node.mesh != null:
		result = transform_in_receiver * node.get_aabb()
	for child in node.get_children():
		var child_bounds := _mesh_bounds(child, transform_in_receiver)
		if child_bounds.size != Vector3.ZERO:
			result = child_bounds if result.size == Vector3.ZERO else result.merge(child_bounds)
	return result

func _add_adapter(socket: Vector3, radius: float) -> void:
	# A flat-shaded reducer closes the socket around each caliber's rear sleeve.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in range(12):
		var a := TAU * i / 12.0
		var b := TAU * (i + 1) / 12.0
		var quad := [Vector3(cos(a)*0.166, sin(a)*0.166, -0.025), Vector3(cos(b)*0.166, sin(b)*0.166, -0.025), Vector3(cos(b)*radius, sin(b)*radius, 0.07), Vector3(cos(a)*radius, sin(a)*radius, 0.07)]
		var normal: Vector3 = (quad[1]-quad[0]).cross(quad[2]-quad[0]).normalized()
		for index in [0, 2, 1, 0, 3, 2]:
			vertices.append(quad[index])
			normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.26, 0.26, 0.26)
	material.roughness = 0.65
	mesh.surface_set_material(0, material)
	var adapter := MeshInstance3D.new()
	adapter.name = "CaliberAdapter"
	adapter.mesh = mesh
	adapter.position = socket
	_assembly.add_child(adapter)

func get_muzzle_transform() -> Transform3D:
	return muzzle.global_transform if is_instance_valid(muzzle) else global_transform

func kick_barrel_recoil(shot_interval_s: float) -> void:
	if is_instance_valid(_recoil):
		_recoil.kick(caliber_mm, shot_interval_s)
