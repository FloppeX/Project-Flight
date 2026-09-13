extends "res://Scenario/DogfightTestMode.gd"

## Opt-in, single-round production-pilot duel. No scripted/invulnerable targets.
var duel_log_path := "user://guns_only_duel.log"
var _camera: Camera3D
var _hud: Label
var _view_index := 0
var _capture_done := false
var _telemetry_timer := 0.0
var _summary_written := false
var _settings_verified := true
var _duel_seed := 20260909
var _input_hashes := {}
var _shot_stats := {}
var _duel_swap := false
var _duel_same_model := false
var _duel_tail_entry := false
var _duel_crossing := false
var _duel_close_parallel := false
var _duel_skills := [2, 2]
var _effective_pilot_settings := {}
var _expected_pilot_settings := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--duel-log="):
			duel_log_path = arg.trim_prefix("--duel-log=")
		elif arg.begins_with("--duel-seed="):
			_duel_seed = int(arg.get_slice("=", 1))
		elif arg == "--duel-swap":
			_duel_swap = true
		elif arg == "--duel-same-model":
			_duel_same_model = true
		elif arg == "--duel-tail-entry":
			_duel_tail_entry = true
		elif arg == "--duel-crossing":
			_duel_crossing = true
		elif arg == "--duel-close-parallel":
			_duel_close_parallel = true
		elif arg.begins_with("--duel-skill-a="):
			_duel_skills[0] = clampi(int(arg.get_slice("=", 1)), 0, 4)
		elif arg.begins_with("--duel-skill-b="):
			_duel_skills[1] = clampi(int(arg.get_slice("=", 1)), 0, 4)
	seed(_duel_seed)
	merge_test_mode = true
	real_dogfight_mode = true
	merge_aircraft_scene = FRIENDLY_SCENE
	merge_aircraft_scene_b = BANDIT_SCENE
	if _duel_same_model:
		merge_aircraft_scene_b = FRIENDLY_SCENE
	elif _duel_swap:
		merge_aircraft_scene = BANDIT_SCENE
		merge_aircraft_scene_b = FRIENDLY_SCENE
	merge_altitude_m = 1000.0
	arena_altitude_m = merge_altitude_m
	merge_speed_mps = 100.0
	merge_closing_range_m = 1500.0
	merge_lateral_offset_m = 300.0
	merge_skill = 2
	round_auto_restart = false
	round_max_duration_s = 240.0
	for path in ["res://AI/AIPilot.gd", "res://AI/VisualContactTrack.gd", "res://AI/FlightPathFollower.gd",
			"res://AI/PilotSkillProfile.gd", "res://Scenario/DogfightTestMode.gd",
			"res://AI/EvasiveFlight.gd", "res://Projectiles/ProjectileNew/projectile_new.gd",
			"res://Aircraft/SimpleAero.gd", "res://Aircraft/aircraft.gd", "res://Aircraft/Aircraft_3.tscn", "res://Aircraft/Aircraft_5.tscn",
			"res://Scenario/GunsOnlyDuel.gd", "res://Weapons/Autocannon/autocannon.gd", "res://Projectiles/Bullet/bullet.gd"]:
		_input_hashes[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(duel_log_path, FileAccess.WRITE)
	if file != null:
		file.close()
	_suppress_carrier_air_ops()
	_build_observation_scene()
	_log("DUEL_START %s vs %s; tail_entry=%s; seed=%d; guns only; normal health/ammo; 1000m; 100m/s; single 240s round" % [merge_aircraft_scene.resource_path, merge_aircraft_scene_b.resource_path, _duel_tail_entry, _duel_seed])
	call_deferred("_spawn_merge_test")

func _flat_terrain_height(_position: Vector3) -> float:
	return 0.0

func _spawn_merge_test() -> void:
	super._spawn_merge_test()
	await get_tree().process_frame
	await get_tree().process_frame
	# Identity is assigned, but perception still decides whether it can be tracked.
	if _combatants.size() == 2:
		for index in 2:
			var craft: Node = _combatants[index].node
			var pilot: AIPilot = craft.find_child("AIPilot", true, false)
			pilot.set_target(_combatants[1 - index].node)
			var effective := {"skill": int(pilot.skill), "perception": pilot.get_combat_skill_profile(), "dogfight": {}}
			for property in pilot.get_property_list():
				var key := String(property.name)
				if key.begins_with("dogfight_"):
					effective.dogfight[key] = pilot.get(key)
					_settings_verified = _settings_verified and pilot.get(key) == _expected_pilot_settings[str(craft.name)][key]
			_effective_pilot_settings[str(craft.name)] = effective
			_settings_verified = _settings_verified and int(pilot.skill) == int(_duel_skills[index])
			_log("EFFECTIVE_PILOT name=%s settings=%s" % [craft.name, JSON.stringify(effective)])
	get_tree().create_timer(2.5).timeout.connect(_verify_loadouts)

func _verify_loadouts() -> void:
	for entry in _combatants:
		var craft: Variant = entry.node
		if not is_instance_valid(craft):
			continue
		var hardpoints: Array[Node] = []
		_collect_hardpoints(craft, hardpoints)
		var guns := 0
		var non_guns := 0
		for hp in hardpoints:
			var weapon: Variant = hp.get("weapon_instance")
			if is_instance_valid(weapon):
				if _is_gun(weapon):
					guns += 1
					if weapon.has_method("set_tuning_context"):
						var target: Node3D = _combatants[1 if int(entry.team) == 1 else 0].node
						weapon.set_tuning_context(_on_duel_shot, _on_duel_report.bind(str(entry.name)), int(entry.team), target)
				else:
					non_guns += 1
		_log("LOADOUT_VERIFIED name=%s guns=%d non_guns=%d" % [entry.name, guns, non_guns])
		assert(guns > 0 and non_guns == 0, "Duel requires guns only on both aircraft")

func _spawn_ai_fighter(scene: PackedScene, fighter_name: String, team: int, pos: Vector3,
		heading: float, speed_mps: float, skill_override: int = -1) -> RigidBody3D:
	# The legacy harness overrides aiming and tactical gains. Snapshot authored
	# values before entering it, then restore them before any physics tick.
	var pristine := scene.instantiate()
	var template := pristine.find_child("AIPilot", true, false)
	var selected_skill: int = int(_duel_skills[0 if team == 1 else 1])
	template.skill = selected_skill
	template.apply_skill_preset()
	var settings := {}
	for property in template.get_property_list():
		var key := String(property.name)
		if key.begins_with("dogfight_"):
			settings[key] = template.get(key)
	pristine.free()
	if _duel_tail_entry:
		pos = Vector3(0, merge_altitude_m, -500 if team == 1 else 0)
		heading = 0.0
	elif _duel_crossing:
		pos = Vector3(-700, merge_altitude_m, 0) if team == 1 else Vector3(0, merge_altitude_m, -700)
		heading = PI / 2.0 if team == 1 else 0.0
	elif _duel_close_parallel:
		pos = Vector3(-25 if team == 1 else 25, merge_altitude_m, 0)
		heading = 0.0
	var craft := super._spawn_ai_fighter(scene, fighter_name, team, pos, heading, speed_mps, selected_skill)
	if craft == null:
		return null
	var pilot := craft.find_child("AIPilot", true, false)
	pilot.set("_terrain_height_callable", Callable(self, "_flat_terrain_height"))
	_shot_stats[fighter_name] = {"shots": 0, "reports": 0, "hits": 0, "damage_events": 0, "damage": 0.0,
		"first_shot_s": -1.0, "min_separation_m": INF, "reset_time_s": 0.0,
		"peak_altitude_m": pos.y}
	craft.damaged.connect(_record_duel_damage.bind(fighter_name))
	var parts: Node = craft.get_node_or_null("PartDamageModel")
	if parts != null and parts.has_signal("zone_damaged"):
		parts.zone_damaged.connect(_record_zone_damage.bind(fighter_name))
	_log("MODEL name=%s advanced=%s ground_y=%s" % [fighter_name,
		craft.get_node("SimpleAero").is_advanced_flight_model(), pilot._get_ground_height_at_position(pos)])
	for key in settings:
		pilot.set(key, settings[key])
		_settings_verified = _settings_verified and pilot.get(key) == settings[key]
	_expected_pilot_settings[fighter_name] = settings.duplicate(true)
	_log("PRODUCTION_SETTINGS name=%s model=%s count=%d verified=%s" % [fighter_name, scene.resource_path, settings.size(), _settings_verified])
	return craft

func _on_duel_shot(team: int, _bullet: Node) -> void:
	if not _summary_written:
		var record: Dictionary = _shot_stats["Merge_A" if team == 1 else "Merge_B"]
		record.shots += 1
		if record.first_shot_s < 0.0:
			record.first_shot_s = _elapsed_s

func _on_duel_report(report: Dictionary, fighter_name: String) -> void:
	if _summary_written:
		return
	_shot_stats[fighter_name].reports += 1
	_shot_stats[fighter_name].hits += int(bool(report.get("hit_target", false)))
	_log("PROJECTILE name=%s %s" % [fighter_name, JSON.stringify(report)])

func _record_duel_damage(amount: float, _health: float, fighter_name: String) -> void:
	if not _summary_written:
		_shot_stats[fighter_name].damage_events += 1
		_shot_stats[fighter_name].damage += amount

func _record_zone_damage(zone: StringName, amount: float, health: float, maximum: float, fighter_name: String) -> void:
	if not _summary_written:
		_log("ZONE_DAMAGE name=%s zone=%s amount=%.2f health=%.2f/%.2f" % [fighter_name, zone, amount, health, maximum])

func _build_observation_scene() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_SKY
	world.environment.sky = Sky.new()
	world.environment.sky.sky_material = ProceduralSkyMaterial.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100000, 100000)
	mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.29, 0.22)
	mesh.material_override = material
	ground.add_child(mesh)
	add_child(ground)
	_camera = Camera3D.new()
	_camera.far = 50000
	_camera.fov = 65
	add_child(_camera)
	_camera.position = Vector3(0, 1020, -1600)
	_camera.make_current()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = Label.new()
	_hud.position = Vector2(20, 20)
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 2)
	_hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_hud)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_view_index = 1 - _view_index
		get_viewport().set_input_as_handled()

