extends Node
class_name AudioDebug

# Debug script to help test the 3D audio system
# Add this to any scene to see audio state information

@export var audio_manager: AudioManager3D
@export var show_debug: bool = true

func _ready():
	if not audio_manager:
		# Try to find AudioManager3D in the scene
		audio_manager = get_tree().get_first_node_in_group("audio_manager")
		if not audio_manager:
			# Look for it as a child of aircraft
			var aircraft = get_tree().get_first_node_in_group("aircraft")
			if aircraft:
				audio_manager = aircraft.find_child("AudioManager3D", true, false)

func _process(_delta):
	if not audio_manager or not show_debug:
		return
	
	# Display audio state in the top-left corner
	var debug_text = "Audio Debug:\n"
	debug_text += "Inside Aircraft: " + str(audio_manager.is_currently_inside()) + "\n"
	debug_text += "Current Bus: " + audio_manager.current_audio_bus + "\n"
	debug_text += "Camera: "
	
	var camera_controller = audio_manager.camera_controller
	if camera_controller:
		if camera_controller.cockpit_camera and camera_controller.cockpit_camera.current:
			debug_text += "Cockpit"
		elif camera_controller.chase_camera and camera_controller.chase_camera.current:
			debug_text += "Chase"
		elif camera_controller.cinematic_camera and camera_controller.cinematic_camera.current:
			debug_text += "Cinematic"
		else:
			debug_text += "None"
	else:
		debug_text += "No Controller"
	
	# Draw debug text
	var viewport = get_viewport()
	var canvas = viewport.get_canvas_transform()
	var camera = viewport.get_camera_3d()
	
	if camera:
		var screen_pos = camera.unproject_position(Vector3.ZERO)
		# This is a simple text display - in a real implementation you'd use a Label node
		print(debug_text)




