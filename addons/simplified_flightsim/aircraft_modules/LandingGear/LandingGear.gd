# The LandingGear module demonstrates how to deal with timed/animated features
# using states and Timer node callbacks

extends AircraftModuleSpatial
class_name AircraftModule_LandingGear

@export var debug_enabled: bool = false

signal update_interface(values)

@export var GearCollisionShape: NodePath
@export var lock_deployed: bool = false
@export var gear_collision_shapes: Array[CollisionShape3D] = []  # Array for wheel collision shapes
@export var gear_visuals: Array[Node3D] = []  # Array for visual gear meshes
@export var gear_rotation_axes: Array[Vector3] = []  # Rotation axis for each gear (empty = no rotation)
@export var gear_rotation_angles: Array[float] = []  # Rotation angle in degrees for each gear when stowed
@export var gear_stowed_rotations_degrees: Array[Vector3] = []  # Explicit Euler stow rotation per gear in degrees
@export var animate_lean_visuals: bool = true
@export var visual_lean_scale: float = 1.0  # 1.0 = visual moves same metres as lean offset
@export var hide_visuals_when_stowed: bool = true

enum LandingGearInitialStates {
	STOWED,
	DEPLOYED
}
@export var InitialState: LandingGearInitialStates = LandingGearInitialStates.STOWED

@export var DeployStowTime: float = 1.0 # secs
@export var DeploySound: AudioStream
@export var StowSound: AudioStream

# Gear suspension (simplified)
@export var spring_strength: float = 50000.0   # Spring force per meter compressed
@export var spring_damping: float = 8000.0     # Damping to prevent bouncing  
@export var nose_spring_damping_multiplier: float = 1.35  # Extra damping on nose gear to reduce pogo on touchdown/rollout
@export var spring_rebound_damping_ratio: float = 0.35  # Use lighter damping while the strut is re-extending to avoid ground pumping
@export var spring_velocity_deadband_mps: float = 0.05  # Ignore tiny contact-normal velocity noise that can cause chatter
@export var wheel_rest_height: float = 1.2     # Normal wheel height above ground
@export var max_compression: float = 0.8       # Maximum compression distance
@export var deck_contact_visual_offset_m: float = 0.0  # Height from collider origin down to visible wheel contact for deck placement helpers
@export var use_accel_lean: bool = true        # Programmatic fore/aft weight transfer
@export var nose_gear_index: int = 0           # Index in gear_collision_shapes for nose gear
@export var rear_gear_indices: Array[int] = [1, 2]  # Indices for main/rear gears
@export var accel_lean_sign: float = -1.0      # Set to 1 or -1 depending on aircraft forward-axis convention
@export var accel_lean_per_mps2: float = 0.16  # Metres of strut offset per m/s^2 longitudinal accel
@export var accel_lean_max_offset_m: float = 0.5  # Max per-wheel offset from acceleration lean
@export var accel_lean_response_s: float = 0.06  # Smoothing time constant for lean offsets
@export var accel_lean_release_response_s: float = 0.03  # Faster response when recovering back toward neutral
@export var accel_lean_ground_compression_threshold_m: float = 0.015  # Treat wheel as grounded above this compression
@export var accel_lean_min_grounded_wheels: int = 2  # Require at least this many grounded wheels
@export var accel_lean_accel_filter_s: float = 0.2  # Low-pass filter for longitudinal acceleration
@export var accel_lean_max_change_per_s: float = 0.9  # Max offset change rate (m/s) to prevent wobble
@export var accel_lean_release_max_change_per_s: float = 2.0  # Faster max offset change while recovering
@export var accel_lean_enable_after_grounded_s: float = 0.25  # Require stable ground contact before enabling lean
@export var accel_lean_max_vertical_speed_mps: float = 0.75  # Disable lean while sink/climb rate is high
@export var accel_lean_compression_curve_power: float = 1.8  # >1 reduces wheel movement more as compression increases
@export var landing_nose_lean_multiplier: float = 1.8  # Extra nose compression during rollout deceleration
@export var landing_nose_min_speed_mps: float = 12.0  # Only boost nose dip above this forward speed
@export var catapult_accel_filter_s: float = 0.6  # Heavier accel filtering during catapult control
@export var catapult_rear_deadband_mps2: float = 1.0  # Ignore tiny accel swings during catapult run
@export var catapult_rear_response_s: float = 0.18  # Slower rear lean response during catapult to prevent pumping
@export var catapult_rear_max_change_per_s: float = 0.45  # Rate-limit rear lean during catapult

# Deck hold: downforce applied at each wheel during cable engagement to resist flipping.
# Released automatically when the cable releases and clears the arresting_engaged meta.
@export var deck_hold_force: float = 15000.0   # Force in Newtons pulling each wheel toward the deck

