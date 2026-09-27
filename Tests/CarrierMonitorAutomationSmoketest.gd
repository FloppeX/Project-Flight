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

class ShotProvider extends Node:
	var target: Node3D
	func get_recently_fired_target() -> Node3D:
		return target

class QuietTurret extends Turret:
	func fire() -> void:
		pass

class FailedWeapon extends Weapon:
	func fire() -> bool:
		return false

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
	var firing_controller = (load("res://Weapons/Turrets/turret_controller.gd") as Script).new()
	var barrel := QuietTurret.new()
	var weapon := Weapon.new()
	firing_controller.turret = barrel
	firing_controller.weapon_instance = weapon
	firing_controller.current_target = enemy
	check(firing_controller.get_recently_fired_target() == null, "aiming was reported as firing")
	firing_controller.fire_weapon()
	check(firing_controller.get_recently_fired_target() == enemy, "successful shot not reported")
	firing_controller._last_fired_at_ms -= 3000
	check(firing_controller.get_recently_fired_target() == null, "gunfire priority did not expire")
	var failed_weapon := FailedWeapon.new()
	firing_controller.weapon_instance = failed_weapon
	firing_controller.fire_weapon()
	check(firing_controller.get_recently_fired_target() == null, "failed shot was reported as firing")
	firing_controller.free()
	barrel.free()
	weapon.free()
	failed_weapon.free()
	root.get_node("WorldUnitIndex").call("register_unit", enemy)
	ops.call("coordinate_defense")
	check((ops.call("get_available_targets") as Array).has(returning), "friendly landing aircraft absent from monitor list")
	check(not (root.get_node("AirOpsManager").call("get_carrier_sensor_contacts", carrier) as Array).has(returning), "friendly recovery leaked into hostile radar API")
	rig.call("_process", 0.1)
	check(rig.get("current_target") == enemy, "enemy did not take priority over nearer friendly")
	var engaged := Contact.new()
	engaged.team = 2
	engaged.add_to_group("enemies")
	engaged.position = Vector3(0, 100, 2500)
	world.add_child(engaged)
	root.get_node("WorldUnitIndex").call("register_unit", engaged)
	var shooter := ShotProvider.new()
	carrier.add_child(shooter)
	shooter.target = engaged
	ops.call("coordinate_defense")
	var shooters: Array[Node] = [shooter]
	ops.set("_turrets", shooters)
	rig.call("_process", 0.1)
	check(rig.get("current_target") == engaged, "recently fired-on enemy did not take priority")
	shooter.target = null
	rig.call("_process", 0.1)
	check(rig.get("current_target") == engaged, "camera hopped between enemies of equal priority")
	engaged.queue_free()
	rig.call("_process", 0.1)
	check(rig.get("current_target") == enemy, "queued target was retained")
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
	check(rig.get("current_target") == enemy, "release did not resume enemy priority")
	pilot.current_state = states.SEARCH
	ops.call("coordinate_defense")
	rig.call("_process", 0.1)
	check((ops.call("get_available_targets") as Array).has(returning) and rig.get("current_target") == enemy, "patrol friendly missing or displaced enemy")
	pilot.current_state = states.RTB
	returning.set_meta("carrier_transport_mode", true)
	ops.call("coordinate_defense")
	check(not (ops.call("get_available_targets") as Array).has(returning), "stored aircraft appeared as inbound")
	returning.set_meta("carrier_transport_mode", false)
	pilot._cached_carrier_node = world
	ops.call("coordinate_defense")
	check((ops.call("get_available_targets") as Array).has(returning), "live friendly returning elsewhere was omitted")
	enemy.queue_free()
	ops.call("coordinate_defense")
	rig.call("_process", 0.0)
	check(rig.get("current_target") == returning, "friendly fallback missing without enemies")
	returning.queue_free()
	var friendly_ground := Contact.new()
	friendly_ground.add_to_group("ground_vehicles")
	world.add_child(friendly_ground)
	root.get_node("WorldUnitIndex").call("register_unit", friendly_ground)
	ops.call("coordinate_defense")
	rig.call("_process", 0.0)
	check(rig.get("current_target") == friendly_ground, "friendly ground unit not tracked")
	friendly_ground.queue_free()
	ops.call("coordinate_defense")
	rig.call("_process", 0.0)
	var yaw := float(rig.get("_scan_yaw"))
	rig.call("_process", 5.0)
	check(is_equal_approx(float(rig.get("_scan_yaw")), yaw), "idle camera rotated without targets")
	rig.call("_process", 15.0)
	check(is_equal_approx(float(rig.get("_scan_yaw")), yaw), "idle camera drifted after twenty seconds")
	carrier.rotation = Vector3(0.2, 0.3, 0.1)
	rig.call("_process", 0.0)
	rig.call("_update_feed_camera", 0.1)
	var feed_camera := rig.get_node("CarrierTargetCameraViewport/Camera3D") as Camera3D
	check(feed_camera.global_basis.y.is_equal_approx(Vector3.UP) and is_equal_approx(feed_camera.fov, 70.0), "idle search is not world-level and zoomed out")
	var forward: Vector3 = -rig.global_basis.z
	forward.y = 0.0
	check((-feed_camera.global_basis.z).is_equal_approx(forward.normalized()), "idle view does not follow carrier heading")
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
		print("[CarrierMonitorAutomationSmoketest] PASS firing_priority+enemy_priority+friendly_units+stable_target+forward_idle+manual_priority+low_light")
	quit(0 if failures.is_empty() else 1)
