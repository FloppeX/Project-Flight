extends Node
class_name FlightDeckManager

signal deck_state_changed(new_state)

@export var catapult: Node
@export var tractor_bot: Node
@export var elevator_pickup_marker: Node3D
@export var elevator: Node
@export var deck_marker: Node3D  # Marker on deck to derive deck world height
@export var tractor_bots: Array[Node] = []  # Array of 3 SimpleTractorBot nodes
@export var hangar_spawn_points: Array[Vector3] = [
	Vector3(-8, 0, 0),
	Vector3(-4, 0, 0), 
	Vector3(0, 0, 0),
	Vector3(4, 0, 0),
	Vector3(8, 0, 0),
	Vector3(12, 0, 0)
]
@export var max_hangar_capacity: int = 12
@export var aircraft_template_scene: PackedScene  # Aircraft 1 template
@export var aircraft_2_scene: PackedScene         # Aircraft 2 template

enum DeckState {
	IDLE,
	AIRCRAFT_ON_DECK,
	LAUNCH_IN_PROGRESS,
	RECOVERY_IN_PROGRESS,
	STORING_IN_HANGAR,
	RETRIEVING_FROM_HANGAR
}

var current_state: DeckState = DeckState.IDLE:
	set(value):
		if current_state != value:
			current_state = value
			emit_signal("deck_state_changed", current_state)

var deck_aircraft: RigidBody3D = null
var _recovery_powerdown_in_progress: bool = false
var _recovery_release_done: bool = false
var stored_aircraft: Array[Dictionary] = []  # Store aircraft data instead of references
var _pending_store_aircraft: RigidBody3D = null
var _aircraft_lift_height: float = 0.2  # Height to lift aircraft when moving
var _aircraft_move_speed: float = 3.0  # Speed to move aircraft around deck
var _tractor_staging_speed: float = 6.0  # Bot retreat speed to staging (m/s)
var _flight_deck_local_offset_y: float = 0.5  # Fallback local offset if no marker
var _aircraft_original_collision_layer: int = 0
var _aircraft_original_collision_mask: int = 0
var _retrieval_top_handled: bool = false

# FlightOps AI-launch queue
var _ai_launch_queue: int = 0          # Aircraft still to retrieve+launch for FlightOps
var _pending_flight_ops: Node = null   # Node waiting for notify_aircraft_launched() callbacks (FlightDirector)

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
	_ensure_elevator_signal_connections()
	set_physics_process(true)

	# Pre-populate hangar with aircraft
	_initialize_hangar_with_aircraft()

	print("[FlightDeckManager] Ready. Hangar contains ", stored_aircraft.size(), " aircraft.")

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

func _ensure_elevator_signal_connections() -> void:
	if not elevator:
		return
	if elevator.has_signal("elevator_at_bottom") and not elevator.elevator_at_bottom.is_connected(_on_elevator_at_bottom):
		elevator.elevator_at_bottom.connect(_on_elevator_at_bottom)
	if elevator.has_signal("elevator_at_top") and not elevator.elevator_at_top.is_connected(_on_elevator_at_top):
		elevator.elevator_at_top.connect(_on_elevator_at_top)
	# CarrierElevator currently emits covers_opened when returning to deck top.
	# Treat it as a top-reached fallback so state transitions complete reliably.
	if elevator.has_signal("covers_opened") and not elevator.covers_opened.is_connected(_on_elevator_covers_opened):
		elevator.covers_opened.connect(_on_elevator_covers_opened)

func _is_elevator_physically_at_top() -> bool:
	if not elevator:
		return false
	if not ("platform" in elevator) or not ("platform_size" in elevator):
		return false
	var top_y = -float(elevator.platform_size.y) * 0.5
	return abs(float(elevator.platform.position.y) - top_y) <= 0.15

func _on_elevator_covers_opened() -> void:
	# Some states can open covers before the platform is fully at deck height.
	# Only treat covers_opened as "top reached" when position is physically at top.
	if (current_state == DeckState.STORING_IN_HANGAR or current_state == DeckState.RETRIEVING_FROM_HANGAR) and _is_elevator_physically_at_top():
		_on_elevator_at_top()

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
	
	# Store last landed aircraft in hangar
	if Input.is_action_just_pressed("store_aircraft"):
		if _pending_store_aircraft and current_state == DeckState.IDLE:
			start_hangar_storage(_pending_store_aircraft)
		else:
			print("[FlightDeckManager] No aircraft to store or deck busy")
	
	# Retrieve aircraft from hangar (key "1" or retrieve_aircraft action)
	if Input.is_action_just_pressed("retrieve_aircraft") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_1):
		print("[FlightDeckManager] Retrieval requested - State: ", DeckState.keys()[current_state], " Hangar count: ", stored_aircraft.size())
		if current_state == DeckState.IDLE and not stored_aircraft.is_empty():
			start_hangar_retrieval()
		else:
			if current_state != DeckState.IDLE:
				print("[FlightDeckManager] Deck busy - current state: ", DeckState.keys()[current_state])
			if stored_aircraft.is_empty():
				print("[FlightDeckManager] Hangar is empty - no aircraft to retrieve")

	# Spawn Aircraft 2 from hangar (key "2")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_2:
		if current_state == DeckState.IDLE:
			var scene := aircraft_2_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_2.tscn")
			if scene:
				stored_aircraft.push_front({"name": "Aircraft_2", "scene_file": "", "scene": scene, "position": Vector3.ZERO, "rotation": Vector3.ZERO, "scale": Vector3.ONE, "metadata": {}})
				start_hangar_retrieval()
			else:
				print("[FlightDeckManager] ERROR: Could not load Aircraft_2.tscn")
		else:
			print("[FlightDeckManager] Deck busy - current state: ", DeckState.keys()[current_state])

	# Debug key to force reset state (key "9")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_9:
		print("[FlightDeckManager] DEBUG: Force resetting deck state to IDLE")
		current_state = DeckState.IDLE
		_pending_store_aircraft = null
		print("[FlightDeckManager] Deck state reset. Hangar count: ", stored_aircraft.size())

