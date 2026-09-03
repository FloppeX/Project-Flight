extends Node3D

const CARRIER_SCENE: PackedScene = preload("res://LandCarrier/LandCarrier2.tscn")
const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_1.tscn")

var _failures: PackedStringArray = []
var _tracked_aircraft: RigidBody3D = null
var _tracked_destroyed: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var carrier := CARRIER_SCENE.instantiate() as Node3D
	_expect(carrier != null, "LandCarrier2 did not instantiate")
	if carrier == null:
		_finish()
		return
	add_child(carrier)
	await get_tree().process_frame
	await get_tree().process_frame

	var manager := carrier.get_node_or_null("FlightDeckManager") as FlightDeckManager
	_expect(manager != null, "FlightDeckManager missing")
	if manager == null:
		carrier.queue_free()
		_finish()
		return

	manager.call(
		"_queue_aircraft_scene_for_retrieval",
		"Aircraft_1",
		AIRCRAFT_SCENE,
		"res://Aircraft/Aircraft_1.tscn"
	)

	var saw_launch_state := false
	var release_grace_seen := false
	var deadline_msec := Time.get_ticks_msec() + 75000
	while Time.get_ticks_msec() < deadline_msec:
		if _tracked_aircraft == null or not is_instance_valid(_tracked_aircraft):
			_tracked_aircraft = _find_live_aircraft_1()
			if _tracked_aircraft != null:
				_tracked_aircraft.destroyed.connect(_on_tracked_destroyed)
		if manager.current_state == FlightDeckManager.DeckState.LAUNCH_IN_PROGRESS:
			saw_launch_state = true
		if is_instance_valid(_tracked_aircraft):
			release_grace_seen = release_grace_seen or _tracked_aircraft.has_meta(
				"carrier_launch_contact_grace_until_msec"
			)
			if release_grace_seen \
					and not bool(_tracked_aircraft.call("_is_carrier_launch_contact_grace_active")) \
					and _tracked_aircraft.global_position.distance_to(carrier.global_position) > 30.0:
				break
		if _tracked_destroyed:
			break
		await get_tree().physics_frame

	_expect(_tracked_aircraft != null and is_instance_valid(_tracked_aircraft), "Aircraft 1 never materialized")
	_expect(saw_launch_state, "Aircraft 1 never entered the catapult launch state")
	_expect(release_grace_seen, "catapult release never established carrier-contact grace")
	_expect(not _tracked_destroyed, "Aircraft 1 was destroyed during its carrier launch")
	if is_instance_valid(_tracked_aircraft):
		_expect(not bool(_tracked_aircraft.get("_has_exploded")), "Aircraft 1 exploded during its carrier launch")
		_expect(
			_tracked_aircraft.global_position.distance_to(carrier.global_position) > 30.0,
			"Aircraft 1 did not clear the carrier after launch"
		)

	if is_instance_valid(_tracked_aircraft):
		var visual_budget := get_node_or_null("/root/EnemyVisualBudget")
		if visual_budget != null:
			visual_budget.call("release_aircraft_cache", _tracked_aircraft, false)
		_tracked_aircraft.queue_free()
	carrier.queue_free()
	for _cleanup_frame in range(4):
		await get_tree().process_frame
	_finish()


func _find_live_aircraft_1() -> RigidBody3D:
	for node in get_tree().get_nodes_in_group("aircraft"):
		if node is RigidBody3D and str(node.name).begins_with("Aircraft_1"):
			return node as RigidBody3D
	return null


func _on_tracked_destroyed() -> void:
	_tracked_destroyed = true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AIRCRAFT_1_CARRIER_LAUNCH_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[Aircraft1CarrierLaunchSmoketest] %s" % failure)
	get_tree().quit(1)
