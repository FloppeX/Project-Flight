extends Node3D
class_name TurretController

const PROJECTILE_SPEED_CAP_SETTING_KEYS: Array = [
    "physics/jolt_3d/simulation/limits/max_linear_velocity",
    "physics/jolt_physics_3d/simulation/limits/max_linear_velocity",
    "physics/jolt_3d/limits/max_linear_velocity",
    "physics/jolt_physics_3d/limits/max_linear_velocity",
    "physics/3d/max_linear_velocity",
]

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
@export var debug_print_each_bullet_result: bool = true
@export var debug_summary_interval_s: float = 1.0
@export_group("Air Target Penalties")
@export var air_target_range_multiplier: float = 1.0
@export var air_target_aim_skill_multiplier: float = 1.0
@export var air_target_fire_angle_tolerance_multiplier: float = 1.0
@export var air_target_extra_spread_m: float = 0.0
@export_group("Lead Estimation")
@export var prefer_measured_target_velocity: bool = true
@export var prefer_reported_velocity_for_physics_targets: bool = true
@export var measured_target_velocity_smoothing_hz: float = 10.0
@export var measured_target_velocity_max_speed_mps: float = 1400.0
@export var measured_target_velocity_max_step_m: float = 180.0

# --- Firing configuration ---
@export_group("AI Firing")
@export var burst_length: float = 1.5
@export var delay_length: float = 3.0
@export var stop_firing_if_target_lost: bool = true
@export var fire_angle_tolerance_deg: float = 18.0
@export var require_line_of_sight_to_fire: bool = true

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
var _debug_shots_fired_window: int = 0
var _debug_reports_window: int = 0
var _debug_hits_window: int = 0
var _debug_edge_distance_sum_window: float = 0.0
var _debug_best_edge_distance_window: float = INF

# Aim noise: updated on a timer so the turret can actually track each position
# rather than chasing a point that jumps every physics frame.
@export var noise_update_interval_s: float = 0.45
var _noise_offset: Vector3 = Vector3.ZERO
var _noise_timer: float = 0.0

