# ContinuousTurbulence.gd - Continuous atmospheric turbulence system with impulse-based forces
extends Node3D
class_name ContinuousTurbulence

@export var base_intensity: float = 2.0
@export var max_intensity: float = 10.0
@export var turbulence_scale: float = 0.001  # How "big" the noise patterns are
@export var time_speed: float = 0.1
@export var altitude_factor: float = 0.001  # How altitude affects turbulence
@export var max_altitude_multiplier: float = 1.45  # Cap high-altitude amplification
@export var ground_effect_height: float = 100.0  # Calmer air near ground
@export var shake_factor: float = 0.0001  # Multiplier for shake intensity
@export var max_shake_amount: float = 0.9  # Clamp shake so high-speed flight stays controllable
@export var impulse_threshold: float = 0.7  # Only apply force when noise is above this
@export var gust_rate_hz: float = 3.0       # Average impulses per second per body
@export var gust_impulse_scale: float = 30.0 # Scales impulse magnitude
@export var lateral_scale: float = 1.2      # Emphasize horizontal components
@export var vertical_scale: float = 0.2     # De-emphasize vertical component
@export var min_interval_s: float = 0.05    # Minimum time between impulses per body
@export var velocity_reference_speed_mps: float = 90.0  # Speed where turbulence reaches full strength
@export var min_velocity_factor: float = 0.3            # Preserve some movement at low speed
@export var max_velocity_factor: float = 1.0            # Prevent high-speed over-amplification
@export var debug_output: bool = false  # Toggle debug messages

# Audio settings
@export var wind_sound: AudioStream
@export var max_volume_db: float = -15.0
@export var min_volume_db: float = -35.0

var noise: FastNoiseLite
var time_offset: float = 0.0
var audio_players: Dictionary = {}  # One audio player per aircraft
var debug_timer: float = 0.0
var _last_impulse_time: Dictionary = {}  # body_id -> last impulse time

func _ready():
	noise = FastNoiseLite.new()
	noise.frequency = turbulence_scale
	noise.seed = randi()
	print("ContinuousTurbulence system initialized")
	print("Wind sound: ", wind_sound)

func _process(delta):
	time_offset += delta * time_speed
	debug_timer += delta
	
	# Find all aircraft automatically
	var bodies = []
	bodies = get_tree().get_nodes_in_group("weather_affected")
	
	# Auto-detect aircraft (fallback if no group assignment)
	if bodies.is_empty():
		bodies = find_aircraft_automatically()
	
	# Debug output every 2 seconds
	if debug_output and debug_timer > 2.0:
		print("Turbulence system found ", bodies.size(), " aircraft")
		debug_timer = 0.0
	
	for body in bodies:
		if body is RigidBody3D:
			apply_continuous_turbulence(body, delta)

func find_aircraft_automatically() -> Array:
	var aircraft = []
	
	for node in get_tree().current_scene.get_children():
		find_aircraft_recursive(node, aircraft)
	
	if debug_output and not aircraft.is_empty():
		print("Auto-detected aircraft: ", aircraft)
	
	return aircraft

func find_aircraft_recursive(node: Node, aircraft_array: Array):
	# Check if this node is an aircraft
	if node is RigidBody3D:
		# Method A: Check for Aircraft class name
		if node.get_script() and node.get_script().get_global_name() == "Aircraft":
			aircraft_array.append(node)
			node.add_to_group("weather_affected")
			if debug_output:
				print("Found Aircraft by class: ", node.name)
		
		# Method B: Check for aircraft-like properties
		elif node.has_method("get") and (node.get("air_velocity") != null or node.get("modules") != null):
			aircraft_array.append(node)
			node.add_to_group("weather_affected")
			if debug_output:
				print("Found Aircraft by properties: ", node.name)
	
	# Recursively check children
	for child in node.get_children():
		find_aircraft_recursive(child, aircraft_array)

