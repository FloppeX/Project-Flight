extends Node

## Toggle between AI and Player control
## Press D-pad Up (or keyboard 'A') to toggle AI on/off

@export var ai_enabled_at_start: bool = true

var aircraft: RigidBody3D
var ai_pilot: AIPilot
var helicopter_pilot: HelicopterPilot
var player_controls: Array[Node] = []
var ai_active: bool = false

func _ready():
	# Get aircraft reference
	aircraft = get_parent() as RigidBody3D
	if not aircraft:
		push_error("[AIToggle] Parent must be a RigidBody3D aircraft!")
		return

	# Find all player control modules
	_find_player_controls()

	if _is_helicopter_aircraft():
		ai_pilot = get_node_or_null("../AIPilot") as AIPilot
		helicopter_pilot = get_node_or_null("../HelicopterPilot") as HelicopterPilot
		if not helicopter_pilot:
			helicopter_pilot = HelicopterPilot.new()
			helicopter_pilot.name = "HelicopterPilot"
			aircraft.add_child(helicopter_pilot)
		if ai_pilot:
			ai_pilot.set_process(false)
			ai_pilot.set_physics_process(false)
		helicopter_pilot.set_process(false)
		helicopter_pilot.set_physics_process(false)
		if ai_enabled_at_start:
			enable_ai()
		else:
			disable_ai()
		if FlightDirector.has_method("register_aircraft"):
			FlightDirector.register_aircraft(aircraft)
		return

	# Find or create AI pilot
	ai_pilot = get_node_or_null("../AIPilot") as AIPilot
	if not ai_pilot:
		ai_pilot = AIPilot.new()
		ai_pilot.name = "AIPilot"
		aircraft.add_child(ai_pilot)

	# Initialize AI pilot
	ai_pilot.initialize(aircraft)

	# Set initial state
	if ai_enabled_at_start:
		enable_ai()
	else:
		disable_ai()

	# Register with global FlightDirector
	if FlightDirector.has_method("register_aircraft"):
		FlightDirector.register_aircraft(aircraft)

func _exit_tree():
	if is_instance_valid(aircraft) and FlightDirector.has_method("unregister_aircraft"):
		FlightDirector.unregister_aircraft(aircraft)

func _input(event):
	pass

func toggle_ai():
	"""Toggle between AI and player control"""
	if ai_active:
		disable_ai()
	else:
		enable_ai()

func enable_ai():
	"""Enable AI control, disable player controls"""
	if _is_helicopter_aircraft():
		ai_active = true
		_set_player_controls_enabled(false)
		if bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
			aircraft.set_meta("parking_brake", true)
			aircraft.linear_velocity = Vector3.ZERO
			aircraft.angular_velocity = Vector3.ZERO
			aircraft.freeze = true
		if ai_pilot:
			ai_pilot.deinitialize()
			ai_pilot.set_process(false)
			ai_pilot.set_physics_process(false)
		if helicopter_pilot:
			helicopter_pilot.initialize(aircraft)
			helicopter_pilot.set_physics_process(true)
		return

	ai_active = true

	# Disable player control modules
	_set_player_controls_enabled(false)

	# Enable AI (re-initialize to override SimpleAero settings)
	if ai_pilot:
		ai_pilot.initialize(aircraft)
		ai_pilot.set_physics_process(true)
		var arresting_engaged: bool = bool(aircraft.get_meta("arresting_engaged", false))
		var has_arresting_cable := aircraft.has_meta("arresting_cable")
		var parking_brake: bool = bool(aircraft.get_meta("parking_brake", false))
		var transport_mode: bool = bool(aircraft.get_meta("carrier_transport_mode", false))
		if arresting_engaged or has_arresting_cable:
			ai_pilot.change_state(AIPilot.State.IDLE)
			var fdm = get_tree().get_first_node_in_group("flight_deck_manager")
			if fdm and fdm.has_method("start_post_arrest_recovery"):
				fdm.start_post_arrest_recovery(aircraft)
			return
		if parking_brake or transport_mode:
			ai_pilot.change_state(AIPilot.State.IDLE)
			return
		# If deck manager owns the aircraft (catapult/recovery sequence), go to LAUNCHING.
		# This must be checked before the altitude check — the aircraft is on deck (Y > 10)
		# but controls are locked; launch() sets the correct launch_position reference point.
		if aircraft.has_meta("controls_disabled"):
			ai_pilot.launch()
		# If airborne and free, start in search mode (figure-eight patrol)
		elif aircraft.global_position.y > 10:
			# Update carrier position so figure-eight is centered correctly
			var carriers = get_tree().get_nodes_in_group("carrier")
			if carriers.size() > 0 and carriers[0] is Node3D:
				ai_pilot.carrier_position = carriers[0].global_position
			else:
				ai_pilot.carrier_position = aircraft.global_position

			# Clear old waypoints to force regeneration of figure-eight
			ai_pilot.waypoints.clear()
			ai_pilot.change_state(AIPilot.State.SEARCH)

	pass