# Directional wheel friction
@export var forward_friction: float = 0.1      # Low resistance for rolling forward/backward
@export var sideways_friction: float = 8.0     # High resistance for sliding sideways
@export var friction_force_multiplier: float = 1000.0  # Overall friction strength
@export var ground_longitudinal_damping: float = 5000.0  # Extra along-forward damping (N per m/s)
@export var ground_lateral_damping: float = 15000.0      # Extra side damping (N per m/s)
@export var nose_wheel_taxi_steering_enabled: bool = true
@export var nose_wheel_taxi_full_effect_speed_mps: float = 4.0
@export var nose_wheel_taxi_cutoff_speed_mps: float = 10.0
@export var carrier_deck_touch_margin_m: float = 0.03
@export var carrier_deck_follow_min_wheels: int = 3
@export var carrier_deck_follow_engage_time_s: float = 0.12
@export var carrier_deck_follow_release_time_s: float = 0.35
@export var carrier_deck_velocity_match_accel_mps2: float = 45.0

var current_state: LandingGearInitialStates
var deploy_timer: Timer
var audio_player: AudioStreamPlayer3D

# Properties for external access
var is_deployed: bool = false
var is_stowed: bool = true
var gear_compressions: Array[float] = []  # Latest compression per gear slot (metres); readable by debug systems
var _lean_offsets: Array[float] = []       # Per-wheel rest-height offsets from accel lean
var _prev_forward_speed_mps: float = 0.0
var _longitudinal_accel_mps2: float = 0.0
var _longitudinal_accel_filtered_mps2: float = 0.0
var _catapult_accel_filtered_mps2: float = 0.0
var _grounded_stable_time_s: float = 0.0
var _collider_rest_positions: Array[Vector3] = []
var _visual_rest_positions: Array[Vector3] = []
var _visual_rest_rotations: Array[Vector3] = []
var _gear_animation_progress: float = 1.0
var _gear_animation_target: float = 1.0
var _gear_animation_active: bool = false
var _wheel_on_carrier_surface: Array[bool] = []
var _wheel_carrier_surfaces: Array = []
var _carrier_deck_follow_engage_timer_s: float = 0.0
var _carrier_deck_follow_release_timer_s: float = 0.0

# Debug state
var _debug_timer: float = 0.0
var _wheel_was_grounded: Array[bool] = []  # Per-wheel first-contact tracking

func _ready():
	"""Set up module properties"""
	ModuleType = "landing_gear"
	ProcessPhysics = true
	
	# Set up timer
	deploy_timer = Timer.new()
	add_child(deploy_timer)
	deploy_timer.one_shot = true
	deploy_timer.timeout.connect(_on_timer_timeout)
	
	# Set up audio player
	audio_player = AudioStreamPlayer3D.new()
	add_child(audio_player)

func setup(aircraft_node):
	"""Initialize the landing gear system"""
	super.setup(aircraft_node)
	
	# Register wheel colliders as safe colliders (for landing detection)
	for collider in gear_collision_shapes:
		if collider:
			aircraft.register_safe_collider(collider)
	_resolve_gear_visuals_from_colliders()
	_cache_visual_rest_positions()
	
	# Set initial state
	current_state = InitialState
	is_deployed = current_state == LandingGearInitialStates.DEPLOYED
	is_stowed = current_state == LandingGearInitialStates.STOWED
	_gear_animation_progress = 1.0 if is_deployed else 0.0
	_gear_animation_target = _gear_animation_progress
	_gear_animation_active = false
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			collision_shape.disabled = is_stowed
	_apply_visual_gear_pose()

func process_physic_frame(delta: float):
	"""Apply spring physics to each wheel"""
	_update_gear_animation(delta)
	if current_state != LandingGearInitialStates.DEPLOYED:
		_update_carrier_deck_follow_state(true, delta)
		return

	_update_accel_lean(delta)

	# Only apply springs if we have proper values set
	if spring_strength > 0 and wheel_rest_height > 0:
		# Apply spring forces to each collision shape
		for i in range(gear_collision_shapes.size()):
			apply_spring_physics(gear_collision_shapes[i], i, delta)
		_update_carrier_deck_follow_state(false, delta)
	else:
		_update_carrier_deck_follow_state(true, delta)
	_update_lean_geometry()

	if not debug_enabled:
		return
	_debug_timer += delta
	if _debug_timer < 0.25:
		return
	_debug_timer = 0.0
	var b: Basis = aircraft.global_transform.basis
	var roll_deg: float = rad_to_deg(atan2(b.x.y, b.y.y))
	var ang: Vector3 = aircraft.angular_velocity
	var spd: float = aircraft.linear_velocity.length()
	var vs: float = aircraft.linear_velocity.y
	var cable: bool = aircraft.get_meta("arresting_engaged", false)
	var comp_str: String = ""
	for c in gear_compressions:
		comp_str += "%.3fm " % c
	print("[LG] roll=%.1f°  ang=(%.2f,%.2f,%.2f) rad/s  spd=%.1f VS=%.1f  cable=%s  comp=[%s]" % [
		roll_deg, ang.x, ang.y, ang.z, spd, vs, cable, comp_str.strip_edges()])
	# Warn loudly if tumble is developing
	if ang.length() > 1.5:
		print("[LG TUMBLE] angular_velocity magnitude=%.2f rad/s (%.0f°/s)" % [ang.length(), rad_to_deg(ang.length())])

