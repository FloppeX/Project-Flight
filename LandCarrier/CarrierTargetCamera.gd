class_name CarrierTargetCamera
extends Node3D

## Shared mast-mounted carrier target camera. One low-resolution SubViewport is
## shared by every monitor station, regardless of monitor count.

const VIEWPORT_SIZE := Vector2i(640, 360)
const REFRESH_INTERVAL_S := 1.0 / 15.0

@export_range(1.0, 60.0, 1.0) var refresh_rate_hz: float = 15.0
@export var viewport_size: Vector2i = VIEWPORT_SIZE
@export_range(1.0, 90.0, 0.5) var minimum_fov_deg: float = 2.0
@export_range(1.0, 90.0, 0.5) var maximum_fov_deg: float = 42.0
@export_range(1.0, 90.0, 0.5) var idle_fov_deg: float = 52.0
@export var assumed_target_width_m: float = 14.0
@export var target_camera_slew_deg_s: float = 120.0
@export var target_camera_zoom_lerp_speed: float = 6.0
@export var target_provider_refresh_interval_s: float = 1.0
@export var render_only_when_monitor_visible: bool = true
@export var search_revolution_s: float = 20.0
@export var search_fov_deg: float = 70.0

## Kept as Variant so a target freed by combat can be validity-checked before
## any Node3D cast or property access.
var current_target: Variant = null

var _feed_viewport: SubViewport = null
var _feed_camera: Camera3D = null
var _screen_material: ShaderMaterial = null
var _registered_screens: Array[WeakRef] = []
var _target_providers: Array[WeakRef] = []
var _refresh_accumulator_s: float = 0.0
var _provider_refresh_accumulator_s: float = INF
var _aim_basis: Basis = Basis.IDENTITY
var _pose_initialized: bool = false
var _last_feed_active: bool = false
var _controlled: bool = false
var _free_yaw: float = 0.0
var _free_pitch: float = 0.0
var _manual_fov: float = 52.0
var _status_label: Label
var _fullscreen_camera: Camera3D
var _fullscreen_hud: CanvasLayer
var _fullscreen_status: Label
var _return_camera: WeakRef
var _fullscreen_enabled: bool = false
var _auto_searching: bool = false
var _scan_yaw: float = 0.0
var _low_light_enabled: bool = false
var _low_light_material: ShaderMaterial
var _feed_low_light: ColorRect
var _fullscreen_low_light: ColorRect

func begin_control() -> void:
	_controlled = true
	current_target = null
	_manual_fov = idle_fov_deg
	_auto_searching = false
	_refresh_accumulator_s = 1.0 / maxf(refresh_rate_hz, 1.0)

func end_control() -> void:
	_controlled = false
	_end_fullscreen_view()
	_update_automatic_camera(0.0)
	_refresh_accumulator_s = 1.0 / maxf(refresh_rate_hz, 1.0)

func begin_fullscreen_view() -> void:
	if not _controlled or _fullscreen_enabled:
		return
	var previous_camera := get_viewport().get_camera_3d()
	if previous_camera == null:
		return
	_return_camera = weakref(previous_camera)
	_ensure_fullscreen_view()
	_update_low_light_mode()
	_update_current_target()
	_update_feed_camera(0.0)
	_copy_fullscreen_pose()
	_fullscreen_enabled = true
	_fullscreen_camera.make_current()
	_fullscreen_hud.show()
	# No second full-size viewport: the mast replaces the room's main render.
	_feed_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_last_feed_active = false

func is_fullscreen_active() -> bool:
	return _fullscreen_enabled and is_instance_valid(_fullscreen_camera) \
		and get_viewport().get_camera_3d() == _fullscreen_camera

func _end_fullscreen_view() -> void:
	if not _fullscreen_enabled:
		return
	# An external camera switch (e.g. photo mode) must not be stolen back.
	if is_fullscreen_active() and _return_camera != null:
		var previous: Variant = _return_camera.get_ref()
		if is_instance_valid(previous) and previous is Camera3D \
				and previous.is_inside_tree() and not previous.is_queued_for_deletion():
			previous.make_current()
	_fullscreen_enabled = false
	_return_camera = null
	if is_instance_valid(_fullscreen_hud):
		_fullscreen_hud.hide()

func _exit_tree() -> void:
	_end_fullscreen_view()

