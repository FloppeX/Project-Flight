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

	pass

func _input(event):
	if Input.is_action_just_pressed("toggle_ai_pilot"):
		toggle_ai()

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
		# If airborne, start in search mode (figure-eight patrol)
		if aircraft.global_position.y > 10:
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
		# If launching, start in launching mode
		elif aircraft.has_meta("controls_disabled"):
			ai_pilot.change_state(AIPilot.State.LAUNCHING)

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
		"ControlEngine.gd",
		"ControlSteering.gd",
		"ControlLandingGear.gd",
		"ControlFlaps.gd",
		"control_weapons.gd",
		"ControlTargeting.gd"
	]

	for script_name in control_scripts:
		var nodes = _find_nodes_by_script(aircraft, script_name)
		player_controls.append_array(nodes)

	pass

func _find_nodes_by_script(root: Node, script_name: String) -> Array[Node]:
	"""Find all nodes with a specific script"""
	var found_nodes: Array[Node] = []
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with(script_name):
			found_nodes.append(child)
		found_nodes.append_array(_find_nodes_by_script(child, script_name))
	return found_nodes