func apply_spring_physics(collision_shape: CollisionShape3D, gear_index: int, delta: float):
	"""Apply spring and damping forces to a gear collision shape"""
	if not collision_shape or collision_shape.disabled:
		if _wheel_on_carrier_surface.size() <= gear_index:
			_wheel_on_carrier_surface.resize(gear_index + 1)
		_wheel_on_carrier_surface[gear_index] = false
		if _wheel_carrier_surfaces.size() <= gear_index:
			_wheel_carrier_surfaces.resize(gear_index + 1)
		_wheel_carrier_surfaces[gear_index] = null
		return
		
	# Cast ray downward from collision shape to detect ground
	var effective_rest_height: float = maxf(0.05, wheel_rest_height)
	var space_state = collision_shape.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		collision_shape.global_position,
		collision_shape.global_position + Vector3.DOWN * (effective_rest_height + max_compression)
	)
	query.exclude = [aircraft.get_rid()]
	
	var result = space_state.intersect_ray(query)
	
	# Track per-wheel grounded state for touchdown prints
	if _wheel_was_grounded.size() <= gear_index:
		_wheel_was_grounded.resize(gear_index + 1)
		_wheel_was_grounded[gear_index] = false

	if result:
		# Ground detected - calculate compression
		var distance_to_ground = collision_shape.global_position.distance_to(result.position)
		var compression = effective_rest_height - distance_to_ground
		compression = clamp(compression, 0.0, max_compression)
		var surface: Variant = result.get("collider", null)
		var carrier_surface := _find_surface_group_node(surface, "carrier")
		var touch_margin: float = maxf(carrier_deck_touch_margin_m, 0.0)
		if _wheel_on_carrier_surface.size() <= gear_index:
			_wheel_on_carrier_surface.resize(gear_index + 1)
		_wheel_on_carrier_surface[gear_index] = carrier_surface != null and distance_to_ground <= (effective_rest_height + touch_margin)
		if _wheel_carrier_surfaces.size() <= gear_index:
			_wheel_carrier_surfaces.resize(gear_index + 1)
		_wheel_carrier_surfaces[gear_index] = carrier_surface if _wheel_on_carrier_surface[gear_index] else null
		# Store for external readers (e.g. debug logging)
		if gear_compressions.size() <= gear_index:
			gear_compressions.resize(gear_index + 1)
		gear_compressions[gear_index] = compression

		# First contact — log touchdown state for this wheel
		if debug_enabled and not _wheel_was_grounded[gear_index]:
			var b: Basis = aircraft.global_transform.basis
			var roll_deg: float = rad_to_deg(atan2(b.x.y, b.y.y))
			var ang: Vector3 = aircraft.angular_velocity
			var cable: bool = aircraft.get_meta("arresting_engaged", false)
			print("[LG Wheel %d] TOUCHDOWN  spd=%.1f m/s  VS=%.1f m/s  roll=%.1f°  ang=(%.2f,%.2f,%.2f) rad/s  cable=%s  comp=%.3fm" % [
				gear_index, aircraft.linear_velocity.length(), aircraft.linear_velocity.y,
				roll_deg, ang.x, ang.y, ang.z, cable, compression])
		_wheel_was_grounded[gear_index] = true

		# Deck hold: pull the wheel toward the deck during cable engagement to prevent flipping.
		# Runs on any ground contact (not just compression) so it fires even if a wheel
		# momentarily unloads during the arrest. Released when the cable clears arresting_engaged.
		var force_position = collision_shape.global_position - aircraft.global_position
		if deck_hold_force > 0.0 and aircraft.get_meta("arresting_engaged", false):
			if debug_enabled and Engine.get_process_frames() % 30 == 0:
				print("[LG Wheel %d] DECK HOLD  force=%.0fN  normal=%s" % [gear_index, deck_hold_force, snapped(result.normal, Vector3.ONE * 0.01)])
			aircraft.apply_force(-result.normal * deck_hold_force, force_position)

		if compression > 0.01:  # Small threshold to avoid jittering
			var contact_normal: Vector3 = (result.normal as Vector3).normalized()

			# Calculate spring force (Hooke's law)
			var spring_force = spring_strength * compression

			# Damping should oppose the wheel point's motion into/out of the contacted surface,
			# not just the aircraft's global Y speed. This is especially important for the nose gear,
			# which otherwise tends to pogo on touchdown and rollout.
			var point_velocity: Vector3 = aircraft.linear_velocity + aircraft.angular_velocity.cross(force_position)
			var velocity_toward_surface: float = -point_velocity.dot(contact_normal)
			if absf(velocity_toward_surface) < spring_velocity_deadband_mps:
				velocity_toward_surface = 0.0
			var damping_ratio: float = 1.0 if velocity_toward_surface >= 0.0 else clampf(spring_rebound_damping_ratio, 0.0, 1.0)
			var damping_scale: float = nose_spring_damping_multiplier if gear_index == nose_gear_index else 1.0
			var damping_force = spring_damping * damping_scale * damping_ratio * velocity_toward_surface

			# Apply suspension force along the actual contact normal and never let rebound
			# turn into an active launch force.
			var total_normal_force = maxf(0.0, spring_force + damping_force)
			aircraft.apply_force(contact_normal * total_normal_force, force_position)

			# Apply directional wheel friction
			apply_wheel_friction(collision_shape, gear_index, compression, contact_normal, result.get("collider", null))
	else:
		if _wheel_on_carrier_surface.size() <= gear_index:
			_wheel_on_carrier_surface.resize(gear_index + 1)
		_wheel_on_carrier_surface[gear_index] = false
		if _wheel_carrier_surfaces.size() <= gear_index:
			_wheel_carrier_surfaces.resize(gear_index + 1)
		_wheel_carrier_surfaces[gear_index] = null
		if gear_compressions.size() <= gear_index:
			gear_compressions.resize(gear_index + 1)
		gear_compressions[gear_index] = 0.0
		if debug_enabled and _wheel_was_grounded.size() > gear_index and _wheel_was_grounded[gear_index]:
			print("[LG Wheel %d] LIFTOFF" % [gear_index])
		if _wheel_was_grounded.size() > gear_index:
			_wheel_was_grounded[gear_index] = false

