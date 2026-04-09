extends Node3D
class_name AudioManager3D

# Audio manager that handles 3D audio with interior/exterior filtering
# Muffles external sounds when inside aircraft, plays normally from external cameras

@export var aircraft: RigidBody3D
@export var camera_controller: CameraController
@export var interior_audio_bus: String = "Interior"
@export var bridge_audio_bus: String = "Bridge"
@export var exterior_audio_bus: String = "Master"
@export var cockpit_interior_sound: AudioStream
@export var cockpit_interior_bus: String = "Interior"
@export var cockpit_interior_volume_db: float = -10.0
@export var cockpit_interior_pitch_scale: float = 1.0
@export var cockpit_interior_silence_db: float = -80.0
@export var bridge_interior_sound: AudioStream = preload("res://Audio/wind_sound_cockpit.wav")
@export var bridge_interior_bus: String = "Interior"
@export var bridge_interior_min_volume_db: float = -24.0
@export var bridge_interior_max_volume_db: float = -14.0
@export var bridge_interior_pitch_min: float = 0.82
@export var bridge_interior_pitch_max: float = 1.0
@export var bridge_interior_silence_db: float = -80.0
@export var bridge_wind_idle_factor: float = 0.32
@export var bridge_wind_full_speed_mps: float = 10.0

# Audio filtering settings
@export var interior_lowpass_cutoff: float = 2300.0  # Hz - cockpit damping without over-muffling cannon transients
@export var interior_secondary_lowpass_cutoff: float = 1400.0  # Hz - gentler second-stage rolloff
@export var interior_highpass_cutoff: float = 60.0   # Hz - keep low engine body present
@export var interior_volume_reduction: float = -4.0  # dB reduction when inside
@export var interior_panning_strength: float = 0.18  # Keep cockpit sources mostly centered with only subtle stereo movement
@export var bridge_lowpass_cutoff: float = 3200.0  # Hz - stronger window damping than open-air deck audio
@export var bridge_secondary_lowpass_cutoff: float = 1850.0  # Hz - extra rolloff so the bridge feels enclosed
@export var bridge_highpass_cutoff: float = 140.0  # Hz - trim exterior low-frequency rumble through the glass
@export var bridge_volume_reduction: float = -5.5  # dB - windows should noticeably soften exterior sources
@export var exterior_panning_strength: float = 1.0

# Interior detection
@export var interior_radius: float = 5.0  # Radius around aircraft center for "inside" detection
@export var smoothing_factor: float = 5.0  # How quickly audio changes when entering/leaving

var is_inside_aircraft: bool = false
var current_audio_bus: String = "Master"
var audio_effect: AudioEffectLowPassFilter
var audio_effect_secondary: AudioEffectLowPassFilter
var audio_effect_high: AudioEffectHighPassFilter
var audio_effect_volume: AudioEffectAmplify
var bridge_audio_effect: AudioEffectLowPassFilter
var bridge_audio_effect_secondary: AudioEffectLowPassFilter
var bridge_audio_effect_high: AudioEffectHighPassFilter
var bridge_audio_effect_volume: AudioEffectAmplify
var cockpit_interior_player: AudioStreamPlayer
var bridge_interior_player: AudioStreamPlayer
var carrier: Node3D
var _aircraft_audio_destroyed: bool = false

func _ready():
	add_to_group("audio_manager_3d")

	if not aircraft:
		aircraft = get_parent() as RigidBody3D
		if not aircraft:
			aircraft = get_tree().get_first_node_in_group("aircraft")

	if not camera_controller:
		camera_controller = get_parent().find_child("CameraController", true, false)
		if not camera_controller:
			camera_controller = get_tree().get_first_node_in_group("camera_controller")

	if not aircraft or not camera_controller:
		return

	carrier = _resolve_carrier()
	_connect_aircraft_audio_signals()
	create_audio_buses()
	create_cockpit_interior_player()
	create_bridge_interior_player()
	setup_audio_effects()

	# Defer initial bus switch to let all audio sources initialize first
	call_deferred("_apply_initial_audio_bus")
	# Also defer a forced sync one frame later to catch any late-created sources
	call_deferred("_sync_dynamic_audio_sources")
	call_deferred("_sync_dynamic_audio_sources")

func _apply_initial_audio_bus() -> void:
	var current_camera: Camera3D = get_current_camera()
	if not _is_authoritative_for_camera(current_camera):
		return

	# Apply initial bus based on which camera is already active
	if is_bridge_camera_active():
		switch_to_bridge_audio()
	elif is_cockpit_camera_active():
		switch_to_interior_audio()
	else:
		switch_to_exterior_audio()

