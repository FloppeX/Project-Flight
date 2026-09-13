extends Node3D

## Isolated production-pilot exercise: durable non-firing targets, real weapons,
## normal aircraft damage and collidable ground. No attack-control overrides.
class Target:
	extends StaticBody3D
	var current_health := 1000.0
	var damage_total := 0.0
	var damage_events := 0
	func get_team() -> int:
		return 2
	func take_damage(amount: float) -> void:
		damage_total += amount
		damage_events += 1 # Persistent target permits repeated passes.

var weapon_focus := "Guns"
var output := "user://ground_attack_diagnostic.json"
var duration := 240.0
var offset := 0.0
var ridge := false
var full_planner := false
var alternate_axis := false
var legacy_direct_revalidation := false
var reentry_start := false
var start_heading_deg := NAN
var start_speed_mps := 100.0
var legacy_rocket_refresh := false
var legacy_rocket_clutter := false
var started_us := 0
var elapsed := 0.0
var craft: RigidBody3D
var pilot: AIPilot
var targets: Array[Target] = []
var weapons: Array[Weapon] = []
var result := {"trace": [], "states_s": {}, "commit_gates_s": {}, "end_reasons_s": {},
	"commit_events": [], "release_times_s": [], "first_damage_s": -1.0,
	"projectiles": [],
	"releases": 0, "first_release_s": -1.0, "first_commit_s": -1.0,
	"min_agl_m": 100000.0, "terrain_intervention_s": 0.0, "hashes": {}, "settings": {}}

func _ready() -> void:
	started_us = Time.get_ticks_usec()
	# This small fixed-coordinate arena does not require floating-origin shifts.
	get_node("/root/FloatingOrigin").set("enabled", false)
	for autoload_name in ["FlightDirector", "AirOpsManager", "EnemyOpsManager", "GroundOpsManager", "OperationsCoordinator"]:
		var manager := get_node_or_null("/root/" + autoload_name)
		if manager != null:
			manager.process_mode = Node.PROCESS_MODE_DISABLED
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ground-weapon="): weapon_focus = arg.get_slice("=", 1)
		elif arg.begins_with("--ground-output="): output = arg.get_slice("=", 1)
		elif arg.begins_with("--ground-duration="): duration = clampf(float(arg.get_slice("=", 1)), 10, 600)
		elif arg.begins_with("--ground-offset="): offset = float(arg.get_slice("=", 1))
		elif arg.begins_with("--ground-heading="): start_heading_deg = float(arg.get_slice("=", 1))
		elif arg.begins_with("--ground-speed="): start_speed_mps = clampf(float(arg.get_slice("=", 1)), 70.0, 160.0)
		elif arg == "--ground-ridge": ridge = true
		elif arg == "--ground-full-planner": full_planner = true
		elif arg == "--ground-legacy-axis": alternate_axis = false
		elif arg == "--ground-alternate-axis": alternate_axis = true
		elif arg == "--ground-legacy-direct-revalidation": legacy_direct_revalidation = true
		elif arg == "--ground-reentry": reentry_start = true
		elif arg == "--ground-legacy-rocket-refresh": legacy_rocket_refresh = true
		elif arg == "--ground-legacy-rocket-clutter": legacy_rocket_clutter = true
	assert(weapon_focus in ["Guns", "Rocket Pod", "Bomb"])
	if is_nan(start_heading_deg): start_heading_deg = 180.0 if reentry_start else 0.0
	assert(is_finite(start_heading_deg) and is_finite(start_speed_mps))
	seed(20260909)
	result.hashes[get_script().resource_path] = FileAccess.get_sha256(get_script().resource_path)
	for path in ["res://AI/AIPilot.gd", "res://AI/FlightPathFollower.gd", "res://Aircraft/Aircraft_5.tscn",
		"res://AI/GroundTargetPriority.gd", "res://AirOps/Flight.gd",
		"res://Projectiles/Rocket/rocket.gd", "res://Projectiles/BombNew/bomb_new.gd",
		"res://Projectiles/Explosion/explosion.gd", "res://Projectiles/ProjectileNew/projectile_new.gd",
		"res://Projectiles/Bullet/bullet.gd", "res://Projectiles/Bullet/BulletPool.gd",
		"res://Projectiles/Bullet/bullet.tscn", "res://Projectiles/HeavyRound/heavy_round.gd",
		"res://Projectiles/HeavyRound/heavy_round.tscn", "res://Projectiles/SmallExplosiveRound/small_explosive_round.tscn",
		"res://Aircraft/SimpleAero.gd", "res://Aircraft/aircraft.gd", "res://Tests/GroundAttackDiagnostic.gd",
		"res://Weapons/Bomb/bomb_rack.gd", "res://Weapons/RocketPod/rocket_pod.gd",
		"res://Weapons/Autocannon/autocannon.gd"]:
		result.hashes[path] = FileAccess.get_sha256(path)
	_box(Vector3(0, -25, 0), Vector3(40000, 50, 40000))
	if ridge:
		_box(Vector3(0, 130, 800), Vector3(3000, 260, 400))
	call_deferred("_run")

