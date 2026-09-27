extends "res://Tests/CarrierPositionComparison.gd"

func _sample() -> void:
	super._sample()
	if not live.has(active_id): return
	var pilot: Variant = live[active_id].pilot.get_ref()
	if not is_instance_valid(pilot): return
	_event("ALIGNMENT_CONTROL", {
		"state": pilot.State.keys()[pilot.current_state],
		"route": pilot.get_route_follow_debug_snapshot(),
		"target_g": pilot._coordinated_turn_target_g,
		"measured_g": pilot._coordinated_turn_measured_g,
		"target_aoa": pilot._coordinated_turn_target_aoa_deg,
		"measured_aoa": pilot._coordinated_turn_measured_aoa_deg,
		"velocity": pilot.aircraft.linear_velocity,
		"rotation": pilot.aircraft.rotation,
		"position": pilot.aircraft.global_position,
		"yaw": pilot.yaw_input,
		"roll": pilot.roll_input,
		"pitch": pilot.pitch_input}, false)
