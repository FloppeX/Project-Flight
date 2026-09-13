extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("SaveGameManager").set_process(false)
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var livery := root.get_node("Livery")
	var menu_script := load("res://UI/MainMenu.gd") as Script
	expect(menu_script != null and menu_script.can_instantiate(), "main menu no longer compiles with project autoloads")
	livery.call("set_player_insignia", 0)
	for filename in ["LandCarrier.tscn", "LandCarrier2.tscn"]:
		var carrier := (load("res://LandCarrier/" + filename) as PackedScene).instantiate() as Node3D
		# Visual authoring test: no scenario, deck operations, physics or save writes.
		carrier.set_script(null)
		for child in carrier.get_children():
			if child.name not in [&"CarrierModel", &"InsigniaHull", &"InsigniaHullR", &"ShipNameMarker"]:
				child.free()
		carrier.add_to_group("carrier")
		carrier.set_meta("carrier_display_name", "Resolute")
		host.add_child(carrier)
		if menu_script != null and menu_script.can_instantiate():
			var menu := menu_script.new() as Node
			menu.set("_carrier_root", carrier)
			expect(menu.call("_carrier_insignia_marker") == carrier.get_node("InsigniaHullR"), "setup camera cannot find new cylinder marker")
			menu.free()
		await process_frame
		livery.call("apply", carrier)
		var carried := RigidBody3D.new()
		carried.freeze = true
		carrier.add_child(carried)
		carried.add_child((load("res://Aircraft/Visuals/InsigniaMarker.tscn") as PackedScene).instantiate())
		livery.call("apply", carrier)
		expect(carried.get_child_count() == 1, "carrier stamped a carried aircraft's marker")
		carried.free()
		var name_marker := carrier.get_node("ShipNameMarker") as Decal
		expect(name_marker.basis.y.is_equal_approx(Vector3.LEFT) and name_marker.basis.z.is_equal_approx(Vector3.DOWN), "name is not upright and projecting into the port hull")
		expect(name_marker.call("get_ship_name_text") == "Resolute", "campaign name not resolved")
		expect(name_marker.get_node_or_null("_PlacementVolume") == null, "authoring box leaked into game")
		for marker_name in ["InsigniaHull", "InsigniaHullR"]:
			var marker := carrier.get_node(marker_name) as Node3D
			expect(marker.basis.z.is_equal_approx(Vector3.DOWN) and is_equal_approx(absf(marker.basis.y.x), 1.0), "insignia is not upright on side wall")
			expect(marker.has_method("get_decal_size"), filename + " missing cylinder marker")
			var decal := carrier.get_node(marker_name + "Decal") as Decal
			expect(decal.transform.is_equal_approx(marker.transform), "decal ignored marker pose")
			expect(decal.size.is_equal_approx(marker.call("get_decal_size", float(decal.texture_albedo.get_height()) / decal.texture_albedo.get_width())), "decal ignored marker size")
			expect(not marker.visible, "cylinder leaked into game")
		var marker := carrier.get_node("InsigniaHull")
		var authored_pose: Transform3D = marker.transform
		marker.set("diameter", 8.0)
		marker.set("depth", 2.0)
		marker.set("rotation", Vector3(0.2, 0.4, 0.6))
		livery.call("apply", carrier)
		var resized := carrier.get_node("InsigniaHullDecal") as Decal
		expect(is_equal_approx(resized.size.x, 8) and is_equal_approx(resized.size.y, 2), "resize not applied")
		expect(resized.transform.is_equal_approx(marker.transform), "rotation not applied")
		marker.transform = authored_pose
		marker.set("diameter", 6.0)
		marker.set("depth", 4.0)
		livery.call("apply", carrier)
		carrier.set_meta("carrier_display_name", "A Very Long Carrier Name 12345678")
		name_marker.call("refresh_ship_name")
		var label := name_marker.get_node("_NameTexture").get_child(0) as Label
		expect(label.text == "A Very Long Carrier Name 12345678", "name update failed")
		expect(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= 1024, "long name overflows")
		name_marker.set("text_override", "RESOLUTE")
		expect(name_marker.call("get_ship_name_text") == "RESOLUTE", "override not applied")
		if filename == "LandCarrier2.tscn" and "--render" in OS.get_cmdline_user_args():
			await capture(host, carrier, name_marker)
		carrier.free()
		await process_frame
	if failures.is_empty():
		print("CARRIER_MARKING_SMOKETEST_PASS scenes=2 transform=true resize=true campaign_name=true long_name=true")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func capture(host: Node3D, carrier: Node3D, marker: Decal) -> void:
	for z: float in [6.0, 15.0, 24.0]:
		var hits: Array[float] = []
		for node in carrier.get_node("CarrierModel").find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var faces := mesh.mesh.get_faces()
			var start := mesh.to_local(Vector3(-100, -12, z))
			var end := mesh.to_local(Vector3(0, -12, z))
			for i in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(start, end, faces[i], faces[i + 1], faces[i + 2])
				if hit is Vector3:
					hits.append(mesh.to_global(hit).x)
		expect(not hits.is_empty(), "no hull surface beneath name")
		if not hits.is_empty():
			expect(absf(hits.min() - marker.position.x) < marker.size.y * 0.5, "name projection does not reach outer hull")
	var light := DirectionalLight3D.new()
	host.add_child(light)
	light.rotation_degrees = Vector3(-35, -60, 0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.25, 0.3)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	host.add_child(environment)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.position = Vector3(-105, -6, 15)
	camera.look_at(marker.global_position)
	camera.fov = 35
	for i in range(20):
		await process_frame
	camera.make_current()
	await RenderingServer.frame_post_draw
	print("NAME_DECAL_POSE size=", marker.size, " transform=", marker.global_transform, " texture=", marker.texture_albedo.get_size())
	DirAccess.make_dir_recursive_absolute("res://captures/carrier_markings")
	root.get_texture().get_image().save_png("res://captures/carrier_markings/ship_name.png")
	# Also capture the texture itself to verify transparent lettering and fit.
	expect(marker.texture_albedo != null, "rendered name texture missing")
	if marker.texture_albedo != null:
		marker.texture_albedo.get_image().save_png("res://captures/carrier_markings/name_texture.png")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
