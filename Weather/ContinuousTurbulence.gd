# ContinuousTurbulence.gd - Continuous atmospheric turbulence system with impulse-based forces
extends Node3D
class_name ContinuousTurbulence

@export var base_intensity: float = 2.0
@export var max_intensity: float = 10.0
@export var turbulence_scale: float = 0.001  # How "big" the noise patterns are
@export var time_speed: float = 0.1
@export var altitude_factor: float = 0.001  # How altitude affects turbulence
@export var ground_effect_height: float = 100.0  # Calmer air near ground
@export var shake_factor: float = 0.0001  # Multiplier for shake intensity
@export var impulse_threshold: float = 0.7  # Only apply force when noise is above this
@export var debug_output: bool = false  # Toggle debug messages

# Audio settings
@export var wind_sound: AudioStream
@export var max_volume_db: float = -15.0
@export var min_volume_db: float = -35.0

var noise: FastNoiseLite
var time_offset: float = 0.0
var audio_players: Dictionary = {}  # One audio player per aircraft
var debug_timer: float = 0.0

func _ready():
	noise = FastNoiseLite.new()
	noise.frequency = turbulence_scale
	noise.seed = randi()
	print("ContinuousTurbulence system initialized")

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
	var velocity_factor = clamp(velocity / 50.0, 0.1, 2.0)
	
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
		var shake_amount = avg_intensity * shake_factor * velocity_factor
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
	var altitude_multiplier = 1.0 + (world_pos.y * altitude_factor)
	var ground_factor = 1.0
	if world_pos.y < ground_effect_height:
		ground_factor = world_pos.y / ground_effect_height
	
	intensity *= altitude_multiplier * ground_factor * strength_multiplier
	
	# Create impulse-style turbulence instead of continuous force
	if noise_value > impulse_threshold:
		var impulse_strength = (noise_value - impulse_threshold) / (1.0 - impulse_threshold)
		
		# Generate sharp, brief impulses using different noise samples
		var turbulence_impulse = Vector3(
			noise.get_noise_3d(world_pos.x + 2000, world_pos.y, world_pos.z + time_offset),
			noise.get_noise_3d(world_pos.x, world_pos.y + 2000, world_pos.z + time_offset) * 0.3,
			noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z + 2000 + time_offset)
		) * intensity * impulse_strength * velocity_factor * 20.0  # Higher force, less frequent
		
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
		body.add_child(audio_player)
		audio_player.stream = wind_sound
		
		# Force loop mode if it's a WAV file
		if wind_sound is AudioStreamWAV:
			wind_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
		
		audio_player.max_distance = 200.0
		audio_player.unit_size = 50.0
		audio_player.play()  # Start playing immediately
		audio_players[body_id] = audio_player
		
		if debug_output:
			print("Created audio player for ", body.name, " - Stream: ", wind_sound)
	
	var audio_player = audio_players[body_id]
	
	# Make sure it's playing
	if not audio_player.playing:
		audio_player.play()
		if debug_output:
			print("Restarting audio for ", body.name)
	
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

func get_turbulence_intensity_at_position(pos: Vector3) -> float:
	# Utility function for other systems to query turbulence intensity
	var noise_value = (noise.get_noise_3d(pos.x, pos.y, pos.z + time_offset) + 1.0) * 0.5
	var intensity = base_intensity + noise_value * max_intensity
	
	var altitude_multiplier = 1.0 + (pos.y * altitude_factor)
	var ground_factor = 1.0
	if pos.y < ground_effect_height:
		ground_factor = pos.y / ground_effect_height
	
	return intensity * altitude_multiplier * ground_factor
