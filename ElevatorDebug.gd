extends Node3D

# =============================================================================
# ELEVATOR DEBUG - Debug elevator visibility and collision
# =============================================================================

var land_carrier: RigidBody3D
var elevator: CarrierElevator

func _ready():
    print("=== Elevator Debug ===")
    print("Debugging elevator visibility and collision")
    
    # Get the land carrier
    land_carrier = $LandCarrier
    
    # Wait for carrier to initialize
    await get_tree().process_frame
    
    # Get the elevator from the carrier
    elevator = land_carrier.get_elevator()
    
    if elevator:
        print("✅ Elevator found!")
        print("Platform position: ", elevator.platform.global_position)
        print("Left cover position: ", elevator.left_cover.global_position)
        print("Right cover position: ", elevator.right_cover.global_position)
        
        # Make elevator components more visible
        make_elevator_visible()
    else:
        print("❌ No elevator found!")

func make_elevator_visible():
    """Make elevator components more visible for debugging"""
    if not elevator:
        return
    
    # Make platform more visible
    var platform_mesh = elevator.platform.get_child(0) as MeshInstance3D
    if platform_mesh:
        var material = platform_mesh.material_override as StandardMaterial3D
        if material:
            material.emission = Color(0.2, 0.2, 0.2, 1.0)  # Add glow
            material.emission_energy = 0.5
    
    # Make covers more visible
    var left_cover_mesh = elevator.left_cover.get_child(0) as MeshInstance3D
    if left_cover_mesh:
        var material = left_cover_mesh.material_override as StandardMaterial3D
        if material:
            material.emission = Color(0.1, 0.1, 0.1, 1.0)  # Add glow
            material.emission_energy = 0.3
    
    var right_cover_mesh = elevator.right_cover.get_child(0) as MeshInstance3D
    if right_cover_mesh:
        var material = right_cover_mesh.material_override as StandardMaterial3D
        if material:
            material.emission = Color(0.1, 0.1, 0.1, 1.0)  # Add glow
            material.emission_energy = 0.3
    
    print("Elevator components made more visible")

func _process(delta):
    if elevator:
        elevator.update(delta)
        
        # Print positions every 60 frames
        if Engine.get_process_frames() % 60 == 0:
            print("Platform Y: ", elevator.platform.global_position.y)
            print("Carrier Y: ", land_carrier.global_position.y)

func _input(event):
    if event.is_action_pressed("ui_accept"):  # Space key
        print("\n--- Testing Elevator ---")
        if elevator:
            elevator.reverse_elevator_sequence()
        else:
            print("No elevator to test!")
    elif event.is_action_pressed("ui_cancel"):  # ESC key
        get_tree().quit()