func _check_round_end() -> void:
	# Explosions can leave a zero-health body alive until its deferred destroyed
	# signal. Count that state now so a mutual collision cannot award it a win.
	for entry in _combatants:
		var craft: Variant = entry.node
		if is_instance_valid(craft) and float(craft.current_health) <= 0.0:
			_kills[entry.name] = true
	super._check_round_end()

func _physics_process(delta: float) -> void:
	if _summary_written:
		return
	# Debug truth is used only for measurement, never fed back into pilot tracks.
	for entry in _combatants:
		var craft: Variant = entry.node
		if not is_instance_valid(craft):
			continue
		var record: Dictionary = _shot_stats[entry.name]
		var pilot: Node = craft.get_node("AIPilot")
		record.peak_altitude_m = maxf(record.peak_altitude_m, craft.global_position.y)
		record.reset_time_s += delta if pilot._dogfight_reset_timer_s > 0.0 else 0.0
		for other in _combatants:
			if other.name != entry.name and is_instance_valid(other.node):
				record.min_separation_m = minf(record.min_separation_m, craft.global_position.distance_to(other.node.global_position))
	if not _round_over:
		super._physics_process(delta)
		if _started:
			_check_round_end()
	_update_observer(delta)
	_telemetry_timer += delta
	if _telemetry_timer >= 5.0 or (_round_over and not _summary_written):
		_telemetry_timer = 0.0
		for entry in _combatants:
			var craft: Variant = entry.node
			if is_instance_valid(craft):
				var pilot: Node = craft.find_child("AIPilot", true, false)
				_log("METRICS name=%s hp=%s %s" % [entry.name, craft.get("current_health"), JSON.stringify(pilot.get_dogfight_gunnery_metrics())])
		if _round_over:
			_summary_written = true
			var unchanged := true
			for path in _input_hashes:
				unchanged = unchanged and FileAccess.get_sha256(path) == _input_hashes[path]
			for entry in _combatants:
				var craft: Variant = entry.node
				if is_instance_valid(craft):
					var pilot: Node = craft.find_child("AIPilot", true, false)
					pilot._stop_firing()
					pilot.set_physics_process(false)
					craft.freeze = true
					_shot_stats[entry.name]["health_at_cutoff"] = craft.current_health
					var parts: Node = craft.get_node_or_null("PartDamageModel")
					if parts != null and parts.has_method("get_damage_state"):
						_shot_stats[entry.name]["part_damage_at_cutoff"] = parts.get_damage_state()
				_shot_stats[entry.name]["pending_at_cutoff"] = _shot_stats[entry.name].shots - _shot_stats[entry.name].reports
			var result := {"status": "COMPLETE", "duration_s": _elapsed_s, "seed": _duel_seed,
				"tail_entry": _duel_tail_entry,
				"crossing_entry": _duel_crossing, "close_parallel_entry": _duel_close_parallel,
				"aircraft_a": merge_aircraft_scene.resource_path, "aircraft_b": merge_aircraft_scene_b.resource_path,
				"physics_hz": Engine.physics_ticks_per_second, "hashes_verified": unchanged, "input_hashes": _input_hashes,
				"pilot_settings": _effective_pilot_settings,
				"settings_verified": _settings_verified,
				"stats": _shot_stats, "team1_wins": _round_wins_team1, "team2_wins": _round_wins_team2, "draws": _round_draws}
			var report := FileAccess.open(duel_log_path + ".json", FileAccess.WRITE)
			report.store_string(JSON.stringify(result, "\t"))
			report.close()
			_log("DUEL_COMPLETE %s" % JSON.stringify(result))
			if DisplayServer.get_name() == "headless":
				get_tree().quit.call_deferred()

