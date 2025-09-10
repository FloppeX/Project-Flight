extends Node3D

# =============================================================================
# ENGINE TEST - Test the new automatic engine start/stop behavior
# =============================================================================

func _ready():
	print("=== Engine Test ===")
	print("New Engine Controls:")
	print("  - Press W/S or throttle up/down to control engines")
	print("  - Engines automatically start when throttle > 0")
	print("  - Engines automatically stop when throttle = 0")
	print("  - No separate start/stop buttons needed!")
	print("")
	print("Test Instructions:")
	print("  1. Press throttle up (W or throttle_up) - engine should start")
	print("  2. Press throttle down (S or throttle_down) - engine should stop")
	print("  3. Press ESC to quit")

func _input(event):
	if event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()

