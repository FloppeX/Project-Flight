extends SceneTree

class CarrierFixture extends Node3D:
	var turning := false
	func is_turning_for_launch(_yaw: float, _steer: float) -> bool:
		return turning

class TerrainFixture extends Node:
	var ridge := 0
	func get_height(point: Vector3) -> float:
		if ridge == 1 and point.z > 100.0: return 600.0
		if ridge == -1 and point.z < -100.0: return 600.0
		return -100.0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children(): child.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier := CarrierFixture.new()
	root.add_child(carrier)
	current_scene = carrier
	carrier.position.y = 100.0
	var terrain := TerrainFixture.new()
	carrier.add_child(terrain)
	terrain.add_to_group("terrain_provider")
	var manager = load("res://Tests/Fixtures/DeckTowSuspensionFixture.gd").new()
	manager.name = "FlightDeckManager"
	carrier.add_child(manager)
	var signs = load("res://LandCarrier/DeckStatusSigns.tscn").instantiate()
	carrier.add_child(signs)
	check_status(manager, true, true, "open terrain")
	terrain.ridge = 1
	check_status(manager, true, false, "cliff ahead")
	signs.refresh()
	for room in signs.get_children():
		check(room.get_node("Land/Lens").material_override.albedo_color == signs.READY_COLOR, "landing lens did not turn green")
		check(room.get_node("Launch/Lens").material_override.albedo_color == signs.HOLD_COLOR, "launch lens did not turn red")
		check(room.get_node("Launch/Reason").text == "TERRAIN AHEAD", "missing obstruction reason")
	terrain.ridge = -1
	check_status(manager, false, true, "ridge on approach")
	carrier.rotation.y = PI
	check_status(manager, true, false, "heading reversal swaps blocked corridor")
	carrier.position.z = 5000.0
	check_status(manager, true, true, "moving away clears corridor")
	terrain.ridge = 0
	carrier.turning = true
	check_status(manager, false, false, "carrier turning")
	carrier.turning = false
	manager.current_state = manager.DeckState.RECOVERY_IN_PROGRESS
	check_status(manager, true, true, "traffic does not change geographic suitability")
	var active_status: Dictionary = manager.get_deck_signal_status()
	check(active_status.landing_active and not active_status.launch_active, "recovery activity flags incorrect")
	signs.apply_status(active_status)
	signs.update_lamps(false, true)
	check(signs.get_node("CommandRoom/Land/Lens").material_override.albedo_color.g < 0.3, "active landing did not blink")
	check(signs.get_node("AirOps/Launch/Lens").material_override.albedo_color == signs.READY_COLOR, "inactive launch blinked")
	manager.current_state = manager.DeckState.LAUNCH_IN_PROGRESS
	active_status = manager.get_deck_signal_status()
	check(not active_status.landing_active and active_status.launch_active, "launch activity flags incorrect")
	signs.apply_status(active_status)
	signs.update_lamps(false, true)
	check(signs.get_node("AirOps/Launch/Lens").material_override.albedo_color.g < 0.3, "active launch did not blink")
	signs.update_lamps(true, true)
	check(signs.get_node("AirOps/Launch/Lens").material_override.albedo_color == signs.READY_COLOR, "blink did not return to bright phase")
	manager.landing_terrain_check_enabled = false
	check_status(manager, false, true, "disabled approach check is unverified")
	manager.landing_terrain_check_enabled = true
	terrain.remove_from_group("terrain_provider")
	check_status(manager, false, false, "missing terrain must not show green")
	manager.free()
	signs.refresh()
	check(signs.get_node("CommandRoom/Land/Reason").text == "OFFLINE", "missing manager did not fail closed")
	var state: SceneState = load("res://LandCarrier/LandCarrier2.tscn").get_state()
	var installed := false
	for i in state.get_node_count():
		if state.get_node_name(i) == &"DeckStatusSigns": installed = true
	check(installed, "signs not installed in gameplay carrier")
	for failure in failures: push_error(failure)
	print("DECK_STATUS_SIGNS_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check_status(manager: Node, land: bool, launch: bool, context: String) -> void:
	manager.set("_landing_path_cache_until_s", 0.0)
	var status: Dictionary = manager.get_deck_signal_status()
	check(status.land_available == land and status.launch_available == launch, "%s: %s" % [context, status])

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
