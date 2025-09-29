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
@export var aircraft_template_scene: PackedScene  # Aircraft template for spawning new aircraft

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
var _flight_deck_local_offset_y: float = 0.5  # Fallback local offset if no marker
var _aircraft_original_collision_layer: int = 0
var _aircraft_original_collision_mask: int = 0

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
	
	# Restore physics for launch
	_restore_aircraft_physics(aircraft)
	
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

# --- Hangar Storage and Retrieval ---
func start_hangar_storage(aircraft: RigidBody3D):
	"""Start storing aircraft in hangar"""
	if stored_aircraft.size() >= max_hangar_capacity:
		print("[FlightDeckManager] Hangar at capacity")
		return
	
	current_state = DeckState.STORING_IN_HANGAR
	print("[FlightDeckManager] Starting hangar storage sequence")
	
	# Move elevator down to hangar level
	if elevator and elevator.has_method("move_platform_down"):
		elevator.move_platform_down()
		# Connect to elevator signals to continue sequence
		if not elevator.elevator_at_bottom.is_connected(_on_elevator_at_bottom):
			elevator.elevator_at_bottom.connect(_on_elevator_at_bottom)

func start_hangar_retrieval():
	"""Start retrieving aircraft from hangar"""
	if stored_aircraft.is_empty():
		print("[FlightDeckManager] No aircraft in hangar")
		return

	current_state = DeckState.RETRIEVING_FROM_HANGAR
	print("[FlightDeckManager] Starting hangar retrieval sequence - lowering empty elevator")

	# Move elevator down to hangar level (empty)
	if elevator and elevator.has_method("move_platform_down"):
		elevator.move_platform_down()
		# Connect to elevator signals to continue sequence
		if not elevator.elevator_at_bottom.is_connected(_on_elevator_at_bottom):
			elevator.elevator_at_bottom.connect(_on_elevator_at_bottom)

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

	# Wait 5 seconds before returning elevator to flight deck
	print("[FlightDeckManager] Waiting 5 seconds before returning elevator...")
	await get_tree().create_timer(5.0).timeout

	# Move elevator back up
	print("[FlightDeckManager] Commanding elevator to move up...")
	if elevator and elevator.has_method("move_platform_up"):
		elevator.move_platform_up()
		print("[FlightDeckManager] Elevator move_platform_up() called successfully")

		# Wait for elevator to finish and set to IDLE
		await get_tree().create_timer(10.0).timeout
		current_state = DeckState.IDLE
		print("[FlightDeckManager] Storage complete - deck now IDLE")
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
	_start_retrieval_ascent_sequence(aircraft)

func _on_elevator_at_top():
	"""Handle elevator reaching top"""
	print("[FlightDeckManager] _on_elevator_at_top() called - Current state: ", DeckState.keys()[current_state])
	match current_state:
		DeckState.STORING_IN_HANGAR:
			current_state = DeckState.IDLE
			print("[FlightDeckManager] Storage complete - deck now IDLE")
		DeckState.RETRIEVING_FROM_HANGAR:
			print("[FlightDeckManager] Retrieval elevator complete - continuing to catapult positioning")
			# Wait 1 second, then move aircraft to launch position
			await get_tree().create_timer(1.0).timeout
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
			bot.activate(aircraft, wheel_offset)
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
		if bot and bot.has_method("deactivate"):
			bot.deactivate()

func _disable_tractor_bot_movement():
	"""Disable tractorbot movement logic during elevator sequence"""
	for bot in tractor_bots:
		if bot and bot.has_method("disable_movement"):
			bot.disable_movement()
			print("[FlightDeckManager] Disabled movement for ", bot.name)

func _start_aircraft_movement(aircraft: RigidBody3D, target_position: Vector3):
	"""Start moving aircraft to target position with physics disabled"""
	_prepare_aircraft_for_movement(aircraft)
	await _move_aircraft_smoothly(aircraft, target_position)
	
	# Wait 1 second after aircraft is in position before starting elevator
	print("[FlightDeckManager] Aircraft in position. Waiting 1 second before elevator descent...")
	await get_tree().create_timer(1.0).timeout

	# After aircraft reaches elevator, start elevator sequence
	_start_elevator_sequence(aircraft)

