extends AircraftPartDamageModel

## The fixed inner panels share damage pools with the folding outer tips.
## The tip colliders follow their hinges; inner colliders stay with the hull.
func _destroy_zone(zone: StringName) -> void:
	super._destroy_zone(zone)
	var inner_path := ""
	if zone == ZONE_LEFT_WING:
		inner_path = "../LeftWingRootDamageCollider"
	elif zone == ZONE_RIGHT_WING:
		inner_path = "../RightWingRootDamageCollider"
	if not inner_path.is_empty():
		var collider := get_node_or_null(inner_path) as CollisionShape3D
		if collider != null:
			collider.set_deferred("disabled", true)
