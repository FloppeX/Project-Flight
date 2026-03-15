# The LandingGear module demonstrates how to deal with timed/animated features
# using states and Timer node callbacks

extends AircraftModuleSpatial
class_name AircraftModule_LandingGear

@export var debug_enabled: bool = false

signal update_interface(values)

@export var GearCollisionShape: NodePath
@export var gear_collision_shapes: Array[CollisionShape3D] = []  # Array for wheel collision shapes
@export var gear_visuals: Array[Node3D] = []  # Array for visual gear meshes
@export var gear_rotation_axes: Array[Vector3] = []  # Rotation axis for each gear (empty = no rotation)
@export var gear_rotation_angles: Array[float] = []  # Rotation angle in degrees for each gear when stowed
@export var animate_lean_visuals: bool = true
@export var visual_lean_scale: float = 1.0  # 1.0 = visual moves same metres as lean offset

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
@export var wheel_rest_height: float = 1.2     # Normal wheel height above ground
@export var max_compression: float = 0.8       # Maximum compression distance
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
	if current_state == LandingGearInitialStates.STOWED:
		stow()
	else:
		deploy()

func process_physic_frame(delta: float):
	"""Apply spring physics to each wheel"""
	if current_state != LandingGearInitialStates.DEPLOYED:
		return

	_update_accel_lean(delta)

	# Only apply springs if we have proper values set
	if spring_strength > 0 and wheel_rest_height > 0:
		# Apply spring forces to each collision shape
		for i in range(gear_collision_shapes.size()):
			apply_spring_physics(gear_collision_shapes[i], i, delta)
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
			# Calculate spring force (Hooke's law)
			var spring_force = spring_strength * compression

			# Calculate damping force (opposes velocity)
			var aircraft_velocity = aircraft.linear_velocity.y
			var damping_force = -spring_damping * aircraft_velocity * compression

			# Apply vertical forces (spring + damping)
			var total_vertical_force = spring_force + damping_force
			aircraft.apply_force(Vector3.UP * total_vertical_force, force_position)

			# Apply directional wheel friction
			apply_wheel_friction(collision_shape, compression)
	else:
		if gear_compressions.size() <= gear_index:
			gear_compressions.resize(gear_index + 1)
		gear_compressions[gear_index] = 0.0
		if debug_enabled and _wheel_was_grounded.size() > gear_index and _wheel_was_grounded[gear_index]:
			print("[LG Wheel %d] LIFTOFF" % [gear_index])
		if _wheel_was_grounded.size() > gear_index:
			_wheel_was_grounded[gear_index] = false

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
	for i in range(gear_collision_shapes.size()):
		var cs: CollisionShape3D = gear_collision_shapes[i]
		if is_instance_valid(cs):
			_collider_rest_positions.append(cs.position)
		else:
			_collider_rest_positions.append(Vector3.ZERO)
		var v: Node3D = gear_visuals[i] if i < gear_visuals.size() else null
		if is_instance_valid(v):
			_visual_rest_positions.append(v.position)
		else:
			_visual_rest_positions.append(Vector3.ZERO)

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
	if current_state == LandingGearInitialStates.DEPLOYED:
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
	_cache_visual_rest_positions()
	
	# Emit interface update
	update_interface.emit({"landing_gear": "deployed"})

func stow():
	"""Stow the landing gear"""
	if current_state == LandingGearInitialStates.STOWED:
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
	if debug_enabled:
		print("[LG] stow() called; disabling ", gear_collision_shapes.size(), " colliders and hiding ", gear_visuals.size(), " visuals")
	
	# Disable collision shapes immediately
	for collision_shape in gear_collision_shapes:
		if collision_shape:
			if debug_enabled:
				print("[LG]  collider -> ", collision_shape.get_path())
			collision_shape.disabled = true
	
	# Hide visual meshes immediately
	for visual in gear_visuals:
		if visual:
			if debug_enabled:
				print("[LG]  visual   -> ", visual.get_path())
			visual.visible = false
	# Reset visual transforms to rest
	for i in range(min(gear_visuals.size(), _visual_rest_positions.size())):
		if is_instance_valid(gear_visuals[i]):
			gear_visuals[i].position = _visual_rest_positions[i]
	for i in range(min(gear_collision_shapes.size(), _collider_rest_positions.size())):
		if is_instance_valid(gear_collision_shapes[i]):
			gear_collision_shapes[i].position = _collider_rest_positions[i]
	
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

func apply_wheel_friction(collision_shape: CollisionShape3D, compression: float):
	"""Apply directional friction to simulate realistic wheel behavior"""
	if not aircraft or compression <= 0.01:
		return
	
	# Get aircraft's local coordinate system
	var aircraft_forward = aircraft.global_transform.basis.z    # Aircraft forward direction (+Z)
	var aircraft_right = aircraft.global_transform.basis.x     # Aircraft right direction
	
	# Get aircraft velocity relative to any carrier it sits on, so friction brakes
	# toward deck-relative zero rather than world zero (carrier is a moving platform).
	var world_velocity = aircraft.linear_velocity
	var carrier_node = aircraft.get_tree().get_first_node_in_group("carrier") if aircraft.get_tree() else null
	if carrier_node and carrier_node.has_method("get") and "velocity" in carrier_node:
		world_velocity -= carrier_node.velocity

	# Project velocity onto aircraft's local axes
	var forward_velocity = world_velocity.dot(aircraft_forward)
	var sideways_velocity = world_velocity.dot(aircraft_right)
	
	# Calculate friction forces
	var forward_friction_force = -forward_velocity * forward_friction * friction_force_multiplier * compression
	var sideways_friction_force = -sideways_velocity * sideways_friction * friction_force_multiplier * compression
	
	# Add velocity-proportional damping to keep aircraft still on deck ONLY when engine is off
	# and not under external control (like a catapult).
	# Skip forward damping while arresting cable is engaged — cable provides the braking.
	if (not _is_engine_running() and not aircraft.has_meta("controls_disabled")) or aircraft.has_meta("parking_brake"):
		if not aircraft.get_meta("arresting_engaged", false):
			forward_friction_force += -forward_velocity * ground_longitudinal_damping
		sideways_friction_force += -sideways_velocity * ground_lateral_damping
	
	# Apply friction forces in aircraft's local coordinate system
	var total_friction = (aircraft_forward * forward_friction_force) + (aircraft_right * sideways_friction_force)
	
	# Apply friction force at wheel position
	var force_position = collision_shape.global_position - aircraft.global_position
	aircraft.apply_force(total_friction, force_position)

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
