extends Node3D

# Dogfight test harness (fixed pilot, no GA -- see if the gun-fighter can hit scripted bandits).
# Spawns one friendly Aircraft_5 (team 1, gun only, dogfight AI on) plus two Aircraft_3 bandits
# (team 2, infinite health, AI off) driven by ScriptedBandit: one flying straight, one weaving.
# Reuses the AIPilot dogfight brain entirely -- this file only builds the arena and logs hits.

const FRIENDLY_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
const BANDIT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_3.tscn")
const TEST_GUN_SCENE: PackedScene = preload("res://Weapons/Guns/Hardpoint/15mm_machine_gun_hardpoint.tscn")
const BANDIT_SCRIPT: Script = preload("res://Scenario/ScriptedBandit.gd")

# Motion pattern constants (mirror ScriptedBandit.Pattern) referenced by plain value to avoid
# depending on the global class_name being registered before this script compiles.
const PATTERN_STRAIGHT: int = 0
const PATTERN_WEAVE: int = 1

const REPORT_PATH := "user://dogfight_test_report.log"
const SUMMARY_INTERVAL_S := 1.0

# Real dogfight: two friendly Aircraft_5 (full dogfight AI) start above+behind two slower
# Aircraft_3, all AI-controlled, fighting each other. Set false for the old scripted-bandit test.
@export var real_dogfight_mode: bool = true

# 1v1 NEUTRAL MERGE test: two equal experienced pilots (same aircraft) merge head-on. Diagnostic for
# how a clean neutral fight develops (lead turns, energy trade) with no bounce/skill advantage.
@export var merge_test_mode: bool = false
@export var merge_aircraft_scene: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
@export var merge_aircraft_scene_b: PackedScene = preload("res://Aircraft/Aircraft_2.tscn")  # side B: different aircraft, same pilot skill
@export var merge_altitude_m: float = 1000.0
@export var merge_speed_mps: float = 100.0
@export var merge_lateral_offset_m: float = 500.0     # sideways miss distance at the merge
@export var merge_closing_range_m: float = 2500.0     # each starts this far from the crossing point
@export var merge_skill: int = 2                       # EXPERIENCED both sides

@export var arena_altitude_m: float = 900.0
@export var friendly_speed_mps: float = 110.0
@export var bandit_speed_mps: float = 80.0    # Below the friendly (~1.4x) so it reels them in for a tail chase without blowing past on every pass
@export var bandit_separation_m: float = 900.0        # lateral spacing between the two bandits
@export var friendly_start_behind_m: float = 900.0    # friendly starts this far behind the bandits
@export var friendly_start_altitude_advantage_m: float = 600.0  # friendly starts this much higher (energy advantage for boom-and-zoom)
@export var weave_amplitude_deg: float = 22.0
@export var weave_period_s: float = 9.0

# Real-dogfight layout
@export var real_friendly_count: int = 2
@export var real_enemy_count: int = 2
@export var real_enemy_speed_mps: float = 75.0        # slower Aircraft_3 initial speed
@export var real_pair_separation_m: float = 500.0     # lateral spacing within each pair
@export var real_engagement_range_m: float = 1600.0   # enemies start this far ahead of the friendlies
@export var real_friendly_altitude_advantage_m: float = 700.0  # friendlies start this much above the enemies

# Auto-restart: when a team is eliminated (or the round times out) declare a result and start a fresh
# round after a short delay. Keeps the test running continuous rounds without manual relaunching.
@export var round_auto_restart: bool = true
@export var round_max_duration_s: float = 240.0       # draw/timeout cap so a stalemate doesn't hang forever
@export var round_restart_delay_s: float = 4.0        # pause between rounds
var _round_number: int = 1
var _round_over: bool = false
var _round_restart_timer_s: float = 0.0
var _round_wins_team1: int = 0
var _round_wins_team2: int = 0
var _round_draws: int = 0
var _round_start_elapsed_s: float = 0.0

var _play_area_center: Vector3 = Vector3.ZERO
var _friendly: RigidBody3D = null
var _friendly_pilot: Node = null
var _bandits: Array[RigidBody3D] = []
var _gun_shots_fired: int = 0
var _hits_by_bandit: Dictionary = {}                  # bandit_name -> hit count
var _elapsed_s: float = 0.0
var _summary_timer_s: float = 0.0
var _started: bool = false

# Real-dogfight combatants (all AI). name -> {node, team, hits_taken, alive}
var _combatants: Array = []
var _hits_taken: Dictionary = {}                      # name -> rounds absorbed
var _kills: Dictionary = {}                           # name -> destroyed bool

func configure(play_area_center: Vector3) -> void:
	_play_area_center = play_area_center

