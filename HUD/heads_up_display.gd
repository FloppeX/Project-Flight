extends Node3D
# HeadsUpDisplay.gd

@export var camera_path: NodePath
@export var aircraft_path: NodePath
@export var crosshair_color: Color = Color.GREEN
@export var hud_range: float = 10000.0
@export var hud_glass_size: Vector2 = Vector2(0.20, 0.20) # 20×20 cm combiner

@onready var cam: Camera3D = get_node(camera_path) as Camera3D
@onready var aircraft: Node3D = get_node(aircraft_path) as Node3D
@onready var subvp: SubViewport = $SubViewport
@onready var reticle: Control = $SubViewport/Reticle
@onready var horizontal_line: ColorRect = $SubViewport/Reticle/HorizontalLine
@onready var vertical_line: ColorRect = $SubViewport/Reticle/VerticalLine
@onready var hud_mesh: MeshInstance3D = $"HUD glass"   # << matches your scene name

func _ready() -> void:
	# Mesh
	var quad := QuadMesh.new()
	quad.size = hud_glass_size
	$"HUD glass".mesh = quad

	# SubViewport (2D, always updating)
	var sv := $SubViewport
	sv.size = Vector2i(256, 256)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	sv.clear_mode = SubViewport.CLEAR_MODE_ALWAYS

	# Fill SubViewport so you can see it on the glass
	var bg := ColorRect.new()
	bg.color = Color(0, 1, 0, 1)	# bright green
	bg.anchors_preset = Control.PRESET_FULL_RECT
	sv.add_child(bg)

	# Material uses the SubViewport texture
	var mat := StandardMaterial3D.new()
	mat.flags_unshaded = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_texture = sv.get_texture()
	mat.emission_enabled = true
	mat.emission_texture = sv.get_texture()
	mat.no_depth_test = true
	# (Optional: crisp sampling)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	$"HUD glass".material_override = mat



func _process(_dt: float) -> void:
	if cam == null or aircraft == null:
		return

	# Project a far point along the aircraft’s forward vector (collimated/“infinite”)
	var fwd: Vector3 = -aircraft.global_transform.basis.z
	var nose_world: Vector3 = aircraft.global_transform.origin + fwd * hud_range

	if cam.is_position_behind(nose_world):
		reticle.visible = false
		return

	# Screen position in MAIN viewport pixels
	var screen_pos: Vector2 = cam.unproject_position(nose_world)

	# Convert to SubViewport pixel space
	var main_size: Vector2 = get_viewport().size
	var sub_size: Vector2 = Vector2(subvp.size)
	var uv := Vector2(screen_pos.x / max(main_size.x, 1.0), screen_pos.y / max(main_size.y, 1.0))
	var sub_px := Vector2(uv.x * sub_size.x, uv.y * sub_size.y)

	reticle.visible = true
	reticle.position = sub_px - reticle.pivot_offset
