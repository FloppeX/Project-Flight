extends Node
const DECK = preload("res://LandCarrier/FlightDeckManager.gd")
const MANAGER = preload("res://LandCarrier/CarrierManager.gd")
const ASSEMBLY = preload("res://AirOps/FlightAssembly.gd")
class FuelAircraft extends Node:
	var energy_containers_by_type := {}
class TestDeck extends DECK:
	func _ready() -> void:
		add_to_group("flight_deck_manager")
	func _physics_process(_delta: float) -> void: pass
	func _launch_next_queued_ai() -> void: pass

var failures: Array[String] = []
var root: Window
func _ready() -> void:
	root = get_tree().root
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	var ops := root.get_node("AirOpsManager")
	ops.set_process(false)
	var service: Node = ops.assembly
	service.set_process(false)
	var pilots := root.get_node("PilotRoster")
	var manager := MANAGER.new()
	root.add_child(manager)
	var fdm := TestDeck.new()
	root.add_child(fdm)
	fdm.carrier_manager = manager
	fdm.current_state = DECK.DeckState.IDLE
	fdm.stored_aircraft.assign([
		_entry("one", 1), _entry("two", 1), _entry("three", 2), _entry("repair", 1, 40.0),
		_entry("spare", 5), _entry("extra", 6)
	])
	var inventory: Array = service.inventory()
	_expect(inventory.size() == 6, "one token per aircraft")
	_expect(_find(inventory, "repair").state == "REPAIRING", "damaged stock must be repairing")
	_expect(is_equal_approx(_find(inventory, "one").fuel_fraction, 1.0), "new stock has full fuel")
	var fuel_info := {"fuel_tanks": {"TankA": 100.0, "TankB": 300.0}}
	var fuel_data := {"energy_state": [
		{"path": "TankA", "energy_type": "fuel", "current_level": 50.0},
		{"path": "TankB", "energy_type": "fuel", "current_level": 50.0}]}
	_expect(is_equal_approx(ASSEMBLY._stored_fuel_fraction(fuel_data, fuel_info), 0.25), "stored fuel uses total tank capacity")
	var fuel_aircraft := FuelAircraft.new()
	var tank := AircraftModule_EnergyContainer.new()
	tank.MaxCapacity = 200.0
	tank.current_level = 40.0
	fuel_aircraft.energy_containers_by_type = {"fuel": [tank]}
	_expect(is_equal_approx(ASSEMBLY._live_fuel_fraction(fuel_aircraft), 0.2), "live fuel reflects remaining fuel")
	tank.ContainerActive = false
	_expect(ASSEMBLY._live_fuel_fraction(fuel_aircraft) < 0.0, "unavailable fuel is unknown, not full")
	tank.free()
	fuel_aircraft.free()
	var payload := ASSEMBLY._payload_summary({"hardpoints": [
		{"weapon_scene": "res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn", "ammo_count": 72},
		{"weapon_scene": "res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn", "ammo_count": 50},
		{"weapon_scene": "res://Weapons/RocketPod/rocket_pod.tscn", "ammo_count": 3}]})
	_expect(payload.guns == 122 and payload.rockets == 3 and payload.bombs == 0, "card loadout reports remaining mounted ammunition")
	_expect(service.assign("one", "Archer").is_empty(), "assign first aircraft")
	_expect(service.assign("two", "Archer").is_empty(), "assign same type")
	_expect(not service.assign("three", "Archer").is_empty(), "reject mixed aircraft types")
	_expect(not service.assign("one", "Archer").is_empty(), "reject duplicate assignment")
	_expect(not service.can_launch("Archer"), "assembly starts held")
	service.auto_assign_pilots("Archer")
	var first: Dictionary = service.stored("one")
	var second: Dictionary = service.stored("two")
	var pilot_id := str(first.metadata.get("assembly_pilot_id", ""))
	_expect(not pilot_id.is_empty(), "auto assign chooses a pilot")
	_expect(second.metadata.assembly_pilot_id != pilot_id, "pilots cannot be double booked")
	_expect(not service.assign_pilot("two", pilot_id).is_empty(), "reject duplicate pilot explicitly")
	service.set_hold("Archer", false)
	_expect(service.can_launch("Archer"), "ready composition may launch")
	_expect(service.configure_loadout("Archer", "rocket_strike").is_empty(), "compatible flight loadout")
	_expect(first.requested_ai_loadout_profile == "rocket_strike" and second.requested_ai_loadout_profile == "rocket_strike", "one loadout for whole flight")
	_expect(not service.can_launch("Archer"), "equipment edit restores hold")
	# Exercise physical hardpoint mounting with a small aircraft fixture.
	var armed := RigidBody3D.new()
	armed.freeze = true
	root.add_child(armed)
	for i in range(3):
		var point := Hardpoint.new()
		point.gun_only = i == 0
		armed.add_child(point)
	fdm._apply_ai_loadout_profile(armed, "rocket_strike")
	_expect(armed.get_child(0).has_gun_mounted(), "flight preset retains reserved gun")
	_expect(armed.get_child(1).mounted_weapon.resource_path == DECK.WEAPON_SCENE_ROCKET_POD, "flight preset mounts rocket pod")
	_expect(armed.get_child(2).mounted_weapon.resource_path == DECK.WEAPON_SCENE_ROCKET_POD, "flight preset mounts matching second pod")
	await get_tree().process_frame
	await get_tree().process_frame
	armed.free()
	service.assign("repair", "Archer")
	service.auto_assign_pilots("Archer")
	service.set_hold("Archer", false)
	_expect(not service.can_launch("Archer"), "repair blocks entire flight dispatch")
	service.service_hangar(fdm, 80.0)
	_expect(service.can_launch("Archer"), "completed repair restores readiness")
	var saved: Dictionary = fdm.capture_save_state()
	var assembly_saved: Dictionary = service.capture_save_state()
	var roster_saved: Dictionary = pilots.capture_save_state()
	service.plans.clear()
	fdm.stored_aircraft.clear()
	fdm.restore_save_state(saved)
	service.restore_save_state(assembly_saved)
	pilots.restore_save_state(roster_saved)
	_expect(service.stored("one").metadata.assembly_pilot_id == pilot_id, "pilot survives save restore")
	_expect(service.can_launch("Archer"), "composition readiness survives save restore")
	_expect(service.stored("repair").current_health == 100.0, "repair survives save restore")
	# Exact ID selection uses the real queue/reservation functions, bypassing only physical transport.
	fdm.current_state = DECK.DeckState.IDLE
	var ids: Array[String] = ["two", "one", "repair"]
	_expect(fdm.queue_ai_flight(3, ops, "", "res://Aircraft/Aircraft_1.tscn", ids) == 3, "accept chosen flight")
	var reserved: Dictionary = fdm._reserve_next_parallel_ai_aircraft()
	_expect(reserved.metadata.airframe_id == "two", "reserve requested individual first")
	_expect(reserved.requested_ai_loadout_profile == "rocket_strike", "launch retains chosen loadout")
	_expect(not service.unassign("one").is_empty(), "launch reservations cannot be edited")
	var live := RigidBody3D.new()
	live.scene_file_path = reserved.scene_file
	root.add_child(live)
	for key in reserved.metadata: live.set_meta(key, reserved.metadata[key])
	_expect(manager.bind_pilot_to_live_aircraft(live, reserved), "bind selected pilot")
	_expect(str(live.get_meta("pilot_roster_id")) == str(reserved.metadata.assembly_pilot_id), "launch uses exact selected pilot")
	var airborne_save: Dictionary = fdm.capture_deployed_aircraft_save_state(live)
	_expect(not airborne_save.has("requested_ai_loadout_profile"), "airborne restore must not rearm spent ammunition")
	var airborne_pilots: Dictionary = pilots.capture_save_state()
	pilots.restore_save_state(airborne_pilots)
	_expect(manager.bind_pilot_to_live_aircraft(live, reserved), "active pilot assignment can rebind after loading")
	var recovered: Dictionary = fdm._extract_aircraft_data(live)
	manager.mark_aircraft_stored(live, recovered)
	_expect(recovered.metadata.airframe_id == "two", "recovery keeps airframe identity")
	_expect(recovered.requested_ai_loadout_profile == "rocket_strike", "recovery keeps flight equipment")
	live.free()
	fdm.stored_aircraft.append(recovered)
	fdm._finish_pending_ai_launch_request()
	fdm.current_state = DECK.DeckState.IDLE
	_expect(fdm._count_stored_aircraft_for_kind("fixed_wing") == 3, "automatic launches cannot steal reserved aircraft")
	# Losses remain legible and removable, rather than leaving hidden full slots.
	service.assign("extra", "Dingo")
	var lost: Dictionary = service.stored("extra")
	fdm.stored_aircraft.erase(lost)
	_expect(_find(service.inventory(), "extra").state == "LOST", "lost airframe retains a visible slot")
	_expect(service.unassign("extra").is_empty(), "player can clear a lost slot")
	_expect(service.plan("Dingo").ids.is_empty(), "lost slot frees flight capacity")
	fdm.stored_aircraft.append(lost)
	lost.metadata.erase("assembly_flight")
	# Render the actual UI with representative stock and repair progress.
	service.stored("repair").current_health = 45.0
	root.get_node("CarrierConsole").show_page("air_wing", true)
	await get_tree().process_frame
	await get_tree().process_frame
	var page: Control = root.get_node("CarrierConsole").get("_air_wing_page")
	_expect(page.get_debug_snapshot().layout == "assembly", "console uses assembly screen")
	var token := _token_for(page, "three")
	var rows: VBoxContainer = page.get("_flight_rows")
	var target: Control = rows.get_child(1).get_child(0).get_child(2).get_child(0)
	(rows.get_parent() as ScrollContainer).ensure_control_visible(target)
	(page.get("_workspace").get_parent() as ScrollContainer).ensure_control_visible(token)
	await get_tree().process_frame
	await _drag(token.get_global_rect().get_center(), target.get_global_rect().get_center())
	_expect(service.stored("three").metadata.get("assembly_flight", "") == "Bulldog", "real drag assigns the individual to destination flight")
	await get_tree().process_frame
	# Click the entire token, then an empty slot (controller-friendly alternative).
	token = _token_for(page, "spare")
	(page.get("_workspace").get_parent() as ScrollContainer).ensure_control_visible(token)
	await get_tree().process_frame
	_click(token.get_global_rect().position + token.size * Vector2(0.9, 0.5))
	await get_tree().process_frame
	rows = page.get("_flight_rows")
	target = rows.get_child(2).get_child(0).get_child(2).get_child(0)
	(rows.get_parent() as ScrollContainer).ensure_control_visible(target)
	await get_tree().process_frame
	_click(target.get_global_rect().get_center())
	await get_tree().process_frame
	_expect(service.stored("spare").metadata.get("assembly_flight", "") == "Crimson", "click token edge then slot assigns selected aircraft")
	page.set("_selected_unit", "Archer")
	page.call("_refresh", true)
	(page.get("_flight_rows").get_parent() as ScrollContainer).scroll_vertical = 0
	(page.get("_workspace").get_parent() as ScrollContainer).scroll_vertical = 0
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/flight_assembly_preview.png")
		page.set("_mode", "PILOTS")
		page.set("_selected_airframe", "one")
		page.call("_refresh", true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/flight_assembly_pilots.png")
		page.set("_mode", "LOADOUT")
		page.call("_refresh", true)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/flight_assembly_loadout.png")
		# Exercise the compact two-column layout on a narrower viewport as well.
		root.content_scale_size = Vector2i(1280, 720)
		page.set("_mode", "AIRCRAFT")
		await get_tree().process_frame
		page.call("_refresh", true)
		await get_tree().process_frame
		await get_tree().process_frame
		var narrow_card := _token_for(page, "one")
		_expect((narrow_card.get_parent() as GridContainer).columns == 2, "narrow flight list uses two compact card columns")
		_expect(narrow_card.get_global_rect().end.x <= page.size.x, "narrow card remains within the page")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://logs/flight_assembly_narrow.png")
	root.get_node("CarrierConsole").set_open(false)
	fdm.free()
	manager.free()
	await get_tree().process_frame
	if failures.is_empty(): print("FLIGHT_ASSEMBLY_PASS inventory type loadout pilots repair launch_ids recovery save_restore ui")
	for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _entry(id: String, model: int, health: float = 100.0) -> Dictionary:
	return {"name": "Aircraft_" + str(model), "scene_file": "res://Aircraft/Aircraft_%d.tscn" % model, "position": Vector3.ZERO, "rotation": Vector3.ZERO, "scale": Vector3.ONE, "max_health": 100.0, "current_health": health, "metadata": {"airframe_id": id}}

func _find(items: Array, id: String) -> Dictionary:
	for item in items:
		if item.id == id: return item
	return {}

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _token_for(node: Node, id: String) -> Control:
	if "airframe_id" in node and str(node.get("airframe_id")) == id: return node as Control
	for child in node.get_children():
		var found := _token_for(child, id)
		if found != null: return found
	return null

func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)

func _motion(position: Vector2, relative: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)

func _click(position: Vector2) -> void:
	_motion(position, Vector2.ZERO, false)
	_mouse(position, true)
	_mouse(position, false)

func _drag(from: Vector2, to: Vector2) -> void:
	_motion(from, Vector2.ZERO, false)
	_mouse(from, true)
	_motion(from + Vector2(25, 0), Vector2(25, 0), true)
	await get_tree().process_frame
	_expect(root.gui_is_dragging(), "mouse movement starts real drag")
	_motion(to, to - from, true)
	await get_tree().process_frame
	_mouse(to, false)
	await get_tree().process_frame
