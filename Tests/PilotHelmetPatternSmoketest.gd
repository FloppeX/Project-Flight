extends SceneTree

const Appearance := preload("res://Aircraft/PilotAppearance.gd")
const Paint := preload("res://Aircraft/Visuals/PilotHelmetPattern.gd")
const PILOT := preload("res://Models/Characters/pilot/pilot.glb")
const COCKPIT_PILOT := preload("res://Models/Characters/pilot/CockpitPilotCharacter.tscn")
var _failures: Array[String] = []
var _cleanup_materials: Array[Material] = []


func _initialize() -> void:
	call_deferred("_run")


func _palette(pattern: String = "plain") -> Dictionary:
	return {"main_color": Color(0.2, 0.27, 0.2), "main_color_dark": Color(0.1, 0.12, 0.1),
		"helmet_color_1": Color(0.72, 0.17, 0.12), "helmet_color_2": Color(0.12, 0.22, 0.35),
		"helmet_pattern": pattern, "helmet_marking_color": Color(0.96, 0.93, 0.82)}


func _run() -> void:
	await process_frame
	_test_random_helmets()
	var livery := root.get_node("Livery")
	var owner_node := Node3D.new()
	root.add_child(owner_node)
	var pilot := PILOT.instantiate() as Node3D
	owner_node.add_child(pilot)
	var mesh_instance := pilot.find_child("PilotMesh", true, false) as MeshInstance3D
	var original := mesh_instance.mesh
	var legacy := _palette()
	legacy.erase("helmet_pattern")
	legacy.erase("helmet_marking_color")
	_check(Appearance.is_valid_palette(legacy), "legacy palette remains valid")
	_check(Appearance.helmet_pattern(legacy) == "plain", "legacy colors are not rerolled")
	_check(Appearance.helmet_pattern(_palette("unknown")) == "plain", "unknown pattern falls back")
	_check(Appearance.HELMET_PATTERNS.slice(0, 4) == ["plain", "racing_stripes", "stars", "camo"], "original shader mode IDs remain stable")
	var derived: Mesh
	for pattern in Appearance.HELMET_PATTERNS:
		owner_node.set_meta(Appearance.META_KEY, _palette(pattern))
		livery.call("apply_pilot_palette_to_visual", owner_node, pilot)
		await process_frame
		var count := 0
		for surface in range(original.get_surface_count()):
			if not Paint.is_helmet_material(original.surface_get_material(surface)):
				continue
			_check(original.surface_get_material(surface).resource_name == "Helmet_Color_2", "former stripe faces use shell material")
			count += 1
			var material := mesh_instance.get_surface_override_material(surface)
			if pattern == "plain":
				_check(material is StandardMaterial3D, "plain retains standard material")
				if material is StandardMaterial3D:
					_check(material.albedo_color == _palette()["helmet_color_2"], "plain helmet has one shell color, no authored stripe")
			else:
				_check(material is ShaderMaterial, "%s applied to both helmet materials" % pattern)
				if material is ShaderMaterial:
					_check(material.get_shader_parameter("base_color") == _palette()["helmet_color_2"], "paint sits over uniform shell color")
					_check(material.get_shader_parameter("pattern_mode") == Appearance.HELMET_PATTERNS.find(pattern), "correct pattern uniform")
		_check(count >= 1, "helmet shell surfaces found after importer material merging")
		if pattern != "plain":
			if derived != null:
				_check(mesh_instance.mesh == derived, "pattern switching reuses prepared mesh")
			derived = mesh_instance.mesh
	_check(derived != original, "authored mesh is not edited")
	for surface in range(original.get_surface_count()):
		var before := original.surface_get_arrays(surface)
		var after := derived.surface_get_arrays(surface)
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX, Mesh.ARRAY_TEX_UV]:
			_check(before[channel] == after[channel], "geometry, skinning, and authored UVs preserved")
		if Paint.is_helmet_material(original.surface_get_material(surface)):
			_check(before[Mesh.ARRAY_CUSTOM0] == null, "source custom channel untouched")
			_check(after[Mesh.ARRAY_CUSTOM0] != null, "bind-pose mapping on both materials")
	var second := PILOT.instantiate() as Node3D
	owner_node.add_child(second)
	livery.call("apply_pilot_palette_to_visual", owner_node, second)
	await process_frame
	_check((second.find_child("PilotMesh", true, false) as MeshInstance3D).mesh == derived, "pooled bodies share derived geometry")
	_check(Paint.prepare_mesh(second.find_child("PilotMesh", true, false)), "preparation is idempotent")
	owner_node.set_meta(Appearance.META_KEY, legacy)
	livery.call("apply_pilot_palette_to_visual", owner_node, pilot)
	await process_frame
	for surface in range(original.get_surface_count()):
		if Paint.is_helmet_material(original.surface_get_material(surface)):
			_check(mesh_instance.get_surface_override_material(surface) is StandardMaterial3D, "reuse clears previous pilot pattern")
	var passenger := Node3D.new()
	owner_node.set_meta(Appearance.META_KEY, _palette("stars"))
	_check(Appearance.copy_palette_metadata(owner_node, passenger), "appearance transfers to rescue/passenger metadata")
	_check(passenger.get_meta(Appearance.META_KEY) == _palette("stars"), "transfer includes pattern and ink")
	passenger.free()
	var posed := COCKPIT_PILOT.instantiate() as Node3D
	owner_node.add_child(posed)
	livery.call("apply_pilot_palette_to_visual", owner_node, posed)
	var posed_mesh := posed.find_child("PilotMesh", true, false) as MeshInstance3D
	var painted_flat_mesh := posed_mesh.mesh
	_check(painted_flat_mesh.has_meta("flat_shaded_visual_mesh"), "flat-shading marker preserved")
	_check(posed.call("apply_static_baked_pose", &"piloting", 1.5), "cockpit animation samples after paint")
	_check(posed_mesh.mesh == painted_flat_mesh, "pose refresh does not rebuild mesh or lose paint mapping")
	var animation_player := posed.get_node("BakedAnimationPlayer") as AnimationPlayer
	var animation_root := animation_player.get_node(animation_player.root_node)
	var checked_tracks := 0
	for animation_name in animation_player.get_animation_list():
		var animation := animation_player.get_animation(animation_name)
		for track in range(animation.get_track_count()):
			var path := animation.track_get_path(track)
			var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			_check(target != null, "baked track node resolves: " + str(path))
			if target is Skeleton3D and path.get_subname_count() > 0:
				_check(target.find_bone(path.get_subname(0)) >= 0, "baked bone track resolves: " + str(path))
			checked_tracks += 1
	_check(checked_tracks > 100, "checked full baked animation library, not only one pose")
	var roster := root.get_node("PilotRoster")
	roster.call("start_new_campaign", 74921)
	var entries: Array = roster.call("get_carrier_roster")
	var id := str(entries[0]["id"])
	var saved_patterns: Dictionary = {}
	_check(entries.size() >= Appearance.HELMET_PATTERNS.size(), "enough roster pilots to test every design")
	for index in range(mini(entries.size(), Appearance.HELMET_PATTERNS.size())):
		var pilot_id := str(entries[index]["id"])
		var pattern := Appearance.HELMET_PATTERNS[index]
		_check(roster.call("set_pilot_helmet_pattern", pilot_id, pattern, Color.CORAL), "roster customization accepted: " + pattern)
		saved_patterns[pilot_id] = pattern
	_check(not roster.call("set_pilot_helmet_pattern", id, "invalid", Color.WHITE), "invalid customization rejected")
	var state: Dictionary = roster.call("capture_save_state")
	# Exercise the actual Variant encoding used by save data, not only references.
	state = bytes_to_var(var_to_bytes(state))
	roster.call("start_new_campaign", 381)
	_check(roster.call("restore_save_state", state), "roster restore succeeded")
	for entry: Dictionary in roster.call("get_carrier_roster"):
		if saved_patterns.has(str(entry["id"])):
			var restored: Dictionary = entry[Appearance.IDENTITY_FIELD]
			_check(Appearance.helmet_pattern(restored) == saved_patterns[str(entry["id"])], "saved pattern restored")
			_check(Appearance.helmet_marking_color(restored) == Color.CORAL, "saved ink restored")
	var legacy_state := state.duplicate(true)
	for entry: Dictionary in legacy_state["pilots"]:
		var colors: Dictionary = entry[Appearance.IDENTITY_FIELD]
		colors.erase("helmet_randomization_version")
		colors.erase("helmet_pattern")
		colors.erase("helmet_marking_color")
	_check(roster.call("restore_save_state", legacy_state), "legacy roster loads")
	var migrated: Dictionary = roster.call("capture_save_state")
	for entry: Dictionary in migrated["pilots"]:
		_check(Appearance.helmet_pattern(entry[Appearance.IDENTITY_FIELD]) != "plain", "every legacy roster pilot upgraded")
	_check(roster.call("restore_save_state", legacy_state), "legacy roster reloads")
	_check((roster.call("capture_save_state") as Dictionary)["pilots"] == migrated["pilots"], "Continue and trailer resets keep migrated colors")
	_check(roster.call("restore_save_state", migrated), "migrated save reloads")
	_check((roster.call("capture_save_state") as Dictionary)["pilots"] == migrated["pilots"], "saved migration remains stable")
	await process_frame
	# Keep material RIDs alive until the renderer has consumed queued mesh
	# teardown. The dummy renderer otherwise reports null material parameters.
	for node in owner_node.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(surface)
			if material != null:
				_cleanup_materials.append(material)
	owner_node.queue_free()
	await process_frame
	if "--render" in OS.get_cmdline_user_args():
		await _render_preview()
	if _failures.is_empty():
		print("PILOT_HELMET_PATTERN_PASS")
	else:
		for failure in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_random_helmets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 57191
	var patterns: Dictionary = {}
	var inks: Dictionary = {}
	for index in range(512):
		var palette := Appearance.make_random_palette(rng)
		_check(Appearance.is_valid_palette(palette), "generated palette valid")
		_check(Appearance.helmet_pattern(palette) != "plain", "each random pilot gets a texture")
		_check(palette["helmet_color_1"] != palette["helmet_color_2"], "two distinct base colors")
		_check(palette["helmet_marking_color"] != palette["helmet_color_1"] \
			and palette["helmet_marking_color"] != palette["helmet_color_2"], "distinct randomized ink")
		patterns[palette["helmet_pattern"]] = true
		inks[palette["helmet_marking_color"]] = true
	_check(patterns.size() == Appearance.HELMET_PATTERNS.size() - 1, "random distribution includes every painted design")
	_check(inks.size() >= 8, "marking ink varies beyond black and cream")
	var legacy := {"id": "pilot_old_7", "name": "Test Pilot", Appearance.IDENTITY_FIELD: _palette("plain")}
	var original := legacy.duplicate(true)
	var rng_state := rng.state
	var upgraded := Appearance.ensure_identity_palette(legacy, rng)
	_check(rng.state == rng_state, "legacy upgrade does not perturb roster RNG")
	_check(upgraded["main_color"] == _palette()["main_color"] \
		and upgraded["main_color_dark"] == _palette()["main_color_dark"], "upgrade preserves suit colors")
	_check(Appearance.helmet_pattern(upgraded) != "plain", "legacy pilot receives a design")
	_check(Appearance.ensure_identity_palette(legacy, rng) == upgraded, "upgrade occurs once")
	rng.seed = 839
	_check(Appearance.ensure_identity_palette(original, rng) == upgraded, "reloading original legacy save repeats same upgrade")
	var saved_identity: Dictionary = bytes_to_var(var_to_bytes(legacy))
	_check(Appearance.ensure_identity_palette(saved_identity, rng) == upgraded, "upgraded identity survives serialization")
	(saved_identity[Appearance.IDENTITY_FIELD] as Dictionary)["helmet_pattern"] = "plain"
	_check(Appearance.helmet_pattern(Appearance.ensure_identity_palette(saved_identity, rng)) == "plain", "later manual customization is not rerolled")