func apply_continuous_turbulence(body: RigidBody3D, delta: float):
	var pos = body.global_position
	
	# Define aerodynamic points on the aircraft
	var wing_span = 20.0
	var fuselage_length = 15.0
	
	# Sample turbulence at multiple points
	var left_wing_pos = pos + body.global_transform.basis.x * -wing_span/2
	var right_wing_pos = pos + body.global_transform.basis.x * wing_span/2
	var nose_pos = pos + body.global_transform.basis.z * -fuselage_length/2
	var tail_pos = pos + body.global_transform.basis.z * fuselage_length/2
	var center_pos = pos
	
	# Get velocity for scaling
	var velocity = body.linear_velocity.length()
	var velocity_factor = _get_velocity_factor(velocity)
	
	# Apply impulse-based turbulence at each point (emphasize roll over yaw)
	apply_turbulence_at_point(body, left_wing_pos, body.global_transform.basis.x * -wing_span/2, velocity_factor, 0.8)  # Strong wing effects
	apply_turbulence_at_point(body, right_wing_pos, body.global_transform.basis.x * wing_span/2, velocity_factor, 0.8)   # Strong wing effects
	apply_turbulence_at_point(body, nose_pos, body.global_transform.basis.z * -fuselage_length/2, velocity_factor, 0.1)  # Weak nose
	apply_turbulence_at_point(body, tail_pos, body.global_transform.basis.z * fuselage_length/2, velocity_factor, 0.2)   # Weak tail
	apply_turbulence_at_point(body, center_pos, Vector3.ZERO, velocity_factor, 0.15)  # Weak center
	
	# Calculate average intensity for audio and shake
	var avg_intensity = (
		get_turbulence_intensity_at_position(left_wing_pos) +
		get_turbulence_intensity_at_position(right_wing_pos) +
		get_turbulence_intensity_at_position(nose_pos) +
		get_turbulence_intensity_at_position(tail_pos) +
		get_turbulence_intensity_at_position(center_pos)
	) / 5.0
	
	# Add shake based on average intensity
	if body.has_method("add_shake"):
		var shake_amount = minf(avg_intensity * shake_factor * velocity_factor, max_shake_amount)
		body.add_shake(shake_amount, 0.1)
		if debug_output and debug_timer < 0.1:
			print("Applying shake: ", shake_amount, " to ", body.name)
	
	# Handle wind audio
	update_wind_audio(body, avg_intensity)

func apply_turbulence_at_point(body: RigidBody3D, world_pos: Vector3, local_offset: Vector3, velocity_factor: float, strength_multiplier: float):
	# Sample turbulence intensity at this specific point
	var noise_value = (noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z + time_offset) + 1.0) * 0.5
	var intensity = base_intensity + noise_value * max_intensity
	
	# Altitude effects
	var altitude_multiplier = _get_altitude_multiplier(world_pos.y)
	var ground_factor = 1.0
	if world_pos.y < ground_effect_height:
		ground_factor = world_pos.y / ground_effect_height
	
	intensity *= altitude_multiplier * ground_factor * strength_multiplier
	
	# Poisson-like triggering: chance based on gust_rate and delta time
	var body_id = body.get_instance_id()
	var now = Time.get_ticks_msec() * 0.001
	var last_t = _last_impulse_time.get(body_id, 0.0)
	var dt_since = now - last_t
	var fire_random = randf() < clamp(gust_rate_hz * get_process_delta_time(), 0.0, 0.8)
	var time_ok = dt_since >= min_interval_s
	
	# Create impulse-style turbulence with horizontal bias
	if (noise_value > impulse_threshold and time_ok and fire_random):
		_last_impulse_time[body_id] = now
		var impulse_strength = (noise_value - impulse_threshold) / max(1e-3, (1.0 - impulse_threshold))
		
		# Separate lateral and vertical samples; de-emphasize vertical
		var lateral = Vector3(
			noise.get_noise_3d(world_pos.x + 2000, world_pos.y, world_pos.z + time_offset),
			0.0,
			noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z + 2000 + time_offset)
		)
		var vertical = Vector3(0.0, noise.get_noise_3d(world_pos.x, world_pos.y + 2000, world_pos.z + time_offset), 0.0)
		var dir = (lateral * lateral_scale + vertical * vertical_scale).normalized()
		
		# Scale by configured gust impulse scale
		var magnitude = intensity * impulse_strength * velocity_factor * gust_impulse_scale
		var turbulence_impulse = dir * magnitude
		
		# Apply as impulse for sharp jolts
		body.apply_impulse(turbulence_impulse, local_offset)
		
		if debug_output and debug_timer < 0.1:
			print("Impulse at offset ", local_offset, ": ", turbulence_impulse)

