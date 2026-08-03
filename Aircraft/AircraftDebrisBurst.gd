extends RefCounted
class_name AircraftDebrisBurst

## Snapshot-based aircraft breakup. The aircraft can be freed immediately while
## this presentation helper creates its procedural chunks over later frames.

const STAGED_SPAWNER_PATH := "res://Aircraft/AircraftDebrisStagedSpawner.gd"
const DEBRIS_CHUNK_SCRIPT_PATH := "res://Aircraft/AircraftDebrisChunk.gd"
const FIRE_TRAIL_SCRIPT_PATH := "res://Effects/FireTrail.gd"


static func spawn(
	parent: Node,
	source_transform: Transform3D,
	inherited_velocity: Vector3,
	chunk_count: int,
	min_size: float,
	max_size: float,
	min_impulse: float,
	max_impulse: float,
	staged: bool = true,
	spread_duration_s: float = 0.28
) -> void:
	if not is_instance_valid(parent) or chunk_count <= 0:
		return
	var config := {
		"chunk_count": chunk_count,
		"min_size": min_size,
		"max_size": max_size,
		"min_impulse": min_impulse,
		"max_impulse": max_impulse,
	}
	if staged and spread_duration_s > 0.0:
		var spawner_script := load(STAGED_SPAWNER_PATH) as Script
		if spawner_script != null:
			var spawner := Node.new()
			spawner.name = "AircraftDebrisStagedSpawner"
			spawner.set_script(spawner_script)
			spawner.call("configure", parent, source_transform, inherited_velocity, config, spread_duration_s)
			parent.add_child(spawner)
			return
	for index in range(chunk_count):
		spawn_chunk(parent, source_transform, inherited_velocity, config, index)


static func spawn_chunk(
	parent: Node,
	source_transform: Transform3D,
	inherited_velocity: Vector3,
	config: Dictionary,
	index: int
) -> void:
	if not is_instance_valid(parent):
		return
	var chunk_script := load(DEBRIS_CHUNK_SCRIPT_PATH) as Script
	if chunk_script == null:
		return
	var min_size := maxf(float(config.get("min_size", 0.55)), 0.05)
	var max_size := maxf(float(config.get("max_size", 2.0)), min_size)
	var min_impulse := maxf(float(config.get("min_impulse", 20.0)), 0.0)
	var max_impulse := maxf(float(config.get("max_impulse", 70.0)), min_impulse)
	var chunk := RigidBody3D.new()
	chunk.name = "AircraftDebrisChunk_%d" % index
	chunk.set_script(chunk_script)
	# FireTrail supplies the pooled fire/smoke presentation for these chunks;
	# disable AircraftDebrisChunk's second overlapping smoke emitter.
	chunk.set("smoke_enabled", false)
	chunk.mass = randf_range(18.0, 60.0)
	chunk.contact_monitor = true
	chunk.max_contacts_reported = 4
	parent.add_child(chunk)

	var size := Vector3(
		randf_range(min_size * 0.7, max_size * 1.15),
		randf_range(min_size * 0.45, max_size * 0.8),
		randf_range(min_size * 0.9, max_size * 1.35)
	)
	var local_offset := Vector3(
		randf_range(-2.6, 2.6),
		randf_range(-0.9, 1.4),
		randf_range(-3.0, 3.0)
	)
	chunk.global_position = source_transform.origin + source_transform.basis * local_offset
	chunk.global_rotation = Vector3(
		randf_range(-PI, PI),
		randf_range(-PI, PI),
		randf_range(-PI, PI)
	)

	var assets := VehicleWreck.create_angular_chunk_assets(size)
	var mesh := MeshInstance3D.new()
	mesh.mesh = assets["mesh"] as ArrayMesh
	var material := StandardMaterial3D.new()
	var shade := randf_range(0.10, 0.24)
	var warmth := randf_range(0.0, 0.05)
	material.albedo_color = Color(shade + warmth, shade, shade * randf_range(0.9, 1.15))
	material.roughness = 0.96
	mesh.material_override = material
	chunk.add_child(mesh)

	var collider := CollisionShape3D.new()
	collider.shape = assets["shape"] as Shape3D
	chunk.add_child(collider)

	var outward := (chunk.global_position - source_transform.origin).normalized()
	if outward == Vector3.ZERO:
		outward = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(0.2, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
	outward.y = maxf(outward.y + randf_range(0.15, 0.65), 0.2)
	chunk.linear_velocity = inherited_velocity + outward.normalized() * randf_range(min_impulse, max_impulse)
	chunk.angular_velocity = Vector3(
		randf_range(-10.0, 10.0),
		randf_range(-10.0, 10.0),
		randf_range(-10.0, 10.0)
	)

	var fire_trail_script := load(FIRE_TRAIL_SCRIPT_PATH) as Script
	if fire_trail_script != null:
		var fire_trail := Node.new()
		fire_trail.set_script(fire_trail_script)
		fire_trail.set("duration", randf_range(4.0, 7.0))
		chunk.add_child(fire_trail)
