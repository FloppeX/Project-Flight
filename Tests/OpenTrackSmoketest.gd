extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var receiver := root.get_node("OpenTrackReceiver")
	var menu := root.get_node("PauseMenu")
	var original_enabled: bool = menu.get("_opentrack_enabled")
	var original_smoothing: int = menu.get("_opentrack_smoothing")
	receiver.configure(false, 2)
	receiver.configure(true, 0)
	receiver.set_process(false)
	_check(receiver.get("_bind_error") == OK, "loopback bind")
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", 4242)
	var packet := PackedByteArray()
	packet.resize(48)
	var values := [10.0, 5.0, -15.0, 30.0, 20.0, 10.0]
	for index in range(6):
		packet.encode_double(index * 8, values[index])
	sender.put_packet(packet)
	await create_timer(0.05).timeout
	receiver._process(0.016)
	_check(receiver.is_receiving(), "actual UDP reception")
	_check(receiver.head_position.is_equal_approx(Vector3(-0.1, 0.05, -0.15)), "lateral axis inverted; vertical/depth preserved; centimetres converted to metres")
	var expected := Basis.from_euler(Vector3(deg_to_rad(20.0), deg_to_rad(-30.0), deg_to_rad(-10.0)))
	_check(Basis(receiver.head_orientation).is_equal_approx(expected), "rotation axis mapping")
	_check(not receiver.accept_packet(PackedByteArray([1, 2])), "short packet rejected")
	var invalid := packet.duplicate()
	invalid.encode_double(0, NAN)
	_check(not receiver.accept_packet(invalid), "NaN rejected")
	invalid.encode_double(0, INF)
	_check(not receiver.accept_packet(invalid), "infinity rejected")

	var rig := preload("res://Camera/CockpitCamera.gd").new()
	rig.rotation.y = PI
	root.add_child(rig)
	rig.set_process(false)
	rig.set_physics_process(false)
	rig.current_look = Vector3(0.1, 0.2, 0.0)
	rig._process(0.0)
	_check(rig.basis.is_equal_approx(Basis.from_euler(rig.base_rotation + rig.current_look) * expected), "tracking composes after stick look")
	_check(rig.position.distance_to(rig.base_position) > 0.1, "head translation applied")
	var pose: Transform3D = rig.transform
	rig._process(0.0)
	_check(rig.transform.is_equal_approx(pose), "no cumulative drift")
	receiver._age = 0.6
	receiver.advance_pose(1.5)
	_check(receiver.head_position.length() < 0.0001, "signal loss returns to neutral")

	# Exponential smoothing must produce the same result at different frame rates.
	receiver.smoothing_index = 2
	receiver.accept_packet(packet)
	receiver.head_position = Vector3.ZERO
	receiver.head_orientation = Quaternion.IDENTITY
	receiver.advance_pose(0.1)
	var one_step: Vector3 = receiver.head_position
	var one_rotation: Quaternion = receiver.head_orientation
	receiver.head_position = Vector3.ZERO
	receiver.head_orientation = Quaternion.IDENTITY
	for index in range(10):
		receiver.advance_pose(0.01)
	_check(receiver.head_position.is_equal_approx(one_step), "frame-rate independent translation")
	_check(receiver.head_orientation.is_equal_approx(one_rotation), "frame-rate independent orientation")
	receiver.configure(false, 2)
	rig._process(0.0)
	_check(rig.basis.is_equal_approx(Basis.from_euler(rig.base_rotation + rig.current_look)), "disabled preserves stick look")
	_check(rig.position.is_equal_approx(rig.base_position), "disabled removes head translation")
	var port_probe := PacketPeerUDP.new()
	_check(port_probe.bind(4242, "127.0.0.1") == OK, "disabled releases UDP port")
	port_probe.close()

	menu.set("_opentrack_enabled", true)
	menu.set("_opentrack_smoothing", 3)
	menu.call("_save_settings", "user://opentrack_smoke.cfg")
	menu.set("_opentrack_enabled", false)
	menu.set("_opentrack_smoothing", 0)
	menu.call("_load_settings", "user://opentrack_smoke.cfg")
	_check(menu.get("_opentrack_enabled") and menu.get("_opentrack_smoothing") == 3, "settings roundtrip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://opentrack_smoke.cfg"))
	menu.set("_opentrack_enabled", original_enabled)
	menu.set("_opentrack_smoothing", original_smoothing)
	menu.call("_apply_opentrack_settings")
	menu.call("_refresh_gameplay_button_labels")
	sender.close()
	rig.free()
	if "--render-settings" in OS.get_cmdline_user_args():
		menu.visible = true
		menu.call("_show_screen", "gameplay")
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/opentrack_settings.png")
	for failure in failures:
		push_error(failure)
	print("[OpenTrackSmoketest] %s UDP+validation+composition+smoothing+timeout+disable+persistence" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
