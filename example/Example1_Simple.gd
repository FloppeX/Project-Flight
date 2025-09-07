extends Node3D

@onready var aircraft = get_node("Aircraft")
var crash_camera: Camera3D

func _ready():
	# Connect aircraft crash signal for restart
	aircraft.connect("crashed", Callable(self, "_on_Aircraft_crashed"))
	
	# Connect module interface signals (these are needed for modules to work)
	$Aircraft/Engine.connect("update_interface", Callable($Aircraft/Model/MovingParts/Engine, "_on_Engine_update_interface"))
	$Aircraft/Steering.connect("update_interface", Callable($Aircraft/Model/MovingParts/Steering, "_on_Steering_update_interface"))
	$Aircraft/Flaps.connect("update_interface", Callable($Aircraft/Model/MovingParts/Flaps, "_on_Flaps_update_interface"))
	$Aircraft/LandingGear.connect("update_interface", Callable($Aircraft/Model/MovingParts/LandingGear, "_on_LandingGear_update_interface"))

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			print("ESC pressed - Exiting game...")
			get_tree().quit()

func _on_Aircraft_crashed(_impact_velocity):
	print("AIRCRAFT CRASHED - Creating cinematic crash sequence...")
	
	var crash_position = aircraft.global_position
	
	# Create explosion at crash site
	create_crash_explosion(crash_position)
	
	# Create and activate crash camera
	create_crash_camera(crash_position)
	
	# Completely disable the aircraft physics and processing
	aircraft.visible = false
	aircraft.set_physics_process(false)
	aircraft.set_process(false)
	aircraft.freeze = true  # Stop all physics movement
	aircraft.set_collision_layer(0)  # Remove from collision layers
	aircraft.set_collision_mask(0)   # Stop detecting collisions
	
	# Wait for cinematic sequence, then restart
	get_tree().create_timer(5.0).timeout.connect(_restart_scene)

func create_crash_explosion(position: Vector3):
	# Create your explosion at the crash site
	var explosion = preload("res://Projectiles/Explosion/explosion.tscn").instantiate()
	add_child(explosion)
	explosion.global_position = position
	explosion.create_scorch_mark()  # Add scorch mark for crashes too

func create_crash_camera(crash_position: Vector3):
	# Create a new camera for the cinematic view
	crash_camera = Camera3D.new()
	add_child(crash_camera)
	crash_camera.name = "CrashCamera"
	
	# Position camera at a good distance from crash
	var camera_distance = 25.0
	var camera_height = 10.0
	
	# Start camera position (to the side and above the crash)
	var start_position = crash_position + Vector3(camera_distance, camera_height, 0)
	crash_camera.global_position = start_position
	
	# Point camera at crash site
	crash_camera.look_at(crash_position, Vector3.UP)
	
	# Make this the active camera
	crash_camera.current = true
	
	# Start the circling animation
	animate_crash_camera(crash_position, camera_distance, camera_height)

func animate_crash_camera(center: Vector3, radius: float, height: float):
	# Create smooth circular motion using a pivot point
	var camera_pivot = Node3D.new()
	add_child(camera_pivot)
	camera_pivot.global_position = center
	
	# Attach camera to the pivot at the desired distance
	crash_camera.get_parent().remove_child(crash_camera)
	camera_pivot.add_child(crash_camera)
	crash_camera.position = Vector3(radius, height, 0)
	
	# Always look at the center point
	crash_camera.look_at(center, Vector3.UP)
	
	# Create smooth rotation tween
	var rotation_tween = create_tween()
	rotation_tween.set_loops()  # Loop forever
	
	# Slower rotation - 12 seconds per full circle (was 8 seconds)
	var circle_duration = 12.0
	var full_rotation = camera_pivot.rotation.y + TAU  # One full circle (2π radians)
	
	rotation_tween.tween_property(camera_pivot, "rotation:y", full_rotation, circle_duration)
	rotation_tween.tween_callback(func(): camera_pivot.rotation.y = 0.0)  # Reset rotation to avoid accumulation

func _restart_scene():
	print("Restarting scene...")
	if get_tree():
		get_tree().reload_current_scene()
	else:
		print("Scene tree is null - cannot reload")

func _on_BtnBack_pressed():
	get_tree().change_scene_to_file("res://example/ExampleList.tscn")
