class_name Bridge
extends Node3D

# =============================================================================
# BRIDGE - COMMAND AND CONTROL CENTER
# =============================================================================
# The player's command center for directing the carrier and managing operations
# =============================================================================

# Bridge Properties
@export var camera_position: Vector3 = Vector3(0, 15, 10)
@export var camera_rotation: Vector3 = Vector3(-30, 0, 0)
@export var map_ui_scene: PackedScene
@export var mission_ui_scene: PackedScene

# State
var carrier: LandCarrier
var is_player_controlling: bool = false
var map_ui: Control
var mission_ui: Control
var current_camera: Camera3D

# Mission Management
var active_missions: Array[Dictionary] = []
var mission_id_counter: int = 0

# Signals
signal player_entered_bridge
signal player_exited_bridge
signal mission_created(mission_id)
signal mission_completed(mission_id)
signal carrier_ordered_to_move(target_position)

func setup(carrier_node: LandCarrier):
	"""Initialize the bridge"""
	carrier = carrier_node
	setup_ui()

func setup_ui():
	"""Set up bridge UI elements"""
	# Create map UI
	if map_ui_scene:
		map_ui = map_ui_scene.instantiate()
		get_parent().add_child(map_ui)
		map_ui.visible = false
	
	# Create mission UI
	if mission_ui_scene:
		mission_ui = mission_ui_scene.instantiate()
		get_parent().add_child(mission_ui)
		mission_ui.visible = false

func update(delta: float):
	"""Update bridge systems"""
	if is_player_controlling:
		handle_bridge_input(delta)
		update_mission_status(delta)

func enter_bridge():
	"""Player enters the bridge"""
	is_player_controlling = true
	
	# Set up camera
	setup_bridge_camera()
	
	# Show UI
	if map_ui:
		map_ui.visible = true
	if mission_ui:
		mission_ui.visible = true
	
	emit_signal("player_entered_bridge")

func exit_bridge():
	"""Player exits the bridge"""
	is_player_controlling = false
	
	# Hide UI
	if map_ui:
		map_ui.visible = false
	if mission_ui:
		mission_ui.visible = false
	
	emit_signal("player_exited_bridge")

func setup_bridge_camera():
	"""Set up the bridge camera view"""
	# Find or create camera
	current_camera = get_viewport().get_camera_3d()
	if not current_camera:
		current_camera = Camera3D.new()
		get_parent().add_child(current_camera)
	
	# Position camera
	current_camera.global_position = global_position + camera_position
	current_camera.global_rotation_degrees = camera_rotation

func handle_bridge_input(delta: float):
	"""Handle input while in bridge"""
	# Map interaction
	if Input.is_action_just_pressed("map_toggle"):
		toggle_map()
	
	# Mission management
	if Input.is_action_just_pressed("mission_menu"):
		toggle_mission_menu()
	
	# Carrier movement orders
	if Input.is_action_just_pressed("order_move"):
		handle_move_order()

func toggle_map():
	"""Toggle map display"""
	if map_ui:
		map_ui.visible = !map_ui.visible

func toggle_mission_menu():
	"""Toggle mission management menu"""
	if mission_ui:
		mission_ui.visible = !mission_ui.visible

func handle_move_order():
	"""Handle carrier movement orders"""
	# This would typically involve clicking on the map
	# For now, we'll use a simple test position
	var test_position = global_position + Vector3(100, 0, 100)
	order_carrier_move(test_position)

func order_carrier_move(target_position: Vector3):
	"""Order the carrier to move to a position"""
	if carrier:
		carrier.set_target_position(target_position)
		emit_signal("carrier_ordered_to_move", target_position)

func create_mission(mission_type: String, target_position: Vector3, aircraft_count: int = 1) -> int:
	"""Create a new mission"""
	var mission_id = mission_id_counter
	mission_id_counter += 1
	
	var mission = {
		"id": mission_id,
		"type": mission_type,
		"target_position": target_position,
		"aircraft_count": aircraft_count,
		"status": "pending",
		"assigned_aircraft": [],
		"created_time": Time.get_ticks_msec()
	}
	
	active_missions.append(mission)
	emit_signal("mission_created", mission_id)
	
	return mission_id

func assign_aircraft_to_mission(mission_id: int, aircraft: Aircraft) -> bool:
	"""Assign an aircraft to a mission"""
	for mission in active_missions:
		if mission.id == mission_id and mission.status == "pending":
			if mission.assigned_aircraft.size() < mission.aircraft_count:
				mission.assigned_aircraft.append(aircraft)
				return true
	return false

func complete_mission(mission_id: int):
	"""Mark a mission as completed"""
	for mission in active_missions:
		if mission.id == mission_id:
			mission.status = "completed"
			emit_signal("mission_completed", mission_id)
			break

func update_mission_status(delta: float):
	"""Update mission status and execute missions"""
	for mission in active_missions:
		if mission.status == "pending":
			# Check if mission can be executed
			if mission.assigned_aircraft.size() >= mission.aircraft_count:
				execute_mission(mission)

func execute_mission(mission: Dictionary):
	"""Execute a mission with assigned aircraft"""
	mission.status = "executing"
	
	# Set aircraft to AI mode and give them targets
	for aircraft in mission.assigned_aircraft:
		if aircraft.has_method("set_ai_mode"):
			aircraft.set_ai_mode(true)
		if aircraft.has_method("set_target"):
			aircraft.set_target(mission.target_position)

func get_active_missions() -> Array[Dictionary]:
	"""Get list of active missions"""
	return active_missions

func get_mission_by_id(mission_id: int) -> Dictionary:
	"""Get mission by ID"""
	for mission in active_missions:
		if mission.id == mission_id:
			return mission
	return {}

func get_status() -> Dictionary:
	"""Get bridge status"""
	return {
		"player_controlling": is_player_controlling,
		"active_missions_count": active_missions.size(),
		"pending_missions": active_missions.filter(func(m): return m.status == "pending").size(),
		"executing_missions": active_missions.filter(func(m): return m.status == "executing").size()
	}














