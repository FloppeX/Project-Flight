extends Node

const PANEL_SCRIPT := preload("res://HUD/instrument_panel.gd")

var _failed: bool = false


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

	var target_viewport := SubViewport.new()
	target_viewport.size = Vector2i(200, 200)
	panel.target_viewport = target_viewport
	panel.assumed_target_width_m = 10.0
	panel.min_fov_deg = 1.0
	var near_target_fov: float = panel._calculate_target_camera_fov(100.0)
	var far_target_fov: float = panel._calculate_target_camera_fov(2000.0)
	_require(near_target_fov > 5.0 and near_target_fov < 6.0, "100 m target framing is incorrect: %.3f deg" % near_target_fov)
	_require(is_equal_approx(far_target_fov, 1.0), "2 km target did not reach the Camera3D optical zoom limit: %.3f deg" % far_target_fov)
	panel.target_camera_zoom_lerp_speed = 100.0
	panel._slew_target_camera_fov(far_target_fov, 1.0)
	_require(is_equal_approx(camera.fov, 1.0), "target camera rejected the narrow optical FOV: %.3f deg" % camera.fov)

	var generated_aircraft := RigidBody3D.new()
	generated_aircraft.name = "RigidBody1854"
	generated_aircraft.set_meta("source_scene_path", "res://Aircraft/Aircraft_1.tscn")
	_require(
		panel._get_target_display_name(generated_aircraft) == "SNA AS-20 Sand Sprite",
		"generated aircraft instance name leaked into the target label"
	)
	var vehicle_scene := load("res://GroundVehicle/vehicle_enemy_buggy.tscn") as PackedScene
	var vehicle := vehicle_scene.instantiate() as Node3D
	vehicle.name = "CharacterBody3D991"
	_require(
		panel._get_target_display_name(vehicle) == "ENEMY ATTACK BUGGY",
		"ground vehicle did not resolve through the display catalog"
	)
	var structure_scene := load("res://Buildings/building_barracks.tscn") as PackedScene
	var structure := structure_scene.instantiate() as Node3D
	structure.name = "StaticBody317"
	_require(
		panel._get_target_display_name(structure) == "BARRACKS",
		"structure did not resolve through the display catalog"
	)
	var unknown_body := RigidBody3D.new()
	unknown_body.name = "RigidBody1854"
	_require(
		panel._get_target_display_name(unknown_body) == "UNKNOWN CONTACT",
		"unidentified generated physics name was displayed"
	)

	var shader: Shader = panel._create_target_effect_shader()
	_require(shader.code.contains("fwidth(y_px)"), "scanlines are not derivative-smoothed")
	_require(shader.code.contains("smoothstep"), "scanlines still use a hard pixel edge")
	var panel_source := FileAccess.get_file_as_string("res://HUD/instrument_panel.gd")
	_require(
		panel_source.contains('set_shader_parameter("texture_size", target_panel.size)'),
		"scanline scale is not tied to the target display size"
	)
	if _failed:
		unknown_body.free()
		structure.free()
		vehicle.free()
		generated_aircraft.free()
		target_viewport.free()
		panel.free()
		get_tree().quit(1)
		return

	print("[InstrumentPanelTargetCameraSmoketest] PASS mount_turn=%.2f zoom_2km=%.3fdeg labels=catalog_names scanlines=display_pixels+soft_edges" % [world_turn_deg, far_target_fov])
	unknown_body.free()
	structure.free()
	vehicle.free()
	generated_aircraft.free()
	target_viewport.free()
	panel.free()
	get_tree().quit(0)


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[InstrumentPanelTargetCameraSmoketest] FAIL %s" % message)
