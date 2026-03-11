extends Node

## Global Flight Director
## Manages spectating, player control swapping, and tracking all active aircraft.
##
## Controls:
##   LB / RB           — cycle target: Bridge → Friendly aircraft → Enemy aircraft
##   Y (switch_camera) — cycle cockpit / chase / cinematic for the viewed aircraft
##   Start             — toggle AI on/off for the viewed aircraft

# ---------------------------------------------------------------------------
# Category / target state
# ---------------------------------------------------------------------------

enum Category { BRIDGE, FRIENDLY, ENEMY }

var current_category: Category = Category.BRIDGE
var friendly_index: int = 0
var enemy_index: int = 0

## 0 = COCKPIT, 1 = CHASE, 2 = CINEMATIC (maps to CameraController.CameraMode)
var aircraft_cam_mode: int = 0

## The CameraController we last handed control to (used for Y-button view cycling)
var active_controller_camera_system: Node = null

## The aircraft currently being viewed (null when on Bridge)
var current_viewed_aircraft: RigidBody3D = null

## Whether the player has taken manual control of an aircraft
var is_player_controlling: bool = false
var player_controlled_plane: RigidBody3D = null

# ---------------------------------------------------------------------------
# Legacy — kept so AIToggle.register_aircraft still compiles
# ---------------------------------------------------------------------------
var active_aircraft: Array[RigidBody3D] = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Start on bridge after the scene is fully ready
	call_deferred("_initial_view")

func _initial_view():
	_activate_view()

# ---------------------------------------------------------------------------
# Legacy registration (AIToggle calls these)
# ---------------------------------------------------------------------------

func register_aircraft(ac: RigidBody3D):
	if ac not in active_aircraft:
		active_aircraft.append(ac)
		if not ac.is_connected("destroyed", Callable(self, "_on_aircraft_destroyed").bind(ac)):
			ac.connect("destroyed", Callable(self, "_on_aircraft_destroyed").bind(ac))

func unregister_aircraft(ac: RigidBody3D):
	active_aircraft.erase(ac)
	if ac == player_controlled_plane:
		is_player_controlling = false
		player_controlled_plane = null
	if ac == current_viewed_aircraft:
		current_viewed_aircraft = null
		_activate_view()

func _on_aircraft_destroyed(ac: RigidBody3D):
	unregister_aircraft(ac)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(_event):
	# Shoulder buttons: cycle target — but only when NOT actively flying
	if not is_player_controlling:
		if Input.is_action_just_pressed("spectate_next"):
			cycle_target(1)
		elif Input.is_action_just_pressed("spectate_prev"):
			cycle_target(-1)

	# Y: cycle camera view for current aircraft (no-op on bridge)
	if Input.is_action_just_pressed("switch_camera"):
		_cycle_aircraft_view()

	# Start: toggle AI for current aircraft (no-op on bridge)
	if Input.is_action_just_pressed("toggle_player_control"):
		toggle_player_control()

# ---------------------------------------------------------------------------
# Category / index helpers
# ---------------------------------------------------------------------------

func _get_friendly_aircraft() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("friendlies"):
		if node is RigidBody3D and is_instance_valid(node) and _node_has_cameras(node):
			result.append(node)
	return result

func _get_enemy_aircraft() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is RigidBody3D and is_instance_valid(node) and _node_has_cameras(node):
			result.append(node)
	return result

func _node_has_cameras(node: Node) -> bool:
	## True if the node looks like an aircraft with spectatable cameras.
	return node.get_node_or_null("CameraChase") != null \
		or node.get_node_or_null("CameraCockpit") != null \
		or node.find_child("CameraController", true, false) != null

func _has_bridge_camera() -> bool:
	return get_tree().get_nodes_in_group("carrier_cam").size() > 0

# ---------------------------------------------------------------------------
# Main cycle logic
# ---------------------------------------------------------------------------

## Advance or retreat through Bridge → Friendly[0..n] → Enemy[0..n] → Bridge …
func cycle_target(direction: int):
	var friendlies := _get_friendly_aircraft()
	var enemies    := _get_enemy_aircraft()
	var has_bridge := _has_bridge_camera()

	# Build a flat ordered list of (category, index) slots
	# so we can do simple +1/-1 arithmetic.
	var slots: Array = []
	if has_bridge:
		slots.append({"cat": Category.BRIDGE, "idx": -1})
	for i in range(friendlies.size()):
		slots.append({"cat": Category.FRIENDLY, "idx": i})
	for i in range(enemies.size()):
		slots.append({"cat": Category.ENEMY, "idx": i})

	if slots.is_empty():
		return

	# Find our current slot
	var cur := 0
	for i in range(slots.size()):
		var s = slots[i]
		if s.cat == current_category:
			if s.cat == Category.BRIDGE:
				cur = i
				break
			elif s.cat == Category.FRIENDLY and s.idx == friendly_index:
				cur = i
				break
			elif s.cat == Category.ENEMY and s.idx == enemy_index:
				cur = i
				break

	cur = (cur + direction + slots.size()) % slots.size()
	var next = slots[cur]

	current_category = next.cat
	match current_category:
		Category.FRIENDLY:
			# clamp in case count shrank
			friendly_index = clampi(next.idx, 0, friendlies.size() - 1)
		Category.ENEMY:
			enemy_index = clampi(next.idx, 0, enemies.size() - 1)

	# Reset to cockpit when switching aircraft targets
	aircraft_cam_mode = 0
	_activate_view()

