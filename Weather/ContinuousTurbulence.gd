# ContinuousTurbulence.gd - Continuous atmospheric turbulence system with impulse-based forces
extends Node3D
class_name ContinuousTurbulence

@export var base_intensity: float = 2.0
@export var max_intensity: float = 10.0
@export var turbulence_scale: float = 0.001  # How "big" the noise patterns are
@export var time_speed: float = 0.1
@export var update_interval_s: float = 0.05
@export var body_scan_interval_s: float = 0.5
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
@export var wind_sound: AudioStream = preload("res://Audio/wind_sound_cockpit.wav")
@export var air_rush_sound: AudioStream = preload("res://Audio/air rush sound.wav")
@export var stall_buffet_sound: AudioStream = preload("res://Audio/stall buffet sound.wav")
@export var layer_silence_db: float = -80.0
@export var turbulence_max_volume_db: float = -48.0
@export var turbulence_min_volume_db: float = -62.0
@export var turbulence_pitch_min: float = 0.7
@export var turbulence_pitch_max: float = 1.3
@export var air_rush_start_speed_mps: float = 20.0
@export var air_rush_full_speed_mps: float = 120.0
@export var air_rush_min_volume_db: float = -58.0
@export var air_rush_max_volume_db: float = -42.0
@export var air_rush_pitch_min: float = 0.72
@export var air_rush_pitch_max: float = 1.28
@export var air_rush_audible_threshold: float = 0.0
@export var air_rush_response_curve: float = 1.0
@export var air_rush_pitch_curve: float = 0.9
@export var stall_buffet_enabled: bool = false
@export var stall_buffet_start_severity: float = 0.05
@export var stall_buffet_full_severity: float = 0.55
@export var stall_buffet_min_volume_db: float = -28.0
@export var stall_buffet_max_volume_db: float = -4.0
@export var stall_buffet_pitch_min: float = 0.96
@export var stall_buffet_pitch_max: float = 1.12
@export var stall_buffet_audible_threshold: float = 0.06

var noise: FastNoiseLite
var time_offset: float = 0.0
var audio_players: Dictionary = {}  # body_id -> {gust, air_rush, stall_buffet}
var debug_timer: float = 0.0
var _last_impulse_time: Dictionary = {}  # body_id -> last impulse time
var _update_timer_s: float = 0.0
var _body_scan_timer_s: float = 0.0
var _cached_bodies: Array = []

func _ready():
	noise = FastNoiseLite.new()
	noise.frequency = turbulence_scale
	noise.seed = randi()
	print("ContinuousTurbulence system initialized")
	print("Wind sound layers: ", wind_sound, ", ", air_rush_sound, ", ", stall_buffet_sound)

func _process(delta):
	time_offset += delta * time_speed
	debug_timer += delta

	_update_timer_s += maxf(delta, 0.0)
	_body_scan_timer_s -= maxf(delta, 0.0)
	if _body_scan_timer_s <= 0.0:
		_refresh_cached_bodies()
		_body_scan_timer_s = maxf(body_scan_interval_s, 0.05)

	if _update_timer_s < maxf(update_interval_s, 0.01):
		return
	var step_delta: float = minf(_update_timer_s, 0.25)
	_update_timer_s = 0.0
	var active_camera := get_active_camera()
	var bodies := _cached_bodies
	
	# Debug output every 2 seconds
	if debug_output and debug_timer > 2.0:
		print("Turbulence system found ", bodies.size(), " aircraft")
		debug_timer = 0.0
	
	for body in bodies:
		if is_instance_valid(body) and body is RigidBody3D:
			apply_continuous_turbulence(body, step_delta, active_camera)

func _refresh_cached_bodies() -> void:
	_cached_bodies = get_tree().get_nodes_in_group("weather_affected")
	if _cached_bodies.is_empty():
		_cached_bodies = find_aircraft_automatically()

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

