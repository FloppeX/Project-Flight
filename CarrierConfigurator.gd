extends Node3D
class_name CarrierConfigurator

# =============================================================================
# CARRIER CONFIGURATOR
# =============================================================================
# Helper script to configure the land carrier with your specific model
# =============================================================================

@export var carrier_scene: PackedScene
@export var auto_configure_on_ready: bool = true

func _ready():
    if auto_configure_on_ready:
        configure_carrier()

func configure_carrier():
    """Configure the carrier with optimal settings"""
    var carrier = get_carrier()
    if not carrier:
        print("No carrier found to configure")
        return
    
    print("Configuring Land Carrier...")
    
    # Configure physics properties based on model size
    configure_physics(carrier)
    
    # Configure tread positions
    configure_tread_positions(carrier)
    
    # Configure collision shape
    configure_collision_shape(carrier)
    
    print("Carrier configuration complete!")

func get_carrier() -> LandCarrier:
    """Get the land carrier instance"""
    var carrier = find_child("LandCarrier")
    if carrier and carrier is LandCarrier:
        return carrier
    
    # Look for carrier in children
    for child in get_children():
        if child is LandCarrier:
            return child
    
    return null

func configure_physics(carrier: LandCarrier):
    """Configure physics properties"""
    # Adjust mass based on carrier size
    carrier.mass = 75000.0  # Heavier for realism
    
    # Configure movement parameters
    carrier.max_speed = 25.0  # km/h - realistic for a land carrier
    carrier.acceleration = 3.0  # m/s² - slow acceleration
    carrier.deceleration = 5.0  # m/s² - good braking
    carrier.turn_rate = 1.0  # rad/s - slow turning
    
    print("Physics configured: Mass=", carrier.mass, " MaxSpeed=", carrier.max_speed)

func configure_tread_positions(carrier: LandCarrier):
    """Configure tread positions for the carrier"""
    var tread_helper = carrier.get_node("TreadPositionHelper")
    if tread_helper and tread_helper is TreadPositionHelper:
        # Get the model bounds to calculate tread positions
        var model_bounds = get_model_bounds(carrier)
        if model_bounds.size != Vector3.ZERO:
            var tread_positions = calculate_tread_positions(model_bounds)
            tread_helper.set_tread_positions(tread_positions)
            print("Tread positions configured: ", tread_positions.size(), " positions")
        else:
            print("Using default tread positions")

func get_model_bounds(carrier: LandCarrier) -> AABB:
    """Get the bounding box of the carrier model"""
    var model = carrier.get_node("CarrierModel")
    if not model:
        return AABB()
    
    var bounds = AABB()
    var first = true
    
    # Calculate bounds by traversing the model
    calculate_bounds_recursive(model, bounds, first)
    
    return bounds

func calculate_bounds_recursive(node: Node3D, bounds: AABB, first: bool):
    """Recursively calculate bounds of the model"""
    if node is MeshInstance3D:
        var mesh_instance = node as MeshInstance3D
        if mesh_instance.mesh:
            var mesh_bounds = mesh_instance.get_aabb()
            var global_bounds = AABB(mesh_bounds.position + node.global_position, mesh_bounds.size)
            
            if first:
                bounds = global_bounds
                first = false
            else:
                bounds = bounds.merge(global_bounds)
    
    for child in node.get_children():
        if child is Node3D:
            calculate_bounds_recursive(child, bounds, first)

func calculate_tread_positions(bounds: AABB) -> Array[Vector3]:
    """Calculate tread positions based on model bounds"""
    var positions: Array[Vector3] = []
    
    # Calculate tread positions for 6 treads (3 per side)
    var half_width = bounds.size.x * 0.4  # 40% from center
    var front_z = bounds.position.z + bounds.size.z * 0.3
    var middle_z = bounds.position.z
    var rear_z = bounds.position.z - bounds.size.z * 0.3
    var tread_y = bounds.position.y - bounds.size.y * 0.1  # Slightly below the model
    
    # Left side treads
    positions.append(Vector3(-half_width, tread_y, front_z))
    positions.append(Vector3(-half_width, tread_y, middle_z))
    positions.append(Vector3(-half_width, tread_y, rear_z))
    
    # Right side treads
    positions.append(Vector3(half_width, tread_y, front_z))
    positions.append(Vector3(half_width, tread_y, middle_z))
    positions.append(Vector3(half_width, tread_y, rear_z))
    
    return positions

func configure_collision_shape(carrier: LandCarrier):
    """Configure collision shape based on model"""
    var collision_shape = carrier.get_node("CollisionShape3D")
    if not collision_shape:
        return
    
    var model_bounds = get_model_bounds(carrier)
    if model_bounds.size != Vector3.ZERO:
        # Create a box collision shape based on model bounds
        var box_shape = BoxShape3D.new()
        box_shape.size = model_bounds.size
        collision_shape.shape = box_shape
        collision_shape.position = model_bounds.position + model_bounds.size * 0.5
        
        print("Collision shape configured: Size=", box_shape.size)

func _input(event):
    """Handle input for manual configuration"""
    if event.is_action_pressed("ui_accept"):  # Space key
        configure_carrier()
    elif event.is_action_pressed("ui_cancel"):  # ESC key
        get_tree().quit()


