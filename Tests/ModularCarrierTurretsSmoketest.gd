extends SceneTree

const GUNS := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
const WEAPONS := [
	"res://Weapons/Turrets/bullet_weapon.tscn",
	"res://Weapons/Turrets/bullet_weapon_15mm.tscn",
	"res://Weapons/Turrets/bullet_weapon_20mm.tscn",
	"res://Weapons/Turrets/heavy_gun_weapon.tscn",
	"res://Weapons/Turrets/40mm_autocannon_weapon.tscn",
]
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func make_carrier() -> Node3D:
	# Keep the real authored sites and their transforms, but omit unrelated world
	# systems from this focused fixture. Nothing in the packed scene is modified.
	var source := (load("res://LandCarrier/LandCarrier2.tscn") as PackedScene).instantiate()
	var carrier := (load("res://Tests/Fixtures/ModularTurretCarrierFixture.gd") as Script).new() as Node3D
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	for child in source.get_children():
		if child.has_method("build_turret") or child.name in ["CarrierDefenseLoadout", "DefenseOps"]:
			child.owner = null
			source.remove_child(child)
			carrier.add_child(child)
	source.free()
	root.add_child(carrier)
	return carrier

func check_gun(controller: Node, caliber: int) -> void:
	var turret: Node3D = controller.get("turret")
	var weapon: Node = controller.get("weapon_instance")
	check(turret != null and weapon != null, "missing turret or weapon")
	if turret == null or weapon == null:
		return
	check(turret.get("mounted_caliber_mm") == caliber, "wrong barrel for %d mm" % caliber)
	check((weapon.get("gun_profile") as Resource).get("caliber_mm") == caliber, "wrong gun profile")
	var mount: Node3D = turret.get("barrel_mount")
	var locator: Node3D = turret.get("barrel_attachment")
	var muzzle: Node3D = turret.get("muzzle")
	check(mount != null and muzzle != null, "missing modular rig")
	if mount == null or muzzle == null:
		return
	check(mount.global_position.is_equal_approx(locator.global_position), "barrel missed authored position")
	check(mount.scale.is_equal_approx(Vector3.ONE), "locator scale distorted barrel")
	check(not locator.visible, "locator mesh is still visible")
	check(mount.get_child_count() == 2, "old barrel remained after swap")
	check(muzzle.position.z > 1.0, "muzzle did not reach imported barrel tip")
	var shot: Transform3D = turret.call("get_current_muzzle_transform")
	check(shot.origin.is_equal_approx(muzzle.global_position), "shot did not use barrel muzzle")
	check((weapon.call("_get_bullet_spawn_transform", shot) as Transform3D).origin.is_equal_approx(shot.origin), "weapon overrode modular muzzle")
	var model := weapon.get_node_or_null("GunModel") as Node3D
	check(model == null or not model.visible, "weapon duplicated the barrel visuals")
	var target: Vector3 = (controller as Node3D).global_transform * Vector3(80, 40, 120)
	for i in range(120):
		turret.call("tick", 1.0 / 60.0, target)
	shot = turret.call("get_current_muzzle_transform")
	check(shot.basis.z.dot((target - shot.origin).normalized()) > 0.999, "barrel yaw/pitch did not track target")
	print("MODULAR_GUN_OK caliber=%d muzzle=%s" % [caliber, muzzle.position])