func _update_carrier_deck_follow_state(force_clear: bool = false, delta: float = 0.0) -> void:
	if not is_instance_valid(aircraft):
		return

	var should_follow: bool = false
	var carrier_surface: Node = null
	var contact_ready: bool = false
	var touching_count: int = 0
	var required_count: int = clampi(carrier_deck_follow_min_wheels, 1, maxi(1, gear_collision_shapes.size()))
	if not force_clear:
		for idx in range(_wheel_on_carrier_surface.size()):
			if _wheel_on_carrier_surface[idx]:
				touching_count += 1
				if carrier_surface == null and idx < _wheel_carrier_surfaces.size():
					carrier_surface = _wheel_carrier_surfaces[idx] as Node
		contact_ready = touching_count >= required_count
		if contact_ready:
			_carrier_deck_follow_engage_timer_s += maxf(delta, 0.0)
			_carrier_deck_follow_release_timer_s = maxf(carrier_deck_follow_release_time_s, 0.0)
		else:
			_carrier_deck_follow_engage_timer_s = 0.0
			_carrier_deck_follow_release_timer_s = maxf(
				_carrier_deck_follow_release_timer_s - maxf(delta, 0.0),
				0.0
			)
		should_follow = _carrier_deck_follow_engage_timer_s >= maxf(carrier_deck_follow_engage_time_s, 0.0) \
				or (aircraft.has_meta("carrier_deck_follow") and _carrier_deck_follow_release_timer_s > 0.0)
		if touching_count > 0:
			_match_helicopter_carrier_velocity(carrier_surface, touching_count, required_count, delta)
	else:
		_carrier_deck_follow_engage_timer_s = 0.0
		_carrier_deck_follow_release_timer_s = 0.0

	if should_follow:
		aircraft.set_meta("carrier_deck_follow", true)
		if carrier_surface:
			VelocityFrame.set_reference_node(aircraft, carrier_surface)
	else:
		if aircraft.has_meta("carrier_deck_follow"):
			aircraft.remove_meta("carrier_deck_follow")
		if not bool(aircraft.get_meta("carrier_transport_mode", false)) \
				and not bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)) \
				and not aircraft.has_meta("helicopter_deck_reference_node"):
			VelocityFrame.clear_reference(aircraft)


func get_gear_count() -> int:
	return gear_collision_shapes.size()


func get_carrier_surface_wheel_count() -> int:
	var count := 0
	for idx in range(gear_collision_shapes.size()):
		if idx < _wheel_on_carrier_surface.size() and bool(_wheel_on_carrier_surface[idx]):
			count += 1
	return count


func are_all_wheels_on_carrier_surface() -> bool:
	var gear_count := get_gear_count()
	return gear_count > 0 and get_carrier_surface_wheel_count() >= gear_count


func _match_helicopter_carrier_velocity(carrier_surface: Node, touching_count: int, required_count: int, delta: float) -> void:
	if not _is_aircraft_helicopter():
		return
	if not (aircraft is RigidBody3D):
		return
	if aircraft.freeze:
		return
	if bool(aircraft.get_meta("carrier_transport_mode", false)):
		return
	if bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false)):
		return
	if carrier_surface == null or not is_instance_valid(carrier_surface):
		return

	var deck_velocity := VelocityFrame.get_node_velocity(carrier_surface)
	var vel: Vector3 = aircraft.linear_velocity
	var target_velocity := Vector3(deck_velocity.x, vel.y, deck_velocity.z)
	var grounded_t := clampf(float(touching_count) / float(maxi(required_count, 1)), 0.0, 1.0)
	var max_step := maxf(carrier_deck_velocity_match_accel_mps2, 0.0) * grounded_t * maxf(delta, 0.0)
	aircraft.linear_velocity = vel.move_toward(target_velocity, max_step)

