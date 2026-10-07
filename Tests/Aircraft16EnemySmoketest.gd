extends Node

class QuietBase extends EnemyBase:
	func _build_base() -> void:
		pass

var failures: Array[String] = []
const SCENE := "res://Aircraft/Aircraft_16.tscn"

func check(okay: bool, reason: String) -> void:
	if not okay:
		failures.append(reason)
		push_error(reason)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	for singleton in get_tree().root.get_children():
		if singleton != self:
			singleton.process_mode = Node.PROCESS_MODE_DISABLED
	var base := QuietBase.new()
	base.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(base)
	await get_tree().process_frame
	check(base._resolve_aircraft_scene("fighter_bomber").resource_path == SCENE, "base aircraft resolution")
	base._rng.seed = 160016
	var found: Dictionary = {}
	for attempt in 100:
		base.aircraft_reserve = 32
		var flights := base.deploy_patrol_pair()
		var deployed := 0
		for flight in flights:
			var data := flight.capture_save_state()
			deployed += flight.aircraft_count
			for slot in data.aircraft_scene_paths.size():
				if data.aircraft_scene_paths[slot] == SCENE:
					var loadout: String = data.loadout_slots[slot]
					found[loadout] = true
					check(flight.role == (EnemyVirtualFlight.AircraftRole.FIGHTER if loadout == "guns" else EnemyVirtualFlight.AircraftRole.BOMBER), "patrol role " + loadout)
			flight.free()
		check(base.aircraft_reserve == 32 - deployed, "reserve accounting")
	for loadout in ["guns", "bombs", "rockets"]:
		check(found.has(loadout), "missing patrol loadout " + loadout)
	var flight := EnemyVirtualFlight.new()
	flight.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(flight)
	var packed := load(SCENE) as PackedScene
	flight.setup(Vector3.ZERO, [packed, packed, packed], ["guns", "bombs", "rockets"])
	flight.position = Vector3(0, 800, 0)
	flight.heading = Vector3.BACK
	var saved := flight.capture_save_state()
	var restored := EnemyVirtualFlight.new()
	check(restored.restore_save_state(saved), "save restore rejected Aircraft 16")
	check(restored._aircraft_slots.size() == 3 and restored._aircraft_slots[0].resource_path == SCENE, "restored aircraft identity")
	restored.free()
	flight._begin_materialize()
	for slot in 3:
		flight._tick_materialize_step()
	check(flight.active_aircraft.size() == 3, "materialization count")
	for slot in flight.active_aircraft.size():
		var craft := flight.active_aircraft[slot] as RigidBody3D
		craft.freeze = true
		craft.process_mode = Node.PROCESS_MODE_DISABLED
		check(craft.get("team") == 2 and craft.is_in_group("enemies") and craft.is_in_group("ai_aircraft"), "hostile team/groups")
		var pilot: Node = craft.get_node("AIPilot")
		check(pilot.dogfight_enabled == (slot == 0) and pilot.ground_attack_enabled == (slot != 0), "materialized pilot role")
		var weapons: Node = craft.get_node("ControlWeapons")
		check("Guns" in weapons.weapon_types, "guns removed")
		check(("Bomb" in weapons.weapon_types) == (slot == 1), "bomb fit")
		check(("Rocket Pod" in weapons.weapon_types) == (slot == 2), "rocket fit")
		craft.queue_free()
	flight.active_aircraft.clear()
	flight.queue_free()
	var spawner := load("res://Enemies/EnemyAircraftSpawner.gd").new() as Node3D
	spawner.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(spawner)
	var spawned: Array = await spawner.spawn_enemy_flight_by_role("fighter_bomber", 1)
	check(spawned.size() == 1, "manual enemy flight spawn")
	for craft in spawned:
		check(craft.scene_file_path == SCENE and craft.team == 2, "manual enemy scene/team")
		var weapons: Node = craft.get_node("ControlWeapons")
		check("Guns" in weapons.weapon_types and "Bomb" in weapons.weapon_types and "Rocket Pod" in weapons.weapon_types, "manual full loadout")
		check(craft.get_node("AIPilot").ground_attack_enabled, "manual ground strike assignment")
		craft.queue_free()
	spawner.queue_free()
	base.queue_free()
	await get_tree().process_frame
	print("AIRCRAFT16_ENEMY_", "PASS" if failures.is_empty() else "FAIL", " loadouts=", found, " errors=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
