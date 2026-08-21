extends Node

const PANEL_SCRIPT := preload("res://HUD/instrument_panel.gd")


func _ready() -> void:
	var panel = PANEL_SCRIPT.new()
	var camera := Camera3D.new()
	add_child(camera)
	panel.target_camera = camera
	panel.target_camera_slew_deg_s = 120.0

	var initial_mount := Transform3D.IDENTITY
	panel._slew_target_camera_to_transform(initial_mount, initial_mount, 0.0)
	_require(panel._target_camera_pose_initialized, "camera pose did not initialize")

	var turned_mount := Transform3D(
		Basis(Vector3.UP, deg_to_rad(90.0)),
		Vector3(12.0, 3.0, -7.0)
	)
	# Hold the desired world aim steady while the aircraft turns. The camera must
	# inherit the 90-degree mount turn immediately, minus only the 12 degrees the
	# gimbal can counter-slew during this 0.1-second frame.
	var steady_world_aim := Transform3D(Basis.IDENTITY, turned_mount.origin)
	panel._slew_target_camera_to_transform(turned_mount, steady_world_aim, 0.1)
	var world_turn_deg := rad_to_deg(
		Basis.IDENTITY.get_rotation_quaternion().angle_to(
			camera.global_basis.get_rotation_quaternion()
		)
	)
	_require(is_equal_approx(camera.global_position.x, turned_mount.origin.x), "camera mount position lagged")
	_require(world_turn_deg > 75.0 and world_turn_deg < 81.0, "camera did not inherit mount turn immediately: %.2f deg" % world_turn_deg)

	var shader: Shader = panel._create_target_effect_shader()
	_require(shader.code.contains("fwidth(y_px)"), "scanlines are not derivative-smoothed")
	_require(shader.code.contains("smoothstep"), "scanlines still use a hard pixel edge")
	var panel_source := FileAccess.get_file_as_string("res://HUD/instrument_panel.gd")
	_require(
		panel_source.contains('set_shader_parameter("texture_size", target_panel.size)'),
		"scanline scale is not tied to the target display size"
	)

	print("[InstrumentPanelTargetCameraSmoketest] PASS mount_turn=%.2f scanlines=display_pixels+soft_edges" % world_turn_deg)
	panel.free()
	get_tree().quit(0)


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("[InstrumentPanelTargetCameraSmoketest] FAIL %s" % message)
	get_tree().quit(1)

