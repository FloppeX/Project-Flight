extends Node3D
## Runnable developer scene for scrubbing the raw parachute clip and tuning
## local-space arm/hand offsets on the retained Auto-Rig Pro pilot.

const SETTINGS_PATH := "res://Models/Characters/pilot/parachute_pose_settings.tres"
const PoseSettings = preload("res://Models/Characters/pilot/PilotParachutePoseSettings.gd")
const ROTATION_CONTROLS := [
	[&"left_shoulder_degrees", "Left shoulder / clavicle"],
	[&"left_upper_arm_degrees", "Left upper arm"],
	[&"left_forearm_degrees", "Left forearm"],
	[&"left_hand_degrees", "Left hand / wrist"],
	[&"right_shoulder_degrees", "Right shoulder / clavicle"],
	[&"right_upper_arm_degrees", "Right upper arm"],
	[&"right_forearm_degrees", "Right forearm"],
	[&"right_hand_degrees", "Right hand / wrist"],
]
const MIRROR_BONE_PAIRS := [
	[&"mixamorig_LeftShoulder", &"mixamorig_RightShoulder", &"left_shoulder_degrees", &"right_shoulder_degrees"],
	[&"mixamorig_LeftArm", &"mixamorig_RightArm", &"left_upper_arm_degrees", &"right_upper_arm_degrees"],
	[&"mixamorig_LeftForeArm", &"mixamorig_RightForeArm", &"left_forearm_degrees", &"right_forearm_degrees"],
	[&"mixamorig_LeftHand", &"mixamorig_RightHand", &"left_hand_degrees", &"right_hand_degrees"],
]

@onready var _pilot: Node3D = $Pilot

var _settings: PoseSettings
var _timeline: HSlider
var _time_label: Label
var _play_button: Button
var _status_label: Label
var _rotation_spins: Array[Dictionary] = []
var _grip_spin: SpinBox
var _updating_controls: bool = false
var _timeline_dragging: bool = false
var _resume_after_drag: bool = false
var _saved_values: Dictionary = {}


func _ready() -> void:
	# Always bind the tuner to the external gameplay resource. Godot can create a
	# scene-local copy when an instanced @tool character is edited and saved.
	_settings = ResourceLoader.load(
		SETTINGS_PATH,
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	) as PoseSettings
	if _settings == null:
		push_error("PilotPoseTuner: canonical pilot has no parachute pose settings")
		return
	_pilot.set("parachute_pose_settings", _settings)
	_saved_values = _capture_settings()
	_build_interface()
	_pilot.set("hide_head_in_cockpit", false)
	await get_tree().process_frame
	_pilot.call("set_ejection_pose", &"parachute", 0.0)
	for frame in range(3):
		await get_tree().process_frame
	_pilot.call("set_retarget_preview_paused", true)
	var clip_length := float(_pilot.call("get_retarget_preview_length"))
	_timeline.max_value = maxf(clip_length, 0.01)
	_timeline.value = float(_pilot.call("get_retarget_preview_position"))
	_update_time_label()
	_update_play_button()
	_status_label.text = "Raw clip loaded. Adjustments update the real pilot immediately."


