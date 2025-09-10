extends Node3D

# =============================================================================
# SIMPLE ELEVATOR TEST - Just the elevator components
# =============================================================================

var elevator: CarrierElevator

func _ready():
	elevator = $Elevator
	
	print("=== Simple Elevator Test ===")
	print("You should see:")
	print("  - Red platform (20x20m)")
	print("  - Green left cover")
	print("  - Blue right cover")
	print("Press SPACE to start elevator sequence")
	print("Press ESC to quit")
	
	if elevator:
		print("✅ Elevator loaded")
		# Connect to signals
		elevator.connect("elevator_at_top", Callable(self, "_on_elevator_at_top"))
		elevator.connect("elevator_at_bottom", Callable(self, "_on_elevator_at_bottom"))
		elevator.connect("covers_closed", Callable(self, "_on_covers_closed"))
		elevator.connect("covers_opened", Callable(self, "_on_covers_opened"))
	else:
		print("❌ No elevator found")

func _process(delta):
	if elevator:
		var status = elevator.get_status()
		print("State: ", status.state, " Platform Y: ", status.platform_y)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Starting Elevator Sequence ---")
		if elevator:
			elevator.start_elevator_sequence()
		else:
			print("No elevator available")
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()

func _on_elevator_at_top():
	print("🎉 Elevator at top!")

func _on_elevator_at_bottom():
	print("🔽 Elevator at bottom!")

func _on_covers_closed():
	print("🔒 Covers closed!")

func _on_covers_opened():
	print("🔓 Covers opened!")
