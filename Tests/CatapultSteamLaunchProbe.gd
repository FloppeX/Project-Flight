extends "res://Tests/CarrierLaunchContactProbe.gd"

var _camera: Camera3D
var _captured := false
var _captured_tail := false
var _saw_steam := false
var _released_frames := 0

func _ready() -> void:
	if "--no-steam" in OS.get_cmdline_user_args():
		get_tree().node_added.connect(func(node: Node):
			if node.has_method("is_available_for_launch"):
				node.set("launch_steam_enabled", false)
		)
	release_observation_ticks = 150
	process_physics_priority = 20
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("647886")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.5
	add_child(sun)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 58.0
	super._ready()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(carrier) or not is_instance_valid(catapult):
		return
	# The isolated carrier has no terrain placement task to reveal its visuals.
	carrier.visible = true
	_camera.global_position = carrier.to_global(Vector3(-32, 18, 75))
	_camera.look_at(carrier.to_global(Vector3(-8, 0, 47)))
	_camera.make_current()
	var steam := catapult.get_node_or_null("LaunchSteam") as CPUParticles3D
	if steam == null:
		return
	if steam.emitting:
		_saw_steam = true
		check(catapult._launching and catapult._latched, "steam must emit only during powered launch")
		check(not steam.local_coords, "steam must remain behind the returning shuttle")
		if not _captured and carrier.to_local(catapult.shuttle.global_position).z > 59.0:
			_captured = true
			_capture("launch")
	if is_instance_valid(aircraft) and aircraft.has_meta("carrier_launch_contact_grace_until_msec"):
		_released_frames += 1
		check(not steam.emitting, "release and return must stop new steam")
		if _released_frames == 30 and not _captured_tail:
			_captured_tail = true
			_capture("after_release")
		if _released_frames == 120:
			check(_saw_steam, "real launch must emit steam")
			print("CATAPULT_STEAM_LAUNCH_%s" % ("PASS" if failures.is_empty() else "FAIL"))

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "res://captures/catapult_steam_%s.png" % label
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "steam preview must save")
	print("CATAPULT_STEAM_CAPTURE ", path)