func _process(_delta: float) -> void:
	if _pilot == null or _timeline == null or _timeline_dragging:
		return
	if not bool(_pilot.call("is_retarget_preview_paused")):
		_updating_controls = true
		_timeline.value = float(_pilot.call("get_retarget_preview_position"))
		_updating_controls = false
		_update_time_label()


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var margin := MarginContainer.new()
	margin.name = "TunerPanel"
	margin.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	margin.offset_left = -480.0
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	layer.add_child(margin)

	var panel := PanelContainer.new()
	margin.add_child(panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.05, 0.075, 0.96)
	panel_style.border_color = Color(0.22, 0.32, 0.45, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	var title := Label.new()
	title.text = "PARACHUTE POSE TUNER"
	title.add_theme_font_size_override("font_size", 22)
	outer.add_child(title)
	var help := Label.new()
	help.text = "F6 runs this scene. Scrub the imported clip, then adjust local bone rotations. Zero is the untouched animation."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(0.78, 0.84, 0.92)
	outer.add_child(help)

	_build_timeline(outer)
	_build_view_angle(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 8)
	scroll.add_child(controls)
	for definition in ROTATION_CONTROLS:
		_add_rotation_group(controls, StringName(definition[0]), String(definition[1]))
	_add_grip_control(controls)

	var mirror_row := HBoxContainer.new()
	outer.add_child(mirror_row)
	var mirror_left_button := Button.new()
	mirror_left_button.name = "MirrorLeftToRight"
	mirror_left_button.text = "Mirror left -> right"
	mirror_left_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mirror_left_button.pressed.connect(_on_mirror_left_to_right_pressed)
	mirror_row.add_child(mirror_left_button)
	var mirror_right_button := Button.new()
	mirror_right_button.name = "MirrorRightToLeft"
	mirror_right_button.text = "Mirror right -> left"
	mirror_right_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mirror_right_button.pressed.connect(_on_mirror_right_to_left_pressed)
	mirror_row.add_child(mirror_right_button)

	var button_row := HBoxContainer.new()
	outer.add_child(button_row)
	var reset_button := Button.new()
	reset_button.name = "ResetRawClip"
	reset_button.text = "Reset to raw clip"
	reset_button.pressed.connect(_on_reset_pressed)
	button_row.add_child(reset_button)
	var reload_button := Button.new()
	reload_button.name = "ReloadSaved"
	reload_button.text = "Reload saved"
	reload_button.pressed.connect(_on_reload_pressed)
	button_row.add_child(reload_button)
	var save_button := Button.new()
	save_button.name = "SavePose"
	save_button.text = "Save pose"
	save_button.pressed.connect(_on_save_pressed)
	button_row.add_child(save_button)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.modulate = Color(0.64, 0.82, 0.66)
	outer.add_child(_status_label)
	_refresh_controls_from_settings()


func _build_timeline(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	parent.add_child(header)
	_play_button = Button.new()
	_play_button.name = "PlayPause"
	_play_button.custom_minimum_size.x = 76.0
	_play_button.pressed.connect(_on_play_pressed)
	header.add_child(_play_button)
	_timeline = HSlider.new()
	_timeline.name = "Timeline"
	_timeline.min_value = 0.0
	_timeline.max_value = 1.0
	_timeline.step = 0.001
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.value_changed.connect(_on_timeline_changed)
	_timeline.drag_started.connect(_on_timeline_drag_started)
	_timeline.drag_ended.connect(_on_timeline_drag_ended)
	header.add_child(_timeline)
	_time_label = Label.new()
	_time_label.custom_minimum_size.x = 88.0
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_time_label)


func _build_view_angle(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = "View angle"
	label.custom_minimum_size.x = 92.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "ViewAngle"
	slider.min_value = -180.0
	slider.max_value = 180.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_view_angle_changed)
	row.add_child(slider)


func _add_rotation_group(parent: VBoxContainer, property_name: StringName, title_text: String) -> void:
	var group := VBoxContainer.new()
	parent.add_child(group)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 16)
	title.modulate = Color(0.92, 0.73, 0.42)
	group.add_child(title)
	for axis in range(3):
		var row := HBoxContainer.new()
		group.add_child(row)
		var axis_label := Label.new()
		axis_label.text = ["X", "Y", "Z"][axis]
		axis_label.custom_minimum_size.x = 24.0
		row.add_child(axis_label)
		var spin := SpinBox.new()
		spin.name = "%s_%s" % [property_name, ["X", "Y", "Z"][axis]]
		spin.min_value = -180.0
		spin.max_value = 180.0
		spin.step = 1.0
		spin.suffix = " deg"
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_on_rotation_changed.bind(property_name, axis))
		row.add_child(spin)
		_rotation_spins.append({"property": property_name, "axis": axis, "control": spin})


