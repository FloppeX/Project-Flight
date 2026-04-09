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
@export var aim_skill: float = 1.0 # 0.0 to 1.0 (adds noise)
@export var target_search_interval_s: float = 0.25
@export var distant_target_search_interval_s: float = 1.0
@export var detailed_targeting_distance_m: float = 1000.0
@export var target_aim_height_bias_m: float = 0.75
@export var debug_enabled: bool = false
@export_group("Air Target Penalties")
@export var air_target_range_multiplier: float = 1.0
@export var air_target_aim_skill_multiplier: float = 1.0
@export var air_target_fire_angle_tolerance_multiplier: float = 1.0
@export var air_target_extra_spread_m: float = 0.0

# --- Firing configuration ---
@export_group("AI Firing")
@export var burst_length: float = 1.5
@export var delay_length: float = 3.0
@export var stop_firing_if_target_lost: bool = true
@export var fire_angle_tolerance_deg: float = 18.0

# State
var current_target: Node3D = null
var target_search_timer: float = 0.0

enum FireState { IDLE, BURSTING, DELAYING }
var fire_state: FireState = FireState.IDLE
var burst_timer: float = 0.0
var delay_timer: float = 0.0

# Instanced component
var weapon_instance: Weapon = null
var host_actor: Node3D = null
var _debug_print_timer: float = 0.0
var _cached_camera: Camera3D = null
var _camera_cache_timer: float = 0.0

# Aim noise: updated on a timer so the turret can actually track each position
# rather than chasing a point that jumps every physics frame.
@export var noise_update_interval_s: float = 0.45
var _noise_offset: Vector3 = Vector3.ZERO
var _noise_timer: float = 0.0

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

    host_actor = _resolve_host_actor()

    if weapon_scene:
        mount_weapon(weapon_scene)

func mount_weapon(scene: PackedScene) -> void:
    if weapon_instance:
        weapon_instance.queue_free()

    weapon_instance = scene.instantiate() as Weapon
    if not weapon_instance:
        push_warning("TurretController: Failed to instantiate weapon scene.")
        return

    # Mount under the turret so muzzle transforms come from the actual aiming rig.
    if turret and is_instance_valid(turret):
        turret.add_child(weapon_instance)
    else:
        add_child(weapon_instance)

func _physics_process(delta: float) -> void:
    if not turret:
        return

    if current_target and not is_instance_valid(current_target):
        current_target = null
        turret.set_target(null)
        fire_state = FireState.IDLE

    # 1. Target finding
    target_search_timer += delta
    if target_search_timer >= maxf(_get_effective_target_search_interval(delta), 0.05):
        target_search_timer = 0.0
        find_and_set_best_target()

    # Noise offset: refresh on a timer so the aim point is stable between updates.
    # Per-frame randomness causes 60 Hz jitter that the turret physically cannot track.
    _noise_timer -= delta
    if _noise_timer <= 0.0:
        _noise_timer = maxf(noise_update_interval_s, 0.05)
        if current_target and is_instance_valid(current_target):
            var effective_aim_skill: float = _get_effective_aim_skill(current_target)
            var spread: float = (1.0 - effective_aim_skill) * 15.0
            if _is_air_target(current_target):
                spread += air_target_extra_spread_m
            if spread > 0.01:
                _noise_offset = Vector3(
                    randf_range(-spread, spread),
                    randf_range(-spread * 0.3, spread * 0.3),
                    randf_range(-spread, spread)
                )
            else:
                _noise_offset = Vector3.ZERO
        else:
            _noise_offset = Vector3.ZERO

    # 2. Target Tracking + Rotation
    if current_target and is_instance_valid(current_target):
        turret.set_target(current_target)
        var lead_position := calculate_lead_position(current_target)
        turret.aim_at_point(lead_position)
        turret.tick(delta, lead_position)

        var aim_angle := turret.get_aim_angle_to_target()
        var aimed := aim_angle >= 0.0 and aim_angle <= _get_effective_fire_angle_tolerance_deg(current_target)

        # 3. Burst firing logic
        if aimed:
            update_burst_firing(delta)
        elif fire_state == FireState.DELAYING:
            update_burst_firing(delta)
        else:
            stop_firing()

        # Throttled debug: print once per second per turret
        _debug_print_timer += delta
        if _debug_print_timer >= 1.0:
            _debug_print_timer = 0.0
            var dist := global_position.distance_to(current_target.global_position)
            var lead_offset: Vector3 = lead_position - current_target.global_position
            var tgt_vel := _get_node_velocity(current_target)
            var flight_t := dist / maxf(_get_weapon_projectile_speed(), 1.0)
            print("[TC %s] tgt=%s dist=%.0fm tVel=(%.0f,%.0f,%.0f) lead_ofs=(%.1f,%.1f,%.1f) flight_t=%.2fs state=%s" % [
                get_parent().name if get_parent() else name,
                current_target.name, dist,
                tgt_vel.x, tgt_vel.y, tgt_vel.z,
                lead_offset.x, lead_offset.y, lead_offset.z,
                flight_t,
                FireState.keys()[fire_state]])
    else:
        turret.set_target(null)
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
    fire_weapon()

