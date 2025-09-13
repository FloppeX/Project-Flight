extends Node3D

@export var cable_area_path: NodePath
@export var left_anchor_path: NodePath
@export var right_anchor_path: NodePath
@export var deck_direction: Vector3 = Vector3(0, 0, -1) # along landing axis (normalized at _ready)
@export var max_tension: float = 80000.0 # N (force cap)
@export var linear_k: float = 5000.0      # spring-like proportional to extension
@export var linear_c: float = 30000.0     # damping proportional to velocity along cable (higher = more damping)
@export var max_pay_out: float = 25.0     # meters of give before hard stop (higher = more play)
@export var auto_release_speed: float = 2.0 # m/s
@export var lateral_k: float = 1500.0        # gentle centering spring across deck (N/m)
@export var lateral_c: float = 5000.0        # lateral damping (N*s/m)
@export var force_smoothing: float = 0.15    # seconds to smooth force changes
@export var visualize_cable: bool = true      # draw a simple cable visualization
@export var cable_radius: float = 0.05
@export var band_length_m: float = 0.5        # physical band length (meters) for stripes
@export var band_color_a: Color = Color(0, 0, 0, 1)     # black
@export var band_color_b: Color = Color(1, 1, 1, 1)     # white

var _area: Area3D
var _left_anchor: Node3D
var _right_anchor: Node3D
var _engaged := false
var _aircraft: RigidBody3D
var _hook_node: Node
var _engage_point: Vector3
var _pay_out_used: float = 0.0
var _debug_t: float = 0.0
var _engaged_elapsed: float = 0.0
var _force_along_prev: float = 0.0
var _seg_left: MeshInstance3D
var _seg_right: MeshInstance3D
var _seg_rest: MeshInstance3D
var _mat_left: ShaderMaterial
var _mat_right: ShaderMaterial
var _mat_rest: ShaderMaterial
var _gear_module: Node = null
var _orig_sideways_friction: float = NAN
var _orig_friction_multiplier: float = NAN

func _ready():
	_area = get_node_or_null(cable_area_path) as Area3D
	_left_anchor = get_node_or_null(left_anchor_path) as Node3D
	_right_anchor = get_node_or_null(right_anchor_path) as Node3D
	if _area:
		_area.area_entered.connect(_on_area_entered)
		_area.area_exited.connect(_on_area_exited)
	else:
		print("[Cable] WARNING: cable_area_path not set")
	if not _left_anchor or not _right_anchor:
		print("[Cable] WARNING: anchor paths not set")
	if deck_direction.length() == 0:
		deck_direction = Vector3(0,0,-1)
	deck_direction = deck_direction.normalized()

	if visualize_cable:
		_create_cable_visuals()

