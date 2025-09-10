extends Node3D

# =============================================================================
# BASIC CARRIER TEST - Simple carrier without complex systems
# =============================================================================

var test_carrier: RigidBody3D

func _ready():
	test_carrier = $TestCarrier
	print("=== Basic Carrier Test ===")
	print("Simple carrier should land on ground")
	print("Press SPACE to test movement")

func _process(delta):
	if test_carrier:
		var y_pos = test_carrier.global_position.y
		var velocity = test_carrier.linear_velocity.length()
		
		if y_pos < -5.0:
			print("ERROR: Carrier fell through ground! Y=", y_pos)
		elif y_pos < 0.0:
			print("WARNING: Carrier below ground! Y=", y_pos)
		
		# Print status every 60 frames
		if Engine.get_process_frames() % 60 == 0:
			print("Position: Y=", y_pos, " Velocity=", velocity)

func _input(event):
	if event.is_action_pressed("ui_accept"):  # Space key
		print("\n--- Testing Movement ---")
		# Apply a small force to test movement
		test_carrier.apply_central_force(Vector3(1000, 0, 0))
		print("Applied force to carrier")
	elif event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()