func _ready() -> void:
	# Truncate the report so each run's log is clean (avoids interleaved t= values across restarts).
	var truncate: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if truncate != null:
		truncate.close()
	_log("START dogfight test: 1 friendly (gun only) vs 2 bandits (straight + weave), infinite health")
	_suppress_carrier_air_ops()
	_clear_scene_clutter()
	# Defer spawn one frame so the scene tree and terrain are ready.
	call_deferred("_spawn_arena")

func _clear_scene_clutter() -> void:
	# Strip the normal-game world down to just terrain + our aircraft: remove buildings, enemy
	# bases, ground vehicles/platoons, gun emplacements, wind turbines, and enemy spawners so the
	# dogfight happens in a clean sky. Runs BEFORE the bandits spawn, so it can't touch them.
	# NOTE: do not clear "enemies"/"ai_aircraft" wholesale -- the bandits will join those groups.
	var clutter_groups: Array[String] = [
		"buildings", "enemy_bases", "ground_vehicles", "ground_vehicle_platoons",
		"gun_emplacements", "wind_turbines", "wind_turbine_proxies", "enemy_aircraft_spawner",
	]
	var removed: int = 0
	for group_name in clutter_groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node):
				node.queue_free()
				removed += 1
	# Also remove any pre-existing enemy AI aircraft from the normal scene (patrol flights etc.)
	# so only our two scripted bandits remain airborne.
	for node in get_tree().get_nodes_in_group("ai_aircraft"):
		if is_instance_valid(node):
			node.queue_free()
			removed += 1
	_log("SCENE_CLEARED removed=%d clutter nodes" % removed)

func _suppress_carrier_air_ops() -> void:
	# The carrier's AirOpsManager autoload scrambles/launches flights (helicopters etc.) during
	# normal ops -- irrelevant clutter for a controlled dogfight test. Stop its process loop, and
	# the enemy ops manager too, so nothing else spawns aircraft into the arena.
	# GroundOpsManager must be suppressed too -- we free the ground vehicles it tracks in
	# _clear_scene_clutter, and it spams "freed instance" errors trying to reference them otherwise.
	for autoload_name in ["AirOpsManager", "EnemyOpsManager", "GroundOpsManager"]:
		var node: Node = get_node_or_null("/root/" + autoload_name)
		if node != null:
			node.set_process(false)
			node.set_physics_process(false)
			_log("SUPPRESSED %s" % autoload_name)

func _spawn_arena() -> void:
	if merge_test_mode:
		_spawn_merge_test()
		return
	if real_dogfight_mode:
		_spawn_real_dogfight()
		return
	var center: Vector3 = _play_area_center
	center.y = arena_altitude_m
	var heading: float = 0.0  # both bandits fly toward +Z; friendly starts behind them

	# --- Bandits ---
	var forward: Vector3 = Vector3(sin(heading), 0.0, cos(heading))
	var right: Vector3 = Vector3.UP.cross(forward).normalized()
	var bandit_specs: Array = [
		{"name": "Bandit_Straight", "pattern": PATTERN_STRAIGHT, "lateral": -bandit_separation_m * 0.5},
		{"name": "Bandit_Weave", "pattern": PATTERN_WEAVE, "lateral": bandit_separation_m * 0.5},
	]
	for spec in bandit_specs:
		var spawn_pos: Vector3 = center + right * float(spec["lateral"])
		var bandit: RigidBody3D = _spawn_bandit(str(spec["name"]), spawn_pos, heading, int(spec["pattern"]))
		if bandit != null:
			_bandits.append(bandit)
			_hits_by_bandit[bandit.name] = 0

	# --- Friendly gun-fighter, starting behind AND above the bandits (energy advantage), pointed
	# at them. The height advantage is what the boom-and-zoom energy tactics work from.
	var friendly_pos: Vector3 = center - forward * friendly_start_behind_m + Vector3.UP * friendly_start_altitude_advantage_m
	_friendly = _spawn_friendly(friendly_pos, heading)
	_started = true
	_log("ARENA_READY center=%s alt=%.0f bandits=%d friendly=%s" % [
		_fmt(center), arena_altitude_m, _bandits.size(),
		"ok" if _friendly != null else "FAILED"])