func request_launch_sequence(aircraft: RigidBody3D):
	if not catapult:
		print("ERROR [FlightDeckManager]: Catapult not available.")
		return

	# Clear parking brake but keep controls_disabled set until catapult latch/release.
	# This prevents AIPilot/ControlEngine from spooling before shuttle connection.
	if aircraft.has_meta("parking_brake"):
		aircraft.remove_meta("parking_brake")
		print("[FlightDeckManager] Cleared parking brake for launch")

	aircraft.set_meta("controls_disabled", true)
	

	var physics_ready_handoff := false
	# Retrieval launch handoff:
	# If retrieval already restored physics at the catapult marker, skip a second
	# restore here and tell Catapult to skip its teleport/freeze path once.
	# This avoids double handoff artifacts and keeps launch flow deterministic.
	if aircraft.has_meta("physics_ready_for_launch") and bool(aircraft.get_meta("physics_ready_for_launch")):
		aircraft.remove_meta("physics_ready_for_launch")
		physics_ready_handoff = true
		
	else:
		await _restore_aircraft_physics(aircraft)

	print("[FlightDeckManager] Launching ", aircraft.name)
	current_state = DeckState.LAUNCH_IN_PROGRESS
	deck_aircraft = aircraft
	if catapult.has_method("align_aircraft"):
		if physics_ready_handoff:
			# One-shot catapult bypass for retrieval launches.
			aircraft.set_meta("catapult_skip_teleport_once", true)
		catapult.align_aircraft(aircraft)
		# If this aircraft is AI-controlled, start AI launch state.
		# Player-retrieved aircraft should not auto-enable AI here.
		var ai_toggle = aircraft.find_child("AIToggle", true, false)
		var ai_is_active: bool = false
		if ai_toggle and "ai_active" in ai_toggle:
			ai_is_active = bool(ai_toggle.ai_active)
		if ai_is_active:
			var ai_pilot = aircraft.get_node_or_null("AIPilot")
			if ai_pilot and ai_pilot.has_method("launch"):
				print("[FlightDeckManager] Commanding AI to start launch sequence")
				ai_pilot.launch()
	else:
		print("ERROR [FlightDeckManager]: Catapult is missing the 'align_aircraft' method.")

func queue_ai_flight(count: int, ops: Node) -> void:
	"""Request FlightOps to launch `count` AI aircraft one after another.
	Each successful launch calls ops.notify_aircraft_launched(pilot)."""
	var available := mini(count, stored_aircraft.size())
	if available <= 0:
		push_warning("[FlightDeckManager] queue_ai_flight: hangar empty")
		return
	_ai_launch_queue = available
	_pending_flight_ops = ops
	print("[FlightDeckManager] FlightOps scramble: queuing ", _ai_launch_queue, " aircraft")
	if current_state == DeckState.IDLE:
		_launch_next_queued_ai()

func _launch_next_queued_ai() -> void:
	if _ai_launch_queue <= 0 or stored_aircraft.is_empty():
		_ai_launch_queue = 0
		_pending_flight_ops = null
		return
	_ai_launch_queue -= 1
	start_hangar_retrieval()

func _on_catapult_sequence_complete():
	# Notify FlightOps about the aircraft that just launched
	if _pending_flight_ops and is_instance_valid(deck_aircraft):
		var pilot = deck_aircraft.get_node_or_null("AIPilot")
		if pilot and _pending_flight_ops.has_method("notify_aircraft_launched"):
			_pending_flight_ops.notify_aircraft_launched(pilot)

	print("[FlightDeckManager] Catapult sequence complete. Deck IDLE.")
	current_state = DeckState.IDLE
	deck_aircraft = null

	# Continue queued AI launches if more are pending
	if _ai_launch_queue > 0:
		_launch_next_queued_ai()
	elif _pending_flight_ops != null:
		_pending_flight_ops = null

func _on_catapult_sequence_aborted():
	print("[FlightDeckManager] Catapult reported sequence aborted. Restoring controls and returning to IDLE.")
	if is_instance_valid(deck_aircraft):
		if deck_aircraft.has_meta("controls_disabled"):
			deck_aircraft.remove_meta("controls_disabled")
	_return_tractors_to_staging()
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
	"""Move aircraft to elevator using simple movement and visual tractorbots"""
	if not is_instance_valid(deck_aircraft) or not is_instance_valid(elevator_pickup_marker):
		print("[FlightDeckManager] WARNING: Missing deck_aircraft or elevator_pickup_marker.")
		return
	
	print("[FlightDeckManager] Moving aircraft to elevator with tractorbots")
	_move_aircraft_to_elevator(deck_aircraft)

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
	
	# Set aircraft as pending for storage
	_pending_store_aircraft = ac
	print("[FlightDeckManager] Aircraft ready for hangar storage. Press 'store_aircraft' to store.")

# --- Fallback polling and safety checks ---
func _physics_process(_delta: float) -> void:
	# 1. Safety Check: If an operation is active, verify the aircraft still exists and is on the deck
	if current_state == DeckState.LAUNCH_IN_PROGRESS or current_state == DeckState.RECOVERY_IN_PROGRESS:
		if not is_instance_valid(deck_aircraft):
			print("[FlightDeckManager] ERROR: deck_aircraft became invalid (destroyed?). Aborting sequence.")
			_abort_current_sequence()
		else:
			var deck_y = _get_deck_height_y()
			# If aircraft falls 10m below the deck, it fell off
			if deck_aircraft.global_position.y < deck_y - 10.0:
				print("[FlightDeckManager] ERROR: Aircraft fell off the deck. Aborting sequence.")
				# Allow the player/AI to fly away if they fell off, but free up the deck state
				if deck_aircraft.has_meta("controls_disabled"):
					deck_aircraft.remove_meta("controls_disabled")
				_abort_current_sequence()

	# 2. Polling for unmanaged arrests
	if current_state != DeckState.RECOVERY_IN_PROGRESS and not _recovery_powerdown_in_progress:
		var ac = _find_arrested_aircraft()
		if ac:
			print("[FlightDeckManager] Detected arrested aircraft via poll: ", ac.name)
			_on_cable_engaged(ac)
			return

func _abort_current_sequence() -> void:
	# Called when a safety check fails (plane destroyed or fell off)
	print("[FlightDeckManager] Executing emergency deck reset.")
	_return_tractors_to_staging()
	_recovery_powerdown_in_progress = false
	deck_aircraft = null
	_pending_store_aircraft = null
	if catapult and catapult.has_method("_reset_state"):
		catapult._reset_state()
	current_state = DeckState.IDLE

func _find_arrested_aircraft() -> RigidBody3D:
	var ac = get_tree().get_first_node_in_group("aircraft") as RigidBody3D
	if ac and ac.has_meta("arresting_engaged") and bool(ac.get_meta("arresting_engaged")):
		return ac
	return null

func start_post_arrest_recovery(aircraft: RigidBody3D) -> void:
	"""Called by AIPilot when the arresting cable has already auto-released.
	Skips the power-down timer and goes straight to hangar storage."""
	if not is_instance_valid(aircraft):
		return
	# If FlightDeckManager already started a managed recovery via signal, let it finish.
	if current_state == DeckState.RECOVERY_IN_PROGRESS:
		print("[FlightDeckManager] Post-arrest recovery requested but already in RECOVERY — skipping duplicate")
		return
	print("[FlightDeckManager] Starting post-arrest recovery for ", aircraft.name)
	deck_aircraft = aircraft
	current_state = DeckState.RECOVERY_IN_PROGRESS
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("controls_disabled", true)
	var th = _find_tailhook(aircraft)
	if is_instance_valid(th) and th.has_method("stow"):
		th.stow()
	_dispatch_recovery_job()
	_pending_store_aircraft = aircraft

