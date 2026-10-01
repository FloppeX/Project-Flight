extends AnimatableBody3D
## Solid exterior volumes for aircraft and vehicles. Commander walking continues
## to use the separate, detailed interior surfaces on physics layer 21.

func _ready() -> void:
	var ancestor := get_parent()
	while ancestor != null and not ancestor is PhysicsBody3D:
		ancestor = ancestor.get_parent()
	if ancestor is PhysicsBody3D:
		add_collision_exception_with(ancestor)
		var commander := ancestor.get_node_or_null("Commander") as PhysicsBody3D
		if commander != null:
			add_collision_exception_with(commander)