func update_wind_audio(body: RigidBody3D, intensity: float):
	if not wind_sound:
		return
	
	# Get or create audio player for this body
	var body_id = body.get_instance_id()
	if not body_id in audio_players:
		var audio_player = AudioStreamPlayer3D.new()
		# Don't attach to aircraft - keep it as a world object
		get_tree().current_scene.add_child(audio_player)
		audio_player.stream = wind_sound
		
		# Force loop mode if it's a WAV file
		if wind_sound is AudioStreamWAV:
			wind_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
		
		# Set up for external camera listening
		audio_player.max_distance = 1000.0  # Very large range for wind
		audio_player.unit_size = 200.0      # Large unit size for consistent volume
		audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		audio_player.add_to_group("3d_audio")  # Add to group for audio management
		audio_player.play()  # Start playing immediately
		audio_players[body_id] = audio_player
		
		if debug_output:
			print("Created wind audio player for ", body.name, " - Stream: ", wind_sound)
	
	var audio_player = audio_players[body_id]
	
	# Position wind audio at the active camera for external views
	var active_camera = get_active_camera()
	if active_camera:
		# For external cameras, position wind at camera
		audio_player.global_position = active_camera.global_position
	else:
		# Fallback to aircraft position
		audio_player.global_position = body.global_position
	
	# Make sure it's playing
	if not audio_player.playing:
		audio_player.play()
		if debug_output:
			print("Restarting wind audio for ", body.name)
	
	# Update volume and pitch based on turbulence intensity
	var volume_factor = clamp(intensity / max_intensity, 0.0, 1.0)
	audio_player.volume_db = lerp(min_volume_db, max_volume_db, volume_factor)
	audio_player.pitch_scale = 0.7 + volume_factor * 0.6  # 0.7 to 1.3 pitch range
	
	# Clean up audio players for destroyed bodies
	var valid_ids = []
	for id in audio_players.keys():
		if is_instance_valid(instance_from_id(id)):
			valid_ids.append(id)
	
	# Remove invalid entries
	for id in audio_players.keys():
		if not id in valid_ids:
			if is_instance_valid(audio_players[id]):
				audio_players[id].queue_free()
			audio_players.erase(id)

func get_active_camera() -> Camera3D:
	# Find the currently active camera
	var camera_controller = get_tree().get_first_node_in_group("camera_controller")
	if not camera_controller:
		return null
	
	# Check which camera is currently active
	if camera_controller.cockpit_camera and camera_controller.cockpit_camera.current:
		return camera_controller.cockpit_camera
	elif camera_controller.chase_camera and camera_controller.chase_camera.current:
		return camera_controller.chase_camera
	elif camera_controller.cinematic_camera and camera_controller.cinematic_camera.current:
		return camera_controller.cinematic_camera
	
	return null

func get_turbulence_intensity_at_position(pos: Vector3) -> float:
	# Utility function for other systems to query turbulence intensity
	var noise_value = (noise.get_noise_3d(pos.x, pos.y, pos.z + time_offset) + 1.0) * 0.5
	var intensity = base_intensity + noise_value * max_intensity
	
	var altitude_multiplier = _get_altitude_multiplier(pos.y)
	var ground_factor = 1.0
	if pos.y < ground_effect_height:
		ground_factor = pos.y / ground_effect_height
	
	return intensity * altitude_multiplier * ground_factor

func _get_velocity_factor(speed: float) -> float:
	return clamp(speed / maxf(velocity_reference_speed_mps, 1.0), min_velocity_factor, max_velocity_factor)

func _get_altitude_multiplier(world_y: float) -> float:
	var altitude_y = maxf(world_y, 0.0)
	return minf(1.0 + altitude_y * altitude_factor, max_altitude_multiplier)
