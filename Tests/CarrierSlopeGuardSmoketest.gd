extends Node

class TestCarrier:
	extends "res://LandCarrier/LandCarrier.gd"
	var terrain_mode := "flat"
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
	func _sample_precise_terrain_y(x: float, z: float) -> float:
		match terrain_mode:
			"gentle": return z * 0.1
			"mountain": return maxf(z - 20.0, 0.0) * 2.0
			"drop": return -maxf(z - 20.0, 0.0) * 2.0
			"side": return maxf(z - 20.0, 0.0) * 2.0 if x > 10.0 else 0.0
		return 0.0

func _ready() -> void:
	var c := TestCarrier.new()
	add_child(c)
	for mode in ["flat", "gentle"]:
		c.terrain_mode = mode
		assert(is_inf(c._get_terrain_drive_speed_limit(10.0)), mode)
	for mode in ["mountain", "drop", "side"]:
		c.terrain_mode = mode
		c.position = Vector3.ZERO
		c._tread_local_xz.assign([Vector2(-20.0, 0.0), Vector2(20.0, 0.0)])
		c._current_planar_speed_mps = 10.0
		for frame in range(300):
			c._apply_drive_motion(1.0 / 60.0, 10.0, 0.0)
		assert(c.position.z < 20.0, "%s crossed slope: %s" % [mode, c.position])
		assert(is_zero_approx(c._current_planar_speed_mps), "%s did not stop" % mode)
	c.free()
	print("[CarrierSlopeGuardSmoketest] PASS flat gentle climb drop lateral_obstacle")
	get_tree().quit()
