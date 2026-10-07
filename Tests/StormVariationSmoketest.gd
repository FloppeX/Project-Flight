extends SceneTree

var failures: Array[String] = []
var front: Node3D
var storm: Node3D
var twister: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func same_appearance(actual: Dictionary, expected: Dictionary) -> bool:
	for key in expected:
		if expected[key] is Array:
			if actual[key].size() != expected[key].size():
				return false
			for index in expected[key].size():
				if not is_equal_approx(float(actual[key][index]), float(expected[key][index])):
					return false
		elif not is_equal_approx(float(actual[key]), float(expected[key])):
			return false
	return true

func run() -> void:
	# Set display choices before the deferred settings application, without saving.
	root.get_node("PauseMenu").set("_display_mode_index", 0)
	root.get_node("PauseMenu").set("_resolution_index", 1)
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("FloatingOrigin").set("enabled", false)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	front = load("res://Weather/DustFront.gd").new() as Node3D
	world.add_child(front)
	front.set_physics_process(false)
	storm = load("res://Weather/ElectricalStorm.gd").new() as Node3D
	world.add_child(storm)
	storm.set_physics_process(false)
	twister = load("res://Weather/Twister.gd").new() as Node3D
	world.add_child(twister)
	twister.set_physics_process(false)
	front._shape_rng.seed = 47123
	storm._rng.seed = 81732
	twister._shape_rng.seed = 51652
	var widths: Array[float] = []
	var radii: Array[float] = []
	var heights: Array[float] = []
	var funnel_shapes: Dictionary = {}
	for iteration in 18:
		front.start_at(Vector3(200, -30, -100), Vector3(1, 0, 1))
		front.elapsed_s = 120.0
		front.strength = 1.0
		widths.append(front.half_width_m)
		check(front.half_width_m > 2500.0 and front.half_width_m < 12000.0, "reused dust size stays bounded")
		check(front.severity == 2, "size does not alter dust severity")
		var visuals := front.get_child(0)
		check(visuals.get_node("DistantDustWall").material_override.get_shader_parameter("outline") == front.outline,
			"wall silhouette receives the sampled outline")
		check(visuals.get_node("LocalStormFog").material.get_shader_parameter("outline") == front.outline,
			"interior fog receives the sampled outline")
		var footprint: PackedVector3Array = front.get_footprint()
		check(footprint.size() == 65 and footprint[0].is_equal_approx(footprint[-1]), "dust footprint is closed")
		for index in 16:
			var angle := TAU * index / 16.0
			var edge: Vector3 = front.get_local_edge(angle)
			check(front.get_intensity_at(front.to_global(edge * 0.7 + Vector3.UP * 30.0)) > 0.9,
				"inner outline has dense exposure")
			check(front.get_intensity_at(front.to_global(edge * 1.05 + Vector3.UP * 30.0)) == 0.0,
				"outside outline is clear")
			check(footprint[index * 4].is_equal_approx(front.to_global(edge + Vector3.UP * front.height_m * 0.2)),
				"map and physical boundary share the same outline")
		var leading: Vector3 = front.get_local_edge(PI * 0.5)
		check(absf(front.get_arrival_seconds(front.to_global(leading + Vector3(0, 30, 1000))) - 1000.0 / front.travel_speed_mps) < 0.01,
			"arrival time follows the varied leading edge")
		storm.start_at(Vector3.ZERO, Vector3.RIGHT)
		radii.append(storm.cloud_radius_m)
		check(storm.cloud_radius_m > 800.0 and storm.cloud_radius_m < 3000.0, "electrical radius stays bounded")
		var electrical_footprint: PackedVector3Array = storm.get_footprint()
		for point in electrical_footprint:
			check(absf(storm.get_cell_envelope(point) - 1.0) < 0.001, "electrical footprint matches its envelope")
		for strike in 3:
			storm._strike()
			check(storm.get_cell_envelope(storm._last_strike_impact) <= 0.821, "lightning stays within the shaped cell")
		var sparks := storm.get_node("ChargedDustLayer/CloudSparks")
		for spark in sparks.get_children():
			if spark.visible:
				check(storm.get_cell_envelope(spark.global_position) <= 0.821, "visible charge stays within the shaped cell")
		twister.start_at(Vector3.ZERO, Vector3.RIGHT)
		twister.elapsed_s = 30.0
		twister.strength = 1.0
		heights.append(twister.height_m)
		funnel_shapes[twister.funnel_profile.w] = true
		check(twister.height_m >= 770.0 and twister.height_m <= 1595.0, "reused twister height stays bounded")
		check(twister.influence_radius_m >= 412.5 and twister.influence_radius_m <= 742.5, "reused twister width stays bounded")
		for height_fraction in [0.1, 0.4, 0.7]:
			var axis: Vector3 = twister.get_axis_offset(height_fraction) + Vector3.UP * twister.height_m * height_fraction
			var wind: Vector3 = twister.get_wind_at(axis)
			check(wind.is_finite() and wind.y > 0.0, "varied twister axis has finite updraft")
			check(twister.get_wind_at(axis + Vector3.RIGHT * twister.influence_radius_m * 1.01) == Vector3.ZERO,
				"varied twister wind stops outside its influence")
			check(axis.length() > 0.0 and twister.get_footprint()[0].x >= twister.influence_radius_m + twister.get_axis_offset(height_fraction).length(),
				"map warning encloses leaning wind column")
		var twister_visuals := twister.get_child(0)
		for child in twister_visuals.get_children():
			if child is GeometryInstance3D and child.material_override is ShaderMaterial:
				check(child.material_override.get_shader_parameter("funnel_profile") == twister.funnel_profile,
					"twister shell and particles receive funnel profile")
	widths.sort()
	radii.sort()
	heights.sort()
	check(widths[-1] / widths[0] > 2.0 and radii[-1] / radii[0] > 2.0, "spawns visibly vary in scale")
	check(heights[-1] / heights[0] > 1.5 and funnel_shapes.size() == 3, "twisters vary in height and funnel shape")
	var atmosphere := load("res://Environment/DayNightCycle.gd").new() as Node
	world.add_child(atmosphere)
	var deck_material := ShaderMaterial.new()
	deck_material.shader = load("res://Environment/dust_layer_surface.gdshader")
	var volume_material := ShaderMaterial.new()
	volume_material.shader = load("res://Environment/dust_layer_volume.gdshader")
	atmosphere._dust_deck_material = deck_material
	atmosphere._dust_deck_upper_material = deck_material.duplicate()
	atmosphere._dust_deck_wall_material = deck_material.duplicate()
	atmosphere._dust_volume_material = volume_material
	atmosphere._update_electrical_storm_uniforms()
	for material in [atmosphere._dust_deck_material, atmosphere._dust_deck_upper_material,
			atmosphere._dust_deck_wall_material, volume_material]:
		check(material.get_shader_parameter("storm_outline") == storm.outline
			and material.get_shader_parameter("storm_axis_ratio") == storm.axis_ratio
			and is_equal_approx(material.get_shader_parameter("storm_yaw"), storm.shape_yaw),
			"atmosphere binds the actual cell shape to every dust surface and volume")
	storm.active = false
	atmosphere._update_electrical_storm_uniforms()
	check(deck_material.get_shader_parameter("storm_radius_m") == 0.0, "inactive electrical cell clears cloud shading")
	storm.active = true
	atmosphere.free()
	var local_probe := Vector3(100, 200, 400)
	var before: float = front.get_intensity_at(front.to_global(local_probe))
	var shift := Vector3(12000, 0, -9000)
	var old_footprint: PackedVector3Array = storm.get_footprint()
	front.global_position -= shift
	storm.global_position -= shift
	check(is_equal_approx(front.get_intensity_at(front.to_global(local_probe)), before), "origin shift preserves dust shape")
	check(storm.get_footprint()[7].is_equal_approx(old_footprint[7] - shift), "origin shift preserves electrical shape")
	var dust_appearance: Dictionary = front.capture_appearance()
	var cell_appearance: Dictionary = storm.capture_appearance()
	var funnel_appearance: Dictionary = twister.capture_appearance()
	var director := load("res://Weather/WeatherDirector.gd").new() as Node
	director.automatic_hazards = false
	world.add_child(director)
	director.set_physics_process(false)
	var save_manager := root.get_node("SaveGameManager")
	var saved: Dictionary = save_manager._decode_json_value(JSON.parse_string(JSON.stringify(
		save_manager._encode_json_value(director.capture_save_state()))))
	var restored_edge: PackedVector3Array = front.get_footprint()
	storm.free()
	twister.free()
	front.start_at(Vector3.ZERO, Vector3.BACK)
	director.restore_save_state(saved)
	storm = get_first_node_in_group("electrical_storm") as Node3D
	storm.set_physics_process(false)
	twister = get_first_node_in_group("twister") as Node3D
	twister.set_physics_process(false)
	check(same_appearance(front.capture_appearance(), dust_appearance), "JSON checkpoint restores dust dimensions and outline")
	check(same_appearance(storm.capture_appearance(), cell_appearance), "JSON checkpoint restores electrical dimensions, yaw and outline")
	check(same_appearance(twister.capture_appearance(), funnel_appearance), "JSON checkpoint restores twister height, funnel and bend")
	check(front.get_footprint()[11].is_equal_approx(restored_edge[11]), "restore preserves dust position and rotation")
	# Old checkpoints retain the original sizes instead of rolling a new storm.
	for hazard in saved.hazards:
		hazard.erase("appearance")
	storm.free()
	twister.free()
	director.restore_save_state(saved)
	storm = get_first_node_in_group("electrical_storm") as Node3D
	storm.set_physics_process(false)
	twister = get_first_node_in_group("twister") as Node3D
	twister.set_physics_process(false)
	check(is_equal_approx(front.half_width_m, 8000.0) and is_equal_approx(front.half_depth_m, 2600.0), "legacy dust retains authored dimensions")
	check(is_equal_approx(storm.cloud_radius_m, 1700.0) and storm.axis_ratio == Vector2.ONE, "legacy electrical cell retains original size")
	check(is_equal_approx(twister.height_m, 1100.0) and twister.funnel_profile == Vector4(48, 210, 70, 2), "legacy twister retains original funnel")
	if DisplayServer.get_name() != "headless":
		await render_variants(world)
	print("STORM_VARIATION_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func render_variants(world: Node3D) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("b0c5d2")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	environment.environment.volumetric_fog_enabled = true
	environment.environment.volumetric_fog_density = 0.0
	environment.environment.volumetric_fog_length = 22000.0
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.2
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.name = "StormProbeCamera"
	world.add_child(camera)
	camera.far = 60000.0
	camera.near = 10.0
	camera.make_current()
	var floor := MeshInstance3D.new()
	var ground := PlaneMesh.new()
	ground.size = Vector2(60000, 60000)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("c79368")
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material = paint
	floor.mesh = ground
	floor.name = "StormProbeGround"
	world.add_child(floor)
	var profiles := [
		{"width": 3400.0, "depth": 1400.0, "height": 1300.0, "outline": [2.0, 0.16, 0.4, 0.06]},
		{"width": 10000.0, "depth": 2300.0, "height": 2100.0, "outline": [3.0, 0.22, 2.0, 0.1]},
		{"width": 5000.0, "depth": 4000.0, "height": 2300.0, "outline": [5.0, 0.18, -1.1, 0.1]},
	]
	storm.active = false
	storm.hide()
	twister.enabled = false
	camera.position = Vector3(0, 5500, 18000)
	camera.look_at(Vector3(0, 500, 0))
	for index in profiles.size():
		front.start_at(Vector3(0, -100, 0), Vector3.BACK, profiles[index])
		front.elapsed_s = 120.0
		front.strength = 1.0
		await capture("dust_variant_%d" % index)
	front.enabled = false
	front.strength = 0.0
	# Use the actual dust-deck shader for the electrical-cell silhouette.
	var deck := MeshInstance3D.new()
	var cloud := PlaneMesh.new()
	cloud.size = Vector2(14000, 14000)
	cloud.subdivide_width = 64
	cloud.subdivide_depth = 64
	deck.mesh = cloud
	deck.position.y = 1200.0
	var material := ShaderMaterial.new()
	material.shader = load("res://Environment/dust_layer_surface.gdshader")
	material.set_shader_parameter("tint", Color(0.88, 0.76, 0.62, 0.9))
	deck.material_override = material
	world.add_child(deck)
	camera.position = Vector3(0, 12000, 11000)
	camera.look_at(Vector3(0, 1200, 0))
	storm.show()
	for index in 3:
		var profile := {"radius": [900.0, 2700.0, 2400.0][index], "aspect": [0.9, 0.8, 0.45][index],
			"yaw": [0.1, 0.7, -0.5][index], "outline": profiles[index].outline}
		storm.start_at(Vector3.ZERO, Vector3.RIGHT, profile)
		var uniforms := {"storm_center_world": storm.global_position, "storm_radius_m": storm.cloud_radius_m,
			"storm_axis_ratio": storm.axis_ratio, "storm_yaw": storm.shape_yaw, "storm_outline": storm.outline}
		for key in uniforms:
			material.set_shader_parameter(key, uniforms[key])
		storm._strike()
		await capture("electrical_variant_%d" % index)
	deck.hide()
	storm.active = false
	storm._end_strike()
	storm.hide()
	twister.enabled = true
	camera.position = Vector3(0, 900, 3500)
	camera.look_at(Vector3(0, 700, 0))
	for index in 3:
		var profile := {"height": [850.0, 1100.0, 1550.0][index], "influence": [430.0, 550.0, 700.0][index],
			"profile": [[32.0, 160.0, 45.0, 3.0], [105.0, 190.0, 85.0, 1.3], [55.0, 300.0, 65.0, 2.8]][index],
			"bend": [[40.0, 30.0], [100.0, 70.0], [180.0, 130.0]][index], "phase": [0.0, 1.0, -1.0][index]}
		twister.start_at(Vector3.ZERO, Vector3.RIGHT, profile)
		twister.elapsed_s = 30.0
		twister.strength = 1.0
		await capture("twister_variant_%d" % index)

func capture(label: String) -> void:
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	print("STORM_RENDER %s camera=%s draws=%d" % [label, root.get_camera_3d().get_path(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	check(root.get_texture().get_image().save_png("res://logs/%s.png" % label) == OK, "render saved " + label)
