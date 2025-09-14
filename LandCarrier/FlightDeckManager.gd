extends Node
class_name FlightDeckManager

signal deck_state_changed(new_state)

@export var catapult: Node
@export var tractor_bot: Node
@export var elevator_pickup_marker: Node3D

enum DeckState {
	IDLE,
	AIRCRAFT_ON_DECK,
	LAUNCH_IN_PROGRESS,
	RECOVERY_IN_PROGRESS
}

var current_state: DeckState = DeckState.IDLE:
	set(value):
		if current_state != value:
			current_state = value
			emit_signal("deck_state_changed", current_state)

var deck_aircraft: RigidBody3D = null
var _recovery_powerdown_in_progress: bool = false
var _recovery_release_done: bool = false

func _ready():
	add_to_group("flight_deck_manager")
	if catapult:
		if catapult.has_signal("launch_sequence_complete"):
			catapult.launch_sequence_complete.connect(_on_catapult_sequence_complete)
		if catapult.has_signal("launch_sequence_aborted"):
			catapult.launch_sequence_aborted.connect(_on_catapult_sequence_aborted)
	var cables = get_tree().get_nodes_in_group("arresting_cable")
	for c in cables:
		_connect_cable_signals(c)
	get_tree().node_added.connect(_on_node_added)
	set_physics_process(true)
	print("[FlightDeckManager] Ready.")

func _on_node_added(node: Node) -> void:
	if node.is_in_group("arresting_cable"):
		_connect_cable_signals(node)

func _connect_cable_signals(cable: Node) -> void:
	if cable.has_signal("cable_engaged") and not cable.cable_engaged.is_connected(_on_cable_engaged):
		cable.cable_engaged.connect(_on_cable_engaged)
		print("[FlightDeckManager] Connected to cable_engaged on ", cable.name)
	if cable.has_signal("cable_released") and not cable.cable_released.is_connected(_on_cable_released):
		cable.cable_released.connect(_on_cable_released)
		print("[FlightDeckManager] Connected to cable_released on ", cable.name)

func _input(event):
	if Input.is_action_just_pressed("request_launch"):
		var player_aircraft = get_tree().get_first_node_in_group("aircraft")
		if player_aircraft and player_aircraft is RigidBody3D:
			if current_state == DeckState.IDLE:
				request_launch_sequence(player_aircraft)
			else:
				print("[FlightDeckManager] Cannot start launch, deck is busy. State: ", DeckState.keys()[current_state])
		else:
			print("[FlightDeckManager] No aircraft found to launch.")

func request_launch_sequence(aircraft: RigidBody3D):
	if not catapult:
		print("ERROR [FlightDeckManager]: Catapult not available.")
		return
	print("[FlightDeckManager] Initiating launch sequence for ", aircraft.name)
	current_state = DeckState.LAUNCH_IN_PROGRESS
	deck_aircraft = aircraft
	if catapult.has_method("align_aircraft"):
		catapult.align_aircraft(aircraft)
	else:
		print("ERROR [FlightDeckManager]: Catapult is missing the 'align_aircraft' method.")

func _on_catapult_sequence_complete():
	print("[FlightDeckManager] Catapult reported sequence complete. Deck is now IDLE.")
	current_state = DeckState.IDLE
	deck_aircraft = null

func _on_catapult_sequence_aborted():
	print("[FlightDeckManager] Catapult reported sequence aborted. Deck is now IDLE.")
	current_state = DeckState.IDLE
	deck_aircraft = null

# --- Arresting cable integration ---
func _on_cable_engaged(aircraft: RigidBody3D) -> void:
	print("[FlightDeckManager] Cable engaged by ", aircraft.name)
	deck_aircraft = aircraft
	current_state = DeckState.RECOVERY_IN_PROGRESS
	_recovery_powerdown_in_progress = true
	_recovery_release_done = false
	if is_instance_valid(aircraft):
		aircraft.set_meta("controls_disabled", true)
		_call_power_down_sequence(aircraft)

func _deferred_release_cable(_cable: Node) -> void:
	# no-op now; timing handled by _call_power_down_sequence
	pass

func _on_cable_released(aircraft: RigidBody3D) -> void:
	print("[FlightDeckManager] Cable released from ", aircraft.name)
	var tailhook = _find_tailhook(aircraft)
	if is_instance_valid(tailhook) and tailhook.has_method("stow"):
		tailhook.stow()

