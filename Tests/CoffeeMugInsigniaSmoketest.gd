extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	create_timer(30).timeout.connect(func(): quit(1))
	var livery = root.get_node("Livery")
	assert(livery.get_insignia_count()>1)
	livery.set_player_insignia(0)
	var scene = load("res://Models/Characters/OfficerFemaleCoffee.tscn")
	var first = scene.instantiate()
	root.add_child(first)
	var patch = first.find_child("CoffeeMug_Insignia",true,false)
	var authored_material = patch.mesh.surface_get_material(0)
	var material = patch.material_override
	assert(material is ShaderMaterial)
	assert(material.get_shader_parameter("insignia_texture")==livery.insignia_textures[0])
	var body = first.find_child("CoffeeMug",true,false)
	var mug_mesh = body.mesh
	first.process_mode = Node.PROCESS_MODE_DISABLED
	livery.set_player_insignia(1)
	assert(material.get_shader_parameter("insignia_texture")==livery.insignia_textures[1])
	var second = scene.instantiate()
	root.add_child(second)
	var second_material = second.find_child("CoffeeMug_Insignia",true,false).material_override
	assert(second_material != material)
	assert(second_material.get_shader_parameter("insignia_texture")==livery.get_player_insignia_texture())
	livery.cycle_insignia()
	assert(material.get_shader_parameter("insignia_texture")==livery.get_player_insignia_texture())
	assert(second_material.get_shader_parameter("insignia_texture")==livery.get_player_insignia_texture())
	assert(patch.mesh.surface_get_material(0)==authored_material and body.mesh==mug_mesh)
	if "--capture" in OS.get_cmdline_user_args():
		var viewport = SubViewport.new()
		viewport.size = Vector2i(800,650)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var preview = load("res://tools/OfficerCoffeeAnimationPreview.tscn").instantiate()
		viewport.add_child(preview)
		preview.camera.position = Vector3(-0.3,1.45,1.5)
		preview.camera.look_at(Vector3(-0.05,1.26,0.227))
		preview.camera.size = 0.32
		for index in [0,1]:
			livery.set_player_insignia(index)
			await create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("D:/3D printing files/Officer mug review/player_mug_insignia_%s.png" % index)
			print("RENDERED_INSIGNIA ",index," ",livery.get_player_insignia_texture().resource_path)
		viewport.queue_free()
	first.queue_free()
	second.queue_free()
	await process_frame
	print("COFFEE_MUG_INSIGNIA_PASS initial_selection=true live_changes=true inactive_officer=true per_instance_material=true authored_mesh_preserved=true")
	quit()