func _configure_retrieved_aircraft_as_ai(aircraft: RigidBody3D) -> void:
	"""Set up a hangar-retrieved aircraft for AI control with land-after-launch behaviour."""
	aircraft.add_to_group("friendlies")
	aircraft.add_to_group("ai_aircraft")
	aircraft.remove_from_group("aircraft")  # Ensure not treated as player plane

	# Disable player-only nodes
	for node_name in ["CameraController", "HeadsUpDisplay", "InstrumentPanel", "ControlTargeting"]:
		var node = aircraft.find_child(node_name, true, false)
		if node:
			node.set_process(false)
			node.set_physics_process(false)
			node.set_process_input(false)
			if node is CanvasItem:
				node.visible = false
			elif node is Node3D:
				node.visible = false

	# Keep camera tripods so the player can watch this plane
	for cam_name in ["CameraCockpit", "CameraChase", "CameraCinematic"]:
		var tripod = aircraft.get_node_or_null(cam_name)
		if tripod:
			tripod.set_process(true)
			tripod.set_physics_process(true)

	# Enable AI but keep it muted until the catapult shuttle connects.
	# controls_disabled is cleared by request_launch_sequence() just before launch().
	aircraft.set_meta("controls_disabled", true)

	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("enable_ai"):
		ai_toggle.enable_ai()

	# Tell AI to go straight to landing approach after clearing the deck
	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if ai_pilot and "land_after_launch" in ai_pilot:
		ai_pilot.land_after_launch = true
		print("[FlightDeckManager] AI configured: will begin landing approach after deck clearance")

func _configure_retrieved_aircraft_as_player(aircraft: RigidBody3D) -> void:
	"""Set up a hangar-retrieved aircraft for player control."""
	# Ensure this craft is treated as a player aircraft, not AI-only.
	if not aircraft.is_in_group("aircraft"):
		aircraft.add_to_group("aircraft")
	if aircraft.is_in_group("ai_aircraft"):
		aircraft.remove_from_group("ai_aircraft")

	# Ensure player-facing nodes are enabled.
	for node_name in ["CameraController", "HeadsUpDisplay", "InstrumentPanel", "ControlTargeting"]:
		var node = aircraft.find_child(node_name, true, false)
		if not node:
			continue
		node.set_process(true)
		node.set_physics_process(true)
		node.set_process_input(true)
		if node is CanvasItem:
			node.visible = true
		elif node is Node3D:
			node.visible = true

	# Explicitly disable AI pilot for this retrieved aircraft.
	var ai_toggle = aircraft.find_child("AIToggle", true, false)
	if ai_toggle and ai_toggle.has_method("disable_ai"):
		ai_toggle.disable_ai()
	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if ai_pilot and "land_after_launch" in ai_pilot:
		ai_pilot.land_after_launch = false

	# Keep controls muted until catapult handoff/release.
	aircraft.set_meta("controls_disabled", true)
	

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

# --- Hangar Storage and Retrieval ---
func start_hangar_storage(aircraft: RigidBody3D):
	"""Start storing aircraft in hangar"""
	if stored_aircraft.size() >= max_hangar_capacity:
		print("[FlightDeckManager] Hangar at capacity")
		return
	
	current_state = DeckState.STORING_IN_HANGAR
	_retrieval_top_handled = false
	print("[FlightDeckManager] Starting hangar storage sequence")
	
	# Move elevator down to hangar level
	if elevator and elevator.has_method("move_platform_down"):
		_ensure_elevator_signal_connections()
		elevator.move_platform_down()

func start_hangar_retrieval():
	"""Start retrieving aircraft from hangar"""
	if stored_aircraft.is_empty():
		print("[FlightDeckManager] No aircraft in hangar")
		return

	current_state = DeckState.RETRIEVING_FROM_HANGAR
	_retrieval_top_handled = false
	print("[FlightDeckManager] Starting hangar retrieval sequence - lowering empty elevator")

	# Move elevator down to hangar level (empty)
	if elevator and elevator.has_method("move_platform_down"):
		_ensure_elevator_signal_connections()
		elevator.move_platform_down()

func _on_elevator_at_bottom():
	"""Handle elevator reaching bottom"""
	print("[FlightDeckManager] _on_elevator_at_bottom() called - Current state: ", DeckState.keys()[current_state])
	match current_state:
		DeckState.STORING_IN_HANGAR:
			print("[FlightDeckManager] State matches STORING_IN_HANGAR - calling _store_aircraft_in_hangar()")
			_store_aircraft_in_hangar()
		DeckState.RETRIEVING_FROM_HANGAR:
			print("[FlightDeckManager] State matches RETRIEVING_FROM_HANGAR - spawning aircraft at hangar level")
			_spawn_aircraft_at_hangar_level()
		_:
			print("[FlightDeckManager] WARNING: Elevator reached bottom but state doesn't match storage operations: ", DeckState.keys()[current_state])

func _store_aircraft_in_hangar():
	"""Store the aircraft in hangar"""
	print("[FlightDeckManager] _store_aircraft_in_hangar() called")
	if not _pending_store_aircraft:
		print("[FlightDeckManager] No aircraft to store")
		current_state = DeckState.IDLE
		return

	print("[FlightDeckManager] Storing aircraft: ", _pending_store_aircraft.name)

	# Store aircraft data for later spawning
	var aircraft_data = _extract_aircraft_data(_pending_store_aircraft)
	stored_aircraft.append(aircraft_data)
	print("[FlightDeckManager] Removing aircraft from scene: ", _pending_store_aircraft.name)

	# Remove aircraft from the scene
	_pending_store_aircraft.queue_free()
	_pending_store_aircraft = null

	print("[FlightDeckManager] Aircraft stored in hangar. Count: ", stored_aircraft.size())

	# Move elevator back up
	print("[FlightDeckManager] Commanding elevator to move up...")
	if elevator and elevator.has_method("move_platform_up"):
		_ensure_elevator_signal_connections()
		elevator.move_platform_up()
		print("[FlightDeckManager] Elevator move_platform_up() called successfully; waiting for elevator_at_top signal")
	else:
		print("[FlightDeckManager] ERROR: Elevator not found or missing move_platform_up() method")

func _spawn_aircraft_at_hangar_level():
	"""Spawn aircraft at hangar level when elevator reaches bottom during retrieval"""
	if stored_aircraft.is_empty():
		print("[FlightDeckManager] No aircraft in hangar")
		current_state = DeckState.IDLE
		return

	print("[FlightDeckManager] Spawning aircraft at hangar level on elevator platform")

	# Create aircraft at hangar level
	var aircraft = _create_aircraft_at_hangar_level()

	if not aircraft:
		print("[FlightDeckManager] Failed to create aircraft for retrieval")
		current_state = DeckState.IDLE
		return

	stored_aircraft.pop_front()  # Remove from hangar storage
	print("[FlightDeckManager] Aircraft spawned from hangar. Remaining: ", stored_aircraft.size())

	# Store reference for the retrieval sequence
	deck_aircraft = aircraft

	# Wait 1 second for aircraft to settle, then activate tractorbots and start ascent
	await get_tree().create_timer(1.0).timeout
	# Re-validate after await: local references can become stale if the node was freed.
	var retrieval_aircraft := deck_aircraft
	if not is_instance_valid(retrieval_aircraft):
		print("[FlightDeckManager] Retrieval ascent cancelled: aircraft reference is no longer valid")
		deck_aircraft = null
		current_state = DeckState.IDLE
		return
	_start_retrieval_ascent_sequence(retrieval_aircraft)

