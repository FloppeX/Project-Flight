extends SceneTree

var failures: Array[String] = []
var livery: Node
var trailer := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	livery = root.get_node("Livery")
	trailer = "--trailer" in OS.get_cmdline_user_args()
	root.get_node("GameSession").set("is_trailer_scenario", trailer)
	livery.call("set_player_livery", Color("2876a8"), Color("e9c85b"), 4)
	# Deterministic contrasting enemy palette, local to this isolated test process.
	livery.get("_team_upper_preset_indices")[2] = 4
	livery.get("_team_secondary_preset_indices")[2] = 1
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var vehicles: Array[Node3D] = []
	var types := ["buggy", "pickup", "battle_bus"]
	for index in types.size():
		var packed := load("res://GroundVehicle/vehicle_enemy_%s.tscn" % types[index]) as PackedScene
		for team in [1, 2]:
			var vehicle := packed.instantiate() as Node3D
			vehicle.set("team", team)
			vehicle.position = Vector3(index * 8.0 - 8.0, 100, (team - 1) * 13.0)
			world.add_child(vehicle)
			stop(vehicle)
			vehicles.append(vehicle)
			validate(vehicle, "%s team %d startup" % [types[index], team])
	livery.call("set_player_livery", Color("358bbd"), Color("eadb85"), 18)
	for vehicle in vehicles:
		validate(vehicle, "%s palette refresh" % vehicle.name)
	if trailer:
		var aircraft := (load("res://Aircraft/Aircraft_5.tscn") as PackedScene).instantiate() as Node3D
		aircraft.set("team", 2)
		aircraft.position = Vector3(0, 100, -17)
		world.add_child(aircraft)
		stop(aircraft)
		await process_frame
		livery.call("apply", aircraft)
		await process_frame
		validate_skull(aircraft)
		# Leaving the scenario exposes the original stored assignments, not its override.
		var primary_index: int = livery.get("_team_upper_preset_indices")[2]
		var secondary_index: int = livery.get("_team_secondary_preset_indices")[2]
		var insignia_index: int = livery.get("_team_insignia_indices")[2]
		root.get_node("GameSession").set("is_trailer_scenario", false)
		check(livery.call("_get_team_upper_color", 2) == livery.get("PRESET_UPPER_COLORS")[primary_index], "campaign primary preserved")
		check(livery.call("_get_team_secondary_color", 2) == livery.get("PRESET_UPPER_COLORS")[secondary_index], "campaign secondary preserved")
		check(livery.call("_get_team_insignia_index", 2) == insignia_index, "campaign insignia preserved")
		root.get_node("GameSession").set("is_trailer_scenario", true)
	if DisplayServer.get_name() != "headless":
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.18, 0.20, 0.23)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.7
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, -25, 0)
		world.add_child(light)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(27, 124, 40)
		camera.look_at(Vector3(0, 101, 6))
		camera.fov = 42
		camera.make_current()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/%s.png" % ("trailer_enemy_livery" if trailer else "ground_vehicle_livery"))
	print("GROUND_VEHICLE_LIVERY_%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func validate(vehicle: Node3D, label: String) -> void:
	var primary: Color = livery.call("_get_team_upper_color", vehicle.get("team"))
	var secondary: Color = livery.call("_get_team_secondary_color", vehicle.get("team"))
	if trailer and vehicle.get("team") == 2:
		check(primary.is_equal_approx(Color(0.03, 0.03, 0.03)), label + " black")
		check(secondary.is_equal_approx(Color(0.53, 0.09, 0.18)), label + " crimson")
		validate_skull(vehicle)
	var counts := [0, 0, 0]
	inspect(vehicle, primary, secondary, label, counts)
	check(counts[0] > 0 and counts[1] > 0 and counts[2] > 0, label + " covers both paint slots and details")
	print("VEHICLE_LIVERY %s primary=%s secondary=%s surfaces=%s" % [label, primary, secondary, counts])

func validate_skull(vehicle: Node3D) -> void:
	var count := 0
	for decal in get_nodes_in_group("livery_insignia"):
		if vehicle.is_ancestor_of(decal) and not decal.is_queued_for_deletion():
			count += 1
			check(decal.texture_albedo.resource_path == "res://Images/Insignia/insignia_skull.png", str(vehicle.name) + " skull decal")
	check(count > 0, str(vehicle.name) + " has insignia decals")

func inspect(node: Node, primary: Color, secondary: Color, label: String, counts: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for index in node.mesh.get_surface_count():
			var source: Material = node.mesh.surface_get_material(index)
			if source == null:
				continue
			var material_name: String = livery.call("_normalized_material_name", source)
			var active: Material = node.get_active_material(index)
			if material_name in ["body main color", "body secondary color"]:
				var slot := 0 if material_name == "body main color" else 1
				counts[slot] += 1
				check(active is StandardMaterial3D, label + " solid two-tone paint")
				if active is StandardMaterial3D:
					check(active.albedo_color.is_equal_approx(primary if slot == 0 else secondary), label + " " + material_name)
				check(active != source, label + " shared source not overridden in place")
			elif material_name.begins_with("detail color") or "wheel" in str(node.get_path()).to_lower():
				counts[2] += 1
				check(active == source, label + " preserves " + str(node.get_path()) + " " + material_name)
	for child in node.get_children():
		inspect(child, primary, secondary, label, counts)

func stop(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		stop(child)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
