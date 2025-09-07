extends Node3D

@export var camera_path: NodePath
@export var aircraft_path: NodePath
@export var crosshair_color: Color = Color.GREEN
@export var hud_range: float = 10000.0
@export var hud_glass_size: Vector2 = Vector2(0.2, 0.2)  # 20x20 cm in meters

@onready var cam: Camera3D = get_node(camera_path) as Camera3D
@onready var aircraft: Node3D = get_node(aircraft_path) as Node3D
@onready var viewport: SubViewport = $SubViewport
@onready var reticle: Control = $SubViewport/Reticle
@onready var horizontal_line: ColorRect = $SubViewport/Reticle/HorizontalLine
@onready var vertical_line: ColorRect = $SubViewport/Reticle/VerticalLine
@onready var hud_mesh: MeshInstance3D = $HUDglass

func _ready():
	# Debug: Check what children exist
	print("All children of ", name, ":")
	for child in get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
	
	# Check each node reference
	print("HUD Mesh: ", hud_mesh)
	print("Viewport: ", viewport)
	print("Reticle: ", reticle)
	print("H-Line: ", horizontal_line)
	print("V-Line: ", vertical_line)
	
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
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.1)  # White with low alpha
	
	# Add viewport texture and emission
	material.albedo_texture = viewport.get_texture()
	material.emission_enabled = true
	material.emission_texture = viewport.get_texture()
	material.emission_energy = 3.0
	
	# Apply material
	hud_mesh.material_override = material
	
	print("Material created with transparency: ", material.transparency)
	
	# Set up viewport size - try much smaller resolution
	viewport.size = Vector2i(64, 64)  # Very small - should force stretching
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# Debug: Make viewport background visible
	viewport.transparent_bg = false  # Force opaque background
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLUE  # Blue background so we can see the viewport
	viewport.world_3d = World3D.new()
	viewport.world_3d.environment = env
	
	# Set up crosshair size - make them fill the tiny viewport
	reticle.size = Vector2(64, 64)  # Fill the entire 64x64 viewport
	reticle.pivot_offset = Vector2(32, 32)  # Center pivot
	reticle.position = Vector2(0, 0)  # Top-left of viewport
	
	# Make crosshair lines smaller and centered
	horizontal_line.size = Vector2(16, 2)  # Smaller horizontal line
	horizontal_line.position = Vector2(24, 31)  # Center it (32-8=24 for X, 32-1=31 for Y)
	
	vertical_line.size = Vector2(2, 16)  # Smaller vertical line
	vertical_line.position = Vector2(31, 24)  # Center it (32-1=31 for X, 32-8=24 for Y)
	
	# Set up crosshair colors - make them very obvious
	horizontal_line.color = Color.YELLOW  # Bright yellow
	vertical_line.color = Color.YELLOW
	
	print("Crosshair setup complete - should be yellow on red background")

func _process(dt: float) -> void:
	if cam == null or aircraft == null:
		return
	
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
	
	# Project to screen coordinates 
	var screen_pos: Vector2 = cam.unproject_position(nose_world)
	
	# Convert screen coordinates to HUD viewport coordinates
	# The HUD viewport is 64x64, so normalize and scale
	var main_viewport_size = get_viewport().size
	var normalized_pos = Vector2(
		screen_pos.x / main_viewport_size.x,
		screen_pos.y / main_viewport_size.y
	)
	
	# Scale to HUD viewport size and center the reticle
	var hud_pos = Vector2(
		normalized_pos.x * 64.0,
		normalized_pos.y * 64.0
	)
	
	# Only show if within reasonable bounds (with some margin)
	if hud_pos.x >= -10 and hud_pos.x <= 74 and hud_pos.y >= -10 and hud_pos.y <= 74:
		reticle.visible = true
		reticle.position = hud_pos - reticle.pivot_offset
	else:
		reticle.visible = false
	