func _on_elevator_at_top():
	"""Handle elevator reaching top"""
	print("[FlightDeckManager] _on_elevator_at_top() called - Current state: ", DeckState.keys()[current_state])
	match current_state:
		DeckState.STORING_IN_HANGAR:
			current_state = DeckState.IDLE
			print("[FlightDeckManager] Storage complete - deck now IDLE")
		DeckState.RETRIEVING_FROM_HANGAR:
			if not _is_elevator_physically_at_top():
				print("[FlightDeckManager] Retrieval top signal received before elevator reached deck height; waiting...")
				return
			if _retrieval_top_handled:
				return
			_retrieval_top_handled = true
			print("[FlightDeckManager] Retrieval elevator reached top - continuing to catapult positioning")
			_complete_retrieval_sequence()
		_:
			print("[FlightDeckManager] WARNING: Elevator reached top but unexpected state: ", DeckState.keys()[current_state])

func get_hangar_status() -> Dictionary:
	"""Get hangar status"""
	return {
		"stored_count": stored_aircraft.size(),
		"max_capacity": max_hangar_capacity,
		"available_space": max_hangar_capacity - stored_aircraft.size(),
		"pending_store": _pending_store_aircraft != null
	}

func _initialize_hangar_with_aircraft():
	"""Pre-populate hangar with aircraft at startup"""
	print("[FlightDeckManager] Initializing hangar with aircraft...")

	# Fill hangar to capacity
	for i in range(max_hangar_capacity):
		var aircraft_data = {
			"name": "Aircraft_" + str(i + 1),
			"scene_file": "res://Aircraft/Aircraft_1.tscn",
			"position": Vector3.ZERO,
			"rotation": Vector3.ZERO,
			"scale": Vector3.ONE,
			"metadata": {}
		}
		stored_aircraft.append(aircraft_data)

	print("[FlightDeckManager] Hangar initialized with ", stored_aircraft.size(), " aircraft")

# --- Aircraft Movement System ---
func _move_aircraft_to_elevator(aircraft: RigidBody3D):
	"""Move aircraft to elevator position using gentle forces"""
	_activate_tractor_bots(aircraft)
	# Wait for tractorbots to position themselves, then start gentle movement
	await _wait_for_tractor_bots_positioned()
	_start_aircraft_movement(aircraft, elevator_pickup_marker.global_position)

func _activate_tractor_bots(aircraft: RigidBody3D):
	"""Activate the 3 tractorbots to position at aircraft wheels"""
	# Find the specific gear colliders by name
	var center_gear = aircraft.get_node_or_null("CenterGearCollider")
	var left_gear = aircraft.get_node_or_null("LeftGearCollider") 
	var right_gear = aircraft.get_node_or_null("RightGearCollider")
	
	var gear_colliders = [center_gear, left_gear, right_gear]
	
	for i in range(min(tractor_bots.size(), gear_colliders.size())):
		var bot = tractor_bots[i]
		var gear_collider = gear_colliders[i]
		if bot and gear_collider and bot.has_method("activate"):
			# Calculate offset from aircraft center to gear collider
			var wheel_offset = gear_collider.global_position - aircraft.global_position
			bot.activate(aircraft, wheel_offset, gear_collider)
			print("[FlightDeckManager] Activated bot ", i, " at gear: ", gear_collider.name, " offset: ", wheel_offset)

func _wait_for_tractor_bots_positioned():
	"""Wait for all tractorbots to be positioned at their gear locations"""
	print("[FlightDeckManager] Waiting for tractorbots to position...")
	
	while true:
		var all_positioned = true
		for bot in tractor_bots:
			if bot and bot.has_method("is_positioned_at_gear") and not bot.is_positioned_at_gear():
				all_positioned = false
				break
		
		if all_positioned:
			print("[FlightDeckManager] All tractorbots positioned!")
			break
		
		await get_tree().process_frame

func _deactivate_tractor_bots():
	"""Deactivate all tractorbots"""
	for bot in tractor_bots:
		if bot and bot.has_method("enable_movement"):
			bot.enable_movement()
		if bot and bot.has_method("deactivate"):
			bot.deactivate()

func _return_tractors_to_staging():
	"""Force tractorbots to drop what they are doing and return to staging"""
	for bot in tractor_bots:
		if is_instance_valid(bot):
			# Drop any active connections
			if bot.has_method("_tick_uncoupling"):
				bot._tick_uncoupling(0.0)
			# Force state to returning
			bot.set("_state", TractorBot.BotState.RETURNING_TO_STAGING)
			if bot.has_method("_plan_move_to") and is_instance_valid(bot.staging_marker):
				bot._plan_move_to(bot.staging_marker.global_position)

func _disable_tractor_bot_movement():
	"""Disable tractorbot movement logic during elevator sequence"""
	for bot in tractor_bots:
		if bot and bot.has_method("disable_movement"):
			bot.disable_movement()
			print("[FlightDeckManager] Disabled movement for ", bot.name)

func _start_aircraft_movement(aircraft: RigidBody3D, target_position: Vector3):
	"""Start moving aircraft to target position with physics disabled"""
	_prepare_aircraft_for_movement(aircraft)
	# Use the same tractor-coupled horizontal move used during retrieval so
	# storage/retrieval have consistent bot motion and pacing.
	var deck_height = _get_deck_height_y()
	var gear_colliders = _find_gear_colliders(aircraft)
	if not gear_colliders.is_empty():
		var lowest_gear_local_y = INF
		for gear in gear_colliders:
			var local_y = aircraft.to_local(gear.global_position).y
			if local_y < lowest_gear_local_y:
				lowest_gear_local_y = local_y
		var lift_aircraft_y = (deck_height + _aircraft_lift_height) - lowest_gear_local_y
		var lift_target_position = Vector3(target_position.x, lift_aircraft_y, target_position.z)
		await _move_aircraft_horizontally(aircraft, lift_target_position)
	else:
		await _move_aircraft_smoothly(aircraft, target_position)
	
	# Wait 1 second after aircraft is in position before starting elevator
	print("[FlightDeckManager] Aircraft in position. Waiting 1 second before elevator descent...")
	await get_tree().create_timer(1.0).timeout

	# After aircraft reaches elevator, start elevator sequence
	if not is_instance_valid(aircraft):
		print("[FlightDeckManager] Elevator sequence cancelled: aircraft reference is no longer valid")
		current_state = DeckState.IDLE
		return
	_start_elevator_sequence(aircraft)

