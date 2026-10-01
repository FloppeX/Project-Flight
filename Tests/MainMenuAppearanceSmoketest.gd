extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var saves := root.get_node("SaveGameManager")
	var session := root.get_node("GameSession")
	var before: Dictionary = session.capture_save_state()
	var pending: bool = session.has_pending_save_state()
	var save_hash := FileAccess.get_sha256(saves.SAVE_PATH) if FileAccess.file_exists(saves.SAVE_PATH) else ""
	var appearance: Dictionary = saves.load_carrier_appearance()
	_expect(session.capture_save_state() == before and session.has_pending_save_state() == pending,
		"reading menu appearance changed the campaign session")
	var menu := (load("res://UI/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	var carrier: Node3D = menu._carrier_root
	var livery := root.get_node("Livery")
	var buttons: Array = menu._main_panel.get_children().filter(func(n: Node) -> bool: return n is Button)
	_expect(buttons[0] == menu._continue_button, "Continue is not the first option")
	_expect(buttons[1].get_meta("operator_menu_label") == "NEW CAMPAIGN", "New Campaign is not second")
	if not menu._continue_button.disabled:
		_expect(root.gui_get_focus_owner() == menu._continue_button, "Continue is not initially focused")
	if not appearance.is_empty():
		_check_appearance(carrier, livery, appearance)
	await _capture("saved_carrier_main")
	menu._show_setup_menu()
	var map_before: int = menu._map_index
	menu._name_edit.text = "MANUAL TEST NAME"
	var original_name: String = menu._name_edit.text
	menu._menu_rng.seed = 20260928
	menu._randomize_button.pressed.emit()
	var draft_name: String = menu._name_edit.text
	_expect(draft_name != original_name, "Randomize did not change carrier name")
	_expect(menu._map_index == map_before, "Randomize changed the selected map")
	_expect(carrier.get_meta("carrier_display_name") == draft_name, "random name missing from carrier")
	_expect(livery._player_custom_primary_color == menu._carrier_colors[menu._primary_index], "random colour missing from preview")
	_expect(livery._player_custom_pattern_index == menu._selected_pattern_index(), "random texture missing from preview")
	_expect(livery.insignia_index == menu._insignia_index, "random insignia missing from preview")
	menu._randomize_button.grab_focus()
	await _capture("randomized_carrier_setup")
	menu._show_main_menu()
	if not appearance.is_empty():
		_check_appearance(carrier, livery, appearance)
	menu._show_setup_menu()
	_expect(menu._name_edit.text == draft_name, "returning to setup discarded the draft")
	# Custom save colours must survive exactly, even outside the preset palette.
	var custom := {"name": "CUSTOM SAVE", "primary": Color(0.137, 0.263, 0.419),
		"secondary": Color(0.813, 0.627, 0.241), "pattern": 2, "insignia": 1}
	menu._saved_carrier_appearance = custom
	menu._show_main_menu()
	_check_appearance(carrier, livery, custom)
	menu._saved_carrier_appearance = {}
	menu._apply_preview_livery()
	_expect(livery._player_custom_primary_color == menu._carrier_colors[menu._primary_index], "no-save fallback failed")
	var after_hash := FileAccess.get_sha256(saves.SAVE_PATH) if FileAccess.file_exists(saves.SAVE_PATH) else ""
	_expect(save_hash == after_hash, "menu changed the save file")
	_expect(session.capture_save_state() == before and session.has_pending_save_state() == pending,
		"preview/randomize changed campaign state")
	print("MAIN_MENU_APPEARANCE_SMOKETEST ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL",
		"saved_appearance_checked": not appearance.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _check_appearance(carrier: Node3D, livery: Node, expected: Dictionary) -> void:
	_expect(carrier.get_meta("carrier_display_name") == expected.name, "saved carrier name differs")
	_expect(livery._player_custom_primary_color == expected.primary, "saved primary colour differs")
	_expect(livery._player_custom_secondary_color == expected.secondary, "saved secondary colour differs")
	_expect(livery._player_custom_pattern_index == expected.pattern, "saved texture differs")
	_expect(livery.insignia_index == expected.insignia, "saved insignia differs")

func _capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--render"):
		return
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures/main_menu")
	root.get_texture().get_image().save_png("res://captures/main_menu/%s.png" % label)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