func disable_ai():
	"""Disable AI control, enable player controls"""
	ai_active = false

	# Enable player control modules
	_set_player_controls_enabled(true)

	# Disable AI and restore SimpleAero player settings
	if ai_pilot:
		ai_pilot.deinitialize()
	if _is_helicopter_aircraft():
		# Keep helicopter deck brakes armed until the flight model sees enough
		# collective for an actual takeoff. Otherwise the first throttle nudge
		# can wake the body and let it roll off the carrier.
		if bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
			aircraft.set_meta("parking_brake", true)
		elif aircraft.has_meta("parking_brake"):
			aircraft.remove_meta("parking_brake")
		aircraft.freeze = false
		aircraft.sleeping = false
		if ai_pilot:
			ai_pilot.set_process(false)
			ai_pilot.set_physics_process(false)
		if helicopter_pilot:
			helicopter_pilot.deinitialize()
			helicopter_pilot.set_process(false)
			helicopter_pilot.set_physics_process(false)
		_apply_player_aircraft_groups()
		return

	pass

func _find_player_controls():
	"""Find all player control modules to disable when AI is active"""
	player_controls.clear()

	# Find control modules by script name
	var control_scripts = [
		"controlengine.gd",
		"controlsteering.gd",
		"controllandinggear.gd",
		"controlflaps.gd",
		"controlweapons.gd",
		"controltargeting.gd",
		"controltargeting_aam.gd"
	]

	for script_name in control_scripts:
		var nodes = _find_nodes_by_script(aircraft, script_name)
		player_controls.append_array(nodes)

	pass

func _find_nodes_by_script(root: Node, script_name: String) -> Array[Node]:
	"""Find all nodes with a specific script"""
	var found_nodes: Array[Node] = []
	for child in root.get_children():
		var script_obj = child.get_script()
		if script_obj and script_obj.resource_path.to_lower().ends_with(script_name):
			found_nodes.append(child)
		found_nodes.append_array(_find_nodes_by_script(child, script_name))
	return found_nodes

func _is_helicopter_aircraft() -> bool:
	if not is_instance_valid(aircraft):
		return false
	if bool(aircraft.get_meta("is_helicopter", false)):
		return true
	var role := str(aircraft.get_meta("aircraft_role", "")).to_lower()
	return role.find("helicopter") >= 0

func _apply_player_aircraft_groups() -> void:
	if not is_instance_valid(aircraft):
		return
	if not aircraft.is_in_group("aircraft"):
		aircraft.add_to_group("aircraft")
	if aircraft.is_in_group("ai_aircraft"):
		aircraft.remove_from_group("ai_aircraft")

	var my_team: int = aircraft.get_team() if aircraft.has_method("get_team") else 1
	if my_team == 1:
		if not aircraft.is_in_group("friendlies"):
			aircraft.add_to_group("friendlies")
		if aircraft.is_in_group("enemies"):
			aircraft.remove_from_group("enemies")
	else:
		if not aircraft.is_in_group("enemies"):
			aircraft.add_to_group("enemies")
		if aircraft.is_in_group("friendlies"):
			aircraft.remove_from_group("friendlies")

func _set_player_controls_enabled(enabled: bool) -> void:
	for control in player_controls:
		control.set_process_input(enabled)
		control.set_process(enabled)
		control.set_physics_process(enabled)