func _update_accel_lean(delta: float) -> void:
	if not use_accel_lean or not aircraft:
		return

	var count: int = gear_collision_shapes.size()
	if _lean_offsets.size() < count:
		_lean_offsets.resize(count)
		for i in range(count):
			_lean_offsets[i] = 0.0

	# Longitudinal acceleration in aircraft forward axis (+Z here).
	var forward_axis: Vector3 = aircraft.global_transform.basis.z.normalized()
	var forward_speed_mps: float = aircraft.linear_velocity.dot(forward_axis)
	_longitudinal_accel_mps2 = (forward_speed_mps - _prev_forward_speed_mps) / maxf(delta, 0.001)
	_prev_forward_speed_mps = forward_speed_mps
	var accel_alpha: float = clampf(delta / maxf(accel_lean_accel_filter_s, 0.001), 0.0, 1.0)
	_longitudinal_accel_filtered_mps2 = lerpf(_longitudinal_accel_filtered_mps2, _longitudinal_accel_mps2, accel_alpha)

	# During catapult/external handling, keep nose gear neutral to avoid lift,
	# but still allow rear compression response under launch acceleration.
	if aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled")):
		_grounded_stable_time_s = 0.0
		var signed_accel_cat_raw: float = _longitudinal_accel_filtered_mps2 * (1.0 if accel_lean_sign >= 0.0 else -1.0)
		var cat_alpha: float = clampf(delta / maxf(catapult_accel_filter_s, 0.001), 0.0, 1.0)
		_catapult_accel_filtered_mps2 = lerpf(_catapult_accel_filtered_mps2, signed_accel_cat_raw, cat_alpha)
		var signed_accel_cat: float = _catapult_accel_filtered_mps2
		if absf(signed_accel_cat) < catapult_rear_deadband_mps2:
			signed_accel_cat = 0.0
		var rear_target_cat: float = clampf(-signed_accel_cat * accel_lean_per_mps2, -accel_lean_max_offset_m, accel_lean_max_offset_m)

		if nose_gear_index >= 0 and nose_gear_index < count:
			var nose_alpha_cat: float = clampf(delta / maxf(accel_lean_release_response_s, 0.001), 0.0, 1.0)
			var nose_step_cat: float = accel_lean_release_max_change_per_s * delta
			var nose_smoothed_zero: float = lerpf(_lean_offsets[nose_gear_index], 0.0, nose_alpha_cat)
			_lean_offsets[nose_gear_index] = move_toward(_lean_offsets[nose_gear_index], nose_smoothed_zero, nose_step_cat)

		for idx in rear_gear_indices:
			if idx >= 0 and idx < count:
				var rear_target_scaled_cat: float = rear_target_cat
				var rear_recovering_cat: bool = absf(rear_target_scaled_cat) < absf(_lean_offsets[idx])
				var rear_alpha_cat: float = clampf(delta / maxf(accel_lean_release_response_s if rear_recovering_cat else catapult_rear_response_s, 0.001), 0.0, 1.0)
				var rear_step_cat: float = (accel_lean_release_max_change_per_s if rear_recovering_cat else catapult_rear_max_change_per_s) * delta
				var rear_smoothed_cat: float = lerpf(_lean_offsets[idx], rear_target_scaled_cat, rear_alpha_cat)
				_lean_offsets[idx] = move_toward(_lean_offsets[idx], rear_smoothed_cat, rear_step_cat)
		return
	else:
		_catapult_accel_filtered_mps2 = _longitudinal_accel_filtered_mps2 * (1.0 if accel_lean_sign >= 0.0 else -1.0)

	# Only drive lean when the aircraft is actually resting on gear.
	var grounded_wheels: int = 0
	for i in range(min(gear_compressions.size(), count)):
		if gear_compressions[i] > accel_lean_ground_compression_threshold_m:
			grounded_wheels += 1
	if grounded_wheels >= accel_lean_min_grounded_wheels:
		_grounded_stable_time_s += delta
	else:
		_grounded_stable_time_s = 0.0
	var vertical_speed_ok: bool = absf(aircraft.linear_velocity.y) <= accel_lean_max_vertical_speed_mps
	var lean_active: bool = _grounded_stable_time_s >= accel_lean_enable_after_grounded_s and vertical_speed_ok

	var signed_accel: float = _longitudinal_accel_filtered_mps2 * (1.0 if accel_lean_sign >= 0.0 else -1.0)
	var front_target: float = 0.0
	if lean_active:
		front_target = clampf(signed_accel * accel_lean_per_mps2, -accel_lean_max_offset_m, accel_lean_max_offset_m)
	var rear_target: float = -front_target
	var is_ground_decelerating: bool = lean_active \
		and absf(forward_speed_mps) >= landing_nose_min_speed_mps \
		and (forward_speed_mps * _longitudinal_accel_filtered_mps2) < 0.0

	if nose_gear_index >= 0 and nose_gear_index < count:
		var nose_scale: float = _compression_scale_for_gear(nose_gear_index)
		var nose_target: float = front_target * nose_scale
		if is_ground_decelerating:
			nose_target *= maxf(landing_nose_lean_multiplier, 1.0)
			nose_target = clampf(nose_target, -accel_lean_max_offset_m, accel_lean_max_offset_m)
		var nose_recovering: bool = absf(nose_target) < absf(_lean_offsets[nose_gear_index])
		var nose_alpha: float = clampf(delta / maxf(accel_lean_release_response_s if nose_recovering else accel_lean_response_s, 0.001), 0.0, 1.0)
		var nose_step: float = (accel_lean_release_max_change_per_s if nose_recovering else accel_lean_max_change_per_s) * delta
		var nose_smoothed: float = lerpf(_lean_offsets[nose_gear_index], nose_target, nose_alpha)
		_lean_offsets[nose_gear_index] = move_toward(_lean_offsets[nose_gear_index], nose_smoothed, nose_step)

	for idx in rear_gear_indices:
		if idx >= 0 and idx < count:
			var rear_scale: float = _compression_scale_for_gear(idx)
			var rear_target_scaled: float = rear_target * rear_scale
			var rear_recovering: bool = absf(rear_target_scaled) < absf(_lean_offsets[idx])
			var rear_alpha: float = clampf(delta / maxf(accel_lean_release_response_s if rear_recovering else accel_lean_response_s, 0.001), 0.0, 1.0)
			var rear_step: float = (accel_lean_release_max_change_per_s if rear_recovering else accel_lean_max_change_per_s) * delta
			var rear_smoothed: float = lerpf(_lean_offsets[idx], rear_target_scaled, rear_alpha)
			_lean_offsets[idx] = move_toward(_lean_offsets[idx], rear_smoothed, rear_step)

