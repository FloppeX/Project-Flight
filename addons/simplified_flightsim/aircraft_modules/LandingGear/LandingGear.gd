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

	# Only apply springs if we have proper values set
	if spring_strength > 0 and wheel_rest_height > 0:
		# Apply spring forces to each collision shape
		for i in range(gear_collision_shapes.size()):
			apply_spring_physics(gear_collision_shapes[i], i, delta)

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
	var space_state = collision_shape.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		collision_shape.global_position,
		collision_shape.global_position + Vector3.DOWN * (wheel_rest_height + max_compression)
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
		var compression = wheel_rest_height - distance_to_ground
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
		if debug_enabled and _wheel_was_grounded.size() > gear_index and _wheel_was_grounded[gear_index]:
			print("[LG Wheel %d] LIFTOFF" % [gear_index])
		if _wheel_was_grounded.size() > gear_index:
			_wheel_was_grounded[gear_index] = false

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
	
	# Get aircraft velocity in world space
	var world_velocity = aircraft.linear_velocity
	
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