func stop_firing() -> void:
    if weapon_instance and weapon_instance.has_method("stop_firing"):
        weapon_instance.stop_firing()

func fire_weapon() -> void:
    if not weapon_instance or not turret:
        return
    if weapon_instance.can_fire():
        turret.fire()
        weapon_instance.fire()

# --- Advanced targeting ---

func find_and_set_best_target() -> void:
    var best_target: Node3D = null
    var best_distance: float = INF

    var candidates = _get_hostile_targets_in_range(max_range)
    for enemy in candidates:
        var enemy_node := enemy as Node3D
        var d: float = global_position.distance_to(enemy_node.global_position)
        if d > _get_effective_range_for_target(enemy_node):
            continue
        if d < best_distance:
            best_target = enemy_node
            best_distance = d

    if current_target != best_target:
        current_target = best_target
        if turret and is_instance_valid(turret):
            turret.set_target(current_target)

func _get_hostile_targets_in_range(range_limit: float) -> Array:
    var results: Array = []

    # Determine hostile groups based on our team:
    #   team 1 (friendly/carrier) shoots at enemies
    #   team 2 (enemy) shoots at player and friendly aircraft
    var target_groups: Array
    if team == 1:
        target_groups = ["enemies"]
    else:
        target_groups = ["aircraft", "friendlies", "ai_aircraft", "carrier"]

    for group_name in target_groups:
        for node in get_tree().get_nodes_in_group(group_name):
            if not is_instance_valid(node) or not node is Node3D:
                continue
            if node == self or node == get_parent() or node == host_actor:
                continue
            if global_position.distance_to((node as Node3D).global_position) <= range_limit:
                results.append(node)

    # Deduplicate
    var unique_results = []
    for node in results:
        if not unique_results.has(node):
            unique_results.append(node)

    return unique_results

func _resolve_host_actor() -> Node3D:
    var node: Node = self
    while node:
        if node != self and node.has_method("get_team") and node is Node3D:
            return node as Node3D
        node = node.get_parent()
    return null

func _get_node_velocity(node: Node) -> Vector3:
    if not node or not is_instance_valid(node):
        return Vector3.ZERO
    var linear = node.get("linear_velocity")
    if linear is Vector3:
        return linear
    var velocity = node.get("velocity")
    if velocity is Vector3:
        return velocity
    if node.has_method("get_linear_velocity"):
        var getter_velocity = node.call("get_linear_velocity")
        if getter_velocity is Vector3:
            return getter_velocity
    return Vector3.ZERO

func _get_node_angular_velocity(node: Node) -> Vector3:
    if not node or not is_instance_valid(node):
        return Vector3.ZERO
    var angular = node.get("angular_velocity")
    if angular is Vector3:
        return angular
    if node.has_method("get_angular_velocity"):
        var getter_velocity = node.call("get_angular_velocity")
        if getter_velocity is Vector3:
            return getter_velocity
    return Vector3.ZERO

func _get_point_velocity_at_world_position(world_pos: Vector3) -> Vector3:
    var point_velocity: Vector3 = _get_node_velocity(host_actor)
    if not host_actor or not is_instance_valid(host_actor):
        return point_velocity

    var angular_velocity: Vector3 = _get_node_angular_velocity(host_actor)
    if angular_velocity.length_squared() > 0.000001:
        var r_offset: Vector3 = world_pos - host_actor.global_position
        point_velocity += angular_velocity.cross(r_offset)
    return point_velocity

