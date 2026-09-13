extends "res://Aircraft/aircraft.gd"
## Projectile-only immortality. Physical/terrain crashes remain real failures.
var received_projectile_hits := 0
func take_projectile_damage_at(amount: float, _position: Vector3, _shape: int = -1) -> StringName:
	if amount > 0.0:
		received_projectile_hits += 1
		combat_damage_received.emit(amount, &"projectile")
	return &"fuselage"
