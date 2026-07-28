extends Node3D

class CCIPSymbol:
	extends Control

	var symbol_color: Color = Color.GREEN
	var ring_radius_px: float = 20.0
	var ring_width_px: float = 3.0
	var dot_radius_px: float = 3.0
	var tick_length_px: float = 7.0
	var tick_gap_px: float = 3.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func configure(
		color: Color,
		radius_px: float,
		width_px: float,
		center_dot_radius_px: float,
		cardinal_tick_length_px: float,
		cardinal_tick_gap_px: float
	) -> void:
		symbol_color = color
		ring_radius_px = radius_px
		ring_width_px = width_px
		dot_radius_px = center_dot_radius_px
		tick_length_px = cardinal_tick_length_px
		tick_gap_px = cardinal_tick_gap_px
		var extent: float = ceil(ring_radius_px + ring_width_px + tick_gap_px + tick_length_px)
		size = Vector2.ONE * (extent * 2.0)
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		draw_arc(center, ring_radius_px, 0.0, TAU, 64, symbol_color, ring_width_px, true)
		draw_circle(center, dot_radius_px, symbol_color)
		var tick_start: float = ring_radius_px + tick_gap_px
		var tick_end: float = tick_start + tick_length_px
		draw_line(center + Vector2(0.0, -tick_start), center + Vector2(0.0, -tick_end), symbol_color, ring_width_px, true)
		draw_line(center + Vector2(tick_start, 0.0), center + Vector2(tick_end, 0.0), symbol_color, ring_width_px, true)
		draw_line(center + Vector2(0.0, tick_start), center + Vector2(0.0, tick_end), symbol_color, ring_width_px, true)
		draw_line(center + Vector2(-tick_start, 0.0), center + Vector2(-tick_end, 0.0), symbol_color, ring_width_px, true)

@export var camera_path: NodePath
@export var aircraft_path: NodePath
@export var crosshair_color: Color = Color.GREEN
@export var hud_primary_color: Color = Color(0.0, 0.55, 0.0, 1.0)
@export var hud_dim_color: Color = Color(0.0, 0.28, 0.0, 1.0)
@export var hud_line_thickness_px: float = 3.5
@export var hud_text_outline_size: int = 2
@export var hud_range: float = 10000.0
@export var hud_glass_size: Vector2 = Vector2(0.4, 0.4)  # 40x40 cm in meters - bigger for more text room
@export var ccip_below_horizon_only: bool = true  # Hide CCIP when projected above screen center
@export var ccip_use_fast: bool = true  # Prefer fast closed-form CCIP
@export var hud_follow_camera_forward: bool = false  # Debug option; true collimated HUD uses aircraft boresight
@export_group("Attitude Ladder")
@export var show_attitude_ladder: bool = true
@export var attitude_tick_step_deg: float = 10.0
@export var attitude_ladder_range_deg: float = 60.0
@export var attitude_ladder_side_margin_px: float = 170.0
@export var attitude_ladder_tick_length_px: float = 16.0
@export var attitude_ladder_horizon_tick_length_px: float = 26.0
@export var attitude_ladder_alpha: float = 0.85
@export var attitude_ladder_show_labels: bool = true
@export var attitude_ladder_label_gap_px: float = 7.0
@export var attitude_ladder_label_width_px: float = 34.0
@export var attitude_ladder_label_font_size: int = 14
@export_group("Compass")
@export var show_compass: bool = true
@export var compass_px_per_deg: float = 6.0
@export var compass_alpha: float = 0.85
@export_group("HUD Data Boxes")
@export var show_speed_alt_boxes: bool = true
@export var speed_alt_box_size_px: Vector2 = Vector2(84.0, 34.0)
@export var speed_alt_box_side_margin_px: float = 14.0
@export var speed_alt_box_vertical_ratio: float = 0.40
@export var speed_alt_box_fill_alpha: float = 0.08

var cam: Camera3D
var aircraft: Node3D
@onready var viewport: SubViewport = $SubViewport
@onready var reticle: Control = $SubViewport/Reticle
@onready var horizontal_line: ColorRect = $SubViewport/Reticle/HorizontalLine
@onready var vertical_line: ColorRect = $SubViewport/Reticle/VerticalLine
@onready var hud_mesh: MeshInstance3D = $HUDglass
@onready var weapon_status: Label = $SubViewport/WeaponStatus
@onready var speed_altitude: Label = $SubViewport/SpeedAltitude
var speed_box_panel: Panel
var speed_box_label: Label
var altitude_box_panel: Panel
var altitude_box_label: Label

# CCIP elements
var ccip_circle: Control
var ccip_update_timer: Timer

# Target overlay elements
var target_overlay: Control
var target_box_lines: Array[ColorRect] = []

# AA missile lock diamond elements
var lock_diamond: Control
var lock_diamond_lines: Array[ColorRect] = []
var lock_label: Label

# Lead aim reticle (red crosshair showing where to aim guns to hit target)
var lead_reticle: Control
var lead_reticle_h_line: ColorRect
var lead_reticle_v_line: ColorRect

# Flight path vector (velocity vector marker)
var fpv_container: Control
var fpv_circle_segments: Array[ColorRect] = []
var fpv_stub_top: ColorRect
var fpv_stub_left: ColorRect
var fpv_stub_right: ColorRect
var fpv_dotted_line_segments: Array[ColorRect] = []
const FPV_DOT_COUNT: int = 12
const FPV_MIN_SPEED_MPS: float = 15.0

# Attitude ladder (side pitch ticks)
var attitude_ladder: Control
var attitude_left_ticks: Array[ColorRect] = []
var attitude_right_ticks: Array[ColorRect] = []
var attitude_left_labels: Array[Label] = []
var attitude_right_labels: Array[Label] = []
var attitude_tick_values_deg: Array[float] = []

# Compass heading strip
const _COMPASS_TICK_STEP: float = 5.0
const _COMPASS_LABEL_STEP: float = 10.0
const _COMPASS_RANGE: float = 55.0
const _COMPASS_TOP: float = 8.0
const _COMPASS_MAJOR_H: float = 16.0
const _COMPASS_MINOR_H: float = 9.0
const _COMPASS_LABEL_GAP: float = 3.0
const _COMPASS_LABEL_H: float = 16.0
const _COMPASS_LABEL_FONT_SIZE: int = 13
const _COMPASS_POOL_TICKS: int = 30
const _COMPASS_POOL_LABELS: int = 16
var compass_strip: Control
var compass_ticks: Array[ColorRect] = []
var compass_labels: Array[Label] = []
var compass_center_mark: ColorRect

# HUD mode system
enum HUDMode { NAV, GUN, ROCKETS, BOMBS }
var hud_mode: HUDMode = HUDMode.NAV
var hud_mode_label: Label
var ccip_line: ColorRect
var _hud_camera_fov_deg: float = 75.0

func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)