func _get_weapon_projectile_speed() -> float:
    if weapon_instance:
        var speed = weapon_instance.get("bullet_speed")
        if typeof(speed) in [TYPE_FLOAT, TYPE_INT]:
            return maxf(float(speed), 50.0)
    return 600.0

func _get_aim_origin() -> Vector3:
    if turret:
        for point in turret.firing_points:
            if point and is_instance_valid(point):
                return point.global_position
        if turret.has_method("get_fallback_firing_origin"):
            return turret.get_fallback_firing_origin()
        if turret.barrel_mount and is_instance_valid(turret.barrel_mount):
            return turret.barrel_mount.global_position
    return global_position

func _get_world_gravity_vector() -> Vector3:
    var gravity_dir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3(0, -1, 0))
    var gravity_mag: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
    return gravity_dir * gravity_mag

func _solve_intercept_time_no_gravity(relative_pos: Vector3, relative_vel: Vector3, projectile_speed: float) -> float:
    var speed_sq: float = projectile_speed * projectile_speed
    var a: float = relative_vel.length_squared() - speed_sq
    var b: float = 2.0 * relative_pos.dot(relative_vel)
    var c: float = relative_pos.length_squared()

    # Degenerate to linear equation when quadratic term is near zero.
    if absf(a) <= 0.0001:
        if absf(b) <= 0.0001:
            return -1.0
        var linear_t: float = -c / b
        return linear_t if linear_t > 0.0 else -1.0

    var discriminant: float = b * b - 4.0 * a * c
    if discriminant < 0.0:
        return -1.0

    var sqrt_discriminant: float = sqrt(discriminant)
    var inv_2a: float = 0.5 / a
    var t0: float = (-b - sqrt_discriminant) * inv_2a
    var t1: float = (-b + sqrt_discriminant) * inv_2a

    var best_t: float = INF
    if t0 > 0.0 and t0 < best_t:
        best_t = t0
    if t1 > 0.0 and t1 < best_t:
        best_t = t1

    return -1.0 if best_t == INF else best_t

func _get_active_camera(delta: float) -> Camera3D:
    _camera_cache_timer = maxf(_camera_cache_timer - delta, 0.0)
    if _cached_camera and is_instance_valid(_cached_camera) and _camera_cache_timer > 0.0:
        return _cached_camera
    _cached_camera = get_viewport().get_camera_3d()
    _camera_cache_timer = 0.25
    return _cached_camera

func _get_effective_target_search_interval(delta: float) -> float:
    var near_interval: float = maxf(target_search_interval_s, 0.05)
    var far_interval: float = maxf(distant_target_search_interval_s, near_interval)
    var camera := _get_active_camera(delta)
    if camera == null or not is_instance_valid(camera):
        return far_interval
    var focus_node: Node3D = host_actor if host_actor and is_instance_valid(host_actor) else self
    if focus_node.global_position.distance_squared_to(camera.global_position) <= detailed_targeting_distance_m * detailed_targeting_distance_m:
        return near_interval
    return far_interval

func _predict_ballistic_aim_point(
    shooter_pos: Vector3,
    shooter_vel: Vector3,
    target_pos: Vector3,
    target_vel: Vector3,
    projectile_speed: float
) -> Vector3:
    var muzzle_speed: float = maxf(projectile_speed, 50.0)
    var gravity_vec: Vector3 = _get_world_gravity_vector()
    var relative_pos: Vector3 = target_pos - shooter_pos
    var relative_vel: Vector3 = target_vel - shooter_vel

    var intercept_t: float = _solve_intercept_time_no_gravity(relative_pos, relative_vel, muzzle_speed)
    if intercept_t <= 0.0:
        intercept_t = relative_pos.length() / muzzle_speed
    intercept_t = clampf(intercept_t, 0.05, 6.0)

    var best_intercept: Vector3 = target_pos + target_vel * intercept_t
    var best_muzzle_vec: Vector3 = Vector3.ZERO

    # Refine time-of-flight with gravity by matching required muzzle speed.
    for _i in range(4):
        var future_target: Vector3 = target_pos + target_vel * intercept_t
        var required_muzzle_vec: Vector3 = (future_target - shooter_pos - shooter_vel * intercept_t - 0.5 * gravity_vec * intercept_t * intercept_t) / intercept_t
        var required_speed: float = required_muzzle_vec.length()
        if required_speed <= 0.0001:
            break

        best_intercept = future_target
        best_muzzle_vec = required_muzzle_vec

        var speed_error: float = required_speed - muzzle_speed
        if absf(speed_error) <= 0.5:
            break

        intercept_t = clampf(intercept_t * (required_speed / muzzle_speed), 0.05, 6.0)

    if best_muzzle_vec.length_squared() < 0.001:
        var fallback_t: float = shooter_pos.distance_to(target_pos) / muzzle_speed
        return target_pos + target_vel * fallback_t

    var launch_dir: Vector3 = best_muzzle_vec.normalized()
    var aim_dist: float = maxf((best_intercept - shooter_pos).length(), 50.0)
    return shooter_pos + launch_dir * aim_dist

