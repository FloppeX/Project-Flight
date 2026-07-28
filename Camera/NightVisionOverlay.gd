extends CanvasLayer

var _enabled: bool = false
var _poly: Polygon2D = null
var _hud_glass: MeshInstance3D = null
var _cockpit_cam: Camera3D = null
var _aircraft: Node3D = null
var _instrument_panel: Node = null

func _ready() -> void:
	layer = 96
	visible = false

	_poly = Polygon2D.new()
	add_child(_poly)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://Shaders/nightvision.gdshader") as Shader
	_poly.material = mat

	await get_tree().process_frame

	var ctrl := get_parent()
	_cockpit_cam = ctrl.get("cockpit_camera") as Camera3D
	_aircraft = ctrl.get("aircraft") as Node3D
	if _aircraft != null:
		_hud_glass = _aircraft.find_child("HUDglass", true, false) as MeshInstance3D
	if _hud_glass == null:
		push_warning("[NightVision] HUDglass not found")
		queue_free()
		return

	_instrument_panel = _find_own_instrument_panel()


func _input(event: InputEvent) -> void:
	if not InputMap.has_action("toggle_nightvision"):
		return
	if event.is_action_pressed("toggle_nightvision") and _is_player_cockpit_view_active():
		_enabled = not _enabled
		_update_visibility()
		_apply_instrument_nv()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_update_visibility()
	if visible:
		_update_polygon()


func _update_visibility() -> void:
	var should_show := _enabled and _is_player_cockpit_view_active()
	if not should_show:
		visible = false
		return
	visible = true


func _is_player_cockpit_view_active() -> bool:
	if not is_instance_valid(_cockpit_cam):
		return false
	if int(get_parent().get("current_mode")) != 0:  # COCKPIT only
		return false
	return get_viewport().get_camera_3d() == _cockpit_cam


func _apply_instrument_nv() -> void:
	_instrument_panel = _find_own_instrument_panel()
	if _instrument_panel != null and _instrument_panel.has_method("set_nv_mode"):
		_instrument_panel.call("set_nv_mode", _enabled)


func _find_own_instrument_panel() -> Node:
	if not is_instance_valid(_aircraft):
		return null
	var panel := _aircraft.find_child("InstrumentPanel", true, false)
	if panel != null:
		return panel
	for candidate in get_tree().get_nodes_in_group("instrument_panel"):
		if candidate is Node and _node_is_same_or_descendant(candidate, _aircraft):
			return candidate as Node
	return null


func _node_is_same_or_descendant(node: Node, ancestor: Node) -> bool:
	var current: Node = node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _update_polygon() -> void:
	if _hud_glass == null or _cockpit_cam == null:
		return

	var quad_mesh := _hud_glass.mesh as QuadMesh
	var half_size := (quad_mesh.size if quad_mesh != null else Vector2(0.4, 0.4)) * 0.5

	var proj := _cockpit_cam.get_camera_projection()
	var cam_transform := _cockpit_cam.get_global_transform_interpolated()
	var hud_transform := _hud_glass.get_global_transform_interpolated()
	var cam_inv := cam_transform.affine_inverse()
	var vp_size := get_viewport().get_visible_rect().size

	var pts := PackedVector2Array()
	pts.resize(4)
	for i in 4:
		var lx: float = -half_size.x if i < 2 else half_size.x
		var ly: float = half_size.y if (i == 0 or i == 3) else -half_size.y
		var world_pos: Vector3 = hud_transform * Vector3(lx, ly, 0.0)
		var view_pos: Vector3 = cam_inv * world_pos
		if view_pos.z > 0.0:
			visible = false
			return
		var clip: Vector4 = proj * Vector4(view_pos.x, view_pos.y, view_pos.z, 1.0)
		if clip.w <= 0.0:
			visible = false
			return
		pts[i] = Vector2(
			(clip.x / clip.w + 1.0) * 0.5 * vp_size.x,
			(1.0 - clip.y / clip.w) * 0.5 * vp_size.y
		)

	_poly.polygon = pts


func _exit_tree() -> void:
	pass