func _add_grip_control(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = "Grip relaxation"
	label.custom_minimum_size.x = 150.0
	row.add_child(label)
	_grip_spin = SpinBox.new()
	_grip_spin.name = "GripRelaxation"
	_grip_spin.min_value = 0.0
	_grip_spin.max_value = 1.0
	_grip_spin.step = 0.01
	_grip_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grip_spin.value_changed.connect(_on_grip_changed)
	row.add_child(_grip_spin)


func _on_rotation_changed(value: float, property_name: StringName, axis: int) -> void:
	if _updating_controls or _settings == null:
		return
	var rotation: Vector3 = _settings.get(property_name)
	rotation[axis] = value
	_settings.set(property_name, rotation)
	_refresh_pose("Unsaved pose adjustments")


func _on_grip_changed(value: float) -> void:
	if _updating_controls or _settings == null:
		return
	_settings.grip_relaxation = value
	_refresh_pose("Unsaved grip adjustment")


func _on_timeline_changed(value: float) -> void:
	if _updating_controls or _pilot == null:
		return
	_pilot.call("seek_retarget_preview", value)
	_update_time_label()


func _on_timeline_drag_started() -> void:
	_timeline_dragging = true
	_resume_after_drag = not bool(_pilot.call("is_retarget_preview_paused"))
	_pilot.call("set_retarget_preview_paused", true)
	_update_play_button()


func _on_timeline_drag_ended(_value_changed: bool) -> void:
	_timeline_dragging = false
	if _resume_after_drag:
		_pilot.call("set_retarget_preview_paused", false)
	_update_play_button()


func _on_play_pressed() -> void:
	var paused := bool(_pilot.call("is_retarget_preview_paused"))
	_pilot.call("set_retarget_preview_paused", not paused)
	_update_play_button()


func _on_view_angle_changed(value: float) -> void:
	_pilot.rotation_degrees.y = value


func _on_reset_pressed() -> void:
	_settings.reset_to_raw_clip()
	_refresh_controls_from_settings()
	_refresh_pose("Raw imported animation restored; not saved yet")


func _on_reload_pressed() -> void:
	_apply_settings_snapshot(_saved_values)
	_refresh_controls_from_settings()
	_refresh_pose("Reloaded the last saved pose")


func _on_mirror_left_to_right_pressed() -> void:
	_mirror_arm_pose(true)


func _on_mirror_right_to_left_pressed() -> void:
	_mirror_arm_pose(false)


func _mirror_arm_pose(left_to_right: bool) -> void:
	var source_skeleton := _pilot.get("_retarget_source_skeleton") as Skeleton3D
	if source_skeleton == null:
		_status_label.text = "Mirror failed: source skeleton is unavailable"
		_status_label.modulate = Color(1.0, 0.45, 0.4)
		return
	for definition in MIRROR_BONE_PAIRS:
		var left_bone := StringName(definition[0])
		var right_bone := StringName(definition[1])
		var left_property := StringName(definition[2])
		var right_property := StringName(definition[3])
		var source_bone := left_bone if left_to_right else right_bone
		var target_bone := right_bone if left_to_right else left_bone
		var source_property := left_property if left_to_right else right_property
		var target_property := right_property if left_to_right else left_property
		var mirrored := _mirror_local_rotation_offset(
			source_skeleton,
			source_bone,
			target_bone,
			_settings.get(source_property)
		)
		_settings.set(target_property, mirrored)
	_refresh_controls_from_settings()
	_refresh_pose(
		"Mirrored left pose to right; click Save pose to keep it"
		if left_to_right
		else "Mirrored right pose to left; click Save pose to keep it"
	)


func _mirror_local_rotation_offset(
		skeleton: Skeleton3D,
		source_bone_name: StringName,
		target_bone_name: StringName,
		source_degrees: Vector3
) -> Vector3:
	var source_index := skeleton.find_bone(source_bone_name)
	var target_index := skeleton.find_bone(target_bone_name)
	if source_index < 0 or target_index < 0:
		return Vector3.ZERO
	var source_rest := skeleton.get_bone_global_rest(source_index).basis.orthonormalized()
	var target_rest := skeleton.get_bone_global_rest(target_index).basis.orthonormalized()
	var source_radians := Vector3(
		deg_to_rad(source_degrees.x),
		deg_to_rad(source_degrees.y),
		deg_to_rad(source_degrees.z)
	)
	var source_local_offset := Basis(Quaternion.from_euler(source_radians))
	var source_world_delta := source_rest * source_local_offset * source_rest.inverse()
	# Reflection through the character's sagittal plane. Conjugating the world
	# rotation by this reflection produces a proper mirrored rotation basis.
	var reflection := Basis(
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0)
	)
	var mirrored_world_delta := reflection * source_world_delta * reflection
	var target_local_offset := (
		target_rest.inverse() * mirrored_world_delta * target_rest
	).orthonormalized()
	var target_radians := target_local_offset.get_euler()
	return Vector3(
		rad_to_deg(target_radians.x),
		rad_to_deg(target_radians.y),
		rad_to_deg(target_radians.z)
	)