func _prepare_aircraft_for_movement(aircraft: RigidBody3D):
	"""Disable physics and position aircraft with gear colliders 20cm above flight deck"""
	print("[FlightDeckManager] Preparing aircraft for movement")

	# Save original collision settings (only if not already saved)
	if _aircraft_original_collision_layer == 0:
		_aircraft_original_collision_layer = aircraft.collision_layer
		_aircraft_original_collision_mask = aircraft.collision_mask
		# Disable physics
	aircraft.set_meta("carrier_transport_mode", true)
	aircraft.freeze = true
	aircraft.gravity_scale = 0.0
	aircraft.collision_layer = 0  # Disable collision with ship
	aircraft.collision_mask = 0
	
	# Position aircraft with gear colliders 20cm above flight deck
	_position_aircraft_above_deck(aircraft)

func _position_aircraft_above_deck(aircraft: RigidBody3D):
	"""Position aircraft so gear colliders are 20cm above flight deck"""
	var gear_colliders = _find_gear_colliders(aircraft)
	var deck_height = _get_deck_height_y()
	var target_gear_height = deck_height + _aircraft_lift_height
	
	if gear_colliders.is_empty():
		print("[FlightDeckManager] No gear colliders found, using default positioning")
		# Default positioning - lift aircraft 20cm above deck
		aircraft.global_position.y = target_gear_height
		return

	# Find the lowest gear collider
	var lowest_gear_y = INF
	for gear in gear_colliders:
		if gear.global_position.y < lowest_gear_y:
			lowest_gear_y = gear.global_position.y

	# Calculate offset to position lowest gear 20cm above deck
	var y_offset = target_gear_height - lowest_gear_y
	
	# Apply offset to aircraft position
	aircraft.global_position.y += y_offset

func _move_aircraft_smoothly(aircraft: RigidBody3D, target_position: Vector3):
	"""Move aircraft smoothly to target position with rotation"""
	# Work in carrier-local space so movement tracks with the moving carrier.
	var carrier := get_parent() as Node3D
	var start_rotation = aircraft.global_rotation
	var target_rotation = aircraft.global_rotation  # Keep same rotation for now

	# Calculate target position - maintain gear at 20cm above deck
	var deck_height = _get_deck_height_y()
	var target_gear_height = deck_height + _aircraft_lift_height

	# Find the lowest gear collider to calculate the aircraft's target Y position
	var gear_colliders = _find_gear_colliders(aircraft)
	var lowest_gear_local_y = INF
	for gear in gear_colliders:
		var local_y = aircraft.to_local(gear.global_position).y
		if local_y < lowest_gear_local_y:
			lowest_gear_local_y = local_y

	# Calculate aircraft's target Y position so its lowest gear is at target_gear_height
	var aircraft_target_y = target_gear_height - lowest_gear_local_y
	var final_position = Vector3(target_position.x, aircraft_target_y, target_position.z)

	# Convert to carrier-local space
	var start_local: Vector3 = carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	var target_local: Vector3 = carrier.to_local(final_position) if carrier else final_position

	var distance = start_local.distance_to(target_local)
	var duration = distance / _aircraft_move_speed

	print("[FlightDeckManager] Moving aircraft to elevator - Distance: ", snappedf(distance, 0.1), "m")

	var elapsed_time = 0.0

	while elapsed_time < duration:
		elapsed_time += get_process_delta_time()
		var t = ease_in_out_cubic(clamp(elapsed_time / duration, 0.0, 1.0))

		# Lerp in carrier-local space, convert back to world — tracks carrier movement
		var current_local = start_local.lerp(target_local, t)
		aircraft.global_position = carrier.to_global(current_local) if carrier else current_local

		# Interpolate rotation (smooth rotation towards target)
		aircraft.global_rotation = start_rotation.slerp(target_rotation, t)

		await get_tree().process_frame

	# Final position — snap to carrier-relative target
	aircraft.global_position = carrier.to_global(target_local) if carrier else final_position
	aircraft.global_rotation = target_rotation

	# Don't deactivate tractorbots yet - they need to follow the elevator
	print("[FlightDeckManager] Aircraft moved to elevator - gear at height: ", target_gear_height)

func _find_gear_colliders(aircraft: RigidBody3D) -> Array[Node3D]:
	"""Find gear colliders on the aircraft"""
	var gear_colliders: Array[Node3D] = []
	
	# Look for common gear collider names
	var gear_names = [
		"CenterGearCollider",
		"LeftGearCollider", 
		"RightGearCollider",
		"LeftMainGearCollider",
		"RightMainGearCollider",
		"NoseGearCollider"
	]
	
	for gear_name in gear_names:
		var gear_node = aircraft.find_child(gear_name, true, false)
		if gear_node and gear_node is Node3D:
			gear_colliders.append(gear_node)
	
	# If we didn't find specific gear colliders, look for any colliders with "gear" in the name
	if gear_colliders.is_empty():
		var all_children = _get_all_children(aircraft)
		for child in all_children:
			if child is Node3D and "gear" in child.name.to_lower():
				gear_colliders.append(child)
	
	pass
	return gear_colliders

func _get_all_children(node: Node) -> Array[Node]:
	"""Get all children recursively"""
	var children: Array[Node] = []
	for child in node.get_children():
		children.append(child)
		children.append_array(_get_all_children(child))
	return children

func _get_deck_height_y() -> float:
	# Prefer explicit deck marker global height if present
	if deck_marker and deck_marker is Node3D:
		return (deck_marker as Node3D).global_position.y
	# Fallback: parent carrier global Y plus known local offset
	var carrier = get_parent()
	if carrier and carrier is Node3D:
		return (carrier as Node3D).global_position.y + _flight_deck_local_offset_y
	return _flight_deck_local_offset_y

func get_deck_height() -> float:
	"""Public method to get deck height for other components"""
	return _get_deck_height_y()

func _extract_aircraft_data(aircraft: RigidBody3D) -> Dictionary:
	"""Extract aircraft data for storage"""
	var data = {
		"name": aircraft.name,
		"scene_file": aircraft.scene_file_path if aircraft.scene_file_path else "",
		"position": aircraft.global_position,
		"rotation": aircraft.global_rotation,
		"scale": aircraft.scale,
		# Store any custom properties you want to preserve
		"metadata": {}
	}

	# Copy any metadata
	for key in aircraft.get_meta_list():
		data.metadata[key] = aircraft.get_meta(key)

	print("[FlightDeckManager] Extracted aircraft data: ", data.name)
	return data

