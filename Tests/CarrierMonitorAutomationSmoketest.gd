extends SceneTree

class Contact:
	extends Node3D
	var team: int = 1
	func get_team() -> int:
		return team

class RecoveryPilot:
	extends Node
	var current_state: int = 0
	var _cached_carrier_node: Node3D

class LightCycle:
	extends Node
	var darkness: float = 0.0
	func get_ai_darkness_factor() -> float:
		return darkness

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var carrier := Node3D.new()
	world.add_child(carrier)
	var main_camera := Camera3D.new()
	world.add_child(main_camera)
	main_camera.make_current()
	var light_cycle := LightCycle.new()
	light_cycle.add_to_group("day_night_cycle")
	world.add_child(light_cycle)
	var ops := (load("res://LandCarrier/DefenseOps.gd") as Script).new() as Node
	ops.name = "DefenseOps"
	carrier.add_child(ops)
	var rig := (load("res://LandCarrier/CarrierTargetCamera.tscn") as PackedScene).instantiate()
	carrier.add_child(rig)
	rig.set_process(false)
	var returning := Contact.new()
	returning.add_to_group("ai_aircraft")
	returning.position = Vector3(0, 100, 500)
	var pilot := RecoveryPilot.new()
	pilot.name = "AIPilot"
	pilot._cached_carrier_node = carrier
	var states: Dictionary = (load("res://AI/AIPilot.gd") as Script).get_script_constant_map()["State"]
	pilot.current_state = states.LANDING
	returning.add_child(pilot)
	world.add_child(returning)
	root.get_node("WorldUnitIndex").call("register_unit", returning)
	var enemy := Contact.new()
	enemy.team = 2
	enemy.add_to_group("enemies")
	enemy.position = Vector3(0, 100, 1500)
	world.add_child(enemy)
	root.get_node("WorldUnitIndex").call("register_unit", enemy)
	ops.call("coordinate_defense")
	check((ops.call("get_available_targets") as Array).has(returning), "friendly landing aircraft absent from monitor list")
	check(not (root.get_node("AirOpsManager").call("get_carrier_sensor_contacts", carrier) as Array).has(returning), "friendly recovery leaked into hostile radar API")
	rig.call("_process", 0.1)
	check(rig.get("current_target") == returning, "unattended camera did not choose nearest friendly landing contact")
	rig.call("begin_control")
	rig.call("cycle_target", 1)
	check(rig.get("current_target") == returning, "friendly recovery not manually selectable")
	rig.call("cycle_target", 1)
	rig.call("_process", 0.1)
	check(rig.get("current_target") == enemy, "automatic tracking overrode player's farther target")
	rig.call("cycle_target", 1)
	rig.call("_process", 0.1)
	check(rig.get("current_target") == null, "automatic tracking overrode player free look")
	rig.call("end_control")
	check(rig.get("current_target") == returning, "release did not resume nearest automatic target")
	pilot.current_state = states.SEARCH
	ops.call("coordinate_defense")
	rig.call("_process", 0.1)
	check(not (ops.call("get_available_targets") as Array).has(returning) and rig.get("current_target") == enemy, "patrolling friendly stayed in landing list")
	pilot.current_state = states.RTB
	returning.set_meta("carrier_transport_mode", true)
	ops.call("coordinate_defense")
	check(not (ops.call("get_available_targets") as Array).has(returning), "stored aircraft appeared as inbound")
	returning.set_meta("carrier_transport_mode", false)
	pilot._cached_carrier_node = world
	ops.call("coordinate_defense")
	check(not (ops.call("get_available_targets") as Array).has(returning), "aircraft returning to another carrier appeared")
	enemy.queue_free()
	ops.call("coordinate_defense")
	rig.call("_process", 0.0)
	var yaw := float(rig.get("_scan_yaw"))
	rig.call("_process", 5.0)
	check(is_equal_approx(wrapf(float(rig.get("_scan_yaw")) - yaw, -PI, PI), -PI / 2), "search did not turn clockwise 90 degrees in five seconds off-screen")
	rig.call("_process", 15.0)
	check(is_equal_approx(wrapf(float(rig.get("_scan_yaw")) - yaw, -PI, PI), 0.0), "search did not complete one revolution in 20 seconds")
	carrier.rotation = Vector3(0.2, 0.3, 0.1)
	rig.call("_update_feed_camera", 0.1)
	var feed_camera := rig.get_node("CarrierTargetCameraViewport/Camera3D") as Camera3D
	check(feed_camera.global_basis.y.is_equal_approx(Vector3.UP) and is_equal_approx(feed_camera.fov, 70.0), "idle search is not world-level and zoomed out")
	light_cycle.darkness = 0.8
	rig.call("_process", 0.1)
	check(bool(rig.get("_low_light_enabled")) and (rig.get("_feed_low_light") as ColorRect).visible, "darkness did not enable preview enhancement")
	rig.call("begin_control")
	rig.call("begin_fullscreen_view")
	check((rig.get("_fullscreen_low_light") as ColorRect).visible, "full-resolution mast lacks low-light enhancement")
	light_cycle.darkness = 0.5
	rig.call("_process", 0.1)
	check(bool(rig.get("_low_light_enabled")), "enhancement flickers around dusk threshold")
	light_cycle.darkness = 0.2
	rig.call("_process", 0.1)
	check(not bool(rig.get("_low_light_enabled")), "enhancement did not turn off in daylight")
	rig.call("end_control")
	check(root.get_camera_3d() == main_camera and not (rig.get("_fullscreen_hud") as CanvasLayer).visible, "enhancement leaked into room view")
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("[CarrierMonitorAutomationSmoketest] PASS friendly_recovery=true nearest=true manual_priority=true clockwise_20s=true level=true low_light=true daylight_restore=true")
	quit(0 if failures.is_empty() else 1)
