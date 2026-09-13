extends RefCounted

## Shared by flight assignment and autonomous pilot selection. Call only on
## reported/known targets; this helper does not discover contacts.
static func threat_tier(node: Node3D) -> int:
	if node == null or not is_instance_valid(node):
		return 2
	# Idle/LOD-sleeping guns retain weapon capability. Explicit unarmed dummies
	# do not. Health/team eligibility belongs to the caller.
	if "is_dummy" in node and bool(node.get("is_dummy")):
		return 1
	if node.is_in_group("gun_emplacements") or node.is_in_group("carrier"):
		return 0
	if "turret_weapon" in node and node.get("turret_weapon") != null:
		return 0
	var turret: Node = node.find_child("TurretController", true, false)
	if turret != null and "weapon_scene" in turret and turret.get("weapon_scene") != null:
		return 0
	return 1
