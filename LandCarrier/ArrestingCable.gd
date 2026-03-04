extends Node3D

# Arresting cable: engages a tailhook Area3D and applies braking force along the deck axis,
# with lateral centering toward the cable line and optional simple visualization.

signal cable_engaged(aircraft: RigidBody3D)
signal cable_released(aircraft: RigidBody3D)

@export var debug_enabled: bool = true

@export var cable_area_path: NodePath           # Area3D detecting the tailhook Area3D
@export var left_anchor_path: NodePath          # Left deck anchor (Node3D)
@export var right_anchor_path: NodePath         # Right deck anchor (Node3D)
@export var deck_direction: Vector3 = Vector3(0, 0, -1) # legacy override; ignored if deck_forward_is_plus_z
@export var deck_forward_is_plus_z: bool = true          # when true, +Z is forward; else -Z
@export var max_tension: float = 750000.0       # Force clamp (N) — increased for ~4.5g stop on 16t aircraft

# Legacy names kept for compatibility in existing scenes (mapped to clearer names in _ready)
@export var linear_k: float = 200.0             # LEGACY: spring stiffness along deck axis (N/m)
@export var linear_c: float = 100.0             # LEGACY: base damping (mass-adaptive added in code)
@export var lateral_k: float = 1500.0           # LEGACY: centering spring across deck (N/m)
@export var lateral_c: float = 5000.0           # LEGACY: lateral damping across deck (N*s/m)

# Clear names used in code after mapping (units in names)
@export var braking_spring_stiffness_n_per_m: float = 1000.0
@export var braking_damping_n_s_per_m: float = 100.0
@export var lateral_centering_stiffness_n_per_m: float = 1500.0
@export var lateral_damping_n_s_per_m: float = 5000.0

@export var mass_adaptive_quadratic_damping_factor: float = 0.03 # kg/m, scales quadratic damping with mass

@export var max_pay_out: float = 30.0           # Max extension before hard stop (m)
@export var auto_release_speed: float = 2.0     # Release when near stop (m/s)
@export var force_smoothing: float = 0.03       # Smooth force changes (s) — fast engagement
@export var visualize_cable: bool = true        # Enable simple cable visuals
@export var cable_radius: float = 0.05
@export var band_length_m: float = 0.5          # Stripe length for visualization (m)
@export var band_color_a: Color = Color(0, 0, 0, 1)
@export var band_color_b: Color = Color(1, 1, 1, 1)

# Roll stabilization while engaged: applies damping around aircraft longitudinal axis
@export var roll_stabilize_enabled: bool = true
@export var roll_stabilize_gain: float = 4.0          # torque per rad/s (scaled by mass)
@export var roll_level_gain: float = 20.0             # leveling torque toward upright (N·m per rad per kg)
@export var roll_max_torque_g_m: float = 30.0         # clamp per (mass*9.8) so torque stays sane
@export var engaged_downforce_g: float = 1.2          # extra downforce in multiples of weight while engaged

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
	add_to_group("arresting_cable")
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
	
	# Map legacy editor values into clearer names so existing scenes continue to work
	braking_spring_stiffness_n_per_m = linear_k
	braking_damping_n_s_per_m = linear_c
	lateral_centering_stiffness_n_per_m = lateral_k
	lateral_damping_n_s_per_m = lateral_c
	if visualize_cable:
		_create_cable_visuals()

