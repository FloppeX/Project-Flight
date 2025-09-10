extends RigidBody3D

# =============================================================================
# SIMPLE LAND CARRIER - Stable version without complex systems
# =============================================================================

@export var max_speed: float = 30.0
@export var acceleration: float = 5.0
@export var deceleration: float = 8.0
@export var turn_rate: float = 1.5

# Movement state
var target_position: Vector3
var target_rotation: float
var is_moving: bool = false
var is_rotating: bool = false

func _ready():
    # Set up physics properties for stability
    gravity_scale = 1.0
    linear_damp = 0.9  # Very high damping to prevent bouncing
    angular_damp = 3.0  # Very high angular damping to prevent spinning
    mass = 1000.0  # Heavy mass for stability
    
    # Add to groups
    add_to_group("land_carrier")
    
    # Set initial position
    global_position.y = 1.0
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    
    # Set initial target
    target_position = global_position
    target_rotation = rotation.y
    
    print("Simple Land Carrier ready at position: ", global_position)

func _physics_process(delta):
    keep_on_ground()
    handle_movement(delta)

func keep_on_ground():
    """Keep the carrier on the ground"""
    # If falling too fast, limit the fall speed
    if linear_velocity.y < -5.0:
        linear_velocity.y = -5.0
    
    # If below ground level, push up strongly
    if global_position.y < 0.5:
        var push_force = Vector3(0, 50000, 0)
        apply_central_force(push_force)
        print("Pushing carrier up from Y=", global_position.y)

func handle_movement(delta):
    """Handle carrier movement toward target position"""
    if not is_moving and not is_rotating:
        return
    
    var current_pos = global_position
    var current_rot = rotation.y
    
    # Handle rotation
    if is_rotating:
        var angle_diff = target_rotation - current_rot
        if abs(angle_diff) > 0.01:
            var rotation_speed = turn_rate * delta
            if angle_diff > PI:
                angle_diff -= 2 * PI
            elif angle_diff < -PI:
                angle_diff += 2 * PI
            
            var rotation_amount = sign(angle_diff) * min(abs(angle_diff), rotation_speed)
            rotate_y(rotation_amount)
        else:
            is_rotating = false
    
    # Handle movement
    if is_moving:
        var distance = current_pos.distance_to(target_position)
        if distance > 0.1:
            var direction = (target_position - current_pos).normalized()
            var current_speed = linear_velocity.length()
            var target_speed = min(max_speed, distance * 2.0)
            
            if current_speed < target_speed:
                var force = direction * acceleration * mass * 100.0
                apply_central_force(force)
        else:
            is_moving = false
            linear_velocity = Vector3.ZERO

func set_target_position(pos: Vector3):
    """Set target position for movement"""
    target_position = pos
    is_moving = true
    print("Moving to: ", pos)

func set_target_rotation(rot: float):
    """Set target rotation"""
    target_rotation = rot
    is_rotating = true
    print("Rotating to: ", rot)


