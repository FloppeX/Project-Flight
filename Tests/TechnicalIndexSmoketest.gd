extends SceneTree

const Catalog = preload("res://UI/TechnicalIndexCatalog.gd")
const TechnicalIndexView = preload("res://UI/TechnicalIndexView.gd")
const TEST_PLAYER_PATTERN_INDEX := 4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_menu_source := FileAccess.get_file_as_string("res://UI/MainMenu.gd")
	if not main_menu_source.contains("[\"TECHNICAL INDEX\", Callable(self, \"_show_technical_index\")]") \
			or not main_menu_source.contains("TechnicalIndexView.new()"):
		_fail("main menu did not expose the Technical Index route")
		return
	if main_menu_source.contains("_current_screen == \"tech_items\" and _is_menu_left_event") \
			or main_menu_source.contains("_current_screen == \"tech_items\" and _is_menu_right_event"):
		_fail("Technical Index still captured left-stick navigation for model rotation")
		return
	if not main_menu_source.contains("_pattern_choice_index = _menu_rng.randi_range(0, _pattern_names.size() - 1)"):
		_fail("main menu no longer randomized the shared player pattern by default")
		return
	var expected_categories: Array[String] = [
		"GROUND VEHICLES",
		"AIRPLANES",
		"HELICOPTERS",
		"STRUCTURES",
		"WEAPONS",
	]
	if Catalog.categories() != expected_categories:
		_fail("category order did not match the requested Technical Index")
		return
	var ground_vehicle_entries := Catalog.entries_for("GROUND VEHICLES")
	var expected_ground_vehicle_scenes: Array[String] = [
		"res://LandCarrier/LandCarrier2.tscn",
		"res://GroundVehicle/vehicle_friendly_light.tscn",
		"res://GroundVehicle/vehicle_enemy_buggy.tscn",
		"res://GroundVehicle/vehicle_enemy_pickup.tscn",
		"res://GroundVehicle/vehicle_enemy_battle_bus.tscn",
	]
	if ground_vehicle_entries.size() != expected_ground_vehicle_scenes.size():
		_fail("ground-vehicle category did not include the carrier and both team rosters")
		return
	for index in expected_ground_vehicle_scenes.size():
		if String(ground_vehicle_entries[index].get("scene", "")) != expected_ground_vehicle_scenes[index]:
			_fail("ground-vehicle catalog order was incorrect at entry %d" % index)
			return
	var airplane_entries := Catalog.entries_for("AIRPLANES")
	if airplane_entries.is_empty() or String(airplane_entries[0].get("name", "")) != "SNA AS-20 Sand Sprite":
		_fail("airplane catalog did not begin with the Sand Sprite")
		return
	if String(airplane_entries[0].get("description", "")) != "Light fighter/attack/recon plane; versatile, modular, but slightly underpowered when loaded.":
		_fail("Sand Sprite description did not match its approved index copy")
		return
	var expected_aircraft_names := {
		"res://Aircraft/Aircraft_1.tscn": "SNA AS-20 Sand Sprite",
		"res://Aircraft/Aircraft_2.tscn": "HK A-88 Crusader",
		"res://Aircraft/Aircraft_3.tscn": "VMFC F-9 Wasp",
		"res://Aircraft/Aircraft_4.tscn": "OKB TB-60 Vulture",
		"res://Aircraft/Aircraft_5.tscn": "SNA JAS-44 Kestrel",
		"res://Aircraft/Aircraft_6.tscn": "OKB Sh-37 Razorback",
		"res://Aircraft/Aircraft_7.tscn": "OKB I-109 Dagger",
		"res://Aircraft/Aircraft_8.tscn": "VAS SF/A-21 Ghost",
		"res://Aircraft/Aircraft_14.tscn": "KAW FX-5 Spitewing",
		"res://Aircraft/Aircraft_9.tscn": "VMFC HH-72 Bumblebee",
		"res://Aircraft/Aircraft_10.tscn": "TAG RA-14 Dune Skimmer",
		"res://Aircraft/Aircraft_11.tscn": "AD UH-8 Hummingbird",
		"res://Aircraft/Aircraft_12.tscn": "HK AH-99 Huntsman",
	}
	for category in ["AIRPLANES", "HELICOPTERS"]:
		for entry in Catalog.entries_for(category):
			var scene_path := String(entry.get("scene", ""))
			if expected_aircraft_names.has(scene_path) \
					and String(entry.get("name", "")) != String(expected_aircraft_names[scene_path]):
				_fail("aircraft catalog name did not match: %s" % scene_path)
				return
			if expected_aircraft_names.has(scene_path) and String(entry.get("description", "")).is_empty():
				_fail("named aircraft had no description: %s" % scene_path)
				return
			if category == "AIRPLANES":
				if String(entry.get("pilot_notes", "")).is_empty():
					_fail("fixed-wing aircraft had no pilot flight notes: %s" % scene_path)
					return
				var entry_stats := entry.get("stats", {}) as Dictionary
				if String(entry_stats.get("ROLE", "")).is_empty():
					_fail("fixed-wing aircraft had no operational role: %s" % scene_path)
					return

	var scene_count := 0
	for category in expected_categories:
		var entries := Catalog.entries_for(category)
		if entries.is_empty():
			_fail("%s had no catalog entries" % category)
			return
		for entry in entries:
			var scene_path := String(entry.get("scene", ""))
			if not ResourceLoader.exists(scene_path):
				_fail("catalog scene was missing: %s" % scene_path)
				return
			var packed := load(scene_path) as PackedScene
			if packed == null:
				_fail("catalog scene could not be loaded: %s" % scene_path)
				return
			var instance := packed.instantiate()
			if not instance is Node3D:
				instance.free()
				_fail("catalog entry was not a 3D scene: %s" % scene_path)
				return
			instance.free()
			scene_count += 1

	var view := TechnicalIndexView.new() as Control
	root.add_child(view)
	var livery := root.get_node_or_null("Livery")
	if livery == null or not livery.has_method("set_player_livery"):
		_fail("player livery singleton was unavailable to the Technical Index")
		return
	livery.call(
		"set_player_livery",
		Color(0.16, 0.47, 0.20),
		Color(0.73, 0.60, 0.44),
		TEST_PLAYER_PATTERN_INDEX
	)
	view.call("open")
	var backdrop := view.get_node_or_null("ComputerBackdrop") as ColorRect
	if backdrop == null or backdrop.position != Vector2.ZERO or backdrop.size != view.size:
		_fail("Technical Index black backdrop did not cover the full screen")
		return
	if String(view.get("current_mode")) != "tech_categories":
		_fail("Technical Index did not open on its category list")
		return
	for category in expected_categories:
		view.call("_show_category", category)
		var category_entries := Catalog.entries_for(category)
		var name_label := view.get("_name_label") as Label
		if name_label == null or name_label.text != String(category_entries[0].get("name", "")):
			_fail("%s did not automatically display its first entry" % category)
			return
		if category == "GROUND VEHICLES":
			var model_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
			if not _preview_uses_only_livery_pattern(model_root, TEST_PLAYER_PATTERN_INDEX):
				_fail("land carrier preview did not use the selected player pattern")
				return
			var track_plate_counts := _find_track_plate_counts(model_root)
			if track_plate_counts.size() != 6 or track_plate_counts.min() <= 0:
				_fail("land carrier preview did not generate all six track-segment loops")
				return
			var track_path_vertical_extents := _find_track_path_vertical_extents(model_root)
			if track_path_vertical_extents.size() != 6:
				_fail("land carrier preview did not expose all six generated track paths")
				return
			for vertical_extent in track_path_vertical_extents:
				if vertical_extent.x > -7.0 or vertical_extent.y < 9.0:
					_fail("land carrier preview tracks did not follow the authored wheel-clearance guides: %s" % [track_path_vertical_extents])
					return
			var carrier_configuration_panel := view.get_node_or_null("PreviewConfigurationControls") as Panel
			var carrier_wings_button := view.get_node_or_null("PreviewConfigurationControls/WingsButton") as Button
			var carrier_gear_button := view.get_node_or_null("PreviewConfigurationControls/LandingGearButton") as Button
			var carrier_doors_button := view.get_node_or_null("PreviewConfigurationControls/DoorsButton") as Button
			var carrier_engine_button := view.get_node_or_null("PreviewConfigurationControls/EngineButton") as Button
			var elevator_button := view.get_node_or_null("PreviewConfigurationControls/ElevatorButton") as Button
			var vehicle_bay_button := view.get_node_or_null("PreviewConfigurationControls/VehicleBayDoorButton") as Button
			if carrier_configuration_panel == null or carrier_wings_button == null \
					or carrier_gear_button == null or carrier_doors_button == null \
					or carrier_engine_button == null or elevator_button == null \
					or vehicle_bay_button == null:
				_fail("land carrier preview controls were unavailable")
				return
			if not carrier_configuration_panel.visible or carrier_wings_button.visible \
					or carrier_gear_button.visible or carrier_doors_button.visible \
					or carrier_engine_button.visible or not elevator_button.visible \
					or not vehicle_bay_button.visible:
				_fail("land carrier did not expose only its elevator and vehicle-bay controls")
				return
			if not _configuration_buttons_are_compact(
					carrier_configuration_panel,
					[
						carrier_wings_button,
						carrier_gear_button,
						carrier_doors_button,
						carrier_engine_button,
						elevator_button,
						vehicle_bay_button,
					]
			):
				_fail("land carrier configuration controls did not form a compact row")
				return

			var carrier_elevator := model_root.find_child("Elevator", true, false) as Node3D
			var elevator_platform := carrier_elevator.find_child("Platform", true, false) as Node3D if carrier_elevator != null else null
			var elevator_left_cover := carrier_elevator.find_child("LeftCover", true, false) as Node3D if carrier_elevator != null else null
			var elevator_right_cover := carrier_elevator.find_child("RightCover", true, false) as Node3D if carrier_elevator != null else null
			var vehicle_ramp := model_root.find_child("VehicleRamp", true, false) as Node3D
			var ramp_slider := vehicle_ramp.find_child("RampSlider", true, false) as Node3D if vehicle_ramp != null else null
			var ramp_inner_pivot := vehicle_ramp.find_child("InnerPivot", true, false) as Node3D if vehicle_ramp != null else null
			var ramp_middle_pivot := vehicle_ramp.find_child("MiddlePivot", true, false) as Node3D if vehicle_ramp != null else null
			var ramp_outer_pivot := vehicle_ramp.find_child("OuterPivot", true, false) as Node3D if vehicle_ramp != null else null
			if elevator_platform == null or elevator_left_cover == null or elevator_right_cover == null \
					or ramp_slider == null or ramp_inner_pivot == null \
					or ramp_middle_pivot == null or ramp_outer_pivot == null:
				_fail("land carrier preview did not build its elevator and folding vehicle-bay door")
				return

			var elevator_down_y := elevator_platform.position.y
			var elevator_closed_left_x := elevator_left_cover.position.x
			var elevator_closed_right_x := elevator_right_cover.position.x
			var elevator_closed_cover_y := elevator_left_cover.position.y
			var ramp_stowed_slider_z := ramp_slider.position.z
			var ramp_stowed_inner_x := ramp_inner_pivot.rotation.x
			var ramp_stowed_middle_x := ramp_middle_pivot.rotation.x
			var ramp_stowed_outer_x := ramp_outer_pivot.rotation.x
			var carrier_animation_values := view.get("_preview_animation_values") as Dictionary

			elevator_button.pressed.emit()
			view.call("_process", 0.5)
			var partial_elevator_raise := float(carrier_animation_values.get(&"elevator", 0.0))
			if partial_elevator_raise <= 0.0 or partial_elevator_raise >= 1.0 \
					or (is_equal_approx(elevator_platform.position.y, elevator_down_y) \
					and is_equal_approx(elevator_left_cover.position.y, elevator_closed_cover_y)):
				_fail("elevator control did not begin raising the carrier elevator")
				return
			view.call("_process", 6.0)
			var carrier_elevator_component := carrier_elevator as CarrierElevator
			var expected_open_cover_x := carrier_elevator_component.platform_size.x * 0.5 \
					+ carrier_elevator_component.cover_size.z * 0.5 \
					+ carrier_elevator_component.cover_recess_margin_m
			var expected_open_cover_y := -carrier_elevator_component.cover_size.y * 0.5 \
					- carrier_elevator_component.cover_recess_depth_m
			if not is_equal_approx(float(carrier_animation_values.get(&"elevator", 0.0)), 1.0) \
					or absf(elevator_platform.position.y + 0.5) > 0.01 \
					or absf(elevator_left_cover.position.x + expected_open_cover_x) > 0.01 \
					or absf(elevator_right_cover.position.x - expected_open_cover_x) > 0.01 \
					or absf(elevator_left_cover.position.y - expected_open_cover_y) > 0.01:
				_fail("elevator control did not bring the carrier elevator fully up")
				return
			elevator_button.pressed.emit()
			view.call("_process", 6.0)
			if not is_equal_approx(float(carrier_animation_values.get(&"elevator", 1.0)), 0.0) \
					or not is_equal_approx(elevator_platform.position.y, elevator_down_y) \
					or not is_equal_approx(elevator_left_cover.position.x, elevator_closed_left_x) \
					or not is_equal_approx(elevator_right_cover.position.x, elevator_closed_right_x) \
					or not is_equal_approx(elevator_left_cover.position.y, elevator_closed_cover_y):
				_fail("second elevator press did not lower and close the carrier elevator")
				return

			vehicle_bay_button.pressed.emit()
			view.call("_process", 0.75)
			var partial_vehicle_bay_open := float(carrier_animation_values.get(&"bay_door", 0.0))
			if partial_vehicle_bay_open <= 0.0 or partial_vehicle_bay_open >= 1.0 \
					or is_equal_approx(ramp_slider.position.z, ramp_stowed_slider_z):
				_fail("vehicle-bay control did not begin sliding out the folding door")
				return
			view.call("_process", 5.0)
			if not is_equal_approx(float(carrier_animation_values.get(&"bay_door", 0.0)), 1.0) \
					or is_equal_approx(ramp_inner_pivot.rotation.x, ramp_stowed_inner_x) \
					or is_equal_approx(ramp_middle_pivot.rotation.x, ramp_stowed_middle_x) \
					or is_equal_approx(ramp_outer_pivot.rotation.x, ramp_stowed_outer_x):
				_fail("vehicle-bay control did not fully open the carrier ramp")
				return
			vehicle_bay_button.pressed.emit()
			view.call("_process", 5.0)
			if not is_equal_approx(float(carrier_animation_values.get(&"bay_door", 1.0)), 0.0) \
					or not is_equal_approx(ramp_slider.position.z, ramp_stowed_slider_z) \
					or not is_equal_approx(ramp_inner_pivot.rotation.x, ramp_stowed_inner_x) \
					or not is_equal_approx(ramp_middle_pivot.rotation.x, ramp_stowed_middle_x) \
					or not is_equal_approx(ramp_outer_pivot.rotation.x, ramp_stowed_outer_x):
				_fail("second vehicle-bay press did not close and stow the carrier ramp")
				return
			view.call("_select_entry", ground_vehicle_entries[1])
			var friendly_vehicle_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
			if not _preview_uses_only_livery_pattern(friendly_vehicle_root, TEST_PLAYER_PATTERN_INDEX):
				_fail("friendly ground-vehicle preview did not inherit the player pattern")
				return
			view.call("_select_entry", ground_vehicle_entries[2])
			var hostile_vehicle_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
			if not _find_livery_pattern_modes(hostile_vehicle_root).is_empty():
				_fail("hostile ground-vehicle preview incorrectly inherited the player pattern")
				return
		await process_frame
	view.call("_show_category", "AIRPLANES")
	if String(view.get("current_mode")) != "tech_items":
		_fail("category selection did not open the equipment list")
		return
	var selected_name := _find_label(view, String(airplane_entries[0].get("name", "")))
	if selected_name == null:
		_fail("automatically selected equipment name was not rendered")
		return
	for airplane_entry in airplane_entries:
		view.call("_select_entry", airplane_entry)
		var airplane_scene_path := String(airplane_entry.get("scene", ""))
		var flight_description := view.get("_description_label") as Label
		var flight_stats := view.get("_stats_label") as Label
		if flight_description == null or not flight_description.text.contains("FLIGHT NOTES //"):
			_fail("airplane pilot notes were not rendered: %s" % airplane_scene_path)
			return
		if flight_stats == null \
				or not flight_stats.text.contains("EST CLEAN SPEED") \
				or not flight_stats.text.contains("STALL CLEAN / FLAPS") \
				or not flight_stats.text.contains("STIFFEN / VNE") \
				or not flight_stats.text.contains("CONTROL POWER P/R/Y") \
				or not flight_stats.text.contains("SURFACE RATE P/R/Y") \
				or not flight_stats.text.contains("STALL AOA") \
				or not flight_stats.text.contains("MODEL LIFT LIMIT"):
			_fail("airplane flight-envelope data was incomplete: %s" % airplane_scene_path)
			return
		if airplane_scene_path == "res://Aircraft/Aircraft_14.tscn" \
				and (not flight_stats.text.contains("110 / 165 m/s") \
				or not flight_stats.text.contains("7 / 18 / 2.8") \
				or not flight_stats.text.contains("16-29 deg")):
			_fail("Spitewing index did not expose its authored control and stall envelope")
			return
		if airplane_scene_path == "res://Aircraft/Aircraft_6.tscn" \
				and (not flight_stats.text.contains("75 / 115 m/s") \
				or not flight_stats.text.contains("24-46 deg")):
			_fail("Razorback index did not expose its low-speed benign envelope")
			return
		var airplane_model_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
		if not _preview_uses_only_livery_pattern(airplane_model_root, TEST_PLAYER_PATTERN_INDEX):
			_fail("airplane preview did not inherit the selected player pattern: %s" % airplane_scene_path)
			return
		var airplane_engine_button := view.get_node_or_null("PreviewConfigurationControls/EngineButton") as Button
		if airplane_engine_button == null or not airplane_engine_button.visible:
			_fail("airplane preview did not expose its engine control: %s" % airplane_scene_path)
			return
		if _has_visible_preview_hud(airplane_model_root):
			_fail("airplane preview retained a visible projected HUD: %s" % airplane_scene_path)
			return
		if not _has_visible_static_instrument_panel(airplane_model_root):
			_fail("airplane preview did not retain a visible instrument panel: %s" % airplane_scene_path)
			return
		if airplane_scene_path == "res://Aircraft/Aircraft_3.tscn" \
				or airplane_scene_path == "res://Aircraft/Aircraft_4.tscn" \
				or airplane_scene_path == "res://Aircraft/Aircraft_6.tscn":
			if airplane_model_root != null and airplane_model_root.find_child("TailHook", true, false) != null:
				_fail("non-carrier airplane preview retained a tailhook: %s" % airplane_scene_path)
				return
		var cockpit_pilot := airplane_model_root.find_child("CockpitPilot", true, false) if airplane_model_root != null else null
		if cockpit_pilot == null \
				or String(cockpit_pilot.get_meta("technical_index_pilot_pose", "")) != "sitting" \
				or cockpit_pilot.get_script() != null:
			_fail("airplane preview pilot was not frozen seated: %s" % String(airplane_entry.get("scene", "")))
			return
		var pilot_visual := cockpit_pilot.get_node_or_null("Pilot") as Node3D
		if pilot_visual == null:
			pilot_visual = cockpit_pilot.get_node_or_null("PilotVisual") as Node3D
		if pilot_visual == null or not pilot_visual.visible or not _has_skeleton_pose_delta(pilot_visual):
			_fail("airplane preview did not retain a visible seated pilot: %s" % String(airplane_entry.get("scene", "")))
			return
		var preview_skeleton := _find_skeleton(pilot_visual)
		for suffix in [".l", ".r"]:
			var seated_geometry := _seated_pilot_geometry(preview_skeleton, suffix)
			var knee_bend := float(seated_geometry.get("knee_bend_degrees", INF))
			var toe_up := float(seated_geometry.get("toe_up_degrees", INF))
			if absf(knee_bend - 45.0) > 0.25 or absf(toe_up - 15.0) > 0.25:
				_fail(
					"airplane preview retained old seated legs: %s %s knee=%.2f toe=%.2f"
					% [airplane_scene_path, suffix, knee_bend, toe_up]
				)
				return
	livery.call(
		"set_player_livery",
		Color(0.16, 0.47, 0.20),
		Color(0.73, 0.60, 0.44),
		1
	)
	view.call("_select_entry", airplane_entries[0])
	var changed_pattern_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
	if not _preview_uses_only_livery_pattern(changed_pattern_root, 1):
		_fail("airplane preview did not pick up a changed player pattern")
		return
	livery.call(
		"set_player_livery",
		Color(0.16, 0.47, 0.20),
		Color(0.73, 0.60, 0.44),
		TEST_PLAYER_PATTERN_INDEX
	)
	view.call("_select_entry", airplane_entries[0])
	var configuration_panel := view.get_node_or_null("PreviewConfigurationControls") as Panel
	var wings_button := view.get_node_or_null("PreviewConfigurationControls/WingsButton") as Button
	var gear_button := view.get_node_or_null("PreviewConfigurationControls/LandingGearButton") as Button
	var doors_button := view.get_node_or_null("PreviewConfigurationControls/DoorsButton") as Button
	var engine_button := view.get_node_or_null("PreviewConfigurationControls/EngineButton") as Button
	if configuration_panel == null or wings_button == null or gear_button == null \
			or doors_button == null or engine_button == null:
		_fail("preview configuration controls were unavailable")
		return
	if not configuration_panel.visible or not wings_button.visible or not gear_button.visible \
			or doors_button.visible or not engine_button.visible:
		_fail("Sand Sprite did not expose its applicable wing, landing-gear, and engine controls")
		return
	if not _configuration_buttons_are_compact(
			configuration_panel,
			[wings_button, gear_button, doors_button, engine_button]
	):
		_fail("Sand Sprite configuration controls did not form a compact row")
		return
	var aircraft_one_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
	var middle_left := aircraft_one_root.find_child("wing middle left", true, false) as Node3D
	var wing_insignia_marker := aircraft_one_root.find_child("InsigniaWing", true, false) as Node3D
	var wing_insignia_decal := aircraft_one_root.find_child("InsigniaDecal_InsigniaWing", true, false) as Decal
	var nose_gear_rig := aircraft_one_root.find_child("NoseGearRig", true, false) as Node3D
	var nose_gear_pivot := nose_gear_rig.find_child("FrontGearPivot", true, false) as Node3D if nose_gear_rig != null else null
	var nose_gear_slide := nose_gear_rig.find_child("LowerLegSlide", true, false) as Node3D if nose_gear_rig != null else null
	var left_main_gear_rig := aircraft_one_root.find_child("LeftGearRig", true, false) as Node3D
	var right_main_gear_rig := aircraft_one_root.find_child("RightGearRig", true, false) as Node3D
	var left_main_pivot := left_main_gear_rig.find_child("FrontGearPivot", true, false) as Node3D if left_main_gear_rig != null else null
	var right_main_pivot := right_main_gear_rig.find_child("FrontGearPivot", true, false) as Node3D if right_main_gear_rig != null else null
	var left_main_slide := left_main_gear_rig.find_child("LowerLegSlide", true, false) as Node3D if left_main_gear_rig != null else null
	var right_main_slide := right_main_gear_rig.find_child("LowerLegSlide", true, false) as Node3D if right_main_gear_rig != null else null
	var left_main_linkage := left_main_gear_rig.find_child("RotationLinkagePivot", true, false) as Node3D if left_main_gear_rig != null else null
	var right_main_linkage := right_main_gear_rig.find_child("RotationLinkagePivot", true, false) as Node3D if right_main_gear_rig != null else null
	var left_main_connector := left_main_gear_rig.find_child("LowerConnectorArmPivot", true, false) as Node3D if left_main_gear_rig != null else null
	var right_main_connector := right_main_gear_rig.find_child("LowerConnectorArmPivot", true, false) as Node3D if right_main_gear_rig != null else null
	var left_main_wheel := left_main_gear_rig.find_child("WheelPivot", true, false) as Node3D if left_main_gear_rig != null else null
	var right_main_wheel := right_main_gear_rig.find_child("WheelPivot", true, false) as Node3D if right_main_gear_rig != null else null
	var tailhook := aircraft_one_root.find_child("TailHook", true, false) as Node3D
	var tailhook_mesh := tailhook.get_node_or_null("Tailhook") as Node3D if tailhook != null else null
	var propeller := aircraft_one_root.find_child("Aircraft 2 propeller", true, false) as Node3D
	var propeller_disc := propeller.find_child("propeller disc", true, false) as GeometryInstance3D if propeller != null else null
	if middle_left == null or wing_insignia_marker == null or wing_insignia_decal == null \
			or not wing_insignia_decal.visible \
			or wing_insignia_decal.get_script() == null \
			or (wing_insignia_decal.get_script() as Script).resource_path != "res://Aircraft/Visuals/InsigniaDecalFollower.gd" \
			or wing_insignia_decal.process_mode != Node.PROCESS_MODE_ALWAYS \
			or not wing_insignia_decal.global_transform.is_equal_approx(wing_insignia_marker.global_transform) \
			or nose_gear_rig == null or nose_gear_pivot == null or nose_gear_slide == null \
			or left_main_pivot == null or right_main_pivot == null \
			or left_main_slide == null or right_main_slide == null \
			or left_main_linkage == null or right_main_linkage == null \
			or left_main_connector == null or right_main_connector == null \
			or left_main_wheel == null or right_main_wheel == null \
			or tailhook == null or tailhook_mesh == null or not tailhook_mesh.visible \
			or propeller == null or propeller_disc == null or propeller_disc.visible:
		_fail("Sand Sprite preview did not retain its wing insignia, stopped propeller, and other animated visuals")
		return
	var unfolded_wing_transform := middle_left.transform
	var unfolded_insignia_transform := wing_insignia_decal.transform
	var unfolded_insignia_size := wing_insignia_decal.size
	var deployed_gear_slide_transform := nose_gear_slide.transform
	var left_main_pivot_deployed_rotation := left_main_pivot.rotation
	var right_main_pivot_deployed_rotation := right_main_pivot.rotation
	var left_main_slide_deployed_position := left_main_slide.position
	var right_main_slide_deployed_position := right_main_slide.position
	var left_main_linkage_deployed_rotation := left_main_linkage.rotation
	var right_main_linkage_deployed_rotation := right_main_linkage.rotation
	var left_main_connector_deployed_rotation := left_main_connector.rotation
	var right_main_connector_deployed_rotation := right_main_connector.rotation
	var aircraft_one_instance := aircraft_one_root.get_child(0) as Node3D
	var aircraft_midline_x := aircraft_one_instance.global_position.x
	var left_wheel_deployed_midline_distance := absf(left_main_wheel.global_position.x - aircraft_midline_x)
	var right_wheel_deployed_midline_distance := absf(right_main_wheel.global_position.x - aircraft_midline_x)
	var animation_values := view.get("_preview_animation_values") as Dictionary
	var stopped_propeller_transform := propeller.transform
	engine_button.pressed.emit()
	view.call("_process", 0.5)
	var partial_engine_start := float(animation_values.get(&"engine", 0.0))
	if partial_engine_start <= 0.0 or partial_engine_start >= 1.0 \
			or propeller.transform.is_equal_approx(stopped_propeller_transform):
		_fail("engine control did not begin spinning up the Sand Sprite propeller")
		return
	view.call("_process", 2.0)
	if not is_equal_approx(float(animation_values.get(&"engine", 0.0)), 1.0) or not propeller_disc.visible:
		_fail("engine control did not reach running speed or show the Sand Sprite propeller disc")
		return
	engine_button.pressed.emit()
	view.call("_process", 2.0)
	if not is_equal_approx(float(animation_values.get(&"engine", 1.0)), 0.0) or propeller_disc.visible:
		_fail("stopped Sand Sprite propeller retained a visible propeller disc")
		return
	wings_button.pressed.emit()
	view.call("_process", 0.5)
	var partial_wing_fold := float(animation_values.get(&"wings", 0.0))
	if partial_wing_fold <= 0.0 or partial_wing_fold >= 1.0:
		_fail("wing control did not begin a timed fold animation")
		return
	view.call("_process", 4.0)
	wing_insignia_decal.call("update_follow_transform")
	if not is_equal_approx(float(animation_values.get(&"wings", 0.0)), 1.0) \
			or middle_left.transform.is_equal_approx(unfolded_wing_transform) \
			or wing_insignia_decal.transform.is_equal_approx(unfolded_insignia_transform) \
			or not wing_insignia_decal.size.is_equal_approx(unfolded_insignia_size):
		_fail("wing control did not fold the Sand Sprite wings and insignia together")
		return
	wings_button.pressed.emit()
	view.call("_process", 4.0)
	wing_insignia_decal.call("update_follow_transform")
	if not is_equal_approx(float(animation_values.get(&"wings", 1.0)), 0.0) \
			or not middle_left.transform.is_equal_approx(unfolded_wing_transform) \
			or not wing_insignia_decal.transform.is_equal_approx(unfolded_insignia_transform) \
			or not wing_insignia_decal.size.is_equal_approx(unfolded_insignia_size):
		_fail("wing control did not unfold the Sand Sprite wings and insignia together")
		return
	gear_button.pressed.emit()
	view.call("_process", 0.2)
	var partial_gear_stow := float(animation_values.get(&"gear", 1.0))
	if partial_gear_stow <= 0.0 or partial_gear_stow >= 1.0 \
			or nose_gear_slide.transform.is_equal_approx(deployed_gear_slide_transform):
		_fail("landing-gear control did not begin a timed stow animation")
		return
	if left_main_slide.position.is_equal_approx(left_main_slide_deployed_position) \
			or right_main_slide.position.is_equal_approx(right_main_slide_deployed_position):
		_fail("Sand Sprite main gear did not shorten before folding")
		return
	if not left_main_pivot.rotation.is_equal_approx(left_main_pivot_deployed_rotation) \
			or not right_main_pivot.rotation.is_equal_approx(right_main_pivot_deployed_rotation):
		_fail("Sand Sprite main gear began rotating before the shortening phase completed")
		return
	view.call("_process", 4.0)
	if not is_equal_approx(float(animation_values.get(&"gear", 1.0)), 0.0) \
			or nose_gear_rig.visible or tailhook_mesh.visible:
		_fail("landing-gear control did not finish stowing the Sand Sprite gear and tailhook")
		return
	if absf(rad_to_deg(left_main_pivot.rotation.z) + 90.0) > 0.05 \
			or absf(rad_to_deg(right_main_pivot.rotation.z) + 90.0) > 0.05:
		_fail("Sand Sprite main gear did not rotate inward as complete assemblies")
		return
	if not left_main_linkage.rotation.is_equal_approx(left_main_linkage_deployed_rotation) \
			or not right_main_linkage.rotation.is_equal_approx(right_main_linkage_deployed_rotation) \
			or not left_main_connector.rotation.is_equal_approx(left_main_connector_deployed_rotation) \
			or not right_main_connector.rotation.is_equal_approx(right_main_connector_deployed_rotation):
		_fail("Sand Sprite main gear still rotated a lower linkage while stowing")
		return
	if absf(left_main_wheel.global_position.x - aircraft_midline_x) >= left_wheel_deployed_midline_distance \
			or absf(right_main_wheel.global_position.x - aircraft_midline_x) >= right_wheel_deployed_midline_distance:
		_fail("Sand Sprite main wheels did not move toward the aircraft midline while stowing")
		return
	gear_button.pressed.emit()
	view.call("_process", 4.0)
	if not is_equal_approx(float(animation_values.get(&"gear", 0.0)), 1.0) \
			or not nose_gear_rig.visible or not tailhook_mesh.visible:
		_fail("landing-gear control did not redeploy the Sand Sprite gear and tailhook")
		return

	var fixed_gear_entry := _find_catalog_entry(airplane_entries, "res://Aircraft/Aircraft_3.tscn")
	if fixed_gear_entry.is_empty():
		_fail("fixed-gear airplane entry was unavailable")
		return
	view.call("_select_entry", fixed_gear_entry)
	if gear_button.visible:
		_fail("fixed landing gear incorrectly exposed a stow control")
		return
	if not _configuration_buttons_are_compact(
			configuration_panel,
			[wings_button, gear_button, doors_button, engine_button]
	):
		_fail("fixed-gear airplane configuration controls did not reflow")
		return

	var helicopter_entries := Catalog.entries_for("HELICOPTERS")
	for helicopter_entry in helicopter_entries:
		view.call("_select_entry", helicopter_entry)
		var helicopter_scene_path := String(helicopter_entry.get("scene", ""))
		var helicopter_preview_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
		if not _preview_uses_only_livery_pattern(helicopter_preview_root, TEST_PLAYER_PATTERN_INDEX):
			_fail("helicopter preview did not inherit the selected player pattern: %s" % helicopter_scene_path)
			return
		if not engine_button.visible:
			_fail("helicopter preview did not expose its engine control: %s" % helicopter_scene_path)
			return
		if not _configuration_buttons_are_compact(
				configuration_panel,
				[wings_button, gear_button, doors_button, engine_button]
		):
			_fail("helicopter configuration controls did not reflow: %s" % helicopter_scene_path)
			return
		if _has_visible_preview_hud(helicopter_preview_root):
			_fail("helicopter preview retained a visible projected HUD: %s" % helicopter_scene_path)
			return
		if not _has_visible_static_instrument_panel(helicopter_preview_root):
			_fail("helicopter preview did not retain a visible instrument panel: %s" % helicopter_scene_path)
			return
	var sliding_door_entry := _find_catalog_entry(helicopter_entries, "res://Aircraft/Aircraft_9.tscn")
	if sliding_door_entry.is_empty():
		_fail("sliding-door helicopter entry was unavailable")
		return
	view.call("_select_entry", sliding_door_entry)
	if not configuration_panel.visible or wings_button.visible or not gear_button.visible \
			or not doors_button.visible or not engine_button.visible:
		_fail("Bumblebee did not expose its applicable landing-gear, door, and engine controls")
		return
	var sliding_door_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
	var left_sliding_door := sliding_door_root.find_child("LeftSlidingDoor", true, false) as Node3D
	var right_sliding_door := sliding_door_root.find_child("RightSlidingDoor", true, false) as Node3D
	var helicopter_main_rotor := sliding_door_root.find_child("UpperRotor", true, false) as Node3D
	var helicopter_rotor_disc := helicopter_main_rotor.find_child("RotorDisc", true, false) as Node3D if helicopter_main_rotor != null else null
	if left_sliding_door == null or right_sliding_door == null \
			or helicopter_main_rotor == null or helicopter_rotor_disc == null or helicopter_rotor_disc.visible:
		_fail("Bumblebee preview did not build its stopped rotor and both sliding door halves")
		return
	var left_door_closed_position := left_sliding_door.position
	var right_door_closed_position := right_sliding_door.position
	animation_values = view.get("_preview_animation_values") as Dictionary
	var stopped_rotor_transform := helicopter_main_rotor.transform
	engine_button.pressed.emit()
	view.call("_process", 1.0)
	if float(animation_values.get(&"engine", 0.0)) <= 0.0 \
			or helicopter_main_rotor.transform.is_equal_approx(stopped_rotor_transform):
		_fail("Bumblebee engine control did not begin spinning up its main rotor")
		return
	view.call("_process", 6.0)
	if not is_equal_approx(float(animation_values.get(&"engine", 0.0)), 1.0) or not helicopter_rotor_disc.visible:
		_fail("Bumblebee engine control did not reach running rotor speed")
		return
	engine_button.pressed.emit()
	view.call("_process", 6.0)
	if not is_equal_approx(float(animation_values.get(&"engine", 1.0)), 0.0) or helicopter_rotor_disc.visible:
		_fail("stopped Bumblebee rotor retained a visible rotor disc")
		return
	doors_button.pressed.emit()
	view.call("_process", 0.2)
	var partial_sliding_door_open := float(animation_values.get(&"doors", 0.0))
	if partial_sliding_door_open <= 0.0 or partial_sliding_door_open >= 1.0 \
			or left_sliding_door.position.is_equal_approx(left_door_closed_position) \
			or right_sliding_door.position.is_equal_approx(right_door_closed_position):
		_fail("Bumblebee door control did not begin its timed sliding animation")
		return
	view.call("_process", 2.0)
	if not is_equal_approx(float(animation_values.get(&"doors", 0.0)), 1.0):
		_fail("Bumblebee door control did not finish opening the sliding doors")
		return
	doors_button.pressed.emit()
	view.call("_process", 2.0)
	if not is_equal_approx(float(animation_values.get(&"doors", 1.0)), 0.0) \
			or not left_sliding_door.position.is_equal_approx(left_door_closed_position) \
			or not right_sliding_door.position.is_equal_approx(right_door_closed_position):
		_fail("Bumblebee door control did not close both sliding doors")
		return

	var door_entry := _find_catalog_entry(helicopter_entries, "res://Aircraft/Aircraft_11.tscn")
	if door_entry.is_empty():
		_fail("swing-door helicopter entry was unavailable")
		return
	view.call("_select_entry", door_entry)
	if not configuration_panel.visible or wings_button.visible or gear_button.visible \
			or not doors_button.visible or not engine_button.visible:
		_fail("Hummingbird did not expose its applicable door and engine controls")
		return
	var helicopter_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
	var left_door_hinge := helicopter_root.find_child("DoorHingeLeft_1", true, false) as Node3D
	if left_door_hinge == null:
		_fail("Hummingbird preview did not retain its door hinge")
		return
	var closed_door_basis := left_door_hinge.basis
	animation_values = view.get("_preview_animation_values") as Dictionary
	doors_button.pressed.emit()
	view.call("_process", 0.2)
	var partial_door_open := float(animation_values.get(&"doors", 0.0))
	if partial_door_open <= 0.0 or partial_door_open >= 1.0:
		_fail("door control did not begin a timed opening animation")
		return
	view.call("_process", 2.0)
	if not is_equal_approx(float(animation_values.get(&"doors", 0.0)), 1.0) \
			or left_door_hinge.basis.is_equal_approx(closed_door_basis):
		_fail("door control did not finish opening the Hummingbird doors")
		return
	doors_button.pressed.emit()
	view.call("_process", 2.0)
	if not is_equal_approx(float(animation_values.get(&"doors", 1.0)), 0.0) \
			or not left_door_hinge.basis.is_equal_approx(closed_door_basis):
		_fail("door control did not close the Hummingbird doors")
		return

	view.call("_select_entry", airplane_entries[0])
	var pivot := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot") as Node3D
	if pivot == null:
		_fail("isolated rotatable preview world was unavailable")
		return
	var grid := view.get_node_or_null("RotatablePreview/EquipmentViewport/ComputerGridGround") as MeshInstance3D
	if grid == null or not grid.visible:
		_fail("green computer-grid ground was unavailable")
		return
	var grid_material := grid.material_override as ShaderMaterial
	if grid_material == null \
			or not is_equal_approx(float(grid_material.get_shader_parameter("minor_spacing_m")), 5.0) \
			or not is_equal_approx(float(grid_material.get_shader_parameter("major_spacing_m")), 25.0):
		_fail("computer grid did not preserve a fixed world-space square size")
		return
	var rotate_right := view.get_node_or_null("PreviewControls/RotateRightButton") as Button
	var zoom_in := view.get_node_or_null("PreviewControls/ZoomInButton") as Button
	var preview_camera := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewCamera") as Camera3D
	if rotate_right == null or zoom_in == null or preview_camera == null:
		_fail("on-screen rotation and zoom controls were unavailable")
		return
	var pivot_rotation_before := pivot.rotation
	var camera_position_before := preview_camera.position
	rotate_right.button_down.emit()
	view.call("_process", 0.5)
	rotate_right.button_up.emit()
	if preview_camera.position.is_equal_approx(camera_position_before):
		_fail("held rotation control did not orbit the preview camera")
		return
	if not pivot.rotation.is_equal_approx(pivot_rotation_before):
		_fail("camera orbit rotated the object away from the grid surface")
		return
	var camera_target := Vector3(0.0, float(view.get("_preview_target_y")), 0.0)
	var camera_distance_before := preview_camera.position.distance_to(camera_target)
	zoom_in.button_down.emit()
	view.call("_process", 0.5)
	zoom_in.button_up.emit()
	if preview_camera.position.distance_to(camera_target) >= camera_distance_before:
		_fail("held zoom control did not move the preview camera inward")
		return

	print("[TechnicalIndexSmoketest] PASS categories=%d scenes=%d preview=grid controls=continuous orbit+zoom+configuration autoselect=ok" % [expected_categories.size(), scene_count])
	quit(0)


