extends Node3D
class_name AudioManager3D

# Audio manager that handles 3D audio with interior/exterior filtering
# Muffles external sounds when inside aircraft, plays normally from external cameras

@export var aircraft: RigidBody3D
@export var camera_controller: CameraController
@export var interior_audio_bus: String = "Interior"
@export var exterior_audio_bus: String = "Master"

# Audio filtering settings
@export var interior_lowpass_cutoff: float = 2000.0  # Hz - muffled sound
@export var interior_highpass_cutoff: float = 200.0  # Hz - remove low rumble
@export var interior_volume_reduction: float = -6.0  # dB reduction when inside

# Interior detection
@export var interior_radius: float = 5.0  # Radius around aircraft center for "inside" detection
@export var smoothing_factor: float = 5.0  # How quickly audio changes when entering/leaving

var is_inside_aircraft: bool = false
var current_audio_bus: String = "Master"
var audio_effect: AudioEffectLowPassFilter
var audio_effect_high: AudioEffectHighPassFilter
var audio_effect_volume: AudioEffectAmplify

func _ready():
	print("AudioManager3D starting up...")
	
	# Try to find aircraft and camera controller if not set
	if not aircraft:
		aircraft = get_parent() as RigidBody3D
		if not aircraft:
			# Look for aircraft in the scene
			aircraft = get_tree().get_first_node_in_group("aircraft")
	
	if not camera_controller:
		camera_controller = get_parent().find_child("CameraController", true, false)
		if not camera_controller:
			# Look for camera controller in the scene
			camera_controller = get_tree().get_first_node_in_group("camera_controller")
	
	print("Aircraft: ", aircraft)
	print("Camera Controller: ", camera_controller)
	
	if not aircraft:
		print("ERROR: No aircraft found!")
		return
	if not camera_controller:
		print("ERROR: No camera controller found!")
		return
	
	# Create audio buses if they don't exist
	create_audio_buses()
	
	# Set up audio effects
	setup_audio_effects()
	
	# Start with exterior audio
	switch_to_exterior_audio()
	
	print("AudioManager3D ready!")

func create_audio_buses():
	# Create interior bus as child of Master
	if AudioServer.get_bus_index(interior_audio_bus) == -1:
		AudioServer.add_bus(1)  # Add after Master bus
		AudioServer.set_bus_name(1, interior_audio_bus)
		AudioServer.set_bus_send(1, "Master")
		print("Created interior audio bus: ", interior_audio_bus)
	else:
		print("Interior audio bus already exists: ", interior_audio_bus)

func setup_audio_effects():
	# Create low-pass filter for muffled interior sound
	audio_effect = AudioEffectLowPassFilter.new()
	audio_effect.cutoff_hz = interior_lowpass_cutoff
	audio_effect.resonance = 0.5
	
	# Create high-pass filter to remove low rumble
	audio_effect_high = AudioEffectHighPassFilter.new()
	audio_effect_high.cutoff_hz = interior_highpass_cutoff
	
	# Create volume effect for interior reduction
	audio_effect_volume = AudioEffectAmplify.new()
	audio_effect_volume.volume_db = interior_volume_reduction

func _process(delta):
	if not aircraft or not camera_controller:
		return
	
	# Check if current camera is inside the aircraft
	var current_camera = get_current_camera()
	if not current_camera:
		return
	
	var is_inside = is_camera_inside_aircraft(current_camera)
	
	# Smoothly transition between interior/exterior audio
	if is_inside != is_inside_aircraft:
		is_inside_aircraft = is_inside
		if is_inside:
			switch_to_interior_audio()
		else:
			switch_to_exterior_audio()

var last_camera_name: String = ""

func get_current_camera() -> Camera3D:
	if not camera_controller:
		return null
	
	# Check which camera is currently active
	var current_camera: Camera3D = null
	var camera_name: String = ""
	
	if camera_controller.cockpit_camera and camera_controller.cockpit_camera.current:
		current_camera = camera_controller.cockpit_camera
		camera_name = "Cockpit"
	elif camera_controller.chase_camera and camera_controller.chase_camera.current:
		current_camera = camera_controller.chase_camera
		camera_name = "Chase"
	elif camera_controller.cinematic_camera and camera_controller.cinematic_camera.current:
		current_camera = camera_controller.cinematic_camera
		camera_name = "Cinematic"
	else:
		camera_name = "None"
	
	# Only print when camera changes
	if camera_name != last_camera_name:
		print("AudioManager3D: Camera changed to ", camera_name)
		last_camera_name = camera_name
	
	return current_camera

func is_camera_inside_aircraft(camera: Camera3D) -> bool:
	if not aircraft or not camera:
		return false
	
	# Check if camera is within interior radius of aircraft center
	var distance = camera.global_position.distance_to(aircraft.global_position)
	var is_inside = distance <= interior_radius
	
	# Debug output
	if is_inside != is_inside_aircraft:  # Only print when state changes
		print("Camera distance: ", distance, " (radius: ", interior_radius, ") - Inside: ", is_inside)
	
	return is_inside

func switch_to_interior_audio():
	if current_audio_bus == interior_audio_bus:
		return
	
	current_audio_bus = interior_audio_bus
	
	# Apply audio effects to interior bus
	var bus_index = AudioServer.get_bus_index(interior_audio_bus)
	if bus_index != -1:
		# Add effects in order: High-pass -> Low-pass -> Volume
		AudioServer.add_bus_effect(bus_index, audio_effect_high)
		AudioServer.add_bus_effect(bus_index, audio_effect)
		AudioServer.add_bus_effect(bus_index, audio_effect_volume)
	
	# Switch all 3D audio sources to interior bus
	switch_audio_sources_to_bus(interior_audio_bus)
	
	print("Switched to interior audio (muffled)")

func switch_to_exterior_audio():
	if current_audio_bus == exterior_audio_bus:
		return
	
	current_audio_bus = exterior_audio_bus
	
	# Clear effects from interior bus
	var bus_index = AudioServer.get_bus_index(interior_audio_bus)
	if bus_index != -1:
		AudioServer.remove_bus_effect(bus_index, 0)  # Remove all effects
		AudioServer.remove_bus_effect(bus_index, 0)
		AudioServer.remove_bus_effect(bus_index, 0)
	
	# Switch all 3D audio sources to master bus
	switch_audio_sources_to_bus(exterior_audio_bus)
	
	print("Switched to exterior audio (normal)")

func switch_audio_sources_to_bus(bus_name: String):
	# Find all AudioStreamPlayer3D nodes in the scene and switch their bus
	var audio_players = get_tree().get_nodes_in_group("3d_audio")
	
	print("Switching ", audio_players.size(), " audio players to bus: ", bus_name)
	
	for player in audio_players:
		if player is AudioStreamPlayer3D:
			player.bus = bus_name
			print("  - Switched ", player.name, " to ", bus_name)
	
	# Also find audio players attached to aircraft modules
	if aircraft:
		switch_aircraft_audio_sources(aircraft, bus_name)

func switch_aircraft_audio_sources(node: Node, bus_name: String):
	# Recursively find and switch all AudioStreamPlayer3D nodes
	for child in node.get_children():
		if child is AudioStreamPlayer3D:
			child.bus = bus_name
		else:
			switch_aircraft_audio_sources(child, bus_name)

# Public methods for manual control
func force_interior_audio():
	switch_to_interior_audio()

func force_exterior_audio():
	switch_to_exterior_audio()

func is_currently_inside() -> bool:
	return is_inside_aircraft