# Target acceleration tracking for second-order lead prediction.
# Linear-only prediction systematically under-leads accelerating targets.
var _prev_target_velocity: Vector3 = Vector3.ZERO
var _target_acceleration: Vector3 = Vector3.ZERO
var _accel_tracking_active: bool = false
var _current_target_velocity: Vector3 = Vector3.ZERO
var _current_target_velocity_valid: bool = false
var _measured_target_velocity: Vector3 = Vector3.ZERO
var _last_target_position: Vector3 = Vector3.ZERO
var _last_target_position_valid: bool = false
var _projectile_speed_cap_cached: bool = false
var _projectile_speed_cap_mps: float = INF

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
    if host_actor and is_instance_valid(host_actor) and host_actor.has_method("get_team"):
        team = int(host_actor.get_team())

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
        _reset_target_motion_tracking()

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
        # Estimate actual world-space target velocity from position deltas (with
        # fallback to reported linear_velocity/velocity). This avoids wrappers
        # or stale properties causing systematic under-lead.
        var cur_target_vel: Vector3 = _get_effective_target_velocity(current_target, delta)
        _current_target_velocity = cur_target_vel
        _current_target_velocity_valid = true

        # Update acceleration estimate from velocity changes between frames.
        if _accel_tracking_active:
            var raw_accel: Vector3 = (cur_target_vel - _prev_target_velocity) / maxf(delta, 0.001)
            # Smooth to avoid jitter from single-frame spikes.
            _target_acceleration = _target_acceleration.lerp(raw_accel, clampf(4.0 * delta, 0.0, 1.0))
        else:
            _accel_tracking_active = true
            _target_acceleration = Vector3.ZERO
        _prev_target_velocity = cur_target_vel

        var lead_position := calculate_lead_position(current_target)
        turret.aim_at_point(lead_position)
        turret.tick(delta, lead_position)

        var aim_angle := turret.get_aim_angle_to_target()
        var aimed := aim_angle >= 0.0 and aim_angle <= _get_effective_fire_angle_tolerance_deg(current_target)
        var has_line_of_sight: bool = _has_line_of_sight_to_aim_point(lead_position, current_target)

        # 3. Burst firing logic
        if aimed and has_line_of_sight:
            update_burst_firing(delta)
        elif fire_state == FireState.DELAYING:
            update_burst_firing(delta)
        else:
            if fire_state == FireState.BURSTING:
                fire_state = FireState.DELAYING
                delay_timer = 0.0
            stop_firing()

        if debug_enabled:
            # Throttled debug summary per turret
            _debug_print_timer += delta
            if _debug_print_timer >= maxf(debug_summary_interval_s, 0.1):
                _debug_print_timer = 0.0
                var dist: float = global_position.distance_to(current_target.global_position)
                var lead_offset: Vector3 = lead_position - current_target.global_position
                var tgt_vel: Vector3 = cur_target_vel
                var shooter_vel: Vector3 = _get_point_velocity_at_world_position(_get_aim_origin())
                var flight_t: float = dist / maxf(_get_weapon_projectile_speed(), 1.0)
                var avg_edge_m: float = -1.0
                if _debug_reports_window > 0:
                    avg_edge_m = _debug_edge_distance_sum_window / float(_debug_reports_window)
                var best_edge_m: float = _debug_best_edge_distance_window if _debug_reports_window > 0 else -1.0
                var hit_rate: float = float(_debug_hits_window) / float(maxi(_debug_reports_window, 1))
                print("[TC %s] tgt=%s dist=%.0fm tVel=(%.0f,%.0f,%.0f) sVel=(%.0f,%.0f,%.0f) accel=(%.1f,%.1f,%.1f) lead_ofs=(%.1f,%.1f,%.1f) flight_t=%.2fs aim=%.2fdeg shots=%d reports=%d hits=%d hit_rate=%.2f best_miss=%.2fm avg_miss=%.2fm state=%s" % [
                    get_parent().name if get_parent() else name,
                    current_target.name, dist,
                    tgt_vel.x, tgt_vel.y, tgt_vel.z,
                    shooter_vel.x, shooter_vel.y, shooter_vel.z,
                    _target_acceleration.x, _target_acceleration.y, _target_acceleration.z,
                    lead_offset.x, lead_offset.y, lead_offset.z,
                    flight_t,
                    aim_angle,
                    _debug_shots_fired_window,
                    _debug_reports_window,
                    _debug_hits_window,
                    hit_rate,
                    best_edge_m,
                    avg_edge_m,
                    FireState.keys()[fire_state]
                ])
                _debug_shots_fired_window = 0
                _debug_reports_window = 0
                _debug_hits_window = 0
                _debug_edge_distance_sum_window = 0.0
                _debug_best_edge_distance_window = INF
    else:
        turret.set_target(null)
        stop_firing()
        fire_state = FireState.IDLE
        _reset_target_motion_tracking()

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
        if debug_enabled:
            if current_target and is_instance_valid(current_target):
                weapon_instance.set_meta("debug_target_node", current_target)
                var aim_origin: Vector3 = _get_aim_origin()
                var target_point: Vector3 = _get_target_aim_point(current_target)
                var muzzle_speed: float = _get_weapon_projectile_speed()
                weapon_instance.set_meta("debug_nominal_flight_time_s", aim_origin.distance_to(target_point) / maxf(muzzle_speed, 1.0))
            else:
                weapon_instance.remove_meta("debug_target_node")
                weapon_instance.remove_meta("debug_nominal_flight_time_s")
            weapon_instance.set_meta("debug_report_callback", Callable(self, "_on_bullet_debug_report"))
        turret.fire()
        var fired_ok: bool = bool(weapon_instance.fire())
        if debug_enabled and fired_ok:
            _debug_shots_fired_window += 1
            # Legacy fallback path; primary metadata handoff now happens before
            # weapon fire so projectile debug setup sees it immediately.
            _attach_debug_tracking_to_last_projectile(current_target)

