extends SceneTree

var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	root.get_node("SaveGameManager").set("autosave_enabled", false)
	for node in root.get_children():
		node.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for model in ["buggy", "pickup", "battle_bus"]:
		var source = load("res://GroundVehicle/vehicle_enemy_%s.tscn" % model).instantiate()
		var controllers: Array[Node] = []
		for node in source.find_children("*", "Node3D", true, false):
			if node.has_method("mount_weapon"):
				controllers.append(node)
		_check(controllers.size() == (2 if model == "battle_bus" else 1), model + ": gun count")
		for controller in controllers:
			controller.get_parent().remove_child(controller)
			controller.process_mode = Node.PROCESS_MODE_DISABLED
			world.add_child(controller)
			var turret = controller.turret
			var receiver = turret.receiver
			var caliber: int = controller.weapon_instance.gun_profile.caliber_mm
			_check(receiver.caliber_mm == caliber, model + ": matching caliber")
			_check(receiver.mounted_barrel.scene_file_path.ends_with("%d mm.blend" % caliber), model + ": Blender barrel")
			_check(turret.firing_points[0] == receiver.muzzle, model + ": actual muzzle")
			var stand: Node3D = turret.get_node("StandModel")
			_check(stand.scene_file_path.contains("monopod.blend"), model + ": monopod model")
			var stand_rest := stand.global_transform
			var body_rest: Transform3D = receiver.get_node("ReceiverModel").global_transform
			var barrel_rest: Vector3 = receiver.mounted_barrel.global_position
			turret.kick_barrel_recoil(caliber, 0.1)
			var expected: Vector3 = barrel_rest - turret.barrel_mount.global_basis.z.normalized() * caliber * 0.01
			_check(receiver.mounted_barrel.global_position.distance_to(expected) < 0.0001, model + ": calibrated barrel recoil")
			_check(stand.global_transform.is_equal_approx(stand_rest), model + ": fixed post during recoil")
			_check(receiver.get_node("ReceiverModel").global_transform.is_equal_approx(body_rest), model + ": fixed receiver during recoil")
			turret.reset_barrel_recoil()
			# Exercise a swap during recoil: no stale muzzle or freed recoil references.
			turret.kick_barrel_recoil(caliber, 0.1)
			controller.mount_weapon(load("res://Weapons/Turrets/40mm_autocannon_weapon.tscn"))
			_check(receiver.caliber_mm == 40 and turret.firing_points[0] == receiver.muzzle, model + ": live caliber swap")
			turret.kick_barrel_recoil(40, 0.1)
			turret.reset_barrel_recoil()
			checked += 1
			controller.free()
		source.free()
	world.free()
	await process_frame
	print("ENEMY_RECEIVER_TURRETS_RESULT guns=%d failures=%s" % [checked, failures])
	quit(0 if failures.is_empty() else 1)