func _spawn_real_dogfight() -> void:
	# Real fight: friendly Aircraft_5 pair (team 1) starts high + behind, diving on an enemy
	# Aircraft_3 pair (team 2) that is lower, slower, and ahead. All AI, fighting each other.
	var center: Vector3 = _play_area_center
	center.y = arena_altitude_m
	var heading: float = 0.0
	var forward: Vector3 = Vector3(sin(heading), 0.0, cos(heading))
	var right: Vector3 = Vector3.UP.cross(forward).normalized()

	# Enemies: lower, ahead, flying forward (away from the friendlies' entry).
	var enemy_base: Vector3 = center + forward * real_engagement_range_m
	for i in range(real_enemy_count):
		var lateral: float = (float(i) - (real_enemy_count - 1) * 0.5) * real_pair_separation_m
		var pos: Vector3 = enemy_base + right * lateral
		var enemy: RigidBody3D = _spawn_ai_fighter(
			BANDIT_SCENE, "Enemy_%d" % (i + 1), 2, pos, heading, real_enemy_speed_mps)
		if enemy != null:
			_register_combatant(enemy, 2)

	# Friendlies: above and behind, flying toward the enemies (the bounce).
	var friendly_base: Vector3 = center + Vector3.UP * real_friendly_altitude_advantage_m
	for i in range(real_friendly_count):
		var lateral: float = (float(i) - (real_friendly_count - 1) * 0.5) * real_pair_separation_m
		var pos: Vector3 = friendly_base + right * lateral
		var friendly: RigidBody3D = _spawn_ai_fighter(
			FRIENDLY_SCENE, "Friendly_%d" % (i + 1), 1, pos, heading, friendly_speed_mps)
		if friendly != null:
			_register_combatant(friendly, 1)
			if _friendly_pilot == null:
				_friendly = friendly
				_friendly_pilot = friendly.find_child("AIPilot", true, false)

	_started = true
	_log("REAL_DOGFIGHT_READY center=%s alt=%.0f friendlies=%d enemies=%d alt_adv=%.0f" % [
		_fmt(center), arena_altitude_m, real_friendly_count, real_enemy_count,
		real_friendly_altitude_advantage_m])

func _spawn_merge_test() -> void:
	# Two equal experienced pilots merge head-on. A flies +forward, B flies -forward, offset laterally by
	# merge_lateral_offset_m so they pass abeam; co-altitude, equal speed. A clean neutral merge.
	var center: Vector3 = _play_area_center
	center.y = merge_altitude_m
	var heading: float = 0.0
	var forward: Vector3 = Vector3(sin(heading), 0.0, cos(heading))
	var right: Vector3 = Vector3.UP.cross(forward).normalized()
	var half_off: Vector3 = right * (merge_lateral_offset_m * 0.5)

	# A: behind (−forward side), flying +forward. B: ahead (+forward side), flying −forward. Offset to
	# opposite sides of the centerline so they cross with merge_lateral_offset_m separation.
	var a_pos: Vector3 = center - forward * merge_closing_range_m + half_off
	var b_pos: Vector3 = center + forward * merge_closing_range_m - half_off
	var back_heading: float = heading + PI

	var scene_b: PackedScene = merge_aircraft_scene_b if merge_aircraft_scene_b != null else merge_aircraft_scene
	var a: RigidBody3D = _spawn_ai_fighter(merge_aircraft_scene, "Merge_A", 1, a_pos, heading, merge_speed_mps, merge_skill)
	if a != null:
		_register_combatant(a, 1)
	var b: RigidBody3D = _spawn_ai_fighter(scene_b, "Merge_B", 2, b_pos, back_heading, merge_speed_mps, merge_skill)
	if b != null:
		_register_combatant(b, 2)

	_started = true
	_log("MERGE_TEST_READY A=%s B=%s center=%s alt=%.0f offset=%.0f speed=%.0f skill=%d range=%.0f" % [
		merge_aircraft_scene.resource_path.get_file(), scene_b.resource_path.get_file(),
		_fmt(center), merge_altitude_m, merge_lateral_offset_m, merge_speed_mps, merge_skill, merge_closing_range_m])

func _register_combatant(node: RigidBody3D, team: int) -> void:
	_combatants.append({"node": node, "team": team, "name": node.name})
	_hits_taken[node.name] = 0
	_kills[node.name] = false
	if node.has_signal("damaged"):
		node.connect("damaged", Callable(self, "_on_combatant_damaged").bind(node.name))
	if node.has_signal("destroyed"):
		node.connect("destroyed", Callable(self, "_on_combatant_destroyed").bind(node.name))

func _on_combatant_damaged(_amount: float, _health: float, combatant_name: String) -> void:
	_hits_taken[combatant_name] = int(_hits_taken.get(combatant_name, 0)) + 1

func _on_combatant_destroyed(combatant_name: String) -> void:
	if not bool(_kills.get(combatant_name, false)):
		_kills[combatant_name] = true
		_log("KILL %s destroyed at t=%.1f" % [combatant_name, _elapsed_s])

