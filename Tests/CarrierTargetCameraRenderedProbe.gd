extends SceneTree

const OUTPUT_DIR := "res://captures/carrier_target_camera_probe"
const CAMERA_SCENE := preload("res://LandCarrier/CarrierTargetCamera.tscn")
const MONITOR_SCENE := preload("res://LandCarrier/MonitorStation.tscn")

class TargetProvider:
	extends Node
	var current_target: Node3D = null

class LightCycle:
	extends Node
	var darkness: float = 0.0
	func get_ai_darkness_factor() -> float:
		return darkness


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "CarrierTargetCameraRenderedProbe"
	root.add_child(scene)
	current_scene = scene

	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color("07121f")
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color("a7c5d4")
	environment_resource.ambient_light_energy = 1.2
	environment.environment = environment_resource
	scene.add_child(environment)

	var rig := CAMERA_SCENE.instantiate() as Node3D
	rig.position = Vector3(0.0, 5.0, 0.0)
	rig.set("render_only_when_monitor_visible", false)
	scene.add_child(rig)

	var target := Node3D.new()
	target.name = "CarrierCameraTarget"
	target.position = Vector3(0.0, 5.0, 80.0)
	scene.add_child(target)
	_add_target_geometry(target)

	var provider := TargetProvider.new()
	provider.current_target = target
	scene.add_child(provider)
	rig.call("register_target_provider", provider)
	rig.call("begin_control")
	rig.call("cycle_target", 1)

	var monitor := MONITOR_SCENE.instantiate() as Node3D
	scene.add_child(monitor)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(5.0, 0.05, 5.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.05, 0.0)
	scene.add_child(floor)

	var light := OmniLight3D.new()
	light.position = Vector3(0.0, 3.0, 2.0)
	light.light_energy = 5.0
	light.omni_range = 8.0
	scene.add_child(light)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.35, 2.6)
	camera.fov = 42.0
	scene.add_child(camera)
	camera.current = true

	await process_frame
	await process_frame
	var screen := monitor.find_child("computer console screen", true, false) as MeshInstance3D
	if screen == null:
		push_error("[CarrierTargetCameraRenderedProbe] screen mesh is missing")
		quit(1)
		return
	var screen_center := screen.global_transform * screen.mesh.get_aabb().get_center()
	camera.look_at(screen_center, Vector3.UP)

	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var main_image := root.get_viewport().get_texture().get_image()
	var main_path := "%s/monitor_station.png" % OUTPUT_DIR
	if main_image.save_png(main_path) != OK:
		push_error("[CarrierTargetCameraRenderedProbe] could not save monitor image")
		quit(1)
		return
	var feed_viewport := rig.get_node_or_null("CarrierTargetCameraViewport") as SubViewport
	if feed_viewport == null:
		push_error("[CarrierTargetCameraRenderedProbe] feed viewport is missing")
		quit(1)
		return
	var feed_image := feed_viewport.get_texture().get_image()
	var feed_path := "%s/mast_camera_feed.png" % OUTPUT_DIR
	if feed_image.save_png(feed_path) != OK:
		push_error("[CarrierTargetCameraRenderedProbe] could not save feed image")
		quit(1)
		return
	if _image_is_nearly_black(feed_image):
		push_error("[CarrierTargetCameraRenderedProbe] mast camera feed rendered nearly black")
		quit(1)
		return
	camera.global_transform = monitor.call("get_screen_focus_camera_transform")
	camera.fov = float(monitor.call("get_screen_focus_fov", float(root.size.x) / root.size.y))
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/focused_monitor.png" % OUTPUT_DIR)
	rig.call("begin_fullscreen_view")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/full_resolution_mast.png" % OUTPUT_DIR)
	# Verify actual light amplification, not just an enabled shader flag.
	var cycle := LightCycle.new()
	cycle.add_to_group("day_night_cycle")
	scene.add_child(cycle)
	environment_resource.ambient_light_energy = 0.08
	environment_resource.background_color = Color(0.002, 0.002, 0.002)
	var dim_material := StandardMaterial3D.new()
	dim_material.albedo_color = Color(0.65, 0.65, 0.65)
	for part in target.get_children():
		(part as MeshInstance3D).material_override = dim_material
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var dark_image := root.get_texture().get_image()
	dark_image.save_png("%s/low_light_off.png" % OUTPUT_DIR)
	cycle.darkness = 1.0
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var enhanced_image := root.get_texture().get_image()
	enhanced_image.save_png("%s/low_light_full_resolution.png" % OUTPUT_DIR)
	var center := Vector2i(enhanced_image.get_width() / 2, enhanced_image.get_height() / 2)
	var enhanced := enhanced_image.get_pixelv(center)
	var dark := dark_image.get_pixelv(center)
	var background := enhanced_image.get_pixel(center.x, enhanced_image.get_height() / 4)
	print("[CarrierTargetCameraRenderedProbe] low_light target_before=%s target_after=%s background=%s" % [dark, enhanced, background])
	if enhanced.g <= dark.g + 0.05 or enhanced.g <= enhanced.r * 2.0 \
			or enhanced.g <= background.g + 0.08:
		push_error("[CarrierTargetCameraRenderedProbe] low-light shader did not brighten the target green")
		quit(1)
		return
	rig.call("end_control")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/low_light_monitor.png" % OUTPUT_DIR)
	var night_feed := feed_viewport.get_texture().get_image()
	var feed_center := night_feed.get_pixel(night_feed.get_width() / 2, night_feed.get_height() / 2)
	if feed_center.g <= feed_center.r * 2.0 or feed_center.g <= 0.05:
		push_error("[CarrierTargetCameraRenderedProbe] low-resolution preview lacks light enhancement")
		quit(1)
		return
	cycle.darkness = 0.0
	environment_resource.ambient_light_energy = 1.2
	environment_resource.background_color = Color("07121f")
	rig.call("begin_control")
	rig.call("cycle_target", 1)
	rig.call("begin_fullscreen_view")
	rig.call("cycle_target", 1)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/free_look_monitor.png" % OUTPUT_DIR)
	rig.call("end_control")
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/restored_physical_monitor.png" % OUTPUT_DIR)

	var carrier_model_scene := load("res://Models/LandCarrier/Land carrier 4.glb") as PackedScene
	if carrier_model_scene == null:
		push_error("[CarrierTargetCameraRenderedProbe] carrier model is unavailable")
		quit(1)
		return
	var carrier_model := carrier_model_scene.instantiate() as Node3D
	carrier_model.rotation.y = PI
	scene.add_child(carrier_model)
	floor.visible = false
	rig.transform = Transform3D(
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3(-21.05627, 23.55, -7.620299)
	)
	monitor.transform = Transform3D(
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(-18.95, 8.863214, 0.0)
	)
	light.position = Vector3(-21.0, 11.0, 0.0)
	light.omni_range = 6.0
	await process_frame
	screen_center = screen.global_transform * screen.mesh.get_aabb().get_center()
	camera.position = Vector3(-21.4, 10.1, 0.0)
	camera.look_at(screen_center, Vector3.UP)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var command_image := root.get_viewport().get_texture().get_image()
	if command_image.save_png("%s/command_room_placement.png" % OUTPUT_DIR) != OK:
		push_error("[CarrierTargetCameraRenderedProbe] could not save command room image")
		quit(1)
		return

	monitor.transform.origin = Vector3(-23.4, 13.34352, -4.35)
	light.position = Vector3(-21.0, 15.2, -4.35)
	await process_frame
	screen_center = screen.global_transform * screen.mesh.get_aabb().get_center()
	camera.position = Vector3(-20.8, 14.55, -4.35)
	camera.look_at(screen_center, Vector3.UP)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var air_ops_image := root.get_viewport().get_texture().get_image()
	if air_ops_image.save_png("%s/air_ops_placement.png" % OUTPUT_DIR) != OK:
		push_error("[CarrierTargetCameraRenderedProbe] could not save Air Ops image")
		quit(1)
		return
	print("[CarrierTargetCameraRenderedProbe] PASS output=%s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _add_target_geometry(target: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ff6d42")
	material.emission_enabled = true
	material.emission = Color("ff421f")
	material.emission_energy_multiplier = 3.0
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(11.0, 2.5, 4.0)
	body.mesh = body_mesh
	body.material_override = material
	target.add_child(body)
	var wing := MeshInstance3D.new()
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(24.0, 0.5, 3.0)
	wing.mesh = wing_mesh
	wing.material_override = material
	target.add_child(wing)


func _image_is_nearly_black(image: Image) -> bool:
	var sample_count := 0
	var luminance_sum := 0.0
	for y in range(0, image.get_height(), 12):
		for x in range(0, image.get_width(), 12):
			var color := image.get_pixel(x, y)
			luminance_sum += maxf(color.r, maxf(color.g, color.b))
			sample_count += 1
	return sample_count == 0 or luminance_sum / float(sample_count) < 0.01
