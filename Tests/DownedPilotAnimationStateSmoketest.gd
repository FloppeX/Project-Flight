extends SceneTree
## Exercises grounded pilot animation selection, in-place turning, helicopter
## attention, and repeated rescue waving.

const DOWNED_PILOT_SCENE := preload("res://Models/Characters/DownedPilot.tscn")


class UnboardableHelicopterPilot:
	extends Node

	func can_accept_passenger() -> bool:
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pilot := DOWNED_PILOT_SCENE.instantiate() as RigidBody3D
	root.add_child(pilot)
	await process_frame
	pilot.set_physics_process(false)
	pilot.set("wave_interval_jitter_s", 0.0)
	pilot.set("helicopter_scan_interval_s", 0.0)
	var model := pilot.get_node_or_null("Model") as Node3D
	var player := model.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer \
			if model != null else null
	if model == null or player == null:
		_fail("downed pilot model or baked animation player is missing")
		return
	if player.assigned_animation != &"idle_breathing" or not player.is_playing():
		_fail("stationary downed pilot did not start in idle")
		return

	pilot.global_position = Vector3.ZERO
	model.quaternion = Quaternion.IDENTITY
	pilot.call("_walk_toward", Vector3(0.0, 0.0, 20.0), 3.8, 0.1)
	if player.assigned_animation != &"walk" or pilot.global_position.z <= 0.1:
		_fail("walking speed did not select walk while moving")
		return
	pilot.call("_walk_toward", Vector3(0.0, 0.0, 20.0), 5.5, 0.1)
	if player.assigned_animation != &"run":
		_fail("running speed did not select run")
		return

	pilot.global_position = Vector3.ZERO
	model.quaternion = Quaternion.IDENTITY
	pilot.set("_turning_in_place", false)
	pilot.call("_walk_toward", Vector3(20.0, 0.0, 0.0), 3.8, 0.1)
	if player.assigned_animation not in [&"turn_left", &"turn_right"]:
		_fail("large stationary heading change did not select a turn clip")
		return
	if Vector2(pilot.global_position.x, pilot.global_position.z).length() > 0.01:
		_fail("pilot translated while performing an in-place turn")
		return

	var helicopter := Node3D.new()
	helicopter.name = "AnimationTestHelicopter"
	helicopter.set_meta("is_helicopter", true)
	root.add_child(helicopter)
	helicopter.global_position = Vector3(100.0, 0.0, 0.0)
	helicopter.add_to_group("friendlies")
	var helicopter_pilot := UnboardableHelicopterPilot.new()
	helicopter_pilot.name = "HelicopterPilot"
	helicopter.add_child(helicopter_pilot)
	pilot.set("_phase", 1) # Phase.WAIT_RESCUE
	pilot.set("_turning_in_place", false)
	model.quaternion = Quaternion.IDENTITY
	for step in range(20):
		pilot.call("_physics_process", 0.1)
		if player.assigned_animation == &"wave":
			break
	if player.assigned_animation != &"wave" or not bool(pilot.get("_wave_active")):
		_fail("pilot did not face and wave to a helicopter within 1 km")
		return
	var facing := model.global_transform.basis.z.normalized()
	if facing.dot(Vector3.RIGHT) < 0.97:
		_fail("pilot waved without facing the nearby helicopter")
		return

	var wave_clip := player.get_animation(&"wave")
	player.advance(wave_clip.length + 0.1)
	pilot.call("_physics_process", 0.1)
	if player.assigned_animation != &"idle_breathing":
		_fail("pilot did not return to idle after waving")
		return
	pilot.call("_physics_process", 10.1)
	if player.assigned_animation != &"wave":
		_fail("pilot did not repeat the wave after roughly ten seconds")
		return

	player.advance(wave_clip.length + 0.1)
	helicopter.global_position = Vector3(1200.0, 0.0, 0.0)
	pilot.call("_physics_process", 0.1)
	if pilot.get("_attention_heli") != null or player.assigned_animation != &"idle_breathing":
		_fail("pilot kept signalling after the helicopter left the 1 km range")
		return

	# A helicopter may despawn between the pilot's periodic scans. The stale
	# typed reference must be cleared before _update_helicopter_attention is
	# called, otherwise Godot rejects the freed Object at the function boundary.
	pilot.set("helicopter_scan_interval_s", 10.0)
	pilot.set("_helicopter_scan_remaining_s", 10.0)
	pilot.set("_nearby_helicopter", helicopter)
	pilot.set("_attention_heli", helicopter)
	helicopter.free()
	pilot.call("_physics_process", 0.1)
	if pilot.get("_nearby_helicopter") != null or pilot.get("_attention_heli") != null:
		_fail("pilot retained a helicopter reference after that helicopter was freed")
		return

	print(
		"[DownedPilotAnimationStateSmoketest] PASS "
		+ "idle=true walk=true run=true turn=true face_heli=true wave_10s=true freed_heli_safe=true"
	)
	pilot.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error("[DownedPilotAnimationStateSmoketest] FAIL %s" % reason)
	quit(1)