func _on_save_pressed() -> void:
	var error := ResourceSaver.save(_settings, SETTINGS_PATH)
	if error != OK:
		_status_label.text = "Save failed with error %d" % error
		_status_label.modulate = Color(1.0, 0.45, 0.4)
		return
	_saved_values = _capture_settings()
	_status_label.text = "Saved to %s" % SETTINGS_PATH
	_status_label.modulate = Color(0.64, 0.82, 0.66)


func _refresh_pose(status: String) -> void:
	_pilot.call("refresh_retarget_preview")
	_status_label.text = status
	_status_label.modulate = Color(0.92, 0.73, 0.42)


func _refresh_controls_from_settings() -> void:
	_updating_controls = true
	for entry in _rotation_spins:
		var property_name := StringName(entry["property"])
		var axis := int(entry["axis"])
		var spin := entry["control"] as SpinBox
		var rotation: Vector3 = _settings.get(property_name)
		spin.value = rotation[axis]
	_grip_spin.value = _settings.grip_relaxation
	_updating_controls = false


func _capture_settings() -> Dictionary:
	return {
		&"left_shoulder_degrees": _settings.left_shoulder_degrees,
		&"left_upper_arm_degrees": _settings.left_upper_arm_degrees,
		&"left_forearm_degrees": _settings.left_forearm_degrees,
		&"left_hand_degrees": _settings.left_hand_degrees,
		&"right_shoulder_degrees": _settings.right_shoulder_degrees,
		&"right_upper_arm_degrees": _settings.right_upper_arm_degrees,
		&"right_forearm_degrees": _settings.right_forearm_degrees,
		&"right_hand_degrees": _settings.right_hand_degrees,
		&"grip_relaxation": _settings.grip_relaxation,
	}


func _apply_settings_snapshot(values: Dictionary) -> void:
	_settings.left_shoulder_degrees = values.get(&"left_shoulder_degrees", Vector3.ZERO)
	_settings.left_upper_arm_degrees = values.get(&"left_upper_arm_degrees", Vector3.ZERO)
	_settings.left_forearm_degrees = values.get(&"left_forearm_degrees", Vector3.ZERO)
	_settings.left_hand_degrees = values.get(&"left_hand_degrees", Vector3.ZERO)
	_settings.right_shoulder_degrees = values.get(&"right_shoulder_degrees", Vector3.ZERO)
	_settings.right_upper_arm_degrees = values.get(&"right_upper_arm_degrees", Vector3.ZERO)
	_settings.right_forearm_degrees = values.get(&"right_forearm_degrees", Vector3.ZERO)
	_settings.right_hand_degrees = values.get(&"right_hand_degrees", Vector3.ZERO)
	_settings.grip_relaxation = float(values.get(&"grip_relaxation", 0.0))


func _update_play_button() -> void:
	_play_button.text = "Play" if bool(_pilot.call("is_retarget_preview_paused")) else "Pause"


func _update_time_label() -> void:
	_time_label.text = "%.2f / %.2f s" % [_timeline.value, _timeline.max_value]