func _ready():
	# Manually resolve NodePath references
	if camera_path != NodePath():
		var camera_node: Node = get_node_or_null(camera_path)
		# Try to find a Camera3D within the camera node
		if camera_node:
			cam = camera_node.get_node_or_null("Camera3D") as Camera3D
			if cam == null:
				# Try to find any Camera3D in the scene
				cam = get_tree().get_first_node_in_group("camera") as Camera3D
	
	if aircraft_path != NodePath():
		aircraft = get_node(aircraft_path) as Node3D
	_resolve_bound_cockpit_camera()
	
	# Exit early if any critical nodes are missing
	if hud_mesh == null:
		push_error("HUD: HUDglass node not found!")
		return
	if viewport == null:
		push_error("HUD: SubViewport node not found!")
		return
	
	# Set up the HUD glass mesh
	var quad = QuadMesh.new()
	quad.size = hud_glass_size
	hud_mesh.mesh = quad
	
	# Create material for the HUD glass - use correct property names
	var material = StandardMaterial3D.new()
	
	# Basic transparency setup
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_unshaded = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	
	# Add viewport texture and emission
	material.albedo_texture = viewport.get_texture()
	material.emission_enabled = true
	material.emission_texture = viewport.get_texture()
	material.emission_energy = 5.5
	
	# Apply material
	hud_mesh.material_override = material
	
	# Set up viewport size - make it bigger for more text room
	viewport.size = Vector2i(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Transparent background so only reticle shows on glass
	viewport.transparent_bg = true
	
	# Set up crosshair size to match viewport
	var hud_size: Vector2 = Vector2(viewport.size)
	reticle.size = hud_size
	reticle.pivot_offset = hud_size * 0.5
	reticle.position = Vector2.ZERO
	
	# Make crosshair lines centered and scale relative to HUD size
	var line_len: float = max(hud_size.x, hud_size.y) * 0.25
	var line_thickness: float = hud_line_thickness_px
	horizontal_line.size = Vector2(line_len, line_thickness)
	horizontal_line.position = reticle.pivot_offset - Vector2(line_len * 0.5, line_thickness * 0.5)
	
	vertical_line.size = Vector2(line_thickness, line_len)
	vertical_line.position = reticle.pivot_offset - Vector2(line_thickness * 0.5, line_len * 0.5)
	
	horizontal_line.color = _opaque(hud_primary_color)
	vertical_line.color = _opaque(hud_primary_color)
	
	# Set up weapon status display
	setup_weapon_status()
	
	# Set up speed and altitude display
	setup_speed_altitude()
	
	# Set up CCIP elements
	setup_ccip()

	# Set up target overlay elements
	setup_target_overlay()

	# Set up AA lock diamond
	setup_lock_diamond()

	# Set up lead aim reticle
	setup_lead_reticle()

	# Set up flight path vector
	setup_fpv()

	# Set up attitude ladder
	setup_attitude_ladder()

	# Set up compass heading strip
	setup_compass()

	# Set up HUD mode label and CCIP line
	setup_hud_mode_label()
	setup_ccip_line()

	# Set up a timer to update the CCIP periodically
	ccip_update_timer = Timer.new()
	ccip_update_timer.wait_time = 0.1 # Update 10 times per second
	add_child(ccip_update_timer)
	ccip_update_timer.timeout.connect(update_ccip)
	ccip_update_timer.start()

func setup_weapon_status():
	"""Set up the weapon status display in lower left corner"""
	if weapon_status == null:
		push_error("HUD: WeaponStatus label not found!")
		return
	
	# Position in lower left corner - move more towards the edge
	var hud_size: Vector2 = Vector2(viewport.size)
	weapon_status.position = Vector2(5, hud_size.y - 60)
	weapon_status.size = Vector2(300, 50)
	
	# Style the text - make it more opaque and larger
	weapon_status.text = "No Weapons"
	weapon_status.add_theme_color_override("font_color", _opaque(hud_primary_color))
	weapon_status.add_theme_color_override("font_outline_color", Color.BLACK)
	weapon_status.add_theme_constant_override("outline_size", hud_text_outline_size)
	weapon_status.add_theme_font_size_override("font_size", 20)
	
	# Add background for better visibility
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.0)  # Completely transparent background
	style_box.corner_radius_top_left = 5
	style_box.corner_radius_top_right = 5
	style_box.corner_radius_bottom_left = 5
	style_box.corner_radius_bottom_right = 5
	weapon_status.add_theme_stylebox_override("normal", style_box)

func setup_speed_altitude():
	"""Set up speed/altitude readout boxes near the upper left/right HUD edges."""
	if speed_altitude == null:
		push_error("HUD: SpeedAltitude label not found!")
		return
	# Keep legacy node hidden; we use separate boxed values now.
	speed_altitude.visible = false

	if not show_speed_alt_boxes:
		return

	var speed_data: Dictionary = _build_speed_alt_data_box("SpeedBox")
	speed_box_panel = speed_data.get("panel") as Panel
	speed_box_label = speed_data.get("label") as Label
	viewport.add_child(speed_box_panel)

	var alt_data: Dictionary = _build_speed_alt_data_box("AltitudeBox")
	altitude_box_panel = alt_data.get("panel") as Panel
	altitude_box_label = alt_data.get("label") as Label
	viewport.add_child(altitude_box_panel)

	_layout_speed_alt_boxes()

func _build_speed_alt_data_box(name_text: String) -> Dictionary:
	var panel := Panel.new()
	panel.name = name_text
	panel.custom_minimum_size = speed_alt_box_size_px
	panel.size = speed_alt_box_size_px

	var border_col: Color = _opaque(hud_primary_color)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, clampf(speed_alt_box_fill_alpha, 0.0, 1.0))
	panel_style.draw_center = true
	panel_style.border_color = border_col
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 2
	panel_style.corner_radius_top_right = 2
	panel_style.corner_radius_bottom_left = 2
	panel_style.corner_radius_bottom_right = 2
	panel.add_theme_stylebox_override("panel", panel_style)

	var label := Label.new()
	label.name = "Value"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "0"
	label.add_theme_color_override("font_color", border_col)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", hud_text_outline_size)
	label.add_theme_font_size_override("font_size", 24)
	panel.add_child(label)

	return {"panel": panel, "label": label}

func _layout_speed_alt_boxes() -> void:
	if not is_instance_valid(viewport):
		return
	if not is_instance_valid(speed_box_panel) or not is_instance_valid(altitude_box_panel):
		return
	var hud_size: Vector2 = Vector2(viewport.size)
	var box_size: Vector2 = speed_alt_box_size_px
	var y: float = clampf(hud_size.y * speed_alt_box_vertical_ratio, 0.0, maxf(hud_size.y - box_size.y, 0.0))
	var left_x: float = speed_alt_box_side_margin_px
	var right_x: float = hud_size.x - box_size.x - speed_alt_box_side_margin_px

	speed_box_panel.position = Vector2(left_x, y)
	speed_box_panel.size = box_size
	altitude_box_panel.position = Vector2(right_x, y)
	altitude_box_panel.size = box_size

func setup_ccip():
	"""Set up CCIP visual elements"""
	ccip_circle = CCIPSymbol.new()
	var ring_color: Color = _opaque(hud_primary_color)
	var ring_width: float = maxf(hud_line_thickness_px, 2.0)
	var ring_radius: float = 20.0
	var center_dot_radius: float = maxf(ring_width * 0.9, 2.5)
	var tick_length: float = maxf(ring_width * 2.0, 6.0)
	var tick_gap: float = maxf(ring_width * 0.8, 2.5)
	ccip_circle.configure(ring_color, ring_radius, ring_width, center_dot_radius, tick_length, tick_gap)
	ccip_circle.visible = false
	viewport.add_child(ccip_circle)

func setup_target_overlay():
	"""Set up target overlay elements for drawing green targeting box"""
	target_overlay = Control.new()
	target_overlay.name = "TargetOverlay"
	target_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_overlay.visible = false
	viewport.add_child(target_overlay)
	
	# Create 4 lines to form a target box (top, bottom, left, right)
	var box_color: Color = _opaque(hud_primary_color)
	var line_thickness: float = hud_line_thickness_px
	
	for i in range(4):
		var line = ColorRect.new()
		line.color = box_color
		line.visible = false
		target_overlay.add_child(line)
		target_box_lines.append(line)

func setup_lock_diamond():
	"""Set up the 4-line diamond shape for AA missile lock indication."""
	lock_diamond = Control.new()
	lock_diamond.name = "LockDiamond"
	lock_diamond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lock_diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_diamond.visible = false
	viewport.add_child(lock_diamond)

	# Diamond = 4 lines: top-left, top-right, bottom-left, bottom-right
	# Each is a thin rect rotated 45° — approximate with short rects positioned at diagonals
	var dim_color: Color = _opaque(hud_dim_color)
	for i in range(4):
		var seg = ColorRect.new()
		seg.color = dim_color
		seg.size = Vector2(hud_line_thickness_px, 20)
		lock_diamond.add_child(seg)
		lock_diamond_lines.append(seg)

	# Lock-acquired label above diamond
	lock_label = Label.new()
	lock_label.text = ""
	lock_label.add_theme_color_override("font_color", _opaque(hud_primary_color))
	lock_label.add_theme_color_override("font_outline_color", Color.BLACK)
	lock_label.add_theme_constant_override("outline_size", hud_text_outline_size)
	lock_label.add_theme_font_size_override("font_size", 16)
	lock_diamond.add_child(lock_label)