# Spawn any aircraft scene as a full-AI dogfighter on a team, airborne and pointed along `heading`.
func _spawn_ai_fighter(scene: PackedScene, fighter_name: String, team: int, pos: Vector3,
		heading: float, speed_mps: float, skill_override: int = -1) -> RigidBody3D:
	var craft: RigidBody3D = scene.instantiate() as RigidBody3D
	if craft == null:
		_log("ERROR could not instantiate %s" % fighter_name)
		return null
	craft.name = fighter_name
	get_tree().current_scene.add_child(craft)
	craft.set("team", team)
	# Keep it OUT of "aircraft" (FlightDeckManager grabs that as the player and launch-sequences it).
	if craft.is_in_group("aircraft"):
		craft.remove_from_group("aircraft")
	if team == 1:
		craft.add_to_group("friendlies")
	else:
		craft.add_to_group("ai_aircraft")
		craft.add_to_group("enemies")
	craft.set_meta("carrier_transport_mode", false)
	craft.set_meta("controls_disabled", false)
	craft.freeze = false
	craft.global_transform = Transform3D(_basis_from_heading(heading), pos)
	var fwd: Vector3 = Vector3(sin(heading), 0.0, cos(heading))
	craft.linear_velocity = fwd * speed_mps

	var ai_toggle: Node = craft.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("enable_ai"):
		ai_toggle.call("enable_ai")
	_strip_to_gun_only(craft)
	var pilot: Node = craft.find_child("AIPilot", true, false)
	if pilot != null:
		pilot.set("ground_attack_enabled", false)
		pilot.set("dogfight_enabled", true)
		pilot.set("land_after_launch", false)
		pilot.set("_land_after_climb", false)
		pilot.set("rtb_health_threshold", 0.0)
		pilot.set("rtb_fuel_threshold", 0.0)
		pilot.set("sensor_range", 12000.0)
		pilot.set("carrier_position", Vector3(_play_area_center.x, arena_altitude_m, _play_area_center.z))
		pilot.set("engagement_radius_from_carrier_m", 0.0)
		pilot.set("disengage_radius_from_carrier_m", 0.0)
		pilot.set("dogfight_max_range_m", 9000.0)
		pilot.set("dogfight_rejoin_range_m", 3500.0)
		pilot.set("patrol_altitude_m", arena_altitude_m)
		pilot.set("dogfight_unrestricted_maneuvering", true)
		# Deflection snapshot gunnery so a good pass converts.
		pilot.set("dogfight_fire_precise_close_range_m", 800.0)
		pilot.set("dogfight_fire_precise_min_blend", 0.70)
		pilot.set("dogfight_fire_fallback_range_m", 450.0)
		pilot.set("dogfight_min_hit_chance", 0.35)
		pilot.set("dogfight_situational_awareness_enabled", true)
		# Skill drives situational awareness: friendlies are veterans (keep the picture, hard to shake),
		# enemies are rookies (lose sight easily) -- so the friendlies can exploit their bounce.
		# AIPilotSkill: RECRUIT=0 ROOKIE=1 EXPERIENCED=2 VETERAN=3 ELITE=4
		pilot.set("skill", skill_override if skill_override >= 0 else (3 if team == 1 else 1))
		# Verbose debug on just one fighter so we can watch its merge geometry without flooding the log.
		if fighter_name == "Friendly_1":
			pilot.set("debug_enabled", true)
			pilot.set("verbose_debug_enabled", true)
		if pilot.has_method("change_state"):
			pilot.call("change_state", AIPilot.State.SEARCH)
	# Retract landing gear on any aircraft that has it (airborne fighters -- less drag, realistic).
	_stow_gear(craft)
	_log("FIGHTER_SPAWNED name=%s team=%d pos=%s speed=%.0f" % [fighter_name, team, _fmt(pos), speed_mps])
	return craft

func _stow_gear(aircraft: RigidBody3D) -> void:
	# Retry over several frames: the gear ControlLandingGear.setup() FORCES gear "deploy" when it runs,
	# and its landing_gear_modules list is only populated there -- a single deferred stow races that and
	# gets clobbered (or finds no modules yet). So we re-issue the stow for a couple of seconds.
	_stow_gear_retry(aircraft, 0)

func _stow_gear_retry(aircraft: RigidBody3D, attempt: int) -> void:
	if not is_instance_valid(aircraft):
		return
	var control_gear: Node = aircraft.find_child("ControlLandingGear", true, false)
	if control_gear != null:
		if "LockGearDeployed" in control_gear:
			control_gear.set("LockGearDeployed", false)
		# Prefer the proper public method (also disables gear colliders + sets state); fall back to the
		# lower-level module forward if needed.
		if control_gear.has_method("stow_gear"):
			control_gear.call("stow_gear")
		elif control_gear.has_method("send_to_landing_gears"):
			control_gear.call("send_to_landing_gears", "stow")
	# Some aircraft expose a direct gear API on the pilot/aircraft.
	var pilot: Node = aircraft.find_child("AIPilot", true, false)
	if pilot != null and "gear_stowed" in pilot:
		pilot.set("gear_stowed", true)
	# Keep re-issuing for ~2s to win the race against a late setup()/rescan that re-deploys.
	if attempt < 20:
		get_tree().create_timer(0.1).timeout.connect(_stow_gear_retry.bind(aircraft, attempt + 1))
	elif control_gear != null and "gear_down_state" in control_gear:
		_log("GEAR_STATE name=%s gear_down=%s" % [aircraft.name, str(control_gear.get("gear_down_state"))])

