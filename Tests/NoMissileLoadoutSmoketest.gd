extends Node

const TechnicalIndexCatalog = preload("res://UI/TechnicalIndexCatalog.gd")
const AIRCRAFT_SCENES := [
	"res://Aircraft/Aircraft_1.tscn",
	"res://Aircraft/Aircraft_2.tscn",
	"res://Aircraft/Aircraft_3.tscn",
	"res://Aircraft/Aircraft_4.tscn",
	"res://Aircraft/Aircraft_5.tscn",
	"res://Aircraft/Aircraft_6.tscn",
	"res://Aircraft/Aircraft_7.tscn",
	"res://Aircraft/Aircraft_8.tscn",
	"res://Aircraft/Aircraft_9.tscn",
	"res://Aircraft/Aircraft_10.tscn",
	"res://Aircraft/Aircraft_11.tscn",
	"res://Aircraft/Aircraft_12.tscn",
	"res://Aircraft/CompleteFighterJet.tscn",
	"res://Enemies/EnemyFighter.tscn",
]
const RETIRED_MISSILE_SCENES := [
	"res://Weapons/AA_Missile/aa_missile_launcher.tscn",
	"res://Weapons/AG_Missile/ag_missile_holder.tscn",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for missile_scene_path in RETIRED_MISSILE_SCENES:
		var missile_scene := load(missile_scene_path) as PackedScene
		var hardpoint := Hardpoint.new()
		add_child(hardpoint)
		if hardpoint.mount_weapon_from_scene(missile_scene):
			_fail("hardpoint accepted retired weapon: %s" % missile_scene_path)
			return
		if hardpoint.weapon_instance != null or hardpoint.mounted_weapon != null:
			_fail("hardpoint retained retired weapon state: %s" % missile_scene_path)
			return
		hardpoint.queue_free()

	for aircraft_scene_path in AIRCRAFT_SCENES:
		var packed_aircraft := load(aircraft_scene_path) as PackedScene
		if packed_aircraft == null:
			_fail("aircraft scene could not be loaded: %s" % aircraft_scene_path)
			return
		var aircraft := packed_aircraft.instantiate()
		var retired_store := _find_authored_missile_store(aircraft)
		aircraft.free()
		if not retired_store.is_empty():
			_fail("%s still authored missile store %s" % [aircraft_scene_path, retired_store])
			return

	var manager_script := load("res://LandCarrier/FlightDeckManager.gd") as Script
	var manager := manager_script.new() as Node
	var intercept_aircraft := RigidBody3D.new()
	for index in range(3):
		var hardpoint := Hardpoint.new()
		hardpoint.name = "Hardpoint%d" % (index + 1)
		intercept_aircraft.add_child(hardpoint)
		var initial_scene := load(
			"res://Weapons/RocketPod/rocket_pod.tscn" if index < 2 \
			else "res://Weapons/Bomb/bomb_rack.tscn"
		) as PackedScene
		hardpoint.mounted_weapon = initial_scene
		hardpoint.mount_weapon_from_scene(initial_scene)
	manager.call("_apply_ai_loadout_profile", intercept_aircraft, "intercept")
	var intercept_hardpoints := _collect_hardpoints(intercept_aircraft)
	if intercept_hardpoints.size() != 3:
		_fail("intercept loadout fixture did not retain three hardpoints")
		return
	for index in intercept_hardpoints.size():
		var hardpoint: Hardpoint = intercept_hardpoints[index]
		if index == 0:
			if hardpoint.weapon_instance == null or hardpoint.mounted_weapon == null \
					or hardpoint.mounted_weapon.resource_path != \
							"res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn":
				_fail("intercept loadout did not mount its gun")
				return
		elif hardpoint.weapon_instance != null or hardpoint.mounted_weapon != null:
			_fail("intercept loadout retained an external store on hardpoint %d" % (index + 1))
			return
	intercept_aircraft.free()
	manager.free()

	for entry in TechnicalIndexCatalog.entries_for("WEAPONS"):
		var entry_text := "%s %s" % [entry.get("name", ""), entry.get("scene", "")]
		if "missile" in entry_text.to_lower():
			_fail("Technical Index still exposed retired weapon: %s" % entry_text)
			return

	for panel_path in [
		"res://Aircraft/Aircraft_1.tscn",
		"res://Aircraft/Aircraft_5.tscn",
		"res://HUD/instrument_panel.gd",
	]:
		var panel_source := FileAccess.get_file_as_string(panel_path)
		if panel_source.contains("\"id\": \"missile_lock\"") \
				or panel_source.contains("\"MISSILE\""):
			_fail("cockpit layout still exposed missile instrumentation: %s" % panel_path)
			return

	print("[NoMissileLoadoutSmoketest] PASS aircraft=%d guard=aa+ag intercept=gun_only ui=clean" % AIRCRAFT_SCENES.size())
	get_tree().quit(0)


func _find_authored_missile_store(root_node: Node) -> String:
	for hardpoint in _collect_hardpoints(root_node):
		if hardpoint.mounted_weapon == null:
			continue
		var store_path := hardpoint.mounted_weapon.resource_path
		if "missile" in store_path.to_lower():
			return store_path
	return ""


func _collect_hardpoints(root_node: Node) -> Array[Hardpoint]:
	var result: Array[Hardpoint] = []
	if root_node is Hardpoint:
		result.append(root_node as Hardpoint)
	for child in root_node.get_children():
		result.append_array(_collect_hardpoints(child as Node))
	return result


func _fail(reason: String) -> void:
	push_error("[NoMissileLoadoutSmoketest] FAIL %s" % reason)
	get_tree().quit(1)
