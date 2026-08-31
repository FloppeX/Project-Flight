extends SceneTree
## Verifies the visual animation changes at physical seat separation and does
## not restart when canopy deployment confirms the parachute state.

const COCKPIT_PILOT_SCENE := preload("res://Aircraft/CockpitPilot.tscn")
const TEST_PALETTE := {
	"main_color": Color(0.16, 0.47, 0.20),
	"main_color_dark": Color(0.17, 0.18, 0.20),
	"helmet_color_1": Color(0.86, 0.42, 0.14),
	"helmet_color_2": Color(0.20, 0.33, 0.73),
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sequence_script := load("res://Aircraft/EjectionSequence.gd") as Script
	var sequence := Node.new()
	sequence.set_script(sequence_script)
	root.add_child(sequence)
	sequence.set("parachute_deploy_delay_s", 60.0)

	var pilot_body := RigidBody3D.new()
	pilot_body.name = "AnimationHandoffPilotBody"
	root.add_child(pilot_body)
	var source_aircraft := Node3D.new()
	source_aircraft.name = "AppearanceSourceAircraft"
	source_aircraft.set_meta("pilot_livery_colors", TEST_PALETTE.duplicate(true))
	root.add_child(source_aircraft)
	sequence.call("_prepare_ejected_pilot_camera_target", source_aircraft, pilot_body)
	if pilot_body.get_meta("pilot_livery_colors", {}) != TEST_PALETTE:
		_fail("ejected pilot did not retain the source pilot appearance")
		return
	var seat := Node3D.new()
	seat.name = "EjectionSeat"
	pilot_body.add_child(seat)
	var pilot := COCKPIT_PILOT_SCENE.instantiate() as Node3D
	pilot_body.add_child(pilot)
	await process_frame
	if pilot.call("get_pilot_visual") != null:
		_fail("dormant cockpit mount checked out a reserve pilot")
		return
	pilot.call("set_presentation_active", true)
	var pooled_visual := pilot.call("get_pilot_visual") as Node3D
	var player := pooled_visual.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer \
			if pooled_visual != null else null
	if player == null:
		_fail("presented cockpit mount did not check out an animated pilot")
		return
	if player.assigned_animation != &"piloting" or not player.is_playing():
		_fail("presented cockpit pilot did not begin piloting")
		return
	pilot.call("set_presentation_active", false)
	if player.is_playing():
		_fail("dormant cockpit pilot did not stop piloting")
		return

	sequence.set("_pilot_body", pilot_body)
	sequence.call("_separate_seat_from_pilot")
	if not bool(sequence.get("_seat_separated")) or pilot_body.has_node("EjectionSeat"):
		_fail("test seat did not physically separate")
		return
	pooled_visual = pilot.call("get_pilot_visual") as Node3D
	player = pooled_visual.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer \
			if pooled_visual != null else null
	if player == null:
		_fail("ejection did not check out a physical reserve pilot")
		return
	if player.assigned_animation != &"parachute" or not player.is_playing():
		_fail("seat separation did not start the baked parachute animation")
		return
	pilot.call("set_presentation_active", false)
	if player.assigned_animation != &"parachute" or not player.is_playing():
		_fail("presentation dormancy interrupted the active ejection animation")
		return
	player.advance(0.4)
	var time_before_canopy := player.current_animation_position
	sequence.call("_ensure_pilot_parachute_animation", pilot)
	if player.assigned_animation != &"parachute" \
			or player.current_animation_position < time_before_canopy - 0.01:
		_fail("parachute confirmation restarted the active animation")
		return

	print(
		"[EjectionPilotAnimationHandoffSmoketest] PASS "
		+ "pooled=true appearance_retained=true dormant_to_parachute=seat_separation continuous_at_canopy=true"
	)
	pilot_body.free()
	source_aircraft.free()
	sequence.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[EjectionPilotAnimationHandoffSmoketest] FAIL %s" % reason)
	quit(1)