func _box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.position = pos
	add_child(body)

func _terrain_height(pos: Vector3) -> float:
	return 260.0 if ridge and absf(pos.x) <= 1500 and pos.z >= 600 and pos.z <= 1000 else 0.0

func _run() -> void:
	for entry in [["Depot", "buildings", Vector3(250, 4, -300)],
		["GunEmplacement", "gun_emplacements", Vector3(0, 4, 0)]]:
		var target := Target.new()
		target.name = entry[0]
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(12, 8, 12)
		collider.shape = shape
		target.add_child(collider)
		target.position = entry[2]
		add_child(target)
		target.add_to_group(entry[1])
		target.add_to_group("enemies")
		targets.append(target)
	craft = preload("res://Aircraft/Aircraft_5.tscn").instantiate()
	craft.position = Vector3(offset, 600, -2600)
	if reentry_start:
		craft.position = Vector3(offset, 500, -1800)
	craft.rotation.y = deg_to_rad(start_heading_deg)
	add_child(craft)
	craft.set("team", 1)
	craft.remove_from_group("aircraft")
	craft.add_to_group("friendlies")
	craft.set_meta("carrier_transport_mode", false)
	craft.set_meta("controls_disabled", false)
	craft.set_meta("heli_test_unlimited_ammo", true)
	craft.set_meta("airplane_test_persistent_bomb_tuning", true)
	craft.set_meta("airplane_test_persistent_rocket_tuning", true)
	craft.linear_velocity = craft.global_basis.z * start_speed_mps
	craft.freeze = false
	await get_tree().process_frame
	await get_tree().process_frame
	craft.get_node("AIToggle").enable_ai()
	pilot = craft.get_node("AIPilot")
	pilot.skill = 2
	pilot.apply_skill_preset()
	pilot.debug_enabled = false
	pilot.verbose_debug_enabled = false
	pilot.ground_attack_enabled = true
	pilot.dogfight_enabled = false
	pilot.land_after_launch = false
	pilot._land_after_climb = false
	pilot.rtb_fuel_threshold = 0.0
	pilot.rtb_health_threshold = 0.0
	pilot.engagement_radius_from_carrier_m = 0.0
	pilot.disengage_radius_from_carrier_m = 0.0
	pilot._terrain_height_callable = _terrain_height
	pilot.set_ground_attack_forced_weapon_type(weapon_focus)
	pilot.ground_attack_alternate_axis_enabled = alternate_axis
	pilot.ground_attack_direct_revalidation_enabled = not legacy_direct_revalidation
	pilot.rocket_ccip_precision_refresh_enabled = not legacy_rocket_refresh
	craft.rocket_ccip_ignore_projectiles = not legacy_rocket_clutter
	result["rocket_ccip_ignore_projectiles"] = not legacy_rocket_clutter
	if full_planner:
		pilot.ground_attack_direct_intercept_enabled = false
		pilot.ground_attack_direct_fire_intercept_enabled = false
	var gear: Node = craft.find_child("ControlLandingGear", true, false)
	if gear != null: gear.stow_gear()
	_collect_weapons(craft)
	for weapon in weapons:
		if weapon is BombRack or weapon is RocketPod:
			weapon.set_tuning_context(_released, Callable(), 1, null)
		elif weapon is Autocannon:
			weapon.ammo_count = 1000000
			weapon.set_tuning_context(_released, Callable(), 1, null)
	result["loadout"] = weapons.map(func(w): return {"name": w.weapon_name, "ammo": w.ammo_count})
	for property in pilot.get_property_list():
		var key := String(property.name)
		if "attack" in key or key.begins_with("bomb_") or key.begins_with("rocket_"):
			var value: Variant = pilot.get(key)
			if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]: result.settings[key] = value
	# Only supply known identities; production selection chooses the target.
	pilot.known_enemies.assign(targets)
	var chosen: Node3D = pilot._find_ground_attack_target()
	result["initial_target"] = str(chosen.name) if chosen != null else "none"
	if reentry_start and chosen != null:
		# Reproduce a post-waveoff outbound pose without spending a first pass
		# reaching it. Only the initial state changes; controls remain production.
		pilot._direct_intercept_blocked_target_id = chosen.get_instance_id()
	pilot.set_target(chosen)
	result["initial_pose"] = {"position": _vector(craft.position), "velocity": _vector(craft.linear_velocity),
		"forward": _vector(craft.global_basis.z), "requested_heading_deg": start_heading_deg,
		"requested_speed_mps": start_speed_mps}
	print("GROUND_DIAGNOSTIC_START weapon=%s target=%s offset=%.0f ridge=%s" % [weapon_focus, result.initial_target, offset, ridge])
	_write("RUNNING")
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var tick := 0
	var observed_commits := 0
	while elapsed < duration:
		await get_tree().physics_frame
		elapsed += dt
		if not is_instance_valid(craft) or not is_instance_valid(pilot) or craft.current_health <= 0:
			break
		var state: String = AIPilot.State.keys()[pilot.current_state]
		_count("states_s", state, dt)
		_count("commit_gates_s", pilot.get_attack_last_commit_reason(), dt)
		_count("end_reasons_s", pilot.get_attack_last_end_reason(), dt)
		result.min_agl_m = minf(result.min_agl_m, craft.position.y - _terrain_height(craft.position))
		if pilot.get_attack_commit_count() > 0 and result.first_commit_s < 0: result.first_commit_s = elapsed
		if result.first_damage_s < 0:
			for target in targets:
				if target.damage_total > 0: result.first_damage_s = elapsed
		if pilot.get_attack_commit_count() > observed_commits:
			observed_commits = pilot.get_attack_commit_count()
			var capture := pilot._ground_attack_axis_guidance(craft.position, craft.linear_velocity,
				pilot._attack_setup_target_pos, pilot._direct_intercept_axis_direction, 400.0)
			result.commit_events.append({"t": elapsed, "count": observed_commits,
				"pos": _vector(craft.position), "speed": craft.linear_velocity.length(),
				"bank": pilot._get_current_bank_angle_deg(), "axis": _vector(pilot._direct_intercept_axis_direction),
				"axis_capture": capture, "reason": pilot.get_attack_last_commit_reason()})
		if pilot._safety_override_active and pilot._recovery_control_owner == "terrain": result.terrain_intervention_s += dt
		if weapon_focus == "Rocket Pod" and state == "ATTACK_DIVE":
			if not result.has("rocket_aim_trace"): result["rocket_aim_trace"] = []
			result.rocket_aim_trace.append({"t": elapsed, "miss": _finite(pilot._rocket_ccip_miss_m),
				"pos": _vector(craft.global_position), "forward": _vector(craft.global_basis.z),
				"rates": _vector(craft.global_basis.inverse() * craft.angular_velocity),
				"inputs": [pilot.roll_input, pilot.pitch_input, pilot.yaw_input],
				"waypoint": _vector(pilot.maneuver_waypoint), "ccip": _vector(pilot._ccip_cached_result),
				"burst": pilot._is_rocket_pod_burst_in_progress(), "releases": result.releases})
		if tick % 30 == 0:
			var target: Node3D = pilot.combat_target if is_instance_valid(pilot.combat_target) else null
			var axis_capture := pilot._ground_attack_axis_guidance(craft.global_position, craft.linear_velocity,
				pilot._attack_setup_target_pos, pilot._direct_intercept_axis_direction, 400.0)
			result.trace.append({"t": elapsed, "state": state, "pos": [craft.position.x, craft.position.y, craft.position.z],
				"speed": craft.linear_velocity.length(), "vy": craft.linear_velocity.y, "bank": pilot._get_current_bank_angle_deg(),
				"target": str(target.name) if target else "none", "commit": pilot.get_attack_last_commit_reason(),
				"end": pilot.get_attack_last_end_reason(), "run_weapon": pilot._run_weapon_type,
				"bomb_block": pilot.get_last_bomb_release_block_reason(), "rocket_block": pilot.get_last_rocket_release_block_reason(),
				"safety": pilot._safety_override_active, "releases": result.releases,
				"inputs": [pilot.roll_input, pilot.pitch_input, pilot.yaw_input],
				"axis_search_ms": pilot._ground_attack_axis_search_ms,
				"short_join_count": pilot._ground_attack_short_join_count,
				"short_join_check_ms": pilot._ground_attack_short_join_check_ms,
				"direct_revalidations": pilot._ground_attack_direct_revalidation_count,
				"direct_revalidation_reason": pilot._ground_attack_direct_revalidation_reason,
				"direct_revalidation_ms": pilot._ground_attack_direct_revalidation_ms,
				"axis": _vector(pilot._direct_intercept_axis_direction),
				"axis_joining": pilot._direct_intercept_axis_joining,
				"axis_guidance_active": pilot._direct_intercept_axis_guidance_active,
				"entry_range_m": pilot._direct_intercept_entry_range_m,
				"entry_waypoint": _vector(pilot._direct_intercept_entry_waypoint) if pilot._direct_intercept_entry_waypoint != Vector3.INF else null,
				"axis_cross_m": axis_capture.get("cross_m", null),
				"axis_along_m": axis_capture.get("along_m", null),
				"axis_heading_deg": axis_capture.get("heading_deg", null),
				"desired_bank": rad_to_deg(pilot._navigation_desired_bank_rad_debug),
				"track_rate": rad_to_deg(pilot._attack_turn_track_rate_rad_s),
				"velocity": _vector(craft.linear_velocity),
				"forward": _vector(craft.global_basis.z),
				"bomb_miss": _finite(pilot.get_last_bomb_release_miss_m()),
				"rocket_miss": _finite(pilot.get_last_rocket_release_miss_m()),
				"route_role": pilot._active_route_leg_role(), "route_index": pilot.current_waypoint_index,
				"waypoint": [pilot.nav_waypoint.x, pilot.nav_waypoint.y, pilot.nav_waypoint.z]})
		if tick % 1800 == 0:
			print("GROUND_PROGRESS t=%.0f state=%s releases=%d commits=%d" % [elapsed, state, result.releases, pilot.get_attack_commit_count()])
			_write("RUNNING")
		tick += 1
	result["aircraft_alive"] = is_instance_valid(craft) and craft.current_health > 0
	result["commits"] = pilot.get_attack_commit_count() if is_instance_valid(pilot) else -1
	result["targets"] = targets.map(func(t): return {"name": t.name, "damage": t.damage_total, "events": t.damage_events})
	_write("COMPLETE")
	print("GROUND_DIAGNOSTIC_COMPLETE output=%s releases=%d alive=%s" % [output, result.releases, result.aircraft_alive])
	get_tree().quit()

