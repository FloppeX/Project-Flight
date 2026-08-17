extends SceneTree

const Catalog = preload("res://UI/TechnicalIndexCatalog.gd")
const TechnicalIndexView = preload("res://UI/TechnicalIndexView.gd")


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
			var track_plate_counts := _find_track_plate_counts(model_root)
			if track_plate_counts.size() != 6 or track_plate_counts.min() <= 0:
				_fail("land carrier preview did not generate all six track-segment loops")
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
		var airplane_model_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
		var cockpit_pilot := airplane_model_root.find_child("CockpitPilot", true, false) if airplane_model_root != null else null
		if cockpit_pilot == null \
				or String(cockpit_pilot.get_meta("technical_index_pilot_pose", "")) != "sitting" \
				or cockpit_pilot.get_script() != null:
			_fail("airplane preview pilot was not frozen seated: %s" % String(airplane_entry.get("scene", "")))
			return
		var pilot_visual := cockpit_pilot.get_node_or_null("Pilot") as Node3D
		if pilot_visual == null or not pilot_visual.visible or not _has_skeleton_pose_delta(pilot_visual):
			_fail("airplane preview did not retain a visible seated pilot: %s" % String(airplane_entry.get("scene", "")))
			return
	view.call("_select_entry", airplane_entries[0])
	var configuration_panel := view.get_node_or_null("PreviewConfigurationControls") as Panel
	var wings_button := view.get_node_or_null("PreviewConfigurationControls/WingsButton") as Button
	var gear_button := view.get_node_or_null("PreviewConfigurationControls/LandingGearButton") as Button
	var doors_button := view.get_node_or_null("PreviewConfigurationControls/DoorsButton") as Button
	if configuration_panel == null or wings_button == null or gear_button == null or doors_button == null:
		_fail("preview configuration controls were unavailable")
		return
	if not configuration_panel.visible or not wings_button.visible or not gear_button.visible or doors_button.visible:
		_fail("Sand Sprite did not expose only its applicable wing and landing-gear controls")
		return
	var aircraft_one_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
	var middle_left := aircraft_one_root.find_child("wing middle left", true, false) as Node3D
	var nose_gear_rig := aircraft_one_root.find_child("NoseGearRig", true, false) as Node3D
	var nose_gear_pivot := nose_gear_rig.find_child("FrontGearPivot", true, false) as Node3D if nose_gear_rig != null else null
	var nose_gear_slide := nose_gear_rig.find_child("LowerLegSlide", true, false) as Node3D if nose_gear_rig != null else null
	if middle_left == null or nose_gear_rig == null or nose_gear_pivot == null or nose_gear_slide == null:
		_fail("Sand Sprite preview did not retain its animated wing and landing-gear visuals")
		return
	var unfolded_wing_transform := middle_left.transform
	var deployed_gear_slide_transform := nose_gear_slide.transform
	var animation_values := view.get("_preview_animation_values") as Dictionary
	wings_button.pressed.emit()
	view.call("_process", 0.5)
	var partial_wing_fold := float(animation_values.get(&"wings", 0.0))
	if partial_wing_fold <= 0.0 or partial_wing_fold >= 1.0:
		_fail("wing control did not begin a timed fold animation")
		return
	view.call("_process", 4.0)
	if not is_equal_approx(float(animation_values.get(&"wings", 0.0)), 1.0) \
			or middle_left.transform.is_equal_approx(unfolded_wing_transform):
		_fail("wing control did not finish folding the Sand Sprite wings")
		return
	wings_button.pressed.emit()
	view.call("_process", 4.0)
	if not is_equal_approx(float(animation_values.get(&"wings", 1.0)), 0.0) \
			or not middle_left.transform.is_equal_approx(unfolded_wing_transform):
		_fail("wing control did not unfold the Sand Sprite wings")
		return
	gear_button.pressed.emit()
	view.call("_process", 0.2)
	var partial_gear_stow := float(animation_values.get(&"gear", 1.0))
	if partial_gear_stow <= 0.0 or partial_gear_stow >= 1.0 \
			or nose_gear_slide.transform.is_equal_approx(deployed_gear_slide_transform):
		_fail("landing-gear control did not begin a timed stow animation")
		return
	view.call("_process", 4.0)
	if not is_equal_approx(float(animation_values.get(&"gear", 1.0)), 0.0) or nose_gear_rig.visible:
		_fail("landing-gear control did not finish stowing the Sand Sprite gear")
		return
	gear_button.pressed.emit()
	view.call("_process", 4.0)
	if not is_equal_approx(float(animation_values.get(&"gear", 0.0)), 1.0) or not nose_gear_rig.visible:
		_fail("landing-gear control did not redeploy the Sand Sprite gear")
		return

	var fixed_gear_entry := _find_catalog_entry(airplane_entries, "res://Aircraft/Aircraft_3.tscn")
	if fixed_gear_entry.is_empty():
		_fail("fixed-gear airplane entry was unavailable")
		return
	view.call("_select_entry", fixed_gear_entry)
	if gear_button.visible:
		_fail("fixed landing gear incorrectly exposed a stow control")
		return

	var helicopter_entries := Catalog.entries_for("HELICOPTERS")
	var sliding_door_entry := _find_catalog_entry(helicopter_entries, "res://Aircraft/Aircraft_9.tscn")
	if sliding_door_entry.is_empty():
		_fail("sliding-door helicopter entry was unavailable")
		return
	view.call("_select_entry", sliding_door_entry)
	if not configuration_panel.visible or wings_button.visible or not gear_button.visible or not doors_button.visible:
		_fail("Bumblebee did not expose its applicable landing-gear and door controls")
		return
	var sliding_door_root := view.get_node_or_null("RotatablePreview/EquipmentViewport/PreviewPivot/ModelRoot")
	var left_sliding_door := sliding_door_root.find_child("LeftSlidingDoor", true, false) as Node3D
	var right_sliding_door := sliding_door_root.find_child("RightSlidingDoor", true, false) as Node3D
	if left_sliding_door == null or right_sliding_door == null:
		_fail("Bumblebee preview did not build both sliding door halves")
		return
	var left_door_closed_position := left_sliding_door.position
	var right_door_closed_position := right_sliding_door.position
	animation_values = view.get("_preview_animation_values") as Dictionary
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
	if not configuration_panel.visible or wings_button.visible or gear_button.visible or not doors_button.visible:
		_fail("Hummingbird did not expose only its applicable door control")
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


func _fail(reason: String) -> void:
	push_error("[TechnicalIndexSmoketest] FAIL %s" % reason)
	quit(1)