func _process(dt: float) -> void:
	if aircraft != null and is_instance_valid(aircraft):
		_resolve_bound_cockpit_camera()
	if cam == null or aircraft == null:
		return

	# Handle HUD mode cycling
	if Input.is_action_just_pressed("change_weapon"):
		_cycle_hud_mode()
	_sync_hud_mode_to_ai_weapon()

	# Update weapon status display
	update_weapon_status()
	
	# Update speed and altitude display
	update_speed_altitude()
	
	# Update target overlay
	update_target_overlay()

	# Update AA missile lock diamond
	update_lock_diamond()

	# Update lead aim reticle
	update_lead_reticle()

	# Update flight path vector
	update_fpv()

	# Update attitude ladder (pitch ticks on left/right)
	update_attitude_ladder()

	# Update compass heading strip
	update_compass()

	# Aircraft in this project are authored facing +Z.
	var aircraft_forward: Vector3 = aircraft.global_transform.basis.z
	var camera_forward: Vector3 = -cam.global_transform.basis.z if cam else Vector3.FORWARD
	
	# Project aircraft's nose direction to infinity for proper collimation
	# This makes the crosshair appear at the same point regardless of head movement
	var nose_world: Vector3
	if hud_follow_camera_forward and cam:
		# Use camera position and forward so looking up moves the crosshair up
		nose_world = cam.global_transform.origin + camera_forward * hud_range
	else:
		# Use aircraft boresight
		nose_world = aircraft.global_transform.origin + aircraft_forward * hud_range
	
	var hud_projection: Dictionary = _project_world_to_hud(nose_world)
	if not bool(hud_projection.get("visible", false)):
		reticle.visible = false
		return

	reticle.visible = (hud_mode == HUDMode.GUN)
	reticle.position = (hud_projection.get("hud_pos", Vector2.ZERO) as Vector2) - reticle.pivot_offset

func _project_world_to_hud(world_pos: Vector3, allow_off_glass: bool = false) -> Dictionary:
	if not is_instance_valid(cam) or not is_instance_valid(hud_mesh):
		return {"visible": false, "projected": false, "on_glass": false}
	if cam.is_position_behind(world_pos):
		return {"visible": false, "projected": false, "on_glass": false}

	var camera_pos: Vector3 = cam.global_position
	var ray_direction: Vector3 = (world_pos - camera_pos).normalized()
	if ray_direction.length_squared() < 0.000001:
		return {"visible": false, "projected": false, "on_glass": false}

	var hud_transform: Transform3D = hud_mesh.global_transform
	var hud_normal: Vector3 = -hud_transform.basis.z.normalized()
	var hud_plane := Plane(hud_normal, hud_transform.origin)
	var intersection_point = hud_plane.intersects_ray(camera_pos, ray_direction)
	if intersection_point == null:
		return {"visible": false, "projected": false, "on_glass": false}

	var local_point: Vector3 = hud_mesh.to_local(intersection_point)
	var half_size: Vector2 = hud_glass_size * 0.5
	var on_glass: bool = abs(local_point.x) <= half_size.x and abs(local_point.y) <= half_size.y

	var hud_size_px := Vector2(viewport.size)
	var hud_pos := Vector2(
		(local_point.x + half_size.x) / max(hud_glass_size.x, 0.001) * hud_size_px.x,
		(-local_point.y + half_size.y) / max(hud_glass_size.y, 0.001) * hud_size_px.y
	)
	if not allow_off_glass and not on_glass:
		return {
			"visible": false,
			"projected": true,
			"on_glass": false,
			"hud_pos": hud_pos,
			"intersection_point": intersection_point,
			"local_point": local_point,
		}
	return {
		"visible": on_glass,
		"projected": true,
		"on_glass": on_glass,
		"hud_pos": hud_pos,
		"intersection_point": intersection_point,
		"local_point": local_point,
	}

func update_weapon_status():
	"""Update the weapon status display with current weapon type"""
	if weapon_status == null:
		return
	
	var weapon_control = get_weapon_control()
	
	# Update display based on weapon control status
	if weapon_control and weapon_control.has_method("get_weapon_status"):
		var status = weapon_control.get_weapon_status()
		var selected_type = status.get("selected_type", "")
		var weapon_count = status.get("weapon_count", 0)
		var total_ammo = status.get("total_ammo", 0)
		
		if selected_type != "" and weapon_count > 0:
			if total_ammo > 0:
				weapon_status.text = selected_type + " (" + str(weapon_count) + ") - " + str(total_ammo) + " ammo"
			else:
				weapon_status.text = selected_type + " (" + str(weapon_count) + ")"
		else:
			weapon_status.text = "No Weapons"
	else:
		# Show what we found
		if not aircraft:
			weapon_status.text = "No Aircraft"
		elif not weapon_control:
			weapon_status.text = "No Weapon Control"
		else:
			weapon_status.text = "No Weapons"

func update_speed_altitude():
	"""Update boxed speed/altitude readouts."""
	if aircraft == null:
		return

	var velocity: Vector3 = aircraft.linear_velocity
	var speed_mps: int = int(round(velocity.length()))
	var altitude_value: float = aircraft.global_position.y
	var local_altitude_value: Variant = aircraft.get("local_altitude")
	if local_altitude_value != null:
		altitude_value = float(local_altitude_value)
	var altitude_m: int = int(round(altitude_value))

	if speed_altitude != null:
		speed_altitude.visible = false

	if not show_speed_alt_boxes:
		if is_instance_valid(speed_box_panel):
			speed_box_panel.visible = false
		if is_instance_valid(altitude_box_panel):
			altitude_box_panel.visible = false
		return

	if is_instance_valid(speed_box_panel) and is_instance_valid(speed_box_label):
		speed_box_panel.visible = true
		speed_box_label.text = str(speed_mps)
	if is_instance_valid(altitude_box_panel) and is_instance_valid(altitude_box_label):
		altitude_box_panel.visible = true
		altitude_box_label.text = str(altitude_m)
	_layout_speed_alt_boxes()

func _hide_ccip() -> void:
	if is_instance_valid(ccip_circle):
		ccip_circle.visible = false
	if is_instance_valid(ccip_line):
		ccip_line.visible = false

func update_ccip():
	"""Update CCIP display based on current HUD mode."""
	if ccip_circle == null or aircraft == null or cam == null:
		_hide_ccip()
		return

	if hud_mode != HUDMode.ROCKETS and hud_mode != HUDMode.BOMBS:
		_hide_ccip()
		return

	# Calculate CCIP impact point using the appropriate function
	var ccip_data: Dictionary
	if hud_mode == HUDMode.ROCKETS:
		ccip_data = aircraft.calculate_rocket_ccip_impact_point()
	else:
		ccip_data = aircraft.calculate_ccip_impact_point()

	if not ccip_data.has_impact:
		_hide_ccip()
		return

	var impact_world: Vector3 = ccip_data.impact_position

	var hud_projection: Dictionary = _project_world_to_hud(impact_world)
	if not bool(hud_projection.get("visible", false)):
		_hide_ccip()
		return

	var hud_size_px := Vector2(viewport.size)
	var hud_pos := hud_projection.get("hud_pos", Vector2.ZERO) as Vector2

	# Optional filter: hide CCIP if above approximate horizon (screen center)
	if ccip_below_horizon_only and hud_pos.y < (hud_size_px.y * 0.5 - 4.0):
		_hide_ccip()
		return
	
	ccip_circle.visible = true
	ccip_circle.position = hud_pos - ccip_circle.size * 0.5

	# Draw line from HUD center to CCIP marker
	if is_instance_valid(ccip_line):
		var hud_center: Vector2 = hud_size_px * 0.5
		var to_ccip: Vector2 = hud_pos - hud_center
		var line_dist: float = to_ccip.length()
		if line_dist < 5.0:
			ccip_line.visible = false
		else:
			var t: float = hud_line_thickness_px
			ccip_line.size = Vector2(line_dist, t)
			ccip_line.pivot_offset = Vector2(0.0, t * 0.5)
			ccip_line.position = hud_center
			ccip_line.rotation = atan2(to_ccip.y, to_ccip.x)
			ccip_line.visible = true

func get_weapon_control():
	"""Get the weapon control module - always from our own aircraft only."""
	if not is_instance_valid(aircraft):
		return null
	for child in aircraft.get_children():
		if child is ControlWeapons:
			return child
		for grandchild in child.get_children():
			if grandchild is ControlWeapons:
				return grandchild
	return null

func _set_target_box_visible(p_visible: bool):
	if not is_instance_valid(target_overlay):
		return
	if target_overlay.visible == p_visible:
		return
	
	target_overlay.visible = p_visible
	# The lines are children, but were created invisible.
	# Make sure their visibility matches the parent overlay.
	for line in target_box_lines:
		if is_instance_valid(line):
			line.visible = p_visible