func apply_continuous_turbulence(body: RigidBody3D, delta: float, active_camera: Camera3D):
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

	# Apply impulse-based turbulence at each point and accumulate intensity
	var intensity_sum: float = 0.0
	intensity_sum += apply_turbulence_at_point(body, left_wing_pos, body.global_transform.basis.x * -wing_span/2, velocity_factor, 0.8, delta)
	intensity_sum += apply_turbulence_at_point(body, right_wing_pos, body.global_transform.basis.x * wing_span/2, velocity_factor, 0.8, delta)
	intensity_sum += apply_turbulence_at_point(body, nose_pos, body.global_transform.basis.z * -fuselage_length/2, velocity_factor, 0.1, delta)
	intensity_sum += apply_turbulence_at_point(body, tail_pos, body.global_transform.basis.z * fuselage_length/2, velocity_factor, 0.2, delta)
	intensity_sum += apply_turbulence_at_point(body, center_pos, Vector3.ZERO, velocity_factor, 0.15, delta)

	# Use accumulated intensity instead of re-sampling noise
	var avg_intensity = intensity_sum / 5.0
	
	# Add shake based on average intensity
	if body.has_method("add_shake"):
		var shake_amount = minf(avg_intensity * shake_factor * velocity_factor, max_shake_amount)
		body.add_shake(shake_amount, 0.1)
		if debug_output and debug_timer < 0.1:
			print("Applying shake: ", shake_amount, " to ", body.name)
	
	# Handle wind audio
	update_wind_audio(body, avg_intensity, active_camera)

func apply_turbulence_at_point(body: RigidBody3D, world_pos: Vector3, local_offset: Vector3, velocity_factor: float, strength_multiplier: float, step_delta: float) -> float:
	# Sample turbulence intensity at this specific point
	var noise_value = (noise.get_noise_3d(world_pos.x, world_pos.y, world_pos.z + time_offset) + 1.0) * 0.5
	var raw_intensity = base_intensity + noise_value * max_intensity

	# Altitude effects
	var altitude_multiplier = _get_altitude_multiplier(world_pos.y)
	var ground_factor = 1.0
	if world_pos.y < ground_effect_height:
		ground_factor = world_pos.y / ground_effect_height

	var intensity = raw_intensity * altitude_multiplier * ground_factor
	var point_intensity = intensity * strength_multiplier
	
	# Poisson-like triggering: chance based on gust_rate and delta time
	var body_id = body.get_instance_id()
	var now = Time.get_ticks_msec() * 0.001
	var last_t = _last_impulse_time.get(body_id, 0.0)
	var dt_since = now - last_t
	var fire_random = randf() < clamp(gust_rate_hz * maxf(step_delta, 0.0), 0.0, 0.8)
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
		var magnitude = point_intensity * impulse_strength * velocity_factor * gust_impulse_scale
		var turbulence_impulse = dir * magnitude
		
		# Apply as impulse for sharp jolts
		body.apply_impulse(turbulence_impulse, local_offset)
		
		if debug_output and debug_timer < 0.1:
			print("Impulse at offset ", local_offset, ": ", turbulence_impulse)

	return intensity  # Return unscaled intensity for averaging

