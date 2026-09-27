extends RefCounted
## Read actual aircraft state; unknown resource values remain -1, never zero.

const RECOVERY_STATES = AIPilot.RECOVERY_STATES
const DEPARTURE_STATES = AIPilot.DEPARTURE_STATES

static func aircraft_status(aircraft: Node3D) -> Dictionary:
	var result := {"name": str(aircraft.name), "available": false, "recovering": false,
		"departing": false, "reason": "No pilot", "state": "INACTIVE", "fuel": -1.0,
		"health": -1.0, "guns": 0, "bombs": 0, "rockets": 0, "weapons_known": false,
		"task": "NONE", "player_controlled": false}
	var pilot := aircraft.find_child("AIPilot", true, false) as AIPilot
	if pilot == null:
		return result
	result.state = AIPilot.State.keys()[pilot.current_state]
	result.recovering = pilot.is_recovering()
	result.departing = pilot.is_departing()
	if ("current_health" in aircraft and float(aircraft.get("current_health")) <= 0.0) or aircraft.is_queued_for_deletion() \
			or bool(aircraft.get_meta("destroyed", false)) or bool(aircraft.get_meta("dying", false)):
		result.reason = "Destroyed or initializing"
		return result
	result.merge(pilot.get_operational_resources(), true)
	var task: Variant = pilot.get_current_air_task()
	if task != null:
		result.task = task.describe()
	var director := aircraft.get_node_or_null("/root/FlightDirector")
	result.player_controlled = director != null and director.get("player_controlled_plane") == aircraft
	var coordinator := aircraft.get_node_or_null("/root/OperationsCoordinator")
	var external_order: bool = coordinator != null and coordinator.has_individual_order(aircraft)
	if result.player_controlled:
		result.reason = "Player controlled"
	elif result.recovering:
		result.reason = str(aircraft.get_meta("rtb_reason", "Returning / recovering"))
	elif result.departing:
		result.reason = "Waiting for departure"
	elif external_order:
		result.reason = "Individual order"
	elif bool(aircraft.get_meta("controls_disabled", false)) or bool(aircraft.get_meta("parking_brake", false)) \
			or bool(aircraft.get_meta("carrier_transport_mode", false)) or bool(aircraft.get_meta("arresting_engaged", false)):
		result.reason = "Deck operations"
	elif result.fuel >= 0.0 and result.fuel < pilot.rtb_fuel_threshold:
		result.reason = "Low fuel"
	elif result.health >= 0.0 and result.health < pilot.rtb_health_threshold:
		result.reason = "Low health"
	else:
		result.available = true
		result.reason = "Available"
	return result

static func can_fill(status: Dictionary, role: String) -> bool:
	if not bool(status.get("available", false)):
		return false
	# Unknown loadout does not assert that the aircraft is unarmed.
	if not bool(status.get("weapons_known", false)):
		return true
	if role in ["intercept", "cap"]:
		return int(status.guns) > 0
	return int(status.guns) + int(status.bombs) + int(status.rockets) > 0