func _render_preview() -> void:
	var new_only := "--new" in OS.get_cmdline_user_args()
	var random_preview := "--random" in OS.get_cmdline_user_args()
	var patterns: Array[String] = Appearance.HELMET_PATTERNS.slice(4) if new_only else Appearance.HELMET_PATTERNS
	var preview_palettes: Array[Dictionary] = []
	var preview_rng := RandomNumberGenerator.new()
	preview_rng.seed = 57191
	for pattern in patterns:
		var palette := Appearance.make_random_palette(preview_rng) if random_preview else _palette(pattern)
		if not random_preview and pattern == "flames":
			palette["helmet_marking_color"] = Color(1.0, 0.60, 0.12)
		preview_palettes.append(palette)
	var columns := mini(5, patterns.size())
	var rows_per_view := ceili(patterns.size() / float(columns))
	var sheet := SubViewport.new()
	sheet.size = Vector2i(columns * 400, rows_per_view * 960)
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var background := ColorRect.new()
	background.color = Color(0.035, 0.045, 0.06)
	background.size = Vector2(sheet.size)
	sheet.add_child(background)
	for index in range(patterns.size() * 2):
		var front_view := index < patterns.size()
		var pattern_index := index % patterns.size()
		var viewport := SubViewport.new()
		viewport.size = Vector2i(400, 420)
		viewport.own_world_3d = true
		viewport.msaa_3d = Viewport.MSAA_4X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sheet.add_child(viewport)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.065, 0.08, 0.11)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.5
		viewport.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-30, -35, 0)
		light.light_energy = 1.7
		viewport.add_child(light)
		var fill := OmniLight3D.new()
		fill.position = Vector3(0.5, 2.2, 1.5)
		fill.light_energy = 0.7
		viewport.add_child(fill)
		var pilot := PILOT.instantiate() as Node3D
		var posed_preview := "--posed" in OS.get_cmdline_user_args()
		if posed_preview:
			pilot.free()
			pilot = COCKPIT_PILOT.instantiate() as Node3D
		viewport.add_child(pilot)
		var preview_palette := preview_palettes[pattern_index]
		var pattern := Appearance.helmet_pattern(preview_palette)
		pilot.set_meta(Appearance.META_KEY, preview_palette)
		root.get_node("Livery").call("apply_pilot_palette_to_visual", pilot, pilot)
		var head_position := Vector3(0, 1.72, 0.035)
		if posed_preview:
			pilot.call("apply_static_baked_pose", &"piloting", 1.5 if front_view else 3.0)
			var skeleton := pilot.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var head := skeleton.find_bone("head.x")
			_check(head >= 0, "animated head found")
			head_position = skeleton.global_transform * skeleton.get_bone_global_pose(head).origin + Vector3(0, 0.15, 0)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = head_position + (Vector3(0.42, 0.16, 0.605) if front_view else Vector3(-0.68, 0.18, -0.30))
		camera.look_at(head_position)
		camera.fov = 38 if posed_preview else 34
		camera.near = 0.01
		camera.current = true
		var tile := TextureRect.new()
		tile.texture = viewport.get_texture()
		var row := floori(pattern_index / float(columns)) + (0 if front_view else rows_per_view)
		tile.position = Vector2((pattern_index % columns) * 400, row * 480)
		tile.size = Vector2(400, 420)
		sheet.add_child(tile)
		var label := Label.new()
		label.text = pattern.replace("_", " ").to_upper()
		label.position = tile.position + Vector2(16, 430)
		label.add_theme_font_size_override("font_size", 23)
		sheet.add_child(label)
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://pilot_helmet_patterns_posed.png" if "--posed" in OS.get_cmdline_user_args() else "user://pilot_helmet_patterns.png"
	if new_only:
		path = path.replace(".png", "_expanded.png")
	if random_preview:
		path = path.replace(".png", "_randomized.png")
	_check(sheet.get_texture().get_image().save_png(path) == OK, "preview saved")
	print("HELMET_PREVIEW ", ProjectSettings.globalize_path(path))
	sheet.queue_free()