func _physics_process(delta: float) -> void:
	if not _engaged or not is_instance_valid(_aircraft):
		return
	_engaged_elapsed += delta
	# Project velocity along deck direction
	var v = _aircraft.linear_velocity
	# Prefer live axis from anchors if available
	# Braking axis in world space derived from carrier orientation
	var axis = (global_transform.basis * deck_direction).normalized()
	var v_along = v.dot(axis)
	# Estimate extension along deck axis from engage point to current hook pos
	var hook_pos = _hook_global_position()
	var anchor_mid = _anchor_midpoint()
	var rel = hook_pos - anchor_mid
	var x = rel.dot(axis) # signed extension from midline
	# Resist motion in direction of travel; spring toward midline
	var spring_term = linear_k * min(abs(x), max_pay_out)
	var sign_v = 1.0 if v_along >= 0.0 else -1.0
	var force_along_target = -(linear_c * v_along + spring_term * sign_v)
	# Smooth force to reduce oscillations
	var alpha = clamp(delta / max(force_smoothing, 0.001), 0.0, 1.0)
	var force_along = lerp(_force_along_prev, force_along_target, alpha)
	force_along = clamp(force_along, -max_tension, max_tension)
	var force_vec = axis * force_along
	# Apply force at hook contact point to avoid destabilizing torque
	var apply_at = hook_pos - _aircraft.global_position
	_aircraft.apply_force(force_vec, apply_at)
	_force_along_prev = force_along

	# Lateral centering toward the cable line: vector form, not fixed X
	var lateral_rel = rel - axis * rel.dot(axis)            # component from midline to hook, across deck
	var v_lat_vec = v - axis * v_along                      # aircraft velocity component across deck
	var f_lat_vec = -(lateral_k * lateral_rel + lateral_c * v_lat_vec)
	var f_lat_limit = max_tension * 0.25
	if f_lat_vec.length() > f_lat_limit:
		f_lat_vec = f_lat_vec.normalized() * f_lat_limit
	_aircraft.apply_force(f_lat_vec, apply_at)

	# Update visuals
	if visualize_cable:
		_update_cable_visuals(hook_pos)

	# Periodic debug
	_debug_t += delta
	if _debug_t >= 0.5:
		_debug_t = 0.0
		print("[Cable] engaged: x=", x, " v_along=", v_along, " F=", force_along)
	# Auto release when nearly stopped
	if _engaged_elapsed > 0.3 and v.length() < auto_release_speed and abs(x) < 1.0:
		print("[Cable] RELEASE by speed: v=", v.length(), " x=", x)
		_release()

func _on_area_entered(area: Area3D) -> void:
	if _engaged:
		return
	# Expect tailhook HookArea to be an Area3D; accept by group or name
	if area.is_in_group("tailhook") or area.name.to_lower().find("hook") != -1:
		print("[Cable] ENTER by ", area.name, " groups=", area.get_groups())
		var ac = _find_aircraft(area)
		if ac:
			_aircraft = ac
			# Interlock: only one cable can engage a given aircraft at a time
			if _aircraft.has_meta("arresting_engaged") and _aircraft.get_meta("arresting_engaged") == true:
				print("[Cable] SKIP engage: aircraft already engaged by another cable")
				_aircraft = null
				return
			_aircraft.set_meta("arresting_engaged", true)
			_hook_node = area
			_engage_point = area.global_position
			_pay_out_used = 0.0
			_engaged = true
			print("[Cable] ENGAGED with ", _aircraft.name)
			# Soften landing gear lateral grip while cable is engaged to prevent tipping
			_gear_module = _aircraft.find_child("LandingGear", true, false)
			if _gear_module:
				var sf = _gear_module.get("sideways_friction")
				if sf != null:
					_orig_sideways_friction = float(sf)
					_gear_module.set("sideways_friction", max(1.0, _orig_sideways_friction * 0.35))
				var fm = _gear_module.get("friction_force_multiplier")
				if fm != null:
					_orig_friction_multiplier = float(fm)
					_gear_module.set("friction_force_multiplier", max(200.0, _orig_friction_multiplier * 0.5))

func _on_area_exited(area: Area3D) -> void:
	if area == _hook_node:
		print("[Cable] EXIT by ", area.name, " (ignoring; remain engaged until slow or manual release)")

func _release():
	_engaged = false
	if _aircraft and _aircraft.has_meta("arresting_engaged"):
		_aircraft.set_meta("arresting_engaged", false)
	_aircraft = null
	_hook_node = null
	print("[Cable] RELEASED")
	if visualize_cable:
		# Return to straight cable between anchors
		_update_cable_visuals(Vector3.INF)
	# Restore landing gear friction settings
	if _gear_module:
		if not is_nan(_orig_sideways_friction) and _gear_module.get("sideways_friction") != null:
			_gear_module.set("sideways_friction", _orig_sideways_friction)
		if not is_nan(_orig_friction_multiplier) and _gear_module.get("friction_force_multiplier") != null:
			_gear_module.set("friction_force_multiplier", _orig_friction_multiplier)
		_gear_module = null

