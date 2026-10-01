extends SceneTree

var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _check_gun(scene: PackedScene, world: Node3D, label: String) -> void:
	var gun := scene.instantiate() as Node3D
	if not "gun_profile" in gun or gun.get("gun_profile") == null:
		gun.free()
		return # Bombs/rockets can have historical gun-like filenames.
	gun.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(gun)
	var caliber: int = gun.gun_profile.caliber_mm
	var model := gun.get_node_or_null("GunModel") as Node3D
	if model == null:
		model = gun.get_node_or_null("Autocannon_glb") as Node3D
	_check(model != null, label + ": missing visual")
	if model != null:
		_check(model.scene_file_path.ends_with("gun barrel %d mm.blend" % caliber), label + ": stale/wrong barrel")
		var barrel: Node3D = gun._barrel_recoil.targets[0].node
		var bounds: AABB = (gun.global_transform.affine_inverse() * barrel.global_transform) * barrel.get_aabb()
		var muzzle: Node3D = gun.get_node("BulletSpawnPoint")
		_check(muzzle.position.distance_to(Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)) < 0.001, label + ": muzzle is not at barrel tip")
	checked += 1
	gun.free()

func _run() -> void:
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for number in range(1, 16):
		var path := "res://Aircraft/Aircraft_%d.tscn" % number
		if not ResourceLoader.exists(path):
			continue
		var source = load(path).instantiate()
		for node in source.find_children("*", "Node3D", true, false):
			if node is Hardpoint and node.mounted_weapon != null:
				_check_gun(node.mounted_weapon, world, "%d/%s" % [number, node.name])
		source.free()
	for path in ["res://Weapons/Turrets/40mm_autocannon_weapon.tscn", "res://Weapons/Guns/Turrets/40mm_autocannon_turret_weapon.tscn"]:
		_check_gun(load(path), world, path)
	var side = load("res://Weapons/Turrets/helicopter_side_gun_turret.tscn").instantiate()
	side.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(side)
	_check(not side.get_node("SideGunModel/machine gun").visible, "old side gun remains visible")
	_check(side.receiver.mounted_barrel.scene_file_path.ends_with("gun barrel 10 mm.blend"), "side gun missing new barrel")
	_check(side.firing_points[0] == side.receiver.muzzle, "side gun wrong muzzle")
	side.free()
	world.free()
	await process_frame
	print("AIRCRAFT_GUN_MODELS_RESULT guns=%d failures=%s" % [checked, failures])
	quit(0 if failures.is_empty() else 1)
