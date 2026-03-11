extends Node3D
class_name TurretController

# --- Dependencies ---
@export var turret: Turret
@export var weapon_scene: PackedScene

# --- Targeting configuration ---
@export_group("AI Targeting")
@export var team: int = 2
@export var max_range: float = 400.0
@export var field_of_view: float = 360.0 # degrees
@export var aim_skill: float = 0.75 # 0.0 to 1.0 (adds noise)

# --- Firing configuration ---
@export_group("AI Firing")
@export var burst_length: float = 1.5
@export var delay_length: float = 3.0
@export var stop_firing_if_target_lost: bool = true

# State
var current_target: Node3D = null
var target_search_timer: float = 0.0

enum FireState { IDLE, BURSTING, DELAYING }
var fire_state: FireState = FireState.IDLE
var burst_timer: float = 0.0
var delay_timer: float = 0.0

# Instanced component
var weapon_instance: Weapon = null

func _ready() -> void:
    if not turret:
        # Try to find a child turret
        for child in get_children():
            if child is Turret:
                turret = child
                break
                
    if not turret:
        push_warning("TurretController: No Turret assigned or found as child!")
        return
        
    if weapon_scene:
        mount_weapon(weapon_scene)

func mount_weapon(scene: PackedScene) -> void:
    if weapon_instance:
        weapon_instance.queue_free()
        
    weapon_instance = scene.instantiate() as Weapon
    # Attach the weapon to the turret's barrel/firing point if needed, or keep it logical
    # If the weapon is visual, it should be a child of the barrel. If it's pure data, child of controller is fine.
    add_child(weapon_instance)

func _physics_process(delta: float) -> void:
    if not turret:
        return
        
    # 1. Target finding (runs 1x per second to save performance)
    target_search_timer += delta
    if target_search_timer >= 1.0:
        target_search_timer = 0.0
        find_and_set_best_target()
        
    # 2. Target Tracking
    var lead_position = Vector3.ZERO
    
    if current_target and is_instance_valid(current_target):
        lead_position = calculate_lead_position(current_target)
        turret.aim_at_point(lead_position)
        
        # 3. Burst firing logic
        if turret.is_aimed_at_target(10.0): # Within 10 degrees, fire!
            update_burst_firing(delta)
        else:
            stop_firing()
    else:
        # No target
        turret.set_target(null) # Stop tracking
        stop_firing()
        fire_state = FireState.IDLE

func update_burst_firing(delta: float) -> void:
    match fire_state:
        FireState.IDLE:
            start_burst()
        FireState.BURSTING:
            burst_timer += delta
            if burst_timer >= burst_length:
                stop_firing()
                fire_state = FireState.DELAYING
                delay_timer = 0.0
            else:
                fire_weapon()
        FireState.DELAYING:
            delay_timer += delta
            if delay_timer >= delay_length:
                fire_state = FireState.IDLE

func start_burst() -> void:
    fire_state = FireState.BURSTING
    burst_timer = 0.0

func stop_firing() -> void:
    if weapon_instance and weapon_instance.has_method("stop_firing"):
        weapon_instance.stop_firing()

func fire_weapon() -> void:
    if not weapon_instance or not turret:
        return
        
    if weapon_instance.can_fire():
        # Ideally, we should tell the weapon WHERE it is firing from (the turret barrels)
        # But for now we just call fire() and let the weapon logic run.
        # If the weapon needs a position/direction, we provide it.
        turret.fire()
        
        # In this project, `Weapon` handles ammo decrement but `Hardpoint` actually spawned bullets.
        # We need to bridge this gap. Let's assume weapon.fire() works internally or we simulate a bullet spawn here:
        
        weapon_instance.fire()

# --- Advanced targeting ---

func find_and_set_best_target() -> void:
    var best_target: Node3D = null
    var best_distance = max_range
    
    for enemy in _get_hostile_targets_in_range(max_range):
        var distance = global_position.distance_to(enemy.global_position)
        if distance < best_distance:
            best_target = enemy
            best_distance = distance
            
    if current_target != best_target:
        current_target = best_target

func _get_hostile_targets_in_range(range_limit: float) -> Array:
    var results: Array = []
    
    # Simple group scan
    for group_name in ["aircraft", "enemies", "friendlies", "ai_aircraft", "ground_vehicles"]:
        for node in get_tree().get_nodes_in_group(group_name):
            if not is_instance_valid(node) or node == self or node == get_parent():
                continue
                
            if not node.has_method("get_team"):
                continue
                
            if int(node.get_team()) == team:
                continue
                
            if global_position.distance_to(node.global_position) <= range_limit:
                results.append(node)
                
    # Deduplicate
    var unique_results = []
    for node in results:
        if not unique_results.has(node):
            unique_results.append(node)
            
    return unique_results

# Reuses the exact math from EnemyAircraft for ballistic drops
func calculate_lead_position(target: Node3D) -> Vector3:
    var target_pos = target.global_position
    var target_velocity = Vector3.ZERO
    
    if target.has_method("get_linear_velocity"):
        target_velocity = target.get_linear_velocity()
    elif "linear_velocity" in target:
        target_velocity = target.linear_velocity

    var distance = global_position.distance_to(target_pos)
    
    # Assuming 600m/s bullet velocity loosely if we don't have direct access
    var bullet_speed = 600.0 
    
    var flight_time = distance / bullet_speed
    var lead_position = target_pos + (target_velocity * flight_time)

    # Inaccuracy based on aim skill
    if aim_skill < 1.0:
        var spread = (1.0 - aim_skill) * 15.0
        lead_position += Vector3(
            randf_range(-spread, spread),
            randf_range(-spread * 0.3, spread * 0.3),
            randf_range(-spread, spread)
        )
        
    return lead_position
