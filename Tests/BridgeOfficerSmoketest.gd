extends SceneTree


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "BridgeOfficerSmoketest"
	root.add_child(scene)
	current_scene = scene

	var officer_scene := load("res://Models/Characters/Bridge officer.glb") as PackedScene
	_expect(officer_scene != null, "bridge officer GLB did not import as a PackedScene")
	if officer_scene != null:
		var officer := officer_scene.instantiate() as Node3D
		_expect(officer != null, "bridge officer GLB did not instantiate")
		if officer != null:
			scene.add_child(officer)
			var body_mesh := officer.find_child("Officer female_001", true, false) as MeshInstance3D
			var sunglasses := officer.find_child("sunglasses", true, false) as MeshInstance3D
			var skeleton := officer.find_child("Skeleton3D", true, false) as Skeleton3D
			_expect(body_mesh != null, "bridge officer body mesh is missing")
			_expect(sunglasses != null, "bridge officer sunglasses are missing")
			_expect(skeleton != null and skeleton.get_bone_count() >= 60, "bridge officer skeleton did not import")
			_expect(
				body_mesh != null and body_mesh.get_skin_reference() != null,
				"bridge officer body mesh is not bound to its skeleton"
			)
			_expect(
				sunglasses != null and sunglasses.get_skin_reference() != null,
				"bridge officer sunglasses are not bound to the skeleton"
			)
			if body_mesh != null:
				var height_m := body_mesh.get_aabb().size.y * body_mesh.scale.y
				_expect(height_m > 1.7 and height_m < 2.0, "bridge officer is not human scale: %.3f m" % height_m)
			officer.free()

	var commander_scene := load("res://LandCarrier/Commander.tscn") as PackedScene
	_expect(commander_scene != null, "Commander scene did not load")
	if commander_scene != null:
		var commander := commander_scene.instantiate() as CharacterBody3D
		scene.add_child(commander)
		await process_frame
		var body_visual := commander.get_node_or_null("BodyVisual") as Node3D
		var rig_controls := body_visual.find_child("cs_grp", true, false) as Node3D \
			if body_visual != null else null
		var animation_player := body_visual.get_node_or_null("BakedAnimationPlayer") as AnimationPlayer \
			if body_visual != null else null
		var officer_skeleton := body_visual.find_child("Skeleton3D", true, false) as Skeleton3D \
			if body_visual != null else null
		_expect(body_visual != null, "Commander does not instance the bridge officer")
		_expect(rig_controls == null or not rig_controls.visible, "exported bridge-officer rig controls remain visible")
		_expect(animation_player != null, "bridge officer animation player is missing")
		_expect(officer_skeleton != null, "bridge officer visible skeleton is missing")
		_expect(animation_player != null and animation_player.has_animation(&"idle_breathing"), "bridge officer breathing idle animation is missing")
		_expect(animation_player != null and animation_player.has_animation(&"idle_neutral"), "bridge officer neutral idle animation is missing")
		for idle_index in range(3, 8):
			var idle_name := StringName("idle_%d" % idle_index)
			_expect(
				animation_player != null and animation_player.has_animation(idle_name),
				"bridge officer %s animation is missing" % idle_name
			)
		_expect(animation_player != null and animation_player.has_animation(&"walk"), "bridge officer walk animation is missing")
		_expect(commander.get_node_or_null("CollisionShape3D") != null, "Commander collision was lost")
		_expect(commander.get_node_or_null("Camera3D") != null, "Commander first-person camera was lost")
		_expect(commander.get_node_or_null("CameraTransitionAnchor") != null, "Commander transition anchor was lost")

		commander.call("_update_body_visibility", false)
		_expect(body_visual != null and body_visual.visible, "bridge officer is hidden in external carrier views")
		commander.call("_update_body_visibility", true)
		_expect(body_visual != null and not body_visual.visible, "bridge officer obstructs the first-person carrier view")

		commander.set_physics_process(false)
		commander.call("_set_officer_moving", false)
		_expect(
			animation_player != null \
				and animation_player.assigned_animation == &"idle_neutral" \
				and animation_player.is_playing(),
			"stationary Commander did not select the officer idle animation"
		)
		var movement_start := commander.position
		Input.action_press("pitch_up", 1.0)
		commander.call("_physics_process", 0.1)
		Input.action_release("pitch_up")
		_expect(
			commander.position.distance_to(movement_start) > 0.01 \
				and animation_player != null \
				and animation_player.assigned_animation == &"walk" \
				and animation_player.is_playing(),
			"actual Commander movement did not select the officer walk animation"
		)
		commander.call("_physics_process", 0.1)
		_expect(
			animation_player != null and animation_player.assigned_animation == &"idle_neutral",
			"officer did not return to idle after movement stopped"
		)

		var officer_forward := -commander.basis.z.normalized()
		var arrow_up_start := commander.position
		_send_physical_key(commander, KEY_UP, true)
		commander.call("_physics_process", 0.1)
		_send_physical_key(commander, KEY_UP, false)
		var arrow_up_delta := commander.position - arrow_up_start
		_expect(
			arrow_up_delta.length() > 0.01 and arrow_up_delta.dot(officer_forward) < 0.0,
			"Up arrow did not move the Commander backward"
		)

		commander.call("_physics_process", 0.1)
		var arrow_down_start := commander.position
		_send_physical_key(commander, KEY_DOWN, true)
		commander.call("_physics_process", 0.1)
		_send_physical_key(commander, KEY_DOWN, false)
		var arrow_down_delta := commander.position - arrow_down_start
		_expect(
			arrow_down_delta.length() > 0.01 \
				and arrow_down_delta.dot(officer_forward) > 0.0 \
				and arrow_up_delta.dot(arrow_down_delta) < 0.0,
			"Down arrow did not move the Commander forward"
		)

		commander.call("_physics_process", 0.1)
		var arrow_turn_start := commander.rotation.y
		_send_physical_key(commander, KEY_RIGHT, true)
		commander.call("_physics_process", 0.1)
		_send_physical_key(commander, KEY_RIGHT, false)
		_expect(
			commander.rotation.y < arrow_turn_start,
			"Right arrow did not turn the Commander right"
		)

		var arrow_left_start := commander.rotation.y
		_send_physical_key(commander, KEY_LEFT, true)
		commander.call("_physics_process", 0.1)
		_send_physical_key(commander, KEY_LEFT, false)
		_expect(
			commander.rotation.y > arrow_left_start,
			"Left arrow did not turn the Commander left"
		)

		var expected_idle_cycle: Array[StringName] = [
			&"idle_3",
			&"idle_4",
			&"idle_5",
			&"idle_6",
			&"idle_7",
			&"idle_breathing",
			&"idle_neutral",
		]
		for expected_idle in expected_idle_cycle:
			_send_physical_key(commander, KEY_I, true)
			_send_physical_key(commander, KEY_I, false)
			_expect(
				commander.get("officer_idle_animation") == expected_idle \
					and animation_player != null \
					and animation_player.assigned_animation == expected_idle \
					and animation_player.is_playing(),
				"I did not select and play officer idle %s" % expected_idle
			)
			_expect(
				_animation_moves_skeleton(animation_player, officer_skeleton, expected_idle),
				"officer idle %s did not move the visible skeleton" % expected_idle
			)

		var flight_director := root.get_node_or_null("FlightDirector")
		_expect(flight_director != null, "FlightDirector autoload is unavailable")
		if flight_director != null:
			if bool(flight_director.call("is_free_camera_active")):
				flight_director.call("_toggle_free_camera")
			commander.get_node("Camera3D").current = true
			flight_director.call("_toggle_free_camera")
			var free_camera := scene.get_node_or_null("FreeCamera") as Camera3D
			_expect(
				bool(flight_director.call("is_free_camera_active")) \
					and not commander.get_node("Camera3D").current \
					and free_camera != null,
				"test could not enter the free camera"
			)
			if free_camera != null:
				var officer_focus := commander.global_position + Vector3.UP * 1.05
				var camera_to_officer := (
					officer_focus - free_camera.global_position
				).normalized()
				_expect(
					free_camera.global_position.distance_to(officer_focus) > 2.0 \
						and (-free_camera.global_basis.z).dot(camera_to_officer) > 0.99,
					"bridge free camera did not start outside and aimed at the officer"
				)

			var free_cam_walk_start := commander.position
			_send_physical_key(commander, KEY_DOWN, true)
			commander.call("_physics_process", 0.1)
			_send_physical_key(commander, KEY_DOWN, false)
			_expect(
				commander.position.distance_to(free_cam_walk_start) > 0.01,
				"arrow keys did not move the officer while the free camera was active"
			)

			var free_cam_turn_start := commander.rotation.y
			_send_physical_key(commander, KEY_RIGHT, true)
			commander.call("_physics_process", 0.1)
			_send_physical_key(commander, KEY_RIGHT, false)
			_expect(
				commander.rotation.y < free_cam_turn_start,
				"arrow keys did not turn the officer while the free camera was active"
			)

			var gamepad_only_start := commander.position
			Input.action_press("pitch_up", 1.0)
			commander.call("_physics_process", 0.1)
			Input.action_release("pitch_up")
			_expect(
				commander.position.is_equal_approx(gamepad_only_start),
				"free-camera gamepad movement also moved the officer"
			)
			flight_director.call("_toggle_free_camera")
		commander.queue_free()

	if _failures.is_empty():
		print("[BridgeOfficerSmoketest] PASS imported=true human_scale=true rig_controls_hidden=true external_visible=true first_person_hidden=true idle_cycle=7 visible_skeleton_motion=true walk=true arrows_switched=true arrow_left_right=true free_camera_third_person=true free_camera_officer_control=true gamepad_camera_only=true")
		quit(0)
	else:
		for failure in _failures:
			push_error("[BridgeOfficerSmoketest] FAIL %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _send_physical_key(target: Node, keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	target.call("_input", event)


func _animation_moves_skeleton(
		player: AnimationPlayer,
		skeleton: Skeleton3D,
		animation_name: StringName
) -> bool:
	if player == null or skeleton == null or not player.has_animation(animation_name):
		return false
	var animation := player.get_animation(animation_name)
	if animation == null or animation.length <= 0.0:
		return false
	player.seek(0.0, true)
	player.advance(0.0)
	var start_pose := _capture_bone_pose(skeleton)
	player.seek(animation.length * 0.61, true)
	player.advance(0.0)
	var sample_pose := _capture_bone_pose(skeleton)
	for bone_index in range(mini(start_pose.size(), sample_pose.size())):
		var start_transform: Transform3D = start_pose[bone_index]
		var sample_transform: Transform3D = sample_pose[bone_index]
		if start_transform.origin.distance_to(sample_transform.origin) > 0.001:
			return true
		if start_transform.basis.get_rotation_quaternion().angle_to(
			sample_transform.basis.get_rotation_quaternion()
		) > 0.001:
			return true
	return false


func _capture_bone_pose(skeleton: Skeleton3D) -> Array[Transform3D]:
	var pose: Array[Transform3D] = []
	for bone_index in range(skeleton.get_bone_count()):
		pose.append(skeleton.get_bone_pose(bone_index))
	return pose