func _find_label(root_node: Node, text_value: String) -> Label:
	if root_node is Label and (root_node as Label).text == text_value:
		return root_node as Label
	for child in root_node.get_children():
		var found := _find_label(child as Node, text_value)
		if found != null:
			return found
	return null


func _find_catalog_entry(entries: Array[Dictionary], scene_path: String) -> Dictionary:
	for entry in entries:
		if String(entry.get("scene", "")) == scene_path:
			return entry
	return {}


func _find_track_plate_counts(root_node: Node) -> Array[int]:
	var counts: Array[int] = []
	if root_node == null:
		return counts
	if root_node is MultiMeshInstance3D and root_node.name == &"TrackPlates":
		var multimesh := (root_node as MultiMeshInstance3D).multimesh
		if multimesh != null:
			counts.append(multimesh.instance_count)
	for child in root_node.get_children():
		counts.append_array(_find_track_plate_counts(child as Node))
	return counts


func _find_track_path_vertical_extents(root_node: Node) -> Array[Vector2]:
	var extents: Array[Vector2] = []
	if root_node == null:
		return extents
	if root_node is Path3D and root_node.name == &"TrackPath":
		var curve := (root_node as Path3D).curve
		if curve != null and curve.point_count > 0:
			var min_y := INF
			var max_y := -INF
			for point_index in curve.point_count:
				var path_y := curve.get_point_position(point_index).y
				min_y = minf(min_y, path_y)
				max_y = maxf(max_y, path_y)
			extents.append(Vector2(min_y, max_y))
	for child in root_node.get_children():
		extents.append_array(_find_track_path_vertical_extents(child as Node))
	return extents