func _prepare_aircraft_for_movement(aircraft: RigidBody3D):
	"""Disable physics and position aircraft with gear colliders 20cm above flight deck"""
	print("[FlightDeckManager] Preparing aircraft for movement")
	
	# Save original collision settings
	_aircraft_original_collision_layer = aircraft.collision_layer
	_aircraft_original_collision_mask = aircraft.collision_mask
	
	# Disable physics
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
	
	print("[FlightDeckManager] Deck height: ", deck_height, " Target gear height: ", target_gear_height, " Current lowest gear Y: ", lowest_gear_y, " Y offset: ", y_offset)
	
	# Apply offset to aircraft position
	aircraft.global_position.y += y_offset
	
	print("[FlightDeckManager] Aircraft positioned with gear 20cm above flight deck at height: ", target_gear_height)

func _move_aircraft_smoothly(aircraft: RigidBody3D, target_position: Vector3):
	"""Move aircraft smoothly to target position with rotation"""
	var start_position = aircraft.global_position
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
	
	var distance = start_position.distance_to(final_position)
	var duration = distance / _aircraft_move_speed
	
	print("[FlightDeckManager] Moving aircraft smoothly to elevator - Distance: ", distance, " Duration: ", duration)
	print("[FlightDeckManager] Aircraft target Y: ", aircraft_target_y, " Gear will be at: ", target_gear_height)
	
	# Use a proper timer for smooth movement
	var elapsed_time = 0.0
	
	# Smooth movement with rotation
	while aircraft.global_position.distance_to(final_position) > 0.1:
		elapsed_time += get_process_delta_time()
		
		if elapsed_time >= duration:
			break
		
		var t = elapsed_time / duration
		t = ease_in_out_cubic(t)  # Smooth easing
		
		# Interpolate position - maintain gear height throughout movement
		var current_position = start_position.lerp(final_position, t)
		aircraft.global_position = current_position
		
		# Interpolate rotation (smooth rotation towards target)
		aircraft.global_rotation = start_rotation.slerp(target_rotation, t)
		
		await get_tree().process_frame
	
	# Final position
	aircraft.global_position = final_position
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
	
	print("[FlightDeckManager] Found ", gear_colliders.size(), " gear colliders")
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

	if not aircraft_template_scene:
		print("[FlightDeckManager] No aircraft template assigned, attempting to load CompleteFighterJet.tscn")
		aircraft_template_scene = load("res://CompleteFighterJet.tscn")
		if not aircraft_template_scene:
			print("[FlightDeckManager] ERROR: Could not load CompleteFighterJet.tscn")
			return null
		else:
			print("[FlightDeckManager] Successfully loaded aircraft template")

	print("[FlightDeckManager] Spawning aircraft from template at hangar level")

	# Get the stored aircraft data (use first stored aircraft)
	var aircraft_data = stored_aircraft[0]  # We'll remove this after spawning

	# Instantiate new aircraft from template
	var aircraft = aircraft_template_scene.instantiate() as RigidBody3D
	if not aircraft:
		print("[FlightDeckManager] ERROR: Failed to instantiate aircraft from template")
		return null

	# Add to scene
	var main_scene = get_tree().current_scene
	main_scene.add_child(aircraft)

	# Restore aircraft properties from stored data
	aircraft.name = aircraft_data.name + "_Retrieved"

	# Position aircraft on elevator platform at hangar level (where elevator currently is)
	var elevator_hangar_pos = elevator_pickup_marker.global_position
	elevator_hangar_pos.y = _get_deck_height_y() + elevator.platform.position.y + 0.2
	aircraft.global_position = elevator_hangar_pos

	# Apply stored rotation and scale if desired
	aircraft.global_rotation = aircraft_data.rotation
	aircraft.scale = aircraft_data.scale

	# Restore metadata
	for key in aircraft_data.metadata:
		aircraft.set_meta(key, aircraft_data.metadata[key])

	# Disable physics for elevator movement
	aircraft.freeze = true
	aircraft.gravity_scale = 0.0
	aircraft.collision_layer = 0
	aircraft.collision_mask = 0

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
				bot.activate(aircraft, wheel_offset)
				print("[FlightDeckManager] Spawned and activated bot ", i, " at gear: ", gear_collider.name)