func _is_gear_down() -> bool:
	if not is_instance_valid(aircraft):
		return false
	for child in aircraft.get_children():
		if "gear_down_state" in child:
			return bool(child.get("gear_down_state"))
		for grandchild in child.get_children():
			if "gear_down_state" in grandchild:
				return bool(grandchild.get("gear_down_state"))
	return false

func _get_nearest_landing_target() -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	var pos: Vector3 = aircraft.global_position
	for node in get_tree().get_nodes_in_group("carrier"):
		if node is Node3D:
			var d: float = (node as Node3D).global_position.distance_to(pos)
			if d < best_dist:
				best_dist = d
				best = node as Node3D
	for node in get_tree().get_nodes_in_group("runway"):
		if node is Node3D:
			var d: float = (node as Node3D).global_position.distance_to(pos)
			if d < best_dist:
				best_dist = d
				best = node as Node3D
	return best

func update_target_overlay():
	"""Update the green target box overlay when target is visible in HUD"""
	# Ensure all required nodes are valid before proceeding
	var required_nodes = [target_overlay, cam, aircraft, hud_mesh]
	for node in required_nodes:
		if not is_instance_valid(node):
			_set_target_box_visible(false)
			return

	# Gear down: landing target always takes priority over combat target.
	var target: Node3D = null
	if _is_gear_down():
		target = _get_nearest_landing_target()

	# Fall back to combat target when gear is up.
	if not is_instance_valid(target):
		var targeting_system = get_targeting_system()
		if is_instance_valid(targeting_system) and "current_target" in targeting_system:
			var raw_target = targeting_system.current_target
			if is_instance_valid(raw_target):
				target = raw_target

	# Hide overlay if no valid target exists
	if not is_instance_valid(target):
		_set_target_box_visible(false)
		return

	var hud_projection: Dictionary = _project_world_to_hud(target.global_position)
	if not bool(hud_projection.get("visible", false)):
		_set_target_box_visible(false)
		return

	var hud_size_px := Vector2(viewport.size)
	var hud_pos := hud_projection.get("hud_pos", Vector2.ZERO) as Vector2

	# Check if the target is within the HUD viewport bounds (with some margin)
	var margin = 50.0
	if (hud_pos.x < -margin or hud_pos.x > (hud_size_px.x + margin) or 
		hud_pos.y < -margin or hud_pos.y > (hud_size_px.y + margin)):
		_set_target_box_visible(false)
		return

	# Target is visible in HUD, so show and position the box
	_set_target_box_visible(true)
	
	var box_size = Vector2(40, 40)
	var line_thickness: float = hud_line_thickness_px
	var top_left = hud_pos - (box_size * 0.5)
	
	# Position the 4 lines that form the box
	var top_line := target_box_lines[0]
	var bottom_line := target_box_lines[1]
	var left_line := target_box_lines[2]
	var right_line := target_box_lines[3]
	
	top_line.position = top_left
	top_line.size = Vector2(box_size.x, line_thickness)
	
	bottom_line.position = Vector2(top_left.x, top_left.y + box_size.y - line_thickness)
	bottom_line.size = Vector2(box_size.x, line_thickness)

	left_line.position = top_left
	left_line.size = Vector2(line_thickness, box_size.y)
	
	right_line.position = Vector2(top_left.x + box_size.x - line_thickness, top_left.y)
	right_line.size = Vector2(line_thickness, box_size.y)


func get_targeting_system():
	"""Get the targeting system module - always from our own aircraft only."""
	if not is_instance_valid(aircraft):
		return null
	for child in aircraft.get_children():
		if child is AircraftModule_ControlTargeting:
			return child
		for grandchild in child.get_children():
			if grandchild is AircraftModule_ControlTargeting:
				return grandchild
	return null

## Called by FlightDirector when switching spectated aircraft.
## Rebinds the HUD so both the reticle and readouts reflect the new plane.
func bind_to_aircraft(new_aircraft: Node3D) -> void:
	if not is_instance_valid(new_aircraft):
		return
	aircraft = new_aircraft
	_resolve_bound_cockpit_camera()


func _resolve_bound_cockpit_camera() -> void:
	if not is_instance_valid(aircraft):
		return
	var cockpit_tripod := aircraft.get_node_or_null("CameraCockpit") as Node3D
	if cockpit_tripod == null:
		return
	var cockpit_cam := cockpit_tripod.find_child("Camera3D", true, false) as Camera3D
	if cockpit_cam != null and is_instance_valid(cockpit_cam):
		cam = cockpit_cam
		_hud_camera_fov_deg = maxf(cockpit_cam.fov, 1.0)

func update_lock_diamond() -> void:
	"""Show a diamond over the current AA target: dim while acquiring, bright when locked."""
	if not is_instance_valid(lock_diamond):
		return

	# Only show for AA missiles
	var weapon_control = get_weapon_control()
	var aa_selected := false
	if weapon_control and "selected_weapon_type" in weapon_control:
		aa_selected = (weapon_control.selected_weapon_type == "AAMissile")
	if not aa_selected:
		lock_diamond.visible = false
		return

	# Need a targeting module with lock data
	var targeting = _get_aa_targeting()
	if not is_instance_valid(targeting):
		lock_diamond.visible = false
		return

	var raw_target = targeting.get("current_target")
	if not is_instance_valid(raw_target):
		lock_diamond.visible = false
		return

	# Project target onto HUD glass
	var target_world: Vector3 = raw_target.global_position
	if not is_instance_valid(cam) or not is_instance_valid(hud_mesh):
		lock_diamond.visible = false
		return
	var hud_projection: Dictionary = _project_world_to_hud(target_world)
	if not bool(hud_projection.get("visible", false)):
		lock_diamond.visible = false
		return

	var hud_pos := hud_projection.get("hud_pos", Vector2.ZERO) as Vector2

	# Lock progress
	var lock_time: float = 0.0
	if targeting.has_method("get_target_lock_time"):
		lock_time = targeting.get_target_lock_time()
	var required: float = 3.0
	if "required_lock_time" in targeting:
		required = float(targeting.required_lock_time)
	var locked := lock_time >= required

	# Draw diamond: 4 line segments at N/E/S/W tips
	# Diamond half-size
	var r := 20.0  # radius in viewport pixels
	var t: float = hud_line_thickness_px
	var seg_len := r * 0.6
	var bright: Color = _opaque(hud_primary_color)
	var dim: Color = _opaque(hud_dim_color)
	var col := bright if locked else dim

	# NW corner segment (top-left arm of diamond)
	# We represent the diamond with 4 corner-angle brackets (like ⟨⟩ rotated)
	# Positions: top (hud_pos - (0, r)), right (hud_pos + (r, 0)),
	#            bottom (hud_pos + (0, r)), left (hud_pos - (r, 0))
	# Lines: top→right, right→bottom, bottom→left, left→top
	var tips := [
		hud_pos + Vector2(0, -r),   # top
		hud_pos + Vector2(r, 0),    # right
		hud_pos + Vector2(0, r),    # bottom
		hud_pos + Vector2(-r, 0),   # left
	]

	for i in range(4):
		var seg: ColorRect = lock_diamond_lines[i]
		seg.color = col
		var a: Vector2 = tips[i]
		var b: Vector2 = tips[(i + 1) % 4]
		var dx: float = b.x - a.x
		var dy: float = b.y - a.y
		var length := sqrt(dx * dx + dy * dy)
		seg.size = Vector2(length, t)
		seg.position = a
		seg.pivot_offset = Vector2(0, t * 0.5)
		seg.rotation = atan2(dy, dx)

	# Label
	if locked:
		lock_label.text = "LOCK"
	else:
		lock_label.text = ""
	lock_label.position = hud_pos + Vector2(-20, -r - 20)

	lock_diamond.visible = true