func _spawn_bandit(bandit_name: String, pos: Vector3, heading: float, pattern: int) -> RigidBody3D:
	var bandit: RigidBody3D = BANDIT_SCENE.instantiate() as RigidBody3D
	if bandit == null:
		_log("ERROR could not instantiate bandit %s" % bandit_name)
		return null
	bandit.name = bandit_name
	get_tree().current_scene.add_child(bandit)
	# Disable the bandit's own AI so only the scripted motion drives it.
	var ai_toggle: Node = bandit.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("disable_ai"):
		ai_toggle.call("disable_ai")
	# Team 2 + hostile groups so the team-1 friendly's sensor sees it as an air enemy.
	bandit.set("team", 2)
	bandit.add_to_group("ai_aircraft")
	bandit.add_to_group("enemies")
	# Infinite health: keep it flying no matter how many rounds land, and count the hits.
	bandit.set("max_health", 1.0e12)
	if "current_health" in bandit:
		bandit.set("current_health", 1.0e12)
	if bandit.has_signal("damaged"):
		bandit.connect("damaged", Callable(self, "_on_bandit_damaged").bind(bandit.name))
	# Freeze physics and drive kinematically.
	bandit.freeze = true
	bandit.global_transform = Transform3D(_basis_from_heading(heading), pos)
	# Attach the scripted motion controller.
	var driver := Node.new()
	driver.set_script(BANDIT_SCRIPT)
	driver.name = "ScriptedBandit"
	bandit.add_child(driver)
	driver.set("pattern", pattern)
	driver.set("speed_mps", bandit_speed_mps)
	driver.set("weave_amplitude_deg", weave_amplitude_deg)
	driver.set("weave_period_s", weave_period_s)
	driver.set("arena_center", Vector3(_play_area_center.x, arena_altitude_m, _play_area_center.z))
	driver.call("setup", bandit, heading)
	_log("BANDIT_SPAWNED name=%s pattern=%s pos=%s" % [
		bandit_name, "weave" if pattern == PATTERN_WEAVE else "straight", _fmt(pos)])
	return bandit

func _spawn_friendly(pos: Vector3, heading: float) -> RigidBody3D:
	var friendly: RigidBody3D = FRIENDLY_SCENE.instantiate() as RigidBody3D
	if friendly == null:
		_log("ERROR could not instantiate friendly")
		return null
	friendly.name = "Friendly_GunFighter"
	get_tree().current_scene.add_child(friendly)
	friendly.set("team", 1)
	# CRITICAL: keep the friendly OUT of the "aircraft" group. FlightDeckManager grabs the first
	# node in that group as the "player aircraft" and runs a launch sequence on it -- which snapped
	# our airborne friendly back onto the carrier deck (the ~28km "teleport"). The Aircraft scene
	# adds itself to "aircraft" in its own _ready(), so remove it here, and flag it as not a
	# deck/transport aircraft so no deck logic touches it. Dogfight only needs team + RigidBody.
	if friendly.is_in_group("aircraft"):
		friendly.remove_from_group("aircraft")
	friendly.add_to_group("friendlies")
	friendly.set_meta("carrier_transport_mode", false)
	friendly.set_meta("controls_disabled", false)
	# Airborne, pointed at the bandits, with forward speed.
	friendly.freeze = false
	friendly.global_transform = Transform3D(_basis_from_heading(heading), pos)
	var forward: Vector3 = Vector3(sin(heading), 0.0, cos(heading))
	friendly.linear_velocity = forward * friendly_speed_mps

	# Enable AI, strip to gun only, turn on the dogfight brain.
	var ai_toggle: Node = friendly.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("enable_ai"):
		ai_toggle.call("enable_ai")
	_strip_to_gun_only(friendly)
	var pilot: Node = friendly.find_child("AIPilot", true, false)
	if pilot == null:
		_log("ERROR friendly has no AIPilot")
		return friendly
	_friendly_pilot = pilot
	pilot.set("ground_attack_enabled", false)
	pilot.set("dogfight_enabled", true)
	pilot.set("land_after_launch", false)
	pilot.set("rtb_health_threshold", 0.0)
	pilot.set("rtb_fuel_threshold", 0.0)
	pilot.set("sensor_range", 12000.0)
	# Air targets are gated by an engagement radius measured from carrier_position. Anchor that at
	# the arena and make it effectively unlimited so the bandits always qualify (0 = no limit).
	pilot.set("carrier_position", Vector3(_play_area_center.x, arena_altitude_m, _play_area_center.z))
	pilot.set("engagement_radius_from_carrier_m", 0.0)
	pilot.set("disengage_radius_from_carrier_m", 0.0)   # never give up on the bandit over distance (0 = unlimited)
	pilot.set("dogfight_max_range_m", 9000.0)
	pilot.set("dogfight_rejoin_range_m", 3500.0)        # stay in the pursuit rejoin longer before disengaging
	pilot.set("patrol_altitude_m", arena_altitude_m)
	pilot.set("debug_enabled", true)
	pilot.set("verbose_debug_enabled", true)   # print the dogfight FIGHT/fire-decision debug line
	pilot.set("land_after_launch", false)
	pilot.set("_land_after_climb", false)
	# Anything-goes maneuvering (roll/pull/yaw the target into the sights, go inverted if needed).
	pilot.set("dogfight_unrestricted_maneuvering", true)
	# Energy tactics: keep the floor low enough that the diving pass can still reach a gun solution
	# against these ~80 m/s bandits (a true low-slow helicopter would use a higher floor).
	pilot.set("dogfight_min_pursuit_height_m", 90.0)
	pilot.set("dogfight_energy_advantage_margin_m", 200.0)
	# Deflection gunnery: loosen the fire gate so it takes snapshot shots as it tracks/passes, not
	# only a perfect stabilized tail shot. Fire on a good solution out to a wider range and a lower
	# hit-chance floor -- the point is to spray rounds where the enemy is going.
	pilot.set("dogfight_fire_precise_close_range_m", 800.0)   # allow firing well before a perfect tail-park (was 300)
	pilot.set("dogfight_fire_precise_min_blend", 0.70)        # don't require the aim to be almost perfect (was 0.90)
	pilot.set("dogfight_fire_fallback_range_m", 450.0)        # wider close-range snapshot window (was 220)
	pilot.set("dogfight_min_hit_chance", 0.35)               # take lower-probability deflection shots (was 0.72)
	# CRITICAL: force the pilot into airborne SEARCH state. It defaults to LAUNCHING (thinks it's on
	# the catapult), and the launch/climb logic repositioned it to a carrier-relative launch point
	# near origin -- the real cause of the ~28km "teleport". Same call the airplane test uses.
	if pilot.has_method("change_state"):
		pilot.call("change_state", AIPilot.State.SEARCH)
	# Track gun fire for the shot count.
	_connect_gun_fire_tracking(friendly)
	_log("FRIENDLY_SPAWNED pos=%s speed=%.0f dogfight=on gun_only" % [_fmt(pos), friendly_speed_mps])
	return friendly

