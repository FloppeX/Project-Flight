extends Node3D

# =============================================================================
# CARRIER COLLISION TEST - Test the carrier physics and collision
# =============================================================================

var land_carrier: LandCarrier

func _ready():
    land_carrier = $LandCarrier
    
    print("=== Carrier Collision Test ===")
    print("Testing carrier physics and collision setup")
    print("Press SPACE to test movement")
    print("Press ESC to quit")
    
    # Wait for collision setup
    await get_tree().create_timer(1.0).timeout
    print("Carrier should be stable on the ground now")

func _process(delta):
    if land_carrier:
        print("Carrier Position: Y=", land_carrier.global_position.y, " Velocity: ", land_carrier.linear_velocity.length(), " m/s")

func _input(event):
    if event.is_action_pressed("ui_accept"):  # Space key
        print("\n--- Testing Movement ---")
        var test_pos = land_carrier.global_position + Vector3(10, 0, 0)
        land_carrier.set_target_position(test_pos)
        print("Moving to: ", test_pos)
    elif event.is_action_pressed("ui_cancel"):  # ESC key
        get_tree().quit()


