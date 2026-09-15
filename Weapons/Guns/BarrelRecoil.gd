extends Node
## Cosmetic recoil only: 1 mm of caliber = 1 cm of travel.
## Never translate the aiming pivot or attachment point.
var frame: Node3D
var targets: Array[Dictionary] = []
var distance_m := 0.0
var duration_s := 0.15
var elapsed_s := 0.0

func configure(axis_frame: Node3D, visuals: Array[Node3D]) -> void:
	reset()
	frame = axis_frame
	targets.clear()
	for visual in visuals:
		if is_instance_valid(visual):
			targets.append({"node": visual, "rest": visual.position})

func kick(caliber_mm: int, shot_interval_s: float) -> void:
	if caliber_mm <= 0 or targets.is_empty():
		return
	distance_m = float(caliber_mm) * 0.01
	duration_s = clampf(shot_interval_s * 0.85, 0.035, 0.22)
	elapsed_s = 0.0
	_apply_offset(distance_m)
	set_process(true)

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	elapsed_s = minf(elapsed_s + delta, duration_s)
	var t := elapsed_s / duration_s
	# Quick kick, smooth return to a fixed rest position; bursts cannot drift.
	_apply_offset(distance_m * (1.0 - t * t * (3.0 - 2.0 * t)))
	if elapsed_s >= duration_s:
		set_process(false)

func _apply_offset(offset_m: float) -> void:
	if not is_instance_valid(frame):
		set_process(false)
		return
	var world_offset := -frame.global_basis.z.normalized() * offset_m
	for target in targets:
		var visual: Variant = target.node
		if is_instance_valid(visual) and visual.is_inside_tree():
			var parent: Node3D = visual.get_parent_node_3d()
			visual.position = target.rest + parent.global_basis.inverse() * world_offset

func reset() -> void:
	for target in targets:
		var visual: Variant = target.node
		if is_instance_valid(visual):
			visual.position = target.rest
	set_process(false)

static func find_hardpoint_barrel(model: Node3D, axis_frame: Node3D) -> Node3D:
	# The current imported gun has unnamed barrel/receiver meshes. Select the
	# longest forward-axis mesh, not the whole model (which includes the mount).
	var result: Node3D = null
	var longest := 0.0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var bounds: AABB = (axis_frame.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		if bounds.size.z > longest:
			longest = bounds.size.z
			result = mesh
	return result

static func mount_hardpoint(gun: Node3D) -> Node:
	var model := gun.get_node_or_null("GunModel") as Node3D
	if model == null:
		model = gun.get_node_or_null("Autocannon_glb") as Node3D
	if model == null:
		return null
	var barrel := find_hardpoint_barrel(model, gun)
	if barrel == null:
		return null
	var recoil = load("res://Weapons/Guns/BarrelRecoil.gd").new()
	recoil.name = "BarrelRecoil"
	gun.add_child(recoil)
	var visuals: Array[Node3D] = [barrel]
	var muzzle := gun.find_child("BulletSpawnPoint", true, false) as Node3D
	if muzzle != null:
		visuals.append(muzzle)
	recoil.configure(gun, visuals)
	return recoil
