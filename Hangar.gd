class_name Hangar
extends Node3D

# =============================================================================
# HANGAR - AIRCRAFT STORAGE AND MAINTENANCE
# =============================================================================
# Manages aircraft storage, spawning, and maintenance
# =============================================================================

# Hangar Properties
@export var aircraft_spawn_points: Array[Vector3] = [
    Vector3(-8, 0, 0),
    Vector3(-4, 0, 0),
    Vector3(0, 0, 0),
    Vector3(4, 0, 0),
    Vector3(8, 0, 0),
    Vector3(12, 0, 0)
]
@export var max_aircraft_capacity: int = 12
@export var aircraft_templates: Array[PackedScene] = []
@export var spawn_time: float = 2.0  # Time to spawn an aircraft

# State
var stored_aircraft: Array[Aircraft] = []
var spawn_queue: Array[Dictionary] = []  # Queue of aircraft to spawn
var carrier: LandCarrier
var spawn_timer: float = 0.0

# Signals
signal aircraft_spawned(aircraft)
signal aircraft_stored(aircraft)
signal aircraft_removed(aircraft)
signal spawn_queue_updated(queue_size)

func setup(carrier_node: LandCarrier):
    """Initialize the hangar"""
    carrier = carrier_node

func update(delta: float):
    """Update hangar systems"""
    # Process spawn queue
    if not spawn_queue.is_empty() and spawn_timer <= 0:
        spawn_next_aircraft()
    
    if spawn_timer > 0:
        spawn_timer -= delta

func spawn_aircraft(aircraft_type: int, spawn_point: int = -1) -> Aircraft:
    """Spawn an aircraft of specified type"""
    if aircraft_type >= aircraft_templates.size():
        print("Invalid aircraft type: ", aircraft_type)
        return null
    
    if stored_aircraft.size() >= max_aircraft_capacity:
        print("Hangar at capacity")
        return null
    
    # Add to spawn queue
    var spawn_data = {
        "type": aircraft_type,
        "spawn_point": spawn_point if spawn_point >= 0 else stored_aircraft.size() % aircraft_spawn_points.size()
    }
    spawn_queue.append(spawn_data)
    emit_signal("spawn_queue_updated", spawn_queue.size())
    
    return null  # Will be created when spawn timer expires

func spawn_next_aircraft():
    """Spawn the next aircraft in the queue"""
    if spawn_queue.is_empty():
        return
    
    var spawn_data = spawn_queue.pop_front()
    emit_signal("spawn_queue_updated", spawn_queue.size())
    
    var aircraft_scene = aircraft_templates[spawn_data.type]
    var new_aircraft = aircraft_scene.instantiate()
    
    # Add to scene tree
    get_parent().add_child(new_aircraft)
    
    # Position aircraft
    var spawn_pos = aircraft_spawn_points[spawn_data.spawn_point]
    new_aircraft.global_position = global_position + spawn_pos
    new_aircraft.global_rotation = global_rotation
    
    # Add to stored aircraft
    stored_aircraft.append(new_aircraft)
    
    # Start spawn timer
    spawn_timer = spawn_time
    
    emit_signal("aircraft_spawned", new_aircraft)

func store_aircraft(aircraft: Aircraft) -> bool:
    """Store an aircraft in the hangar"""
    if stored_aircraft.size() >= max_aircraft_capacity:
        return false
    
    if aircraft in stored_aircraft:
        return true  # Already stored
    
    # Position aircraft in hangar
    var spawn_pos = aircraft_spawn_points[stored_aircraft.size() % aircraft_spawn_points.size()]
    aircraft.global_position = global_position + spawn_pos
    aircraft.global_rotation = global_rotation
    
    # Add to stored aircraft
    stored_aircraft.append(aircraft)
    emit_signal("aircraft_stored", aircraft)
    
    return true

func remove_aircraft(aircraft: Aircraft) -> bool:
    """Remove an aircraft from the hangar"""
    if aircraft in stored_aircraft:
        stored_aircraft.erase(aircraft)
        emit_signal("aircraft_removed", aircraft)
        return true
    return false

func get_stored_aircraft() -> Array[Aircraft]:
    """Get list of stored aircraft"""
    return stored_aircraft

func get_available_capacity() -> int:
    """Get available storage capacity"""
    return max_aircraft_capacity - stored_aircraft.size()

func get_spawn_queue_size() -> int:
    """Get current spawn queue size"""
    return spawn_queue.size()

func clear_spawn_queue():
    """Clear the spawn queue"""
    spawn_queue.clear()
    emit_signal("spawn_queue_updated", 0)

func get_aircraft_templates() -> Array[PackedScene]:
    """Get available aircraft templates"""
    return aircraft_templates

func add_aircraft_template(template: PackedScene):
    """Add a new aircraft template"""
    if template not in aircraft_templates:
        aircraft_templates.append(template)

func get_status() -> Dictionary:
    """Get hangar status"""
    return {
        "stored_aircraft_count": stored_aircraft.size(),
        "max_capacity": max_aircraft_capacity,
        "available_capacity": get_available_capacity(),
        "spawn_queue_size": spawn_queue.size(),
        "spawn_timer": spawn_timer,
        "templates_available": aircraft_templates.size()
    }