# --- Advanced targeting ---

func find_and_set_best_target() -> void:
    var best_target: Node3D = null
    var best_priority: int = 999999
    var best_distance: float = INF

    var candidates = _get_hostile_targets_in_range(max_range)
    for enemy in candidates:
        var enemy_node := enemy as Node3D
        if enemy_node == null or not is_instance_valid(enemy_node):
            continue
        var d: float = global_position.distance_to(enemy_node.global_position)
        if d > _get_effective_range_for_target(enemy_node):
            continue
        if turret and is_instance_valid(turret) and not turret.is_point_within_yaw_arc(enemy_node.global_position):
            continue
        if not _is_within_targeting_fov(enemy_node):
            continue
        var priority: int = _get_target_priority(enemy_node)
        if priority < best_priority or (priority == best_priority and d < best_distance):
            best_target = enemy_node
            best_priority = priority
            best_distance = d

    if current_target != best_target:
        current_target = best_target
        _reset_target_motion_tracking()
        if turret and is_instance_valid(turret):
            turret.set_target(current_target)

func _get_hostile_targets_in_range(range_limit: float) -> Array:
    var results: Array = []

    # Determine hostile groups based on our team:
    #   team 1 (friendly/carrier) shoots at enemies
    #   team 2 (enemy) shoots at player and friendly aircraft
    var target_groups: Array
    var effective_team: int = _get_effective_team()
    if effective_team == 1:
        target_groups = ["enemies", "aircraft", "ai_aircraft", "ground_vehicles"]
    else:
        target_groups = ["enemies", "aircraft", "friendlies", "ai_aircraft", "carrier", "ground_vehicles"]

    for group_name in target_groups:
        for node in get_tree().get_nodes_in_group(group_name):
            if not is_instance_valid(node) or not node is Node3D:
                continue
            if node == self or node == get_parent() or node == host_actor:
                continue
            if node.has_method("get_team"):
                var node_team: int = int(node.call("get_team"))
                if node_team == effective_team:
                    continue
            if global_position.distance_to((node as Node3D).global_position) <= range_limit:
                results.append(node)

    # Deduplicate
    var unique_results = []
    for node in results:
        if not unique_results.has(node):
            unique_results.append(node)

    return unique_results

func _get_effective_team() -> int:
    if host_actor and is_instance_valid(host_actor) and host_actor.has_method("get_team"):
        return int(host_actor.get_team())
    return team

func _is_within_targeting_fov(target: Node3D) -> bool:
    if target == null or not is_instance_valid(target):
        return false
    var clamped_fov: float = clampf(field_of_view, 0.0, 360.0)
    if clamped_fov >= 359.9:
        return true
    var forward: Vector3 = global_transform.basis.z.normalized()
    if forward.length_squared() <= 0.0001:
        return true
    var to_target: Vector3 = (target.global_position - global_position).normalized()
    if to_target.length_squared() <= 0.0001:
        return true
    var cos_half_fov: float = cos(deg_to_rad(clamped_fov * 0.5))
    return forward.dot(to_target) >= cos_half_fov

func _get_target_priority(target: Node3D) -> int:
    if target == null or not is_instance_valid(target):
        return 1000
    if _is_air_target(target):
        return 0
    if target.is_in_group("ground_vehicles"):
        return 1
    if target.is_in_group("carrier"):
        return 2
    return 3

func _resolve_host_actor() -> Node3D:
    var node: Node = self
    while node:
        if node != self and node.has_method("get_team") and node is Node3D:
            return node as Node3D
        node = node.get_parent()
    return null

