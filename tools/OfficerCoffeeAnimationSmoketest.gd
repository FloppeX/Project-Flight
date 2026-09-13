extends SceneTree
const REVIEW = "D:/3D printing files/Officer mug review/"
func _initialize():
	call_deferred("run")
func run():
	create_timer(90.0).timeout.connect(func():
		push_error("Coffee animation verification did not complete")
		quit(1))
	var viewport = SubViewport.new()
	viewport.size = Vector2i(800,900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage = load("res://tools/OfficerCoffeeAnimationPreview.tscn").instantiate()
	viewport.add_child(stage)
	var officer = stage.officer
	var player = officer.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton = officer.get_node("rig/Skeleton3D") as Skeleton3D
	assert(skeleton.get_bone_count()==344)
	assert(player.has_animation("Coffee_Hold") and player.has_animation("Coffee_Sip") and player.has_animation("Coffee_Walk"))
	pose(player,"Coffee_Hold",0)
	var held = []
	for i in skeleton.get_bone_count():
		held.append(skeleton.get_bone_pose(i))
	var hand = skeleton.find_bone("hand.r")
	var chest = skeleton.find_bone("spine_03.x")
	var direction = skeleton.get_bone_global_pose(hand).basis.y
	var grip_angle = rad_to_deg(atan2(-direction.z,direction.x))
	var source_angle = source_grip_angle()
	assert(absf(grip_angle-source_angle)<0.1,"Runtime grip must match the Blender source angle")
	var held_grip = skeleton.get_bone_global_pose(chest).affine_inverse()*skeleton.get_bone_global_pose(hand)
	for time in [0.0,player.get_animation("Coffee_Sip").length]:
		pose(player,"Coffee_Sip",time)
		for i in skeleton.get_bone_count():
			if not close(held[i],skeleton.get_bone_pose(i),0.0002):
				print("ENDPOINT_MISMATCH ",time," ",skeleton.get_bone_name(i)," ",held[i]," ",skeleton.get_bone_pose(i))
				quit(1)
				return
	pose(player,"Coffee_Sip",1.9)
	var fresh_sip = []
	for i in skeleton.get_bone_count():
		fresh_sip.append(skeleton.get_bone_pose(i))
	var max_grip_error = 0.0
	for time in [0.0,0.25,0.5,0.75,1.0]:
		pose(player,"Coffee_Walk",time)
		var grip = skeleton.get_bone_global_pose(chest).affine_inverse()*skeleton.get_bone_global_pose(hand)
		max_grip_error = maxf(max_grip_error,grip.origin.distance_to(held_grip.origin))
		assert(close(grip,held_grip,0.0002),"The carrying arm must stay fixed relative to the torso")
	pose(player,"Coffee_Sip",1.9)
	# A sip must not inherit stale limb transforms from a preceding walk.
	pose(player,"Coffee_Walk",0.25)
	pose(player,"Coffee_Sip",1.9)
	for i in skeleton.get_bone_count():
		if not close(fresh_sip[i],skeleton.get_bone_pose(i),0.0002):
			push_error("Sip inherited walking pose on "+skeleton.get_bone_name(i))
			quit(1)
			return
	assert(skeleton.get_bone_global_pose(hand).origin.y > 1.55,"Sip must lift the mug to the mouth")
	var max_sleeve_twist = 0.0
	for frame in 121:
		pose(player,"Coffee_Sip",frame/30.0)
		var forearm = skeleton.get_bone_global_pose(skeleton.find_bone("forearm_stretch.r")).basis.get_rotation_quaternion()
		var sleeve = skeleton.get_bone_global_pose(skeleton.find_bone("forearm_twist.r")).basis.get_rotation_quaternion()
		max_sleeve_twist = maxf(max_sleeve_twist,rad_to_deg(forearm.angle_to(sleeve)))
	assert(max_sleeve_twist<75.0,"Excessive forearm roll collapses the linear-skinned sleeve")
	officer.set_walking(true)
	assert(player.current_animation=="Coffee_Walk")
	officer.set_walking(false)
	officer.play_sip()
	player.advance(4.2)
	assert(player.current_animation=="Coffee_Hold","Sip must return automatically to hold")
	print("COFFEE_ANIMATION_SMOKETEST_PASS sip_endpoints=true walk_grip_error=%s max_sleeve_twist=%s walk_to_sip_restored=true controller_transitions=true" % [max_grip_error,max_sleeve_twist])
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.6).timeout
		stage.camera.position = Vector3(-1.9,2.0,3)
		stage.camera.look_at(Vector3(0,1.48,0.04))
		stage.camera.size = 0.85
		pose(player,"Coffee_Hold",0)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(REVIEW+"hold_godot.png")
		pose(player,"Coffee_Sip",1.9)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(REVIEW+"sip_godot.png")
		stage.camera.position = Vector3(-3,1.9,0.25)
		stage.camera.look_at(Vector3(0,1.58,0.03))
		stage.camera.size = 0.6
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(REVIEW+"sip_side_godot.png")
		stage.camera.position = Vector3(-2.4,2.1,4)
		stage.camera.look_at(Vector3(0,0.95,0))
		stage.camera.size = 2.15
		pose(player,"Coffee_Walk",0.25)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(REVIEW+"walk_godot.png")
		DirAccess.make_dir_recursive_absolute(REVIEW+"animation_frames")
		for frame in 190:
			pose(player,"Coffee_Sip" if frame<121 else "Coffee_Walk",frame/30.0 if frame<121 else fmod((frame-121)/30.0,player.get_animation("Coffee_Walk").length))
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(REVIEW+"animation_frames/%04d.png" % frame)
	viewport.queue_free()
	await process_frame
	quit()
func pose(player: AnimationPlayer, clip: String, time: float):
	player.play(clip)
	player.seek(time,true)
	player.advance(0)
	player.pause()
func close(a: Transform3D,b: Transform3D,tolerance: float):
	return a.origin.distance_to(b.origin)<tolerance and a.basis.get_scale().distance_to(b.basis.get_scale())<tolerance and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())<0.002

func source_grip_angle() -> float:
	# Read the GLB's provenance directly: Godot need not retain armature extras.
	var file = FileAccess.open("res://Models/Characters/OfficerFemaleCoffee.glb",FileAccess.READ)
	file.seek(12)
	var length = file.get_32()
	file.get_32()
	var document = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	for node in document.nodes:
		if node.get("extras",{}).has("coffee_hold_hand_azimuth_degrees"):
			return float(node.extras.coffee_hold_hand_azimuth_degrees)
	assert(false,"Source grip provenance is missing")
	return NAN
