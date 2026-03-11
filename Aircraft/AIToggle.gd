extends Node

## Toggle between AI and Player control
## Press D-pad Up (or keyboard 'A') to toggle AI on/off

@export var ai_enabled_at_start: bool = true

var aircraft: RigidBody3D
var ai_pilot: AIPilot
var player_controls: Array[Node] = []
var ai_active: bool = false

func _ready():
	# Get aircraft reference
	aircraft = get_parent() as RigidBody3D
	if not aircraft:
		push_error("[AIToggle] Parent must be a RigidBody3D aircraft!")
		return

	# Find or create AI pilot
	ai_pilot = get_node_or_null("../AIPilot") as AIPilot
	if not ai_pilot:
		ai_pilot = AIPilot.new()
		ai_pilot.name = "AIPilot"
		aircraft.add_child(ai_pilot)

	# Initialize AI pilot
	ai_pilot.initialize(aircraft)

	# Find all player control modules
	_find_player_controls()

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
	ai_active = true

	# Disable player control modules
	for control in player_controls:
		control.set_process_input(false)
		control.set_process(false)
		control.set_physics_process(false)

	# Enable AI (re-initialize to override SimpleAero settings)
	if ai_pilot:
		ai_pilot.initialize(aircraft)
		ai_pilot.set_physics_process(true)
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
	for control in player_controls:
		control.set_process_input(true)
		control.set_process(true)
		control.set_physics_process(true)

	# Disable AI and restore SimpleAero player settings
	if ai_pilot:
		ai_pilot.deinitialize()

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