func _physics_process(delta: float) -> void:
	if not _engaged or not is_instance_valid(_aircraft):
		return
	_engaged_elapsed += delta
	# Velocity along deck axis (+Z or legacy deck_direction)
	var v = _aircraft.linear_velocity
	var fwd = deck_direction
	if deck_forward_is_plus_z:
		fwd = Vector3(0, 0, 1)
	var axis = (global_transform.basis * fwd).normalized()
	var v_along = v.dot(axis)
	# Signed extension along axis from cable midline to hook
	var hook_pos = _hook_global_position()
	var anchor_mid = _anchor_midpoint()
	var rel = hook_pos - anchor_mid
	var x = rel.dot(axis)

	# Anti-rubber-band: Release if pulling back (rollback)
	if x > 0.5 and v_along < -0.1:
		if debug_enabled:
			print("[Cable] RELEASE by rollback: v_along=", v_along, " x=", x)
		_release()
		return

	# Spring-damper braking: high linear damping clamps to max_tension at high speed (constant braking);
	# spring takes over at low speed to maintain tension until auto-release.
	var spring_term = braking_spring_stiffness_n_per_m * min(abs(x), max_pay_out)
	var sign_x = 1.0 if x >= 0.0 else -1.0
	var damping_force = braking_damping_n_s_per_m * v_along
	var force_along_target = -(damping_force + spring_term * sign_x)

	var alpha = clamp(delta / max(force_smoothing, 0.001), 0.0, 1.0)
	var force_along = lerp(_force_along_prev, force_along_target, alpha)
	force_along = clamp(force_along, -max_tension, max_tension)
	var force_vec = axis * force_along
	# Braking force applied at CG — avoids pitch torque from hook offset (hook is ~1.7m below
	# and ~2.4m behind CG; applying there creates nose-down pitching that lifts the main gear).
	_aircraft.apply_central_force(force_vec)
	_force_along_prev = force_along
	# Lateral centering applied at CG — avoids the roll/yaw torque that the hook's tail
	# offset creates when lateral force is applied there (~2.4m behind, ~1.7m below CG).
	var lateral_rel = rel - axis * rel.dot(axis)
	var v_lat_vec = v - axis * v_along
	var f_lat_vec = -(lateral_centering_stiffness_n_per_m * lateral_rel + lateral_damping_n_s_per_m * v_lat_vec)
	var f_lat_limit = max_tension * 0.25
	if f_lat_vec.length() > f_lat_limit:
		f_lat_vec = f_lat_vec.normalized() * f_lat_limit
	_aircraft.apply_central_force(f_lat_vec)

	# Roll stabilization torque around aircraft forward axis to resist flipping
	if roll_stabilize_enabled and is_instance_valid(_aircraft):
		var fwd_axis: Vector3 = _aircraft.global_transform.basis.z.normalized()
		var up_axis: Vector3 = _aircraft.global_transform.basis.y.normalized()
		# Dampen roll rate (component of angular velocity around forward axis)
		var roll_rate: float = _aircraft.angular_velocity.dot(fwd_axis)
		var damp_torque: float = -roll_rate * roll_stabilize_gain * _aircraft.mass
		# Gentle leveling toward world up using signed angle around forward axis
		var up_proj: Vector3 = (up_axis - fwd_axis * up_axis.dot(fwd_axis)).normalized()
		var world_up_proj: Vector3 = (Vector3.UP - fwd_axis * Vector3.UP.dot(fwd_axis)).normalized()
		if up_proj.length() > 0.0 and world_up_proj.length() > 0.0:
			var sin_a: float = up_proj.cross(world_up_proj).dot(fwd_axis)
			var cos_a: float = up_proj.dot(world_up_proj)
			var roll_err: float = atan2(sin_a, cos_a)  # positive means need +roll around fwd to align
			var level_torque: float = -roll_err * roll_level_gain * _aircraft.mass
			# Clamp total torque to avoid violent reactions
			var max_torque: float = max(0.0, _aircraft.mass * 9.8 * roll_max_torque_g_m)
			var total_torque: float = clamp(damp_torque + level_torque, -max_torque, max_torque)
			_aircraft.apply_torque(fwd_axis * total_torque)
		# Pull each landing gear toward the deck individually.
		# Applying at each gear's position creates a restoring roll torque: if the aircraft
		# tips right, the left gear (now higher) gets pulled down, and so does the right,
		# but their offsets from CG create a net torque that rights the aircraft.
		if engaged_downforce_g > 0.0 and is_instance_valid(_gear_module):
			var gear_shapes = _gear_module.get("gear_collision_shapes")
			if gear_shapes != null and gear_shapes.size() > 0:
				var per_gear_force = Vector3.DOWN * (_aircraft.mass * 9.8 * engaged_downforce_g / gear_shapes.size())
				for gear in gear_shapes:
					if is_instance_valid(gear):
						_aircraft.apply_force(per_gear_force, gear.global_position - _aircraft.global_position)
			else:
				_aircraft.apply_central_force(Vector3.DOWN * (_aircraft.mass * 9.8 * engaged_downforce_g))
		elif engaged_downforce_g > 0.0:
			_aircraft.apply_central_force(Vector3.DOWN * (_aircraft.mass * 9.8 * engaged_downforce_g))
	# Update visuals
	if visualize_cable:
		_update_cable_visuals(hook_pos)
	# Debug and auto-release
	_debug_t += delta
	if debug_enabled and _debug_t >= 0.2:
		_debug_t = 0.0
		var gear_str: String = ""
		if _gear_module and "gear_compressions" in _gear_module and _gear_module.gear_compressions.size() > 0:
			var parts: Array[String] = []
			for c in _gear_module.gear_compressions:
				parts.append(str(snapped(c, 0.001)))
			gear_str = " gear=[" + ", ".join(parts) + "] m"
		print("[Cable] engaged: x=", snapped(x, 0.1), " v=", snapped(v_along, 0.1), " F=", snapped(force_along, 1), gear_str)
	if _engaged_elapsed > 0.3 and v.length() < auto_release_speed:
		if debug_enabled:
			print("[Cable] RELEASE by speed: v=", v.length(), " x=", x)
		_release()

