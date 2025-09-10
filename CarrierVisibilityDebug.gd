extends Node3D

# =============================================================================
# CARRIER VISIBILITY DEBUG - Debug carrier visibility in main scene
# =============================================================================

var land_carrier: RigidBody3D

func _ready():
    print("=== Carrier Visibility Debug ===")
    print("Debugging carrier visibility in main scene")
    
    # Get the land carrier
    land_carrier = $LandCarrier
    
    if land_carrier:
        print("✅ Carrier found!")
        print("Carrier global position: ", land_carrier.global_position)
        print("Carrier rotation: ", land_carrier.rotation)
        print("Carrier scale: ", land_carrier.scale)
        print("Carrier mass: ", land_carrier.mass)
        print("Carrier linear velocity: ", land_carrier.linear_velocity)
        print("Carrier angular velocity: ", land_carrier.angular_velocity)
        
        # Check if carrier has a model
        var carrier_model = land_carrier.get_node_or_null("CarrierModel")
        if carrier_model:
            print("✅ Carrier model found at: ", carrier_model.global_position)
        else:
            print("❌ No carrier model found!")
            
        # Make carrier more visible
        make_carrier_visible()
    else:
        print("❌ No carrier found!")

func make_carrier_visible():
    """Make carrier more visible for debugging"""
    if not land_carrier:
        return
    
    # Add a bright material to make it visible
    var carrier_model = land_carrier.get_node_or_null("CarrierModel")
    if carrier_model:
        # Find all MeshInstance3D nodes in the model
        find_and_highlight_meshes(carrier_model)

func find_and_highlight_meshes(node: Node3D):
    """Recursively find and highlight mesh instances"""
    for child in node.get_children():
        if child is MeshInstance3D:
            var mesh_instance = child as MeshInstance3D
            print("Found mesh: ", mesh_instance.name, " at ", mesh_instance.global_position)
            
            # Create a bright material
            var material = StandardMaterial3D.new()
            material.albedo_color = Color(1.0, 0.0, 0.0, 1.0)  # Bright red
            material.emission = Color(0.2, 0.0, 0.0, 1.0)  # Red glow
            material.emission_energy = 0.5
            mesh_instance.material_override = material
            
        elif child is Node3D:
            find_and_highlight_meshes(child)

func _process(delta):
    if land_carrier:
        # Print carrier status every 60 frames
        if Engine.get_process_frames() % 60 == 0:
            print("Carrier Y position: ", land_carrier.global_position.y)
            print("Carrier velocity: ", land_carrier.linear_velocity.length())

func _input(event):
    if event.is_action_pressed("ui_accept"):  # Space key
        print("\n--- Resetting Carrier Position ---")
        if land_carrier:
            land_carrier.global_position = Vector3(0, 10, 0)  # Move high up
            land_carrier.linear_velocity = Vector3.ZERO
            land_carrier.angular_velocity = Vector3.ZERO
            print("Carrier reset to high position")
    elif event.is_action_pressed("ui_cancel"):  # ESC key
        get_tree().quit()


