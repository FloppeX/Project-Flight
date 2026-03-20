extends Node3D

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

var cam: Camera3D
var aircraft: Node3D
@onready var viewport: SubViewport = $SubViewport
@onready var reticle: Control = $SubViewport/Reticle
@onready var horizontal_line: ColorRect = $SubViewport/Reticle/HorizontalLine
@onready var vertical_line: ColorRect = $SubViewport/Reticle/VerticalLine
@onready var hud_mesh: MeshInstance3D = $HUDglass
@onready var weapon_status: Label = $SubViewport/WeaponStatus
@onready var speed_altitude: Label = $SubViewport/SpeedAltitude

# CCIP elements
var ccip_circle: Control
var ccip_dot: ColorRect
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

func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)

func _ready():
	# Manually resolve NodePath references
	if camera_path != NodePath():
		var camera_node = get_node(camera_path)
		# Try to find a Camera3D within the camera node
		if camera_node:
			cam = camera_node.get_node("Camera3D") as Camera3D
			if not cam:
				# Try to find any Camera3D in the scene
				cam = get_tree().get_first_node_in_group("camera") as Camera3D
	
	if aircraft_path != NodePath():
		aircraft = get_node(aircraft_path) as Node3D
	
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
	"""Set up the speed and altitude display in lower right corner"""
	if speed_altitude == null:
		push_error("HUD: SpeedAltitude label not found!")
		return
	
	# Position in lower right corner - move more towards the edge
	var hud_size: Vector2 = Vector2(viewport.size)
	speed_altitude.position = Vector2(hud_size.x - 200, hud_size.y - 60)
	speed_altitude.size = Vector2(190, 50)
	
	# Style the text - make it more opaque and larger
	speed_altitude.text = "SPD: 0\nALT: 0"
	speed_altitude.add_theme_color_override("font_color", _opaque(hud_primary_color))
	speed_altitude.add_theme_color_override("font_outline_color", Color.BLACK)
	speed_altitude.add_theme_constant_override("outline_size", hud_text_outline_size)
	speed_altitude.add_theme_font_size_override("font_size", 18)
	
	# Add background for better visibility
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.0)  # Completely transparent background
	style_box.corner_radius_top_left = 5
	style_box.corner_radius_top_right = 5
	style_box.corner_radius_bottom_left = 5
	style_box.corner_radius_bottom_right = 5
	speed_altitude.add_theme_stylebox_override("normal", style_box)

func setup_ccip():
	"""Set up CCIP visual elements"""
	# Create CCIP circle container
	ccip_circle = Control.new()
	ccip_circle.size = Vector2(32, 32)  # 32px container
	ccip_circle.visible = false
	viewport.add_child(ccip_circle)
	
	# Create circle outline using 4 ColorRect segments (top, bottom, left, right)
	var circle_color: Color = _opaque(hud_primary_color)
	var line_thickness: float = hud_line_thickness_px
	var radius = 14.0
	
	# Top arc (approximate with rectangle)
	var top_line = ColorRect.new()
	top_line.color = circle_color
	top_line.size = Vector2(radius * 1.4, line_thickness)  # Approximate arc width
	top_line.position = Vector2(radius * 0.3, 0)
	ccip_circle.add_child(top_line)
	
	# Bottom arc
	var bottom_line = ColorRect.new()
	bottom_line.color = circle_color
	bottom_line.size = Vector2(radius * 1.4, line_thickness)
	bottom_line.position = Vector2(radius * 0.3, radius * 2 - line_thickness)
	ccip_circle.add_child(bottom_line)
	
	# Left arc
	var left_line = ColorRect.new()
	left_line.color = circle_color
	left_line.size = Vector2(line_thickness, radius * 1.4)
	left_line.position = Vector2(0, radius * 0.3)
	ccip_circle.add_child(left_line)
	
	# Right arc
	var right_line = ColorRect.new()
	right_line.color = circle_color
	right_line.size = Vector2(line_thickness, radius * 1.4)
	right_line.position = Vector2(radius * 2 - line_thickness, radius * 0.3)
	ccip_circle.add_child(right_line)
	
	# Create CCIP dot (center)
	ccip_dot = ColorRect.new()
	ccip_dot.color = _opaque(hud_primary_color)
	ccip_dot.size = Vector2(6, 6)
	ccip_dot.visible = false
	viewport.add_child(ccip_dot)

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
	if cam == null or aircraft == null:
		return
	
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

	reticle.visible = true
	reticle.position = (hud_projection.get("hud_pos", Vector2.ZERO) as Vector2) - reticle.pivot_offset

