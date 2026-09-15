extends Node
## Real aircraft seat/pilot handoff, ascent-gated deployment, and canopy descent.
var sequence: EjectionSequence
var camera: Camera3D
var elapsed := 0.0
var seat_saved := false
var freefall_saved := false
var canopy_saved := false
var next_sample := 0.5

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for child in get_tree().root.get_children():
		if child != self: child.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("779aad")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	world.add_child(sun)
	var craft := load("res://Aircraft/Aircraft_1.tscn").instantiate() as RigidBody3D
	craft.position = Vector3(0, 300, 0)
	craft.freeze = true
	craft.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(craft)
	await get_tree().process_frame
	await get_tree().process_frame
	sequence = craft.find_child("EjectionSequence", true, false) as EjectionSequence
	if sequence == null:
		push_error("EJECTION_PROBE missing sequence")
		get_tree().quit(1)
		return
	camera = Camera3D.new()
	world.add_child(camera)
	camera.fov = 50.0
	camera.current = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	sequence.start_ejection()
	get_tree().physics_frame.connect(tick)
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit(2))

func tick() -> void:
	elapsed += 1.0 / Engine.physics_ticks_per_second
	var body := sequence._pilot_body
	if not is_instance_valid(body): return
	var pilot := sequence._get_ejected_pilot()
	var focus := pilot.global_position + Vector3.UP if pilot != null else body.global_position
	if sequence._parachute_deployed:
		camera.global_position = focus + Vector3(12, 5, 15)
		camera.look_at(focus + Vector3.UP * 2.5)
	else:
		camera.global_position = focus + Vector3(3, 1.5, 4)
		camera.look_at(focus)
	camera.current = true
	if elapsed >= next_sample:
		next_sample += 0.5
		print("EJECTION_SAMPLE t=%.2f separated=%s chute=%s vy=%.2f angular=%s com=%s" % [elapsed, sequence._seat_separated, sequence._parachute_deployed, body.linear_velocity.y, body.angular_velocity, body.center_of_mass])
	if not seat_saved and elapsed > 1.2:
		seat_saved = true
		capture.call_deferred("seat")
	if sequence._seat_separated and not sequence._parachute_deployed and not freefall_saved:
		freefall_saved = true
		capture.call_deferred("freefall")
	if sequence._parachute_deployed and not canopy_saved and sequence._parachute_inflation_elapsed_s > 2.0:
		canopy_saved = true
		capture.call_deferred("canopy")
	if elapsed > 15.0:
		get_tree().physics_frame.disconnect(tick)
		print("EJECTION_PROBE_COMPLETE captures=%s/%s/%s vy=%.2f" % [seat_saved, freefall_saved, canopy_saved, body.linear_velocity.y])
		get_tree().quit(0 if seat_saved and freefall_saved and canopy_saved and body.linear_velocity.y < 0 else 1)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/ejection/%s.png" % label)