func create_cockpit_interior_player():
	if not cockpit_interior_sound:
		return

	if cockpit_interior_sound is AudioStreamWAV:
		cockpit_interior_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD

	cockpit_interior_player = AudioStreamPlayer.new()
	cockpit_interior_player.name = "CockpitInteriorLoop"
	cockpit_interior_player.bus = cockpit_interior_bus
	cockpit_interior_player.stream = cockpit_interior_sound
	cockpit_interior_player.pitch_scale = cockpit_interior_pitch_scale
	cockpit_interior_player.volume_db = cockpit_interior_silence_db
	add_child(cockpit_interior_player)
	cockpit_interior_player.play()

func create_bridge_interior_player():
	if not bridge_interior_sound:
		return

	if bridge_interior_sound is AudioStreamWAV:
		bridge_interior_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD

	bridge_interior_player = AudioStreamPlayer.new()
	bridge_interior_player.name = "BridgeInteriorLoop"
	bridge_interior_player.bus = bridge_interior_bus
	bridge_interior_player.stream = bridge_interior_sound
	bridge_interior_player.pitch_scale = bridge_interior_pitch_min
	bridge_interior_player.volume_db = bridge_interior_silence_db
	add_child(bridge_interior_player)
	bridge_interior_player.play()

func create_audio_buses():
	# Create interior bus as child of Master
	if AudioServer.get_bus_index(interior_audio_bus) == -1:
		AudioServer.add_bus(1)  # Add after Master bus
		AudioServer.set_bus_name(1, interior_audio_bus)
		AudioServer.set_bus_send(1, "Master")

	# Create bridge bus as child of Master
	if AudioServer.get_bus_index(bridge_audio_bus) == -1:
		AudioServer.add_bus(2)  # Add after Interior bus
		AudioServer.set_bus_name(2, bridge_audio_bus)
		AudioServer.set_bus_send(2, "Master")

func setup_audio_effects():
	# Create low-pass filter for muffled interior sound
	audio_effect = AudioEffectLowPassFilter.new()
	audio_effect.cutoff_hz = interior_lowpass_cutoff
	audio_effect.resonance = 0.5

	# A second low-pass stage makes the cockpit coloration much more obvious.
	audio_effect_secondary = AudioEffectLowPassFilter.new()
	audio_effect_secondary.cutoff_hz = interior_secondary_lowpass_cutoff
	audio_effect_secondary.resonance = 0.45

	# Create high-pass filter to remove low rumble
	audio_effect_high = AudioEffectHighPassFilter.new()
	audio_effect_high.cutoff_hz = interior_highpass_cutoff

	# Create volume effect for interior reduction
	audio_effect_volume = AudioEffectAmplify.new()
	audio_effect_volume.volume_db = interior_volume_reduction

	# Bridge audio: window damping that is audible, but still a bit more open than cockpit view.
	bridge_audio_effect = AudioEffectLowPassFilter.new()
	bridge_audio_effect.cutoff_hz = bridge_lowpass_cutoff
	bridge_audio_effect.resonance = 0.4

	bridge_audio_effect_secondary = AudioEffectLowPassFilter.new()
	bridge_audio_effect_secondary.cutoff_hz = bridge_secondary_lowpass_cutoff
	bridge_audio_effect_secondary.resonance = 0.35

	bridge_audio_effect_high = AudioEffectHighPassFilter.new()
	bridge_audio_effect_high.cutoff_hz = bridge_highpass_cutoff

	# Bridge volume reduction keeps the room feeling separated from the deck.
	bridge_audio_effect_volume = AudioEffectAmplify.new()
	bridge_audio_effect_volume.volume_db = bridge_volume_reduction

