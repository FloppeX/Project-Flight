extends SceneTree
var failures: Array[String] = []
func _initialize():
	call_deferred("run")
func run():
	create_timer(45).timeout.connect(func(): quit(1))
	var carrier=load("res://LandCarrier/LandCarrier2.tscn").instantiate()
	carrier.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(carrier)
	current_scene=carrier
	disable_logic(carrier)
	carrier.process_mode=Node.PROCESS_MODE_INHERIT
	await physics_frame
	await physics_frame
	var walk=carrier.get_node("CommanderWalkArea")
	if not walk._initialized:
		push_error("Walk area failed to initialize")
		quit(1)
		return
	for door in carrier.get_node("CarrierModel").get_children():
		if door.get_script()==load("res://LandCarrier/CarrierSlidingDoor.gd"):
			door.openness=1.0
			door._apply_pose()
	await physics_frame
	await physics_frame
	var routes=[
		["entry to half landing",Vector3(-20.425,0.04,-3.8),Vector3(-20.425,2.41,-7.85)],
		["half landing to operations",Vector3(-19.325,2.41,-7.85),Vector3(-19.325,4.78,-3.55)],
		["operations to balcony",Vector3(-20.425,4.78,-3.4),Vector3(-20.425,7.765,-8.5)],
		["balcony to bridge",Vector3(-19.35,7.765,-3.95),Vector3(-19.35,8.853,-1.55)],
		["bridge landing turn",Vector3(-19.35,8.853,-1.55),Vector3(-21.795,8.853,-1.55)],
		["bridge landing exit",Vector3(-21.795,8.853,-1.55),Vector3(-21.795,8.853,0.8)]
	]
	for placement in 2:
		if placement==1:
			carrier.position=Vector3(450,24,-280)
			carrier.rotation.y=0.63
			await physics_frame
			await physics_frame
		for route in routes:
			traverse(walk,route[1],route[2],"%s up placement %s" % [route[0],placement],placement==1)
			traverse(walk,route[2],route[1],"%s down placement %s" % [route[0],placement],placement==1)
	# Exercise the original moving-parent failure without waiting for the next
	# physics synchronization between changing the carrier and querying support.
	var anchored=carrier.get_node("CommanderBridgeSpawn").position
	anchored.y=walk._lower_floor_y
	var current=anchored
	for frame in 120:
		carrier.position+=Vector3(.2,.012,-.1)
		current=walk.constrain_commander_position(current,current)
		await physics_frame
	if absf(current.y-anchored.y)>.01:
		failures.append("Moving carrier accumulated height: %s versus %s" % [current,anchored])
	print("MOVING_CARRIER_HEIGHT ",current.y," expected ",anchored.y)
	for failure in failures:
		push_error(failure)
	print("CARRIER_STAIRS_PASS" if failures.is_empty() else "CARRIER_STAIRS_FAIL")
	if failures.is_empty() and "--capture" in OS.get_cmdline_user_args():
		await capture_stairs(carrier,walk)
	carrier.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
func traverse(walk,start:Vector3,end:Vector3,label:String,moving_carrier:bool=false):
	var position=start
	for frame in 500:
		var target=Vector3(end.x,position.y,end.z)
		if position.distance_to(target)<.005:break
		if moving_carrier:
			walk.get_parent().position+=Vector3(.12,.005,-.08)
		var next=walk.constrain_commander_position(position,position.move_toward(target,.04))
		if position.distance_to(next)<.000001:break
		position=next
	print("STAIR_ROUTE ",label," ",position," target ",end)
	if position.distance_to(end)>.09:
		failures.append(label+" blocked at "+str(position))
func disable_logic(node:Node):
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():disable_logic(child)

func capture_stairs(carrier:Node3D,walk:Node):
	var viewport=SubViewport.new()
	viewport.size=Vector2i(960,720)
	viewport.own_world_3d=false
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.world_3d=carrier.get_world_3d()
	carrier.show()
	carrier.get_node("CarrierModel").show()
	var camera=Camera3D.new()
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near=.04
	camera.fov=75
	viewport.add_child(camera)
	camera.current=true
	var env=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.08,.1,.14)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color(.8,.85,1)
	env.environment.ambient_light_energy=.65
	carrier.add_child(env)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-30,0)
	carrier.add_child(sun)
	var position=Vector3(-20.425,.04,-3.8)
	var targets=[Vector3(-20.425,2.41,-7.85),Vector3(-20.425,.04,-3.8)]
	var frame=0
	DirAccess.make_dir_recursive_absolute("D:/3D printing files/Carrier stair review/frames")
	for target in targets:
		for i in 125:
			var direction=Vector3(target.x-position.x,0,target.z-position.z).normalized()
			position=walk.constrain_commander_position(position,position.move_toward(Vector3(target.x,position.y,target.z),.04))
			camera.position=carrier.to_global(position+Vector3.UP*1.65)
			camera.look_at(carrier.to_global(position+Vector3.UP*1.5+direction*3),Vector3.UP)
			await process_frame
			await RenderingServer.frame_post_draw
			if i in [20,70]:
				viewport.get_texture().get_image().save_png("D:/3D printing files/Carrier stair review/stairs_%03d.png" % frame)
			frame+=1
			if Vector2(position.x-target.x,position.z-target.z).length()<.01:break
	viewport.queue_free()
