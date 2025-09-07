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
@onready var hud_mesh: MeshInstance3D = $HUDGlass

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
		print("ERROR: HUDGlass node not found!")
		return
	if viewport == null:
		print("ERROR: SubViewport node not found!")
		return
	
	# Set up the HUD glass mesh
	var quad = QuadMesh.new()
	quad.size = hud_glass_size
	hud_mesh.mesh = quad
	
	# Create material for the HUD glass - match manual inspector setup
	var material = StandardMaterial3D.new()
	
	# Basic transparency setup (matching inspector)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_transparent = true
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
	print("Material flags_transparent: ", material.flags_transparent)
	
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
	
	# Make crosshair lines fill most of the viewport
	horizontal_line.size = Vector2(50, 4)  # Most of viewport width
	horizontal_line.position = Vector2(7, 30)  # Center it
	
	vertical_line.size = Vector2(4, 50)  # Most of viewport height
	vertical_line.position = Vector2(30, 7)  # Center it
	
	# Set up crosshair colors - make them very obvious
	horizontal_line.color = Color.YELLOW  # Bright yellow
	vertical_line.color = Color.YELLOW
	
	print("Crosshair setup complete - should be yellow on red background")

func _process(dt: float) -> void:
	if cam == null or aircraft == null:
		return
	
	# Aircraft forward in Godot: -Z
	var fwd: Vector3 = -aircraft.global_transform.basis.z
	var nose_world: Vector3 = aircraft.global_transform.origin + fwd * hud_range
	
	# Hide if the target point is behind the camera
	if cam.is_position_behind(nose_world):
		reticle.visible = false
		return
	
	# Project to screen coordinates and convert to viewport coordinates
	var screen_pos: Vector2 = cam.unproject_position(nose_world)
	
	# Convert screen coordinates to viewport coordinates (0-64 range)
	var viewport_size = get_viewport().size
	var viewport_pos = Vector2(
		(screen_pos.x / viewport_size.x) * 64,
		(screen_pos.y / viewport_size.y) * 64
	)
	
	reticle.visible = true
	reticle.position = viewport_pos - reticle.pivot_offset