func _ensure_fullscreen_view() -> void:
	if is_instance_valid(_fullscreen_camera):
		return
	_fullscreen_camera = Camera3D.new()
	_fullscreen_camera.name = "FullscreenMastCamera"
	_fullscreen_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_fullscreen_camera.near = _feed_camera.near
	_fullscreen_camera.far = _feed_camera.far
	add_child(_fullscreen_camera)
	_fullscreen_hud = CanvasLayer.new()
	_fullscreen_hud.name = "MastCameraHUD"
	_fullscreen_hud.layer = 20
	_fullscreen_hud.hide()
	add_child(_fullscreen_hud)
	_fullscreen_low_light = _create_low_light_overlay(_fullscreen_hud)
	_fullscreen_status = _status_label.duplicate() as Label
	_fullscreen_status.position = Vector2(28, 24)
	_fullscreen_status.add_theme_font_size_override("font_size", 24)
	_fullscreen_hud.add_child(_fullscreen_status)

func _copy_fullscreen_pose() -> void:
	_fullscreen_camera.global_transform = _feed_camera.global_transform
	_fullscreen_camera.fov = _feed_camera.fov
	_fullscreen_status.text = _status_label.text

func get_available_targets() -> Array[Node3D]:
	var defense_ops := get_parent().get_node_or_null("DefenseOps")
	if defense_ops != null and defense_ops.has_method("get_available_targets"):
		return defense_ops.call("get_available_targets") as Array[Node3D]
	# Standalone previews can supply targets without loading a complete carrier.
	var result: Array[Node3D] = []
	for provider_ref in _target_providers:
		var target := _get_provider_target(provider_ref.get_ref() as Node)
		if target != null and not result.has(target):
			result.append(target)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.get_instance_id() < b.get_instance_id())
	return result

func cycle_target(direction: int) -> void:
	if not _controlled:
		return
	var targets := get_available_targets()
	var index := targets.find(current_target) if _is_live_target(current_target) else -1
	# Ring: free look, target 1 ... target N, free look (in either direction).
	var next_index := posmod(index + 1 + direction, targets.size() + 1) - 1
	current_target = targets[next_index] if next_index >= 0 else null
	if current_target != null:
		_manual_fov = _calculate_target_fov(global_position.distance_to(current_target.global_position))

func apply_manual_input(stick: Vector2, zoom: float, delta: float) -> void:
	if not _controlled or get_tree().paused:
		return
	if not _is_live_target(current_target):
		var speed := deg_to_rad(55.0) * clampf(_manual_fov / idle_fov_deg, 0.08, 1.0)
		_free_yaw = wrapf(_free_yaw - stick.x * speed * delta, -PI, PI)
		_free_pitch = clampf(_free_pitch - stick.y * speed * delta, deg_to_rad(-85.0), deg_to_rad(85.0))
	_manual_fov = clampf(_manual_fov * exp(-zoom * delta * 1.4), minimum_fov_deg, 70.0)


func _ready() -> void:
	add_to_group("carrier_target_camera")
	add_to_group("target_camera_focus_provider")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_manual_fov = idle_fov_deg
	_ensure_feed_viewport()
	call_deferred("_refresh_target_providers")


func _process(delta: float) -> void:
	_update_low_light_mode()
	_update_automatic_camera(delta)
	_provider_refresh_accumulator_s += delta
	if _provider_refresh_accumulator_s >= maxf(target_provider_refresh_interval_s, 0.1):
		_provider_refresh_accumulator_s = 0.0
		_refresh_target_providers()

	if _fullscreen_enabled:
		if is_fullscreen_active():
			# Update aim at display cadence, independently of the 15 Hz preview.
			_update_current_target()
			_update_feed_camera(delta)
			_copy_fullscreen_pose()
			_feed_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_last_feed_active = false
			return
		end_control()

	var feed_active := _should_render_feed()
	_last_feed_active = feed_active
	if not feed_active or _feed_viewport == null:
		if _feed_viewport != null:
			_feed_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	_refresh_accumulator_s += delta
	var interval := 1.0 / maxf(refresh_rate_hz, 1.0)
	if _refresh_accumulator_s < interval:
		return
	var camera_delta := _refresh_accumulator_s
	_refresh_accumulator_s = fmod(_refresh_accumulator_s, interval)
	_update_current_target()
	_update_feed_camera(camera_delta)
	_feed_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func register_screen(screen: MeshInstance3D) -> ShaderMaterial:
	if screen == null or not is_instance_valid(screen) or screen.mesh == null:
		return null
	for screen_ref in _registered_screens:
		if screen_ref.get_ref() == screen:
			return _get_or_create_screen_material(screen.mesh.get_aabb())
	_registered_screens.append(weakref(screen))
	_refresh_accumulator_s = 1.0 / maxf(refresh_rate_hz, 1.0)
	return _get_or_create_screen_material(screen.mesh.get_aabb())