func _project_world_to_hud(world_pos: Vector3) -> Dictionary:
	if not is_instance_valid(cam) or not is_instance_valid(hud_mesh):
		return {"visible": false}
	if cam.is_position_behind(world_pos):
		return {"visible": false}

	var camera_pos: Vector3 = cam.global_position
	var ray_direction: Vector3 = (world_pos - camera_pos).normalized()
	if ray_direction.length_squared() < 0.000001:
		return {"visible": false}

	var hud_transform: Transform3D = hud_mesh.global_transform
	var hud_normal: Vector3 = -hud_transform.basis.z.normalized()
	var hud_plane := Plane(hud_normal, hud_transform.origin)
	var intersection_point = hud_plane.intersects_ray(camera_pos, ray_direction)
	if intersection_point == null:
		return {"visible": false}

	var local_point: Vector3 = hud_mesh.to_local(intersection_point)
	var half_size: Vector2 = hud_glass_size * 0.5
	if abs(local_point.x) > half_size.x or abs(local_point.y) > half_size.y:
		return {"visible": false}

	var hud_size_px := Vector2(viewport.size)
	var hud_pos := Vector2(
		(local_point.x + half_size.x) / max(hud_glass_size.x, 0.001) * hud_size_px.x,
		(-local_point.y + half_size.y) / max(hud_glass_size.y, 0.001) * hud_size_px.y
	)
	return {
		"visible": true,
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
	"""Update the speed and altitude display"""
	if speed_altitude == null or aircraft == null:
		return
	
	# Get aircraft velocity and position
	var velocity = aircraft.linear_velocity
	var speed = velocity.length()
	var altitude = aircraft.global_position.y
	
	# Format the display
	speed_altitude.text = "SPD: " + str(int(speed)) + "\nALT: " + str(int(altitude))

func update_ccip():
	"""Update CCIP display - only show when bombs are selected"""
	if ccip_circle == null or ccip_dot == null or aircraft == null or cam == null:
		return
	
	# Check if bombs are currently selected
	var weapon_control = get_weapon_control()
	var bombs_selected = false
	
	if weapon_control and weapon_control.has_method("get_weapon_status"):
		var status = weapon_control.get_weapon_status()
		var selected_type = status.get("selected_type", "")
		bombs_selected = (selected_type == "Bomb")
	
	if not bombs_selected:
		ccip_circle.visible = false
		ccip_dot.visible = false
		return
	
	# Calculate CCIP impact point
	var ccip_data = aircraft.calculate_ccip_impact_point()
	
	if not ccip_data.has_impact:
		ccip_circle.visible = false
		ccip_dot.visible = false
		return
	
	var impact_world: Vector3 = ccip_data.impact_position

	# --- Replicate working projection logic from target box ---
	var hud_projection: Dictionary = _project_world_to_hud(impact_world)
	if not bool(hud_projection.get("visible", false)):
		ccip_circle.visible = false
		ccip_dot.visible = false
		return

	var hud_size_px := Vector2(viewport.size)
	var hud_pos := hud_projection.get("hud_pos", Vector2.ZERO) as Vector2

	# Optional filter: hide CCIP if above approximate horizon (screen center)
	if ccip_below_horizon_only and hud_pos.y < (hud_size_px.y * 0.5 - 4.0):
		ccip_circle.visible = false
		ccip_dot.visible = false
		return
	
	ccip_circle.visible = true
	ccip_dot.visible = true
	
	# Position circle and dot at impact point
	ccip_circle.position = hud_pos - ccip_circle.size * 0.5
	# Center the dot precisely in the middle of the circle
	var circle_center = ccip_circle.position + ccip_circle.size * 0.5
	ccip_dot.position = circle_center - ccip_dot.size * 0.5

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

func update_target_overlay():
	"""Update the green target box overlay when target is visible in HUD"""
	# Ensure all required nodes are valid before proceeding
	var required_nodes = [target_overlay, cam, aircraft, hud_mesh]
	for node in required_nodes:
		if not is_instance_valid(node):
			_set_target_box_visible(false)
			return

	# Get current target from the targeting system
	var targeting_system = get_targeting_system()
	var target: Node3D = null
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
	# Re-resolve the cockpit camera so the reticle projects correctly for this plane
	var cockpit_tripod := new_aircraft.get_node_or_null("CameraCockpit") as Node3D
	if cockpit_tripod:
		var cockpit_cam := cockpit_tripod.find_child("Camera3D", true, false) as Camera3D
		if cockpit_cam:
			cam = cockpit_cam

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
	var shooter_pos: Vector3 = aircraft.global_position
	var shooter_vel: Vector3 = Vector3.ZERO
	if "linear_velocity" in aircraft:
		shooter_vel = aircraft.linear_velocity

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
	"""Return the muzzle velocity of the first autocannon found on the aircraft."""
	var weapon_control = get_weapon_control()
	if not is_instance_valid(weapon_control):
		return 0.0
	if not "hardpoints" in weapon_control:
		return 0.0
	for hp in weapon_control.hardpoints:
		if not hp or not hp.weapon_instance:
			continue
		if hp.weapon_instance.weapon_name == "Autocannon" and "muzzle_velocity" in hp.weapon_instance:
			return float(hp.weapon_instance.muzzle_velocity)
	return 0.0

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