func _start_retrieval_elevator_sequence(aircraft: RigidBody3D):
	"""Start elevator ascent with aircraft and activate tractorbots"""
	print("[FlightDeckManager] Starting retrieval elevator sequence")

	# Activate tractorbots at aircraft position
	_activate_tractor_bots(aircraft)
	await _wait_for_tractor_bots_positioned()

	# Start elevator moving up
	if elevator and elevator.has_method("move_platform_up"):
		elevator.move_platform_up()

	# Follow elevator up with aircraft and tractorbots
	await _follow_elevator_up(aircraft)

func _follow_elevator_up(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow elevator up"""
	print("[FlightDeckManager] Aircraft and tractorbots following elevator up")

	var deck_height = _get_deck_height_y()
	var gear_colliders = _find_gear_colliders(aircraft)
	var lowest_gear_local_y = INF
	for gear in gear_colliders:
		var local_y = aircraft.to_local(gear.global_position).y
		if local_y < lowest_gear_local_y:
			lowest_gear_local_y = local_y

	var gear_offset_from_aircraft_center = lowest_gear_local_y
	var target_gear_height_above_elevator = 0.2

	# Follow elevator up until it reaches the top
	while elevator.current_state != elevator.ElevatorState.AT_TOP:
		var elevator_local_y = elevator.platform.position.y
		var elevator_global_y = deck_height + elevator_local_y

		# Calculate aircraft position so its lowest gear is 0.2m above elevator
		var target_gear_height = elevator_global_y + target_gear_height_above_elevator
		var target_aircraft_y = target_gear_height - gear_offset_from_aircraft_center

		aircraft.global_position.y = target_aircraft_y

		# Move tractorbots with elevator
		for bot in tractor_bots:
			if bot and bot.is_active:
				var target_bot_position = bot.global_position
				target_bot_position.y = elevator_global_y + 0.2
				bot.global_position = target_bot_position

		await get_tree().process_frame

	print("[FlightDeckManager] Elevator reached top - moving aircraft to catapult")

	# Wait 1 second at the top
	await get_tree().create_timer(1.0).timeout

	# Move aircraft to catapult position
	_move_aircraft_to_catapult(aircraft)

func _move_aircraft_to_catapult(aircraft: RigidBody3D):
	"""Move aircraft from elevator to catapult position and restore physics"""
	print("[FlightDeckManager] Moving aircraft to catapult position")

	# Get catapult position (assuming it has a global position we can use)
	var catapult_position = Vector3.ZERO
	if catapult and catapult is Node3D:
		catapult_position = (catapult as Node3D).global_position
	else:
		# Fallback - position forward of elevator
		catapult_position = elevator_pickup_marker.global_position + Vector3(0, 0, 20)

	# Move aircraft smoothly to catapult
	await _move_aircraft_smoothly(aircraft, catapult_position)

	# Lower aircraft to deck and restore physics
	_position_aircraft_above_deck(aircraft)
	_restore_aircraft_physics(aircraft)

	# Deactivate tractorbots
	_deactivate_tractor_bots()

	# Set state back to idle - aircraft is ready for launch
	current_state = DeckState.IDLE
	print("[FlightDeckManager] Aircraft positioned at catapult and ready for launch")

func _start_elevator_sequence(aircraft: RigidBody3D):
	"""Start the elevator sequence - aircraft and tractorbots follow elevator down"""
	print("[FlightDeckManager] Starting elevator sequence")

	# Set state to STORING_IN_HANGAR so elevator signals work properly
	current_state = DeckState.STORING_IN_HANGAR

	# Connect to elevator signals if not already connected
	if not elevator.elevator_at_bottom.is_connected(_on_elevator_at_bottom):
		elevator.elevator_at_bottom.connect(_on_elevator_at_bottom)
	if not elevator.elevator_at_top.is_connected(_on_elevator_at_top):
		elevator.elevator_at_top.connect(_on_elevator_at_top)

	# Disable tractorbot movement logic during elevator sequence
	_disable_tractor_bot_movement()

	# Start elevator moving down
	elevator.move_platform_down()

	# Start following the elevator with aircraft and tractorbots
	_follow_elevator_down(aircraft)


func _follow_elevator_down(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow the elevator down"""
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
	
	print("[FlightDeckManager] Deck height: ", deck_height)
	print("[FlightDeckManager] Lowest gear local Y: ", lowest_gear_local_y)
	print("[FlightDeckManager] Initial bot offsets from deck: ", initial_bot_offsets_from_deck)
	
	print("[FlightDeckManager] Starting elevator following loop")
	# Start following the elevator platform
	while elevator.current_state != elevator.ElevatorState.AT_BOTTOM:
		# Calculate the current elevator platform height relative to deck
		var elevator_local_y = elevator.platform.position.y
		var elevator_global_y = deck_height + elevator_local_y
		
		# Calculate aircraft position so its lowest gear is 0.2m above elevator platform
		var target_gear_height = elevator_global_y + target_gear_height_above_elevator
		var target_aircraft_y = target_gear_height - gear_offset_from_aircraft_center
		
		# Move aircraft maintaining the same relative position to deck
		var target_aircraft_position = aircraft.global_position
		target_aircraft_position.y = target_aircraft_y
		aircraft.global_position = target_aircraft_position
		
		# Disabled for cleaner output:
		# print("[FlightDeckManager] Elevator local Y: ", elevator_local_y, " Global Y: ", elevator_global_y, " Aircraft Y: ", target_aircraft_y, " Gear will be at: ", target_gear_height)

		# Move tractorbots maintaining the same relative positions to deck
		for i in range(min(tractor_bots.size(), initial_bot_offsets_from_deck.size())):
			var bot = tractor_bots[i]
			if bot and bot.is_active:
				var target_bot_position = bot.global_position
				target_bot_position.y = elevator_global_y + initial_bot_offsets_from_deck[i]
				bot.global_position = target_bot_position
				# Disabled: print("[FlightDeckManager] Bot ", i, " positioned at: ", target_bot_position)
		
		await get_tree().process_frame
	
	print("[FlightDeckManager] Elevator reached bottom - waiting for signal to handle storage")

	# Now deactivate tractorbots after elevator sequence is complete
	_deactivate_tractor_bots()

func _restore_aircraft_physics(aircraft: RigidBody3D):
	"""Restore aircraft physics for launch"""
	print("[FlightDeckManager] Restoring aircraft physics for launch")

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

	# Wait longer for everything to settle
	await get_tree().create_timer(1.0).timeout

	# Clear again after waiting
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	# Enable physics but keep aircraft frozen initially
	aircraft.set_gravity_scale(1.0)

	# Wait more
	await get_tree().create_timer(0.5).timeout

	# Clear velocities one more time before unfreezing
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	# Unfreeze and immediately clear velocities
	aircraft.freeze = false
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	# Wait a bit more before enabling collisions
	await get_tree().create_timer(0.5).timeout

	# Clear velocities yet again
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	# Finally restore collisions
	aircraft.collision_layer = _aircraft_original_collision_layer
	aircraft.collision_mask = _aircraft_original_collision_mask

	# Final clearing after collisions enabled
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	print("[FlightDeckManager] Aircraft physics fully restored with aggressive velocity clearing")

func _start_retrieval_ascent_sequence(aircraft: RigidBody3D):
	"""Start the elevator ascent with aircraft and tractorbots"""
	print("[FlightDeckManager] Starting retrieval ascent sequence")

	# Tractorbots are already spawned at aircraft wheels, so just start elevator
	print("[FlightDeckManager] Tractorbots already positioned, starting elevator ascent")

	# Start elevator moving up
	elevator.move_platform_up()

	# Follow elevator up with aircraft and tractorbots
	_follow_elevator_up_for_retrieval(aircraft)

func _follow_elevator_up_for_retrieval(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow the elevator up during retrieval"""
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

	# Start following the elevator platform up - continue until elevator actually stops moving
	var last_elevator_y = elevator.platform.position.y
	var elevator_stopped_frames = 0

	while true:
		# Calculate the current elevator platform height relative to deck
		var elevator_local_y = elevator.platform.position.y
		var elevator_global_y = deck_height + elevator_local_y

		# Calculate aircraft position so its lowest gear is 0.2m above elevator platform
		var target_gear_height = elevator_global_y + target_gear_height_above_elevator
		var target_aircraft_y = target_gear_height - gear_offset_from_aircraft_center

		# Move aircraft to follow elevator
		aircraft.global_position.y = target_aircraft_y

		# Move tractorbots to follow elevator
		for i in range(min(tractor_bots.size(), initial_bot_offsets_from_deck.size())):
			var bot = tractor_bots[i]
			if bot and bot.is_active:
				var target_bot_position = bot.global_position
				target_bot_position.y = elevator_global_y + 0.2  # Keep bots on elevator platform
				bot.global_position = target_bot_position

		# Check if elevator has actually stopped moving
		if abs(elevator_local_y - last_elevator_y) < 0.001:  # Elevator barely moving
			elevator_stopped_frames += 1
			if elevator_stopped_frames > 5:  # Stopped for several frames
				break
		else:
			elevator_stopped_frames = 0  # Reset counter if still moving

		last_elevator_y = elevator_local_y
		await get_tree().process_frame

	print("[FlightDeckManager] Elevator physically stopped - aircraft gear at final position")

	# Continue directly to catapult positioning since we know elevator has stopped
	print("[FlightDeckManager] Starting catapult positioning sequence")
	await get_tree().create_timer(1.0).timeout
	_complete_retrieval_sequence()

func _complete_retrieval_sequence():
	"""Complete the retrieval by moving aircraft to launch position and restoring physics"""
	print("[FlightDeckManager] Completing retrieval sequence - moving to launch position")

	var aircraft = deck_aircraft
	if not aircraft:
		print("[FlightDeckManager] ERROR: No aircraft found for retrieval completion")
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
		print("[FlightDeckManager] No catapult_latch_marker found, using fallback")

	# Move aircraft smoothly to catapult position while maintaining lift height
	print("[FlightDeckManager] Moving aircraft to launch position while maintaining 0.2m gear height")

	# Calculate the correct Y position to maintain gear 0.2m above deck during move
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

	# Now lower aircraft down to deck height (final landing)
	print("[FlightDeckManager] Lowering aircraft to deck height for final positioning")

	if not gear_colliders.is_empty():
		# Find lowest gear collider
		var lowest_gear_local_y = INF
		for gear in gear_colliders:
			var local_y = aircraft.to_local(gear.global_position).y
			if local_y < lowest_gear_local_y:
				lowest_gear_local_y = local_y

		# Position aircraft so lowest gear is slightly ABOVE deck level to prevent collision issues
		var target_aircraft_y = deck_height - lowest_gear_local_y + 0.1  # 10cm above deck to prevent clipping
		aircraft.global_position.y = target_aircraft_y
		print("[FlightDeckManager] Aircraft positioned with gear 10cm above deck level to prevent physics collision issues")

	# Wait 1 second after positioning
	await get_tree().create_timer(1.0).timeout

	# Move tractorbots to their staging positions and deactivate
	print("[FlightDeckManager] Moving tractorbots to staging positions")
	_move_tractorbots_to_staging()

	# Wait for tractorbots to reach staging positions
	await get_tree().create_timer(2.0).timeout

	# Restore physics
	_restore_aircraft_physics(aircraft)

	# Set state back to idle
	current_state = DeckState.IDLE
	print("[FlightDeckManager] Retrieval sequence complete - aircraft ready for launch")

func _move_aircraft_horizontally(aircraft: RigidBody3D, target_position: Vector3):
	"""Move aircraft horizontally to target position with tractorbots following"""
	var start_position = aircraft.global_position
	var start_rotation = aircraft.global_rotation
	var target_rotation = aircraft.global_rotation  # Keep same rotation

	# Get initial tractorbot offsets from aircraft
	var bot_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot.is_active:
			bot_offsets.append(bot.global_position - aircraft.global_position)
		else:
			bot_offsets.append(Vector3.ZERO)

	var distance = start_position.distance_to(target_position)
	var duration = distance / _aircraft_move_speed

	print("[FlightDeckManager] Moving aircraft horizontally with tractorbots - Distance: ", distance, " Duration: ", duration)
	print("[FlightDeckManager] From: ", start_position, " To: ", target_position)

	# Use a proper timer for smooth movement
	var elapsed_time = 0.0

	# Smooth movement with rotation
	while aircraft.global_position.distance_to(target_position) > 0.1:
		elapsed_time += get_process_delta_time()

		if elapsed_time >= duration:
			break

		var t = elapsed_time / duration
		t = ease_in_out_cubic(t)  # Smooth easing

		# Interpolate aircraft position
		var current_position = start_position.lerp(target_position, t)
		aircraft.global_position = current_position

		# Move tractorbots to maintain relative positions
		for i in range(min(tractor_bots.size(), bot_offsets.size())):
			var bot = tractor_bots[i]
			if bot and bot.is_active:
				bot.global_position = aircraft.global_position + bot_offsets[i]

		# Interpolate rotation
		aircraft.global_rotation = start_rotation.slerp(target_rotation, t)

		await get_tree().process_frame

	# Final position
	aircraft.global_position = target_position
	aircraft.global_rotation = target_rotation

	# Final tractorbot positions
	for i in range(min(tractor_bots.size(), bot_offsets.size())):
		var bot = tractor_bots[i]
		if bot and bot.is_active:
			bot.global_position = aircraft.global_position + bot_offsets[i]

	print("[FlightDeckManager] Aircraft horizontal movement complete with tractorbots")

func _position_aircraft_gear_above_deck(aircraft: RigidBody3D):
	"""Position aircraft so gear colliders are exactly 0.2m above deck level"""
	var gear_colliders = _find_gear_colliders(aircraft)
	var deck_height = _get_deck_height_y()
	var target_gear_height = deck_height + _aircraft_lift_height  # deck + 0.2m

	if gear_colliders.is_empty():
		print("[FlightDeckManager] No gear colliders found for final positioning")
		# Fallback - position aircraft center at deck + 0.2m
		aircraft.global_position.y = target_gear_height
		return

	# Find the lowest gear collider
	var lowest_gear_y = INF
	for gear in gear_colliders:
		if gear.global_position.y < lowest_gear_y:
			lowest_gear_y = gear.global_position.y

	# Calculate how much to adjust aircraft Y position to get lowest gear at target height
	var y_adjustment = target_gear_height - lowest_gear_y

	print("[FlightDeckManager] Final positioning - Deck: ", deck_height, " Target gear: ", target_gear_height, " Current lowest gear: ", lowest_gear_y, " Adjustment: ", y_adjustment)

	# Apply the adjustment to aircraft position
	aircraft.global_position.y += y_adjustment

	print("[FlightDeckManager] Aircraft positioned - gear now at: ", target_gear_height)

func _move_tractorbots_to_staging():
	"""Move tractorbots to their staging positions and deactivate them"""
	print("[FlightDeckManager] Moving tractorbots to staging positions")

	for i in range(tractor_bots.size()):
		var bot = tractor_bots[i]
		if bot:
			print("[FlightDeckManager] Moving tractorbot ", i, " to staging")

			# First deactivate them
			if bot.has_method("deactivate"):
				bot.deactivate()
				print("[FlightDeckManager] Deactivated bot ", i)

			# Then physically move them away from aircraft to staging area
			# Move them to a position away from the aircraft
			var staging_offset = Vector3(20.0 + i * 5.0, 0, -10.0)  # Spread them out
			var staging_position = elevator_pickup_marker.global_position + staging_offset
			staging_position.y = _get_deck_height_y()  # Put them on deck level

			bot.global_position = staging_position
			print("[FlightDeckManager] Moved bot ", i, " to staging at: ", staging_position)

func ease_in_out_cubic(t: float) -> float:
	"""Smooth easing function"""
	return 3.0 * t * t - 2.0 * t * t * t