func unregister_screen(screen: MeshInstance3D) -> void:
	for index in range(_registered_screens.size() - 1, -1, -1):
		var candidate: Object = _registered_screens[index].get_ref()
		if candidate == null or candidate == screen:
			_registered_screens.remove_at(index)


func register_target_provider(provider: Node) -> void:
	if provider == null or not is_instance_valid(provider):
		return
	for provider_ref in _target_providers:
		if provider_ref.get_ref() == provider:
			return
	_target_providers.append(weakref(provider))


func is_target_camera_focusing_node(node: Node3D) -> bool:
	return (_last_feed_active or is_fullscreen_active()) and node != null and is_instance_valid(node) \
		and node == current_target


func get_debug_snapshot() -> Dictionary:
	_prune_registered_screens()
	_prune_target_providers()
	return {
		"viewport_size": _feed_viewport.size if _feed_viewport != null else Vector2i.ZERO,
		"refresh_rate_hz": refresh_rate_hz,
		"refresh_interval_s": 1.0 / maxf(refresh_rate_hz, 1.0),
		"registered_screen_count": _registered_screens.size(),
		"target_provider_count": _target_providers.size(),
		"has_screen_material": _screen_material != null,
		"has_feed_camera": _feed_camera != null,
		"feed_active": _last_feed_active,
		"fullscreen_active": is_fullscreen_active(),
		"automatic_search": _auto_searching,
		"low_light_enabled": _low_light_enabled,
		"current_target": current_target,
		"mount_global_position": global_position if is_inside_tree() else position,
		"idle_fov_deg": idle_fov_deg,
	}


func _ensure_feed_viewport() -> void:
	if _feed_viewport != null:
		return
	_feed_viewport = SubViewport.new()
	_feed_viewport.name = "CarrierTargetCameraViewport"
	_feed_viewport.size = viewport_size
	_feed_viewport.transparent_bg = false
	_feed_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_feed_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_feed_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_feed_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_feed_viewport.use_taa = false
	_feed_viewport.use_debanding = false
	_feed_viewport.positional_shadow_atlas_size = 0
	add_child(_feed_viewport)
	# The viewport owns its Camera3D, but observes the same 3D world as the main
	# carrier scene. Its transform is copied from this mast mount before a frame.
	_feed_viewport.world_3d = get_viewport().world_3d

	_feed_camera = Camera3D.new()
	_feed_camera.name = "Camera3D"
	_feed_camera.fov = idle_fov_deg
	_feed_camera.near = 0.15
	_feed_camera.far = 12000.0
	_feed_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_feed_viewport.add_child(_feed_camera)
	_feed_camera.current = true
	_feed_low_light = _create_low_light_overlay(_feed_viewport)
	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.position = Vector2(12, 10)
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.8))
	_status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	_feed_viewport.add_child(_status_label)


func _create_low_light_overlay(parent: Node) -> ColorRect:
	if _low_light_material == null:
		_low_light_material = ShaderMaterial.new()
		# Same light amplification and green phosphor treatment as aircraft HUDs.
		_low_light_material.shader = preload("res://Shaders/nightvision.gdshader")
		_low_light_material.set_shader_parameter("noise_amt", 0.025)
	var overlay := ColorRect.new()
	overlay.name = "LightEnhancement"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.material = _low_light_material
	overlay.visible = _low_light_enabled
	parent.add_child(overlay)
	return overlay