func _get_lean_offset_for_gear(gear_index: int) -> float:
	if not use_accel_lean:
		return 0.0
	if gear_index < 0 or gear_index >= _lean_offsets.size():
		return 0.0
	return _lean_offsets[gear_index]

func _compression_scale_for_gear(gear_index: int) -> float:
	if gear_index < 0 or gear_index >= gear_compressions.size():
		return 1.0
	var compression: float = gear_compressions[gear_index]
	var norm: float = clampf(compression / maxf(max_compression, 0.001), 0.0, 1.0)
	var power: float = maxf(accel_lean_compression_curve_power, 0.1)
	return pow(1.0 - norm, power)

func _resolve_gear_visuals_from_colliders() -> void:
	if gear_visuals.size() < gear_collision_shapes.size():
		gear_visuals.resize(gear_collision_shapes.size())
	for i in range(gear_collision_shapes.size()):
		if i < gear_visuals.size() and is_instance_valid(gear_visuals[i]):
			continue
		var cs: CollisionShape3D = gear_collision_shapes[i]
		if not is_instance_valid(cs):
			continue
		for child in cs.get_children():
			if child is Node3D:
				gear_visuals[i] = child as Node3D
				break

func _cache_visual_rest_positions() -> void:
	_collider_rest_positions.clear()
	_visual_rest_positions.clear()
	_visual_rest_rotations.clear()
	for i in range(gear_collision_shapes.size()):
		var cs: CollisionShape3D = gear_collision_shapes[i]
		if is_instance_valid(cs):
			_collider_rest_positions.append(cs.position)
		else:
			_collider_rest_positions.append(Vector3.ZERO)
		var v: Node3D = gear_visuals[i] if i < gear_visuals.size() else null
		if is_instance_valid(v):
			_visual_rest_positions.append(v.position)
			_visual_rest_rotations.append(v.rotation)
		else:
			_visual_rest_positions.append(Vector3.ZERO)
			_visual_rest_rotations.append(Vector3.ZERO)

func _update_gear_animation(delta: float) -> void:
	if not _gear_animation_active:
		return
	var duration: float = maxf(DeployStowTime, 0.001)
	var step: float = delta / duration
	_gear_animation_progress = move_toward(_gear_animation_progress, _gear_animation_target, step)
	_apply_visual_gear_pose()
	if is_equal_approx(_gear_animation_progress, _gear_animation_target):
		_gear_animation_active = false
		if hide_visuals_when_stowed and _gear_animation_progress <= 0.0:
			for visual in gear_visuals:
				if is_instance_valid(visual):
					visual.visible = false
					_set_shadow_casting_recursive(visual, false)

func _set_shadow_casting_recursive(node: Node, enabled: bool) -> void:
	if node is GeometryInstance3D:
		var geom: GeometryInstance3D = node as GeometryInstance3D
		geom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_set_shadow_casting_recursive(child, enabled)

func _apply_visual_gear_pose() -> void:
	if _visual_rest_positions.size() < gear_collision_shapes.size() or _visual_rest_rotations.size() < gear_collision_shapes.size():
		_cache_visual_rest_positions()
	var stow_alpha: float = 1.0 - clampf(_gear_animation_progress, 0.0, 1.0)
	for i in range(gear_visuals.size()):
		var visual: Node3D = gear_visuals[i]
		if not is_instance_valid(visual):
			continue
		if i < _visual_rest_positions.size():
			visual.position = _visual_rest_positions[i]
		if i < _visual_rest_rotations.size():
			var rest_rotation: Vector3 = _visual_rest_rotations[i]
			var stowed_rotation_deg: Vector3 = gear_stowed_rotations_degrees[i] if i < gear_stowed_rotations_degrees.size() else Vector3.ZERO
			if i < gear_stowed_rotations_degrees.size():
				visual.rotation = rest_rotation + Vector3(
					deg_to_rad(stowed_rotation_deg.x),
					deg_to_rad(stowed_rotation_deg.y),
					deg_to_rad(stowed_rotation_deg.z)
				) * stow_alpha
			else:
				var axis: Vector3 = gear_rotation_axes[i] if i < gear_rotation_axes.size() else Vector3.ZERO
				var angle_deg: float = gear_rotation_angles[i] if i < gear_rotation_angles.size() else 0.0
				if axis.length_squared() > 0.0 and not is_zero_approx(angle_deg):
					visual.rotation = rest_rotation + axis.normalized() * deg_to_rad(angle_deg) * stow_alpha
				else:
					visual.rotation = rest_rotation
		if _gear_animation_progress > 0.0 or not hide_visuals_when_stowed:
			visual.visible = true
			_set_shadow_casting_recursive(visual, true)

