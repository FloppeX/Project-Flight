extends Node3D
const Defense = preload("res://AI/EvasiveFlight.gd")
const Track = preload("res://AI/VisualContactTrack.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var own := {"position": Vector3(0, 1000, 0), "velocity": Vector3(0, 0, 90),
		"forward": Vector3.BACK, "bank": 0.5, "agl": 1000.0, "floor_agl": 150.0, "stall_speed": 40.0, "skill": 1.0}
	var threat := {"position": Vector3(120, 1000, -300), "velocity": Vector3(-40, 0, 110),
		"visible": true, "expired": false, "age_s": 0.0}
	var defense = Defense.new()
	for i in 30:
		check(defense.update(0.1, own, {}, true) == Vector3.ZERO, "No threat must not cause jinking")
	defense.report_damage(10, &"collision")
	check(defense.update(1, own, {}, true) == Vector3.ZERO, "Landing/contact damage is not incoming fire")
	for i in 20:
		defense.report_damage(10, &"near_miss")
		defense.update(0.1, own, {}, true)
	check(defense.episodes == 0, "Unimplemented near-miss reports cannot invent threat knowledge")
	var stale := threat.duplicate()
	stale.visible = false
	check(defense.update(1, own, stale, true) == Vector3.ZERO, "Remembered target cannot trigger visual evasion")
	defense.report_damage(1, &"projectile")
	check(defense.update(0.1, own, {}, true) == Vector3.ZERO, "Reaction is not instantaneous")
	var request: Vector3 = defense.update(0.25, own, {}, true)
	check(request != Vector3.ZERO and defense.reason == "projectile_damage", "Unknown-source projectile causes a break")
	check(request.x < 0 and request.y < own.position.y, "Own bank selects unknown-source direction; descending break allowed")
	var initial_direction: Vector3 = defense.direction
	for i in 10:
		defense.update(0.1, own, threat, true)
		check(defense.direction == initial_direction, "Threat changes cannot flip a committed break")
	for i in 100:
		defense.report_damage(1, &"projectile")
		defense.update(0.1, own, {}, true)
	check(defense.phase == "idle" and defense.cooldown_s > 0, "Repeated hits cannot extend defense forever")
	check(defense.episodes == 1, "Cooldown prevents repeated break loop")
	defense = Defense.new()
	check(defense.update(0.4, own, threat, true) != Vector3.ZERO, "Persistent observed attack geometry triggers a break")
	defense = Defense.new()
	own.velocity = Vector3(0, 0, 50)
	defense.report_damage(5, &"projectile")
	defense.update(0.4, own, {}, true)
	check(defense.phase == "extend" and absf(defense.direction.x) < 0.001, "Low energy unloads instead of tightening turn")
	defense = Defense.new()
	own.agl = 200.0
	defense.report_damage(5, &"projectile")
	request = defense.update(0.4, own, {}, true)
	check(request.y >= own.position.y, "No descending request near terrain floor")
	check(defense.update(0.1, own, {}, false) == Vector3.ZERO and defense.phase == "idle", "Recovery/disabled state cancels intent")
	var craft := preload("res://Aircraft/Aircraft_5.tscn").instantiate() as Aircraft
	craft.position = Vector3(0, 1000, 0)
	craft.freeze = true
	add_child(craft)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	var pilot: AIPilot = craft.get_node("AIPilot")
	pilot.set_physics_process(false)
	var events := []
	craft.combat_damage_received.connect(func(amount: float, source: StringName): events.append([amount, source]))
	var hp := craft.current_health
	var wing: Node3D = craft.get_node("LeftWingDamageCollider")
	craft.take_projectile_damage_at(1, wing.global_position)
	check(events.size() == 1 and events[0][1] == &"projectile", "Regional projectile hit produces source-aware danger")
	check(craft.current_health == hp, "Component danger does not require hull damage")
	craft.take_damage_at(1, wing.global_position)
	check(events.size() == 1, "Uncategorized localized damage cannot invent incoming fire")
	var projectile := preload("res://Projectiles/ProjectileNew/projectile_new.gd").new()
	projectile._impact_world_position = wing.global_position
	projectile._apply_impact_damage(craft, 1.0)
	check(events.size() == 2, "Actual projectile impact dispatcher uses the source-aware aircraft entry")
	projectile.free()
	pilot._enemy_awareness.clear()
	pilot._safety_override_active = false
	pilot._terrain_height_callable = Callable()
	var descending_point := craft.position + Vector3(0, -100, 500)
	check(pilot._clamp_dogfight_suicide_dive(craft.position, Vector3(0, 0, 90), descending_point).y < craft.position.y - 50,
		"Unknown terrain height cannot flatten a legitimate downward pursuit")
	pilot._terrain_height_callable = func(_position: Vector3) -> float: return 1000.0
	check(pilot._clamp_dogfight_suicide_dive(craft.position, Vector3(0, 0, 90), descending_point).y >= craft.position.y - 0.1,
		"Known unsafe pullout still flattens a dive at ground level")
	pilot._terrain_height_callable = Callable()
	pilot._on_aircraft_damaged(5, hp)
	check(pilot._enemy_awareness.is_empty(), "Generic damage cannot reveal nearest enemy")
	var track = Track.new()
	track.observe(Vector3(20, 1000, -500), Vector3(0, 0, 80), 0)
	pilot._visual_contacts.clear()
	pilot._visual_contacts[123] = track
	pilot._visual_clock_s = 3.0
	pilot._dogfight_contact_visible = false
	pilot._dogfight_contact_age_s = 3.0
	pilot._dogfight_reacquire_until_s = 15.0
	pilot._dogfight_reset_cooldown_s = 0.0
	pilot._dogfight_reset_timer_s = 0.0
	var look_point := craft.position + Vector3(0, 0, -500)
	pilot._update_dogfight_tactical_reset(0.1, look_point)
	check(pilot._dogfight_reset_direction.z < 0 and pilot._dogfight_reset_timer_s <= 2.5,
		"Lost-contact reset looks toward remembered sector instead of extending away")
	pilot._visual_clock_s = 12.0
	check(not pilot._dogfight_search_area().is_empty(), "Expired track may seed a finite uncertain search area")
	pilot._visual_clock_s = 19.0
	check(pilot._dogfight_search_area().is_empty(), "Search area expires without a new observation")
	print("EVASIVE_FLIGHT_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
