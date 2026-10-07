extends SubViewportContainer
## A decorative, isolated 3D logo. Never takes input or the menu's exterior camera.

const LOGO_SCENE: PackedScene = preload("res://Models/Branding/land_carrier_logo.glb")
const LOGO_SHADER: Shader = preload("res://UI/MenuLogo3D.gdshader")
const PALETTE_PATH := "res://Models/Branding/land_carrier_logo.json"
# Temporary Amiga-style title experiment. False restores the authored single face and sway.
const SPIN_EXPERIMENT := true
const HALF_TURN_SECONDS := 7.0
const FACE_HOLD_SECONDS := 1.8

var _viewport: SubViewport
var _pivot: Node3D
var _logo: Node3D
var _camera: Camera3D
var _bounds := AABB()
var _elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	stretch = true
	_viewport = SubViewport.new()
	_viewport.name = "LogoViewport"
	_viewport.size = Vector2i(size)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# Background colour alpha blends with the renderer's default clear colour.
	# Use opaque black to avoid bright MSAA fringes; transparent_bg above still
	# makes the viewport background transparent when composited into the menu.
	environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment_node.environment = environment
	_viewport.add_child(environment_node)

	_pivot = Node3D.new()
	_pivot.name = "LogoPivot"
	_viewport.add_child(_pivot)
	var scene := load("res://Models/Branding/land_carrier_logo_spin.glb") as PackedScene if SPIN_EXPERIMENT else LOGO_SCENE
	_logo = scene.instantiate() as Node3D
	_pivot.add_child(_logo)
	_configure_meshes()
	_logo.position -= _bounds.get_center()

	_camera = Camera3D.new()
	_camera.name = "LogoCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = Vector3(0.0, 0.0, 32.0)
	_camera.near = 0.1
	_camera.far = 64.0
	_viewport.add_child(_camera)
	_camera.current = true
	resized.connect(_fit_camera)
	_fit_camera()
	_apply_pose()
	_sync_visibility()


func _configure_meshes() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	var palettes: Dictionary = {}
	for entry: Dictionary in manifest.get("objects", []):
		palettes[String(entry["name"])] = entry["palette"]
	var first := true
	for child in _logo.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var bounds: AABB = _logo.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		_bounds = bounds if first else _bounds.merge(bounds)
		first = false
		var key := String(mesh.name).trim_suffix("_Rear")
		if not palettes.has(key):
			key = key.replace("_", " ")
		if not palettes.has(key):
			push_error("Menu logo has no exported palette for " + key)
			continue
		var palette: Array = palettes[key]
		var material := ShaderMaterial.new()
		material.shader = LOGO_SHADER
		for index in palette.size():
			var rgba: Array = palette[index]["color"]
			material.set_shader_parameter("tone_%d" % index, Vector4(rgba[0], rgba[1], rgba[2], rgba[3]))
		material.set_shader_parameter("thresholds", Vector3(
			palette[1]["position"], palette[2]["position"], palette[3]["position"]))
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _fit_camera() -> void:
	if not is_instance_valid(_camera) or size.y <= 0.0:
		return
	var aspect := maxf(size.x / size.y, 0.1)
	# Extra vertical room keeps all corners inside the viewport throughout the sway.
	_camera.size = maxf(_bounds.size.y * 1.30, _bounds.size.x / aspect * 1.10)


func _process(delta: float) -> void:
	_elapsed += delta
	_apply_pose()


func _apply_pose() -> void:
	if SPIN_EXPERIMENT:
		var half_turn := floorf(_elapsed / HALF_TURN_SECONDS)
		var phase := fmod(_elapsed, HALF_TURN_SECONDS)
		var progress := clampf((phase - FACE_HOLD_SECONDS) / (HALF_TURN_SECONDS - FACE_HOLD_SECONDS), 0.0, 1.0)
		var eased := progress * progress * (3.0 - 2.0 * progress)
		_pivot.rotation = Vector3(deg_to_rad(2.0 * sin(_elapsed * 0.7)), PI * (half_turn + eased), deg_to_rad(0.6 * sin(_elapsed * 0.45)))
		_pivot.position.y = 0.04 * sin(_elapsed * 0.40)
		return
	_pivot.rotation_degrees = Vector3(
		-2.5 + 1.7 * sin(_elapsed * 0.31),
		7.0 * sin(_elapsed * 0.27 + 0.4),
		0.35 * sin(_elapsed * 0.21))
	_pivot.position.y = 0.04 * sin(_elapsed * 0.40)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_instance_valid(_viewport):
		_sync_visibility()


func _sync_visibility() -> void:
	var active := is_visible_in_tree()
	set_process(active)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active else SubViewport.UPDATE_DISABLED