func update_wind_audio(body: RigidBody3D, intensity: float, active_camera: Camera3D):
	if not _is_aircraft_audio_target(body, active_camera):
		_stop_audio_for_body(body)
		_cleanup_invalid_audio_players()
		return

	var player_set := _ensure_audio_players(body)
	if player_set.is_empty():
		return

	var audio_position := _get_audio_anchor_position(body)
	for player in player_set.values():
		if player is AudioStreamPlayer3D:
			player.global_position = audio_position
			if not player.playing:
				player.play()

	var turbulence_factor: float = clampf(intensity / maxf(max_intensity, 0.01), 0.0, 1.0)
	var forward_airspeed: float = _get_body_forward_airspeed(body)
	var air_rush_factor: float = _smoothstep(
		air_rush_start_speed_mps,
		maxf(air_rush_full_speed_mps, air_rush_start_speed_mps + 0.01),
		forward_airspeed
	)
	var stall_severity: float = _get_body_stall_severity(body)
	var stall_factor: float = 0.0
	if stall_buffet_enabled:
		stall_factor = _smoothstep(
			stall_buffet_start_severity,
			maxf(stall_buffet_full_severity, stall_buffet_start_severity + 0.001),
			stall_severity
		)

	_update_layer(
		player_set.get("gust") as AudioStreamPlayer3D,
		turbulence_min_volume_db,
		turbulence_max_volume_db,
		turbulence_pitch_min,
		turbulence_pitch_max,
		turbulence_factor,
		0.0
	)
	_update_layer(
		player_set.get("air_rush") as AudioStreamPlayer3D,
		air_rush_min_volume_db,
		air_rush_max_volume_db,
		air_rush_pitch_min,
		air_rush_pitch_max,
		air_rush_factor,
		air_rush_audible_threshold,
		air_rush_response_curve,
		air_rush_pitch_curve
	)
	_update_layer(
		player_set.get("stall_buffet") as AudioStreamPlayer3D,
		stall_buffet_min_volume_db,
		stall_buffet_max_volume_db,
		stall_buffet_pitch_min,
		stall_buffet_pitch_max,
		stall_factor,
		stall_buffet_audible_threshold,
		0.9,
		1.0
	)

	_cleanup_invalid_audio_players()

func _ensure_audio_players(body: RigidBody3D) -> Dictionary:
	var body_id = body.get_instance_id()
	if body_id in audio_players:
		return audio_players[body_id]

	var player_set := {}
	player_set["gust"] = _create_audio_layer_player(wind_sound)
	player_set["air_rush"] = _create_audio_layer_player(air_rush_sound)
	player_set["stall_buffet"] = _create_audio_layer_player(stall_buffet_sound)
	audio_players[body_id] = player_set

	if body.has_signal("destroyed"):
		body.destroyed.connect(_on_body_destroyed.bind(body_id), CONNECT_ONE_SHOT)

	if debug_output:
		print("Created layered wind audio for ", body.name)

	return player_set

func _create_audio_layer_player(stream: AudioStream) -> AudioStreamPlayer3D:
	if stream == null:
		return null

	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD

	var audio_player := AudioStreamPlayer3D.new()
	var host: Node = get_tree().current_scene if get_tree() and get_tree().current_scene else self
	host.add_child(audio_player)
	audio_player.stream = stream
	audio_player.max_distance = 1000.0
	audio_player.unit_size = 200.0
	audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	audio_player.add_to_group("3d_audio")
	audio_player.volume_db = -80.0
	audio_player.pitch_scale = 1.0
	return audio_player

func _update_layer(audio_player: AudioStreamPlayer3D, min_db: float, max_db: float, min_pitch: float, max_pitch: float, factor: float, audible_threshold: float = 0.0, volume_curve: float = 0.75, pitch_curve: float = 0.75) -> void:
	if audio_player == null:
		return
	var clamped_factor: float = clampf(factor, 0.0, 1.0)
	if clamped_factor <= audible_threshold:
		audio_player.volume_db = layer_silence_db
		audio_player.pitch_scale = min_pitch
		return
	var normalized_factor: float = _smoothstep(
		audible_threshold,
		1.0,
		clamped_factor
	)
	var shaped_volume_factor: float = pow(normalized_factor, maxf(volume_curve, 0.01))
	var shaped_pitch_factor: float = pow(normalized_factor, maxf(pitch_curve, 0.01))
	audio_player.volume_db = lerpf(min_db, max_db, shaped_volume_factor)
	audio_player.pitch_scale = lerpf(min_pitch, max_pitch, shaped_pitch_factor)

func _get_body_forward_airspeed(body: RigidBody3D) -> float:
	if body == null:
		return 0.0
	var speed_variant = body.get("forward_air_speed") if body.has_method("get") else null
	if speed_variant != null:
		return maxf(float(speed_variant), 0.0)
	return maxf(body.linear_velocity.dot(body.global_transform.basis.z), 0.0)