func _collect_weapons(node: Node) -> void:
	if node is Weapon: weapons.append(node)
	for child in node.get_children(): _collect_weapons(child)

func _released(_id: int, _projectile: Node = null) -> void:
	result.releases += 1
	result.release_times_s.append(elapsed)
	if result.first_release_s < 0: result.first_release_s = elapsed
	if not is_instance_valid(_projectile) or not _projectile.has_signal("tuning_impact_detail"):
		return
	var target_pos: Vector3 = pilot._get_surface_target_position(pilot.combat_target)
	var entry := {"release_s": elapsed, "release_pos": _vector(_projectile.global_position),
		"target_pos": _vector(target_pos), "status": "in_flight"}
	var predicted: Vector3 = _projectile.get_meta("debug_predicted_impact", Vector3.ZERO)
	if weapon_focus == "Rocket Pod":
		predicted = pilot._ccip_cached_result
	if predicted != Vector3.ZERO:
		entry["predicted_pos"] = _vector(predicted)
		entry["predicted_miss_m"] = Vector2(predicted.x - target_pos.x, predicted.z - target_pos.z).length()
	var index: int = result.projectiles.size()
	result.projectiles.append(entry)
	_projectile.connect("tuning_impact_detail", _impact.bind(index), CONNECT_ONE_SHOT)

