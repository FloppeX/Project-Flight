extends Node3D

class TestTerrain extends Node3D:
	var ridge := false
	func get_height(point: Vector3) -> float:
		return 80.0 if ridge and point.x > 400.0 and point.x < 600.0 else 0.0

class TestBase extends EnemyBase:
	func _ready() -> void:
		aircraft_reserve = 0
		vehicle_reserve = 24
		_enemy_vehicle_scenes = [load("res://GroundVehicle/vehicle_enemy_buggy.tscn")]
		EnemyOpsManager.register_base(self)
		set_physics_process(false)

var failures: Array[String] = []
const STATION := preload("res://Buildings/building_enemy_outpost.tscn")

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	EnemyBaseManager.disable_for_heli_test()
	EnemyOpsManager.set_physics_process(false)
	FloatingOrigin.enabled = false
	var terrain := TestTerrain.new()
	add_child(terrain)
	TerrainReference.terrain_node = terrain
	var station := STATION.instantiate() as EnemyOutpost
	add_child(station)
	station.set_physics_process(false)
	EnemyBaseManager.outposts.append(station)
	check(station._radar != null, "authored radar found")
	check(station.find_children("*", "CollisionShape3D", true, false).size() == 2, "both authored meshes have damage collision")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 5, 100), Vector3(0, 5, -100)))
	check(hit.get("collider") == station, "weapons ray hits damageable outpost body")
	var radar_before := station._radar.transform
	station._physics_process(1.0)
	check(not station._radar.transform.is_equal_approx(radar_before), "radar rotates at its authored pivot")
	check(station.can_observe(Vector3(1000, 0, 0)), "flat terrain permits ground observation")
	check(not station.can_observe(Vector3(4100, 0, 0)), "range limit enforced")
	terrain.ridge = true
	check(not station.can_observe(Vector3(1000, 0, 0)), "ridge conceals ground target")
	check(station.can_observe(Vector3(1000, 300, 0)), "aircraft above ridge remains visible")
	terrain.ridge = false
	var friendly := Node3D.new()
	add_child(friendly)
	friendly.add_to_group("carrier")
	friendly.position = Vector3(1000, 0, 0)
	station._scan_contacts()
	check(station._pending_reports.size() == 1, "scan queues friendly carrier report")
	station._service_reports(14.0)
	check(EnemyOpsManager._get_contact("carrier").is_empty(), "no intel before transmission delay")
	friendly.position.x = 1200.0
	station._scan_contacts()
	station._service_reports(1.0)
	var intel := EnemyOpsManager._get_contact("carrier")
	check(intel.get("position") == Vector3(1000, 0, 0), "reported position is original sighting, not a live lock")
	check(intel.get("reporter") == station.outpost_id, "report identifies station")
	station._scan_contacts()
	var shift := Vector3(300, 0, -200)
	station.apply_origin_shift(shift)
	check(station._pending_reports[0].position == friendly.position - shift, "pending reports follow floating origin")
	station.apply_origin_shift(-shift)
	friendly.free()
	station.take_damage(125.0)
	var saved: Dictionary = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(station.capture_save_state()))))
	var restored := STATION.instantiate() as EnemyOutpost
	add_child(restored)
	restored.set_physics_process(false)
	restored.restore_save_state(saved)
	check(restored.current_health == 475.0 and restored._pending_reports.size() == 1, "JSON checkpoint retains damage and pending reports")
	restored.free()
	var base := TestBase.new()
	add_child(base)
	base.position = Vector3(20000, 0, 0)
	EnemyOpsManager._evaluate_ground(base)
	var patrols := EnemyOpsManager._get_platoons(base)
	check(patrols.size() == 1 and base.vehicle_reserve == 20, "station patrol consumes four base vehicles")
	var patrol: EnemyVirtualPlatoon = patrols[0]
	check(patrol.outpost_id == station.outpost_id and patrol.home_position == station.global_position, "patrol belongs to station and uses local home")
	EnemyOpsManager._evaluate_ground(base)
	check(EnemyOpsManager._get_platoons(base).size() == 1, "no duplicate patrol")
	EnemyOpsManager._assess_threats()
	check(patrol.mission == EnemyVirtualPlatoon.Mission.ATTACK_POSITION, "station patrol responds to reported position beyond base response radius")
	var patrol_state := patrol.capture_save_state()
	var restored_patrol := EnemyVirtualPlatoon.new()
	check(restored_patrol.restore_save_state(patrol_state) and restored_patrol.outpost_id == station.outpost_id, "patrol ownership persists")
	restored_patrol.free()
	patrol.vehicle_count = 0
	EnemyOpsManager._evaluate_ground(base)
	check(EnemyOpsManager._get_platoons(base).is_empty(), "replacement waits after patrol loss")
	station.patrol_cooldown_s = 0.0
	EnemyOpsManager._evaluate_ground(base)
	check(EnemyOpsManager._get_platoons(base).size() == 1 and base.vehicle_reserve == 16, "replacement uses reserves after cooldown")
	var survivor: EnemyVirtualPlatoon = EnemyOpsManager._get_platoons(base)[0]
	survivor.set_mission_attack_position(Vector3(800, 0, 0))
	station.take_damage(10000.0)
	check(station.is_destroyed and station._pending_reports.is_empty(), "destruction cancels unsent reports")
	check(not station.can_observe(Vector3(1000, 0, 0)) and not station.is_in_group("enemies"), "destroyed station loses observation and targeting")
	check(not EnemyOpsManager._get_contact("carrier").is_empty(), "previously delivered intel survives destruction")
	EnemyOpsManager._evaluate_ground(base)
	check(survivor.vehicle_count == 4 and survivor.mission == EnemyVirtualPlatoon.Mission.ATTACK_POSITION, "surviving patrol keeps force and committed order")
	survivor.vehicle_count = 0
	station.patrol_cooldown_s = 0.0
	EnemyOpsManager._evaluate_ground(base)
	check(EnemyOpsManager._get_platoons(base).is_empty() and base.vehicle_reserve == 16, "destroyed station never replaces patrol")
	saved = SaveGameManager._decode_json_value(JSON.parse_string(JSON.stringify(SaveGameManager._encode_json_value(station.capture_save_state()))))
	restored = STATION.instantiate() as EnemyOutpost
	add_child(restored)
	restored.set_physics_process(false)
	restored.restore_save_state(saved)
	check(restored.is_destroyed and not restored._radar.visible and not restored.can_observe(Vector3.ZERO), "destroyed station remains offline after JSON restore")
	restored.free()
	EnemyOpsManager._decay_intel(181.0)
	check(EnemyOpsManager._get_contact("carrier").is_empty(), "old contact expires without new reports")
	var manager_state := EnemyBaseManager.capture_save_state()
	check(manager_state.outposts.size() == 1 and manager_state.outposts[0].is_destroyed, "manager checkpoint includes destroyed station")
	EnemyBaseManager.outposts.clear()
	EnemyBaseManager._spawn_bases_from_save({"bases": [], "outposts": manager_state.outposts})
	check(EnemyBaseManager.outposts.size() == 1 and EnemyBaseManager.outposts[0].is_destroyed, "manager restores offline station")
	EnemyBaseManager.outposts[0].free()
	EnemyBaseManager.outposts.clear()
	if "--render" in OS.get_cmdline_user_args():
		await _render(station)
		await _render_map()
	print("ENEMY_OUTPOST_SMOKETEST_", "OK" if failures.is_empty() else "FAILED", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _render(wreck: EnemyOutpost) -> void:
	var intact := STATION.instantiate() as EnemyOutpost
	intact.position = Vector3(-15, 0, 0)
	add_child(intact)
	intact.set_physics_process(false)
	wreck.position = Vector3(15, 0, 0)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("96866d")
	floor_mesh.material_override = material
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("91a8b1")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	add_child(environment)
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 45.0
	camera.position = Vector3(30, 28, 58)
	camera.look_at(Vector3(0, 6, 0))
	camera.current = true
	await get_tree().create_timer(4.0).timeout
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://captures/enemy_outpost_intact_destroyed.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("OUTPOST_RENDER ", path)

func _render_map() -> void:
	TerrainNavGrid.set_process(false)
	MapFogOfWar.set_process(false)
	TerrainNavGrid.cell_size_m = 100.0
	TerrainNavGrid._cols = 501
	TerrainNavGrid._rows = 501
	TerrainNavGrid._origin_x = -25000.0
	TerrainNavGrid._origin_z = -25000.0
	TerrainNavGrid._heights.resize(501 * 501)
	TerrainNavGrid._heights.fill(0.0)
	TerrainNavGrid._is_baked = true
	MapFogOfWar._initialize_from_navgrid()
	for station: EnemyOutpost in get_tree().get_nodes_in_group("enemy_outposts"):
		station.position = Vector3(9000, 0, 5000) if station.is_destroyed else Vector3(-8000, 0, -5000)
		station.outpost_id = "OP-02" if station.is_destroyed else "OP-01"
		MapFogOfWar.reveal_circle(station.global_position, 1500.0)
	var layer := CanvasLayer.new()
	add_child(layer)
	var background := ColorRect.new()
	background.color = Color("111b20")
	background.size = Vector2(1920, 1080)
	layer.add_child(background)
	var symbols := load("res://UI/WorldMapSymbolLayer.gd").new() as Control
	symbols.position = Vector2(100, 90)
	symbols.size = Vector2(1720, 900)
	symbols.set("show_contact_counters", false)
	background.add_child(symbols)
	check(not symbols._is_world_explored(Vector3.ZERO), "map keeps undiscovered locations hidden")
	var title := Label.new()
	title.text = "OUTPOST OBSERVATION   /   dashed rings show estimated maximum range"
	title.position = Vector2(100, 30)
	title.add_theme_font_size_override("font_size", 22)
	background.add_child(title)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/enemy_outpost_map.png")
	print("OUTPOST_MAP_RENDER res://captures/enemy_outpost_map.png")
