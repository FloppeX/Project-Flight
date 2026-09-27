extends "res://Tests/CarrierLaunchContactProbe.gd"
var injected_residual_steer := false
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(carrier): return
	var deck := carrier.get_node_or_null("FlightDeckManager")
	if deck == null: return
	var waiting: Variant = deck.get("deck_aircraft")
	if not is_instance_valid(waiting): return
	if deck.get("current_state") != deck.get_script().get_script_constant_map()["DeckState"]["RETRIEVING_FROM_HANGAR"]: return
	var ready_to_launch := bool(waiting.get_meta("physics_ready_for_launch",false))
	# Simulate a navigation correction still present during the final retrieval handoff.
	carrier.set("_current_steer",0.2)
	carrier.set("_current_yaw_rate_rad_s",deg_to_rad(0.2 if ready_to_launch else 1.0))
	if ready_to_launch and not injected_residual_steer:
		injected_residual_steer = true
		print("[LaunchTurnCarrierProbe] injected residual steer=0.20 yaw=0.20deg/s at catapult handoff")
func check(ok: bool, message: String) -> void:
	super.check(ok,message)
	if not injected_residual_steer:
		super.check(false,"turn-wait handoff was not exercised")
