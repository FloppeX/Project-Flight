extends SceneTree

# Temporary headless smoke test for ground-vehicle pathfinding.
# Loads Main_Scene, spawns several friendly/enemy vehicle waves through the
# existing spawner, lets the sim run briefly, then exits.

const MAIN_SCENE := "res://Main_Scene.tscn"
const TEST_DURATION_S := 18.0
const WAVE_INTERVAL_S := 2.0
const WAVE_COUNT := 3
const WAVE_SIZE := 5

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("[GVPathSmoke] Failed to load %s" % MAIN_SCENE)
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene

	print("[GVPathSmoke] Scene instantiated")
	await _wait_for_ready_state()

	var spawner := scene.get_node_or_null("EnemyAircraftSpawner")
	if spawner == null:
		push_error("[GVPathSmoke] EnemyAircraftSpawner not found")
		quit(1)
		return

	spawner.debug_ground_vehicle_spawns = false
	print("[GVPathSmoke] Spawning %d waves of %d friendly + %d enemy vehicles" % [WAVE_COUNT, WAVE_SIZE, WAVE_SIZE])

	for wave in range(WAVE_COUNT):
		spawner._spawn_ground_vehicles(spawner._friendly_vehicle_scene, WAVE_SIZE)
		spawner._spawn_ground_vehicles(spawner._enemy_vehicle_scene, WAVE_SIZE)
		print("[GVPathSmoke] Wave %d/%d spawned" % [wave + 1, WAVE_COUNT])
		await create_timer(WAVE_INTERVAL_S).timeout

	var elapsed := 0.0
	while elapsed < TEST_DURATION_S:
		await create_timer(1.0).timeout
		elapsed += 1.0
		print("[GVPathSmoke] t=%ss ground_vehicles=%d" % [int(elapsed), get_nodes_in_group("ground_vehicles").size()])

	print("[GVPathSmoke] Complete")
	quit()

func _wait_for_ready_state() -> void:
	var terrain_nav := root.get_node_or_null("TerrainNavGrid")
	var nav_graph := root.get_node_or_null("NavGraph")
	if terrain_nav == null or nav_graph == null:
		push_error("[GVPathSmoke] Required autoloads missing")
		quit(1)
		return
	while not terrain_nav.is_ready() or not nav_graph.is_ready():
		await create_timer(0.25).timeout