func _get_body_stall_severity(body: RigidBody3D) -> float:
	if body == null:
		return 0.0
	var simple_aero := body.get_node_or_null("SimpleAero")
	if simple_aero and simple_aero.has_method("get_stall_severity"):
		return clampf(float(simple_aero.get_stall_severity()), 0.0, 1.0)
	return 0.0

func _is_aircraft_audio_target(body: RigidBody3D, active_camera: Camera3D) -> bool:
	if body == null or body.get_node_or_null("SimpleAero") == null:
		return false
	if not _is_body_audio_alive(body):
		return false
	if active_camera == null:
		return false
	var cockpit_camera := _get_body_cockpit_camera(body)
	if cockpit_camera == null:
		return false
	return active_camera == cockpit_camera and cockpit_camera.current

func _get_audio_anchor_position(body: RigidBody3D) -> Vector3:
	var cockpit_camera := _get_body_cockpit_camera(body)
	if cockpit_camera and cockpit_camera.current:
		return cockpit_camera.global_position
	return body.global_position

func _stop_audio_for_body(body: RigidBody3D) -> void:
	if body == null:
		return
	var body_id = body.get_instance_id()
	if not (body_id in audio_players):
		return
	var player_set: Dictionary = audio_players[body_id]
	for player in player_set.values():
		if player is AudioStreamPlayer3D and player.playing:
			player.stop()

func _free_audio_for_body_id(body_id: int) -> void:
	if not (body_id in audio_players):
		return
	var player_set: Dictionary = audio_players[body_id]
	for player in player_set.values():
		if player is AudioStreamPlayer3D and is_instance_valid(player):
			player.stop()
			player.queue_free()
	audio_players.erase(body_id)

func _on_body_destroyed(body_id: int) -> void:
	_free_audio_for_body_id(body_id)

func _cleanup_invalid_audio_players() -> void:
	var invalid_ids: Array = []
	for id in audio_players.keys():
		var body_instance = instance_from_id(id)
		if body_instance == null or not is_instance_valid(body_instance):
			invalid_ids.append(id)

	for id in invalid_ids:
		_free_audio_for_body_id(id)

func _is_body_audio_alive(body: RigidBody3D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var current_health_variant = body.get("current_health") if body.has_method("get") else null
	if current_health_variant != null and float(current_health_variant) <= 0.0:
		return false
	return true

func _get_body_cockpit_camera(body: RigidBody3D) -> Camera3D:
	if body == null:
		return null
	var body_camera_controller := body.get_node_or_null("CameraController")
	if body_camera_controller and body_camera_controller.cockpit_camera:
		return body_camera_controller.cockpit_camera
	var cockpit_tripod := body.get_node_or_null("CameraCockpit")
	if cockpit_tripod:
		return cockpit_tripod.find_child("Camera3D", true, false) as Camera3D
	return null

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func get_active_camera() -> Camera3D:
	# Multiple aircraft instantiate CameraController, so scan all of them for the active one.
	for camera_controller in get_tree().get_nodes_in_group("camera_controller"):
		if camera_controller == null:
			continue
		if camera_controller.has_method("get_current_camera"):
			var current_camera = camera_controller.get_current_camera()
			if is_instance_valid(current_camera) and current_camera is Camera3D and (current_camera as Camera3D).current:
				return current_camera as Camera3D
		if is_instance_valid(camera_controller.cockpit_camera) and camera_controller.cockpit_camera.current:
			return camera_controller.cockpit_camera
		elif is_instance_valid(camera_controller.chase_camera) and camera_controller.chase_camera.current:
			return camera_controller.chase_camera
		elif is_instance_valid(camera_controller.cinematic_camera) and camera_controller.cinematic_camera.current:
			return camera_controller.cinematic_camera

	for camera in get_tree().get_nodes_in_group("camera"):
		if is_instance_valid(camera) and camera is Camera3D and camera.current:
			return camera as Camera3D

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