func _reset_target_motion_tracking() -> void:
    _accel_tracking_active = false
    _target_acceleration = Vector3.ZERO
    _prev_target_velocity = Vector3.ZERO
    _current_target_velocity = Vector3.ZERO
    _current_target_velocity_valid = false
    _measured_target_velocity = Vector3.ZERO
    _last_target_position = Vector3.ZERO
    _last_target_position_valid = false
    _debug_shots_fired_window = 0
    _debug_reports_window = 0
    _debug_hits_window = 0
    _debug_edge_distance_sum_window = 0.0
    _debug_best_edge_distance_window = INF

func _get_effective_target_velocity(target: Node3D, delta: float) -> Vector3:
    var reported_velocity: Vector3 = _get_node_velocity(target)
    if not prefer_measured_target_velocity:
        return reported_velocity
    if _is_reported_target_velocity_reliable(target, reported_velocity):
        _measured_target_velocity = reported_velocity
        _last_target_position = target.global_position
        _last_target_position_valid = true
        return reported_velocity
    return _measure_target_world_velocity(target, delta, reported_velocity)

func _is_reported_target_velocity_reliable(target: Node3D, reported_velocity: Vector3) -> bool:
    if target == null or not is_instance_valid(target):
        return false
    if reported_velocity.length_squared() <= 1.0:
        return false
    if not prefer_reported_velocity_for_physics_targets:
        return false
    if target is PhysicsBody3D:
        return true
    if target.has_method("get_velocity_vector"):
        return true
    return false

func _measure_target_world_velocity(target: Node3D, delta: float, fallback_velocity: Vector3) -> Vector3:
    if not target or not is_instance_valid(target):
        _last_target_position_valid = false
        return fallback_velocity

    var current_pos: Vector3 = target.global_position
    if (not _last_target_position_valid) or delta <= 0.0:
        _last_target_position = current_pos
        _last_target_position_valid = true
        _measured_target_velocity = fallback_velocity
        return _measured_target_velocity

    var displacement: Vector3 = current_pos - _last_target_position
    _last_target_position = current_pos

    if displacement.length() > measured_target_velocity_max_step_m:
        # Likely teleport/origin shift; trust reported velocity this frame.
        _measured_target_velocity = fallback_velocity
        return _measured_target_velocity

    var raw_velocity: Vector3 = displacement / maxf(delta, 0.001)
    if raw_velocity.length() > measured_target_velocity_max_speed_mps:
        _measured_target_velocity = fallback_velocity
        return _measured_target_velocity

    var blend: float = clampf(measured_target_velocity_smoothing_hz * delta, 0.0, 1.0)
    _measured_target_velocity = _measured_target_velocity.lerp(raw_velocity, blend)
    if fallback_velocity.length_squared() > 0.01:
        _measured_target_velocity = _measured_target_velocity.lerp(fallback_velocity, minf(blend * 0.35, 0.35))
    return _measured_target_velocity

func _get_last_fired_projectile_from_weapon() -> Node:
    if not weapon_instance or not is_instance_valid(weapon_instance):
        return null
    var projectile_variant: Variant = weapon_instance.get("last_fired_projectile")
    if typeof(projectile_variant) != TYPE_OBJECT:
        return null
    if not (projectile_variant is Node):
        return null
    var projectile_node: Node = projectile_variant as Node
    if projectile_node == null or not is_instance_valid(projectile_node):
        return null
    return projectile_node

func _attach_debug_tracking_to_last_projectile(target: Node3D) -> void:
    if not debug_enabled:
        return
    if target == null or not is_instance_valid(target):
        return
    var projectile_node: Node = _get_last_fired_projectile_from_weapon()
    if projectile_node == null:
        return
    projectile_node.set_meta("debug_target_node", target)
    projectile_node.set_meta("debug_report_callback", Callable(self, "_on_bullet_debug_report"))

