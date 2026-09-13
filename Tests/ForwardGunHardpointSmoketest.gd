extends SceneTree

const AIRCRAFT_SCENES := {
	"res://Aircraft/Aircraft_1.tscn": 1,
	"res://Aircraft/Aircraft_2.tscn": 1,
	"res://Aircraft/Aircraft_3.tscn": 2,
	"res://Aircraft/Aircraft_4.tscn": 1,
	"res://Aircraft/Aircraft_5.tscn": 1,
	"res://Aircraft/Aircraft_6.tscn": 1,
	"res://Aircraft/Aircraft_7.tscn": 1,
	"res://Aircraft/Aircraft_8.tscn": 1,
	"res://Aircraft/Aircraft_9.tscn": 0,
	"res://Aircraft/Aircraft_10.tscn": 0,
	"res://Aircraft/Aircraft_11.tscn": 0,
	"res://Aircraft/Aircraft_12.tscn": 2,
	"res://Aircraft/Aircraft_14.tscn": 1,
	"res://Aircraft/CompleteFighterJet.tscn": 1,
	"res://Enemies/EnemyFighter.tscn": 1,
}
const GUN_SCENE_PATH := "res://Weapons/Guns/Hardpoint/10mm_machine_gun_hardpoint.tscn"
const FALLBACK_GUN_SCENE_PATH := "res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn"
const ROCKET_SCENE_PATH := "res://Weapons/RocketPod/rocket_pod.tscn"
const BOMB_SCENE_PATH := "res://Weapons/Bomb/bomb_rack.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for scene_path: String in AIRCRAFT_SCENES:
		_check_aircraft_scene(scene_path, int(AIRCRAFT_SCENES[scene_path]))
	_check_gun_only_guard()
	_check_dynamic_loadouts()

	if _failures.is_empty():
		print("[ForwardGunHardpointSmoketest] PASS aircraft=%d aircraft_3_forward_guns=2 guard=rocket+bomb dynamic=rocket+bomb+intercept" % AIRCRAFT_SCENES.size())
		quit(0)
		return
	for failure in _failures:
		push_error("[ForwardGunHardpointSmoketest] FAIL %s" % failure)
	quit(1)


func _check_aircraft_scene(scene_path: String, expected_reserved_count: int) -> void:
	var packed := load(scene_path) as PackedScene
	_check(packed != null, "%s could not be loaded" % scene_path)
	if packed == null:
		return
	var aircraft := packed.instantiate()
	var hardpoints := _collect_hardpoints(aircraft)
	var reserved: Array[Hardpoint] = []
	var forward_z := -INF
	for hardpoint in hardpoints:
		forward_z = maxf(forward_z, _position_relative_to(hardpoint, aircraft).z)
		if hardpoint.gun_only:
			reserved.append(hardpoint)
	_check(reserved.size() == expected_reserved_count, "%s expected %d reserved gun stations, found %d" % [scene_path, expected_reserved_count, reserved.size()])
	for hardpoint in reserved:
		var station_z := _position_relative_to(hardpoint, aircraft).z
		_check(station_z >= forward_z - 0.01, "%s %s is not at the forward-most hardpoint position" % [scene_path, hardpoint.name])
		_check(hardpoint.mounted_weapon != null and _is_gun_scene(hardpoint.mounted_weapon), "%s %s does not start with a gun" % [scene_path, hardpoint.name])
	aircraft.free()


func _check_gun_only_guard() -> void:
	var hardpoint := Hardpoint.new()
	hardpoint.name = "ReservedGunStation"
	hardpoint.gun_only = true
	root.add_child(hardpoint)
	var rocket_scene := load(ROCKET_SCENE_PATH) as PackedScene
	var bomb_scene := load(BOMB_SCENE_PATH) as PackedScene
	var gun_scene := load(GUN_SCENE_PATH) as PackedScene
	_check(not hardpoint.mount_weapon_from_scene(rocket_scene), "gun-only hardpoint accepted a rocket pod")
	_check(hardpoint.weapon_instance == null and hardpoint.mounted_weapon == null, "gun-only hardpoint retained rejected rocket state")
	_check(not hardpoint.mount_weapon_from_scene(bomb_scene), "gun-only hardpoint accepted a bomb rack")
	_check(hardpoint.weapon_instance == null and hardpoint.mounted_weapon == null, "gun-only hardpoint retained rejected bomb state")
	_check(hardpoint.mount_weapon_from_scene(gun_scene), "gun-only hardpoint rejected a gun")
	hardpoint.queue_free()