# ---------------------------------------------------------------------------
# Camera view cycling (Y button)
# ---------------------------------------------------------------------------

func _cycle_aircraft_view():
	if current_category == Category.BRIDGE:
		return  # Y does nothing on bridge
	aircraft_cam_mode = (aircraft_cam_mode + 1) % 3
	_activate_view()

# ---------------------------------------------------------------------------
# Activate the current view target
# ---------------------------------------------------------------------------

func _activate_view():
	var cc := _get_player_camera_controller()

	match current_category:
		Category.BRIDGE:
			current_viewed_aircraft = null
			if cc and cc.has_method("switch_to_camera"):
				# CameraController.CameraMode.BRIDGE == 3
				cc.switch_to_camera(3)
				active_controller_camera_system = cc

		Category.FRIENDLY:
			var friendlies := _get_friendly_aircraft()
			if friendlies.is_empty():
				# Fall back to bridge
				current_category = Category.BRIDGE
				_activate_view()
				return
			friendly_index = clampi(friendly_index, 0, friendlies.size() - 1)
			var ac := friendlies[friendly_index] as RigidBody3D
			_view_aircraft(ac)

		Category.ENEMY:
			var enemies := _get_enemy_aircraft()
			if enemies.is_empty():
				current_category = Category.BRIDGE
				_activate_view()
				return
			enemy_index = clampi(enemy_index, 0, enemies.size() - 1)
			var ac := enemies[enemy_index] as RigidBody3D
			_view_aircraft(ac)

## Route the camera to a specific aircraft at the current cam mode.
func _view_aircraft(ac: RigidBody3D):
	current_viewed_aircraft = ac

	# FlightDeckManager disables HeadsUpDisplay and InstrumentPanel on AI aircraft.
	# Re-enable them so the player can see instruments while spectating.
	for node_name in ["HeadsUpDisplay", "InstrumentPanel"]:
		var node := ac.find_child(node_name, true, false) as Node
		if node:
			node.set_process(true)
			node.set_physics_process(true)
			if node is Node3D:
				(node as Node3D).show()

	# Try to find a CameraController on the aircraft itself
	var ac_cc := ac.find_child("CameraController", true, false) as Node
	if ac_cc and ac_cc.has_method("switch_to_camera"):
		ac_cc.switch_to_camera(aircraft_cam_mode)
		active_controller_camera_system = ac_cc
		return

	# Fall back: use the player's CameraController and ask it to aim at this aircraft.
	# This works for AI planes that share the same tripod cameras.
	var player_cc := _get_player_camera_controller()
	if player_cc and player_cc.has_method("switch_to_aircraft_and_mode"):
		player_cc.switch_to_aircraft_and_mode(ac, aircraft_cam_mode)
		active_controller_camera_system = player_cc
	elif player_cc and player_cc.has_method("switch_to_camera"):
		player_cc.switch_to_camera(aircraft_cam_mode)
		active_controller_camera_system = player_cc


## Find whichever CameraController is on the player's own aircraft (first in group).
func _get_player_camera_controller() -> Node:
	var ccs := get_tree().get_nodes_in_group("camera_controller")
	if ccs.size() > 0:
		return ccs[0]
	return null

# ---------------------------------------------------------------------------
# Start button: toggle AI / player control for current aircraft
# ---------------------------------------------------------------------------

func toggle_player_control():
	if current_category == Category.BRIDGE:
		return  # No aircraft to control from bridge

	if is_player_controlling:
		# Return control to AI on the plane we took over
		if is_instance_valid(player_controlled_plane):
			var ai_toggle = player_controlled_plane.get_node_or_null("AIToggle")
			if ai_toggle and ai_toggle.has_method("enable_ai"):
				ai_toggle.enable_ai()
			print("[FlightDirector] Returned control to AI: ", player_controlled_plane.name)
		is_player_controlling = false
		player_controlled_plane = null
	else:
		# Take control of the currently viewed aircraft
		if not is_instance_valid(current_viewed_aircraft):
			return
		var ai_toggle = current_viewed_aircraft.get_node_or_null("AIToggle")
		if ai_toggle and ai_toggle.has_method("disable_ai"):
			ai_toggle.disable_ai()
		is_player_controlling = true
		player_controlled_plane = current_viewed_aircraft
		print("[FlightDirector] Player took control of: ", current_viewed_aircraft.name)
		# Switch to cockpit whenever player takes control
		aircraft_cam_mode = 0
		_activate_view()