func run() -> void:
	var carrier := make_carrier()
	var loadout := carrier.get_node("CarrierDefenseLoadout")
	var sites: Array = loadout.call("get_build_sites")
	check(sites.size() == 9, "expected four hull sites plus five island sites")
	for site in sites:
		check(not site.call("is_built"), "authored site was not empty")
		if String(site.name).begins_with("TurretPosition "):
			var carrier_up := carrier.global_basis.y.normalized()
			var carrier_forward := carrier.global_basis.z.normalized()
			check(site.global_basis.y.normalized().dot(carrier_up) > 0.9999, "%s was not vertically upright" % site.name)
			check(site.global_basis.z.normalized().dot(carrier_forward) > 0.9999, "%s did not face carrier-forward" % site.name)
			check(site.call("build_turret", 20), "%s could not build its pose-check turret" % site.name)
			var pose_controller := site.get("built_turret") as Node3D
			var pose_turret: Node3D = pose_controller.get("turret") if pose_controller != null else null
			if pose_turret != null:
				var muzzle_pose := pose_turret.call("get_current_muzzle_transform") as Transform3D
				check(muzzle_pose.basis.y.normalized().dot(carrier_up) > 0.9999, "%s barrel rig was not vertically upright" % site.name)
				check(muzzle_pose.basis.z.normalized().dot(carrier_forward) > 0.9999, "%s barrel did not default carrier-forward" % site.name)
			else:
				check(false, "%s did not create a turret rig" % site.name)
			site.call("clear_turret")
	loadout.call("initialize_starting_turrets", 12345)
	var saved: Dictionary = loadout.call("capture_save_state")
	check(saved.turrets.size() == 2, "new game did not build exactly two turrets")
	check(saved.turrets[0].site != saved.turrets[1].site, "starting sites were not distinct")
	for site in sites:
		if site.call("is_built"):
			check_gun(site.get("built_turret"), site.get("installed_caliber_mm"))
	loadout.call("initialize_starting_turrets", 42)
	check(loadout.call("capture_save_state") == saved, "reinitialization rerolled starting loadout")
	var carrier_state: Dictionary = carrier.call("capture_save_state")
	check(carrier_state.defense_loadout == saved, "carrier snapshot omitted its turrets")
	var session := root.get_node("GameSession")
	var previous_pending: Dictionary = session.get("_pending_save_state")
	session.set("_pending_save_state", {"campaign": {"carrier": carrier_state}})
	var other := make_carrier()
	var restored := other.get_node("CarrierDefenseLoadout")
	await process_frame
	check(restored.call("capture_save_state") == saved, "pending-load startup rerolled saved loadout")
	check(other.call("restore_save_state", carrier_state), "carrier save restore was rejected")
	check(restored.call("capture_save_state") == saved, "carrier restore changed loadout")
	session.set("_pending_save_state", previous_pending)
	check((other.get_node("DefenseOps").get("_turrets") as Array).size() == 2, "DefenseOps did not discover the two built turrets")
	check(not restored.call("restore_save_state", {"turrets": [{"site": "missing", "caliber_mm": 10}]}), "invalid site was accepted")
	check(restored.call("capture_save_state") == saved, "invalid save damaged current loadout")
	check(not restored.call("restore_save_state", {"turrets": [saved.turrets[0], saved.turrets[0]]}), "duplicate save sites were accepted")
	for site in sites:
		if not site.call("is_built"):
			check(site.call("build_turret", 40), "empty site could not build later")
			check(not site.call("build_turret", 10), "occupied site allowed duplicate build")
			break
	var expanded: Dictionary = loadout.call("capture_save_state")
	check(expanded.turrets.size() == 3, "later turret was not saved")
	check(restored.call("restore_save_state", expanded), "expanded loadout was rejected")
	check(restored.call("capture_save_state") == expanded, "later turret was not restored")
	check(restored.call("restore_save_state", {"turrets": []}), "empty saved loadout was rejected")
	restored.call("_initialize")
	check((restored.call("capture_save_state") as Dictionary).turrets.is_empty(), "empty saved loadout respawned turrets")
	var seen_sites: Dictionary = {}
	var seen_calibers: Dictionary = {}
	for seed_value in range(1, 33):
		restored.call("restore_save_state", {"turrets": []})
		restored.set("_initialized", false)
		restored.call("initialize_starting_turrets", seed_value)
		var rolled: Dictionary = restored.call("capture_save_state")
		check(rolled.turrets.size() == 2, "random start count varied with seed")
		for entry in rolled.turrets:
			seen_sites[entry.site] = true
			seen_calibers[entry.caliber_mm] = true
	check(seen_sites.size() == 9 and seen_calibers.size() == 5, "random selection did not cover all authored sites and calibers")

	# Exercise the actual friendly vehicle controller and its scene-mounted gun,
	# without running unrelated vehicle navigation/terrain systems.
	var vehicle := (load("res://GroundVehicle/vehicle_friendly_light.tscn") as PackedScene).instantiate()
	var controller := vehicle.get_node("Body/TurretController")
	controller.owner = null
	controller.get_parent().remove_child(controller)
	vehicle.free()
	controller.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(controller)
	for i in range(GUNS.CALIBERS.size()):
		controller.call("mount_weapon", load(WEAPONS[i]))
		check_gun(controller, GUNS.CALIBERS[i])
	controller.free()
	carrier.free()
	other.free()
	await process_frame
	if failures.is_empty():
		print("MODULAR_CARRIER_TURRETS_SMOKETEST_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