func _process(delta):
	# Get current camera - this works even without an aircraft
	var current_camera: Camera3D = get_current_camera()
	var has_authority: bool = _is_authoritative_for_camera(current_camera)

	_update_cockpit_interior_player(delta, has_authority and is_cockpit_camera_active())
	_update_bridge_interior_player(delta, has_authority and is_bridge_camera_active())

	# Prevent multiple aircraft audio managers from fighting over the same global buses.
	if not has_authority:
		return

	if current_camera:
		# Check bridge camera separately - it gets its own audio environment
		if camera_controller and camera_controller.bridge_camera == current_camera:
			if current_audio_bus != bridge_audio_bus:
				switch_to_bridge_audio()
		else:
			# For all other cameras (including free look), check if inside aircraft
			var is_inside = false
			if aircraft:
				is_inside = is_camera_inside_aircraft(current_camera)

			# Apply correct audio bus
			if is_inside:
				if current_audio_bus != interior_audio_bus:
					switch_to_interior_audio()
			else:
				if current_audio_bus != exterior_audio_bus:
					switch_to_exterior_audio()
	else:
		# No camera active - default to exterior audio
		if current_audio_bus != exterior_audio_bus:
			switch_to_exterior_audio()

	# Always sync dynamic audio sources every frame to catch newly created ones
	_sync_dynamic_audio_sources()

func is_cockpit_camera_active() -> bool:
	if not camera_controller or not camera_controller.cockpit_camera:
		return false

	return camera_controller.cockpit_camera.current and _is_aircraft_audio_alive()

func is_bridge_camera_active() -> bool:
	if not camera_controller or not camera_controller.bridge_camera:
		return false

	return camera_controller.bridge_camera.current

func _update_cockpit_interior_player(delta: float, cockpit_active: bool):
	if not cockpit_interior_player:
		return
	if not _is_aircraft_audio_alive():
		cockpit_interior_player.volume_db = cockpit_interior_silence_db
		if cockpit_interior_player.playing:
			cockpit_interior_player.stop()
		return

	var target_volume = cockpit_interior_volume_db if cockpit_active else cockpit_interior_silence_db
	var blend = clamp(delta * smoothing_factor, 0.0, 1.0)
	cockpit_interior_player.volume_db = lerpf(cockpit_interior_player.volume_db, target_volume, blend)

	if abs(cockpit_interior_player.volume_db - target_volume) < 0.05:
		cockpit_interior_player.volume_db = target_volume

	if not cockpit_interior_player.playing:
		cockpit_interior_player.play()

func _update_bridge_interior_player(delta: float, bridge_active: bool):
	if not bridge_interior_player:
		return

	var target_volume: float = bridge_interior_silence_db
	var target_pitch: float = bridge_interior_pitch_min
	if bridge_active:
		var wind_factor: float = _get_bridge_wind_factor()
		target_volume = lerpf(bridge_interior_min_volume_db, bridge_interior_max_volume_db, wind_factor)
		target_pitch = lerpf(bridge_interior_pitch_min, bridge_interior_pitch_max, wind_factor)

	var blend = clamp(delta * smoothing_factor, 0.0, 1.0)
	bridge_interior_player.volume_db = lerpf(bridge_interior_player.volume_db, target_volume, blend)
	bridge_interior_player.pitch_scale = lerpf(bridge_interior_player.pitch_scale, target_pitch, blend)

	if abs(bridge_interior_player.volume_db - target_volume) < 0.05:
		bridge_interior_player.volume_db = target_volume
	if abs(bridge_interior_player.pitch_scale - target_pitch) < 0.01:
		bridge_interior_player.pitch_scale = target_pitch

	if not bridge_interior_player.playing:
		bridge_interior_player.play()

func _connect_aircraft_audio_signals():
	if not aircraft or not aircraft.has_signal("destroyed"):
		return
	if not aircraft.destroyed.is_connected(_on_aircraft_destroyed):
		aircraft.destroyed.connect(_on_aircraft_destroyed)

func _on_aircraft_destroyed():
	_aircraft_audio_destroyed = true
	if cockpit_interior_player:
		cockpit_interior_player.volume_db = cockpit_interior_silence_db
		if cockpit_interior_player.playing:
			cockpit_interior_player.stop()

func _is_aircraft_audio_alive() -> bool:
	if _aircraft_audio_destroyed or aircraft == null or not is_instance_valid(aircraft):
		return false
	var current_health_variant = aircraft.get("current_health") if aircraft.has_method("get") else null
	if current_health_variant != null and float(current_health_variant) <= 0.0:
		return false
	return true

var last_camera_name: String = ""

func get_current_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport == null:
		return null

	var current_camera := viewport.get_camera_3d()
	var camera_name: String = "None"

	if current_camera != null:
		camera_name = current_camera.name
		if camera_controller:
			if camera_controller.cockpit_camera == current_camera:
				camera_name = "Cockpit"
			elif camera_controller.chase_camera == current_camera:
				camera_name = "Chase"
			elif camera_controller.cinematic_camera == current_camera:
				camera_name = "Cinematic"
			elif camera_controller.bridge_camera == current_camera:
				camera_name = "Bridge"
	
	# Only print when camera changes
	if camera_name != last_camera_name:
		pass
		last_camera_name = camera_name
	
	return current_camera

