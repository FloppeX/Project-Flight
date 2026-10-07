extends "res://Tests/HelicopterDamageSmoketest.gd"

var camera: Camera3D
var caption: Label

func _run() -> void:
	var gear_preview := "--gear" in OS.get_cmdline_user_args()
	for singleton in ["AirOpsManager","GroundOpsManager","OperationsCoordinator","FlightDirector","EnemyVisualBudget"]:
		get_node("/root/"+singleton).process_mode = Node.PROCESS_MODE_DISABLED
	host = Node3D.new()
	add_child(host)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/helicopter_damage"))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("344754")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.85,.9,1)
	env.environment.ambient_light_energy = .8
	host.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-25,0)
	host.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19
	host.add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(35,25)
	caption.add_theme_font_size_override("font_size",30)
	canvas.add_child(caption)
	var panel := Panel.new()
	panel.position = Vector2(1460,125)
	panel.size = Vector2(400,600)
	canvas.add_child(panel)
	var diagram := preload("res://HUD/Instruments/AircraftDamageDiagram.gd").new()
	diagram.position = Vector2(20,20)
	diagram.size = Vector2(360,550)
	panel.add_child(diagram)
	diagram.set_process(false)
	for number in [9,10,11,12,13,15]:
		var craft := spawn(number)
		while not craft.runtime_initialized: await get_tree().process_frame
		prime(craft)
		craft.process_mode = Node.PROCESS_MODE_DISABLED
		var rotor := craft.get_node("RotorAssembly")
		rotor._power = .3
		rotor._update_rotor_transparency()
		var model = craft.get_node("PartDamageModel")
		var origin := craft.global_position
		camera.position = origin+(Vector3(12,4,15) if gear_preview else Vector3(11,13,-18))
		camera.look_at(origin+Vector3(1,0,0))
		camera.make_current()
		for damaged in [false,true]:
			if damaged and gear_preview:
				craft.get_node("LandingGear").shear_from_damage()
				model.systems.refresh()
				for node in host.get_children():
					if node is RigidBody3D and node != craft:
						node.freeze = true
						node.position.x += 6.0
			elif damaged:
				model.damage_zone(&"tail",1000)
				model.damage_zone(&"main_rotor",model.get_zone_max_health(&"main_rotor")*.65)
				model.damage_zone(&"engine",model.get_zone_max_health(&"engine")*.5)
				# Move the detached assembly aside to expose both fracture ends.
				for node in host.get_children():
					if node is RigidBody3D and node != craft:
						node.freeze = true
						node.position.x += 5.0
				var smoke := craft.get_node_or_null("EngineDamageSmoke")
				if smoke != null: smoke.hide()
			caption.text = "AIRCRAFT %d   %s" % [number,"TAIL DETACHED / ROTOR + ENGINE DAMAGE" if damaged else "INTACT"]
			if gear_preview: caption.text = "AIRCRAFT %d   %s" % [number,"GEAR / SKIDS TORN OFF" if damaged else "GEAR / SKIDS INTACT"]
			diagram._state = model.systems.get_display_state()
			diagram.queue_redraw()
			for frame in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var filename := "res://captures/helicopter_damage/%02d_%s%s.png" % [number,"gear_" if gear_preview else "","damaged" if damaged else "intact"]
			check(get_viewport().get_texture().get_image().save_png(filename) == OK,"save preview "+filename)
		for node in host.get_children():
			if node is PhysicsBody3D: node.queue_free()
		await get_tree().process_frame
	print("HELICOPTER_DAMAGE_PREVIEW_","PASS" if failures.is_empty() else "FAIL",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
