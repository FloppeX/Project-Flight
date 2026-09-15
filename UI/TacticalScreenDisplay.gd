class_name TacticalScreenDisplay
extends Node

## One shared, throttled tactical render target for every physical carrier
## computer. WorldMapOverlay moves into this viewport while the full console is
## closed, then returns to the main viewport when the player uses a station.

const VIEWPORT_SIZE := Vector2i(1024, 576)
## Lay out the desktop UI at a readable logical size, then downsample once.
## Increasing layout space does not increase the shared render texture cost.
const LAYOUT_SIZE := Vector2i(1600, 900)
const REFRESH_INTERVAL_S := 0.1

var _preview_viewport: SubViewport = null
var _screen_material: ShaderMaterial = null
var _world_map_overlay: Node = null
var _carrier_console: Node = null
var _refresh_accumulator_s: float = 0.0
var _preview_enabled: bool = true


func _ready() -> void:
	add_to_group("tactical_screen_display")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_preview_viewport()
	call_deferred("_bind_interfaces")


func _exit_tree() -> void:
	if is_instance_valid(_world_map_overlay) \
			and _world_map_overlay.has_method("clear_monitor_preview_viewport"):
		_world_map_overlay.call("clear_monitor_preview_viewport", _preview_viewport)


func _process(delta: float) -> void:
	if not _preview_enabled or _preview_viewport == null:
		return
	_refresh_accumulator_s += delta
	if _refresh_accumulator_s < REFRESH_INTERVAL_S:
		return
	_refresh_accumulator_s = fmod(_refresh_accumulator_s, REFRESH_INTERVAL_S)
	_request_preview_frame()


func get_screen_material(mesh_min: Vector2, mesh_max: Vector2) -> ShaderMaterial:
	_ensure_preview_viewport()
	if _preview_viewport == null:
		return null
	if _screen_material == null:
		_screen_material = _create_screen_material()
	_screen_material.set_shader_parameter("mesh_min", mesh_min)
	_screen_material.set_shader_parameter("mesh_max", mesh_max)
	return _screen_material


func get_debug_snapshot() -> Dictionary:
	return {
		"viewport_size": _preview_viewport.size if _preview_viewport != null else Vector2i.ZERO,
		"refresh_interval_s": REFRESH_INTERVAL_S,
		"preview_enabled": _preview_enabled,
		"has_world_map_overlay": is_instance_valid(_world_map_overlay),
		"has_carrier_console": is_instance_valid(_carrier_console),
		"has_screen_material": _screen_material != null,
	}


func _ensure_preview_viewport() -> void:
	if _preview_viewport != null:
		return
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "TacticalMonitorViewport"
	_preview_viewport.size = VIEWPORT_SIZE
	_preview_viewport.size_2d_override = LAYOUT_SIZE
	_preview_viewport.size_2d_override_stretch = true
	_preview_viewport.disable_3d = true
	_preview_viewport.transparent_bg = false
	_preview_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_preview_viewport)


func _bind_interfaces() -> void:
	_world_map_overlay = get_node_or_null("/root/WorldMapOverlay")
	_carrier_console = get_node_or_null("/root/CarrierConsole")
	if _world_map_overlay != null \
			and _world_map_overlay.has_method("set_monitor_preview_viewport"):
		_world_map_overlay.call("set_monitor_preview_viewport", _preview_viewport)
	if _carrier_console != null:
		var opened_callback := Callable(self, "_on_console_opened")
		var closed_callback := Callable(self, "_on_console_closed")
		if _carrier_console.has_signal("opened") \
				and not _carrier_console.is_connected("opened", opened_callback):
			_carrier_console.connect("opened", opened_callback)
		if _carrier_console.has_signal("closed") \
				and not _carrier_console.is_connected("closed", closed_callback):
			_carrier_console.connect("closed", closed_callback)
		if _carrier_console.has_method("is_open"):
			_preview_enabled = not bool(_carrier_console.call("is_open"))
	_request_preview_frame()


func _on_console_opened() -> void:
	_preview_enabled = false
	if _preview_viewport != null:
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _on_console_closed() -> void:
	_preview_enabled = true
	_refresh_accumulator_s = REFRESH_INTERVAL_S
	_request_preview_frame()


func _request_preview_frame() -> void:
	if not _preview_enabled or _preview_viewport == null:
		return
	if is_instance_valid(_world_map_overlay) \
			and _world_map_overlay.has_method("request_monitor_preview_refresh"):
		_world_map_overlay.call("request_monitor_preview_refresh", REFRESH_INTERVAL_S)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _create_screen_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tactical_texture : source_color, filter_linear;
uniform vec2 mesh_min = vec2(0.0);
uniform vec2 mesh_max = vec2(1.0);

varying vec2 screen_uv;

void vertex() {
	vec2 mesh_span = max(mesh_max - mesh_min, vec2(0.0001));
	vec2 mapped = clamp((VERTEX.xy - mesh_min) / mesh_span, vec2(0.0), vec2(1.0));
	screen_uv = vec2(mapped.x, 1.0 - mapped.y);
}

void fragment() {
	vec3 tactical_color = texture(tactical_texture, screen_uv).rgb;
	ALBEDO = tactical_color;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tactical_texture", _preview_viewport.get_texture())
	return material