func is_camera_inside_aircraft(camera: Camera3D) -> bool:
	if not aircraft or not camera:
		return false

	if camera.name == "FreeCamera" or camera.name == "DestroyedPlaneLingerCamera":
		return false

	# Treat the explicit cockpit camera as inside regardless of its offset from the origin.
	if camera_controller:
		if camera_controller.cockpit_camera == camera:
			return true
		# Bridge camera is NOT inside aircraft - it gets its own audio environment
		if camera_controller.bridge_camera == camera:
			return false
		if camera_controller.chase_camera == camera or camera_controller.cinematic_camera == camera:
			return false

	# Fallback for any other custom camera placement.
	var distance = camera.global_position.distance_to(aircraft.global_position)
	var is_inside = distance <= interior_radius

	# Debug output
	if is_inside != is_inside_aircraft:  # Only print when state changes
		pass

	return is_inside

func switch_to_interior_audio():
	if current_audio_bus == interior_audio_bus:
		return
	
	current_audio_bus = interior_audio_bus

	# Clear bridge effects when transitioning away from bridge processing.
	var bridge_bus_index = AudioServer.get_bus_index(bridge_audio_bus)
	if bridge_bus_index != -1:
		while AudioServer.get_bus_effect_count(bridge_bus_index) > 0:
			AudioServer.remove_bus_effect(bridge_bus_index, 0)
	
	# Apply audio effects to interior bus
	var bus_index = AudioServer.get_bus_index(interior_audio_bus)
	if bus_index != -1:
		while AudioServer.get_bus_effect_count(bus_index) > 0:
			AudioServer.remove_bus_effect(bus_index, 0)
		# Add effects in order: High-pass -> Low-pass -> Low-pass -> Volume
		AudioServer.add_bus_effect(bus_index, audio_effect_high)
		AudioServer.add_bus_effect(bus_index, audio_effect)
		AudioServer.add_bus_effect(bus_index, audio_effect_secondary)
		AudioServer.add_bus_effect(bus_index, audio_effect_volume)

	# Switch all 3D audio sources to interior bus
	switch_audio_sources_to_bus(interior_audio_bus)

	pass

func switch_to_bridge_audio():
	if current_audio_bus == bridge_audio_bus:
		return

	current_audio_bus = bridge_audio_bus

	# Clear effects from interior bus first
	var interior_bus_index = AudioServer.get_bus_index(interior_audio_bus)
	if interior_bus_index != -1:
		while AudioServer.get_bus_effect_count(interior_bus_index) > 0:
			AudioServer.remove_bus_effect(interior_bus_index, 0)

	# Apply light audio effects to bridge bus for canopy damping
	var bridge_bus_index = AudioServer.get_bus_index(bridge_audio_bus)
	if bridge_bus_index != -1:
		while AudioServer.get_bus_effect_count(bridge_bus_index) > 0:
			AudioServer.remove_bus_effect(bridge_bus_index, 0)
		# Add effects in order: High-pass -> Low-pass -> Low-pass -> Volume
		AudioServer.add_bus_effect(bridge_bus_index, bridge_audio_effect_high)
		AudioServer.add_bus_effect(bridge_bus_index, bridge_audio_effect)
		AudioServer.add_bus_effect(bridge_bus_index, bridge_audio_effect_secondary)
		AudioServer.add_bus_effect(bridge_bus_index, bridge_audio_effect_volume)

	# Switch all 3D audio sources to bridge bus
	switch_audio_sources_to_bus(bridge_audio_bus)

	pass

func switch_to_exterior_audio():
	if current_audio_bus == exterior_audio_bus:
		return

	current_audio_bus = exterior_audio_bus

	# Clear effects from interior bus
	var interior_bus_index = AudioServer.get_bus_index(interior_audio_bus)
	if interior_bus_index != -1:
		while AudioServer.get_bus_effect_count(interior_bus_index) > 0:
			AudioServer.remove_bus_effect(interior_bus_index, 0)

	# Clear effects from bridge bus
	var bridge_bus_index = AudioServer.get_bus_index(bridge_audio_bus)
	if bridge_bus_index != -1:
		while AudioServer.get_bus_effect_count(bridge_bus_index) > 0:
			AudioServer.remove_bus_effect(bridge_bus_index, 0)

	# Switch all 3D audio sources to master bus
	switch_audio_sources_to_bus(exterior_audio_bus)
	
	pass

