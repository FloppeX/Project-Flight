extends SceneTree

var failures: Array[String] = []
var livery: Node
var minimum_distance := INF

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	for child in root.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
	livery = root.get_node("Livery")
	livery.get("_rng").seed = 13092026
	var presets: Array = livery.get("PRESET_UPPER_COLORS")
	var cases := 0
	# Every ordered preset pair, including identical colours and neutrals.
	for primary in presets:
		for secondary in presets:
			livery.call("set_player_livery", primary, secondary, 18)
			livery.call("_reset_team_livery_assignments")
			for team in [2, 3]:
				validate_team(team, primary, secondary)
				cases += 1
	# Arbitrary picker colours must use actual colours, not stale preset indices.
	for pair in [[Color("446080"), Color("7790ab")], [Color("080707"), Color("eae9e9")],
			[Color.from_hsv(0.99, 0.9, 0.8), Color.from_hsv(0.01, 0.85, 0.75)]]:
		livery.call("set_player_livery", pair[0], pair[1], 18)
		for team in range(2, 32):
			validate_team(team, pair[0], pair[1])
			cases += 1
	# Repeated generation has variety, repeated reads/pattern edits have stability.
	livery.call("set_player_livery", Color("2580bd"), Color("edce63"), 0)
	var distinct: Dictionary = {}
	for iteration in 64:
		livery.call("_reset_team_livery_assignments")
		var enemy: Color = livery.call("_get_team_upper_color", 2)
		distinct[enemy.to_html()] = true
	check(distinct.size() > 1, "random variety among safe primary colours")
	var before: Color = livery.call("_get_team_upper_color", 2)
	var before_secondary: Color = livery.call("_get_team_secondary_color", 2)
	var insignia: int = livery.call("_get_team_insignia_index", 2)
	livery.call("set_player_livery", Color("2580bd"), Color("edce63"), 18)
	check(before == livery.call("_get_team_upper_color", 2), "pattern-only edit preserves primary")
	check(before_secondary == livery.call("_get_team_secondary_color", 2), "pattern-only edit preserves secondary")
	# Player deliberately adopts the enemy's old palette: existing enemy must adapt.
	livery.call("set_player_livery", before, before_secondary, 18)
	validate_team(2, before, before_secondary)
	check(insignia == livery.call("_get_team_insignia_index", 2), "colour repair preserves insignia")
	print("ENEMY_LIVERY_SEPARATION_%s cases=%d minimum_distance=%.4f varied_primaries=%d failures=%s" % [
		"PASS" if failures.is_empty() else "FAIL", cases, minimum_distance, distinct.size(), failures])
	quit(0 if failures.is_empty() else 1)

func validate_team(team: int, player_primary: Color, player_secondary: Color) -> void:
	var primary: Color = livery.call("_get_team_upper_color", team)
	var secondary: Color = livery.call("_get_team_secondary_color", team)
	for enemy in [primary, secondary]:
		for player in [player_primary, player_secondary]:
			var distance: float = livery.call("_color_separation", enemy, player)
			minimum_distance = minf(minimum_distance, distance)
			check(distance >= 0.35 - 0.00001, "team %d distance %.4f below threshold" % [team, distance])
	check(primary != secondary, "enemy two-tone paint retains two colours")
	check(primary == livery.call("_get_team_upper_color", team), "repeated lookup preserves faction colour")

func check(ok: bool, label: String) -> void:
	if not ok and failures.size() < 20:
		failures.append(label)
