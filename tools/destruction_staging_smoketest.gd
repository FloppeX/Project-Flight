extends SceneTree

## Focused regression test for staged explosion presentation and vehicle wrecks.

const EXPLOSION_SCENE_PATH := "res://Projectiles/Explosion/explosion.tscn"
const AIRCRAFT_DEBRIS_BURST_SCRIPT: Script = preload("res://Aircraft/AircraftDebrisBurst.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	world.name = "DestructionStagingSmokeWorld"
	root.add_child(world)
	current_scene = world
	await process_frame

	VehicleWreck.spawn(world, Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3.ZERO, true, 0.10)
	_check(_count_rigid_bodies(world) == 0, "staged wreck creates no rigid bodies in the destruction frame")
	await process_frame
	var first_frame_count := _count_rigid_bodies(world)
	_check(first_frame_count > 0 and first_frame_count < 10, "staged wreck begins with only part of the debris burst")
	for _frame in range(20):
		await process_frame
	_check(_count_rigid_bodies(world) == 10, "staged wreck eventually creates all 10 wreck pieces")

	var rollback_world := Node3D.new()
	world.add_child(rollback_world)
	VehicleWreck.spawn(rollback_world, Transform3D(Basis.IDENTITY, Vector3(20.0, 0.0, 0.0)), Vector3.ZERO, false, 0.0)
	_check(_count_rigid_bodies(rollback_world) == 10, "wreck staging rollback restores immediate construction")

	var aircraft_debris_world := Node3D.new()
	world.add_child(aircraft_debris_world)
	AIRCRAFT_DEBRIS_BURST_SCRIPT.call("spawn",
		aircraft_debris_world,
		Transform3D(Basis.IDENTITY, Vector3(60.0, 8.0, 0.0)),
		Vector3(20.0, 0.0, 0.0),
		8,
		0.55,
		2.0,
		20.0,
		70.0,
		true,
		0.10
	)
	_check(_count_rigid_bodies(aircraft_debris_world) == 0, "staged aircraft breakup creates no chunks in the destruction frame")
	await process_frame
	var first_aircraft_frame_count := _count_rigid_bodies(aircraft_debris_world)
	_check(first_aircraft_frame_count > 0 and first_aircraft_frame_count < 8, "staged aircraft breakup begins with a partial chunk burst")
	for _frame in range(20):
		await process_frame
	_check(_count_rigid_bodies(aircraft_debris_world) == 8, "staged aircraft breakup eventually creates every chunk")

	var explosion_scene := load(EXPLOSION_SCENE_PATH) as PackedScene
	_check(explosion_scene != null, "explosion scene loads after autoload initialization")
	if explosion_scene == null:
		await _finish(world)
		return
	var explosion := explosion_scene.instantiate()
	explosion.visual_spread_duration_s = 0.40
	explosion.play_explosion_audio = false
	world.add_child(explosion)
	explosion.global_position = Vector3(40.0, 2.0, 0.0)
	await process_frame
	await process_frame
	var event_count: int = (explosion.get("_visual_events") as Array).size()
	var initial_event_index := int(explosion.get("_visual_event_index"))
	_check(event_count >= 8, "explosion prepares a multi-part visual burst")
	_check(initial_event_index > 0 and initial_event_index < event_count, "explosion emits the first flash without allocating the entire burst")
	for _frame in range(4):
		await process_frame
	var intermediate_event_index := int(explosion.get("_visual_event_index"))
	_check(intermediate_event_index > initial_event_index and intermediate_event_index < event_count, "explosion advances secondary visuals over later frames")
	for _frame in range(20):
		await process_frame
	_check(int(explosion.get("_visual_event_index")) == event_count, "explosion eventually emits every queued visual")

	await _finish(world)


func _finish(world: Node) -> void:
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("[DestructionStaging] PASS")
		quit(0)
	else:
		push_error("[DestructionStaging] FAIL (%d checks)" % _failures)
		quit(1)


func _count_rigid_bodies(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is RigidBody3D:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[DestructionStaging] ok: %s" % message)
		return
	_failures += 1
	push_error("[DestructionStaging] failed: %s" % message)
