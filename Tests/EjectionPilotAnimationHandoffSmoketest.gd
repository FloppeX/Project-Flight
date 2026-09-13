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
	var camera_rig := Node3D.new()
	camera_rig.name = "CameraCockpit"
	var cockpit_camera := Camera3D.new()
	cockpit_camera.name = "Camera3D"
	camera_rig.add_child(cockpit_camera)
	pilot_body.add_child(camera_rig)
	cockpit_camera.current = true
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
	pilot.call("set_presentation_active", true)
	if player.assigned_animation != &"parachute" or not player.is_playing():
		_fail("ejection presentation refresh replaced the parachute animation")
		return
	var pilot_mesh_root := pooled_visual.get_node_or_null("Pilot") as Node3D
	if pilot_mesh_root == null or pilot_mesh_root.visible:
		_fail("current first-person ejection camera did not hide the pilot mesh")
		return
	cockpit_camera.current = false
	pooled_visual.call("_process", 0.0)
	if not pilot_mesh_root.visible:
		_fail("external ejection view did not restore the pilot mesh")
		return
	cockpit_camera.current = true
	pooled_visual.call("_process", 0.0)
	if pilot_mesh_root.visible:
		_fail("returning to first-person ejection view exposed the pilot mesh")
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

	var downed_scene := load("res://Models/Characters/DownedPilot.tscn") as PackedScene
	var downed_pilot := downed_scene.instantiate() as RigidBody3D
	root.add_child(downed_pilot)
	var landed_camera_rig := Node3D.new()
	landed_camera_rig.name = "CameraCockpit"
	var landed_camera := Camera3D.new()
	landed_camera.name = "Camera3D"
	landed_camera_rig.add_child(landed_camera)
	downed_pilot.add_child(landed_camera_rig)
	landed_camera.current = true
	sequence.call("_position_landed_camera_at_head", landed_camera_rig, downed_pilot)
	var downed_visual := downed_pilot.get_node_or_null("Model") as Node3D
	var downed_mesh_root := downed_visual.get_node_or_null("Pilot") as Node3D \
			if downed_visual != null else null
	if downed_mesh_root == null or downed_mesh_root.visible:
		_fail("landed first-person camera did not hide the downed pilot mesh")
		return
	landed_camera.current = false
	downed_visual.call("_process", 0.0)
	if not downed_mesh_root.visible:
		_fail("landed external view did not restore the downed pilot mesh")
		return

	print(
		"[EjectionPilotAnimationHandoffSmoketest] PASS "
		+ "pooled=true appearance_retained=true dormant_to_parachute=seat_separation "
		+ "continuous_at_canopy=true first_person_hidden=true external_visible=true "
		+ "landed_first_person_hidden=true"
	)
	downed_pilot.free()
	pilot_body.free()
	source_aircraft.free()
	sequence.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[EjectionPilotAnimationHandoffSmoketest] FAIL %s" % reason)
	quit(1)
