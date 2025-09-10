extends Node3D

var restart_timer: Timer

func _ready():
	# Find the aircraft and connect to its destruction signal
	var aircraft = find_child("CompleteFighterJet")
	if aircraft:
		aircraft.destroyed.connect(_on_aircraft_destroyed)
		aircraft.crashed.connect(_on_aircraft_crashed)

func _input(event):
	if Input.is_action_just_pressed("ui_cancel"):  # ESC key
		get_tree().quit()

func _on_aircraft_destroyed():
	print("Aircraft destroyed! Restarting scene in 3 seconds...")
	restart_scene_after_delay(3.0)

func _on_aircraft_crashed(impact_velocity: float):
	# Only restart on hard crashes (high impact)
	if impact_velocity > 15.0:
		print("Aircraft crashed hard! Restarting scene in 3 seconds...")
		restart_scene_after_delay(3.0)

func restart_scene_after_delay(delay_seconds: float):
	if restart_timer:
		restart_timer.queue_free()
	
	restart_timer = Timer.new()
	add_child(restart_timer)
	restart_timer.one_shot = true
	restart_timer.timeout.connect(restart_scene)
	restart_timer.start(delay_seconds)

func restart_scene():
	get_tree().reload_current_scene()