func setup_fpv() -> void:
	fpv_container = Control.new()
	fpv_container.name = "FlightPathVector"
	fpv_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fpv_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fpv_container.visible = false
	viewport.add_child(fpv_container)

	var col: Color = _opaque(hud_primary_color)
	var t: float = hud_line_thickness_px

	# Circle — approximate with 8 small segments around a 10px radius
	var radius: float = 10.0
	var seg_count: int = 8
	for i in range(seg_count):
		var angle_a: float = TAU * float(i) / float(seg_count)
		var angle_b: float = TAU * float(i + 1) / float(seg_count)
		var ax: float = cos(angle_a) * radius
		var ay: float = sin(angle_a) * radius
		var bx: float = cos(angle_b) * radius
		var by: float = sin(angle_b) * radius
		var seg := ColorRect.new()
		seg.color = col
		var dx: float = bx - ax
		var dy: float = by - ay
		var seg_len: float = sqrt(dx * dx + dy * dy)
		seg.size = Vector2(seg_len, t)
		seg.pivot_offset = Vector2(0, t * 0.5)
		seg.rotation = atan2(dy, dx)
		# Position will be set relative to FPV center in update
		fpv_container.add_child(seg)
		fpv_circle_segments.append(seg)

	# Stub lines — top (vertical going up), left, right (horizontal going outward)
	var stub_len: float = 8.0

	fpv_stub_top = ColorRect.new()
	fpv_stub_top.color = col
	fpv_stub_top.size = Vector2(t, stub_len)
	fpv_container.add_child(fpv_stub_top)

	fpv_stub_left = ColorRect.new()
	fpv_stub_left.color = col
	fpv_stub_left.size = Vector2(stub_len, t)
	fpv_container.add_child(fpv_stub_left)

	fpv_stub_right = ColorRect.new()
	fpv_stub_right.color = col
	fpv_stub_right.size = Vector2(stub_len, t)
	fpv_container.add_child(fpv_stub_right)

	# Dotted line segments from crosshair to FPV
	for i in range(FPV_DOT_COUNT):
		var dot_seg := ColorRect.new()
		dot_seg.color = col
		dot_seg.size = Vector2(4, t)
		dot_seg.pivot_offset = Vector2(2, t * 0.5)
		fpv_container.add_child(dot_seg)
		fpv_dotted_line_segments.append(dot_seg)

func update_fpv() -> void:
	if not is_instance_valid(fpv_container):
		return
	if hud_mode != HUDMode.NAV:
		fpv_container.visible = false
		return
	if not is_instance_valid(cam) or not is_instance_valid(aircraft) or not is_instance_valid(hud_mesh):
		fpv_container.visible = false
		return

	var vel: Vector3 = Vector3.ZERO
	if "linear_velocity" in aircraft:
		vel = aircraft.linear_velocity
	var speed: float = vel.length()
	if speed < FPV_MIN_SPEED_MPS:
		fpv_container.visible = false
		return

	# Project velocity direction onto HUD — place the point far away along the velocity vector
	# Keep the FPV in HUD-plane coordinates so it does not jump when it leaves the glass.
	var fpv_world: Vector3 = cam.global_position + vel.normalized() * hud_range
	var hud_projection: Dictionary = _project_world_to_hud(fpv_world, true)
	var fpv_projected: bool = bool(hud_projection.get("projected", false))
	var fpv_pos: Vector2 = Vector2.ZERO

	if fpv_projected:
		fpv_pos = hud_projection.get("hud_pos", Vector2.ZERO) as Vector2
	else:
		# FPV is off-screen — project via screen space so the dotted line can point toward it
		if cam.is_position_behind(fpv_world):
			# Behind camera — use unprojected and flip to get a direction
			var screen_pt: Vector2 = cam.unproject_position(fpv_world)
			var hud_center := Vector2(viewport.size) * 0.5
			fpv_pos = hud_center + (hud_center - screen_pt).normalized() * 600.0
		else:
			var screen_pt: Vector2 = cam.unproject_position(fpv_world)
			# Map screen pixel to HUD viewport coordinates
			var vp_size: Vector2 = cam.get_viewport().get_visible_rect().size
			fpv_pos = (screen_pt / vp_size) * Vector2(viewport.size)

	fpv_container.visible = true

	# Determine if the FPV symbol itself is within drawable area
	var hud_size_px := Vector2(viewport.size)
	var symbol_margin: float = 20.0
	var symbol_on_hud: bool = (fpv_pos.x >= -symbol_margin and fpv_pos.x <= hud_size_px.x + symbol_margin
		and fpv_pos.y >= -symbol_margin and fpv_pos.y <= hud_size_px.y + symbol_margin)

	# Position circle segments around FPV center (hide if off-screen)
	var radius: float = 10.0
	var seg_count: int = fpv_circle_segments.size()
	var t: float = hud_line_thickness_px
	for i in range(seg_count):
		fpv_circle_segments[i].visible = symbol_on_hud
		if symbol_on_hud:
			var angle_a: float = TAU * float(i) / float(seg_count)
			var ax: float = cos(angle_a) * radius
			var ay: float = sin(angle_a) * radius
			fpv_circle_segments[i].position = fpv_pos + Vector2(ax, ay) - Vector2(0, t * 0.5)

	# Position stubs (hide if off-screen)
	var stub_len: float = 8.0
	fpv_stub_top.visible = symbol_on_hud
	fpv_stub_left.visible = symbol_on_hud
	fpv_stub_right.visible = symbol_on_hud
	if symbol_on_hud:
		fpv_stub_top.position = fpv_pos + Vector2(-t * 0.5, -radius - stub_len)
		fpv_stub_left.position = fpv_pos + Vector2(-radius - stub_len, -t * 0.5)
		fpv_stub_right.position = fpv_pos + Vector2(radius, -t * 0.5)

	# Dotted line from crosshair center toward FPV (drawn even when FPV is off-HUD)
	var crosshair_center: Vector2 = reticle.position + reticle.pivot_offset
	var to_fpv: Vector2 = fpv_pos - crosshair_center
	var line_dist: float = to_fpv.length()
	if line_dist < 20.0:
		for dot_seg in fpv_dotted_line_segments:
			dot_seg.visible = false
	else:
		var line_dir: Vector2 = to_fpv / line_dist
		var line_angle: float = atan2(line_dir.y, line_dir.x)
		var start_offset: float = 12.0
		# If symbol is on screen, stop before the circle; otherwise draw to HUD edge
		var end_offset: float = (radius + 4.0) if symbol_on_hud else 0.0
		var draw_dist: float = line_dist - start_offset - end_offset
		# Clamp draw distance to HUD bounds
		var max_draw: float = hud_size_px.length()
		draw_dist = minf(draw_dist, max_draw)
		if draw_dist < 8.0:
			for dot_seg in fpv_dotted_line_segments:
				dot_seg.visible = false
		else:
			var dot_len: float = 4.0
			var gap: float = maxf((draw_dist - dot_len * FPV_DOT_COUNT) / maxf(FPV_DOT_COUNT - 1, 1), dot_len * 0.5)
			var stride: float = dot_len + gap
			for i in range(FPV_DOT_COUNT):
				var along: float = start_offset + stride * float(i)
				if along + dot_len > start_offset + draw_dist:
					fpv_dotted_line_segments[i].visible = false
				else:
					var dot_center: Vector2 = crosshair_center + line_dir * (along + dot_len * 0.5)
					# Only show dots that are within the HUD viewport
					if dot_center.x < -10.0 or dot_center.x > hud_size_px.x + 10.0 or dot_center.y < -10.0 or dot_center.y > hud_size_px.y + 10.0:
						fpv_dotted_line_segments[i].visible = false
					else:
						fpv_dotted_line_segments[i].visible = true
						fpv_dotted_line_segments[i].position = dot_center - Vector2(dot_len * 0.5, t * 0.5)
						fpv_dotted_line_segments[i].rotation = line_angle

func setup_lead_reticle() -> void:
	"""Set up the red lead-aim crosshair that shows where to point guns to hit the target."""
	lead_reticle = Control.new()
	lead_reticle.name = "LeadReticle"
	lead_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lead_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead_reticle.visible = false
	viewport.add_child(lead_reticle)

	var red: Color = Color(1.0, 0.15, 0.1, 1.0)
	var arm_len: float = 14.0
	var thickness: float = hud_line_thickness_px

	lead_reticle_h_line = ColorRect.new()
	lead_reticle_h_line.color = red
	lead_reticle_h_line.size = Vector2(arm_len * 2.0, thickness)
	lead_reticle.add_child(lead_reticle_h_line)

	lead_reticle_v_line = ColorRect.new()
	lead_reticle_v_line.color = red
	lead_reticle_v_line.size = Vector2(thickness, arm_len * 2.0)
	lead_reticle.add_child(lead_reticle_v_line)

