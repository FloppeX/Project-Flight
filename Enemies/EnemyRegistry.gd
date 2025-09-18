extends Node

# Registry of enemies by team id
var _team_to_enemies: Dictionary = {}
var debug_enabled: bool = false

func _ready() -> void:
	# Initialize structure
	_team_to_enemies.clear()
	# Optionally scan existing enemies in scene
	var existing = get_tree().get_nodes_in_group("enemies")
	for e in existing:
		var team_id := 0
		if e and e.has_method("get_team"):
			team_id = int(e.get_team())
		register_enemy(e, team_id)
	if debug_enabled:
		print("[EnemyRegistry] Ready. Pre-registered enemies: ", existing.size())

func register_enemy(enemy: Node, team_id: int) -> void:
	if enemy == null:
		return
	if not _team_to_enemies.has(team_id):
		_team_to_enemies[team_id] = []
	var list := _team_to_enemies[team_id] as Array
	if enemy in list:
		return
	list.append(enemy)
	# Clean up on exit
	if not enemy.is_connected("tree_exiting", Callable(self, "_on_enemy_exiting").bind(enemy, team_id)):
		enemy.connect("tree_exiting", Callable(self, "_on_enemy_exiting").bind(enemy, team_id))
	if debug_enabled:
		print("[EnemyRegistry] Registered ", enemy.name, " on team ", team_id)

func _on_enemy_exiting(enemy: Node, team_id: int) -> void:
	unregister_enemy(enemy, team_id)

func unregister_enemy(enemy: Node, team_id: int) -> void:
	if not _team_to_enemies.has(team_id):
		return
	var list := _team_to_enemies[team_id] as Array
	if enemy in list:
		list.erase(enemy)
		if debug_enabled:
			print("[EnemyRegistry] Unregistered ", enemy.name, " from team ", team_id)

func get_enemies_for_team(team_id: int) -> Array:
	if not _team_to_enemies.has(team_id):
		return []
	# Filter invalid
	var list: Array = _team_to_enemies[team_id]
	return list.filter(func(n): return is_instance_valid(n))

func get_all_enemy_positions_for_team(team_id: int) -> Array:
	var out := []
	for e in get_enemies_for_team(team_id):
		out.append({
			"node": e,
			"position": e.global_position if ("global_position" in e) else Vector3.ZERO,
			"altitude": (e.global_position.y if ("global_position" in e) else 0.0)
		})
	return out


