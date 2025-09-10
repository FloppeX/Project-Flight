extends Node3D

# =============================================================================
# TERRAIN COLLISION DEBUG - Debug Terrain3D collision issues
# =============================================================================

var land_carrier: RigidBody3D

func _ready():
    print("=== Terrain Collision Debug ===")
    print("Debugging Terrain3D collision with carrier")
    
    # Get the land carrier
    land_carrier = $LandCarrier
    
    if land_carrier:
        print("✅ Carrier found!")
        print("Carrier position: ", land_carrier.global_position)
        print("Carrier mass: ", land_carrier.mass)
        print("Carrier linear velocity: ", land_carrier.linear_velocity)
        
        # Check collision layers
        print("Carrier collision layer: ", land_carrier.collision_layer)
        print("Carrier collision mask: ", land_carrier.collision_mask)
        
        # Check if carrier is falling
        if land_carrier.linear_velocity.y < -1.0:
            print("⚠️ Carrier is falling! Velocity Y: ", land_carrier.linear_velocity.y)
        else:
            print("✅ Carrier seems stable")
    else:
        print("❌ No carrier found!")

func _process(delta):
    if land_carrier:
        # Monitor carrier position
        if Engine.get_process_frames() % 60 == 0:
            print("Carrier Y: ", land_carrier.global_position.y, " Velocity Y: ", land_carrier.linear_velocity.y)

func _input(event):
    if event.is_action_pressed("ui_accept"):  # Space key
        print("\n--- Testing Terrain Collision ---")
        if land_carrier:
            # Move carrier to a known position
            land_carrier.global_position = Vector3(0, 10, 0)
            land_carrier.linear_velocity = Vector3.ZERO
            land_carrier.angular_velocity = Vector3.ZERO
            print("Carrier moved to Y=10, should fall and land on terrain")
    elif event.is_action_pressed("ui_cancel"):  # ESC key
        get_tree().quit()


