@tool
extends Decal

## Rectangular ship-name placer. Local -Y projects into the hull; -Z is text UP
## and +X is text RIGHT, matching InsigniaMarker. Move/rotate the entire node.
## The translucent box is editor-only. The lettering is a real surface decal.
@export var width: float = 18.0:
	set(value):
		width = maxf(value, 0.01)
		_refresh()
@export var height: float = 2.5:
	set(value):
		height = maxf(value, 0.01)
		_refresh()
@export var depth: float = 4.0:
	set(value):
		depth = maxf(value, 0.01)
		_refresh()
## Empty uses the carrier's campaign name. Also available for an authored name.
@export var text_override: String = "":
	set(value):
		text_override = value
		_refresh()
@export var preview_name: String = "LAND CARRIER":
	set(value):
		preview_name = value
		_refresh()
@export var text_color: Color = Color(0.92, 0.92, 0.85):
	set(value):
		text_color = value
		_refresh()

const FONT = preload("res://UI/Fonts/ArchivoNarrow-Variable.ttf")
var _viewport: SubViewport
var _label: Label
var _volume: MeshInstance3D
var _preview_label: Label3D
var _signature := ""
var _bake_queued := false

func _ready() -> void:
	upper_fade = 0.0
	lower_fade = 0.0
	sorting_offset = 11.0
	albedo_mix = 1.0
	call_deferred("refresh_ship_name")

func get_ship_name_text() -> String:
	if not text_override.strip_edges().is_empty():
		return text_override.strip_edges()
	if not Engine.is_editor_hint():
		var ancestor := get_parent()
		while ancestor != null:
			if ancestor.has_meta("carrier_display_name"):
				return str(ancestor.get_meta("carrier_display_name"))
			ancestor = ancestor.get_parent()
		var session := get_node_or_null("/root/GameSession")
		if session != null:
			return str(session.get("carrier_name"))
	return preview_name

## Called after campaign naming/livery changes. No per-frame text rendering.
func refresh_ship_name() -> void:
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	size = Vector3(width, depth, height)
	modulate = text_color
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "_NameTexture"
		_viewport.disable_3d = true
		_viewport.transparent_bg = true
		_viewport.gui_disable_input = true
		add_child(_viewport)
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_override("font", FONT)
		_label.add_theme_color_override("font_color", Color.WHITE)
		_viewport.add_child(_label)
	var text := get_ship_name_text()
	var texture_size := Vector2i(1024, clampi(roundi(1024.0 * height / width), 64, 1024))
	var signature := "%s|%s" % [text, texture_size]
	if signature != _signature:
		_signature = signature
		_viewport.size = texture_size
		_label.text = text
		var font_size := maxi(int(texture_size.y * 0.78), 1)
		var measured := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if measured > texture_size.x * 0.94:
			font_size = maxi(int(font_size * texture_size.x * 0.94 / measured), 1)
		_label.add_theme_font_size_override("font_size", font_size)
		_label.size = Vector2(texture_size)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		if not _bake_queued and DisplayServer.get_name() != "headless":
			_bake_queued = true
			call_deferred("_bake_texture")
	if Engine.is_editor_hint():
		if _volume == null:
			_volume = MeshInstance3D.new()
			_volume.name = "_PlacementVolume"
			_volume.set_meta("_edit_lock_", true)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.2, 0.8, 1.0, 0.16)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_volume.material_override = material
			_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_volume)
		var box := BoxMesh.new()
		box.size = size
		_volume.mesh = box
		if _preview_label == null:
			_preview_label = Label3D.new()
			_preview_label.name = "_ReadingDirection"
			_preview_label.font = FONT
			_preview_label.font_size = 64
			_preview_label.outline_size = 0
			_preview_label.no_depth_test = true
			_preview_label.rotation.x = -PI * 0.5
			_preview_label.set_meta("_edit_lock_", true)
			add_child(_preview_label)
		_preview_label.text = text
		_preview_label.modulate = text_color
		_preview_label.position.y = depth * 0.5 + 0.02
		_preview_label.pixel_size = minf(width * 0.94 / maxf(FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x, 1.0), height * 0.78 / FONT.get_height(64))

func _bake_texture() -> void:
	# Decals use an atlas and cannot sample a ViewportTexture directly. Bake only
	# on text/size changes, then keep a static mipmapped texture during gameplay.
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_viewport):
		return
	var image := _viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		image.generate_mipmaps()
		texture_albedo = ImageTexture.create_from_image(image)
	_bake_queued = false
