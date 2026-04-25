extends Node
class_name FireTrail

## Attaches to a Node3D (or RigidBody3D) and emits fire puffs from its position.
## Self-destructs after `duration` seconds.

var duration: float = 8.0
var interval: float = 0.06

var _timer: float = 0.0
var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = interval
		_spawn_puff()


func _spawn_puff() -> void:
	var parent := get_parent() as Node3D
	if not is_instance_valid(parent):
		queue_free()
		return

	var puff := MeshInstance3D.new()
	get_tree().current_scene.add_child(puff)
	puff.global_position = parent.global_position + Vector3(
		randf_range(-0.4, 0.4),
		randf_range(-0.3, 0.4),
		randf_range(-0.4, 0.4)
	)

	var sphere := SphereMesh.new()
	sphere.radial_segments = 6
	sphere.rings = 4
	var r := randf_range(0.25, 0.6)
	sphere.radius = r
	sphere.height = r * 2.0
	puff.mesh = sphere

	var s := randf_range(0.5, 0.9)
	puff.scale = Vector3(s, s, s)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var fade_frac := clampf(1.0 - _elapsed / duration, 0.2, 1.0)
	var roll := randf()
	if roll < 0.35:
		var col := Color(randf_range(0.9, 1.0), randf_range(0.45, 0.75), 0.05, 0.8 * fade_frac)
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = Color(col.r * 0.5, col.g * 0.2, 0.0)
		mat.emission_energy_multiplier = 1.5
	elif roll < 0.65:
		var col := Color(randf_range(0.75, 1.0), randf_range(0.2, 0.45), 0.02, 0.65 * fade_frac)
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = Color(col.r * 0.3, 0.05, 0.0)
		mat.emission_energy_multiplier = 1.0
	else:
		var v := randf_range(0.03, 0.1)
		mat.albedo_color = Color(v, v * 0.85, v * 0.75, 0.6 * fade_frac)

	puff.material_override = mat

	var expand := roll >= 0.65  # black smoke expands; fire core shrinks
	var life := randf_range(0.5, 1.2)
	ParticleManager.add_rising_smoke(puff, life, puff.scale,
		randf_range(4.0, 8.0), randf_range(-0.5, 0.5), {"expand": expand})
