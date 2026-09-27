extends SceneTree

class TestTerrain:
	extends Node3D

	var surface_y := 2.5

	func get_height(world_pos: Vector3) -> float:
		return surface_y + world_pos.x * 0.25


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var terrain := TestTerrain.new()
	terrain.add_to_group("terrain_provider")
	scene.add_child(terrain)
	var pilot := load("res://Models/Characters/DownedPilot.tscn").instantiate() as RigidBody3D
	pilot.position = Vector3(0.0, 4.0, 0.0)
	scene.add_child(pilot)
	pilot.set_physics_process(false)
	await process_frame
	for frame in 30:
		await physics_frame
	pilot.call("_snap_to_terrain")
	if not _feet_at_surface(pilot, 2.5):
		return
	pilot.global_position = Vector3(2.0, 4.0, 0.0)
	pilot.call("_snap_to_terrain")
	if not _feet_at_surface(pilot, 3.0):
		return
	var sequence := Node.new()
	sequence.set_script(load("res://Aircraft/EjectionSequence.gd"))
	scene.add_child(sequence)
	var sampled: float = sequence.call("_sample_landing_height", Vector3(2.0, 100.0, 0.0))
	if absf(sampled - 3.0) > 0.001:
		_fail("ejection landing fallback ignored the terrain surface")
		return
	print("[DownedPilotGroundProbe] PASS")
	quit(0)


func _feet_at_surface(pilot: RigidBody3D, surface_y: float) -> bool:
	var collider := pilot.get_node("CollisionShape3D") as CollisionShape3D
	var box := collider.shape as BoxShape3D
	var collider_bottom := collider.global_position.y - box.size.y * 0.5
	if absf(collider_bottom - surface_y) > 0.01:
		_fail("collider bottom %.3f differs from surface %.3f" % [collider_bottom, surface_y])
		return false
	var skeleton := pilot.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		_fail("pilot skeleton is missing")
		return false
	for bone_index in skeleton.get_bone_count():
		if "toe" not in skeleton.get_bone_name(bone_index).to_lower():
			continue
		var toe_y := (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin).y
		if absf(toe_y - surface_y) > 0.12:
			_fail("pilot toe %.3f differs from surface %.3f" % [toe_y, surface_y])
			return false
	return true


func _fail(message: String) -> void:
	push_error("[DownedPilotGroundProbe] " + message)
	quit(1)