func _create_aircraft_at_hangar_level() -> RigidBody3D:
	"""Create aircraft at hangar level from stored data and template"""
	if stored_aircraft.is_empty():
		print("[FlightDeckManager] No aircraft data in hangar")
		return null

	# Get the stored aircraft data (use first stored aircraft)
	var aircraft_data = stored_aircraft[0]  # We'll remove this after spawning

	# Use scene embedded in data dict (e.g. Aircraft 2), otherwise fall back to template
	var scene_to_use: PackedScene = aircraft_data.get("scene", null)
	if not scene_to_use:
		scene_to_use = aircraft_template_scene
	if not scene_to_use:
		print("[FlightDeckManager] No aircraft template assigned, attempting to load Aircraft_1.tscn")
		scene_to_use = load("res://Aircraft/Aircraft_1.tscn")
		if not scene_to_use:
			print("[FlightDeckManager] ERROR: Could not load Aircraft_1.tscn")
			return null

	print("[FlightDeckManager] Spawning aircraft from template at hangar level")

	# Instantiate new aircraft from template
	var aircraft = scene_to_use.instantiate() as RigidBody3D
	if not aircraft:
		print("[FlightDeckManager] ERROR: Failed to instantiate aircraft from template")
		return null

	# Mute all controls immediately — before add_child so _physics_process never sees an open throttle.
	aircraft.set_meta("controls_disabled", true)
	aircraft.set_meta("carrier_transport_mode", true)
	_aircraft_original_collision_layer = aircraft.collision_layer
	_aircraft_original_collision_mask = aircraft.collision_mask
	aircraft.freeze = true
	aircraft.gravity_scale = 0.0
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.collision_layer = 0
	aircraft.collision_mask = 0

	# Add to scene
	var main_scene = get_tree().current_scene
	main_scene.add_child(aircraft)

	# Restore aircraft properties from stored data
	aircraft.name = aircraft_data.name + "_Retrieved"

	# Position aircraft on elevator platform at hangar level (where elevator currently is)
	var elevator_hangar_pos = elevator_pickup_marker.global_position
	elevator_hangar_pos.y = _get_deck_height_y() + elevator.platform.position.y + 0.2
	aircraft.global_position = elevator_hangar_pos

	# Face aircraft toward deck forward (carrier's +Z) during retrieval
	var carrier_fwd := (get_parent() as Node3D).global_transform.basis.z
	aircraft.global_rotation = Vector3(0, atan2(carrier_fwd.x, carrier_fwd.z), 0)
	aircraft.scale = aircraft_data.scale

	# Restore metadata
	for key in aircraft_data.metadata:
		aircraft.set_meta(key, aircraft_data.metadata[key])

	# Keep aircraft fully still during elevator movement.
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	# Immediately spawn tractorbots at aircraft wheels (they can't travel from staging to hangar)
	_spawn_tractorbots_at_aircraft(aircraft)

	print("[FlightDeckManager] Aircraft spawned at: ", aircraft.global_position, " with tractorbots")
	return aircraft

func _spawn_tractorbots_at_aircraft(aircraft: RigidBody3D):
	"""Spawn tractorbots directly at aircraft wheel positions at hangar level"""
	print("[FlightDeckManager] Spawning tractorbots at aircraft wheels")

	# Find the specific gear colliders by name
	var center_gear = aircraft.get_node_or_null("CenterGearCollider")
	var left_gear = aircraft.get_node_or_null("LeftGearCollider")
	var right_gear = aircraft.get_node_or_null("RightGearCollider")

	var gear_colliders = [center_gear, left_gear, right_gear]

	# Position tractorbots directly at aircraft wheels
	for i in range(min(tractor_bots.size(), gear_colliders.size())):
		var bot = tractor_bots[i]
		var gear_collider = gear_colliders[i]
		if bot and gear_collider:
			# Position bot directly at the gear collider location
			bot.global_position = gear_collider.global_position
			bot.global_position.y = aircraft.global_position.y - 0.5  # Place bot on elevator platform level

			# Activate bot for the aircraft
			if bot.has_method("activate"):
				var wheel_offset = gear_collider.global_position - aircraft.global_position
				bot.activate(aircraft, wheel_offset, gear_collider)
				print("[FlightDeckManager] Spawned and activated bot ", i, " at gear: ", gear_collider.name)

func _start_elevator_sequence(aircraft: RigidBody3D):
	"""Start the elevator sequence - aircraft and tractorbots follow elevator down"""
	print("[FlightDeckManager] Starting elevator sequence")

	# Set state to STORING_IN_HANGAR so elevator signals work properly
	current_state = DeckState.STORING_IN_HANGAR
	_retrieval_top_handled = false

	# Ensure elevator signals are connected
	_ensure_elevator_signal_connections()

	# Disable tractorbot movement logic during elevator sequence
	_disable_tractor_bot_movement()

	# Start elevator moving down
	elevator.move_platform_down()

	# Start following the elevator with aircraft and tractorbots
	_follow_elevator_down(aircraft)


