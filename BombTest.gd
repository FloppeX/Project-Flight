extends Node3D

# =============================================================================
# BOMB TEST - Test the new bomb arming system
# =============================================================================

func _ready():
	print("=== Bomb Arming Test ===")
	print("New Bomb Behavior:")
	print("  - Bombs drop and take 1 second to arm")
	print("  - Unarmed bombs do reduced damage (10%)")
	print("  - Armed bombs do full damage and explode")
	print("  - Press fire_weapon to drop bombs")
	print("  - Press ESC to quit")
	print("")
	print("Test Instructions:")
	print("  1. Drop a bomb and immediately hit something - should do reduced damage")
	print("  2. Drop a bomb and wait 1+ seconds before hitting - should explode normally")

func _input(event):
	if event.is_action_pressed("ui_cancel"):  # ESC key
		get_tree().quit()

