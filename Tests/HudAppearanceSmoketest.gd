extends SceneTree

const SETTINGS_FIXTURE := "res://logs/hud_appearance_settings.cfg"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var settings := root.get_node("PauseMenu")
	var original_color: int = settings.get_hud_color_index()
	var original_brightness: int = settings.get_hud_brightness_index()
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var hud: Node = load("res://HUD/HeadsUpDisplay.tscn").instantiate()
	world.add_child(hud)
	await process_frame
	var buttons: Dictionary = settings.get("_gameplay_buttons")
	for key in ["hud_color", "hud_brightness"]:
		_expect(buttons.has(key) and buttons[key] is Button, "Gameplay control missing: " + key)
		if buttons.has(key):
			_expect(buttons[key].pressed.get_connections().size() > 0, "Disconnected Gameplay control: " + key)
	var lead: ColorRect = hud.get("lead_reticle_h_line")
	var lead_color := lead.color
	var compass: ColorRect = hud.get("compass_ticks")[0]
	var compass_alpha := compass.color.a
	var labels := ["GREEN", "AMBER", "BLUE", "PINK", "WHITE"]
	for color_index in range(labels.size()):
		# Settings must update existing HUDs even while gameplay is paused.
		paused = true
		settings.set_hud_appearance(color_index, 2, false)
		var color: Color = settings.get_hud_color()
		_expect((buttons["hud_color"] as Button).text == "HUD COLOR: " + labels[color_index], "Palette label mismatch")
		_expect((hud.get("horizontal_line") as ColorRect).color.is_equal_approx(color), "Crosshair did not update while paused")
		_expect((hud.get("weapon_status") as Label).get_theme_color("font_color").is_equal_approx(color), "Weapon text retained old palette")
		_expect((hud.get("speed_box_label") as Label).get_theme_color("font_color").is_equal_approx(color), "Speed text retained old palette")
		var panel: Panel = hud.get("altitude_box_panel")
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		_expect(style.border_color.is_equal_approx(color), "Altitude border retained old palette")
		_expect(style.bg_color.r == 0.0 and style.bg_color.a < 0.2, "Data box background changed")
		_expect((hud.get("target_direction_arrow").symbol_color as Color).is_equal_approx(color), "Direction arrow retained old palette")
		_expect((hud.get("ccip_circle").symbol_color as Color).is_equal_approx(color), "CCIP symbol retained old palette")
		_expect(is_equal_approx(compass.color.a, compass_alpha), "Compass opacity changed")
		_expect(Color(compass.color.r, compass.color.g, compass.color.b).is_equal_approx(color), "Compass retained old palette")
		var dim: Color = hud.get("hud_dim_color")
		_expect(dim.v < color.v, "Dim lock indication lost contrast")
		_expect((hud.get("lock_diamond_lines")[0] as ColorRect).color.is_equal_approx(dim), "Dim lock lines retained old palette")
		_expect(lead.color.is_equal_approx(lead_color), "Gun lead cue lost its distinct color")
		paused = false

	var material := (hud.get("hud_mesh") as MeshInstance3D).material_override as StandardMaterial3D
	for brightness in range(5):
		settings.set_hud_appearance(1, brightness, false)
		_expect(is_equal_approx(material.albedo_color.srgb_to_linear().r, settings.get_hud_brightness()), "HUD brightness did not update material")
		_expect((hud.get("horizontal_line") as ColorRect).color.a == 1.0, "Brightness made HUD transparent")
	_expect(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "HUD lost its lighting-independent material")

	settings.set_hud_appearance(3, 3, false)
	var fresh_hud: Node = load("res://HUD/HeadsUpDisplay.tscn").instantiate()
	world.add_child(fresh_hud)
	await process_frame
	_expect((fresh_hud.get("hud_primary_color") as Color).is_equal_approx(settings.get_hud_color()), "New HUD ignored saved preference")
	world.remove_child(fresh_hud)
	settings.set_hud_appearance(4, 4, false)
	world.add_child(fresh_hud)
	await process_frame
	_expect((fresh_hud.get("hud_primary_color") as Color).is_equal_approx(settings.get_hud_color()), "Reactivated HUD retained stale preference")

	var cfg := ConfigFile.new()
	cfg.set_value("unrelated", "preserve", 42)
	cfg.save(SETTINGS_FIXTURE)
	settings.call("_save_settings", SETTINGS_FIXTURE)
	settings.set_hud_appearance(0, 2, false)
	settings.call("_load_settings", SETTINGS_FIXTURE)
	settings.call("_apply_hud_appearance")
	_expect(settings.get_hud_color_index() == 4 and settings.get_hud_brightness_index() == 4, "HUD settings did not survive save/load")
	cfg.load(SETTINGS_FIXTURE)
	_expect(cfg.get_value("unrelated", "preserve") == 42, "HUD save removed unrelated settings")
	cfg.set_value("gameplay", "hud_color_index", -20)
	cfg.set_value("gameplay", "hud_brightness_index", 99)
	cfg.save(SETTINGS_FIXTURE)
	settings.call("_load_settings", SETTINGS_FIXTURE)
	_expect(settings.get_hud_color_index() == 0 and settings.get_hud_brightness_index() == 4, "Invalid preferences were not bounded")
	cfg.erase_section_key("gameplay", "hud_color_index")
	cfg.erase_section_key("gameplay", "hud_brightness_index")
	cfg.save(SETTINGS_FIXTURE)
	settings.call("_load_settings", SETTINGS_FIXTURE)
	_expect(settings.get_hud_color_index() == 0 and settings.get_hud_brightness_index() == 2, "Old settings did not use original green/100% defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FIXTURE))
	settings.set_hud_appearance(original_color, original_brightness, false)
	current_scene = null
	world.queue_free()
	await process_frame
	if _failures.is_empty():
		print("[HudAppearanceSmoketest] PASS palettes=5 brightness=5 paused=immediate new_and_reactivated=updated persistence=roundtrip legacy=defaults")
		quit(0)
	else:
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error("[HudAppearanceSmoketest] " + description)