func calculate_lead_position(target: Node3D) -> Vector3:
    var target_pos: Vector3 = _get_target_aim_point(target)
    var target_velocity: Vector3 = _get_node_velocity(target)
    var shooter_pos: Vector3 = _get_aim_origin()
    var shooter_velocity: Vector3 = _get_point_velocity_at_world_position(shooter_pos)
    var bullet_speed: float = _get_weapon_projectile_speed()
    var lead_position: Vector3 = _predict_ballistic_aim_point(
        shooter_pos,
        shooter_velocity,
        target_pos,
        target_velocity,
        bullet_speed
    )

    # Apply pre-computed noise offset (updated on a timer, not per frame).
    return lead_position + _noise_offset

func _get_target_aim_point(target: Node3D) -> Vector3:
    if not target or not is_instance_valid(target):
        return global_position
    var collision_shape: CollisionShape3D = _find_collision_shape(target)
    if collision_shape and is_instance_valid(collision_shape):
        return collision_shape.global_position + collision_shape.global_basis.y.normalized() * _get_shape_vertical_extent(collision_shape) * 0.35
    var body_node: Node3D = target.get_node_or_null("Body") as Node3D
    if body_node and is_instance_valid(body_node):
        return body_node.global_position + body_node.global_basis.y.normalized() * target_aim_height_bias_m
    return target.global_position + Vector3.UP * target_aim_height_bias_m

func _find_collision_shape(node: Node) -> CollisionShape3D:
    if not node or not is_instance_valid(node):
        return null
    for child in node.get_children():
        if child is CollisionShape3D:
            return child as CollisionShape3D
    return null

func _get_shape_vertical_extent(collision_shape: CollisionShape3D) -> float:
    if not collision_shape or not is_instance_valid(collision_shape) or collision_shape.shape == null:
        return target_aim_height_bias_m
    var shape: Shape3D = collision_shape.shape
    if shape is BoxShape3D:
        return (shape as BoxShape3D).size.y * 0.5
    if shape is CapsuleShape3D:
        var capsule := shape as CapsuleShape3D
        return capsule.height * 0.5 + capsule.radius
    if shape is SphereShape3D:
        return (shape as SphereShape3D).radius
    if shape is CylinderShape3D:
        return (shape as CylinderShape3D).height * 0.5
    return target_aim_height_bias_m

func _is_air_target(target: Node3D) -> bool:
    return target != null and (target.is_in_group("aircraft") or target.is_in_group("ai_aircraft"))

func _get_effective_range_for_target(target: Node3D) -> float:
    var range_multiplier: float = air_target_range_multiplier if _is_air_target(target) else 1.0
    return maxf(max_range * range_multiplier, 1.0)

func _get_effective_aim_skill(target: Node3D) -> float:
    var skill_multiplier: float = air_target_aim_skill_multiplier if _is_air_target(target) else 1.0
    return clampf(aim_skill * skill_multiplier, 0.0, 1.0)

func _get_effective_fire_angle_tolerance_deg(target: Node3D) -> float:
    var tolerance_multiplier: float = air_target_fire_angle_tolerance_multiplier if _is_air_target(target) else 1.0
    return maxf(fire_angle_tolerance_deg * tolerance_multiplier, 0.5)
