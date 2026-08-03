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
	if not is_instance_valid(parent) or ParticleManager == null:
		queue_free()
		return
	var puff_position: Vector3 = parent.global_position + Vector3(
		randf_range(-0.4, 0.4),
		randf_range(-0.3, 0.4),
		randf_range(-0.4, 0.4)
	)
	var r := randf_range(0.25, 0.6)
	var s := randf_range(0.5, 0.9)
	var fade_frac := clampf(1.0 - _elapsed / duration, 0.2, 1.0)
	var roll := randf()
	var color: Color
	var emission_energy: float = 0.0
	if roll < 0.35:
		color = Color(randf_range(0.9, 1.0), randf_range(0.45, 0.75), 0.05, 0.8 * fade_frac)
		emission_energy = 1.5
	elif roll < 0.65:
		color = Color(randf_range(0.75, 1.0), randf_range(0.2, 0.45), 0.02, 0.65 * fade_frac)
		emission_energy = 1.0
	else:
		var v := randf_range(0.03, 0.1)
		color = Color(v, v * 0.85, v * 0.75, 0.6 * fade_frac)

	var expand := roll >= 0.65  # black smoke expands; fire core shrinks
	var life := randf_range(0.5, 1.2)
	ParticleManager.spawn_managed_smoke(
		puff_position,
		Vector3.ONE * (r * 2.0 * s),
		color,
		life,
		randf_range(4.0, 8.0),
		randf_range(-0.5, 0.5),
		expand,
		"sphere",
		emission_energy,
		false
	)
