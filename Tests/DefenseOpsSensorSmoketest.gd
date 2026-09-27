extends SceneTree

class Contact:
	extends Node3D
	var team: int = 2
	var is_destroyed: bool = false
	func get_team() -> int:
		return team

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func add_contact(world: Node3D, pos: Vector3, group: String, team: int = 2) -> Contact:
	var contact := Contact.new()
	contact.team = team
	contact.position = pos
	contact.add_to_group(group)
	world.add_child(contact)
	root.get_node("WorldUnitIndex").call("register_unit", contact)
	return contact

func run() -> void:
	var sensors := root.get_node("AirOpsManager")
	var index := root.get_node("WorldUnitIndex")
	var saved_range: float = sensors.get("carrier_radar_range_m")
	var saved_enabled: bool = sensors.get("carrier_radar_enabled")
	var saved_spatial: bool = index.get("spatial_queries_enabled")
	sensors.set("carrier_radar_range_m", 5000.0)
	sensors.set("carrier_radar_enabled", true)
	var world := Node3D.new()
	root.add_child(world)
	var carrier := Node3D.new()
	world.add_child(carrier)
	var near := add_contact(world, Vector3(0, 100, 300), "enemies")
	var distant := add_contact(world, Vector3(0, 100, 4500), "enemies")
	var outside := add_contact(world, Vector3(0, 100, 5100), "enemies")
	var friendly := add_contact(world, Vector3(0, 100, 300), "aircraft", 1)
	var neutral := add_contact(world, Vector3(0, 0, 300), "buildings", 0)
	var structure := add_contact(world, Vector3(5000, 0, 0), "buildings")
	# A structure not registered in WorldUnitIndex must still be discoverable.
	index.call("unregister_unit", structure)
	var dead := add_contact(world, Vector3(0, 0, 100), "enemies")
	dead.is_destroyed = true
	var mount := (load("res://LandCarrier/CarrierDefenseTurret.tscn") as PackedScene).instantiate()
	mount.process_mode = Node.PROCESS_MODE_DISABLED
	carrier.add_child(mount)
	var gun := mount.get_node("TurretController")
	var ops := (load("res://LandCarrier/DefenseOps.gd") as Script).new() as Node
	ops.name = "DefenseOps"
	carrier.add_child(ops)
	ops.call("coordinate_defense")
	var contacts: Array = ops.call("get_available_targets")
	check(contacts.size() == 4 and contacts.has(near) and contacts.has(distant) and contacts.has(structure) and contacts.has(friendly), "monitor roster missing enemy or friendly contacts")
	check(not contacts.has(outside) and not contacts.has(neutral) and not contacts.has(dead), "out-of-range, neutral or dead contact leaked into roster")
	check(not (sensors.call("get_carrier_sensor_contacts", carrier) as Array).has(friendly), "friendly monitor contact leaked into hostile sensor API")
	check(not bool(gun.call("can_engage_defense_target", distant)), "test target is not outside turret range")
	check(gun.get("current_target") == near, "sensor-only contact changed turret engagement limits")
	var rig := (load("res://LandCarrier/CarrierTargetCamera.tscn") as PackedScene).instantiate()
	carrier.add_child(rig)
	rig.call("begin_control")
	rig.call("cycle_target", 1)
	rig.call("cycle_target", 1)
	check(rig.get("current_target") == distant, "monitor could not select unengaged distant contact")
	# Removing every turret must not remove the sensor picture.
	carrier.remove_child(mount)
	mount.free()
	ops.call("coordinate_defense")
	check((ops.call("get_available_targets") as Array).size() == 4, "no-turret carrier lost monitor contacts")
	index.set("spatial_queries_enabled", false)
	ops.call("coordinate_defense")
	check((ops.call("get_available_targets") as Array) == contacts, "fallback scan disagreed with indexed radar query")
	index.set("spatial_queries_enabled", saved_spatial)
	distant.position.z = 5100
	index.call("register_unit", distant)
	ops.call("coordinate_defense")
	rig.call("_update_current_target")
	check(rig.get("current_target") == null, "monitor retained contact outside sensor radius")
	distant.position.z = 4500
	index.call("register_unit", distant)
	sensors.set("carrier_radar_range_m", 1000.0)
	ops.call("coordinate_defense")
	check((ops.call("get_available_targets") as Array) == [near, friendly], "roster ignored live radar-radius setting")
	sensors.set("carrier_radar_range_m", 5000.0)
	sensors.set("carrier_radar_enabled", false)
	ops.call("coordinate_defense")
	check((ops.call("get_available_targets") as Array) == [friendly], "disabled hostile radar should retain friendly observation")
	sensors.set("carrier_radar_enabled", true)
	carrier.position = Vector3(100000, 0, 0)
	ops.call("coordinate_defense")
	check((ops.call("get_available_targets") as Array).is_empty(), "radar query did not follow moving carrier")
	carrier.position = Vector3.ZERO
	ops.call("coordinate_defense")
	near.queue_free()
	check((ops.call("get_available_targets") as Array).size() == 3, "queued contact was not immediately removed")
	sensors.set("carrier_radar_range_m", saved_range)
	sensors.set("carrier_radar_enabled", saved_enabled)
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("[DefenseOpsSensorSmoketest] PASS distant_selectable=true turret_range_unchanged=true no_turrets=true structures=true team_filter=true radius_exit=true fallback=true moving_carrier=true")
	quit(0 if failures.is_empty() else 1)
