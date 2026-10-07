extends Node

# Real physics contacts with minimal aircraft fixtures; inherited force sampling
# is exercised without unrelated flight control or damage changing each case.
class TestAircraft extends Aircraft:
	func _ready() -> void:
		_setup_belly_scrape_audio()
	func _physics_process(_delta: float) -> void:
		pass
	func _process(_delta: float) -> void:
		pass

class TestSurface extends StaticBody3D:
	var deck_velocity := Vector3.ZERO
	func get_deck_reference_velocity_vector() -> Vector3:
		return deck_velocity

var failures: Array[String] = []
var craft: RigidBody3D
var camera: Camera3D
var capture: AudioEffectCapture
var surface: TestSurface

func _ready() -> void:
	call_deferred("run")

func _physics_process(_delta: float) -> void:
	if is_instance_valid(craft):
		camera.global_position = craft.global_position + Vector3(0, 3, 0)

func run() -> void:
	get_tree().create_timer(45.0).timeout.connect(func():
		push_error("BELLY_SCRAPE_TIMEOUT")
		get_tree().quit(1))
	for singleton in ["AirOpsManager", "GroundOpsManager", "OperationsCoordinator", "FlightDirector"]:
		var node := get_node_or_null("/root/" + singleton)
		if node != null: node.process_mode = Node.PROCESS_MODE_DISABLED
	AudioServer.set_bus_mute(0, true)
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, "ScrapeProbe")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus_index, capture)
	get_viewport().audio_listener_enable_3d = true
	camera = Camera3D.new()
	add_child(camera)
	camera.make_current()
	surface = TestSurface.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(1000, 1, 1000)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.5
	surface.add_child(ground_shape)
	surface.physics_material_override = PhysicsMaterial.new()
	surface.physics_material_override.friction = 0.0
	add_child(surface)

	await contact_case("terrain", false, 25, 0, true)
	await contact_case("runway_surface", false, 25, 0, true)
	await contact_case("carrier", false, 45, 30, true)
	await contact_case("carrier", false, 30, 30, false)
	await contact_case("terrain", true, 25, 0, false)
	await contact_case("carrier", true, 45, 30, false)
	await contact_case("terrain", false, 0, 0, false)
	await contact_case("carrier", false, 45, 30, false, true)
	await playback_lifecycle()
	await authored_aircraft()
	for failure in failures: push_error(failure)
	print("BELLY_SCRAPE_%s real_contacts=terrain+runway+moving_deck wheels=quiet deck_relative=true mixer=true lifecycle=true authored_aircraft=5" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func spawn_fixture(wheels: bool, speed: float) -> AudioStreamPlayer3D:
	craft = TestAircraft.new()
	craft.position = Vector3(0, 0.55, 0)
	craft.max_contacts_reported = 16
	craft.contact_monitor = true
	craft.can_sleep = false
	craft.linear_damp = 0.0
	craft.axis_lock_angular_x = true
	craft.axis_lock_angular_y = true
	craft.axis_lock_angular_z = true
	craft.physics_material_override = PhysicsMaterial.new()
	craft.physics_material_override.friction = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 1, 4)
	shape.shape = box
	craft.add_child(shape)
	if wheels: craft.register_safe_collider(shape)
	add_child(craft)
	craft.linear_velocity = Vector3(speed, 0, 0)
	var player := craft.get_node("BellyScrapeAudio") as AudioStreamPlayer3D
	player.bus = "ScrapeProbe"
	return player

func set_surface(group: String, velocity: float) -> void:
	for old_group in ["terrain", "carrier", "runway_surface"]:
		surface.remove_from_group(old_group)
	surface.add_to_group(group)
	surface.deck_velocity = Vector3(velocity, 0, 0)

func contact_case(group: String, wheels: bool, speed: float, deck_speed: float, audible: bool, managed: bool = false) -> void:
	set_surface(group, deck_speed)
	var player := spawn_fixture(wheels, speed)
	craft.set_meta("carrier_transport_mode", managed)
	await get_tree().create_timer(0.4).timeout
	var level := await rms()
	check((level > 0.00001) if audible else (level < 0.000001), "%s wheels=%s speed=%.1f deck=%.1f managed=%s wrong mixer level %.8f" % [group, wheels, speed, deck_speed, managed, level])
	check(player.playing == audible, "contact playback state disagrees")
	if deck_speed > 0:
		check(craft.linear_velocity.x > 20.0, "moving-deck case was not moving in world space")
	print("SCRAPE_CONTACT ", group, " wheels=", wheels, " speed=", speed, " deck=", deck_speed, " managed=", managed, " rms=", level)
	craft.free()
	await get_tree().process_frame

func playback_lifecycle() -> void:
	set_surface("terrain", 0)
	var player := spawn_fixture(false, 3)
	await get_tree().create_timer(0.4).timeout
	var slow := await rms()
	craft.linear_velocity = Vector3(35, 0, 0)
	await get_tree().create_timer(0.3).timeout
	var fast := await rms()
	check(fast > slow * 1.5 and slow > 0.00001, "slide speed should affect audible level")
	check(player.stream is AudioStreamWAV and player.stream.loop_end > 0, "WAV loop has no valid endpoint")
	player.seek(player.stream.get_length() - 0.08)
	check(await rms() > 0.00001 and player.playing, "scrape stopped at loop boundary")
	player.set_aircraft_audio_budget_enabled(false)
	check(await rms() < 0.000001, "audio budget suppression leaked sound")
	player.set_aircraft_audio_budget_enabled(true)
	check(await rms() > 0.00001, "audio budget did not restore contact sound")
	craft.freeze = true
	check(await rms() < 0.000001, "frozen aircraft still scrapes")
	craft.freeze = false
	craft.position.y = 15
	craft.linear_velocity = Vector3(35, 0, 0)
	check(await rms() < 0.000001, "airborne craft still scrapes")
	craft.position = Vector3(0, 0.55, 0)
	craft.linear_velocity = Vector3(25, 0, 0)
	await get_tree().create_timer(0.4).timeout
	check(await rms() > 0.00001, "fresh contact did not restart scraping")
	craft._has_exploded = true
	check(await rms() < 0.000001, "exploded aircraft still scrapes")
	craft.free()
	await get_tree().process_frame

func authored_aircraft() -> void:
	craft = load("res://Aircraft/Aircraft_5.tscn").instantiate()
	craft.freeze = true
	craft.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(craft)
	await get_tree().process_frame
	await get_tree().process_frame
	var player := craft.get_node_or_null("BellyScrapeAudio") as AudioStreamPlayer3D
	check(player != null and player.is_in_group("3d_audio"), "authored aircraft did not create routed scraper")
	if player != null:
		var manager := craft.get_node("AudioManager3D")
		manager.switch_aircraft_audio_sources(craft, "Interior")
		check(player.bus == "Interior", "scraper missed cockpit routing")
	craft.free()
	await get_tree().process_frame

func rms() -> float:
	await get_tree().create_timer(0.10).timeout
	capture.clear_buffer()
	await get_tree().create_timer(0.12).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	check(not samples.is_empty(), "mixer capture returned no frames")
	var total := 0.0
	for sample in samples: total += sample.length_squared()
	return sqrt(total / maxf(samples.size() * 2.0, 1.0))

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
