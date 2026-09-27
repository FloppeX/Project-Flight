extends SceneTree

func _initialize() -> void:
	var canonical := load("res://Projectiles/AG Missile/ag_missile_projectile.tscn") as PackedScene
	var compatible := load("res://Projectiles/AG Missile/ag_missile.tscn") as PackedScene
	if canonical == null or compatible == null:
		quit(1)
		return
	var expected := canonical.instantiate()
	var actual := compatible.instantiate()
	var valid := true
	for property in ["mass", "collision_layer", "collision_mask", "damage", "max_speed_mps", "thrust_force"]:
		if actual.get(property) != expected.get(property):
			push_error("Missile compatibility mismatch: " + property)
			valid = false
	for path in ["missile", "CollisionShape3D", "NoseCamera"]:
		if not actual.has_node(path) or actual.get_node(path).transform != expected.get_node(path).transform:
			push_error("Missile compatibility node mismatch: " + path)
			valid = false
	var holder := AGMissileHolder.new()
	if not holder._ensure_missile_scene() or holder.missile_scene != canonical:
		push_error("Missile holder did not choose canonical projectile")
		valid = false
	holder.free()
	expected.free()
	actual.free()
	print("MISSILE_SCENE_COMPATIBILITY ", "PASS" if valid else "FAIL")
	quit(0 if valid else 1)
