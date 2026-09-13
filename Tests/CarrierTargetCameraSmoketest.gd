extends SceneTree

const CAMERA_SCENE := preload("res://LandCarrier/CarrierTargetCamera.tscn")
const MONITOR_SCENE := preload("res://LandCarrier/MonitorStation.tscn")
const VISUAL_FOCUS := preload("res://Effects/VisualFocus.gd")

class TargetProvider:
	extends Node
	var current_target: Node3D = null

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	world.name = "CarrierTargetCameraTestWorld"
	root.add_child(world)

	var carrier_root := Node3D.new()
	carrier_root.name = "Carrier"
	world.add_child(carrier_root)
	var main_camera := Camera3D.new()
	main_camera.position = Vector3(0.0, 1.2, 4.0)
	world.add_child(main_camera)
	main_camera.look_at(Vector3(-0.16, 1.05, -0.35), Vector3.UP)
	main_camera.current = true

	var target_camera := CAMERA_SCENE.instantiate() as Node3D
	target_camera.position = Vector3(-21.05627, 23.55, -7.620299)
	carrier_root.add_child(target_camera)

	var monitor_a := MONITOR_SCENE.instantiate() as Node3D
	monitor_a.name = "MonitorA"
	carrier_root.add_child(monitor_a)
	var monitor_b := MONITOR_SCENE.instantiate() as Node3D
	monitor_b.name = "MonitorB"
	monitor_b.position = Vector3(3.0, 0.0, 0.0)
	carrier_root.add_child(monitor_b)

	var near_target := Node3D.new()
	near_target.name = "NearTarget"
	near_target.position = Vector3(-21.0, 30.0, 400.0)
	world.add_child(near_target)
	var far_target := Node3D.new()
	far_target.name = "FarTarget"
	far_target.position = Vector3(-21.0, 60.0, 800.0)
	world.add_child(far_target)

	var provider_a := TargetProvider.new()
	provider_a.current_target = far_target
	carrier_root.add_child(provider_a)
	var provider_b := TargetProvider.new()
	provider_b.current_target = near_target
	carrier_root.add_child(provider_b)
	target_camera.call("register_target_provider", provider_a)
	target_camera.call("register_target_provider", provider_b)

	await process_frame
	await process_frame
	await create_timer(0.12).timeout

	var monitor_a_snapshot: Dictionary = monitor_a.call("get_debug_snapshot")
	var monitor_b_snapshot: Dictionary = monitor_b.call("get_debug_snapshot")
	_expect(bool(monitor_a_snapshot.get("screen_mesh_found", false)), "monitor A did not find the authored screen mesh")
	_expect(bool(monitor_b_snapshot.get("screen_mesh_found", false)), "monitor B did not find the authored screen mesh")
	_expect(bool(monitor_a_snapshot.get("has_camera_material", false)), "monitor A did not receive the camera material")
	_expect(bool(monitor_b_snapshot.get("has_camera_material", false)), "monitor B did not receive the camera material")
	_expect(bool(monitor_a_snapshot.get("interactive", false)), "monitor is not interactive")

	var screen_a := monitor_a.find_child("computer console screen", true, false) as MeshInstance3D
	var screen_b := monitor_b.find_child("computer console screen", true, false) as MeshInstance3D
	_expect(screen_a != null and screen_b != null, "authored monitor screen meshes are missing")
	if screen_a != null and screen_b != null:
		_expect(screen_a.material_override == screen_b.material_override, "monitor copies do not share one camera material")

	var camera_snapshot: Dictionary = target_camera.call("get_debug_snapshot")
	_expect(camera_snapshot.get("viewport_size", Vector2i.ZERO) == Vector2i(640, 360), "carrier feed is not 640x360")
	_expect(is_equal_approx(float(camera_snapshot.get("refresh_rate_hz", 0.0)), 15.0), "carrier feed is not throttled to 15 Hz")
	_expect(int(camera_snapshot.get("registered_screen_count", 0)) == 2, "two monitors did not share one feed")
	_expect(bool(camera_snapshot.get("has_feed_camera", false)), "carrier feed Camera3D is missing")
	_expect(bool(camera_snapshot.get("feed_active", false)), "visible monitor did not activate the shared feed")
	_expect(target_camera.get("current_target") == near_target, "unattended camera did not choose nearest contact")
	target_camera.call("begin_control")
	target_camera.call("cycle_target", 1)
	_expect(target_camera.get("current_target") == near_target, "cycle did not choose first stable contact")
	_expect(VISUAL_FOCUS.is_node_in_target_camera_focus(target_camera, near_target), "carrier feed did not keep its watched target in visual focus")
	target_camera.call("cycle_target", 1)
	_expect(target_camera.get("current_target") == far_target, "cycle did not choose second contact")
	target_camera.call("cycle_target", 1)
	_expect(target_camera.get("current_target") == null, "cycle did not return to free look")
	target_camera.call("cycle_target", -1)
	_expect(target_camera.get("current_target") == far_target, "reverse cycling did not wrap to last contact")

	provider_b.current_target = null
	await create_timer(0.12).timeout
	_expect(target_camera.get("current_target") == far_target, "camera did not hand off when its current defense target was lost")
	far_target.queue_free()
	await process_frame
	await create_timer(0.12).timeout
	_expect(target_camera.get("current_target") == null, "camera retained a freed defense target")

	var carrier_scene := load("res://LandCarrier/LandCarrier2.tscn") as PackedScene
	_expect(carrier_scene != null, "LandCarrier2 could not be loaded")
	var carrier := carrier_scene.instantiate() as Node3D if carrier_scene != null else null
	if carrier == null:
		await _finish(world)
		return
	_expect(carrier.get_node_or_null("CarrierTargetCamera") != null, "LandCarrier2 has no mast target camera")
	_expect(carrier.get_node_or_null("MonitorStationCommand") != null, "LandCarrier2 has no command-room monitor")
	_expect(carrier.get_node_or_null("MonitorStationAirOps") != null, "LandCarrier2 has no Air Ops monitor")
	var integrated_camera := carrier.get_node_or_null("CarrierTargetCamera") as Node3D
	if integrated_camera != null:
		_expect(integrated_camera.position.y > 23.18, "carrier camera is not above the mast top")
		integrated_camera.call("_refresh_target_providers")
		var integrated_snapshot: Dictionary = integrated_camera.call("get_debug_snapshot")
		_expect(int(integrated_snapshot.get("target_provider_count", 0)) == carrier.find_children("*", "TurretController", true, false).size(), "mast camera missed carrier-defense providers")
	carrier.free()

	await _finish(world)


func _finish(world: Node) -> void:
	world.queue_free()
	await process_frame
	if _failures.is_empty():
		print("[CarrierTargetCameraSmoketest] PASS shared_viewport=true frustum_gate=true free_look=true target_ring=true target_loss=true")
		quit(0)
		return
	for failure in _failures:
		push_error("[CarrierTargetCameraSmoketest] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