func update_lead_reticle() -> void:
	"""Compute and display the lead-aim point for the current gun/target pair."""
	if not is_instance_valid(lead_reticle):
		return
	if hud_mode != HUDMode.GUN:
		lead_reticle.visible = false
		return
	if not is_instance_valid(cam) or not is_instance_valid(aircraft) or not is_instance_valid(hud_mesh):
		lead_reticle.visible = false
		return

	# Need a valid air target
	var targeting_system = get_targeting_system()
	var target: Node3D = null
	if is_instance_valid(targeting_system) and "current_target" in targeting_system:
		var raw_target = targeting_system.current_target
		if is_instance_valid(raw_target):
			target = raw_target
	if not is_instance_valid(target):
		lead_reticle.visible = false
		return

	# Get target motion — only show lead reticle for moving targets (aircraft)
	var target_pos: Vector3 = target.global_position
	var target_vel: Vector3 = Vector3.ZERO
	if "linear_velocity" in target:
		target_vel = target.linear_velocity
	if target_vel.length_squared() < 25.0:
		# Target not moving fast enough to need lead (ground target or stationary)
		lead_reticle.visible = false
		return

	# Get shooter (our aircraft) motion
	var gun_mount: Dictionary = _get_gun_mount_info()
	var shooter_pos: Vector3 = gun_mount.get("origin", aircraft.global_position)
	var shooter_vel: Vector3 = _get_aircraft_point_velocity_at_world_position(shooter_pos)

	# Get muzzle velocity from equipped gun
	var muzzle_speed: float = _get_gun_muzzle_velocity()
	if muzzle_speed < 50.0:
		lead_reticle.visible = false
		return

	# Compute gravity-compensated aim point (where to point the nose so bullets hit)
	var lead_point: Vector3 = _compute_ballistic_aim_point(shooter_pos, shooter_vel, target_pos, target_vel, muzzle_speed)

	# Project lead point onto HUD
	var hud_projection: Dictionary = _project_world_to_hud(lead_point)
	if not bool(hud_projection.get("visible", false)):
		lead_reticle.visible = false
		return

	var hud_pos: Vector2 = hud_projection.get("hud_pos", Vector2.ZERO) as Vector2
	var hud_size_px := Vector2(viewport.size)
	var margin: float = 30.0
	if hud_pos.x < -margin or hud_pos.x > hud_size_px.x + margin or hud_pos.y < -margin or hud_pos.y > hud_size_px.y + margin:
		lead_reticle.visible = false
		return

	lead_reticle.visible = true
	# Center the crosshair lines on the projected point
	var h_size: Vector2 = lead_reticle_h_line.size
	var v_size: Vector2 = lead_reticle_v_line.size
	lead_reticle_h_line.position = hud_pos - Vector2(h_size.x * 0.5, h_size.y * 0.5)
	lead_reticle_v_line.position = hud_pos - Vector2(v_size.x * 0.5, v_size.y * 0.5)

func _get_gun_muzzle_velocity() -> float:
	"""Return muzzle velocity for the selected gun, or any available non-missile gun."""
	var weapon_control = get_weapon_control()
	if not is_instance_valid(weapon_control):
		return 0.0
	if not "hardpoints" in weapon_control:
		return 0.0

	var selected_type: String = ""
	if "selected_weapon_type" in weapon_control:
		selected_type = str(weapon_control.selected_weapon_type)

	var fallback_speed: float = 0.0
	for hp in weapon_control.hardpoints:
		if not hp or not hp.weapon_instance:
			continue
		var weapon_name: String = str(hp.weapon_instance.weapon_name)
		if not _is_lead_reticle_gun_weapon_name(weapon_name):
			continue
		var speed_mps: float = 0.0
		if "muzzle_velocity" in hp.weapon_instance:
			speed_mps = float(hp.weapon_instance.muzzle_velocity)
		elif "bullet_speed" in hp.weapon_instance:
			speed_mps = float(hp.weapon_instance.bullet_speed)
		speed_mps = maxf(speed_mps, 0.0)
		if speed_mps <= 0.0:
			continue
		if selected_type != "" and weapon_name == selected_type:
			return speed_mps
		if fallback_speed <= 0.0:
			fallback_speed = speed_mps
	return fallback_speed

func _is_lead_reticle_gun_weapon_name(weapon_name: String) -> bool:
	if weapon_name.is_empty():
		return false
	return weapon_name != "Bomb" and weapon_name != "AAMissile"

func _get_gun_mount_info() -> Dictionary:
	var mount_info := {
		"origin": aircraft.global_position if is_instance_valid(aircraft) else Vector3.ZERO,
	}
	var weapon_control = get_weapon_control()
	if not is_instance_valid(weapon_control):
		return mount_info
	if not "hardpoints" in weapon_control:
		return mount_info

	var selected_type: String = ""
	if "selected_weapon_type" in weapon_control:
		selected_type = str(weapon_control.selected_weapon_type)

	var count: int = 0
	var avg_origin: Vector3 = Vector3.ZERO
	for hp in weapon_control.hardpoints:
		if not hp or not hp.weapon_instance:
			continue
		var weapon_name: String = str(hp.weapon_instance.weapon_name)
		if not _is_lead_reticle_gun_weapon_name(weapon_name):
			continue
		if selected_type != "" and weapon_name != selected_type:
			continue
		avg_origin += hp.global_position
		count += 1

	if count <= 0:
		for hp in weapon_control.hardpoints:
			if not hp or not hp.weapon_instance:
				continue
			var weapon_name_fallback: String = str(hp.weapon_instance.weapon_name)
			if not _is_lead_reticle_gun_weapon_name(weapon_name_fallback):
				continue
			avg_origin += hp.global_position
			count += 1

	if count > 0:
		mount_info["origin"] = avg_origin / float(count)
	return mount_info

func _get_aircraft_point_velocity_at_world_position(world_pos: Vector3) -> Vector3:
	if not is_instance_valid(aircraft):
		return Vector3.ZERO

	var point_velocity: Vector3 = Vector3.ZERO
	if "linear_velocity" in aircraft:
		point_velocity = aircraft.linear_velocity
	elif aircraft.get("velocity") is Vector3:
		point_velocity = aircraft.get("velocity")
	elif aircraft.has_method("get_linear_velocity"):
		var getter_velocity = aircraft.call("get_linear_velocity")
		if getter_velocity is Vector3:
			point_velocity = getter_velocity

	var angular_velocity = aircraft.get("angular_velocity")
	if angular_velocity is Vector3:
		var r_offset: Vector3 = world_pos - aircraft.global_position
		point_velocity += (angular_velocity as Vector3).cross(r_offset)
	return point_velocity

func _compute_ballistic_aim_point(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3, projectile_speed: float) -> Vector3:
	"""Gravity-compensated aim point: where to point the nose so bullets hit the target.
	Iteratively solves for the muzzle direction that makes a gravity-affected projectile
	arrive at the target's predicted future position."""
	var muzzle_speed: float = maxf(projectile_speed, 50.0)
	var gravity_vec: Vector3 = Vector3(0.0, -1.0, 0.0) * ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var max_tof: float = 1.2
	var min_tof: float = 0.02
	var best_error: float = INF
	var best_t: float = min_tof
	var best_muzzle_vec: Vector3 = Vector3.ZERO
	var best_intercept: Vector3 = target_pos

	# Coarse search over time-of-flight
	var coarse_steps: int = 24
	for i in range(coarse_steps):
		var t: float = lerpf(min_tof, max_tof, float(i) / float(coarse_steps - 1))
		var future_target: Vector3 = target_pos + target_vel * t
		# Solve for the muzzle-relative velocity needed to hit future_target at time t:
		# future_target = shooter_pos + shooter_vel * t + muzzle_vec * t + 0.5 * gravity * t²
		var required_muzzle_vec: Vector3 = (future_target - shooter_pos - shooter_vel * t - 0.5 * gravity_vec * t * t) / t
		var speed_error: float = absf(required_muzzle_vec.length() - muzzle_speed)
		if speed_error < best_error:
			best_error = speed_error
			best_t = t
			best_intercept = future_target
			best_muzzle_vec = required_muzzle_vec

	# Refine around the best coarse result
	var coarse_step_span: float = (max_tof - min_tof) / maxf(float(coarse_steps - 1), 1.0)
	var refine_min: float = maxf(min_tof, best_t - coarse_step_span)
	var refine_max: float = minf(max_tof, best_t + coarse_step_span)
	var refine_steps: int = 10
	for i in range(refine_steps):
		var t: float = lerpf(refine_min, refine_max, float(i) / float(refine_steps - 1))
		var future_target: Vector3 = target_pos + target_vel * t
		var required_muzzle_vec: Vector3 = (future_target - shooter_pos - shooter_vel * t - 0.5 * gravity_vec * t * t) / t
		var speed_error: float = absf(required_muzzle_vec.length() - muzzle_speed)
		if speed_error < best_error:
			best_error = speed_error
			best_t = t
			best_intercept = future_target
			best_muzzle_vec = required_muzzle_vec

	if best_muzzle_vec.length_squared() < 1.0:
		# Fallback: simple lead point without gravity
		var rel_pos: Vector3 = target_pos - shooter_pos
		var t: float = maxf(rel_pos.length() / muzzle_speed, 0.01)
		return target_pos + target_vel * t

	# Project the required muzzle direction out to aim distance to get the aim point
	var launch_dir: Vector3 = best_muzzle_vec.normalized()
	var aim_dist: float = maxf((best_intercept - shooter_pos).length(), 50.0)
	return shooter_pos + launch_dir * aim_dist

