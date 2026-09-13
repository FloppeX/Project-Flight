extends Node

## Exercise the production DOGFIGHT path, not just the final blend equation.
func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var craft := preload("res://Aircraft/Aircraft_5.tscn").instantiate() as Aircraft
	craft.position = Vector3(0, 1000, 0)
	craft.freeze = true
	add_child(craft)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	var pilot: AIPilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	pilot.dogfight_enabled = true
	pilot.engagement_radius_from_carrier_m = 0
	pilot.disengage_radius_from_carrier_m = 0
	pilot._terrain_height_callable = func(_position: Vector3) -> float: return 0.0
	pilot.altitude_agl = 1000
	var target := preload("res://Scenario/GunneryTrackingBaseline.gd").ImmortalTarget.new()
	target.freeze = true
	target.add_to_group("enemies")
	target.add_to_group("ai_aircraft")
	add_child(target)
	var failures := 0
	for side in [-1.0, 1.0]:
		craft.rotation = Vector3(0, 0, side * deg_to_rad(25))
		craft.linear_velocity = Vector3(0, 0, 95)
		craft.angular_velocity = Vector3.ZERO
		target.position = craft.position + Vector3(side * 150, -200, 650)
		target.linear_velocity = Vector3(0, 0, 78)
		pilot.current_state = AIPilot.State.DOGFIGHT
		pilot.combat_target = target
		pilot._dogfight_retarget_timer_s = 10
		pilot._reset_dogfight_pursuit()
		var track = preload("res://AI/VisualContactTrack.gd").new()
		track.observe(target.position, target.linear_velocity, pilot._visual_clock_s)
		pilot._visual_contacts[target.get_instance_id()] = track
		pilot._state_dogfight(1.0 / 60.0)
		var valid := pilot.current_state == AIPilot.State.DOGFIGHT \
			and pilot._dogfight_assertive_turn_active \
			and pilot._dogfight_aim_pitch_request < 0.0 \
			and pilot.pitch_input < 0.0
		if not valid:
			failures += 1
			push_error("Downward pursuit must not inherit a legacy positive turn floor: side=%s aim=%s pitch=%s active=%s" % [
				side, pilot._dogfight_aim_pitch_request, pilot.pitch_input, pilot._dogfight_assertive_turn_active])
	print("DOGFIGHT_PITCH_OWNERSHIP_SMOKETEST checks=2 failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