func _dispatch_recovery_job() -> void:
	var bot: Node = tractor_bot
	if not is_instance_valid(bot):
		bot = get_tree().get_first_node_in_group("tractor_bot")
		if is_instance_valid(bot):
			tractor_bot = bot
	if not is_instance_valid(bot):
		print("[FlightDeckManager] WARNING: No tractor bot assigned; cannot recover aircraft.")
		return
	if not is_instance_valid(deck_aircraft) or not is_instance_valid(elevator_pickup_marker):
		print("[FlightDeckManager] WARNING: Missing deck_aircraft or elevator_pickup_marker.")
		return
	if bot.has_method("accept_recover_job"):
		bot.accept_recover_job(deck_aircraft, elevator_pickup_marker)
		print("[FlightDeckManager] Tractor dispatched to recover ", deck_aircraft.name)
	else:
		print("[FlightDeckManager] Tractor bot missing accept_recover_job().")

# Timed power-down and release sequence
func _call_power_down_sequence(ac: RigidBody3D) -> void:
	var engine = _find_engine(ac)
	var steps := 6
	for i in steps:
		if not is_instance_valid(ac):
			break
		var t := 1.0 - float(i + 1) / float(steps)
		if is_instance_valid(engine) and engine.has_method("set_throttle_input"):
			engine.set_throttle_input(max(0.0, t))
		await get_tree().create_timer(0.5).timeout
	# Ensure full stop
	if is_instance_valid(engine):
		if engine.has_method("engine_stop"):
			engine.engine_stop()
		elif engine.has_method("set_throttle_input"):
			engine.set_throttle_input(0.0)
	# Wait additional 3s before releasing cable
	await get_tree().create_timer(3.0).timeout
	_perform_cable_release(ac)
	_recovery_powerdown_in_progress = false
	_recovery_release_done = true

func _perform_cable_release(ac: RigidBody3D) -> void:
	if not is_instance_valid(ac):
		return
	ac.set_meta("parking_brake", true)
	var cable = ac.get_meta("arresting_cable") if ac.has_meta("arresting_cable") else null
	if cable and cable.has_method("manual_release"):
		cable.manual_release()
	# Ensure tailhook is stowed even if the signal is missed
	var th = _find_tailhook(ac)
	if is_instance_valid(th) and th.has_method("stow"):
		th.stow()
	_dispatch_recovery_job()

# --- Fallback polling to ensure robustness ---
func _physics_process(_delta: float) -> void:
	# Only poll if not already in a managed recovery sequence
	if current_state != DeckState.RECOVERY_IN_PROGRESS and not _recovery_powerdown_in_progress:
		var ac = _find_arrested_aircraft()
		if ac:
			print("[FlightDeckManager] Detected arrested aircraft via poll: ", ac.name)
			_on_cable_engaged(ac)
			return
	# Do not force-stop/release during the timed sequence; let it control timing

func _find_arrested_aircraft() -> RigidBody3D:
	var ac = get_tree().get_first_node_in_group("aircraft") as RigidBody3D
	if ac and ac.has_meta("arresting_engaged") and bool(ac.get_meta("arresting_engaged")):
		return ac
	return null

# --- Helpers ---
func _find_nodes_by_script(root: Node, script_name: String) -> Array[Node]:
	var found_nodes: Array[Node] = []
	for child in root.get_children():
		if child.get_script() and child.get_script().resource_path.ends_with(script_name):
			found_nodes.append(child)
		found_nodes.append_array(_find_nodes_by_script(child, script_name))
	return found_nodes

func _find_tailhook(root: Node) -> Node:
	# First pass: by script file name
	var nodes = _find_nodes_by_script(root, "Tailhook.gd")
	if not nodes.is_empty():
		return nodes[0]
	var nodes2 = _find_nodes_by_script(root, "TailhookSimple.gd")
	if not nodes2.is_empty():
		return nodes2[0]
	# Second pass: by ModuleType property
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n and n.has_method("get"):
			var mt = null
			# Protect against modules without get
			if n.has_method("get"):
				mt = n.get("ModuleType")
			if mt != null and str(mt).to_lower() == "tailhook":
				return n
		for child in n.get_children():
			stack.push_back(child)
	# Third pass: any node with stow() and class/script hint containing Tailhook
	stack = [root]
	while not stack.is_empty():
		var n2 = stack.pop_back()
		if n2 and n2.has_method("stow"):
			var hint = ""
			if n2.get_script():
				hint = str(n2.get_script().resource_path)
			if hint.to_lower().find("tailhook") != -1 or n2.get_class().to_lower().find("tailhook") != -1:
				return n2
		for ch in n2.get_children():
			stack.push_back(ch)
	return null

func _find_engine(root: Node) -> Node:
	var engine_nodes = _find_nodes_by_script(root, "Engine.gd")
	if not engine_nodes.is_empty():
		return engine_nodes[0]
	return null
