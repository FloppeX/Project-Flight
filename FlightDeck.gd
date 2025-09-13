class_name FlightDeck
extends Node3D

# =============================================================================
# FLIGHT DECK - AIRCRAFT LAUNCH AND RECOVERY SYSTEM
# =============================================================================
# Manages aircraft operations on the carrier's flight deck
# =============================================================================

# Flight Deck Properties
@export var catapult_position: Vector3 = Vector3(0, 2, -15)
@export var catapult_force: float = 15000.0
@export var catapult_cooldown: float = 3.0
@export var arresting_cable_positions: Array[Vector3] = [
	Vector3(-5, 1, 10),
	Vector3(0, 1, 10),
	Vector3(5, 1, 10)
]
@export var arresting_cable_force: float = 8000.0
@export var elevator_position: Vector3 = Vector3(0, 0, 0)
@export var max_parked_aircraft: int = 6

# State
var parked_aircraft: Array[Aircraft] = []
var catapult_ready: bool = true
var arresting_cables_active: bool = true
var catapult_timer: float = 0.0
var carrier: LandCarrier

# Signals
signal aircraft_launched(aircraft)
signal aircraft_landed(aircraft)
signal catapult_ready_changed(ready)

func setup(carrier_node: LandCarrier):
	"""Initialize the flight deck"""
	carrier = carrier_node
	catapult_ready = true
	arresting_cables_active = true

func update(delta: float):
	"""Update flight deck systems"""
	# Update catapult cooldown
	if catapult_timer > 0:
		catapult_timer -= delta
		if catapult_timer <= 0:
			catapult_ready = true
			emit_signal("catapult_ready_changed", true)

func launch_aircraft(aircraft: Aircraft) -> bool:
	"""Launch an aircraft from the catapult"""
	if not catapult_ready or not aircraft:
		return false
	
	if aircraft in parked_aircraft:
		parked_aircraft.erase(aircraft)
	
	# Position aircraft at catapult
	aircraft.global_position = global_position + catapult_position
	aircraft.global_rotation = global_rotation
	
	# Apply catapult force
	var launch_force = -global_transform.basis.z * catapult_force
	aircraft.apply_central_force(launch_force)
	
	# Start catapult cooldown
	catapult_ready = false
	catapult_timer = catapult_cooldown
	emit_signal("catapult_ready_changed", false)
	emit_signal("aircraft_launched", aircraft)
	
	return true

func land_aircraft(aircraft: Aircraft) -> bool:
	"""Land an aircraft using arresting cables"""
	if not arresting_cables_active or not aircraft:
		return false
	
	# Check if we have space
	if parked_aircraft.size() >= max_parked_aircraft:
		return false
	
	# Position aircraft at arresting cable position
	var cable_pos = arresting_cable_positions[parked_aircraft.size() % arresting_cable_positions.size()]
	aircraft.global_position = global_position + cable_pos
	
	# Apply arresting force to slow down
	var arresting_force = aircraft.linear_velocity.normalized() * -arresting_cable_force
	aircraft.apply_central_force(arresting_force)
	
	# Add to parked aircraft
	parked_aircraft.append(aircraft)
	emit_signal("aircraft_landed", aircraft)
	
	return true

func get_parked_aircraft() -> Array[Aircraft]:
	"""Get list of parked aircraft"""
	return parked_aircraft

func get_available_parking_spots() -> int:
	"""Get number of available parking spots"""
	return max_parked_aircraft - parked_aircraft.size()

func is_catapult_ready() -> bool:
	"""Check if catapult is ready"""
	return catapult_ready

func set_arresting_cables(active: bool):
	"""Enable/disable arresting cables"""
	arresting_cables_active = active

func get_status() -> Dictionary:
	"""Get flight deck status"""
	return {
		"parked_aircraft_count": parked_aircraft.size(),
		"max_parked_aircraft": max_parked_aircraft,
		"catapult_ready": catapult_ready,
		"arresting_cables_active": arresting_cables_active,
		"catapult_cooldown_remaining": catapult_timer
	}