func _strip_to_gun_only(aircraft: RigidBody3D) -> void:
	var hardpoints: Array[Node] = []
	_collect_hardpoints(aircraft, hardpoints)
	var has_gun: bool = false
	for hp in hardpoints:
		var weapon_value: Variant = hp.get("weapon_instance")
		if is_instance_valid(weapon_value) and weapon_value is Node:
			if _is_gun(weapon_value as Node):
				has_gun = true
			else:
				# Remove non-gun weapons.
				(weapon_value as Node).queue_free()
				hp.set("weapon_instance", null)
	if not has_gun:
		_install_gun(aircraft, hardpoints)

func _install_gun(aircraft: RigidBody3D, hardpoints: Array[Node]) -> void:
	if hardpoints.is_empty():
		_log("WARN no hardpoints to install gun on")
		return
	var hp: Node = hardpoints[0]
	for candidate in hardpoints:
		if candidate.name == "Hardpoint3":
			hp = candidate
			break
	var gun: Node = TEST_GUN_SCENE.instantiate()
	hp.add_child(gun)
	if hp.has_method("set_weapon_instance"):
		hp.call("set_weapon_instance", gun)
	elif "weapon_instance" in hp:
		hp.set("weapon_instance", gun)
	_log("GUN_INSTALLED hardpoint=%s" % hp.name)

