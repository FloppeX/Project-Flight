extends RefCounted
## Persistent combat state, independent of a spawned aircraft's scene lifetime.
## Unlike hangar servicing, capture never repairs, refuels, or rearms a unit.


static func validate(state: Dictionary) -> bool:
	if state.has("gear_sheared") and not state.gear_sheared is bool:
		return false
	if state.has("gear_collapsed") and not state.gear_collapsed is bool:
		return false
	if state.has("current_health") and not _finite_number(state.current_health):
		return false
	for section in ["modules", "hardpoints", "damage"]:
		var entries: Variant = state.get(section, [])
		if not entries is Array:
			return false
		for entry: Variant in entries:
			if not entry is Dictionary or not entry.get("path") is String or str(entry.path).is_empty():
				return false
			if section == "modules" and (not _finite_number(entry.get("level")) or not entry.get("active") is bool):
				return false
			if section == "hardpoints":
				if not entry.get("scene") is String or not _finite_number(entry.get("ammo")):
					return false
				if not str(entry.scene).is_empty() and (not ResourceLoader.exists(entry.scene) or not load(entry.scene) is PackedScene):
					return false
			if section == "damage":
				if not entry.get("zones") is Dictionary:
					return false
				for zone: Variant in entry.zones.values():
					if not zone is Dictionary or not _finite_number(zone.get("health")) or not zone.get("destroyed") is bool:
						return false
	return true


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func capture(aircraft: Node3D) -> Dictionary:
	var state := {"modules": [], "hardpoints": [], "damage": []}
	state["gear_collapsed"] = bool(aircraft.get_meta("gear_collapsed", false))
	state["gear_sheared"] = bool(aircraft.get_meta("gear_sheared", false))
	if "current_health" in aircraft:
		state["current_health"] = float(aircraft.get("current_health"))
	for node in aircraft.find_children("*", "", true, false):
		var path := str(aircraft.get_path_to(node))
		if "current_level" in node and "EnergyType" in node:
			state.modules.append({"path": path, "level": float(node.get("current_level")),
				"active": bool(node.get("ContainerActive"))})
		if node is Hardpoint:
			var weapon: Variant = node.weapon_instance
			state.hardpoints.append({"path": path,
				"scene": weapon.scene_file_path if is_instance_valid(weapon) else "",
				"ammo": int(weapon.get("ammo_count")) if is_instance_valid(weapon) else 0})
		if node.has_method("get_damage_state") and node.has_method("restore_damage_state"):
			state.damage.append({"path": path, "zones": node.get_damage_state()})
	return state


static func restore(aircraft: Node3D, state: Dictionary) -> void:
	if state.is_empty():
		return # Older saves and never-materialized slots use scene defaults.
	for entry: Dictionary in state.get("modules", []):
		var module := aircraft.get_node_or_null(NodePath(entry.path))
		if module != null:
			module.set("current_level", float(entry.level))
			module.set("ContainerActive", bool(entry.active))
	for entry: Dictionary in state.get("hardpoints", []):
		var hardpoint := aircraft.get_node_or_null(NodePath(entry.path)) as Hardpoint
		if hardpoint == null:
			continue
		if str(entry.scene).is_empty():
			if is_instance_valid(hardpoint.weapon_instance):
				hardpoint.weapon_instance.queue_free()
				hardpoint.weapon_instance = null
			hardpoint.mounted_weapon = null
			continue
		if not is_instance_valid(hardpoint.weapon_instance) or hardpoint.weapon_instance.scene_file_path != entry.scene:
			hardpoint.mount_weapon_from_scene(load(entry.scene) as PackedScene)
		if is_instance_valid(hardpoint.weapon_instance):
			hardpoint.weapon_instance.set("ammo_count", int(entry.ammo))
	for entry: Dictionary in state.get("damage", []):
		var damage := aircraft.get_node_or_null(NodePath(entry.path))
		if damage != null and damage.has_method("restore_damage_state"):
			damage.restore_damage_state(entry.zones)
	if state.has("current_health") and "current_health" in aircraft:
		aircraft.set("current_health", float(state.current_health))
	if bool(state.get("gear_collapsed", false)) or bool(state.get("gear_sheared", false)):
		aircraft.set_meta("gear_collapsed", true)
		var gear := aircraft.get_node_or_null("LandingGear")
		if gear != null:
			if bool(state.get("gear_sheared", false)):
				gear.call("shear_from_damage", false)
			else:
				gear.call("collapse_from_damage")
		var parts := aircraft.get_node_or_null("PartDamageModel") as AircraftPartDamageModel
		if parts != null and is_instance_valid(parts.systems):
			parts.systems.refresh()
	if aircraft.has_method("prepare_energy_system"):
		aircraft.prepare_energy_system()
	var weapons := aircraft.find_child("ControlWeapons", true, false)
	if weapons != null:
		weapons.find_hardpoints()
		weapons.categorize_weapons()