func _update_lean_geometry() -> void:
	if not animate_lean_visuals:
		return
	if current_state != LandingGearInitialStates.DEPLOYED:
		return
	if _visual_rest_positions.size() < gear_collision_shapes.size() or _collider_rest_positions.size() < gear_collision_shapes.size():
		_cache_visual_rest_positions()
	for i in range(gear_collision_shapes.size()):
		if i >= _collider_rest_positions.size():
			continue
		var cs: CollisionShape3D = gear_collision_shapes[i]
		if not is_instance_valid(cs):
			continue
		var y_off: float = _get_lean_offset_for_gear(i) * visual_lean_scale
		var cs_rest: Vector3 = _collider_rest_positions[i]
		cs.position = Vector3(cs_rest.x, cs_rest.y + y_off, cs_rest.z)

		# If the visual is not parented under the collider, apply the same offset to keep it in sync.
		if i < gear_visuals.size() and i < _visual_rest_positions.size():
			var v: Node3D = gear_visuals[i]
			if is_instance_valid(v):
				var parent_is_collider: bool = v.get_parent() == cs
				if not parent_is_collider:
					var v_rest: Vector3 = _visual_rest_positions[i]
					v.position = Vector3(v_rest.x, v_rest.y + y_off, v_rest.z)

func deploy():
	"""Deploy the landing gear"""
	if current_state == LandingGearInitialStates.DEPLOYED and is_equal_approx(_gear_animation_target, 1.0):
		return
	
	# Start deploy animation/timer
	deploy_timer.start(DeployStowTime)
	
	# Play deploy sound
	if DeploySound:
		play_sound(DeploySound)
	
	# Update state immediately for interface
	current_state = LandingGearInitialStates.DEPLOYED
	is_deployed = true
	is_stowed = false
	_gear_animation_target = 1.0
	_gear_animation_active = true
	if debug_enabled:
		print("[LG] deploy() called; enabling ", gear_collision_shapes.size(), " colliders and ", gear_visuals.size(), " visuals")
	
	# Enable collision shapes immediately
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			if debug_enabled:
				print("[LG]  collider -> ", collision_shape.get_path())
			collision_shape.disabled = false
	
	# Show visual meshes immediately
	for visual in gear_visuals:
		if visual:
			if debug_enabled:
				print("[LG]  visual   -> ", visual.get_path())
			visual.visible = true
	_apply_visual_gear_pose()
	
	# Emit interface update
	update_interface.emit({"landing_gear": "deployed"})

func stow():
	"""Stow the landing gear"""
	if lock_deployed:
		deploy()
		return
	if current_state == LandingGearInitialStates.STOWED and is_equal_approx(_gear_animation_target, 0.0):
		return
	
	# Start stow animation/timer
	deploy_timer.start(DeployStowTime)
	
	# Play stow sound
	if StowSound:
			play_sound(StowSound)
	
	# Update state immediately for interface
	current_state = LandingGearInitialStates.STOWED
	is_deployed = false
	is_stowed = true
	_gear_animation_target = 0.0
	_gear_animation_active = true
	if debug_enabled:
		print("[LG] stow() called; disabling ", gear_collision_shapes.size(), " colliders and hiding ", gear_visuals.size(), " visuals")
	
	# Disable collision shapes immediately
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			if debug_enabled:
				print("[LG]  collider -> ", collision_shape.get_path())
			collision_shape.disabled = true
	
	for visual in gear_visuals:
		if visual:
			if debug_enabled:
				print("[LG]  visual   -> ", visual.get_path())
			visual.visible = true
	# Reset visual transforms to rest
	for i in range(min(gear_visuals.size(), _visual_rest_positions.size())):
		if is_instance_valid(gear_visuals[i]):
			gear_visuals[i].position = _visual_rest_positions[i]
	for i in range(min(gear_visuals.size(), _visual_rest_rotations.size())):
		if is_instance_valid(gear_visuals[i]):
			gear_visuals[i].rotation = _visual_rest_rotations[i]
	for i in range(min(gear_collision_shapes.size(), _collider_rest_positions.size())):
		if is_instance_valid(gear_collision_shapes[i]):
			gear_collision_shapes[i].position = _collider_rest_positions[i]
	_apply_visual_gear_pose()
	
	# Emit interface update
	update_interface.emit({"landing_gear": "stowed"})

func _on_timer_timeout():
	"""Called when deploy/stow timer completes"""
	# Animation is complete, nothing more to do since we handle states immediately
	pass

func play_sound(sound: AudioStream):
	"""Play a sound effect"""
	if sound and audio_player:
		audio_player.stream = sound
		audio_player.play()

func _find_surface_group_node(surface: Variant, group_name: String) -> Node:
	var node := surface as Node
	while node:
		if node.is_in_group(group_name):
			return node
		node = node.get_parent()
	return null

