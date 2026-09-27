extends "res://Tests/ContinuousRTBTest.gd"
## Two identical relative arrivals at obstructed and clear carrier poses.
## Calm weather isolates placement; authored aircraft/control settings are unchanged.

const BAD_POSITION := Vector3(-21.21289, 522.0, 2.299316)
const CLEAR_POSITION := Vector3(-144.3647, 524.6493, -2375.053)
var clear_position := false

func _run() -> void:
	batch_model = 5
	max_trials = 2
	for arg in OS.get_cmdline_user_args():
		if arg == "--clear-position": clear_position = true
	await super._run()

func _run_diagnostic_override() -> bool:
	carrier.hold_position()
	carrier.global_position = CLEAR_POSITION if clear_position else BAD_POSITION
	carrier.rotation = Vector3(0.0, -3.133704, 0.0)
	carrier.velocity = Vector3.ZERO
	var wind := get_first_node_in_group("atmospheric_wind")
	if is_instance_valid(wind): wind.enabled = false
	for i in 5: await physics_frame
	var site: Dictionary = deck.get_recovery_site_status(true)
	var corridor_clear: bool = site.status == "clear"
	_event("POSITION_CHECK", {"location": "clear" if clear_position else "obstructed",
		"carrier_position": carrier.global_position, "carrier_rotation": carrier.global_rotation,
		"corridor_clear": corridor_clear, "site_status": site, "wind_enabled": false,
		"terrain_position": current_scene.get_node("LowPolyTerrainPrototype").global_position})
	if site.status == "unchecked" or corridor_clear != clear_position:
		super._finish("unexpected_corridor_clearance")
		return true
	return await super._run_diagnostic_override()

func _batch_spawn_height(frame: Dictionary, position: Vector3, profile: Dictionary) -> float:
	# Use the same height above deck at both locations, even if one spawn needs
	# extra clearance. Otherwise terrain clamping would change the entry condition.
	var terrain: Node = current_scene.get_node("LowPolyTerrainPrototype")
	var other_carrier: Vector3 = BAD_POSITION if clear_position else CLEAR_POSITION
	var other_position := position + other_carrier - carrier.global_position
	var deck_offset := float(frame.deck_y) - carrier.global_position.y
	var height := maxf(float(profile.height), float(terrain.get_height(position)) + 200.0 - float(frame.deck_y))
	height = maxf(height, float(terrain.get_height(other_position)) + 200.0 - (other_carrier.y + deck_offset))
	return float(frame.deck_y) + height