func _check_dynamic_loadouts() -> void:
	var manager_script := load("res://LandCarrier/FlightDeckManager.gd") as Script
	var manager := manager_script.new() as Node
	var aircraft := RigidBody3D.new()
	var gun_scene := load(GUN_SCENE_PATH) as PackedScene
	for station_name in ["External1", "External2"]:
		var external := Hardpoint.new()
		external.name = station_name
		aircraft.add_child(external)
	for station_name in ["ForwardGunLeft", "ForwardGunRight"]:
		var reserved := Hardpoint.new()
		reserved.name = station_name
		reserved.gun_only = true
		reserved.mounted_weapon = gun_scene
		aircraft.add_child(reserved)
		reserved.mount_weapon_from_scene(gun_scene)

	manager.call("_apply_ai_loadout_profile", aircraft, "rocket_strike")
	_check_external_weapon_scene(aircraft, ROCKET_SCENE_PATH, "rocket strike")
	_check_reserved_guns(aircraft, GUN_SCENE_PATH, "rocket strike")
	manager.call("_apply_ai_loadout_profile", aircraft, "bomb_strike")
	_check_external_weapon_scene(aircraft, BOMB_SCENE_PATH, "bomb strike")
	_check_reserved_guns(aircraft, GUN_SCENE_PATH, "bomb strike")
	manager.call("_apply_ai_loadout_profile", aircraft, "intercept")
	for hardpoint in _collect_hardpoints(aircraft):
		if not hardpoint.gun_only:
			_check(hardpoint.weapon_instance == null and hardpoint.mounted_weapon == null, "intercept retained an external store on %s" % hardpoint.name)
	_check_reserved_guns(aircraft, GUN_SCENE_PATH, "intercept")

	var restored_station := aircraft.get_node("ForwardGunLeft") as Hardpoint
	manager.call("_restore_aircraft_loadout_state", aircraft, {
		"hardpoints": [{
			"path": str(aircraft.get_path_to(restored_station)),
			"weapon_scene": ROCKET_SCENE_PATH,
			"ammo_count": 12,
		}],
	})
	_check(restored_station.has_gun_mounted(), "save restore left a rocket-assigned reserved station without a gun")
	_check(restored_station.mounted_weapon != null and restored_station.mounted_weapon.resource_path == FALLBACK_GUN_SCENE_PATH, "save restore did not replace a forbidden rocket with the fallback gun")

	aircraft.free()
	manager.free()


func _check_external_weapon_scene(aircraft: Node, expected_scene_path: String, context: String) -> void:
	for hardpoint in _collect_hardpoints(aircraft):
		if hardpoint.gun_only:
			continue
		_check(is_instance_valid(hardpoint.weapon_instance), "%s left %s empty" % [context, hardpoint.name])
		if is_instance_valid(hardpoint.weapon_instance):
			_check(hardpoint.mounted_weapon != null and hardpoint.mounted_weapon.resource_path == expected_scene_path, "%s put %s on %s" % [context, hardpoint.mounted_weapon.resource_path if hardpoint.mounted_weapon != null else "nothing", hardpoint.name])


func _check_reserved_guns(aircraft: Node, expected_scene_path: String, context: String) -> void:
	for hardpoint in _collect_hardpoints(aircraft):
		if not hardpoint.gun_only:
			continue
		_check(hardpoint.has_gun_mounted(), "%s removed the gun from %s" % [context, hardpoint.name])
		_check(hardpoint.mounted_weapon != null and hardpoint.mounted_weapon.resource_path == expected_scene_path, "%s replaced the authored gun on %s" % [context, hardpoint.name])


func _collect_hardpoints(node: Node) -> Array[Hardpoint]:
	var result: Array[Hardpoint] = []
	if node is Hardpoint:
		result.append(node as Hardpoint)
	for child in node.get_children():
		result.append_array(_collect_hardpoints(child as Node))
	return result


func _position_relative_to(node: Node3D, ancestor: Node) -> Vector3:
	var relative_transform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != ancestor:
		if parent is Node3D:
			relative_transform = (parent as Node3D).transform * relative_transform
		parent = parent.get_parent()
	return relative_transform.origin


func _is_gun_scene(scene: PackedScene) -> bool:
	var path := scene.resource_path.to_lower()
	return "/guns/" in path or "/autocannon/" in path


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
