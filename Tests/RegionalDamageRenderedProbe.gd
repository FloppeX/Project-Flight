extends Node

var world: Node3D
var camera: Camera3D
const OUTPUT := "res://captures/regional_damage"

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/"+singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	world = Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("253441")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("dbe9fa")
	env.environment.ambient_light_energy = .7
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-35,0)
	light.light_energy = 1.6
	world.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	world.add_child(camera)
	camera.position = Vector3(11,8,-14)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	for number in [1,2,3,4,5,6,7,8,14,16]:
		var craft := load("res://Aircraft/Aircraft_%d.tscn" % number).instantiate() as Aircraft
		craft.freeze = true
		craft.prevent_below_terrain = false
		world.add_child(craft)
		await get_tree().process_frame
		await get_tree().process_frame
		craft.process_mode = Node.PROCESS_MODE_DISABLED
		var ejection := craft.get_node_or_null("EjectionSequence")
		if ejection != null: ejection.auto_start_on_critical_damage = false
		camera.size = 18 if number != 14 else 12
		await capture("%02d_intact" % number)
		var model := craft.get_node("PartDamageModel") as AircraftPartDamageModel
		model.damage_zone(&"tail", model.get_zone_max_health(&"tail"))
		var debris := world.get_node_or_null("DetachedTailSection") as RigidBody3D
		assert(debris != null, "Missing tail debris")
		debris.freeze = true
		debris.position += Vector3(0,1,-3)
		camera.size += 2
		await capture("%02d_tail_lost" % number)
		if number == 5:
			model.damage_zone(&"engine", model.get_zone_max_health(&"engine")*.55)
			model.damage_zone(&"left_wing", model.get_zone_max_health(&"left_wing")*.55)
			var layer := CanvasLayer.new()
			add_child(layer)
			var mfd := MFDModule.new()
			layer.add_child(mfd)
			mfd.configure({"id":"damage_preview","modes":["MAP","DAMAGE"],"initial_mode_index":1})
			mfd.position = Vector2(780,80)
			mfd.size = Vector2(390,540)
			mfd.set_context(null,craft)
			mfd.update_from_aircraft(0.1)
			await capture("damage_page")
			layer.queue_free()
			var mount := craft.get_node("InstrumentPanel")
			var director := get_node("/root/FlightDirector")
			director.current_viewed_aircraft = craft
			director.is_player_controlling = true
			var cockpit := craft.get_node("CameraCockpit")
			(cockpit.find_child("Camera3D", true, false) as Camera3D).make_current()
			mount.set_view_updates_active(true)
			await get_tree().process_frame
			var live_panel: Node = mount.get_live_panel()
			assert(live_panel != null and mount.select_damage_page())
			live_panel.set_view_updates_active(true)
			await get_tree().create_timer(.3).timeout
			await RenderingServer.frame_post_draw
			assert(live_panel.viewport.get_texture().get_image().save_png(OUTPUT+"/cockpit_panel_damage.png") == OK)
			assert(live_panel.mfd_modules[0].mode_label.text.begins_with("DAMAGE"))
			mount.set_view_updates_active(false)
			director.current_viewed_aircraft = null
			director.is_player_controlling = false
		for child in world.get_children():
			if child is RigidBody3D: child.queue_free()
		await get_tree().process_frame
	print("REGIONAL_DAMAGE_RENDERED_PASS fleet=10")
	get_tree().quit()

func capture(label: String) -> void:
	await get_tree().create_timer(.2).timeout
	camera.make_current()
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(OUTPUT+"/"+label+".png")
	assert(error == OK)
