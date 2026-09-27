extends Node3D

var failures: Array[String] = []
class FlatTerrain extends Node3D:
	var bad_bay := false
	func get_height(point: Vector3) -> float:
		return 20.0 if bad_bay and point.x > 30 else 0.0

func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	EnemyBaseManager.disable_for_heli_test()
	EnemyOpsManager.set_physics_process(false)
	FloatingOrigin.enabled = false
	var terrain := FlatTerrain.new()
	add_child(terrain)
	TerrainReference.terrain_node = terrain
	var pads := EnemyBaseManager._find_outpost_compound_pads(Vector3.ZERO)
	check(pads.size() == 4, "flat compound has four support pads")
	terrain.bad_bay = true
	check(EnemyBaseManager._find_outpost_compound_pads(Vector3.ZERO).is_empty(), "uneven bay footprint rejects entire site")
	terrain.bad_bay = false
	var station := EnemyBaseManager._add_outpost(Vector3.ZERO, "OP-test", 0)
	EnemyBaseManager._populate_outpost_compound(station, pads)
	station.set_physics_process(false)
	var bay = station.get_node("VehicleBay")
	check(EnemyBaseManager.emplacements.size() == 3, "compound has three working emplacements")
	check(bay.get_node("Model").scene_file_path.ends_with("enemy vehicle bay.glb"), "authored bay model used")
	check(bay.get_node("Model/door") != null and bay._shapes.size() == 2, "authored door and shell have collision")
	check(station.can_support_patrols(), "intact bay supports patrols")
	var base = load("res://Tests/EnemyOutpostSmoketest.gd").TestBase.new()
	add_child(base)
	base.position = Vector3(20000, 0, 0)
	EnemyOpsManager._evaluate_ground(base)
	var patrols := EnemyOpsManager._get_platoons(base)
	check(patrols.size() == 1 and base.vehicle_reserve == 20, "intact compound funds one patrol")
	check(bay._door_hold_s > 0, "patrol deployment opens the bay")
	bay.set_physics_process(false)
	bay._physics_process(2.0)
	await get_tree().physics_frame
	check(bay._door_fraction == 1.0 and not bay._door.visible and bay._door_shape.disabled, "open shutter clears doorway and collision")
	var door_state: Dictionary = bay.capture_save_state()
	bay._physics_process(10.0)
	bay._physics_process(2.0)
	await get_tree().physics_frame
	check(bay._door.transform.is_equal_approx(bay._door_closed) and not bay._door_shape.disabled, "door returns to authored closed pose and collision")
	bay.restore_save_state(door_state)
	check(bay._door_fraction == 1.0 and bay._door_hold_s > 0, "door cycle survives checkpoint restoration")
	var survivor: EnemyVirtualPlatoon = patrols[0]
	survivor.set_mission_attack_position(Vector3(800, 0, 0))
	bay.take_damage(125)
	var saved := EnemyBaseManager.capture_save_state()
	check(saved.outposts[0].vehicle_bay.current_health == 475, "bay damage is saved independently")
	if "--render" in OS.get_cmdline_user_args(): await render_compound(station)
	bay._explosion_scene = null
	bay.take_damage(10000)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(bay.is_destroyed and not station.is_destroyed, "bay destroyed independently")
	bay.begin_deployment()
	check(not bay.is_physics_processing(), "destroyed bay cannot restart door animation")
	check(not station.can_support_patrols() and station.can_observe(Vector3(100, 0, 0)), "bay loss stops replacements but preserves observation")
	EnemyOpsManager._evaluate_ground(base)
	check(survivor.vehicle_count == 4 and survivor.mission == EnemyVirtualPlatoon.Mission.ATTACK_POSITION, "bay loss preserves surviving patrol orders")
	survivor.vehicle_count = 0
	station.patrol_cooldown_s = 0
	EnemyOpsManager._evaluate_ground(base)
	check(EnemyOpsManager._get_platoons(base).is_empty() and base.vehicle_reserve == 20, "destroyed bay prevents replacement and reserve spend")
	check(bay._shapes.all(func(s): return s.disabled), "intact collision disabled")
	check(bay._wreck.get_node("Model").scene_file_path.ends_with("enemy vehicle bay destroyed.glb"), "authored wreck installed")
	check(not bay._wreck.find_children("*", "CollisionShape3D", true, false).is_empty(), "wreck has silhouette collision")
	if "--render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://captures/enemy_outpost_compound_bay_destroyed.png")
	saved = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(EnemyBaseManager.capture_save_state()))))
	EnemyBaseManager.disable_for_heli_test()
	await get_tree().process_frame
	EnemyBaseManager._spawn_bases_from_save(saved)
	var restored := EnemyBaseManager.outposts[0]
	check(restored.get_node("VehicleBay").is_destroyed and not restored.is_destroyed, "JSON restore retains independent destruction")
	check(EnemyBaseManager.emplacements.size() == 3, "restore keeps exactly three guns")
	print("ENEMY_OUTPOST_COMPOUND_", "PASS" if failures.is_empty() else "FAIL", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func render_compound(station: EnemyOutpost) -> void:
	for gun in EnemyBaseManager.emplacements:
		gun.inactive_when_no_targets = false
		gun._set_full_presence_active(true)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8c8165")
	ground.material_override = mat
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8ba5b6")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 35.0
	camera.position = Vector3(105, 95, 140)
	camera.look_at(Vector3(10, 2, 0))
	camera.current = true
	await get_tree().create_timer(2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/enemy_outpost_compound.png")
