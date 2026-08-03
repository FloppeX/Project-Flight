extends Node
## Lightweight combat/event log — a running record of MEANINGFUL events (attacks started, hits, kills,
## crashes, flight taskings), NOT a per-frame trace of every aircraft. Autoload singleton.
##
## Two ways events get in:
##   1. Auto: connects to each aircraft's damaged/destroyed/crashed signals (polls the "aircraft" group
##      for new spawns). Hits are COALESCED per aircraft so a burst doesn't spam the log.
##   2. Manual: any system calls CombatLog.event("CATEGORY", "text") for things it alone knows about
##      (e.g. AirOpsManager on a scramble/role change, AIPilot when it commits an attack run).
##
## Output: appends to user://combat_log.txt and (optionally) prints to the console.

@export var enabled: bool = true
@export var echo_to_console: bool = true
@export var write_to_file: bool = true
@export var log_path: String = "user://combat_log.txt"
@export var aircraft_scan_interval_s: float = 1.0
## Coalesce hits: after logging a hit on a target, suppress further hit lines for this long, then log a
## summary ("N hits") instead of every round. Keeps a sustained gun pass to a couple of lines.
@export var hit_coalesce_window_s: float = 4.0

var _connected: Dictionary = {}          # aircraft instance_id -> true (already hooked)
var _scan_timer: float = 0.0
var _start_ticks_ms: int = 0
var _file: FileAccess = null
# Per-target hit coalescing: id -> {"count": int, "last_log_s": float, "pending": int}
var _hit_state: Dictionary = {}
var _dead: Dictionary = {}                # instance_id -> true once logged crashed/destroyed (suppress repeats)


func _ready() -> void:
	_start_ticks_ms = Time.get_ticks_msec()
	if write_to_file:
		_file = FileAccess.open(log_path, FileAccess.WRITE)  # fresh file each run
		if _file != null:
			_file.store_line("=== Combat log started %s ===" % Time.get_datetime_string_from_system())
			_file.flush()
	event("SYS", "Combat log online.")


func _process(delta: float) -> void:
	if not enabled:
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = maxf(aircraft_scan_interval_s, 0.25)
		_scan_aircraft()
	_flush_pending_hits()


## Public API: record a meaningful event. `category` is a short tag (ATTACK, KILL, ORDER, ...).
func event(category: String, text: String) -> void:
	if not enabled:
		return
	var line := "[%7.1f] %-6s %s" % [_elapsed_s(), category, text]
	if echo_to_console:
		print("[CombatLog] " + line)
	if write_to_file and _file != null:
		_file.store_line(line)
		_file.flush()


func _elapsed_s() -> float:
	return float(Time.get_ticks_msec() - _start_ticks_ms) / 1000.0


func _scan_aircraft() -> void:
	# Prune tracking for freed instances so the dictionaries don't grow unbounded over a long session.
	for id in _connected.keys():
		if instance_from_id(int(id)) == null:
			_connected.erase(id)
			_dead.erase(id)
			_hit_state.erase(id)
	for group in ["aircraft", "ai_aircraft", "friendlies", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is Node) or not is_instance_valid(node):
				continue
			var id := node.get_instance_id()
			if _connected.has(id):
				continue
			# Only hook things that actually emit combat signals (aircraft-like bodies).
			if not (node.has_signal("destroyed") or node.has_signal("damaged")):
				continue
			_connected[id] = true
			if node.has_signal("damaged") and not node.is_connected("damaged", _on_damaged):
				node.connect("damaged", _on_damaged.bind(node))
			if node.has_signal("destroyed") and not node.is_connected("destroyed", _on_destroyed):
				node.connect("destroyed", _on_destroyed.bind(node))
			if node.has_signal("crashed") and not node.is_connected("crashed", _on_crashed):
				node.connect("crashed", _on_crashed.bind(node))


func _label_for(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "?"
	var team_str := ""
	if node.has_method("get_team"):
		var t: int = int(node.call("get_team"))
		team_str = "T%d:" % t
	return "%s%s" % [team_str, str(node.name)]


func _on_damaged(_amount: float, current_health: float, node: Node) -> void:
	if not enabled or node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _dead.has(id):
		return  # already crashed/destroyed -- ignore trailing damage ticks
	var now := _elapsed_s()
	var st: Dictionary = _hit_state.get(id, {"count": 0, "last_log_s": -999.0, "pending": 0})
	st["count"] = int(st["count"]) + 1
	# Log the FIRST hit immediately (an aircraft coming under fire is meaningful); then coalesce.
	if now - float(st["last_log_s"]) >= hit_coalesce_window_s:
		event("HIT", "%s hit (%d total, hp=%.0f)" % [_label_for(node), int(st["count"]), current_health])
		st["last_log_s"] = now
		st["pending"] = 0
	else:
		st["pending"] = int(st["pending"]) + 1
	_hit_state[id] = st


func _flush_pending_hits() -> void:
	if _hit_state.is_empty():
		return
	var now := _elapsed_s()
	for id in _hit_state.keys():
		if _dead.has(id):
			continue
		var st: Dictionary = _hit_state[id]
		if int(st.get("pending", 0)) > 0 and now - float(st["last_log_s"]) >= hit_coalesce_window_s:
			var node: Object = instance_from_id(int(id))
			var label := _label_for(node as Node) if (node is Node and is_instance_valid(node)) else "target"
			event("HIT", "%s +%d hits (%d total)" % [label, int(st["pending"]), int(st["count"])])
			st["last_log_s"] = now
			st["pending"] = 0
			_hit_state[id] = st


func _on_destroyed(signal_node: Node = null, bound_node: Node = null) -> void:
	# Aircraft destruction signals carry no node and use the bound argument.
	# Ground-vehicle signals already carry the destroyed vehicle, so their bound
	# connection supplies a second argument. Accept both signal shapes.
	var node: Node = bound_node if bound_node != null and is_instance_valid(bound_node) else signal_node
	if not enabled or node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _dead.has(id):
		return  # already logged its death (crashed then destroyed, or repeated signal)
	_dead[id] = true
	var total := ""
	var st: Dictionary = _hit_state.get(id, {})
	if st.has("count"):
		total = " (%d hits taken)" % int(st["count"])
	event("KILL", "%s destroyed%s" % [_label_for(node), total])
	_hit_state.erase(id)


func _on_crashed(impact_velocity, node: Node) -> void:
	if not enabled or node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _dead.has(id):
		return  # crash signal can fire repeatedly while grounded -- log once
	_dead[id] = true
	var spd := ""
	if impact_velocity is Vector3:
		spd = " @%.0f m/s" % (impact_velocity as Vector3).length()
	event("CRASH", "%s crashed%s" % [_label_for(node), spd])
	_hit_state.erase(id)
