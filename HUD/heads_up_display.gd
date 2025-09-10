extends Node3D

@export var camera_path: NodePath
@export var aircraft_path: NodePath
@export var crosshair_color: Color = Color.GREEN
@export var hud_range: float = 10000.0
@export var hud_glass_size: Vector2 = Vector2(0.4, 0.4)  # 40x40 cm in meters - bigger for more text room

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
		print("ERROR: HUDglass node not found!")
		return
	if viewport == null:
		print("ERROR: SubViewport node not found!")
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
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.3)  # White with some transparency
	
	# Add viewport texture and emission
	material.albedo_texture = viewport.get_texture()
	material.emission_enabled = true
	material.emission_texture = viewport.get_texture()
	material.emission_energy = 10.0  # Much higher emission for brightness
	
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
	var line_thickness: float = 2.0
	horizontal_line.size = Vector2(line_len, line_thickness)
	horizontal_line.position = reticle.pivot_offset - Vector2(line_len * 0.5, line_thickness * 0.5)
	
	vertical_line.size = Vector2(line_thickness, line_len)
	vertical_line.position = reticle.pivot_offset - Vector2(line_thickness * 0.5, line_len * 0.5)
	
	# Set up crosshair colors - maximum brightness green
	horizontal_line.color = Color(0, 10.0, 0, 1.0)  # Maximum brightness green
	vertical_line.color = Color(0, 10.0, 0, 1.0)  # Maximum brightness green
	
	# Set up weapon status display
	setup_weapon_status()
	
	# Set up speed and altitude display
	setup_speed_altitude()
	
	# Set up CCIP elements
	setup_ccip()

func setup_weapon_status():
	"""Set up the weapon status display in lower left corner"""
	if weapon_status == null:
		print("ERROR: WeaponStatus label not found!")
		return
	
	# Position in lower left corner - move more towards the edge
	var hud_size: Vector2 = Vector2(viewport.size)
	weapon_status.position = Vector2(5, hud_size.y - 60)
	weapon_status.size = Vector2(300, 50)
	
	# Style the text - make it more opaque and larger
	weapon_status.text = "No Weapons"
	weapon_status.add_theme_color_override("font_color", Color(0, 10.0, 0, 1.0))  # Maximum brightness green
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
		print("ERROR: SpeedAltitude label not found!")
		return
	
	# Position in lower right corner - move more towards the edge
	var hud_size: Vector2 = Vector2(viewport.size)
	speed_altitude.position = Vector2(hud_size.x - 200, hud_size.y - 60)
	speed_altitude.size = Vector2(190, 50)
	
	# Style the text - make it more opaque and larger
	speed_altitude.text = "SPD: 0\nALT: 0"
	speed_altitude.add_theme_color_override("font_color", Color(0, 10.0, 0, 1.0))  # Maximum brightness green
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
	var circle_color = Color(0, 10.0, 0, 1.0)
	var line_thickness = 2.0
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
	ccip_dot.color = Color(0, 10.0, 0, 1.0)  # Maximum brightness green
	ccip_dot.size = Vector2(4, 4)  # 4px dot
	ccip_dot.visible = false
	viewport.add_child(ccip_dot)

func _process(dt: float) -> void:
	if cam == null or aircraft == null:
		print("HUD: Missing camera or aircraft reference")
		return
	
	# Update weapon status display
	update_weapon_status()
	
	# Update speed and altitude display
	update_speed_altitude()
	
	# Update CCIP display
	update_ccip()
	
	# Get aircraft's forward direction (nose pointing direction)
	# In Godot, -Z is forward for most objects
	var aircraft_forward: Vector3 = -aircraft.global_transform.basis.z
	
	# Project aircraft's nose direction to infinity for proper collimation
	# This makes the crosshair appear at the same point regardless of head movement
	var nose_world: Vector3 = aircraft.global_transform.origin + aircraft_forward * hud_range
	
	# Convert to camera's local space to check if it's in front
	var nose_local = cam.global_transform.inverse() * nose_world
	if nose_local.z > 0:  # Behind camera in local space
		reticle.visible = false
		return
	
	# Project to screen coordinates (world → screen)
	var screen_pos: Vector2 = cam.unproject_position(nose_world)
	
	# Convert screen coordinates to HUD viewport coordinates using actual sizes
	var main_viewport_size = get_viewport().size
	var hud_size_px: Vector2 = Vector2(viewport.size)
	var normalized_pos = Vector2(
		screen_pos.x / max(main_viewport_size.x, 0.001),
		screen_pos.y / max(main_viewport_size.y, 0.001)
	)
	var hud_pos = Vector2(
		normalized_pos.x * hud_size_px.x,
		normalized_pos.y * hud_size_px.y
	)
	
	# Only show if within reasonable bounds (with some margin)
	if hud_pos.x >= -10 and hud_pos.x <= (hud_size_px.x + 10) and hud_pos.y >= -10 and hud_pos.y <= (hud_size_px.y + 10):
		reticle.visible = true
		reticle.position = hud_pos - reticle.pivot_offset
	else:
		reticle.visible = false

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
	
	# Convert impact point to screen coordinates
	var impact_world = ccip_data.impact_position
	var impact_local = cam.global_transform.inverse() * impact_world
	
	if impact_local.z > 0:  # Behind camera
		ccip_circle.visible = false
		ccip_dot.visible = false
		return
	
	# Project to screen coordinates
	var screen_pos = cam.unproject_position(impact_world)
	
	# Convert to HUD viewport coordinates
	var main_viewport_size = get_viewport().size
	var hud_size_px = Vector2(viewport.size)
	var normalized_pos = Vector2(
		screen_pos.x / max(main_viewport_size.x, 0.001),
		screen_pos.y / max(main_viewport_size.y, 0.001)
	)
	var hud_pos = Vector2(
		normalized_pos.x * hud_size_px.x,
		normalized_pos.y * hud_size_px.y
	)
	
	# Only show if within HUD bounds
	if (hud_pos.x >= 0 and hud_pos.x <= hud_size_px.x and 
		hud_pos.y >= 0 and hud_pos.y <= hud_size_px.y):
		ccip_circle.visible = true
		ccip_dot.visible = true
		
		# Position circle and dot at impact point
		ccip_circle.position = hud_pos - ccip_circle.size * 0.5
		# Center the dot precisely in the middle of the circle
		var circle_center = ccip_circle.position + ccip_circle.size * 0.5
		ccip_dot.position = circle_center - ccip_dot.size * 0.5
	else:
		ccip_circle.visible = false
		ccip_dot.visible = false

func get_weapon_control():
	"""Get the weapon control module"""
	# Try to find the weapon control module
	var weapon_control = null
	
	# Look for ControlWeapons in the aircraft
	if aircraft and aircraft.has_method("get_children"):
		for child in aircraft.get_children():
			if child is ControlWeapons:
				weapon_control = child
				break
			# Also check children of children
			for grandchild in child.get_children():
				if grandchild is ControlWeapons:
					weapon_control = grandchild
					break
	
	# If not found, try searching by group
	if not weapon_control:
		var weapon_controls = get_tree().get_nodes_in_group("ControlWeapons")
		if weapon_controls.size() > 0:
			weapon_control = weapon_controls[0]
	
	return weapon_control