func apply_wheel_friction(collision_shape: CollisionShape3D, gear_index: int, compression: float, contact_normal: Vector3 = Vector3.UP, surface: Variant = null):
	"""Apply directional friction to simulate realistic wheel behavior"""
	if not aircraft or compression <= 0.01:
		return
	
	var carrier_surface := _find_surface_group_node(surface, "carrier")
	var on_carrier_surface: bool = carrier_surface != null
	var parking_brake: bool = aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
	var controls_disabled: bool = aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled"))
	var arresting_engaged: bool = aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged"))
	var deck_follow: bool = aircraft.has_meta("carrier_deck_follow") and bool(aircraft.get_meta("carrier_deck_follow"))
	var transport_mode: bool = aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode"))
	if on_carrier_surface and _is_aircraft_helicopter() \
			and not deck_follow \
			and not transport_mode \
			and not parking_brake \
			and not arresting_engaged \
			and not controls_disabled:
		return
	contact_normal = contact_normal.normalized() if contact_normal.length_squared() > 0.0001 else Vector3.UP
	
	# Build wheel axes along the contact plane so steering works on ground without
	# introducing vertical friction components on slopes or moving decks.
	var wheel_forward: Vector3 = _project_axis_onto_surface(aircraft.global_transform.basis.z, contact_normal, aircraft.global_transform.basis.z)
	var wheel_right: Vector3 = _project_axis_onto_surface(aircraft.global_transform.basis.x, contact_normal, aircraft.global_transform.basis.x)
	
	# Get aircraft velocity relative to any carrier it sits on, so friction brakes
	# toward deck-relative zero rather than world zero (carrier is a moving platform).
	var relative_velocity = aircraft.linear_velocity
	if on_carrier_surface:
		relative_velocity = VelocityFrame.get_relative_velocity(aircraft)

	if nose_wheel_taxi_steering_enabled and gear_index == nose_gear_index and nose_wheel_taxi_cutoff_speed_mps > 0.0:
		var surface_velocity: Vector3 = relative_velocity - contact_normal * relative_velocity.dot(contact_normal)
		var ground_speed_mps: float = surface_velocity.length()
		var steer_blend: float = 1.0 - _smoothstep(
			nose_wheel_taxi_full_effect_speed_mps,
			maxf(nose_wheel_taxi_cutoff_speed_mps, nose_wheel_taxi_full_effect_speed_mps + 0.01),
			ground_speed_mps
		)
		if steer_blend > 0.001:
			var steered_forward: Vector3 = _project_axis_onto_surface(collision_shape.global_transform.basis.z, contact_normal, wheel_forward)
			wheel_forward = wheel_forward.lerp(steered_forward, steer_blend).normalized()
			wheel_right = contact_normal.cross(wheel_forward).normalized()
			if wheel_right.length_squared() <= 0.0001:
				wheel_right = _project_axis_onto_surface(collision_shape.global_transform.basis.x, contact_normal, aircraft.global_transform.basis.x)

	# Project velocity onto aircraft's local axes
	var forward_velocity = relative_velocity.dot(wheel_forward)
	var sideways_velocity = relative_velocity.dot(wheel_right)
	
	# Calculate friction forces
	var forward_friction_force = -forward_velocity * forward_friction * friction_force_multiplier * compression
	var sideways_friction_force = -sideways_velocity * sideways_friction * friction_force_multiplier * compression
	
	# Add velocity-proportional damping to keep aircraft still on deck ONLY when engine is off
	# and not under external control (like a catapult).
	# Skip forward damping while arresting cable is engaged — cable provides the braking.
	if (on_carrier_surface and not _is_engine_running() and not controls_disabled) or parking_brake:
		if not arresting_engaged:
			forward_friction_force += -forward_velocity * ground_longitudinal_damping
		sideways_friction_force += -sideways_velocity * ground_lateral_damping
	
	# Apply friction forces in aircraft's local coordinate system
	var total_friction = (wheel_forward * forward_friction_force) + (wheel_right * sideways_friction_force)
	
	# Apply friction force at wheel position
	var force_position = collision_shape.global_position - aircraft.global_position
	aircraft.apply_force(total_friction, force_position)


func _is_aircraft_helicopter() -> bool:
	if not is_instance_valid(aircraft):
		return false
	if bool(aircraft.get_meta("is_helicopter", false)):
		return true
	var role: String = str(aircraft.get_meta("aircraft_role", "")).to_lower()
	return role.find("helicopter") >= 0

func _project_axis_onto_surface(axis: Vector3, normal: Vector3, fallback: Vector3) -> Vector3:
	var projected: Vector3 = axis - normal * axis.dot(normal)
	if projected.length_squared() <= 0.0001:
		projected = fallback - normal * fallback.dot(normal)
	if projected.length_squared() <= 0.0001:
		projected = Vector3(normal.z, 0.0, -normal.x)
	if projected.length_squared() <= 0.0001:
		projected = Vector3.FORWARD
	return projected.normalized()

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _is_engine_running() -> bool:
	if aircraft == null:
		return false
	if not aircraft.has_method("find_modules_by_type"):
		return false
	var engines = aircraft.find_modules_by_type("engine")
	for e in engines:
		var working = e.get("is_engine_working") if e.has_method("get") else null
		if working != null and bool(working):
			return true
		var power = e.get("current_power") if e.has_method("get") else null
		if power != null and float(power) > 0.05:
			return true
	return false