func _on_area_entered(area: Area3D) -> void:
	# Engage on tailhook Area3D by group/name; enforce single-cable interlock
	if _engaged:
		return
	if area.is_in_group("tailhook") or area.name.to_lower().find("hook") != -1:
		print("[Cable] ENTER by ", area.name, " groups=", area.get_groups())
		var ac = _find_aircraft(area)
		if ac:
			_aircraft = ac
			if _aircraft.has_meta("arresting_engaged") and _aircraft.get_meta("arresting_engaged") == true:
				print("[Cable] SKIP engage: aircraft already engaged by another cable")
				_aircraft = null
				return
			_aircraft.set_meta("arresting_engaged", true)
			_aircraft.set_meta("arresting_cable", self)
			_hook_node = area
			_engage_point = area.global_position
			_pay_out_used = 0.0
			_engaged = true
			_engaged_elapsed = 0.0
			_force_along_prev = 0.0
			_debug_t = 0.0
			_cut_aircraft_engine(_aircraft)
			print("[Cable] ENGAGED with ", _aircraft.name, " (Mass: ", _aircraft.mass, " kg)")
			# Reduce lateral grip while engaged to prevent tipping
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
			# Notify listeners (e.g., FlightDeckManager)
			emit_signal("cable_engaged", _aircraft)

func _on_area_exited(area: Area3D) -> void:
	# Stay engaged on exit; release by speed criteria or explicit command
	if area == _hook_node:
		print("[Cable] EXIT by ", area.name, " (ignoring; remain engaged until slow or manual release)")

func _release():
	# Clear engaged state, visuals, and restore gear friction settings
	var released_aircraft := _aircraft
	_engaged = false
	if _aircraft and _aircraft.has_meta("arresting_engaged"):
		_aircraft.set_meta("arresting_engaged", false)
		if _aircraft.has_meta("arresting_cable"):
			_aircraft.remove_meta("arresting_cable")
	_aircraft = null
	_hook_node = null
	print("[Cable] RELEASED")
	if visualize_cable:
		_update_cable_visuals(Vector3.INF)
	if _gear_module:
		if not is_nan(_orig_sideways_friction) and _gear_module.get("sideways_friction") != null:
			_gear_module.set("sideways_friction", _orig_sideways_friction)
		if not is_nan(_orig_friction_multiplier) and _gear_module.get("friction_force_multiplier") != null:
			_gear_module.set("friction_force_multiplier", _orig_friction_multiplier)
		_gear_module = null
	# Notify listeners that the cable released
	if is_instance_valid(released_aircraft):
		emit_signal("cable_released", released_aircraft)

func manual_release() -> void:
	# Public manual release for external controllers (e.g., FlightDeckManager)
	if _engaged:
		_release()

func _cut_aircraft_engine(ac: RigidBody3D) -> void:
	# Try to find ControlEngine or Engine and cut power immediately
	# This ensures stopping even if AI is disabled or player holds throttle
	var targets = ["ControlEngine", "Engine"]
	for t in targets:
		var nodes = ac.find_children(t, "", true, false)
		for n in nodes:
			if n.has_method("set_target_power"):
				n.set_target_power(0.0)
			elif n.has_method("set_throttle_input"):
				n.set_throttle_input(0.0)

# --- Helpers ---
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
	# Orient a cylinder's Y axis along the vector from a to b, centered at midpoint
	var dir = b - a
	var len = dir.length()
	if len < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var cyl := mi.mesh as CylinderMesh
	if cyl:
		cyl.height = len
		if mat and band_length_m > 0.01:
			mat.set_shader_parameter("u_repeat", max(1.0, len / band_length_m))
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
	# Simple unshaded black/white stripe shader; repeats based on cylinder height
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