func _find_aircraft(from_node: Node) -> RigidBody3D:
	var n: Node = from_node
	while n:
		if n is RigidBody3D:
			return n
		n = n.get_parent()
	return null

func _anchor_midpoint() -> Vector3:
	if _left_anchor and _right_anchor:
		return 0.5 * (_left_anchor.global_position + _right_anchor.global_position)
	return global_position

func _hook_global_position() -> Vector3:
	if _hook_node and _hook_node is Node3D:
		return (_hook_node as Node3D).global_position
	return _engage_point

# --- Cable visuals ---
func _create_cable_visuals() -> void:
	# One straight segment for idle, and two segments when engaged (left->hook, hook->right)
	_seg_rest = MeshInstance3D.new()
	_seg_left = MeshInstance3D.new()
	_seg_right = MeshInstance3D.new()
	for seg in [_seg_rest, _seg_left, _seg_right]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = cable_radius
		cyl.bottom_radius = cable_radius
		cyl.height = 1.0
		cyl.radial_segments = 12
		seg.mesh = cyl
		var mat := _make_stripe_material()
		seg.material_override = mat
		if seg == _seg_rest:
			_mat_rest = mat
		elif seg == _seg_left:
			_mat_left = mat
		else:
			_mat_right = mat
		add_child(seg)
	_seg_left.visible = false
	_seg_right.visible = false
	_seg_rest.visible = true
	_update_cable_visuals(Vector3.INF)

func _update_cable_visuals(hook_pos: Vector3) -> void:
	if not (_left_anchor and _right_anchor):
		return
	var A = _left_anchor.global_position
	var B = _right_anchor.global_position
	if _engaged and hook_pos != Vector3.INF:
		_seg_rest.visible = false
		_seg_left.visible = true
		_seg_right.visible = true
		_set_cylinder_between(_seg_left, A, hook_pos, _mat_left)
		_set_cylinder_between(_seg_right, hook_pos, B, _mat_right)
	else:
		_seg_rest.visible = true
		_seg_left.visible = false
		_seg_right.visible = false
		_set_cylinder_between(_seg_rest, A, B, _mat_rest)

func _set_cylinder_between(mi: MeshInstance3D, a: Vector3, b: Vector3, mat: ShaderMaterial) -> void:
	var dir = b - a
	var len = dir.length()
	if len < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var cyl := mi.mesh as CylinderMesh
	if cyl:
		cyl.height = len
		# Update band repeats based on physical length
		if mat and band_length_m > 0.01:
			mat.set_shader_parameter("u_repeat", max(1.0, len / band_length_m))
	# Align cylinder local Y with dir
	dir = dir / len
	var y_axis = dir
	var tmp = Vector3(0,1,0)
	if abs(tmp.dot(y_axis)) > 0.95:
		tmp = Vector3(1,0,0)
	var x_axis = tmp.cross(y_axis).normalized()
	var z_axis = x_axis.cross(y_axis)
	var basis = Basis(x_axis, y_axis, z_axis)
	var mid = (a + b) * 0.5
	mi.global_transform = Transform3D(basis, mid)

func _make_stripe_material() -> ShaderMaterial:
	var sh = Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back;

uniform float u_repeat = 10.0; // bands along cylinder height
uniform vec4 u_color_a : source_color = vec4(0.0,0.0,0.0,1.0);
uniform vec4 u_color_b : source_color = vec4(1.0,1.0,1.0,1.0);

void fragment() {
	// CylinderMesh V runs 0..1 along height; alternate by floor(V * repeat)
	float bands = floor(UV.y * u_repeat);
	vec4 ca = u_color_a;
	vec4 cb = u_color_b;
	vec4 col = (mod(bands, 2.0) < 0.5) ? ca : cb;
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("u_color_a", band_color_a)
	mat.set_shader_parameter("u_color_b", band_color_b)
	mat.set_shader_parameter("u_repeat", max(1.0, 10.0))
	return mat