func _has_visible_preview_hud(root_node: Node) -> bool:
	if root_node == null:
		return false
	var lowered_name := String(root_node.name).to_lower()
	if root_node is Node3D \
			and lowered_name in ["headsupdisplay", "physicalhud"] \
			and (root_node as Node3D).visible:
		return true
	for child in root_node.get_children():
		if _has_visible_preview_hud(child as Node):
			return true
	return false


func _configuration_buttons_are_compact(panel: Control, buttons: Array) -> bool:
	if panel == null:
		return false
	var visible_buttons: Array[Button] = []
	for button_variant in buttons:
		var button := button_variant as Button
		if button != null and button.visible:
			visible_buttons.append(button)
	if visible_buttons.is_empty():
		return not panel.visible
	visible_buttons.sort_custom(func(a: Button, b: Button) -> bool: return a.position.x < b.position.x)
	var expected_width := 16.0 + float(visible_buttons.size()) * 66.0 \
			+ float(visible_buttons.size() - 1) * 8.0
	if not is_equal_approx(panel.size.x, expected_width):
		return false
	for index in visible_buttons.size():
		if not is_equal_approx(visible_buttons[index].position.x, 8.0 + float(index) * 74.0):
			return false
	return true


func _has_visible_static_instrument_panel(root_node: Node) -> bool:
	if root_node == null:
		return false
	if root_node is Node3D and String(root_node.name).to_lower() == "instrumentpanel":
		var instrument_panel := root_node as Node3D
		if not instrument_panel.visible \
				or not bool(instrument_panel.get_meta("technical_index_static_instrument", false)) \
				or instrument_panel.get_script() == null:
			return false
		var panel_viewport := instrument_panel.get_node_or_null("SubViewport") as SubViewport
		var display_root := instrument_panel.get_node_or_null("SubViewport/InstrumentDisplay") as Control
		var panel_screen := instrument_panel.get_node_or_null("PanelScreen") as MeshInstance3D
		if panel_viewport == null or display_root == null or panel_screen == null \
				or panel_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED \
				or not display_root.visible:
			return false
		if panel_screen.visible and panel_screen.material_override is ShaderMaterial:
			return true
		var model_panel_mesh := instrument_panel.get("model_panel_mesh") as MeshInstance3D
		if model_panel_mesh != null and model_panel_mesh.mesh != null:
			for surface_index in model_panel_mesh.mesh.get_surface_count():
				if model_panel_mesh.get_surface_override_material(surface_index) is ShaderMaterial:
					return true
		return false
	for child in root_node.get_children():
		if _has_visible_static_instrument_panel(child as Node):
			return true
	return false