func _update_low_light_mode() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	var darkness := 0.0
	if is_instance_valid(cycle) and cycle.has_method("get_ai_darkness_factor"):
		darkness = float(cycle.call("get_ai_darkness_factor"))
	# Separate thresholds avoid flickering on and off around dusk.
	if darkness >= 0.6:
		_low_light_enabled = true
	elif darkness <= 0.4:
		_low_light_enabled = false
	if is_instance_valid(_feed_low_light):
		_feed_low_light.size = Vector2(_feed_viewport.size)
		_feed_low_light.visible = _low_light_enabled
	if is_instance_valid(_fullscreen_low_light):
		_fullscreen_low_light.size = get_viewport().get_visible_rect().size
		_fullscreen_low_light.visible = _low_light_enabled

func _get_or_create_screen_material(screen_aabb: AABB) -> ShaderMaterial:
	_ensure_feed_viewport()
	if _feed_viewport == null:
		return null
	if _screen_material == null:
		_screen_material = _create_screen_material()
	_screen_material.set_shader_parameter(
		"mesh_min",
		Vector2(screen_aabb.position.x, screen_aabb.position.y)
	)
	_screen_material.set_shader_parameter(
		"mesh_max",
		Vector2(screen_aabb.end.x, screen_aabb.end.y)
	)
	return _screen_material


func _create_screen_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D camera_texture : source_color, filter_linear;
uniform vec2 mesh_min = vec2(0.0);
uniform vec2 mesh_max = vec2(1.0);
uniform float emission_energy = 1.15;

varying vec2 screen_uv;

void vertex() {
	vec2 mesh_span = max(mesh_max - mesh_min, vec2(0.0001));
	vec2 mapped = clamp((VERTEX.xy - mesh_min) / mesh_span, vec2(0.0), vec2(1.0));
	screen_uv = vec2(mapped.x, 1.0 - mapped.y);
}