func _get_aa_targeting() -> Node:
	"""Find AircraftModule_ControlTargeting_AAM on the aircraft."""
	if not is_instance_valid(aircraft):
		return null
	for child in aircraft.get_children():
		if child is AircraftModule_ControlTargeting_AAM:
			return child
		for grandchild in child.get_children():
			if grandchild is AircraftModule_ControlTargeting_AAM:
				return grandchild
	return null

func setup_attitude_ladder() -> void:
	attitude_ladder = Control.new()
	attitude_ladder.name = "AttitudeLadder"
	attitude_ladder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	attitude_ladder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attitude_ladder.visible = show_attitude_ladder
	viewport.add_child(attitude_ladder)

	attitude_left_ticks.clear()
	attitude_right_ticks.clear()
	attitude_left_labels.clear()
	attitude_right_labels.clear()
	attitude_tick_values_deg.clear()

	var step_deg: float = maxf(attitude_tick_step_deg, 1.0)
	var range_deg: float = maxf(attitude_ladder_range_deg, step_deg)
	var tick_each_side: int = int(floor(range_deg / step_deg))
	var tick_color: Color = Color(
		hud_primary_color.r,
		hud_primary_color.g,
		hud_primary_color.b,
		clampf(attitude_ladder_alpha, 0.0, 1.0)
	)

	for i in range(-tick_each_side, tick_each_side + 1):
		var tick_deg: float = float(i) * step_deg
		attitude_tick_values_deg.append(tick_deg)

		var left_tick: ColorRect = ColorRect.new()
		left_tick.color = tick_color
		left_tick.visible = false
		attitude_ladder.add_child(left_tick)
		attitude_left_ticks.append(left_tick)

		var left_label: Label = Label.new()
		left_label.text = str(int(round(tick_deg)))
		left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		left_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		left_label.add_theme_color_override("font_color", tick_color)
		left_label.add_theme_color_override("font_outline_color", Color.BLACK)
		left_label.add_theme_constant_override("outline_size", hud_text_outline_size)
		left_label.add_theme_font_size_override("font_size", attitude_ladder_label_font_size)
		left_label.visible = false
		attitude_ladder.add_child(left_label)
		attitude_left_labels.append(left_label)

		var right_tick: ColorRect = ColorRect.new()
		right_tick.color = tick_color
		right_tick.visible = false
		attitude_ladder.add_child(right_tick)
		attitude_right_ticks.append(right_tick)

		var right_label: Label = Label.new()
		right_label.text = str(int(round(tick_deg)))
		right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		right_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		right_label.add_theme_color_override("font_color", tick_color)
		right_label.add_theme_color_override("font_outline_color", Color.BLACK)
		right_label.add_theme_constant_override("outline_size", hud_text_outline_size)
		right_label.add_theme_font_size_override("font_size", attitude_ladder_label_font_size)
		right_label.visible = false
		attitude_ladder.add_child(right_label)
		attitude_right_labels.append(right_label)

func update_attitude_ladder() -> void:
	if not is_instance_valid(attitude_ladder):
		return
	if not show_attitude_ladder or not is_instance_valid(viewport) or not is_instance_valid(aircraft):
		attitude_ladder.visible = false
		attitude_ladder.rotation = 0.0
		return
	if attitude_tick_values_deg.is_empty():
		attitude_ladder.visible = false
		attitude_ladder.rotation = 0.0
		return
	attitude_ladder.visible = true

	var hud_size_px: Vector2 = Vector2(viewport.size)
	attitude_ladder.pivot_offset = hud_size_px * 0.5
	# Keep the ladder world-level: rotate opposite aircraft bank.
	attitude_ladder.rotation = -_get_aircraft_roll_rad()

	var center_y: float = hud_size_px.y * 0.5
	var line_thickness: float = hud_line_thickness_px
	var pitch_deg: float = _get_aircraft_pitch_deg()
	var fov_deg: float = _hud_camera_fov_deg
	if is_instance_valid(cam):
		_hud_camera_fov_deg = maxf(cam.fov, 1.0)
		fov_deg = _hud_camera_fov_deg
	var pixels_per_degree: float = hud_size_px.y / fov_deg

	for idx in range(attitude_tick_values_deg.size()):
		var tick_deg: float = attitude_tick_values_deg[idx]
		var y: float = center_y + (pitch_deg - tick_deg) * pixels_per_degree
		var on_hud: bool = y >= -4.0 and y <= hud_size_px.y + 4.0
		var left_tick: ColorRect = attitude_left_ticks[idx]
		var right_tick: ColorRect = attitude_right_ticks[idx]
		var left_label: Label = attitude_left_labels[idx]
		var right_label: Label = attitude_right_labels[idx]
		if not on_hud:
			left_tick.visible = false
			right_tick.visible = false
			left_label.visible = false
			right_label.visible = false
			continue

		var is_horizon_tick: bool = is_zero_approx(tick_deg)
		var tick_len: float = attitude_ladder_horizon_tick_length_px if is_horizon_tick else attitude_ladder_tick_length_px
		var alpha_scale: float = 1.0 if is_horizon_tick else 0.72
		var tick_color: Color = Color(
			hud_primary_color.r,
			hud_primary_color.g,
			hud_primary_color.b,
			clampf(attitude_ladder_alpha * alpha_scale, 0.0, 1.0)
		)

		left_tick.color = tick_color
		right_tick.color = tick_color

		left_tick.visible = true
		left_tick.position = Vector2(attitude_ladder_side_margin_px, y - line_thickness * 0.5)
		left_tick.size = Vector2(tick_len, line_thickness)

		var right_end_x: float = hud_size_px.x - attitude_ladder_side_margin_px
		right_tick.visible = true
		right_tick.position = Vector2(right_end_x - tick_len, y - line_thickness * 0.5)
		right_tick.size = Vector2(tick_len, line_thickness)

		if attitude_ladder_show_labels:
			var label_height: float = float(attitude_ladder_label_font_size) + 6.0
			var label_size: Vector2 = Vector2(attitude_ladder_label_width_px, label_height)
			left_label.visible = true
			right_label.visible = true
			left_label.size = label_size
			right_label.size = label_size
			left_label.position = Vector2(
				attitude_ladder_side_margin_px - attitude_ladder_label_gap_px - label_size.x,
				y - label_size.y * 0.5
			)
			right_label.position = Vector2(
				right_end_x + attitude_ladder_label_gap_px,
				y - label_size.y * 0.5
			)
			left_label.add_theme_color_override("font_color", tick_color)
			right_label.add_theme_color_override("font_color", tick_color)
		else:
			left_label.visible = false
			right_label.visible = false

func _get_aircraft_pitch_deg() -> float:
	if not is_instance_valid(aircraft):
		return 0.0
	var nose_dir: Vector3 = aircraft.global_transform.basis.z.normalized()
	var pitch_rad: float = asin(clampf(nose_dir.y, -1.0, 1.0))
	return rad_to_deg(pitch_rad)

func _get_aircraft_roll_rad() -> float:
	if not is_instance_valid(aircraft):
		return 0.0
	var basis: Basis = aircraft.global_transform.basis.orthonormalized()
	var forward: Vector3 = basis.z.normalized()
	var up: Vector3 = basis.y.normalized()
	var world_up: Vector3 = Vector3.UP
	var ref_right: Vector3 = forward.cross(world_up)
	if ref_right.length_squared() < 0.000001:
		return 0.0
	ref_right = ref_right.normalized()
	var ref_up: Vector3 = ref_right.cross(forward).normalized()
	var sinv: float = forward.dot(ref_up.cross(up))
	var cosv: float = clampf(ref_up.dot(up), -1.0, 1.0)
	return atan2(sinv, cosv)

