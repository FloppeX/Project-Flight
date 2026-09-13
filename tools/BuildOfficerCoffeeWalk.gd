extends SceneTree
## Rebuild after exporting the coffee GLB or changing the regular officer walk.
## Transfer the existing walk's deformation in skeleton space, accounting for
## the ARP export rig's different hierarchy/rest axes. Keep the right arm rigid
## relative to the chest, with the current Coffee_Hold grip intact.
const OUTPUT = "res://Models/Characters/OfficerFemaleCoffeeAnimations.tres"
const SOURCE = "res://Models/Characters/pilot/animations/bridge_officer_animation_library.tres"

func _initialize():
	call_deferred("build")

func build():
	create_timer(30.0).timeout.connect(func():
		push_error("Coffee walk build did not complete")
		quit(1))
	var regular = load("res://Models/Characters/Bridge officer.glb").instantiate()
	var coffee = load("res://Models/Characters/OfficerFemaleCoffee.glb").instantiate()
	root.add_child(regular)
	root.add_child(coffee)
	var source = regular.find_child("Skeleton3D", true, false) as Skeleton3D
	var target = coffee.find_child("Skeleton3D", true, false) as Skeleton3D
	var holder = coffee.get_node("AnimationPlayer") as AnimationPlayer
	holder.play("Coffee_Hold")
	holder.advance(0)
	holder.pause()
	var hold = globals(target, false)
	var target_rest = globals(target, true)
	var source_rest = globals(source, true)
	var walk = load(SOURCE).get_animation("walk") as Animation
	var source_player = AnimationPlayer.new()
	regular.add_child(source_player)
	var source_library = AnimationLibrary.new()
	var source_clip = walk.duplicate() as Animation
	for i in source_clip.get_track_count():
		var bone = String(source_clip.track_get_path(i)).get_slice(":",1)
		source_clip.track_set_path(i, NodePath("%s:%s" % [regular.get_path_to(source),bone]))
	source_library.add_animation("walk",source_clip)
	source_player.add_animation_library("",source_library)
	source_player.play("walk")
	var baked = Animation.new()
	baked.length = walk.length
	baked.loop_mode = Animation.LOOP_LINEAR
	baked.step = 1.0/30.0
	var mappings = []
	var frozen = []
	for i in target.get_bone_count():
		var name = String(target.get_bone_name(i))
		var mapped = name.trim_prefix("c_").replace("arm_twist_offset", "arm_twist")
		mappings.append(source.find_bone(mapped))
		frozen.append(is_right_arm(name))
		for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
			var track = baked.add_track(type)
			baked.track_set_path(track,NodePath("rig/Skeleton3D:%s" % name))
	var chest = target.find_bone("spine_03.x")
	var source_chest = source.find_bone("spine_03.x")
	var samples = ceili(walk.length*30)+1
	var max_transfer_error = 0.0
	var max_grip_error = 0.0
	for frame in samples:
		var time = minf(frame/30.0,walk.length)
		source_player.seek(time,true)
		source_player.advance(0)
		var source_pose = globals(source,false)
		var chest_delta = source_pose[source_chest]*source_rest[source_chest].affine_inverse()
		var pose: Array[Transform3D] = []
		for i in target.get_bone_count():
			var parent = target.get_bone_parent(i)
			var transform: Transform3D
			var mapping = mappings[i]
			if frozen[i]:
				transform = chest_delta*hold[i]
			elif mapping >= 0:
				transform = source_pose[mapping]*source_rest[mapping].affine_inverse()*target_rest[i]
			else:
				transform = pose[parent]*hold[parent].affine_inverse()*hold[i] if parent>=0 else hold[i]
			pose.append(transform)
			var local = pose[parent].affine_inverse()*transform if parent>=0 else transform
			baked.position_track_insert_key(i*3,time,local.origin)
			baked.rotation_track_insert_key(i*3+1,time,local.basis.orthonormalized().get_rotation_quaternion())
			baked.scale_track_insert_key(i*3+2,time,local.basis.get_scale())
			if frozen[i]:
				max_grip_error = maxf(max_grip_error,(pose[chest].affine_inverse()*transform).origin.distance_to((hold[chest].affine_inverse()*hold[i]).origin))
			elif mapping >= 0:
				max_transfer_error = maxf(max_transfer_error,(transform*target_rest[i].affine_inverse()).origin.distance_to((source_pose[mapping]*source_rest[mapping].affine_inverse()).origin))
	var library = AnimationLibrary.new()
	for name in ["Coffee_Hold","Coffee_Sip"]:
		var clip = holder.get_animation(name).duplicate() as Animation
		clip.loop_mode = Animation.LOOP_LINEAR if name == "Coffee_Hold" else Animation.LOOP_NONE
		clip.length = maxf(clip.length, 1.0/30.0)
		# Import can omit constant tracks. Explicitly restore every bone channel
		# so switching from the full-rig walk cannot leave stale twist/limb poses.
		for i in target.get_bone_count():
			var path = NodePath("rig/Skeleton3D:%s" % target.get_bone_name(i))
			var local = target.get_bone_pose(i)
			for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
				if clip.find_track(path,type)>=0:
					continue
				var track = clip.add_track(type)
				clip.track_set_path(track,path)
				if type == Animation.TYPE_POSITION_3D:
					clip.position_track_insert_key(track,0,local.origin)
				elif type == Animation.TYPE_ROTATION_3D:
					clip.rotation_track_insert_key(track,0,local.basis.orthonormalized().get_rotation_quaternion())
				else:
					clip.scale_track_insert_key(track,0,local.basis.get_scale())
		library.add_animation(name,clip)
	library.add_animation("Coffee_Walk",baked)
	assert(ResourceSaver.save(library,OUTPUT)==OK)
	assert(max_transfer_error<0.0001)
	assert(max_grip_error<0.0001)
	print("COFFEE_WALK_BUILT samples=%s regular_motion_error=%s right_arm_chest_error=%s" % [samples,max_transfer_error,max_grip_error])
	regular.queue_free()
	coffee.queue_free()
	await process_frame
	quit()

func is_right_arm(name: String) -> bool:
	if not name.ends_with(".r"):
		return false
	for part in ["arm","shoulder","hand","thumb","index","middle","ring","pinky"]:
		if name.contains(part):
			return true
	return false

func globals(skeleton: Skeleton3D, rest: bool) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		var parent = skeleton.get_bone_parent(i)
		var local = skeleton.get_bone_rest(i) if rest else skeleton.get_bone_pose(i)
		result.append(result[parent]*local if parent>=0 else local)
	return result