func _update_observer(delta: float) -> void:
	if _combatants.size() < 2:
		return
	var craft: Variant = _combatants[_view_index].node
	if not is_instance_valid(craft):
		craft = _combatants[1 - _view_index].node
	if is_instance_valid(craft):
		var forward: Vector3 = craft.global_basis.z.normalized()
		var desired: Vector3 = craft.global_position - forward * 42.0 + Vector3.UP * 13.0
		_camera.global_position = _camera.global_position.lerp(desired, 1.0 - exp(-delta * 6.0))
		_camera.look_at(craft.global_position + forward * 65.0, Vector3.UP)
		_camera.make_current()
	var text := "GUNS ONLY  |  %.0f / 240 s\nTAB: switch aircraft  |  Normal damage and ammunition\n" % _elapsed_s
	for entry in _combatants:
		var fighter: Variant = entry.node
		var model := (merge_aircraft_scene if int(entry.team) == 1 else merge_aircraft_scene_b).resource_path.get_file().get_basename()
		if is_instance_valid(fighter) and not _kills.get(entry.name, false):
			text += "%s: HP %.0f  |  %.0f m/s  |  altitude %.0f m\n" % [model, float(fighter.get("current_health")), fighter.linear_velocity.length(), fighter.global_position.y]
		else:
			text += "%s: DESTROYED\n" % model
	if _round_over:
		text += "ROUND COMPLETE: " + ("Aircraft 5 wins" if _round_wins_team1 > 0 else ("Aircraft 3 wins" if _round_wins_team2 > 0 else "draw"))
	_hud.text = text
	if not _capture_done and _elapsed_s > 8.0 and DisplayServer.get_name() != "headless":
		_capture_done = true
		_capture_frame.call_deferred()

func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(duel_log_path + ".png")

func _log(message: String) -> void:
	print("[Duel] ", message)
	var file := FileAccess.open(duel_log_path, FileAccess.READ_WRITE)
	if file != null:
		file.seek_end()
		file.store_line(message)
