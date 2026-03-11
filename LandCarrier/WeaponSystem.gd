class_name WeaponSystem
extends Node3D

# =============================================================================
# WEAPON SYSTEM - CARRIER DEFENSIVE WEAPONS
# =============================================================================
# Manages the carrier's defensive weapon systems by deploying TurretControllers
# =============================================================================

# Weapon Properties
@export var weapon_turrets: Array[Node3D] = []
@export var max_range: float = 500.0
@export var ammunition: int = 1000
@export var max_ammunition: int = 1000

# Optional scene to spawn at each weapon_turret node location
@export var turret_scene: PackedScene 

# State
var carrier: Node3D # Usually LandCarrier
var active_controllers: Array[TurretController] = []
var is_active: bool = true

# Signals
signal ammunition_changed(current, max)

func setup(carrier_node: Node3D):
    """Initialize the weapon system"""
    carrier = carrier_node
    
    # Try to deploy turrets at the weapon_turret hardpoint locations
    if turret_scene and not weapon_turrets.is_empty():
        for point in weapon_turrets:
            var instance = turret_scene.instantiate()
            point.add_child(instance)
            
            # Find the controller within
            var controller: TurretController = null
            if instance is TurretController:
                controller = instance
            else:
                for child in instance.get_children():
                    if child is TurretController:
                        controller = child
                        break
                        
            if controller:
                controller.max_range = max_range
                # Assuming carrier is team 1
                controller.team = 1 if carrier.has_method("get_team") else 1
                active_controllers.append(controller)

func update(delta: float):
    """Update weapon system (Mainly ammo management now, logic handled by Turrets)"""
    if not is_active:
        return
        
    # Ammunition logic could be wired into the controllers' fire signals,
    # but since controllers manage their own burst loops now, we might leave
    # carrier ammo passive unless we connect the "fired" signal from the turrets.

func set_active(active: bool):
    """Enable/disable weapon system"""
    is_active = active
    for controller in active_controllers:
        controller.set_process(active)
        controller.set_physics_process(active)

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
        "active_turrets": active_controllers.size(),
        "max_range": max_range
    }

