func _get_aircraft_heading_deg() -> float:
	if not is_instance_valid(aircraft):
		return 0.0
	var fwd: Vector3 = aircraft.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)

func setup_compass() -> void:
	compass_strip = Control.new()
	compass_strip.name = "CompassStrip"
	compass_strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	compass_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_strip.visible = show_compass
	viewport.add_child(compass_strip)

	var tick_col := Color(hud_primary_color.r, hud_primary_color.g, hud_primary_color.b, compass_alpha)
	for _i in range(_COMPASS_POOL_TICKS):
		var t := ColorRect.new()
		t.color = tick_col
		t.visible = false
		compass_strip.add_child(t)
		compass_ticks.append(t)

	for _i in range(_COMPASS_POOL_LABELS):
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", _COMPASS_LABEL_FONT_SIZE)
		lbl.add_theme_color_override("font_color", tick_col)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", hud_text_outline_size)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.visible = false
		compass_strip.add_child(lbl)
		compass_labels.append(lbl)

	# Bright center reference mark
	compass_center_mark = ColorRect.new()
	compass_center_mark.color = _opaque(hud_primary_color)
	compass_strip.add_child(compass_center_mark)

func update_compass() -> void:
	if not is_instance_valid(compass_strip):
		return
	if hud_mode != HUDMode.NAV or not show_compass or not is_instance_valid(viewport) or not is_instance_valid(aircraft):
		compass_strip.visible = false
		return
	compass_strip.visible = true

	var hud_w: float = float(viewport.size.x)
	var cx: float = hud_w * 0.5
	var lt: float = hud_line_thickness_px
	var px: float = compass_px_per_deg
	var tick_top: float = _COMPASS_TOP
	var label_top: float = tick_top + _COMPASS_MAJOR_H + _COMPASS_LABEL_GAP
	var label_w: float = 38.0

	# Center mark (always at cx, slightly wider than a normal tick)
	compass_center_mark.size = Vector2(lt + 2.0, _COMPASS_MAJOR_H)
	compass_center_mark.position = Vector2(cx - (lt + 2.0) * 0.5, tick_top)

	var hdg: float = _get_aircraft_heading_deg()

	# --- Ticks ---
	var t_start: float = floor((hdg - _COMPASS_RANGE) / _COMPASS_TICK_STEP) * _COMPASS_TICK_STEP
	for i in range(_COMPASS_POOL_TICKS):
		var tv: float = t_start + float(i) * _COMPASS_TICK_STEP
		var delta: float = fposmod(tv - hdg + 180.0, 360.0) - 180.0
		var x: float = cx + delta * px
		var t: ColorRect = compass_ticks[i]
		if absf(delta) > _COMPASS_RANGE + _COMPASS_TICK_STEP:
			t.visible = false
			continue
		var is_major: bool = is_zero_approx(fposmod(tv, _COMPASS_LABEL_STEP))
		var th: float = _COMPASS_MAJOR_H if is_major else _COMPASS_MINOR_H
		var ty: float = tick_top if is_major else tick_top + (_COMPASS_MAJOR_H - _COMPASS_MINOR_H)
		t.visible = true
		t.size = Vector2(lt, th)
		t.position = Vector2(x - lt * 0.5, ty)

	# --- Labels ---
	var l_start: float = floor((hdg - _COMPASS_RANGE) / _COMPASS_LABEL_STEP) * _COMPASS_LABEL_STEP
	for i in range(_COMPASS_POOL_LABELS):
		var lv: float = l_start + float(i) * _COMPASS_LABEL_STEP
		var delta: float = fposmod(lv - hdg + 180.0, 360.0) - 180.0
		var x: float = cx + delta * px
		var lbl: Label = compass_labels[i]
		if absf(delta) > _COMPASS_RANGE + _COMPASS_LABEL_STEP:
			lbl.visible = false
			continue
		var hn: int = int(fposmod(lv, 360.0))
		var txt: String
		var is_cardinal: bool = hn == 0 or hn == 90 or hn == 180 or hn == 270
		match hn:
			0:   txt = "N"
			90:  txt = "E"
			180: txt = "S"
			270: txt = "W"
			_:   txt = str(hn)
		lbl.text = txt
		lbl.add_theme_font_size_override("font_size", 20 if is_cardinal else _COMPASS_LABEL_FONT_SIZE)
		lbl.size = Vector2(label_w, _COMPASS_LABEL_H)
		lbl.position = Vector2(x - label_w * 0.5, label_top)
		lbl.visible = true

func setup_hud_mode_label() -> void:
	hud_mode_label = Label.new()
	hud_mode_label.name = "HUDModeLabel"
	hud_mode_label.add_theme_color_override("font_color", _opaque(hud_primary_color))
	hud_mode_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_mode_label.add_theme_constant_override("outline_size", hud_text_outline_size)
	hud_mode_label.add_theme_font_size_override("font_size", 20)
	hud_mode_label.text = "NAV"
	hud_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_mode_label.size = Vector2(100, 30)
	var hud_size: Vector2 = Vector2(viewport.size)
	hud_mode_label.position = Vector2(hud_size.x * 0.5 - 50.0, 50.0)
	viewport.add_child(hud_mode_label)

func setup_ccip_line() -> void:
	ccip_line = ColorRect.new()
	ccip_line.name = "CCIPLine"
	ccip_line.color = _opaque(hud_primary_color)
	ccip_line.visible = false
	viewport.add_child(ccip_line)

func _cycle_hud_mode() -> void:
	var available: Array = _available_hud_modes()
	if available.is_empty():
		return
	var current_idx: int = available.find(hud_mode)
	if current_idx == -1:
		current_idx = 0
	else:
		current_idx = (current_idx + 1) % available.size()
	hud_mode = available[current_idx]

	# Sync selected weapon type in ControlWeapons
	var weapon_control = get_weapon_control()
	if is_instance_valid(weapon_control):
		match hud_mode:
			HUDMode.GUN:
				for wt in weapon_control.weapon_types:
					if wt != "Bomb" and wt != "AAMissile" and wt != "Rocket Pod":
						weapon_control.selected_weapon_type = wt
						break
			HUDMode.ROCKETS:
				weapon_control.selected_weapon_type = "Rocket Pod"
			HUDMode.BOMBS:
				weapon_control.selected_weapon_type = "Bomb"
			_:
				pass

	# Update mode label
	if is_instance_valid(hud_mode_label):
		hud_mode_label.text = HUDMode.keys()[hud_mode]


func _sync_hud_mode_to_ai_weapon() -> void:
	# While this aircraft is AI-controlled, its pilot owns the weapon selection.
	# Keep the mode-specific symbology and label on that weapon instead of retaining
	# whichever HUD mode the spectator/player last selected.
	if not is_instance_valid(aircraft):
		return
	var ai_toggle: Node = aircraft.find_child("AIToggle", true, false)
	if ai_toggle == null or not bool(ai_toggle.get("ai_active")):
		return
	var weapon_control = get_weapon_control()
	if not is_instance_valid(weapon_control):
		return
	var selected_type: String = str(weapon_control.get("selected_weapon_type"))
	var desired_mode: HUDMode = HUDMode.NAV
	if selected_type == "Rocket Pod":
		desired_mode = HUDMode.ROCKETS
	elif selected_type == "Bomb":
		desired_mode = HUDMode.BOMBS
	elif not selected_type.is_empty() and selected_type != "AAMissile":
		desired_mode = HUDMode.GUN
	if hud_mode != desired_mode:
		hud_mode = desired_mode
		if is_instance_valid(hud_mode_label):
			hud_mode_label.text = HUDMode.keys()[hud_mode]

func _available_hud_modes() -> Array:
	var modes: Array = [HUDMode.NAV]
	var weapon_control = get_weapon_control()
	if not is_instance_valid(weapon_control):
		return modes
	var types: Array = weapon_control.weapon_types
	var has_gun := false
	for wt in types:
		if wt != "Bomb" and wt != "AAMissile" and wt != "Rocket Pod":
			has_gun = true
			break
	if has_gun:
		modes.append(HUDMode.GUN)
	if "Rocket Pod" in types:
		modes.append(HUDMode.ROCKETS)
	if "Bomb" in types:
		modes.append(HUDMode.BOMBS)
	return modes
