extends Node

const GUNS := preload("res://Weapons/Turrets/TurretGunCatalog.gd")
@export var starting_turret_count: int = 2
var _initialized: bool = false

func _ready() -> void:
	call_deferred("_initialize")

func _initialize() -> void:
	if _initialized:
		return
	var carrier := get_parent()
	if carrier.has_method("_get_pending_carrier_save_state"):
		var saved: Dictionary = carrier.call("_get_pending_carrier_save_state")
		if saved.has("defense_loadout") and saved.defense_loadout is Dictionary:
			if restore_save_state(saved.defense_loadout):
				return
	initialize_starting_turrets()

func get_build_sites() -> Array[Node3D]:
	var sites: Array[Node3D] = []
	for node in get_parent().find_children("*", "Node3D", true, false):
		if node.has_method("build_turret"):
			sites.append(node as Node3D)
	return sites

func initialize_starting_turrets(seed_value: int = 0) -> void:
	if _initialized:
		return
	var sites := get_build_sites()
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	for i in range(sites.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := sites[i]
		sites[i] = sites[j]
		sites[j] = temp
	for i in range(mini(maxi(starting_turret_count, 0), sites.size())):
		sites[i].call("build_turret", GUNS.CALIBERS[rng.randi_range(0, GUNS.CALIBERS.size() - 1)])
	_initialized = true
	_refresh_defense_ops()

func capture_save_state() -> Dictionary:
	var turrets: Array[Dictionary] = []
	for site in get_build_sites():
		if bool(site.call("is_built")):
			turrets.append({"site": str(get_parent().get_path_to(site)), "caliber_mm": int(site.get("installed_caliber_mm"))})
	return {"version": 1, "turrets": turrets}

func restore_save_state(state: Dictionary) -> bool:
	var entries: Variant = state.get("turrets")
	if not entries is Array:
		return false
	var sites := get_build_sites()
	var validated: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary:
			return false
		var path := NodePath(str(entry.get("site", "")))
		var site := get_parent().get_node_or_null(path) as Node3D
		var caliber := int(entry.get("caliber_mm", 0))
		if not sites.has(site) or validated.has(site) or not GUNS.CALIBERS.has(caliber):
			return false
		validated[site] = caliber
	for site in sites:
		site.call("clear_turret")
	for site in validated:
		site.call("build_turret", validated[site])
	_initialized = true
	_refresh_defense_ops()
	return true

func _refresh_defense_ops() -> void:
	var ops := get_parent().get_node_or_null("DefenseOps")
	if ops != null:
		ops.call("coordinate_defense")