func _preview_uses_only_livery_pattern(root_node: Node, expected_pattern_index: int) -> bool:
	var pattern_modes := _find_livery_pattern_modes(root_node)
	if pattern_modes.is_empty():
		return false
	for pattern_mode in pattern_modes:
		if pattern_mode != expected_pattern_index:
			return false
	return true


func _find_livery_pattern_modes(root_node: Node) -> Array[int]:
	var pattern_modes: Array[int] = []
	if root_node == null:
		return pattern_modes
	if root_node is MeshInstance3D:
		var mesh_instance := root_node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material is ShaderMaterial and material.resource_name == "Livery Test Pattern":
					pattern_modes.append(int((material as ShaderMaterial).get_shader_parameter("pattern_mode")))
	for child in root_node.get_children():
		pattern_modes.append_array(_find_livery_pattern_modes(child as Node))
	return pattern_modes


func _has_skeleton_pose_delta(root_node: Node) -> bool:
	if root_node is Skeleton3D:
		var skeleton := root_node as Skeleton3D
		for bone_index in skeleton.get_bone_count():
			if skeleton.get_bone_pose_rotation(bone_index).get_angle() > 0.01 \
					or skeleton.get_bone_pose_position(bone_index).length() > 0.001:
				return true
	for child in root_node.get_children():
		if _has_skeleton_pose_delta(child as Node):
			return true
	return false