func _on_bullet_debug_report(report: Dictionary) -> void:
    if not debug_enabled:
        return
    _debug_reports_window += 1
    var hit_target: bool = bool(report.get("hit_target", false))
    if hit_target:
        _debug_hits_window += 1

    var closest_edge_m: float = float(report.get("closest_edge_m", INF))
    if is_finite(closest_edge_m):
        _debug_edge_distance_sum_window += closest_edge_m
        _debug_best_edge_distance_window = minf(_debug_best_edge_distance_window, closest_edge_m)

    if debug_print_each_bullet_result:
        var target_name: String = str(report.get("target_name", "<none>"))
        var closest_center_m: float = float(report.get("closest_center_m", INF))
        var reason: String = str(report.get("reason", "unknown"))
        var bullet_age_s: float = float(report.get("bullet_age_s", -1.0))
        var closest_time_s: float = float(report.get("closest_time_s", -1.0))
        var nominal_flight_s: float = float(report.get("bullet_nominal_flight_time_s", -1.0))
        var speed_nominal_mps: float = float(report.get("bullet_nominal_speed_mps", -1.0))
        var speed_initial_mps: float = float(report.get("bullet_initial_speed_mps", -1.0))
        var speed_avg_mps: float = float(report.get("bullet_avg_speed_mps", -1.0))
        var speed_avg_integrated_mps: float = float(report.get("bullet_avg_speed_integrated_mps", -1.0))
        var speed_now_mps: float = float(report.get("bullet_speed_now_mps", -1.0))
        var speed_peak_mps: float = float(report.get("bullet_speed_peak_mps", -1.0))
        var speed_max_linear_mps: float = float(report.get("bullet_max_linear_velocity_mps", -1.0))
        var traveled_m: float = float(report.get("bullet_distance_traveled_m", -1.0))
        print("[TC %s] BULLET target=%s hit=%s closest_center=%.2fm closest_edge=%.2fm reason=%s age=%.2fs t_closest=%.2fs t_nom=%.2fs v_nom=%.0f v_init=%.0f v_avg=%.0f v_int=%.0f v_now=%.0f v_peak=%.0f v_cap=%.0f dist=%.1fm" % [
            get_parent().name if get_parent() else name,
            target_name,
            str(hit_target),
            closest_center_m,
            closest_edge_m,
            reason,
            bullet_age_s,
            closest_time_s,
            nominal_flight_s,
            speed_nominal_mps,
            speed_initial_mps,
            speed_avg_mps,
            speed_avg_integrated_mps,
            speed_now_mps,
            speed_peak_mps,
            speed_max_linear_mps,
            traveled_m
        ])

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
    if node.has_method("get_velocity_vector"):
        var vector_velocity = node.call("get_velocity_vector")
        if vector_velocity is Vector3:
            return vector_velocity
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

func _has_line_of_sight_to_aim_point(aim_point: Vector3, target: Node3D) -> bool:
    if not require_line_of_sight_to_fire:
        return true
    if target == null or not is_instance_valid(target):
        return false

    var origin: Vector3 = _get_aim_origin()
    if origin.distance_squared_to(aim_point) <= 0.0001:
        return true

    var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, aim_point)
    params.collision_mask = 0xFFFFFFFF
    params.exclude = _build_los_exclusion_rids()
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
    if hit.is_empty():
        return true

    var collider_variant: Variant = hit.get("collider", null)
    if typeof(collider_variant) != TYPE_OBJECT or not is_instance_valid(collider_variant):
        return false
    return _is_target_or_target_child(collider_variant as Object, target)

func _build_los_exclusion_rids() -> Array:
    var exclude_rids: Array = []
    var node: Node = self
    while node != null:
        if node is CollisionObject3D and is_instance_valid(node):
            exclude_rids.append((node as CollisionObject3D).get_rid())
        node = node.get_parent()
    return exclude_rids

func _is_target_or_target_child(collider_obj: Object, target: Node3D) -> bool:
    if collider_obj == null or target == null:
        return false
    if collider_obj == target:
        return true
    if collider_obj is Node:
        var node: Node = collider_obj as Node
        while node != null:
            if node == target:
                return true
            node = node.get_parent()
    return false

