extends Node
## Real aircraft physics, isolated from combat. Run Tests/FormationFlightProbe.tscn, optionally with
## -- --maneuvers --capture for a turn/rejoin run and a rendered image.
class FlatTerrain extends Node3D:
	func get_height(_position: Vector3) -> float: return 0.0

var flight: Flight
var aircraft: Array[RigidBody3D] = []
var camera: Camera3D
var elapsed := 0.0
var next_sample := 5.0
var errors: Array[float] = []
var minimum_separation := INF
var maneuvers := false
var captured := false

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	maneuvers = "--maneuvers" in OS.get_cmdline_user_args()
	get_tree().create_timer(180.0).timeout.connect(func(): get_tree().quit(2))
	await get_tree().process_frame
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	var ground := FlatTerrain.new()
	world.add_child(ground)
	ground.add_to_group("terrain_provider")
	get_tree().root.get_node("TerrainReference").terrain_node = ground
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("7196b0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(sun)
	flight = Flight.new()
	world.add_child(flight)
	flight.set_physics_process(false)
	var packed := load("res://Aircraft/Aircraft_3.tscn") as PackedScene
	for i in range(4):
		var craft := packed.instantiate() as RigidBody3D
		craft.name = "FormationProbe%d" % i
		craft.position = Vector3(0, 1200, 0) + Flight.FORMATION_OFFSETS[i]
		craft.linear_velocity = Vector3(0, 0, 90)
		get_tree().root.get_node("EnemyVisualBudget").prepare_ai_aircraft_for_tree_entry(craft)
		world.add_child(craft)
		aircraft.append(craft)
	await get_tree().create_timer(1.0).timeout
	for i in range(4):
		var craft := aircraft[i]
		craft.global_position = Vector3(0, 1200, 0) + Flight.FORMATION_OFFSETS[i]
		if maneuvers and i == 3:
			craft.global_position += Vector3(25, 0, -60)
		craft.global_rotation = Vector3.ZERO
		craft.linear_velocity = Vector3(0, 0, 90)
		craft.angular_velocity = Vector3.ZERO
		craft.find_child("AIToggle", true, false).enable_ai()
		var pilot := craft.find_child("AIPilot", true, false) as AIPilot
		if "--diagnostic" in OS.get_cmdline_user_args() and i == 3:
			pilot.debug_enabled = true
			pilot.verbose_debug_enabled = true
		pilot.clear_air_task()
		pilot.target_altitude = 1200.0
		pilot.patrol_altitude_m = 1200.0
		pilot.nav_waypoint = Vector3(0, 1200, 30000)
		pilot.dogfight_enabled = false
		pilot.ground_attack_enabled = false
		if maneuvers:
			pilot.set_waypoints([Vector3(0, 1200, 2500), Vector3(10000, 1200, 2500)])
		else:
			pilot.set_waypoints([Vector3(0, 1200, 30000), Vector3(20000, 1200, 30000)])
		pilot.change_state(AIPilot.State.SEARCH)
		var gear := craft.find_child("ControlLandingGear", true, false)
		if gear:
			gear.send_to_landing_gears("stow")
		flight.register(craft)
	var route: Array[Vector3] = [Vector3(0, 1200, 30000), Vector3(20000, 1200, 30000)]
	if maneuvers:
		route = [Vector3(0, 1200, 2500), Vector3(2000, 1200, 6000), Vector3(10000, 1200, 6000)]
	flight.set_cap_route(null, route, 1200.0)
	flight.set_physics_process(true)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.far = 10000.0
	camera.fov = 45.0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	camera.current = true
	get_tree().physics_frame.connect(tick)
	

func tick() -> void:
	elapsed += 1.0 / Engine.physics_ticks_per_second
	var lead := aircraft[0]
	var heading := flight._formation_heading_basis(lead)
	camera.global_position = lead.global_position + heading * Vector3(110, 100, -180)
	camera.look_at(lead.global_position - heading.z * 35.0)
	camera.current = true
	for i in range(4):
		for j in range(i + 1, 4):
			minimum_separation = minf(minimum_separation, aircraft[i].global_position.distance_to(aircraft[j].global_position))
	if "--capture" in OS.get_cmdline_user_args() and not captured and elapsed >= 20.0:
		captured = true
		capture_image.call_deferred()
	if elapsed >= next_sample:
		next_sample += 5.0
		var row: Array = []
		for i in range(1, 4):
			var slot := flight._formation_position(lead, flight._formation_heading_basis(lead), i)
			var error := aircraft[i].global_position.distance_to(slot)
			var pilot := aircraft[i].find_child("AIPilot", true, false) as AIPilot
			row.append([snappedf(error, 0.1), aircraft[i].global_position - slot, snappedf(aircraft[i].linear_velocity.length(), 0.1), pilot.current_state, pilot.formation_anchor_active, pilot._get_effective_target_speed(), pilot.throttle_input, pilot._recovery_control_owner, aircraft[i].rotation_degrees, pilot.pitch_input])
			if elapsed >= (75.0 if maneuvers else 30.0): errors.append(error)
		print("FORMATION_SAMPLE t=%.0f errors=%s speed=%.1f lead_pos=%s" % [elapsed, row, lead.linear_velocity.length(), lead.global_position])
	if elapsed >= (90.0 if maneuvers else 60.0):
		get_tree().physics_frame.disconnect(tick)
		var worst := 0.0
		for error in errors: worst = maxf(worst, error)
		print("FORMATION_RESULT worst_settled_error=%.1f minimum_separation=%.1f" % [worst, minimum_separation])
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png("user://formation_probe.png")
		for craft in aircraft:
			craft.queue_free()
		aircraft.clear()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(0 if worst < (35.0 if maneuvers else 15.0) and minimum_separation > 20.0 else 1)

func capture_image() -> void:
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png("user://formation_probe_early.png")