func _find_skeleton(root_node: Node) -> Skeleton3D:
	if root_node == null:
		return null
	if root_node is Skeleton3D:
		return root_node as Skeleton3D
	for child in root_node.get_children():
		var found := _find_skeleton(child as Node)
		if found != null:
			return found
	return null


func _seated_pilot_geometry(skeleton: Skeleton3D, suffix: String) -> Dictionary:
	if skeleton == null:
		return {}
	var thigh_index := skeleton.find_bone("thigh_stretch" + suffix)
	var shin_index := skeleton.find_bone("leg_stretch" + suffix)
	var foot_index := skeleton.find_bone("foot" + suffix)
	var toe_index := skeleton.find_bone("toes_01" + suffix)
	if thigh_index < 0 or shin_index < 0 or foot_index < 0 or toe_index < 0:
		return {}
	skeleton.force_update_all_bone_transforms()
	var hip := skeleton.get_bone_global_pose(thigh_index).origin
	var knee := skeleton.get_bone_global_pose(shin_index).origin
	var ankle := skeleton.get_bone_global_pose(foot_index).origin
	var toe := skeleton.get_bone_global_pose(toe_index).origin
	var upper := Vector2(knee.y - hip.y, knee.z - hip.z).normalized()
	var lower := Vector2(ankle.y - knee.y, ankle.z - knee.z).normalized()
	var foot_vector := toe - ankle
	var rest_foot := skeleton.get_bone_global_rest(foot_index)
	var rest_toe := skeleton.get_bone_global_rest(toe_index)
	var rest_foot_vector := rest_toe.origin - rest_foot.origin
	return {
		"knee_bend_degrees": rad_to_deg(acos(clampf(upper.dot(lower), -1.0, 1.0))),
		"toe_up_degrees": rad_to_deg(
			atan2(-rest_foot_vector.y, rest_foot_vector.z)
			- atan2(-foot_vector.y, foot_vector.z)
		),
	}


func _fail(reason: String) -> void:
	push_error("[TechnicalIndexSmoketest] FAIL %s" % reason)
	quit(1)
