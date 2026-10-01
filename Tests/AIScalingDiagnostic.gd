extends Node3D
## CPU-only isolated hot-path benchmark; no campaign save is loaded.
class ProbePilot extends HelicopterPilot:
	var ground_queries := 0
	func _ready() -> void: pass
	func _get_ground_height_at_position(point: Vector3) -> float:
		ground_queries += 1
		return super._get_ground_height_at_position(point)

func _ready() -> void: call_deferred("run")

func run() -> void:
	var root := get_tree().root
	for node in root.get_children():
		if node != self: node.process_mode = Node.PROCESS_MODE_DISABLED
	var scene := self
	var terrain = load("res://Environment/LowPolyTerrain.gd").new()
	terrain.generate_on_ready = false
	terrain.cell_size_m = 36.0
	scene.add_child(terrain)
	terrain.set_process(false)
	terrain._refresh_layout()
	terrain._noises = terrain._build_noises()
	root.get_node("TerrainReference").terrain_node = terrain
	var pilots: Array[ProbePilot] = []
	for i in 96:
		var craft := RigidBody3D.new()
		craft.gravity_scale = 0.0
		craft.position = Vector3((i % 12) * 350, 3000, (i / 12) * 350)
		scene.add_child(craft)
		craft.add_to_group("aircraft")
		craft.add_to_group("ai_aircraft")
		var pilot := ProbePilot.new()
		craft.add_child(pilot)
		pilot.set_physics_process(false)
		pilot.aircraft = craft
		pilots.append(pilot)
		terrain.get_height(craft.position)
	var start := Time.get_ticks_usec()
	for tick in 20:
		for pilot in pilots:
			pilot._apply_airborne_separation_speed_limit(50, Vector3.BACK * 50, Vector3.BACK, Vector3.RIGHT, 1.0 / 60.0)
			pilot._get_airborne_separation_velocity(Vector3.BACK * 50, Vector3.BACK, Vector3.RIGHT)
	var duration_us := Time.get_ticks_usec() - start
	var queries := 0
	for pilot in pilots: queries += pilot.ground_queries
	assert(queries == 96 * 2 * 20, "Distant traffic must not trigger terrain sampling")
	print("AI_SCALING_RESULT ", JSON.stringify({"aircraft": pilots.size(), "ticks": 20,
		"separation_ms_per_tick": duration_us / 20000.0, "terrain_queries": queries}))
	# Nearby aircraft must still trigger both braking and lateral avoidance.
	var leader := pilots[1].aircraft
	leader.position = pilots[0].aircraft.position + Vector3(0, 0, 25)
	var speed := pilots[0]._apply_airborne_separation_speed_limit(50, Vector3.BACK * 50, Vector3.BACK, Vector3.RIGHT, 0.016)
	assert(speed < 50, "Nearby traffic still causes braking")
	assert(pilots[0]._get_airborne_separation_velocity(Vector3.BACK * 50, Vector3.BACK, Vector3.RIGHT) != Vector3.ZERO)
	leader.set_meta("parking_brake", true)
	assert(pilots[0]._apply_airborne_separation_speed_limit(50, Vector3.BACK * 50, Vector3.BACK, Vector3.RIGHT, 0.016) == 50)
	print("AI_SCALING_BEHAVIOR_PASS")
	get_tree().quit()