func _follow_elevator_down(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow the elevator down"""
	if not is_instance_valid(aircraft):
		print("[FlightDeckManager] Elevator-down follow aborted: aircraft is invalid")
		return
	print("[FlightDeckManager] Aircraft and tractorbots following elevator down")
	print("[FlightDeckManager] Elevator current state: ", elevator.current_state)
	
	# Store reference to aircraft for elevator following
	_pending_store_aircraft = aircraft
	
	# Get initial positions relative to deck level (not elevator platform)
	var deck_height = _get_deck_height_y()
	var initial_aircraft_position = aircraft.global_position
	
	# Calculate the aircraft's gear offset from its center
	var gear_colliders = _find_gear_colliders(aircraft)
	var lowest_gear_local_y = INF
	for gear in gear_colliders:
		var local_y = aircraft.to_local(gear.global_position).y
		if local_y < lowest_gear_local_y:
			lowest_gear_local_y = local_y
	
	# Calculate how much the aircraft center needs to be offset to position gear 0.2m above elevator
	var gear_offset_from_aircraft_center = lowest_gear_local_y
	var target_gear_height_above_elevator = 0.2  # 20cm above elevator platform
	
	# Get initial tractorbot positions relative to deck level
	var initial_bot_offsets_from_deck: Array[float] = []
	for bot in tractor_bots:
		if bot and bot.is_active:
			initial_bot_offsets_from_deck.append(bot.global_position.y - deck_height)
		else:
			initial_bot_offsets_from_deck.append(0.0)
	
	print("[FlightDeckManager] Following elevator down...")
	# Start following the elevator platform
	while is_instance_valid(aircraft) and is_instance_valid(elevator) and elevator.current_state != elevator.ElevatorState.AT_BOTTOM:
		# Refresh deck height each frame so carrier movement is tracked
		var current_deck_height = _get_deck_height_y()
		var elevator_local_y = elevator.platform.position.y
		var elevator_global_y = current_deck_height + elevator_local_y

		# Calculate aircraft position so its lowest gear is 0.2m above elevator platform
		var target_gear_height = elevator_global_y + target_gear_height_above_elevator
		var target_aircraft_y = target_gear_height - gear_offset_from_aircraft_center

		# Only update Y — carrier delta (LandCarrier._carry_deck_passengers) handles XZ
		aircraft.global_position.y = target_aircraft_y

		# Bots are carrier children so XZ auto-follows; only update Y
		for i in range(min(tractor_bots.size(), initial_bot_offsets_from_deck.size())):
			var bot = tractor_bots[i]
			if bot and bot.is_active:
				bot.global_position.y = elevator_global_y + initial_bot_offsets_from_deck[i]

		await get_tree().process_frame

	if not is_instance_valid(aircraft):
		print("[FlightDeckManager] Elevator-down follow ended: aircraft was freed during storage sequence")
		return
	
	print("[FlightDeckManager] Elevator reached bottom - waiting for signal to handle storage")

	# Now deactivate tractorbots after elevator sequence is complete
	_deactivate_tractor_bots()

func _restore_aircraft_physics(aircraft: RigidBody3D, keep_frozen: bool = false):
	"""Restore aircraft physics for launch.
	keep_frozen=true restores collisions/gravity but skips the unfreeze,
	used by the retrieval path where the aircraft is already correctly positioned."""
	print("[FlightDeckManager] Restoring aircraft physics for launch (keep_frozen=", keep_frozen, ")")

	# Force aircraft to be completely still first
	aircraft.freeze = true
	aircraft.set_gravity_scale(0.0)
	aircraft.collision_layer = 0
	aircraft.collision_mask = 0

	# Clear ALL forces and momentum aggressively
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.constant_force = Vector3.ZERO
	aircraft.constant_torque = Vector3.ZERO

	# Short frame-based settle to avoid long pauses during retrieval->launch handoff
	await get_tree().process_frame

	# Clear again after waiting
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	# Enable physics but keep aircraft frozen initially
	aircraft.set_gravity_scale(1.0)

	# Let gravity/physics state apply for a frame
	await get_tree().process_frame

	# Clear velocities one more time before unfreezing
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	var default_layer = 513  # Layers 0 and 9 (binary 1000000001)
	var default_mask = 513

	if keep_frozen:
		# Retrieval path: aircraft is already correctly positioned on the deck.
		# Restore collisions and gravity without unfreezing — avoids the moving
		# deck surface pushing the aircraft before begin_sequence freezes it.
		aircraft.set_gravity_scale(1.0)
		aircraft.collision_layer = _aircraft_original_collision_layer if _aircraft_original_collision_layer != 0 else default_layer
		aircraft.collision_mask  = _aircraft_original_collision_mask  if _aircraft_original_collision_mask  != 0 else default_mask
		if aircraft.has_meta("carrier_transport_mode"):
			aircraft.remove_meta("carrier_transport_mode")
		print("[FlightDeckManager] Aircraft physics restored (frozen, no settle). Layer=", aircraft.collision_layer)
		return

	# Normal path: aircraft was teleported to catapult, needs a brief unfreeze
	# so it can settle onto the deck under gravity before the catapult latches.
	aircraft.freeze = false
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	await get_tree().process_frame

	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	aircraft.collision_layer = _aircraft_original_collision_layer if _aircraft_original_collision_layer != 0 else default_layer
	aircraft.collision_mask  = _aircraft_original_collision_mask  if _aircraft_original_collision_mask  != 0 else default_mask

	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	if aircraft.has_meta("carrier_transport_mode"):
		aircraft.remove_meta("carrier_transport_mode")

	print("[FlightDeckManager] Aircraft physics fully restored. Layer=", aircraft.collision_layer)

func _start_retrieval_ascent_sequence(aircraft: RigidBody3D):
	"""Start the elevator ascent with aircraft and tractorbots"""
	print("[FlightDeckManager] Starting retrieval ascent sequence")

	# Tractorbots are already spawned at aircraft wheels, so just start elevator
	print("[FlightDeckManager] Tractorbots already positioned, starting elevator ascent")

	# Start elevator moving up
	_retrieval_top_handled = false
	_ensure_elevator_signal_connections()
	elevator.move_platform_up()

	# Follow elevator up with aircraft and tractorbots
	_follow_elevator_up_for_retrieval(aircraft)

func _follow_elevator_up_for_retrieval(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow the elevator up during retrieval"""
	if not is_instance_valid(aircraft):
		print("[FlightDeckManager] Elevator-up follow aborted: aircraft is invalid")
		return
	print("[FlightDeckManager] Aircraft and tractorbots following elevator up for retrieval")

	# Get initial positions relative to deck level
	var deck_height = _get_deck_height_y()

	# Calculate the aircraft's gear offset from its center
	var gear_colliders = _find_gear_colliders(aircraft)
	var lowest_gear_local_y = INF
	for gear in gear_colliders:
		var local_y = aircraft.to_local(gear.global_position).y
		if local_y < lowest_gear_local_y:
			lowest_gear_local_y = local_y

	var gear_offset_from_aircraft_center = lowest_gear_local_y
	var target_gear_height_above_elevator = 0.2  # 20cm above elevator platform

	# Get initial tractorbot positions relative to deck level
	var initial_bot_offsets_from_deck: Array[float] = []
	for bot in tractor_bots:
		if bot and bot.is_active:
			initial_bot_offsets_from_deck.append(bot.global_position.y - deck_height)
		else:
			initial_bot_offsets_from_deck.append(0.0)

	# Follow until the platform is physically at top, not just state transitions.
	while is_instance_valid(aircraft) and is_instance_valid(elevator) and not _is_elevator_physically_at_top():
		# Refresh deck height each frame so carrier movement is tracked
		var current_deck_height = _get_deck_height_y()
		var elevator_local_y = elevator.platform.position.y
		var elevator_global_y = current_deck_height + elevator_local_y

		# Calculate aircraft position so its lowest gear is 0.2m above elevator platform
		var target_gear_height = elevator_global_y + target_gear_height_above_elevator
		var target_aircraft_y = target_gear_height - gear_offset_from_aircraft_center

		# Only update Y — carrier delta (LandCarrier._carry_deck_passengers) handles XZ
		aircraft.global_position.y = target_aircraft_y

		# Bots are carrier children so XZ auto-follows; only update Y
		for i in range(min(tractor_bots.size(), initial_bot_offsets_from_deck.size())):
			var bot = tractor_bots[i]
			if bot and bot.is_active:
				bot.global_position.y = elevator_global_y + 0.2

		await get_tree().process_frame

	if not is_instance_valid(aircraft):
		print("[FlightDeckManager] Elevator-up follow ended: aircraft became invalid")
		return

	print("[FlightDeckManager] Elevator physically reached top")
	# Signal timing can vary (elevator_at_top/covers_opened may have fired early).
	# Force the handoff once we have physically reached top.
	if current_state == DeckState.RETRIEVING_FROM_HANGAR and not _retrieval_top_handled:
		_on_elevator_at_top()

func _complete_retrieval_sequence():
	"""Complete the retrieval by moving aircraft to launch position and restoring physics"""
	print("[FlightDeckManager] Completing retrieval sequence - moving to launch position")

	var aircraft = deck_aircraft
	if not is_instance_valid(aircraft):
		print("[FlightDeckManager] ERROR: No aircraft found for retrieval completion")
		deck_aircraft = null
		current_state = DeckState.IDLE
		return

	# Move aircraft to catapult latch marker
	var target_position = Vector3.ZERO
	var launch_marker = get_tree().current_scene.find_child("catapult_latch_marker", true, false)

	if launch_marker and launch_marker is Node3D:
		target_position = (launch_marker as Node3D).global_position
		print("[FlightDeckManager] Found catapult_latch_marker at: ", target_position)
	else:
		# Fallback - position forward of elevator
		target_position = elevator_pickup_marker.global_position + Vector3(0, 0, 20)
		print("[FlightDeckManager] WARNING: No catapult_latch_marker found, using fallback")

	var deck_height = _get_deck_height_y()
	var gear_colliders = _find_gear_colliders(aircraft)
	var target_gear_height = deck_height + _aircraft_lift_height  # deck + 0.2m

	if not gear_colliders.is_empty():
		# Find lowest gear collider offset
		var lowest_gear_local_y = INF
		for gear in gear_colliders:
			var local_y = aircraft.to_local(gear.global_position).y
			if local_y < lowest_gear_local_y:
				lowest_gear_local_y = local_y

		# Calculate aircraft Y position to maintain gear at deck + 0.2m
		var lift_aircraft_y = target_gear_height - lowest_gear_local_y
		var lift_target_position = Vector3(target_position.x, lift_aircraft_y, target_position.z)

		# Move to launch position while maintaining lift
		await _move_aircraft_horizontally(aircraft, lift_target_position)
	else:
		# Fallback if no gear colliders found
		await _move_aircraft_smoothly(aircraft, target_position)

	# Re-enable physics at launch position. Keep the body frozen so the moving
	# deck doesn't push it before the catapult takes over.
	await _restore_aircraft_physics(aircraft, true)

	# Lower the frozen aircraft so its wheels sit on the flight deck.
	# Must happen before tractor bots leave so they can support the aircraft.
	var deck_y := _get_deck_height_y()
	var landing_gear_nodes: Array[Node3D] = []
	for child in aircraft.get_children():
		if child is Node3D and ("gear" in child.name.to_lower() or "wheel" in child.name.to_lower()):
			landing_gear_nodes.append(child as Node3D)
		for grandchild in child.get_children():
			if grandchild is Node3D and ("gear" in grandchild.name.to_lower() or "wheel" in grandchild.name.to_lower()):
				landing_gear_nodes.append(grandchild as Node3D)
	if not landing_gear_nodes.is_empty():
		var lowest_local_y := INF
		for gear in landing_gear_nodes:
			var ly := aircraft.to_local(gear.global_position).y
			if ly < lowest_local_y:
				lowest_local_y = ly
		aircraft.global_position.y = deck_y - lowest_local_y
		print("[FlightDeckManager] Lowered aircraft to deck: gear_y=", snappedf(deck_y, 0.1), " aircraft_y=", snappedf(aircraft.global_position.y, 0.1))
	else:
		aircraft.global_position.y = deck_y
		print("[FlightDeckManager] Lowered aircraft to deck (no gear found, using deck_y directly)")

	aircraft.set_meta("physics_ready_for_launch", true)

	# After physics handoff, send tractorbots to staging.
	await _move_tractorbots_to_staging()

	# Retrieved aircraft stay AI-controlled until the player explicitly takes over.
	_configure_retrieved_aircraft_as_ai(aircraft)

	# Automatically start launch sequence
	
	request_launch_sequence(aircraft)

func _move_aircraft_horizontally(aircraft: RigidBody3D, target_position: Vector3):
	"""Move aircraft horizontally to target position with tractorbots following"""
	# Work in carrier-local space so movement tracks with the moving carrier.
	# Lerping world-space snapshots causes the aircraft to lag behind as the
	# carrier moves forward during the tween.
	var carrier := get_parent() as Node3D
	var start_local: Vector3 = carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	var target_local: Vector3 = carrier.to_local(target_position) if carrier else target_position

	var start_rotation = aircraft.global_rotation
	var target_rotation = aircraft.global_rotation  # Keep same rotation

	# Get initial tractorbot offsets from aircraft
	var bot_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot.is_active:
			bot_offsets.append(bot.global_position - aircraft.global_position)
		else:
			bot_offsets.append(Vector3.ZERO)

	var distance = start_local.distance_to(target_local)
	var duration = distance / _aircraft_move_speed

	print("[FlightDeckManager] Moving aircraft to catapult - Distance: ", snappedf(distance, 0.1), "m")

	var elapsed_time = 0.0

	while elapsed_time < duration:
		elapsed_time += get_process_delta_time()
		var t = ease_in_out_cubic(clamp(elapsed_time / duration, 0.0, 1.0))

		# Lerp in carrier-local space, convert back to world — tracks carrier movement
		var current_local = start_local.lerp(target_local, t)
		aircraft.global_position = carrier.to_global(current_local) if carrier else current_local

		# Move tractorbots to maintain relative positions
		for i in range(min(tractor_bots.size(), bot_offsets.size())):
			var bot = tractor_bots[i]
			if bot and bot.is_active:
				bot.global_position = aircraft.global_position + bot_offsets[i]

		# Interpolate rotation
		aircraft.global_rotation = start_rotation.slerp(target_rotation, t)

		await get_tree().process_frame

	# Final position — snap to carrier-relative target
	aircraft.global_position = carrier.to_global(target_local) if carrier else target_position
	aircraft.global_rotation = target_rotation

	# Final tractorbot positions
	for i in range(min(tractor_bots.size(), bot_offsets.size())):
		var bot = tractor_bots[i]
		if bot and bot.is_active:
			bot.global_position = aircraft.global_position + bot_offsets[i]

	print("[FlightDeckManager] Aircraft horizontal movement complete with tractorbots")

func _move_tractorbots_to_staging():
	"""Move tractorbots to staging at a consistent speed, then deactivate them"""
	var moving_bots: Array[Node3D] = []
	var start_positions: Array[Vector3] = []
	var target_positions: Array[Vector3] = []
	var max_distance: float = 0.0

	for i in range(tractor_bots.size()):
		var bot = tractor_bots[i]
		if bot:
			# Deactivate bot logic so it doesn't fight manual retreat motion.
			if bot.has_method("deactivate"):
				bot.deactivate()
			if bot.has_method("enable_movement"):
				bot.enable_movement()

			# Move them to a position away from the aircraft
			var staging_offset = Vector3(20.0 + i * 5.0, 0, -10.0)  # Spread them out
			var staging_position = elevator_pickup_marker.global_position + staging_offset
			staging_position.y = _get_deck_height_y()  # Put them on deck level

			if bot is Node3D:
				moving_bots.append(bot as Node3D)
				var start_pos: Vector3 = (bot as Node3D).global_position
				start_positions.append(start_pos)
				target_positions.append(staging_position)
				max_distance = maxf(max_distance, start_pos.distance_to(staging_position))

	var elapsed: float = 0.0
	var duration: float = maxf(max_distance / maxf(_tractor_staging_speed, 0.1), 0.01)
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t: float = clampf(elapsed / duration, 0.0, 1.0)
		t = ease_in_out_cubic(t)
		for i in range(moving_bots.size()):
			moving_bots[i].global_position = start_positions[i].lerp(target_positions[i], t)
		await get_tree().process_frame

	for i in range(moving_bots.size()):
		moving_bots[i].global_position = target_positions[i]
		

func ease_in_out_cubic(t: float) -> float:
	"""Smooth easing function"""
	return 3.0 * t * t - 2.0 * t * t * t