func _impact(pos: Vector3, body: Node, index: int) -> void:
	var entry: Dictionary = result.projectiles[index]
	entry["impact_s"] = elapsed
	entry["impact_pos"] = _vector(pos)
	entry["body"] = str(body.name) if is_instance_valid(body) else "none"
	entry["body_is_projectile"] = body is ProjectileNew if is_instance_valid(body) else false
	entry["status"] = "collision" if is_instance_valid(body) else "expired_or_cleanup"
	var target: Array = entry.target_pos
	entry["actual_miss_m"] = Vector2(pos.x - target[0], pos.z - target[2]).length()
	if entry.has("predicted_pos"):
		var predicted: Array = entry.predicted_pos
		entry["prediction_error_m"] = Vector2(pos.x - predicted[0], pos.z - predicted[2]).length()

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _finite(value: float) -> Variant:
	return value if is_finite(value) else null

func _count(field: String, key: String, dt: float) -> void:
	result[field][key] = float(result[field].get(key, 0.0)) + dt

func _write(status: String) -> void:
	result["status"] = status
	result["duration_s"] = elapsed
	result["weapon"] = weapon_focus
	result["offset_m"] = offset
	result["ridge"] = ridge
	result["reentry_start"] = reentry_start
	result["requested_heading_deg"] = start_heading_deg
	result["requested_speed_mps"] = start_speed_mps
	result["wall_duration_s"] = (Time.get_ticks_usec() - started_us) * 0.000001
	result["physics_hz"] = Engine.physics_ticks_per_second
	result["targets"] = targets.map(func(t): return {"name": t.name, "damage": t.damage_total, "events": t.damage_events})
	result["hashes_verified"] = true
	for path in result.hashes:
		if FileAccess.get_sha256(path) != result.hashes[path]: result.hashes_verified = false
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