func _get_weapon_projectile_speed() -> float:
    var nominal_speed_mps: float = 600.0
    if weapon_instance:
        var muzzle_speed = weapon_instance.get("muzzle_velocity")
        if typeof(muzzle_speed) in [TYPE_FLOAT, TYPE_INT]:
            nominal_speed_mps = maxf(float(muzzle_speed), 50.0)
        else:
            var bullet_speed = weapon_instance.get("bullet_speed")
            if typeof(bullet_speed) in [TYPE_FLOAT, TYPE_INT]:
                nominal_speed_mps = maxf(float(bullet_speed), 50.0)
    var speed_cap_mps: float = _get_projectile_linear_speed_cap_mps()
    if is_finite(speed_cap_mps):
        return maxf(minf(nominal_speed_mps, speed_cap_mps), 50.0)
    return nominal_speed_mps

func _get_projectile_linear_speed_cap_mps() -> float:
    if _projectile_speed_cap_cached:
        return _projectile_speed_cap_mps
    _projectile_speed_cap_cached = true
    _projectile_speed_cap_mps = INF
    for key_variant in PROJECTILE_SPEED_CAP_SETTING_KEYS:
        var key: String = str(key_variant)
        if not ProjectSettings.has_setting(key):
            continue
        var cap_variant: Variant = ProjectSettings.get_setting(key)
        if typeof(cap_variant) in [TYPE_FLOAT, TYPE_INT]:
            var cap_mps: float = float(cap_variant)
            if cap_mps > 0.0:
                _projectile_speed_cap_mps = cap_mps
                break
    return _projectile_speed_cap_mps

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
    projectile_speed: float,
    target_accel: Vector3 = Vector3.ZERO
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
    # Include target acceleration for second-order prediction.
    for _i in range(4):
        var future_target: Vector3 = target_pos + target_vel * intercept_t + 0.5 * target_accel * intercept_t * intercept_t
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
        return target_pos + target_vel * fallback_t + 0.5 * target_accel * fallback_t * fallback_t

    var launch_dir: Vector3 = best_muzzle_vec.normalized()
    var aim_dist: float = maxf((best_intercept - shooter_pos).length(), 50.0)
    return shooter_pos + launch_dir * aim_dist

func calculate_lead_position(target: Node3D) -> Vector3:
    var target_pos: Vector3 = _get_target_aim_point(target)
    var target_velocity: Vector3 = _get_node_velocity(target)
    if target == current_target and _current_target_velocity_valid:
        target_velocity = _current_target_velocity
    var shooter_pos: Vector3 = _get_aim_origin()
    var shooter_velocity: Vector3 = _get_point_velocity_at_world_position(shooter_pos)
    var bullet_speed: float = _get_weapon_projectile_speed()
    var lead_position: Vector3 = _predict_ballistic_aim_point(
        shooter_pos,
        shooter_velocity,
        target_pos,
        target_velocity,
        bullet_speed,
        _target_acceleration
    )

    # Apply pre-computed noise offset (updated on a timer, not per frame).
    return lead_position + _noise_offset

func _get_target_aim_point(target: Node3D) -> Vector3:
    if not target or not is_instance_valid(target):
        return global_position
    var collision_shape: CollisionShape3D = _find_collision_shape(target)
    if collision_shape and is_instance_valid(collision_shape):
        # Use world-up for vertical bias. Some target colliders are rotated so their
        # local Y axis points forward/backward, which can bias aim behind/ahead.
        return collision_shape.global_position + Vector3.UP * _get_shape_vertical_extent(collision_shape) * 0.35
    var body_node: Node3D = target.get_node_or_null("Body") as Node3D
    if body_node and is_instance_valid(body_node):
        return body_node.global_position + Vector3.UP * target_aim_height_bias_m
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