void fragment() {
	vec3 feed_color = texture(camera_texture, screen_uv).rgb;
	ALBEDO = feed_color;
	EMISSION = feed_color * emission_energy;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("camera_texture", _feed_viewport.get_texture())
	return material


func _refresh_target_providers() -> void:
	_prune_target_providers()
	var carrier_root := get_parent()
	if carrier_root == null:
		return
	for node in carrier_root.find_children("*", "TurretController", true, false):
		register_target_provider(node)


func _update_current_target() -> void:
	var targets := get_available_targets()
	if not _controlled:
		current_target = null
		var nearest_sq := INF
		for target in targets:
			var distance_sq := global_position.distance_squared_to(target.global_position)
			if distance_sq < nearest_sq:
				nearest_sq = distance_sq
				current_target = target
		if current_target != null:
			_manual_fov = _calculate_target_fov(sqrt(nearest_sq))
	elif not _is_live_target(current_target) or not targets.has(current_target):
		current_target = null

func _update_automatic_camera(delta: float) -> void:
	if _controlled:
		return
	_update_current_target()
	if _is_live_target(current_target):
		_auto_searching = false
		return
	if not _auto_searching:
		_scan_yaw = _aim_basis.get_euler().y
	_auto_searching = true
	# Negative yaw is clockwise when viewed from above. Advance even off-screen,
	# while leaving the costly viewport render subject to the visibility gate.
	_scan_yaw = wrapf(_scan_yaw - TAU * maxf(delta, 0.0) / maxf(search_revolution_s, 0.1), -PI, PI)
	_free_pitch = 0.0
	_manual_fov = search_fov_deg

func _get_provider_target(provider: Node) -> Node3D:
	if provider == null or not is_instance_valid(provider):
		return null
	var raw_target: Variant = provider.get("current_target")
	if not _is_live_target(raw_target):
		return null
	return raw_target as Node3D


func _is_live_target(target: Variant) -> bool:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return false
	var target_node := target as Node3D
	if target_node.is_queued_for_deletion():
		return false
	if "is_destroyed" in target_node and bool(target_node.get("is_destroyed")):
		return false
	if "is_dying" in target_node and bool(target_node.get("is_dying")):
		return false
	return true


func _update_feed_camera(delta: float) -> void:
	if _feed_camera == null:
		return
	var mount_transform := get_global_transform_interpolated()
	var desired_basis := mount_transform.basis.orthonormalized() * Basis.from_euler(Vector3(_free_pitch, _free_yaw, 0))
	var desired_fov := _manual_fov
	if _auto_searching and not _controlled:
		# World-level, independent of carrier suspension pitch/roll.
		desired_basis = Basis(Vector3.UP, _scan_yaw)
	if _is_live_target(current_target):
		var target_node := current_target as Node3D
		var target_position := target_node.get_global_transform_interpolated().origin
		if mount_transform.origin.distance_squared_to(target_position) > 0.0001:
			var direction := (target_position - mount_transform.origin).normalized()
			var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP
			desired_basis = Transform3D(Basis(), mount_transform.origin).looking_at(
				target_position,
				up
			).basis
	if not _pose_initialized or (_auto_searching and not _controlled):
		_aim_basis = desired_basis
		_pose_initialized = true
	else:
		_aim_basis = _slew_basis_toward(
			_aim_basis,
			desired_basis,
			target_camera_slew_deg_s,
			delta
		)
	_feed_camera.global_transform = Transform3D(
		_aim_basis.orthonormalized(),
		mount_transform.origin
	)
	var zoom_blend := clampf(
		1.0 - exp(-maxf(target_camera_zoom_lerp_speed, 0.0) * maxf(delta, 0.0)),
		0.0,
		1.0
	)
	_feed_camera.fov = desired_fov if _auto_searching and not _controlled \
		else lerpf(_feed_camera.fov, desired_fov, zoom_blend)
	if _status_label != null:
		var mode := "TRACK: %s" % current_target.name if _is_live_target(current_target) else "FREE LOOK"
		if _auto_searching and not _controlled:
			mode = "AUTO SCAN"
		elif not _controlled:
			mode = "AUTO " + mode
		if _is_live_target(current_target) and current_target.has_method("get_team") \
				and int(current_target.call("get_team")) == 1:
			mode += " [FRIENDLY LANDING]"
		_status_label.text = "%s   %.1fx" % [mode, idle_fov_deg / maxf(_manual_fov, 1.0)]
		if _low_light_enabled:
			_status_label.text += "   LOW LIGHT"
		if _controlled:
			_status_label.text += "\nRS AIM   LT/RT ZOOM   D-PAD TARGET   B BACK"


func _calculate_target_fov(distance_m: float) -> float:
	var aspect := float(maxi(viewport_size.x, 1)) / float(maxi(viewport_size.y, 1))
	var target_width := maxf(assumed_target_width_m, 0.1)
	var desired_vfov_rad := 2.0 * atan(
		target_width / (2.0 * maxf(distance_m, 0.1) * aspect)
	)
	return clampf(
		rad_to_deg(desired_vfov_rad),
		maxf(minimum_fov_deg, 1.0),
		maxf(maximum_fov_deg, minimum_fov_deg)
	)


func _slew_basis_toward(
		from_basis: Basis,
		to_basis: Basis,
		max_deg_s: float,
		delta: float
) -> Basis:
	var from_q := from_basis.orthonormalized().get_rotation_quaternion()
	var to_q := to_basis.orthonormalized().get_rotation_quaternion()
	var angle := from_q.angle_to(to_q)
	if angle <= 0.0001:
		return to_basis.orthonormalized()
	var max_step := deg_to_rad(maxf(max_deg_s, 1.0)) * maxf(delta, 0.0)
	return Basis(from_q.slerp(to_q, clampf(max_step / angle, 0.0, 1.0))).orthonormalized()


func _should_render_feed() -> bool:
	_prune_registered_screens()
	if _registered_screens.is_empty():
		return false
	if not render_only_when_monitor_visible:
		return true
	var main_camera := get_viewport().get_camera_3d()
	if main_camera == null or not is_instance_valid(main_camera):
		return false
	for screen_ref in _registered_screens:
		var screen := screen_ref.get_ref() as MeshInstance3D
		if screen == null or not screen.is_visible_in_tree() or screen.mesh == null:
			continue
		var screen_center := screen.global_transform * screen.mesh.get_aabb().get_center()
		if main_camera.is_position_in_frustum(screen_center):
			return true
	return false


func _prune_registered_screens() -> void:
	for index in range(_registered_screens.size() - 1, -1, -1):
		var screen: Object = _registered_screens[index].get_ref()
		if screen == null or not is_instance_valid(screen):
			_registered_screens.remove_at(index)


func _prune_target_providers() -> void:
	for index in range(_target_providers.size() - 1, -1, -1):
		var provider: Object = _target_providers[index].get_ref()
		if provider == null or not is_instance_valid(provider):
			_target_providers.remove_at(index)