func switch_audio_sources_to_bus(bus_name: String):
	# Find all AudioStreamPlayer3D nodes in the scene and switch their bus
	var audio_players = get_tree().get_nodes_in_group("3d_audio")

	for player in audio_players:
		if player is AudioStreamPlayer3D:
			_apply_3d_audio_settings(player, bus_name)
	
	# Also find audio players attached to aircraft modules
	if aircraft:
		switch_aircraft_audio_sources(aircraft, bus_name)

func _sync_dynamic_audio_sources():
	var current_camera: Camera3D = get_current_camera()
	if not _is_authoritative_for_camera(current_camera):
		return
	switch_audio_sources_to_bus(current_audio_bus)

func switch_aircraft_audio_sources(node: Node, bus_name: String):
	# Recursively find and switch all AudioStreamPlayer3D nodes
	for child in node.get_children():
		if child is AudioStreamPlayer3D:
			_apply_3d_audio_settings(child, bus_name)
		else:
			switch_aircraft_audio_sources(child, bus_name)

func _apply_3d_audio_settings(player: AudioStreamPlayer3D, bus_name: String):
	if player == null:
		return
	player.bus = bus_name
	# Bridge uses full stereo panning like exterior (not cockpit's muffled panning)
	player.panning_strength = interior_panning_strength if bus_name == interior_audio_bus else exterior_panning_strength

# Public methods for manual control
func force_interior_audio():
	switch_to_interior_audio()

func force_exterior_audio():
	switch_to_exterior_audio()

func is_currently_inside() -> bool:
	return is_inside_aircraft

func _resolve_carrier() -> Node3D:
	if camera_controller and camera_controller.bridge_script and is_instance_valid(camera_controller.bridge_script):
		var candidate := camera_controller.bridge_script.get_parent()
		if candidate is Node3D and candidate.is_in_group("carrier"):
			return candidate as Node3D

	var carrier_node := get_tree().get_first_node_in_group("carrier") if get_tree() else null
	return carrier_node as Node3D

func _get_bridge_wind_factor() -> float:
	if carrier == null or not is_instance_valid(carrier):
		carrier = _resolve_carrier()

	var carrier_speed_mps: float = 0.0
	if carrier and carrier.has_method("get_velocity_vector"):
		var velocity_variant = carrier.call("get_velocity_vector")
		if velocity_variant is Vector3:
			carrier_speed_mps = (velocity_variant as Vector3).length()

	var speed_factor: float = clampf(carrier_speed_mps / maxf(bridge_wind_full_speed_mps, 0.01), 0.0, 1.0)
	speed_factor = speed_factor * speed_factor * (3.0 - 2.0 * speed_factor)
	return clampf(maxf(bridge_wind_idle_factor, speed_factor), 0.0, 1.0)

func _is_authoritative_for_camera(camera: Camera3D) -> bool:
	if camera == null:
		return false

	var tree: SceneTree = get_tree()
	if tree == null:
		return false

	var managers: Array = tree.get_nodes_in_group("audio_manager_3d")
	var best_rank: float = INF
	var best_id: int = 2147483647
	for n in managers:
		if n is AudioManager3D and is_instance_valid(n):
			var mgr: AudioManager3D = n as AudioManager3D
			var rank: float = mgr._authority_rank_for_camera(camera)
			var mgr_id: int = int(mgr.get_instance_id())
			if rank < best_rank or (is_equal_approx(rank, best_rank) and mgr_id < best_id):
				best_rank = rank
				best_id = mgr_id

	return int(get_instance_id()) == best_id

func _authority_rank_for_camera(camera: Camera3D) -> float:
	if camera == null:
		return INF

	if camera_controller:
		if camera_controller.cockpit_camera == camera:
			return 0.0
		if camera_controller.chase_camera == camera:
			return 1.0
		if camera_controller.cinematic_camera == camera:
			return 2.0
		if camera_controller.bridge_camera == camera:
			return 3.0

	if aircraft and _node_is_same_or_descendant(camera, aircraft):
		return 4.0

	if aircraft and is_instance_valid(aircraft):
		return 1000.0 + camera.global_position.distance_to(aircraft.global_position)

	return INF

func _node_is_same_or_descendant(node: Node, root: Node) -> bool:
	var cur: Node = node
	while cur != null:
		if cur == root:
			return true
		cur = cur.get_parent()
	return false