func _collect_hardpoints(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.get_class() == "Node3D" or "weapon_instance" in child:
			if child.has_method("get") and ("weapon_instance" in child or child is Hardpoint):
				out.append(child)
		_collect_hardpoints(child, out)

func _is_gun(weapon: Node) -> bool:
	var wn: String = str(weapon.get("weapon_name")) if "weapon_name" in weapon else weapon.name
	wn = wn.to_lower()
	return wn.find("gun") >= 0 or wn.find("cannon") >= 0 or wn.find("mm") >= 0

func _connect_gun_fire_tracking(aircraft: RigidBody3D) -> void:
	# Count rounds by watching the gun's fire signal if present; otherwise we rely on hit counts.
	var hardpoints: Array[Node] = []
	_collect_hardpoints(aircraft, hardpoints)
	for hp in hardpoints:
		var weapon_value: Variant = hp.get("weapon_instance")
		if is_instance_valid(weapon_value) and weapon_value is Node and _is_gun(weapon_value as Node):
			var gun: Node = weapon_value as Node
			if gun.has_signal("fired"):
				gun.connect("fired", Callable(self, "_on_gun_fired"))

func _on_gun_fired() -> void:
	_gun_shots_fired += 1

func _on_bandit_damaged(_amount: float, _health: float, bandit_name: String) -> void:
	_hits_by_bandit[bandit_name] = int(_hits_by_bandit.get(bandit_name, 0)) + 1

func _physics_process(delta: float) -> void:
	if not _started:
		return
	_elapsed_s += delta

	# Round restart countdown (after a team has won or a draw).
	if _round_over:
		_round_restart_timer_s -= delta
		if _round_restart_timer_s <= 0.0:
			_start_new_round()
		return

	_summary_timer_s += delta
	if _summary_timer_s >= SUMMARY_INTERVAL_S:
		_summary_timer_s = 0.0
		_log_summary()

	if round_auto_restart and (real_dogfight_mode or merge_test_mode):
		_check_round_end()

func _check_round_end() -> void:
	var team1_alive: int = 0
	var team2_alive: int = 0
	for c in _combatants:
		# Read as Variant first -- a typed (RigidBody3D) assignment errors on a freed instance.
		var node: Variant = c["node"]
		var cname: String = str(c["name"])
		if is_instance_valid(node) and not bool(_kills.get(cname, false)):
			if int(c["team"]) == 1: team1_alive += 1
			else: team2_alive += 1
	var timed_out: bool = _elapsed_s - _round_start_elapsed_s >= round_max_duration_s
	if team1_alive > 0 and team2_alive > 0 and not timed_out:
		return
	# Round is decided.
	_round_over = true
	_round_restart_timer_s = round_restart_delay_s
	var result: String
	if team1_alive > 0 and team2_alive == 0:
		result = "TEAM1_WIN"; _round_wins_team1 += 1
	elif team2_alive > 0 and team1_alive == 0:
		result = "TEAM2_WIN"; _round_wins_team2 += 1
	else:
		result = "DRAW"; _round_draws += 1
	_log("ROUND_OVER round=%d result=%s duration=%.1f team1_alive=%d team2_alive=%d | tally team1=%d team2=%d draws=%d" % [
		_round_number, result, _elapsed_s - _round_start_elapsed_s, team1_alive, team2_alive,
		_round_wins_team1, _round_wins_team2, _round_draws])

func _start_new_round() -> void:
	# Tear down all combatants from the finished round, then spawn a fresh one.
	for c in _combatants:
		var node: Variant = c["node"]
		if is_instance_valid(node):
			(node as Node).queue_free()
	_combatants.clear()
	_hits_taken.clear()
	_kills.clear()
	_friendly = null
	_friendly_pilot = null
	_round_over = false
	_round_number += 1
	_round_start_elapsed_s = _elapsed_s
	_log("ROUND_START round=%d" % _round_number)
	# Re-clear any clutter (dead wrecks, etc.) then respawn.
	_clear_scene_clutter()
	call_deferred("_spawn_merge_test" if merge_test_mode else "_spawn_real_dogfight")

func _log_summary() -> void:
	if real_dogfight_mode or merge_test_mode:
		_log_real_dogfight_summary()
		return
	var pilot_state: String = "?"
	if _friendly_pilot != null and is_instance_valid(_friendly_pilot):
		var st: Variant = _friendly_pilot.get("current_state")
		pilot_state = str(st)
	var total_hits: int = 0
	for k in _hits_by_bandit:
		total_hits += int(_hits_by_bandit[k])
	var friendly_pos: String = _fmt(_friendly.global_position) if _friendly != null and is_instance_valid(_friendly) else "(gone)"
	var range_to_nearest: float = _nearest_bandit_range()
	var spd: float = _friendly.linear_velocity.length() if _friendly != null and is_instance_valid(_friendly) else 0.0
	# Aim dot: how well the friendly's nose points at the nearest bandit (1.0 = dead on).
	var aim_dot: float = _nearest_bandit_aim_dot()
	var tactic: String = "?"
	if _friendly_pilot != null and is_instance_valid(_friendly_pilot):
		var t: Variant = _friendly_pilot.get("_dogfight_energy_tactic")
		var names: Array = ["NEUTRAL", "DIVING_ATTACK", "ZOOM_RESET", "EXTEND_REBUILD", "COMMITTED_ATTACK"]
		if t != null and int(t) >= 0 and int(t) < names.size():
			tactic = names[int(t)]
	var alt: float = _friendly.global_position.y if _friendly != null and is_instance_valid(_friendly) else 0.0
	_log("SAMPLE t=%.1f state=%s tactic=%s shots=%d hits=%d nearest_bandit=%.0fm spd=%.0f alt=%.0f aim_dot=%.3f hits_detail=%s" % [
		_elapsed_s, pilot_state, tactic, _gun_shots_fired, total_hits, range_to_nearest, spd, alt, aim_dot,
		str(_hits_by_bandit)])

func _log_real_dogfight_summary() -> void:
	# Per-combatant one-liner: team, alive/dead, altitude, speed, hits taken, state, tactic.
	var team1_alive: int = 0
	var team2_alive: int = 0
	for c in _combatants:
		var node: Variant = c["node"]  # Variant, not RigidBody3D -- typed read errors on a freed instance
		var cname: String = str(c["name"])
		var team: int = int(c["team"])
		var alive: bool = is_instance_valid(node) and not bool(_kills.get(cname, false))
		if alive:
			if team == 1: team1_alive += 1
			else: team2_alive += 1
		var alt: float = node.global_position.y if is_instance_valid(node) else 0.0
		var spd: float = node.linear_velocity.length() if is_instance_valid(node) else 0.0
		var st: String = "-"
		var tac: String = "-"
		var tgt: String = "none"
		var bank_deg: float = 0.0
		var pitch_input: float = 0.0
		var yaw_input: float = 0.0
		var alpha_deg: float = NAN
		var lift_ratio: float = NAN
		var assertive_turn: bool = false
		var turn_error_deg: float = 0.0
		if is_instance_valid(node):
			bank_deg = absf(rad_to_deg(atan2(
				node.global_transform.basis.x.y,
				node.global_transform.basis.y.y
			)))
			var pilot: Node = node.find_child("AIPilot", true, false)
			if pilot != null:
				st = str(pilot.get("current_state"))
				if "pitch_input" in pilot:
					pitch_input = float(pilot.get("pitch_input"))
				if "yaw_input" in pilot:
					yaw_input = float(pilot.get("yaw_input"))
				if "_dogfight_assertive_turn_active" in pilot:
					assertive_turn = bool(pilot.get("_dogfight_assertive_turn_active"))
				if "_dogfight_assertive_turn_yaw_error_deg" in pilot:
					turn_error_deg = float(pilot.get("_dogfight_assertive_turn_yaw_error_deg"))
				var t: Variant = pilot.get("_dogfight_energy_tactic")
				var names: Array = ["NEUTRAL", "DIVING_ATTACK", "ZOOM_RESET", "EXTEND_REBUILD", "COMMITTED_ATTACK"]
				if t != null and int(t) >= 0 and int(t) < names.size():
					tac = names[int(t)]
				var ct: Variant = pilot.get("combat_target")
				if ct != null and is_instance_valid(ct):
					tgt = str((ct as Node).name)
				var simple_aero: Variant = pilot.get("simple_aero")
				if is_instance_valid(simple_aero):
					if simple_aero.has_method("get_estimated_angle_of_attack_deg"):
						alpha_deg = float(simple_aero.call("get_estimated_angle_of_attack_deg"))
					if simple_aero.has_method("get_estimated_lift_ratio"):
						lift_ratio = float(simple_aero.call("get_estimated_lift_ratio"))
		_log("FIGHTER t=%.1f name=%s team=%d %s alt=%.0f spd=%.0f bank=%.0f pitch=%.2f yaw=%.2f alpha=%.1f lift=%.2f assertive=%s turn_err=%.0f hits_taken=%d state=%s tactic=%s target=%s" % [
			_elapsed_s, cname, team, ("ALIVE" if alive else "DEAD"), alt, spd,
			bank_deg, pitch_input, yaw_input, alpha_deg, lift_ratio, str(assertive_turn), turn_error_deg,
			int(_hits_taken.get(cname, 0)), st, tac, tgt])
	_log("SCORE t=%.1f team1_alive=%d team2_alive=%d" % [_elapsed_s, team1_alive, team2_alive])

func _nearest_bandit_aim_dot() -> float:
	if _friendly == null or not is_instance_valid(_friendly):
		return -2.0
	var nearest: RigidBody3D = null
	var nd: float = INF
	for b in _bandits:
		if is_instance_valid(b):
			var d: float = _friendly.global_position.distance_to(b.global_position)
			if d < nd:
				nd = d
				nearest = b
	if nearest == null:
		return -2.0
	var to_bandit: Vector3 = (nearest.global_position - _friendly.global_position).normalized()
	var nose: Vector3 = _friendly.global_transform.basis.z.normalized()
	return nose.dot(to_bandit)

func _nearest_bandit_range() -> float:
	if _friendly == null or not is_instance_valid(_friendly):
		return INF
	var nearest: float = INF
	for b in _bandits:
		if is_instance_valid(b):
			nearest = minf(nearest, _friendly.global_position.distance_to(b.global_position))
	return nearest

func _basis_from_heading(heading_rad: float) -> Basis:
	var forward: Vector3 = Vector3(sin(heading_rad), 0.0, cos(heading_rad))
	var up: Vector3 = Vector3.UP
	var right: Vector3 = up.cross(forward).normalized()
	up = forward.cross(right).normalized()
	return Basis(right, up, forward)

func _fmt(v: Vector3) -> String:
	return "(%.0f,%.0f,%.0f)" % [v.x, v.y, v.z]

func _log(msg: String) -> void:
	var line: String = msg
	print("[Dogfight] ", line)
	var f: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.READ_WRITE) if FileAccess.file_exists(REPORT_PATH) \
			else FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)
		f.close()
