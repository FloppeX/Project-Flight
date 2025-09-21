class_name WeaponSystem
extends Node3D

# =============================================================================
# WEAPON SYSTEM - CARRIER DEFENSIVE WEAPONS
# =============================================================================
# Manages the carrier's defensive weapon systems
# =============================================================================

# Weapon Properties
@export var weapon_turrets: Array[Node3D] = []
@export var max_range: float = 500.0
@export var damage_per_shot: float = 50.0
@export var fire_rate: float = 2.0  # Shots per second
@export var ammunition: int = 1000
@export var max_ammunition: int = 1000

# State
var carrier: LandCarrier
var target_enemies: Array[Node3D] = []
var fire_timer: float = 0.0
var is_active: bool = true

# Signals
signal weapon_fired(target, damage)
signal ammunition_changed(current, max)
signal target_acquired(target)
signal target_lost(target)

func setup(carrier_node: LandCarrier):
    """Initialize the weapon system"""
    carrier = carrier_node

func update(delta: float):
    """Update weapon system"""
    if not is_active or ammunition <= 0:
        return
    
    # Update fire timer
    if fire_timer > 0:
        fire_timer -= delta
    
    # Find targets
    find_targets()
    
    # Fire at targets
    if fire_timer <= 0 and not target_enemies.is_empty():
        fire_at_target(target_enemies[0])

func find_targets():
    """Find enemy targets within range"""
    target_enemies.clear()
    
    # Get all enemy aircraft
    var enemies = get_tree().get_nodes_in_group("aircraft")
    for enemy in enemies:
        if enemy.has_method("get_team") and enemy.get_team() != carrier.team:
            var distance = global_position.distance_to(enemy.global_position)
            if distance <= max_range:
                target_enemies.append(enemy)

func fire_at_target(target: Node3D):
    """Fire at a specific target"""
    if ammunition <= 0:
        return
    
    # Calculate damage
    var distance = global_position.distance_to(target.global_position)
    var damage = damage_per_shot * (1.0 - distance / max_range)  # Damage decreases with distance
    
    # Apply damage to target
    if target.has_method("take_damage"):
        target.take_damage(damage)
    
    # Consume ammunition
    ammunition -= 1
    emit_signal("ammunition_changed", ammunition, max_ammunition)
    
    # Reset fire timer
    fire_timer = 1.0 / fire_rate
    
    emit_signal("weapon_fired", target, damage)

func set_active(active: bool):
    """Enable/disable weapon system"""
    is_active = active

func reload_ammunition(amount: int):
    """Reload ammunition"""
    ammunition = min(ammunition + amount, max_ammunition)
    emit_signal("ammunition_changed", ammunition, max_ammunition)

func get_status() -> Dictionary:
    """Get weapon system status"""
    return {
        "active": is_active,
        "ammunition": ammunition,
        "max_ammunition": max_ammunition,
        "targets_in_range": target_enemies.size(),
        "fire_rate": fire_rate,
        "max_range": max_range
    }















