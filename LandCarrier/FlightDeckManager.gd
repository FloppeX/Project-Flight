extends Node
class_name FlightDeckManager

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

signal deck_state_changed(new_state)

@export var catapult: Node
@export var tractor_bot: Node
@export var elevator_pickup_marker: Node3D
@export var elevator: Node
@export var deck_marker: Node3D  # Marker on deck to derive deck world height
@export var tractor_bots: Array[Node] = []  # Array of SimpleTractorBot nodes
@export var hangar_spawn_points: Array[Vector3] = [
	Vector3(-8, 0, 0),
	Vector3(-4, 0, 0), 
	Vector3(0, 0, 0),
	Vector3(4, 0, 0),
	Vector3(8, 0, 0),
	Vector3(12, 0, 0)
]
@export var max_hangar_capacity: int = 12
@export var aircraft_template_scene: PackedScene  # Default aircraft template (Aircraft 5)
@export var aircraft_2_scene: PackedScene         # Aircraft 2 template
@export var aircraft_7_scene: PackedScene         # Aircraft 7 template
@export var aircraft_8_scene: PackedScene         # Aircraft 8 template
@export var aircraft_9_scene: PackedScene         # Rescue helicopter placeholder template
@export var aircraft_10_scene: PackedScene        # Scout helicopter template
@export var aircraft_11_scene: PackedScene        # Utility helicopter template
@export var carrier_manager_path: NodePath = NodePath("../CarrierManager")
@export var auto_recovery_enabled: bool = true
@export var auto_recovery_speed_threshold_mps: float = 1.5
@export var auto_recovery_zone_half_width_m: float = 22.0
@export var auto_recovery_zone_min_local_z: float = -90.0
@export var auto_recovery_zone_max_local_z: float = -15.0
@export var auto_recovery_zone_height_margin_m: float = 6.0
@export var launch_deck_pitch_contact_max_deg: float = 4.0
@export var desired_deck_tractor_count: int = 4
@export var landing_deck_block_half_width_m: float = 24.0
@export var landing_deck_block_min_local_z: float = -95.0
@export var landing_deck_block_max_local_z: float = 95.0
@export var landing_deck_block_height_margin_m: float = 8.0
@export var landing_blocker_cleanup_enabled: bool = true
@export var landing_blocker_cleanup_timeout_s: float = 35.0
@export var landing_blocker_cleanup_speed_threshold_mps: float = 2.5
@export var landing_blocker_cleanup_deck_contact_margin_m: float = 1.0
@export var landing_clearance_abandon_radius_m: float = 6000.0
@export var landing_clearance_timeout_s: float = 30.0
@export var landing_clearance_retry_cooldown_s: float = 12.0
@export var carrier_recovery_speed_limit_mps: float = 0.0
@export var carrier_recovery_constraint_requires_active_clearance: bool = true
@export var tractor_recovery_debug: bool = true
@export var tractor_recovery_debug_interval_s: float = 1.0
@export var tractor_position_timeout_s: float = 16.0
@export var tractor_elevator_floor_offset_m: float = 0.0
@export var tractor_elevator_align_duration_s: float = 1.2

const DEFAULT_AIRCRAFT_SCENE_PATH := "res://Aircraft/Aircraft_5.tscn"
const LOADOUT_CAP := "cap"
const LOADOUT_INTERCEPT := "intercept"
const LOADOUT_STRIKE := "strike"
const WEAPON_SCENE_20MM := "res://Weapons/Guns/Hardpoint/20mm_autocannon_hardpoint.tscn"
const WEAPON_SCENE_AA_MISSILE := "res://Weapons/AA_Missile/aa_missile_launcher.tscn"
const WEAPON_SCENE_ROCKET_POD := "res://Weapons/RocketPod/rocket_pod.tscn"
const WEAPON_SCENE_BOMB_RACK := "res://Weapons/Bomb/bomb_rack.tscn"
const PRIMARY_TRACTOR_COUNT := 4
const MOTION_REFERENCE_NODE_META := "motion_reference_node"
const MOTION_REFERENCE_VELOCITY_META := "motion_reference_velocity"
const LEGACY_CARRIER_VELOCITY_META := "carrier_deck_velocity"
const MANUAL_TRANSPORT_META := "carrier_manual_transport"

enum DeckState {
	IDLE,
	AIRCRAFT_ON_DECK,
	LAUNCH_IN_PROGRESS,
	RECOVERY_IN_PROGRESS,
	STORING_IN_HANGAR,
	RETRIEVING_FROM_HANGAR,
	TRACTOR_CLEANUP
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
var _aircraft_move_speed: float = 7.0  # Speed to move aircraft around deck
var _tractor_staging_speed: float = 18.0  # Bot retreat speed to staging (m/s)
var _retrieval_spawn_settle_s: float = 0.15
var _flight_deck_local_offset_y: float = 0.5  # Fallback local offset if no marker
var _aircraft_original_collision_layer: int = 0
var _aircraft_original_collision_mask: int = 0
var _retrieval_top_handled: bool = false
var _recovery_job_dispatched: bool = false
var _tractor_cleanup_in_progress: bool = false
var _tractor_cleanup_batch: Array[Node3D] = []
var _tractor_cleanup_move_speed: float = 5.0
var _tractor_elevator_transfer_in_progress: bool = false
var _tractorbots_in_hangar: bool = false
var landing_deck_active: bool = false
var _landing_clearance_aircraft: RigidBody3D = null
var _landing_clearance_queue: Array[RigidBody3D] = []
var _landing_clearance_elapsed_s: float = 0.0
var _landing_clearance_retry_after_s: Dictionary = {}
var _landing_blocker_aircraft: RigidBody3D = null
var _landing_blocker_elapsed_s: float = 0.0
var _landing_blocker_cleanup_dispatched: bool = false
var carrier_manager: CarrierManager = null

# --- Landing test mode ---
var _landing_test_active: bool = false
var _landing_test_timer: float = 0.0
var _landing_test_aircraft: Array[RigidBody3D] = []
var _landing_test_spawn_index: int = 0
var _recovery_debug_spawn_index: int = 0
var _retrieval_sequence: int = 0
const LANDING_TEST_INTERVAL_S: float = 20.0
const LANDING_TEST_SPAWN_DIST_M: float = 2000.0
const LANDING_TEST_ALTITUDE_M: float = 140.0  # above carrier deck
const LANDING_TEST_SPEED_MPS: float = 70.0
const RECOVERY_DEBUG_SPAWN_DIST_M: float = 1000.0
const RECOVERY_DEBUG_ALTITUDE_M: float = 100.0
const LANDING_WIRE_HALF_WIDTH_M: float = 24.8  # ±24.8 m = full wire width

# --- Helicopter test mode (F12) ---
@export var start_in_heli_test_mode: bool = false
var _heli_test_active: bool = false
var _heli_test_timer: float = 0.0
var _heli_test_spawn_index: int = 0
const HELI_TEST_INTERVAL_S: float = 30.0
const HELI_TEST_MAX_COUNT: int = 5
const HELI_TEST_SPAWN_DIST_M: float = 200.0
const HELI_TEST_ALTITUDE_M: float = 40.0

var _landing_score_total: float = 0.0
var _landing_attempt_count: int = 0

# --- HELI TEST UI STATS ---
var _heli_test_stats: Dictionary = {
	"Aircraft_9": {"spawned": 0, "lz": 0, "carrier": 0, "crash": 0},
	"Aircraft_10": {"spawned": 0, "lz": 0, "carrier": 0, "crash": 0},
	"Aircraft_11": {"spawned": 0, "lz": 0, "carrier": 0, "crash": 0},
}
var _heli_test_start_time_msec: int = 0
var _heli_ui_canvas: CanvasLayer = null
var _heli_ui_label: Label = null

func _landing_test_outcome_type(outcome: String) -> String:
	match outcome:
		"CAUGHT":
			return "CATCH"
		"BOLTER", "WAVE-OFF":
			return "GO-AROUND"
		"CRASH", "DESTROYED":
			return "CRASH"
		"STRAY":
			return "STRAY"
		_:
			return "OTHER"

func record_landing_test_outcome(aircraft_variant: Variant, outcome: String, points: float = 0.0) -> bool:
	if not is_instance_valid(aircraft_variant):
		return false
	var aircraft := aircraft_variant as RigidBody3D
	if not is_instance_valid(aircraft):
		return false
	var terminal_outcome: bool = outcome in ["CAUGHT", "BOLTER", "WAVE-OFF", "CRASH", "DESTROYED", "STRAY"]
	if terminal_outcome:
		release_landing_clearance(aircraft)
	if not _landing_test_aircraft.has(aircraft):
		return false
	if aircraft.has_meta("landing_test_score_recorded") and bool(aircraft.get_meta("landing_test_score_recorded")):
		if terminal_outcome:
			_release_landing_test_aircraft(aircraft, 0.2)
		return false
	aircraft.set_meta("landing_test_score_recorded", true)
	_landing_score_total += points
	_landing_attempt_count += 1
	var avg: float = _landing_score_total / maxf(float(_landing_attempt_count), 1.0)
	var outcome_type: String = _landing_test_outcome_type(outcome)
	print("[LAND] AVG  %.2f pts  n=%d  last=%s %.1f pts  type=%s" % [
		avg,
		_landing_attempt_count,
		outcome,
		points,
		outcome_type
	])
	if terminal_outcome:
		var release_delay: float = 1.5 if outcome == "CAUGHT" else 0.2
		_release_landing_test_aircraft(aircraft, release_delay)
	return true

func _release_landing_test_aircraft(aircraft: RigidBody3D, delay_s: float = 0.2) -> void:
	_landing_test_aircraft.erase(aircraft)
	if not is_instance_valid(aircraft):
		return
	if delay_s <= 0.0:
		aircraft.queue_free()
		return
	get_tree().create_timer(delay_s).timeout.connect(func():
		if is_instance_valid(aircraft):
			aircraft.queue_free()
	)

# FlightOps AI-launch queue
var _ai_launch_queue: int = 0          # Aircraft still to retrieve+launch for FlightOps
var _pending_flight_ops: Node = null   # Node waiting for notify_aircraft_launched() callbacks (FlightDirector)
var _retrieval_ai_land_after_launch: bool = true
var _pending_ai_loadout_profile: String = ""

func _deck_state_name(state: int = -1) -> String:
	var resolved_state := current_state if state == -1 else state
	match resolved_state:
		DeckState.IDLE:
			return "IDLE"
		DeckState.AIRCRAFT_ON_DECK:
			return "AIRCRAFT_ON_DECK"
		DeckState.LAUNCH_IN_PROGRESS:
			return "LAUNCH_IN_PROGRESS"
		DeckState.RECOVERY_IN_PROGRESS:
			return "RECOVERY_IN_PROGRESS"
		DeckState.STORING_IN_HANGAR:
			return "STORING_IN_HANGAR"
		DeckState.RETRIEVING_FROM_HANGAR:
			return "RETRIEVING_FROM_HANGAR"
		DeckState.TRACTOR_CLEANUP:
			return "TRACTOR_CLEANUP"
		_:
			return "UNKNOWN"

func _aircraft_debug_name(aircraft: Variant) -> String:
	if not is_instance_valid(aircraft):
		return "none"
	var node := aircraft as Node
	return node.name if is_instance_valid(node) else "none"

func _fmt_vec3(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]

func _recovery_debug(message: String) -> void:
	if not tractor_recovery_debug:
		return
	print("[FlightDeck RECOVERY] state=%s aircraft=%s pending=%s dispatched=%s bots_hangar=%s %s" % [
		_deck_state_name(),
		_aircraft_debug_name(deck_aircraft),
		_aircraft_debug_name(_pending_store_aircraft),
		str(_recovery_job_dispatched),
		str(_tractorbots_in_hangar),
		message
	])

func _ready():
	if not aircraft_template_scene:
		aircraft_template_scene = load(DEFAULT_AIRCRAFT_SCENE_PATH) as PackedScene
	_normalize_primary_tractorbots()
	_place_primary_tractorbots_at_staging_start()
	_resolve_carrier_manager()
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

	if start_in_heli_test_mode:
		_toggle_heli_test_mode()


func _on_node_added(node: Node) -> void:
	if node.is_in_group("arresting_cable"):
		_connect_cable_signals(node)

func _connect_cable_signals(cable: Node) -> void:
	if cable.has_signal("cable_engaged") and not cable.cable_engaged.is_connected(_on_cable_engaged):
		cable.cable_engaged.connect(_on_cable_engaged)
	if cable.has_signal("cable_released") and not cable.cable_released.is_connected(_on_cable_released):
		cable.cable_released.connect(_on_cable_released)

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

func _resolve_carrier_manager() -> void:
	if is_instance_valid(carrier_manager):
		return
	if carrier_manager_path != NodePath():
		var configured_node := get_node_or_null(carrier_manager_path)
		if configured_node is CarrierManager:
			carrier_manager = configured_node as CarrierManager
	if not is_instance_valid(carrier_manager):
		var parent := get_parent()
		if parent:
			var sibling := parent.get_node_or_null("CarrierManager")
			if sibling is CarrierManager:
				carrier_manager = sibling as CarrierManager
	if is_instance_valid(carrier_manager):
		carrier_manager.ensure_initialized()
	else:
		push_warning("[FlightDeckManager] CarrierManager not found. Aircraft pilot assignment is unavailable.")

func _get_primary_tractor_bots() -> Array[Node3D]:
	var primary: Array[Node3D] = []
	var seen: Dictionary = {}
	for bot_variant in tractor_bots:
		if not is_instance_valid(bot_variant) or not (bot_variant is Node3D):
			continue
		var bot := bot_variant as Node3D
		var id := bot.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		primary.append(bot)
		if primary.size() >= PRIMARY_TRACTOR_COUNT:
			break
	return primary

func _normalize_primary_tractorbots() -> void:
	var primary := _get_primary_tractor_bots()
	tractor_bots.clear()
	for bot in primary:
		tractor_bots.append(bot)
	desired_deck_tractor_count = PRIMARY_TRACTOR_COUNT
	var primary_lookup: Dictionary = {}
	for bot in primary:
		primary_lookup[bot.get_instance_id()] = true
	for node in _get_all_tractor_nodes():
		if primary_lookup.has(node.get_instance_id()):
			continue
		node.queue_free()
	if primary.size() < PRIMARY_TRACTOR_COUNT:
		push_warning("[FlightDeckManager] Expected %d tractorbots, found %d." % [PRIMARY_TRACTOR_COUNT, primary.size()])

func _get_primary_staging_slots_local(count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var deck_local_y: float = _get_deck_local_y()
	var slot_offsets: Array[Vector3] = [
		Vector3(10.0, 0.0, -6.0),
		Vector3(14.0, 0.0, -6.0),
		Vector3(18.0, 0.0, -6.0),
		Vector3(22.0, 0.0, -6.0)
	]
	var base_local: Vector3 = elevator_pickup_marker.position if is_instance_valid(elevator_pickup_marker) else Vector3.ZERO
	for i in range(min(count, slot_offsets.size())):
		var slot_local: Vector3 = base_local + slot_offsets[i]
		slot_local.y = deck_local_y
		slots.append(slot_local)
	return slots

func _place_primary_tractorbots_at_staging_start() -> void:
	var primary := _get_primary_tractor_bots()
	if primary.is_empty():
		return

	var starts_on_bottom_elevator := _is_elevator_physically_at_bottom()
	var slots := _get_primary_staging_slots_local(primary.size())
	if starts_on_bottom_elevator:
		var bottom_slot_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
		slots = _get_primary_elevator_slots_local(primary.size(), bottom_slot_y)

	for i in range(min(primary.size(), slots.size())):
		var bot := primary[i]
		_set_cleanup_idle_for_tractor_bot(bot)
		bot.position = slots[i]

	_tractorbots_in_hangar = starts_on_bottom_elevator
	_tractor_elevator_transfer_in_progress = false

func _ensure_pilot_assigned_for_data(aircraft_data: Dictionary) -> bool:
	_resolve_carrier_manager()
	if not is_instance_valid(carrier_manager):
		return false
	return carrier_manager.ensure_aircraft_data_has_pilot(aircraft_data)

func _make_stored_aircraft_entry(aircraft_name: String, scene: PackedScene, scene_file: String = "") -> Dictionary:
	var resolved_scene_file := scene_file
	if resolved_scene_file == "" and scene != null:
		resolved_scene_file = scene.resource_path
	var entry := {
		"name": aircraft_name,
		"scene_file": resolved_scene_file,
		"scene": scene,
		"position": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"scale": Vector3.ONE,
		"metadata": {}
	}
	if not _ensure_pilot_assigned_for_data(entry):
		return {}
	return entry

func _queue_aircraft_scene_for_retrieval(aircraft_name: String, scene: PackedScene, scene_file: String = "") -> void:
	if _landing_test_active:
		return
	var entry := _make_stored_aircraft_entry(aircraft_name, scene, scene_file)
	if entry.is_empty():
		return
	stored_aircraft.push_front(entry)
	if _heli_test_active:
		_log_heli_test("retrieval queued state=%s stored=%d elevator_top=%s bottom=%s" % [
			_deck_state_name(),
			stored_aircraft.size(),
			str(_is_elevator_physically_at_top()),
			str(elevator != null and "current_state" in elevator and elevator.current_state == elevator.ElevatorState.AT_BOTTOM),
		])
	start_hangar_retrieval()

func _is_elevator_physically_at_top() -> bool:
	if not elevator:
		return false
	if not ("platform_size" in elevator):
		return false
	var platform_local_y := _get_elevator_platform_local_y(INF)
	if platform_local_y == INF:
		return false
	var top_y = -float(elevator.platform_size.y) * 0.5
	return abs(platform_local_y - top_y) <= 0.15

func _is_elevator_physically_at_bottom() -> bool:
	if not elevator:
		return false
	if not ("shaft_depth" in elevator):
		return false
	var platform_local_y := _get_elevator_platform_local_y(INF)
	if platform_local_y == INF:
		return false
	return abs(platform_local_y + float(elevator.shaft_depth)) <= 0.15

func _get_elevator_platform_local_y(fallback_y: float = -10.0) -> float:
	if not elevator or not ("platform" in elevator):
		return fallback_y
	var platform_node: Variant = elevator.platform
	if not is_instance_valid(platform_node) or not (platform_node is Node3D):
		return fallback_y
	return float((platform_node as Node3D).position.y)

func _get_elevator_platform_top_offset_y() -> float:
	if elevator and "platform_size" in elevator:
		return float(elevator.platform_size.y) * 0.5
	return 0.5

func _get_elevator_platform_top_global_y(fallback_platform_local_y: float = -10.0) -> float:
	return _get_deck_height_y() + _get_elevator_platform_local_y(fallback_platform_local_y) + _get_elevator_platform_top_offset_y()

func _get_elevator_platform_top_local_y(fallback_platform_local_y: float = -10.0) -> float:
	return _get_deck_local_y() + _get_elevator_platform_local_y(fallback_platform_local_y) + _get_elevator_platform_top_offset_y()

func _get_carrier_forward_yaw() -> float:
	var carrier := get_parent() as Node3D
	var forward := Vector3.FORWARD
	if is_instance_valid(carrier):
		forward = carrier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	return atan2(forward.x, forward.z)

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
				pass
		else:
			pass

	# Store last landed aircraft in hangar
	if Input.is_action_just_pressed("store_aircraft"):
		if _pending_store_aircraft and current_state == DeckState.IDLE:
			start_hangar_storage(_pending_store_aircraft)
		else:
			pass

	# Retrieve aircraft from hangar (key "1" or retrieve_aircraft action)
	if Input.is_action_just_pressed("retrieve_aircraft") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_1):
		if current_state == DeckState.IDLE and not stored_aircraft.is_empty():
			start_hangar_retrieval()
		else:
			if current_state != DeckState.IDLE:
				pass
			if stored_aircraft.is_empty():
				pass

	# Spawn Aircraft 2 from hangar (key "2")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_2:
		if current_state == DeckState.IDLE:
			var scene := aircraft_2_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_2.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_2", scene)
			else:
				pass
		else:
			pass

	# Spawn Aircraft 5 from hangar (key "5")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_5:
		if current_state == DeckState.IDLE:
			var scene: PackedScene = load(DEFAULT_AIRCRAFT_SCENE_PATH)
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_5", scene, DEFAULT_AIRCRAFT_SCENE_PATH)

	# Spawn Aircraft 7 from hangar (key "7")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_7:
		if current_state == DeckState.IDLE:
			var scene := aircraft_7_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_7.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_7", scene)

	# Spawn Aircraft 8 from hangar (key "8")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_8:
		if current_state == DeckState.IDLE:
			var scene := aircraft_8_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_8.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_8", scene)

	# Spawn Aircraft 9 rescue helicopter from hangar (key "9")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_9:
		if current_state == DeckState.IDLE:
			var scene := aircraft_9_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_9.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_9", scene)

	# Spawn Aircraft 10 scout helicopter from hangar (key "0")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_0:
		if current_state == DeckState.IDLE:
			var scene := aircraft_10_scene
			if not scene:
				scene = load("res://Aircraft/Aircraft_10.tscn")
			if scene:
				_queue_aircraft_scene_for_retrieval("Aircraft_10", scene)

	# Debug key to force reset state (F9)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		current_state = DeckState.IDLE
		_pending_store_aircraft = null
		_landing_clearance_aircraft = null
		_landing_clearance_queue.clear()

	# F1 — toggle landing test mode
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_landing_test_active = not _landing_test_active
		_landing_test_timer = 0.0  # Spawn first aircraft immediately
		print("[LandingTest] mode %s" % ("ON" if _landing_test_active else "OFF"))
		if _landing_test_active:
			_enter_landing_test_isolation()
		else:
			for ac in _landing_test_aircraft:
				if is_instance_valid(ac):
					ac.queue_free()
			_landing_test_aircraft.clear()
			_landing_clearance_aircraft = null
			_landing_clearance_queue.clear()
			_landing_test_spawn_index = 0
			_landing_score_total = 0.0
			_landing_attempt_count = 0

	# F2 - spawn one normal recovery-test aircraft on straight-in landing.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_spawn_recovery_debug_aircraft()

	# F3 - command closest eligible airborne AI aircraft to return via recovery framework.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_command_closest_aircraft_to_return_to_base()

	# F11 - toggle helicopter test mode: despawn all non-helicopters, spawn one heli/minute up to 4.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		_toggle_heli_test_mode()

func request_launch_sequence(aircraft: RigidBody3D):
	if not is_instance_valid(aircraft):
		_recovery_debug("launch request ignored: invalid aircraft")
		return
	if _is_non_aircraft_body(aircraft):
		_recovery_debug("launch request ignored for non-aircraft body %s" % _aircraft_debug_name(aircraft))
		return
	if _landing_test_active and not _landing_test_aircraft.has(aircraft):
		return
	if not catapult:
		return

	# Clear parking brake but keep controls_disabled set until catapult latch/release.
	# This prevents AIPilot/ControlEngine from spooling before shuttle connection.
	if aircraft.has_meta("parking_brake"):
		aircraft.remove_meta("parking_brake")

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
		if not is_instance_valid(aircraft):
			_recovery_debug("launch request aborted after restore: aircraft invalid")
			return
		if _is_non_aircraft_body(aircraft):
			_recovery_debug("launch request aborted after restore for non-aircraft body %s" % _aircraft_debug_name(aircraft))
			return

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
				ai_pilot.launch()
	else:
		pass

func _is_non_aircraft_body(node: Node) -> bool:
	if not is_instance_valid(node):
		return true
	return bool(node.get_meta("non_aircraft_body", false)) \
			or bool(node.get_meta("ejected_pilot_camera_target", false)) \
			or node.is_in_group("ejected_pilots")

func queue_ai_flight(count: int, ops: Node, loadout_profile: String = "") -> int:
	"""Request FlightOps to launch `count` AI aircraft one after another.
	Each successful launch calls ops.notify_aircraft_launched(pilot)."""
	if _landing_test_active:
		_ai_launch_queue = 0
		_pending_flight_ops = null
		_retrieval_ai_land_after_launch = true
		_pending_ai_loadout_profile = ""
		return 0
	var available := mini(count, stored_aircraft.size())
	if available <= 0:
		push_warning("[FlightDeckManager] queue_ai_flight: hangar empty")
		return 0
	_ai_launch_queue = available
	_pending_flight_ops = ops
	_retrieval_ai_land_after_launch = false
	_pending_ai_loadout_profile = loadout_profile
	if current_state == DeckState.IDLE:
		_launch_next_queued_ai()
	return available

func _launch_next_queued_ai() -> void:
	if _landing_test_active:
		_ai_launch_queue = 0
		_pending_flight_ops = null
		_retrieval_ai_land_after_launch = true
		_pending_ai_loadout_profile = ""
		return
	if _ai_launch_queue <= 0 or stored_aircraft.is_empty():
		_ai_launch_queue = 0
		_pending_flight_ops = null
		_retrieval_ai_land_after_launch = true
		_pending_ai_loadout_profile = ""
		return
	_ai_launch_queue -= 1
	start_hangar_retrieval()

func _on_catapult_sequence_complete():
	# Notify FlightOps about the aircraft that just launched
	if _pending_flight_ops and is_instance_valid(deck_aircraft):
		var pilot = deck_aircraft.get_node_or_null("AIPilot")
		if pilot and _pending_flight_ops.has_method("notify_aircraft_launched"):
			_pending_flight_ops.notify_aircraft_launched(pilot)

	current_state = DeckState.IDLE
	deck_aircraft = null

	# Continue queued AI launches if more are pending
	if _ai_launch_queue > 0:
		_launch_next_queued_ai()
	elif _pending_flight_ops != null:
		_pending_flight_ops = null
		_retrieval_ai_land_after_launch = true
		_pending_ai_loadout_profile = ""

func _on_catapult_sequence_aborted():
	if is_instance_valid(deck_aircraft):
		if deck_aircraft.has_meta("controls_disabled"):
			deck_aircraft.remove_meta("controls_disabled")
	_return_tractors_to_staging()
	_ai_launch_queue = 0
	_pending_flight_ops = null
	_retrieval_ai_land_after_launch = true
	_pending_ai_loadout_profile = ""
	current_state = DeckState.IDLE
	deck_aircraft = null

# --- Arresting cable integration ---
func _on_cable_engaged(aircraft_variant: Variant) -> void:
	if not is_instance_valid(aircraft_variant):
		_recovery_debug("cable engaged ignored: invalid aircraft")
		return
	var aircraft := aircraft_variant as RigidBody3D
	if not is_instance_valid(aircraft):
		_recovery_debug("cable engaged ignored: non-aircraft node")
		return
	release_landing_clearance(aircraft)
	# Landing test mode: cable catch despawns the test aircraft after a short pause.
	if _landing_test_aircraft.has(aircraft):
		# Score tracking — per-aircraft detail is printed by AIPilot's CAUGHT snap
		var cable: Node = null
		if aircraft.has_meta("arresting_cable"):
			cable = aircraft.get_meta("arresting_cable")
		var wire_num: int = 2
		var lateral_m: float = 0.0
		if cable and cable.has_method("get_wire_number"):
			wire_num = cable.get_wire_number()
		if cable and cable.has_method("get_engage_lateral_m"):
			lateral_m = cable.get_engage_lateral_m()
		var base_pts: float = 10.0 if wire_num == 2 else 5.0
		var lat_factor: float = clamp(1.0 - abs(lateral_m) / LANDING_WIRE_HALF_WIDTH_M, 0.0, 1.0)
		record_landing_test_outcome(aircraft, "CAUGHT", base_pts * lat_factor)
		print("[LandingTest] cable caught — despawning %s" % _aircraft_debug_name(aircraft))
		return

	deck_aircraft = aircraft
	current_state = DeckState.RECOVERY_IN_PROGRESS
	_recovery_powerdown_in_progress = true
	_recovery_release_done = false
	_recovery_job_dispatched = false
	_recovery_debug("cable engaged by %s" % _aircraft_debug_name(aircraft))
	if is_instance_valid(aircraft):
		aircraft.set_meta("controls_disabled", true)
		aircraft.set_meta("arresting_hold_until_manual_release", true)
		_call_power_down_sequence(aircraft)

func _deferred_release_cable(_cable: Node) -> void:
	# no-op now; timing handled by _call_power_down_sequence
	pass

func _on_cable_released(aircraft_variant: Variant) -> void:
	if not is_instance_valid(aircraft_variant):
		_recovery_debug("cable released ignored: invalid aircraft")
		return
	var aircraft := aircraft_variant as RigidBody3D
	if not is_instance_valid(aircraft):
		_recovery_debug("cable released ignored: non-aircraft node")
		return
	_recovery_debug("cable released signal for %s" % _aircraft_debug_name(aircraft))
	var tailhook = _find_tailhook(aircraft)
	if is_instance_valid(tailhook) and tailhook.has_method("stow"):
		tailhook.stow()
	if current_state == DeckState.RECOVERY_IN_PROGRESS and deck_aircraft == aircraft and not _recovery_job_dispatched:
		start_post_arrest_recovery(aircraft)

func _dispatch_recovery_job() -> void:
	"""Move aircraft to elevator using simple movement and visual tractorbots"""
	if not is_instance_valid(deck_aircraft) or not is_instance_valid(elevator_pickup_marker):
		_recovery_debug("cannot dispatch recovery: aircraft_valid=%s pickup_marker_valid=%s" % [
			str(is_instance_valid(deck_aircraft)),
			str(is_instance_valid(elevator_pickup_marker))
		])
		return
	if _recovery_job_dispatched:
		_recovery_debug("recovery dispatch ignored: job already dispatched")
		return
	
	_recovery_job_dispatched = true
	_recovery_debug("dispatch recovery job")
	await _prepare_tractorbots_for_recovery_job()
	if not is_instance_valid(deck_aircraft):
		_recovery_debug("recovery dispatch aborted after tractor prep: aircraft no longer valid")
		return
	_recovery_debug("tractor prep complete; moving aircraft to elevator")
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
	if not is_instance_valid(ac):
		_recovery_powerdown_in_progress = false
		_recovery_release_done = true
		return
	_perform_cable_release(ac)
	_recovery_powerdown_in_progress = false
	_recovery_release_done = true

func _perform_cable_release(ac_variant: Variant) -> void:
	if not is_instance_valid(ac_variant):
		return
	var ac_obj: Object = ac_variant as Object
	if ac_obj == null:
		return
	var ac_node: Node = ac_obj as Node
	if ac_node == null:
		return
	if not (ac_node is RigidBody3D):
		return
	var ac: RigidBody3D = ac_node as RigidBody3D
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
	_stabilize_aircraft_for_recovery_pickup(ac)
	_recovery_debug("manual cable release complete; dispatching tractor recovery")
	_dispatch_recovery_job()
	
	# Set aircraft as pending for storage
	_pending_store_aircraft = ac
	_recovery_debug("pending store aircraft set after cable release")

# --- Fallback polling and safety checks ---
func _physics_process(_delta: float) -> void:
	var _profiler_start: int = FrameProfiler.begin("FlightDeckManager.physics")
	# 1. Safety Check: If an operation is active, verify the aircraft still exists and is on the deck
	if current_state == DeckState.LAUNCH_IN_PROGRESS or current_state == DeckState.RECOVERY_IN_PROGRESS:
		if not is_instance_valid(deck_aircraft):
			_abort_current_sequence()
		else:
			var deck_y = _get_deck_height_y()
			# If aircraft falls 10m below the deck, it fell off
			if deck_aircraft.global_position.y < deck_y - 10.0:
				# Allow the player/AI to fly away if they fell off, but free up the deck state
				if deck_aircraft.has_meta("controls_disabled"):
					deck_aircraft.remove_meta("controls_disabled")
				_abort_current_sequence()

	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	_update_landing_clearance_timeout(_delta)
	var landing_blocker := _find_landing_deck_blocker()
	var deck_blocked_by_aircraft: bool = is_instance_valid(landing_blocker)
	if current_state in [DeckState.IDLE, DeckState.AIRCRAFT_ON_DECK]:
		landing_deck_active = deck_blocked_by_aircraft \
				or is_instance_valid(_landing_clearance_aircraft) \
				or not _landing_clearance_queue.is_empty()
		if deck_blocked_by_aircraft and current_state == DeckState.IDLE:
			current_state = DeckState.AIRCRAFT_ON_DECK
		elif not deck_blocked_by_aircraft and current_state == DeckState.AIRCRAFT_ON_DECK:
			current_state = DeckState.IDLE
	else:
		landing_deck_active = true
	_update_landing_blocker_cleanup(_delta, landing_blocker)
	_grant_next_landing_clearance_if_possible()

	# 2. Polling for unmanaged arrests
	if current_state != DeckState.RECOVERY_IN_PROGRESS and not _recovery_powerdown_in_progress:
		var ac = _find_arrested_aircraft()
		if ac:
			_recovery_debug("polling found arrested aircraft %s" % _aircraft_debug_name(ac))
			_on_cable_engaged(ac)
			FrameProfiler.end("FlightDeckManager.physics", _profiler_start)
			return

	# 3. Fallback for manual player landings that stop in the aft recovery zone
	if auto_recovery_enabled and current_state in [DeckState.IDLE, DeckState.AIRCRAFT_ON_DECK]:
		var recovery_candidate := _find_stopped_aircraft_in_recovery_zone()
		if recovery_candidate and recovery_candidate != _pending_store_aircraft:
			_recovery_debug("auto recovery selected stopped aircraft %s" % _aircraft_debug_name(recovery_candidate))
			start_post_arrest_recovery(recovery_candidate)
			FrameProfiler.end("FlightDeckManager.physics", _profiler_start)
			return

	if current_state == DeckState.IDLE and not _tractor_cleanup_in_progress:
		_maybe_dispatch_extra_tractor_cleanup()

	# Landing test mode: spawn on a fixed cadence; older attempts may still be airborne.
	if _landing_test_active:
		# Despawn test aircraft that have left the landing state and drifted far from the carrier
		var carrier_node_t := get_tree().get_first_node_in_group("carrier") as Node3D
		if is_instance_valid(carrier_node_t):
			var to_despawn: Array[RigidBody3D] = []
			for ac in _landing_test_aircraft:
				if not is_instance_valid(ac):
					to_despawn.append(ac)
					continue
				var pilot = ac.find_child("AIPilot", true, false)
				var in_landing: bool = is_instance_valid(pilot) and \
						pilot.get("current_state") == AIPilot.State.LANDING
				if not in_landing and ac.global_position.distance_to(carrier_node_t.global_position) > 250.0:
					to_despawn.append(ac)
			for ac in to_despawn:
				if is_instance_valid(ac):
					# 0 pts for bolter/wave-off/crash — per-aircraft detail already printed by AIPilot
					record_landing_test_outcome(ac, "STRAY", 0.0)
					print("[LandingTest] despawning stray %s" % ac.name)
				else:
					_landing_test_aircraft.erase(ac)
		_landing_test_timer -= _delta
		if _landing_test_timer <= 0.0:
			_landing_test_timer = LANDING_TEST_INTERVAL_S
			_spawn_landing_test_aircraft()

	if _heli_test_active:
		_heli_test_timer -= _delta
		if _heli_test_timer <= 0.0:
			var live_count := get_tree().get_nodes_in_group("aircraft").filter(
				func(n): return is_instance_valid(n) and _is_helicopter_aircraft(n as RigidBody3D if n is RigidBody3D else null)
			).size()
			var is_deck_free := current_state == DeckState.IDLE and _landing_clearance_queue.is_empty() and not is_instance_valid(_landing_clearance_aircraft)
			if is_deck_free:
				if not stored_aircraft.is_empty():
					_log_heli_test("retrieving stored aircraft from hangar instead of spawning new")
					start_hangar_retrieval()
					_heli_test_timer = HELI_TEST_INTERVAL_S
				elif live_count < HELI_TEST_MAX_COUNT:
					_spawn_heli_test_aircraft()
					_heli_test_timer = HELI_TEST_INTERVAL_S
				else:
					_heli_test_timer = HELI_TEST_INTERVAL_S
					_log_heli_test("at max count (%d), skipping spawn" % HELI_TEST_MAX_COUNT)
				
		if is_instance_valid(_heli_ui_label):
			var elapsed_s := (Time.get_ticks_msec() - _heli_test_start_time_msec) / 1000
			var text := "HELI TEST MODE\nRuntime: %02d:%02d:%02d\n\n" % [elapsed_s / 3600, (elapsed_s / 60) % 60, elapsed_s % 60]
			text += "%-12s | %-7s | %-2s | %-7s | %-5s\n" % ["AIRCRAFT", "SPAWNED", "LZ", "CARRIER", "CRASH"]
			text += "------------------------------------------------\n"
			for key in ["Aircraft_9", "Aircraft_10", "Aircraft_11"]:
				var st: Dictionary = _heli_test_stats[key]
				text += "%-12s | %7d | %2d | %7d | %5d\n" % [key, st["spawned"], st["lz"], st["carrier"], st["crash"]]
			_heli_ui_label.text = text
	FrameProfiler.end("FlightDeckManager.physics", _profiler_start)


func record_heli_stat(craft_name: String, stat: String) -> void:
	if not _heli_test_active:
		return
	var base_name: String = ""
	for k in _heli_test_stats.keys():
		if k in craft_name:
			base_name = k
			break
	if base_name != "" and _heli_test_stats[base_name].has(stat):
		_heli_test_stats[base_name][stat] += 1

func _abort_current_sequence() -> void:
	# Called when a safety check fails (plane destroyed or fell off)
	_return_tractors_to_staging()
	_recovery_powerdown_in_progress = false
	_recovery_release_done = false
	_recovery_job_dispatched = false
	deck_aircraft = null
	_pending_store_aircraft = null
	_landing_clearance_aircraft = null
	_landing_clearance_queue.clear()
	_reset_landing_blocker_cleanup()
	if catapult and catapult.has_method("_reset_state"):
		catapult._reset_state()
	current_state = DeckState.IDLE

func _find_arrested_aircraft() -> RigidBody3D:
	for group in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is RigidBody3D):
				continue
			var aircraft := node as RigidBody3D
			if not is_instance_valid(aircraft):
				continue
			if aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged")):
				return aircraft
	return null

func _find_stopped_aircraft_in_recovery_zone() -> RigidBody3D:
	for group in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is RigidBody3D):
				continue
			var aircraft := node as RigidBody3D
			if not is_instance_valid(aircraft):
				continue
			var in_transport := aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode"))
			if _is_helicopter_aircraft(aircraft):
				# Helicopters set carrier_transport_mode when parked — don't skip them.
				if _is_helicopter_ready_for_deck_recovery(aircraft):
					return aircraft
				continue
			if in_transport:
				continue
			var controls_disabled := aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled"))
			var arresting_engaged := aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged"))
			var parking_brake := aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
			if controls_disabled and not arresting_engaged and not parking_brake:
				continue
			if aircraft.linear_velocity.length() > auto_recovery_speed_threshold_mps:
				continue
			if _is_aircraft_in_auto_recovery_zone(aircraft):
				var carrier := get_parent() as Node3D
				var local_pos := carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
				_recovery_debug("candidate in recovery zone %s speed=%.2f local=%s" % [
					_aircraft_debug_name(aircraft),
					aircraft.linear_velocity.length(),
					_fmt_vec3(local_pos)
				])
				return aircraft
	return null

func _is_helicopter_ready_for_deck_recovery(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if aircraft.has_meta("helicopter_deck_takeoff_ready") and bool(aircraft.get_meta("helicopter_deck_takeoff_ready")):
		return false
	if aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled")):
		return false
	if not _is_helicopter_on_carrier_deck_for_recovery(aircraft):
		return false
	# Accept a parked helicopter (parking_brake set, near-zero relative speed) even
	# if the engine is still spinning down — the pilot already zeroed collective/power.
	# A braked helicopter can be anywhere on deck (not just the fixed-wing recovery zone).
	var has_brake := aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
	var relative_speed := _get_aircraft_carrier_relative_speed(aircraft)
	if not has_brake:
		if not _is_helicopter_engine_stopped(aircraft):
			return false
		if not _is_aircraft_blocking_landing_deck(aircraft):
			return false
	if relative_speed > auto_recovery_speed_threshold_mps:
		return false
	var carrier := get_parent() as Node3D
	var local_pos := carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	_recovery_debug("helicopter ready for deck recovery %s rel_speed=%.2f local=%s" % [
		_aircraft_debug_name(aircraft),
		relative_speed,
		_fmt_vec3(local_pos)
	])
	return true

func _is_helicopter_on_carrier_deck_for_recovery(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode")):
		return true
	if _is_aircraft_blocking_landing_deck(aircraft):
		return true
	if _is_aircraft_in_auto_recovery_zone(aircraft):
		return true
	return false

func _is_helicopter_engine_stopped(aircraft: RigidBody3D) -> bool:
	var engine := aircraft.find_child("Engine", true, false)
	if engine == null:
		return aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake"))
	var working = engine.get("is_engine_working")
	if working != null and bool(working):
		return false
	var target_power = engine.get("target_power")
	if target_power != null and float(target_power) > 0.01:
		return false
	return true

func _get_aircraft_carrier_relative_speed(aircraft: RigidBody3D) -> float:
	var reference_velocity := _get_aircraft_reference_velocity(aircraft)
	if reference_velocity.length_squared() <= 0.0001:
		var carrier := get_parent()
		if carrier is Node:
			reference_velocity = _get_node_velocity(carrier as Node)
	var relative_velocity := aircraft.linear_velocity - reference_velocity
	return Vector2(relative_velocity.x, relative_velocity.z).length()

func _get_aircraft_reference_velocity(aircraft: RigidBody3D) -> Vector3:
	if aircraft.has_meta(MOTION_REFERENCE_NODE_META):
		var reference = aircraft.get_meta(MOTION_REFERENCE_NODE_META)
		if reference is Node and is_instance_valid(reference):
			return _get_node_velocity(reference as Node)
	if aircraft.has_meta(MOTION_REFERENCE_VELOCITY_META):
		var velocity = aircraft.get_meta(MOTION_REFERENCE_VELOCITY_META)
		if typeof(velocity) == TYPE_VECTOR3:
			return velocity as Vector3
	if aircraft.has_meta(LEGACY_CARRIER_VELOCITY_META):
		var legacy_velocity = aircraft.get_meta(LEGACY_CARRIER_VELOCITY_META)
		if typeof(legacy_velocity) == TYPE_VECTOR3:
			return legacy_velocity as Vector3
	return Vector3.ZERO

func _set_aircraft_reference_node(aircraft: RigidBody3D, reference_node: Node) -> void:
	if not is_instance_valid(aircraft) or not is_instance_valid(reference_node):
		return
	var reference_velocity := _get_node_velocity(reference_node)
	aircraft.set_meta(MOTION_REFERENCE_NODE_META, reference_node)
	aircraft.set_meta(MOTION_REFERENCE_VELOCITY_META, reference_velocity)
	aircraft.set_meta(LEGACY_CARRIER_VELOCITY_META, reference_velocity)

func _set_manual_transport(node: Node, enabled: bool) -> void:
	if not is_instance_valid(node):
		return
	if enabled:
		node.set_meta(MANUAL_TRANSPORT_META, true)
	elif node.has_meta(MANUAL_TRANSPORT_META):
		node.remove_meta(MANUAL_TRANSPORT_META)

func _get_node_velocity(node: Node) -> Vector3:
	if node is RigidBody3D:
		return (node as RigidBody3D).linear_velocity
	if node.has_method("get_deck_reference_velocity_vector"):
		var deck_velocity = node.call("get_deck_reference_velocity_vector")
		if typeof(deck_velocity) == TYPE_VECTOR3:
			return deck_velocity as Vector3
	if node is CharacterBody3D:
		return (node as CharacterBody3D).velocity
	if node.has_method("get_velocity_vector"):
		var velocity = node.call("get_velocity_vector")
		if typeof(velocity) == TYPE_VECTOR3:
			return velocity as Vector3
	var property_velocity = node.get("velocity")
	if typeof(property_velocity) == TYPE_VECTOR3:
		return property_velocity as Vector3
	return Vector3.ZERO

func _is_aircraft_in_auto_recovery_zone(aircraft: RigidBody3D) -> bool:
	var carrier := get_parent() as Node3D
	if carrier == null:
		return false
	var local_pos := carrier.to_local(aircraft.global_position)
	var deck_y := _get_deck_height_y()
	if absf(aircraft.global_position.y - deck_y) > auto_recovery_zone_height_margin_m:
		return false
	if absf(local_pos.x) > auto_recovery_zone_half_width_m:
		return false
	return local_pos.z >= auto_recovery_zone_min_local_z and local_pos.z <= auto_recovery_zone_max_local_z

func _get_all_aircraft_nodes() -> Array[RigidBody3D]:
	var all_aircraft: Array[RigidBody3D] = []
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is RigidBody3D):
				continue
			var aircraft := node as RigidBody3D
			if not is_instance_valid(aircraft):
				continue
			if _is_non_aircraft_body(aircraft):
				continue
			var id := aircraft.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			all_aircraft.append(aircraft)
	return all_aircraft

func _is_aircraft_blocking_landing_deck(aircraft: RigidBody3D, requester: RigidBody3D = null) -> bool:
	if not is_instance_valid(aircraft) or aircraft == requester:
		return false
	if _is_landing_clearance_aircraft_stale(aircraft):
		return false
	if aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode")):
		return false
	var carrier := get_parent() as Node3D
	if carrier == null:
		return false
	var local_pos := carrier.to_local(aircraft.global_position)
	var deck_y := _get_deck_height_y()
	if absf(aircraft.global_position.y - deck_y) > landing_deck_block_height_margin_m:
		return false
	if absf(local_pos.x) > landing_deck_block_half_width_m:
		return false
	return local_pos.z >= landing_deck_block_min_local_z and local_pos.z <= landing_deck_block_max_local_z

func _is_aircraft_physically_in_landing_deck_rectangle(aircraft: RigidBody3D, requester: RigidBody3D = null) -> bool:
	if not is_instance_valid(aircraft) or aircraft == requester:
		return false
	if _is_landing_clearance_aircraft_stale(aircraft):
		return false
	var carrier := get_parent() as Node3D
	if carrier == null:
		return false
	var local_pos := carrier.to_local(aircraft.global_position)
	var deck_y := _get_deck_height_y()
	if absf(aircraft.global_position.y - deck_y) > landing_deck_block_height_margin_m:
		return false
	if absf(local_pos.x) > landing_deck_block_half_width_m:
		return false
	return local_pos.z >= landing_deck_block_min_local_z and local_pos.z <= landing_deck_block_max_local_z

func _find_landing_deck_blocker(requester: RigidBody3D = null) -> RigidBody3D:
	for aircraft in _get_all_aircraft_nodes():
		if _is_aircraft_blocking_landing_deck(aircraft, requester) \
				or _is_aircraft_physically_in_landing_deck_rectangle(aircraft, requester):
			return aircraft
	return null

func _reset_landing_blocker_cleanup() -> void:
	_landing_blocker_aircraft = null
	_landing_blocker_elapsed_s = 0.0
	_landing_blocker_cleanup_dispatched = false

func _landing_blocker_cleanup_has_landing_pressure(blocker: RigidBody3D) -> bool:
	if is_instance_valid(_landing_clearance_aircraft):
		return true
	if not _landing_clearance_queue.is_empty():
		return true
	# If the blocker itself has already landed and is waiting on the deck, clearing it is
	# useful even before the next aircraft asks for clearance.
	return is_instance_valid(blocker) and _is_helicopter_ready_for_deck_recovery(blocker)

func _landing_blocker_has_deck_contact(blocker: RigidBody3D) -> bool:
	if not is_instance_valid(blocker):
		return false
	if blocker.has_meta("carrier_transport_mode") and bool(blocker.get_meta("carrier_transport_mode")):
		return true
	if blocker.has_meta("parking_brake") and bool(blocker.get_meta("parking_brake")):
		return true
	var deck_y := _get_deck_height_y()
	var contact_margin := maxf(landing_blocker_cleanup_deck_contact_margin_m, 0.0)
	var gear_nodes := _find_gear_colliders(blocker)
	if gear_nodes.is_empty():
		gear_nodes = _get_launch_wheel_nodes(blocker)
	if gear_nodes.is_empty():
		return absf(blocker.global_position.y - deck_y) <= contact_margin
	for gear in gear_nodes:
		if is_instance_valid(gear) and absf((gear as Node3D).global_position.y - deck_y) <= contact_margin:
			return true
	return false

func _update_landing_blocker_cleanup(delta: float, blocker: RigidBody3D) -> void:
	if not landing_blocker_cleanup_enabled:
		_reset_landing_blocker_cleanup()
		return
	if current_state not in [DeckState.IDLE, DeckState.AIRCRAFT_ON_DECK]:
		_reset_landing_blocker_cleanup()
		return
	if not is_instance_valid(blocker):
		_reset_landing_blocker_cleanup()
		return
	if blocker == deck_aircraft or blocker == _pending_store_aircraft:
		_reset_landing_blocker_cleanup()
		return
	if _landing_blocker_cleanup_dispatched:
		return
	if not _landing_blocker_cleanup_has_landing_pressure(blocker):
		_reset_landing_blocker_cleanup()
		return
	var relative_speed := _get_aircraft_carrier_relative_speed(blocker)
	if relative_speed > maxf(landing_blocker_cleanup_speed_threshold_mps, 0.0):
		_reset_landing_blocker_cleanup()
		return
	if not _landing_blocker_has_deck_contact(blocker):
		_reset_landing_blocker_cleanup()
		return
	if _landing_blocker_aircraft != blocker:
		_landing_blocker_aircraft = blocker
		_landing_blocker_elapsed_s = 0.0
		_recovery_debug("landing blocker cleanup armed for %s" % _aircraft_debug_name(blocker))
	_landing_blocker_elapsed_s += maxf(delta, 0.0)
	if _landing_blocker_elapsed_s < maxf(landing_blocker_cleanup_timeout_s, 0.0):
		return
	_landing_blocker_cleanup_dispatched = true
	_recovery_debug("landing blocker cleanup dispatching tractor recovery for %s after %.1fs" % [
		_aircraft_debug_name(blocker),
		_landing_blocker_elapsed_s,
	])
	start_post_arrest_recovery(blocker)

func _landing_deck_state_busy_for_clearance() -> bool:
	return current_state in [
		DeckState.LAUNCH_IN_PROGRESS,
		DeckState.RECOVERY_IN_PROGRESS,
		DeckState.STORING_IN_HANGAR,
		DeckState.RETRIEVING_FROM_HANGAR,
		DeckState.TRACTOR_CLEANUP
	]

func _can_grant_landing_clearance_to(requester: RigidBody3D = null) -> bool:
	if _landing_deck_state_busy_for_clearance():
		return false
	for aircraft in _get_all_aircraft_nodes():
		if _is_aircraft_blocking_landing_deck(aircraft, requester) \
				or _is_aircraft_physically_in_landing_deck_rectangle(aircraft, requester):
			return false
	return true

func _is_landing_deck_busy(requester: RigidBody3D = null) -> bool:
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	if is_instance_valid(_landing_clearance_aircraft):
		if requester == null or _landing_clearance_aircraft != requester:
			return true
	else:
		_landing_clearance_aircraft = null
		if not _landing_clearance_queue.is_empty() \
				and (requester == null or _landing_clearance_queue[0] != requester):
			return true
	return not _can_grant_landing_clearance_to(requester)

func can_accept_landing(requester: RigidBody3D = null) -> bool:
	var busy := _is_landing_deck_busy(requester)
	landing_deck_active = busy \
			or is_instance_valid(_landing_clearance_aircraft) \
			or not _landing_clearance_queue.is_empty()
	return not busy

func is_carrier_recovery_constraint_active() -> bool:
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	return current_state == DeckState.RECOVERY_IN_PROGRESS \
			or (carrier_recovery_constraint_requires_active_clearance and _landing_clearance_aircraft_needs_carrier_constraint())

func _landing_clearance_aircraft_needs_carrier_constraint() -> bool:
	if not is_instance_valid(_landing_clearance_aircraft):
		return false
	if _is_helicopter_aircraft(_landing_clearance_aircraft):
		return false
	return _landing_clearance_aircraft.has_meta("carrier_landing_final_active") \
			and bool(_landing_clearance_aircraft.get_meta("carrier_landing_final_active"))

func get_carrier_recovery_speed_limit_mps() -> float:
	if not is_carrier_recovery_constraint_active():
		return INF
	return maxf(carrier_recovery_speed_limit_mps, 0.0)

func has_landing_clearance(requester: RigidBody3D) -> bool:
	_prune_landing_clearance_aircraft()
	return is_instance_valid(requester) \
			and is_instance_valid(_landing_clearance_aircraft) \
			and _landing_clearance_aircraft == requester

func _queue_landing_clearance_request(requester: RigidBody3D) -> void:
	if _is_landing_clearance_aircraft_stale(requester):
		return
	if _landing_clearance_queue.has(requester):
		return
	_landing_clearance_queue.append(requester)
	_recovery_debug("landing clearance queued for %s" % _aircraft_debug_name(requester))

func _remove_landing_clearance_request(requester: RigidBody3D) -> void:
	if requester == null:
		return
	for i in range(_landing_clearance_queue.size() - 1, -1, -1):
		if _landing_clearance_queue[i] == requester:
			_landing_clearance_queue.remove_at(i)

func _prune_landing_clearance_queue() -> void:
	_prune_landing_clearance_retry_cooldowns()
	for i in range(_landing_clearance_queue.size() - 1, -1, -1):
		if _is_landing_clearance_aircraft_stale(_landing_clearance_queue[i]):
			_recovery_debug("landing clearance removed stale queued aircraft %s" % _aircraft_debug_name(_landing_clearance_queue[i]))
			_landing_clearance_queue.remove_at(i)

func _prune_landing_clearance_retry_cooldowns() -> void:
	if _landing_clearance_retry_after_s.is_empty():
		return
	var now_s := Time.get_ticks_msec() / 1000.0
	for key in _landing_clearance_retry_after_s.keys():
		if float(_landing_clearance_retry_after_s[key]) <= now_s:
			_landing_clearance_retry_after_s.erase(key)

func _is_landing_clearance_request_on_cooldown(requester: RigidBody3D) -> bool:
	if not is_instance_valid(requester):
		return false
	var key := requester.get_instance_id()
	if not _landing_clearance_retry_after_s.has(key):
		return false
	return float(_landing_clearance_retry_after_s[key]) > Time.get_ticks_msec() / 1000.0

func _set_landing_clearance_retry_cooldown(requester: RigidBody3D) -> void:
	if not is_instance_valid(requester):
		return
	var cooldown_s := maxf(landing_clearance_retry_cooldown_s, 0.0)
	if cooldown_s <= 0.0:
		return
	_landing_clearance_retry_after_s[requester.get_instance_id()] = Time.get_ticks_msec() / 1000.0 + cooldown_s

func _prune_landing_clearance_aircraft() -> void:
	if _landing_clearance_aircraft == null:
		_landing_clearance_elapsed_s = 0.0
		return
	if not _is_landing_clearance_aircraft_stale(_landing_clearance_aircraft):
		return
	_recovery_debug("landing clearance released stale holder %s" % _aircraft_debug_name(_landing_clearance_aircraft))
	_landing_clearance_aircraft = null
	_landing_clearance_elapsed_s = 0.0

func _update_landing_clearance_timeout(delta: float) -> void:
	if not is_instance_valid(_landing_clearance_aircraft):
		_landing_clearance_aircraft = null
		_landing_clearance_elapsed_s = 0.0
		return
	var timeout_s := maxf(landing_clearance_timeout_s, 0.0)
	if timeout_s <= 0.0:
		return
	_landing_clearance_elapsed_s += maxf(delta, 0.0)
	if _landing_clearance_elapsed_s < timeout_s:
		return
	if _is_aircraft_blocking_landing_deck(_landing_clearance_aircraft):
		_landing_clearance_elapsed_s = timeout_s
		return
	var bumped := _landing_clearance_aircraft
	_landing_clearance_aircraft = null
	_landing_clearance_elapsed_s = 0.0
	if _landing_clearance_queue.is_empty():
		_set_landing_clearance_retry_cooldown(bumped)
		_recovery_debug("landing clearance timed out for %s; released (no queue waiting)" % _aircraft_debug_name(bumped))
	elif not _is_landing_clearance_aircraft_stale(bumped) and not _landing_clearance_queue.has(bumped):
		_landing_clearance_queue.append(bumped)
		_recovery_debug("landing clearance timed out for %s; moved to back of queue (%d waiting)" % [
			_aircraft_debug_name(bumped),
			_landing_clearance_queue.size(),
		])
	landing_deck_active = _is_landing_deck_busy()
	_grant_next_landing_clearance_if_possible()

func _is_landing_clearance_aircraft_stale(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return true
	if aircraft.is_queued_for_deletion():
		return true
	if _is_non_aircraft_body(aircraft):
		return true
	if not aircraft.is_inside_tree():
		return true
	if aircraft.has_meta("non_aircraft_body") and bool(aircraft.get_meta("non_aircraft_body")):
		return true
	if "current_health" in aircraft and float(aircraft.get("current_health")) <= 0.0:
		return true
	if "_has_exploded" in aircraft and bool(aircraft.get("_has_exploded")):
		return true
	var carrier := get_parent() as Node3D
	if is_instance_valid(carrier) and maxf(landing_clearance_abandon_radius_m, 0.0) > 0.0:
		var carrier_to_aircraft := aircraft.global_position - carrier.global_position
		carrier_to_aircraft.y = 0.0
		if carrier_to_aircraft.length() > landing_clearance_abandon_radius_m:
			return true
	return false

func _grant_landing_clearance(requester: RigidBody3D) -> void:
	if _is_landing_clearance_aircraft_stale(requester):
		return
	_landing_clearance_aircraft = requester
	_landing_clearance_elapsed_s = 0.0
	_remove_landing_clearance_request(requester)
	landing_deck_active = true
	_recovery_debug("landing clearance granted to %s" % _aircraft_debug_name(requester))

func _grant_next_landing_clearance_if_possible() -> void:
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	if is_instance_valid(_landing_clearance_aircraft):
		return
	if _landing_clearance_queue.is_empty():
		return
	var requester := _landing_clearance_queue[0]
	if not is_instance_valid(requester):
		_landing_clearance_queue.remove_at(0)
		return
	if _can_grant_landing_clearance_to(requester):
		_grant_landing_clearance(requester)

func request_landing_clearance(requester: RigidBody3D) -> bool:
	if not is_instance_valid(requester):
		return false
	_prune_landing_clearance_queue()
	_prune_landing_clearance_aircraft()
	if _is_landing_clearance_request_on_cooldown(requester):
		landing_deck_active = _is_landing_deck_busy()
		return false
	if has_landing_clearance(requester):
		return true
	if is_instance_valid(_landing_clearance_aircraft):
		_queue_landing_clearance_request(requester)
		landing_deck_active = true
		return false
	if not _landing_clearance_queue.is_empty():
		if not _landing_clearance_queue.has(requester):
			_queue_landing_clearance_request(requester)
		if _landing_clearance_queue[0] != requester:
			landing_deck_active = true
			return false
	if not _can_grant_landing_clearance_to(requester):
		_queue_landing_clearance_request(requester)
		landing_deck_active = true
		return false
	_grant_landing_clearance(requester)
	return true

func get_landing_queue_position(requester: RigidBody3D) -> int:
	if not is_instance_valid(requester):
		return -1
	if is_instance_valid(_landing_clearance_aircraft) and _landing_clearance_aircraft == requester:
		return 0  # cleared, actively landing
	for i in range(_landing_clearance_queue.size()):
		if is_instance_valid(_landing_clearance_queue[i]) and _landing_clearance_queue[i] == requester:
			# Position 1 = next in queue (at approach point), 2 = behind, etc.
			return i + 1
	return -1  # not in queue


func release_landing_clearance(requester: RigidBody3D) -> void:
	if requester != null:
		_remove_landing_clearance_request(requester)
	if not is_instance_valid(_landing_clearance_aircraft):
		_landing_clearance_aircraft = null
		_landing_clearance_elapsed_s = 0.0
		landing_deck_active = _is_landing_deck_busy()
		_grant_next_landing_clearance_if_possible()
		return
	if requester == null or _landing_clearance_aircraft == requester:
		_recovery_debug("landing clearance released for %s" % _aircraft_debug_name(_landing_clearance_aircraft))
		_landing_clearance_aircraft = null
		_landing_clearance_elapsed_s = 0.0
		landing_deck_active = _is_landing_deck_busy()
		_grant_next_landing_clearance_if_possible()

func start_post_arrest_recovery(aircraft_variant: Variant) -> void:
	"""Called by AIPilot when the arresting cable has already auto-released.
	Skips the power-down timer and goes straight to hangar storage."""
	if not is_instance_valid(aircraft_variant):
		_recovery_debug("start_post_arrest_recovery ignored: invalid aircraft")
		return
	var aircraft := aircraft_variant as RigidBody3D
	if not is_instance_valid(aircraft):
		_recovery_debug("start_post_arrest_recovery ignored: invalid aircraft")
		return
	if _is_helicopter_aircraft(aircraft) and not _is_helicopter_on_carrier_deck_for_recovery(aircraft):
		var carrier := get_parent() as Node3D
		var local_pos := carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
		_recovery_debug("start_post_arrest_recovery ignored: helicopter not on deck aircraft=%s local=%s pos=%s" % [
			_aircraft_debug_name(aircraft),
			_fmt_vec3(local_pos),
			_fmt_vec3(aircraft.global_position),
		])
		return
	release_landing_clearance(aircraft)
	var arresting_engaged := aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged"))
	var cable = aircraft.get_meta("arresting_cable") if aircraft.has_meta("arresting_cable") else null
	# If FlightDeckManager already started a managed recovery via signal, let it finish.
	if current_state == DeckState.RECOVERY_IN_PROGRESS:
		if deck_aircraft == aircraft and _recovery_job_dispatched:
			_recovery_debug("start_post_arrest_recovery ignored: same aircraft already dispatched")
			return
		if deck_aircraft != aircraft and _recovery_job_dispatched:
			_recovery_debug("start_post_arrest_recovery ignored: another aircraft already dispatched")
			return
	if current_state == DeckState.RECOVERY_IN_PROGRESS and deck_aircraft != aircraft and _recovery_job_dispatched and false:
		return
	deck_aircraft = aircraft
	_pending_store_aircraft = aircraft
	current_state = DeckState.RECOVERY_IN_PROGRESS
	_recovery_debug("start post-arrest recovery arresting=%s cable=%s" % [
		str(arresting_engaged),
		str(cable != null)
	])
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("controls_disabled", true)
	_stabilize_aircraft_for_recovery_pickup(aircraft)
	var th = _find_tailhook(aircraft)
	if is_instance_valid(th) and th.has_method("stow"):
		th.stow()
	if arresting_engaged and cable and cable.has_method("manual_release"):
		_recovery_powerdown_in_progress = false
		_recovery_release_done = false
		_recovery_job_dispatched = false
		cable.manual_release()
		var still_engaged: bool = aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged"))
		if still_engaged:
			_recovery_debug("manual release requested but aircraft still reports arresting_engaged")
		elif not _recovery_job_dispatched:
			_recovery_release_done = true
			_recovery_debug("cable released synchronously; dispatching recovery")
			_dispatch_recovery_job()
		return
	_recovery_powerdown_in_progress = false
	_recovery_release_done = true
	_recovery_job_dispatched = false
	_recovery_debug("dispatching direct recovery with no engaged cable")
	_dispatch_recovery_job()

func _stabilize_aircraft_for_recovery_pickup(aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("controls_disabled", true)
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	aircraft.freeze = true

func _configure_retrieved_aircraft_as_ai(aircraft: RigidBody3D, land_after_launch: bool = true) -> void:
	"""Set up a hangar-retrieved aircraft for AI control."""
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

	# Manual retrieval can still use a launch-then-recover flow, but scramble
	# launches should immediately proceed to their assigned mission.
	var ai_pilot = aircraft.find_child("AIPilot", true, false)
	if ai_pilot and "land_after_launch" in ai_pilot:
		ai_pilot.land_after_launch = land_after_launch

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
	if _landing_test_active:
		return
	if stored_aircraft.size() >= max_hangar_capacity:
		return
	
	current_state = DeckState.STORING_IN_HANGAR
	_retrieval_top_handled = false
	
	# Move elevator down to hangar level
	if elevator and elevator.has_method("move_platform_down"):
		_ensure_elevator_signal_connections()
		elevator.move_platform_down()

func start_hangar_retrieval():
	"""Start retrieving aircraft from hangar"""
	if _landing_test_active:
		return
	if stored_aircraft.is_empty():
		return
	while _tractor_elevator_transfer_in_progress:
		await get_tree().process_frame

	current_state = DeckState.RETRIEVING_FROM_HANGAR
	_retrieval_top_handled = false

	# Move elevator down to hangar level (empty)
	if elevator and elevator.has_method("move_platform_down"):
		_ensure_elevator_signal_connections()
		if "current_state" in elevator and elevator.current_state == elevator.ElevatorState.AT_BOTTOM:
			_spawn_aircraft_at_hangar_level.call_deferred()
		else:
			elevator.move_platform_down()

func _on_elevator_at_bottom():
	"""Handle elevator reaching bottom"""
	if _landing_test_active and current_state in [DeckState.STORING_IN_HANGAR, DeckState.RETRIEVING_FROM_HANGAR]:
		current_state = DeckState.IDLE
		deck_aircraft = null
		_pending_store_aircraft = null
		_landing_clearance_aircraft = null
		_landing_clearance_queue.clear()
		return
	match current_state:
		DeckState.STORING_IN_HANGAR:
			_store_aircraft_in_hangar()
		DeckState.RETRIEVING_FROM_HANGAR:
			_spawn_aircraft_at_hangar_level()
		DeckState.TRACTOR_CLEANUP:
			pass
		_:
			# State was clobbered mid-descent (e.g. second helicopter landed during storage).
			# If we still have a pending store aircraft, complete it now.
			if is_instance_valid(_pending_store_aircraft):
				_recovery_debug("elevator_at_bottom: state=%s but pending_store valid; completing storage for %s" % [
					_deck_state_name(), _aircraft_debug_name(_pending_store_aircraft)
				])
				current_state = DeckState.STORING_IN_HANGAR
				_store_aircraft_in_hangar()

func _store_aircraft_in_hangar():
	"""Store the aircraft in hangar"""
	if not is_instance_valid(_pending_store_aircraft):
		_pending_store_aircraft = null
		_recovery_debug("store aircraft skipped: no pending store aircraft")
		_landing_clearance_aircraft = null
		_landing_clearance_queue.clear()
		current_state = DeckState.IDLE
		return


	# Store aircraft data for later spawning
	_recovery_debug("storing aircraft in hangar")
	var aircraft_data = _extract_aircraft_data(_pending_store_aircraft)
	_resolve_carrier_manager()
	if is_instance_valid(carrier_manager):
		carrier_manager.mark_aircraft_stored(_pending_store_aircraft, aircraft_data)
	elif not _ensure_pilot_assigned_for_data(aircraft_data):
		push_warning("[FlightDeckManager] Stored aircraft is missing pilot data and CarrierManager is unavailable.")
	stored_aircraft.append(aircraft_data)
	_recovery_debug("aircraft stored; hangar count=%d" % stored_aircraft.size())

	# Remove aircraft from the scene
	_pending_store_aircraft.queue_free()
	_pending_store_aircraft = null

	deck_aircraft = null
	_recovery_powerdown_in_progress = false
	_recovery_release_done = false
	_recovery_job_dispatched = false
	_landing_clearance_aircraft = null
	_landing_clearance_queue.clear()
	_reset_landing_blocker_cleanup()
	current_state = DeckState.IDLE

func _spawn_aircraft_at_hangar_level():
	"""Spawn aircraft at hangar level when elevator reaches bottom during retrieval"""
	if _landing_test_active:
		current_state = DeckState.IDLE
		deck_aircraft = null
		return
	if stored_aircraft.is_empty():
		current_state = DeckState.IDLE
		return


	# Create aircraft at hangar level
	var aircraft = _create_aircraft_at_hangar_level()

	if not aircraft:
		current_state = DeckState.IDLE
		return

	stored_aircraft.pop_front()  # Remove from hangar storage

	# Store reference for the retrieval sequence
	deck_aircraft = aircraft

	# Short settle so the fresh spawn is stable before the elevator starts up.
	await get_tree().create_timer(_retrieval_spawn_settle_s).timeout
	# Re-validate after await: local references can become stale if the node was freed.
	var retrieval_aircraft := deck_aircraft
	if not is_instance_valid(retrieval_aircraft):
		deck_aircraft = null
		current_state = DeckState.IDLE
		return
	_start_retrieval_ascent_sequence(retrieval_aircraft)

func _on_elevator_at_top():
	"""Handle elevator reaching top"""
	if _heli_test_active:
		_log_heli_test("elevator top callback state=%s handled=%s physical_top=%s aircraft=%s" % [
			_deck_state_name(),
			str(_retrieval_top_handled),
			str(_is_elevator_physically_at_top()),
			_aircraft_debug_name(deck_aircraft),
		])
	if _landing_test_active and current_state in [DeckState.STORING_IN_HANGAR, DeckState.RETRIEVING_FROM_HANGAR]:
		current_state = DeckState.IDLE
		deck_aircraft = null
		_pending_store_aircraft = null
		return
	match current_state:
		DeckState.STORING_IN_HANGAR:
			deck_aircraft = null
			_pending_store_aircraft = null
			_recovery_powerdown_in_progress = false
			_recovery_release_done = false
			_recovery_job_dispatched = false
			current_state = DeckState.IDLE
		DeckState.RETRIEVING_FROM_HANGAR:
			if not _is_elevator_physically_at_top():
				return
			if _retrieval_top_handled:
				return
			_retrieval_top_handled = true
			_complete_retrieval_sequence()
		DeckState.TRACTOR_CLEANUP:
			pass
		_:
			pass

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

	# Fill hangar to capacity
	for i in range(max_hangar_capacity):
		var aircraft_data := _make_stored_aircraft_entry(
			"Aircraft_" + str(i + 1),
			null,
			DEFAULT_AIRCRAFT_SCENE_PATH
		)
		if aircraft_data.is_empty():
			push_warning("[FlightDeckManager] Stopping hangar prefill: unable to assign pilot to stored aircraft.")
			break
		stored_aircraft.append(aircraft_data)


# --- Aircraft Movement System ---
func _move_aircraft_to_elevator(aircraft: RigidBody3D):
	"""Move aircraft to elevator position using gentle forces"""
	var active_bots: Array[Node] = _activate_tractor_bots(aircraft)
	_recovery_debug("move aircraft to elevator; active_bots=%d target=%s" % [
		active_bots.size(),
		_fmt_vec3(elevator_pickup_marker.global_position)
	])
	# Wait for tractorbots to position themselves, then start gentle movement
	if not active_bots.is_empty():
		await _wait_for_tractor_bots_positioned(active_bots)
	else:
		_recovery_debug("no active tractorbots; moving aircraft without visual tractor pickup")
		
	if not is_instance_valid(aircraft):
		current_state = DeckState.IDLE
		return

	_start_aircraft_movement(aircraft, elevator_pickup_marker.global_position)

func _activate_tractor_bots(aircraft: RigidBody3D) -> Array[Node]:
	"""Activate tractorbots to position at aircraft wheels"""
	var active_bots: Array[Node] = []
	var gear_colliders: Array[Node3D] = _get_launch_wheel_nodes(aircraft)
	if gear_colliders.is_empty():
		_recovery_debug("tractor activation found no gear/wheel nodes on %s" % _aircraft_debug_name(aircraft))
		return active_bots
	_recovery_debug("tractor activation found %d gear nodes and %d configured bots" % [gear_colliders.size(), tractor_bots.size()])

	for i in range(min(tractor_bots.size(), gear_colliders.size())):
		var bot = tractor_bots[i]
		var gear_collider = gear_colliders[i]
		if bot and gear_collider and bot.has_method("activate"):
			# Calculate offset from aircraft center to gear collider
			var wheel_offset = gear_collider.global_position - aircraft.global_position
			bot.activate(aircraft, wheel_offset, gear_collider)
			active_bots.append(bot)
			_recovery_debug("activated %s for gear %s offset=%s" % [
				bot.name,
				gear_collider.name,
				_fmt_vec3(wheel_offset)
			])
	return active_bots

func _get_tractor_wait_status(active_bots: Array[Node]) -> String:
	var parts := PackedStringArray()
	for bot in active_bots:
		if not is_instance_valid(bot):
			parts.append("invalid")
			continue
		if bot.has_method("get_recovery_debug_status"):
			var status: Dictionary = bot.get_recovery_debug_status()
			parts.append("%s phase=%s role=%s pos=%s wheel=%s src=%s dist=%.2f live=%.2f fixed_delta=%.2f replans=%d last_replan=%.2f ac_spd=%.1f bot=%s goal=%s wheel_pos=%s blocked=%s disabled=%s" % [
				str(status.get("name", bot.name)),
				str(status.get("phase", "?")),
				str(status.get("role", "?")),
				str(status.get("positioned", false)),
				str(status.get("target_wheel", "none")),
				str(status.get("wheel_source", "?")),
				float(status.get("distance", -1.0)),
				float(status.get("live_distance", -1.0)),
				float(status.get("fixed_live_delta", -1.0)),
				int(status.get("replans", 0)),
				float(status.get("last_replan_delta", 0.0)),
				float(status.get("aircraft_speed", 0.0)),
				_fmt_vec3(status.get("bot_position", Vector3.ZERO)),
				_fmt_vec3(status.get("goal_position", Vector3.ZERO)),
				_fmt_vec3(status.get("live_wheel_position", Vector3.ZERO)),
				str(status.get("blocked", false)),
				str(status.get("movement_disabled", false))
			])
		else:
			var positioned := false
			if bot.has_method("is_positioned_at_gear"):
				positioned = bool(bot.is_positioned_at_gear())
			parts.append("%s pos=%s" % [bot.name, str(positioned)])
	return "; ".join(parts)

func _wait_for_tractor_bots_positioned(active_bots: Array[Node]):
	"""Wait for all tractorbots to be positioned at their gear locations"""
	var wait_time := 0.0
	var next_debug_time := 0.0
	_recovery_debug("waiting for tractorbots to reach gear")
	while true:
		var all_positioned = true
		for bot in active_bots:
			if bot and bot.has_method("is_positioned_at_gear") and not bot.is_positioned_at_gear():
				all_positioned = false
				break
		
		if all_positioned:
			_recovery_debug("tractorbots positioned after %.2fs" % wait_time)
			break
		if wait_time >= maxf(tractor_position_timeout_s, 0.5):
			_recovery_debug("tractorbot positioning timed out after %.2fs; snapping visual bots to gear" % wait_time)
			_snap_active_tractor_bots_to_targets(active_bots)
			break
		
		var delta := get_process_delta_time()
		wait_time += delta
		if wait_time >= next_debug_time:
			_recovery_debug("waiting for tractorbots %.1fs: %s" % [
				wait_time,
				_get_tractor_wait_status(active_bots)
			])
			next_debug_time += maxf(tractor_recovery_debug_interval_s, 0.1)
		await get_tree().process_frame

func _snap_active_tractor_bots_to_targets(active_bots: Array[Node]) -> void:
	var deck_y := _get_deck_height_y()
	for bot in active_bots:
		if not is_instance_valid(bot) or not (bot is Node3D):
			continue
		var bot_node := bot as Node3D
		var status_target: Vector3 = bot_node.global_position
		var wheel_node := bot.get("target_wheel_node") as Node3D
		var target_aircraft_node := bot.get("target_aircraft") as RigidBody3D
		if is_instance_valid(wheel_node):
			status_target = wheel_node.global_position
		elif is_instance_valid(target_aircraft_node):
			var wheel_offset_variant: Variant = bot.get("wheel_position_offset")
			var wheel_offset: Vector3 = wheel_offset_variant if wheel_offset_variant is Vector3 else Vector3.ZERO
			status_target = target_aircraft_node.global_position + wheel_offset
		status_target.y = deck_y
		_recovery_debug("snap tractorbot %s to wheel target=%s wheel=%s aircraft=%s" % [
			bot_node.name,
			_fmt_vec3(status_target),
			wheel_node.name if is_instance_valid(wheel_node) else "offset",
			_aircraft_debug_name(target_aircraft_node)
		])
		bot_node.global_position = status_target
		bot.set("is_positioned", true)
		if bot.has_method("enable_movement"):
			bot.enable_movement()

func _deactivate_tractor_bots():
	"""Deactivate all tractorbots"""
	for bot in tractor_bots:
		if bot and bot.has_method("enable_movement"):
			bot.enable_movement()
		if bot and bot.has_method("deactivate"):
			bot.deactivate()

func _return_tractors_to_staging():
	"""Force tractorbots to drop what they are doing and return to staging"""
	var primary_bots := _get_primary_tractor_bots()
	var staging_slots := _get_primary_staging_slots_local(primary_bots.size())
	for i in range(min(primary_bots.size(), staging_slots.size())):
		var bot := primary_bots[i]
		if not is_instance_valid(bot):
			continue
		_set_cleanup_idle_for_tractor_bot(bot)
		bot.position = staging_slots[i]
	_tractorbots_in_hangar = false
	for bot in tractor_bots:
		if is_instance_valid(bot):
			# Drop any active connections
			if bot.has_method("_tick_uncoupling"):
				bot._tick_uncoupling(0.0)
			# Legacy TractorBot retreat path (SimpleTractorBot does not expose these members).
			if bot is TractorBot:
				bot.set("_state", TractorBot.BotState.RETURNING_TO_STAGING)
				if bot.has_method("_plan_move_to") and is_instance_valid(bot.staging_marker):
					bot._plan_move_to(bot.staging_marker.global_position)

func _disable_tractor_bot_movement():
	"""Disable tractorbot movement logic during elevator sequence"""
	for bot in tractor_bots:
		if bot and bot.has_method("disable_movement"):
			bot.disable_movement()

func _start_aircraft_movement(aircraft: RigidBody3D, target_position: Vector3):
	"""Start moving aircraft to target position with physics disabled"""
	_recovery_debug("starting aircraft movement to %s" % _fmt_vec3(target_position))
	_prepare_aircraft_for_movement(aircraft)
	# Use the same tractor-coupled horizontal move used during retrieval so
	# storage/retrieval have consistent bot motion and pacing.
	var deck_height = _get_deck_height_y()
	var gear_colliders = _find_gear_colliders(aircraft)
	if not gear_colliders.is_empty():
		var lowest_gear_global_y := INF
		for gear in gear_colliders:
			if (gear as Node3D).global_position.y < lowest_gear_global_y:
				lowest_gear_global_y = (gear as Node3D).global_position.y
		var gear_to_body_offset: float = aircraft.global_position.y - lowest_gear_global_y
		var lift_aircraft_y: float = float(deck_height) + _aircraft_lift_height + gear_to_body_offset
		var lift_target_position = Vector3(target_position.x, lift_aircraft_y, target_position.z)
		await _move_aircraft_horizontally(aircraft, lift_target_position)
	else:
		await _move_aircraft_smoothly(aircraft, target_position)
	
	if not is_instance_valid(aircraft):
		current_state = DeckState.IDLE
		return
	await _align_aircraft_forward_on_elevator(aircraft)

	if not is_instance_valid(aircraft):
		current_state = DeckState.IDLE
		return
	# Wait 1 second after aircraft is in position before starting elevator
	await get_tree().create_timer(1.0).timeout

	# After aircraft reaches elevator, start elevator sequence
	if not is_instance_valid(aircraft):
		_recovery_debug("aircraft movement completed but aircraft became invalid")
		current_state = DeckState.IDLE
		return
	_recovery_debug("aircraft reached elevator; starting elevator sequence")
	_start_elevator_sequence(aircraft)

func _prepare_aircraft_for_movement(aircraft: RigidBody3D):
	"""Disable physics and position aircraft with gear colliders 20cm above flight deck"""

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
		# No gear colliders found — use the LandingGear module's wheel nodes instead
		var wheel_nodes := _get_launch_wheel_nodes(aircraft)
		if not wheel_nodes.is_empty():
			var lowest_world_y := INF
			for w in wheel_nodes:
				if (w as Node3D).global_position.y < lowest_world_y:
					lowest_world_y = (w as Node3D).global_position.y
			aircraft.global_position.y += target_gear_height - lowest_world_y
		else:
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


	var elapsed_time = 0.0

	while elapsed_time < duration and is_instance_valid(aircraft):
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

func _align_aircraft_forward_on_elevator(aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return

	var active_bots: Array[Node3D] = []
	var fallback_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot is Node3D and bool(bot.get("is_active")):
			var bot_node := bot as Node3D
			if bot.has_method("disable_movement"):
				bot.disable_movement()
			active_bots.append(bot_node)
			fallback_offsets.append(bot_node.global_position - aircraft.global_position)

	var start_rotation := aircraft.global_rotation
	var target_yaw := _get_carrier_forward_yaw()
	var duration := maxf(tractor_elevator_align_duration_s, 0.01)
	var elapsed := 0.0
	_recovery_debug("aligning aircraft forward on elevator")

	while elapsed < duration and is_instance_valid(aircraft):
		elapsed += get_process_delta_time()
		var t := ease_in_out_cubic(clampf(elapsed / duration, 0.0, 1.0))
		aircraft.global_rotation = Vector3(
			lerp_angle(start_rotation.x, 0.0, t),
			lerp_angle(start_rotation.y, target_yaw, t),
			lerp_angle(start_rotation.z, 0.0, t)
		)
		_snap_active_bots_to_aircraft_wheels(active_bots, fallback_offsets, aircraft)
		await get_tree().process_frame

	if not is_instance_valid(aircraft):
		return
	aircraft.global_rotation = Vector3(0.0, target_yaw, 0.0)
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	_snap_active_bots_to_aircraft_wheels(active_bots, fallback_offsets, aircraft)

func _snap_active_bots_to_aircraft_wheels(active_bots: Array[Node3D], fallback_offsets: Array[Vector3], aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return
	var bot_floor_y := _get_deck_height_y() + tractor_elevator_floor_offset_m
	for i in range(min(active_bots.size(), fallback_offsets.size())):
		var bot := active_bots[i]
		if not is_instance_valid(bot):
			continue
		var bot_position := aircraft.global_position + fallback_offsets[i]
		var wheel_node := bot.get("target_wheel_node") as Node3D
		if is_instance_valid(wheel_node):
			bot_position = wheel_node.global_position
		bot_position.y = bot_floor_y
		bot.global_position = bot_position

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
		"NoseGearCollider",
		"FrontGearCollider",
		"RearLeftGearCollider",
		"RearRightGearCollider",
		"RearGearCollider",
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

func _find_landing_gear_module(aircraft: RigidBody3D) -> Node:
	for child in _get_all_children(aircraft):
		if "gear_collision_shapes" in child and "nose_gear_index" in child:
			return child
	return null

func _get_launch_wheel_nodes(aircraft: RigidBody3D) -> Array[Node3D]:
	var wheel_nodes: Array[Node3D] = []
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module:
		var shapes_variant: Variant = landing_gear_module.get("gear_collision_shapes")
		if typeof(shapes_variant) == TYPE_ARRAY:
			for entry in shapes_variant:
				if entry is Node3D and is_instance_valid(entry) and not wheel_nodes.has(entry):
					wheel_nodes.append(entry)
	if wheel_nodes.is_empty():
		wheel_nodes = _find_gear_colliders(aircraft)
	return wheel_nodes

func _get_launch_nose_and_main_nodes(aircraft: RigidBody3D, wheel_nodes: Array[Node3D]) -> Dictionary:
	var nose_node: Node3D = null
	var main_nodes: Array[Node3D] = []
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module:
		var nose_index: int = int(landing_gear_module.get("nose_gear_index"))
		if nose_index >= 0 and nose_index < wheel_nodes.size():
			nose_node = wheel_nodes[nose_index]

	if nose_node == null:
		for wheel in wheel_nodes:
			var name_l: String = wheel.name.to_lower()
			if "nose" in name_l or "center" in name_l:
				nose_node = wheel
				break

	for wheel in wheel_nodes:
		if wheel != nose_node:
			main_nodes.append(wheel)

	return {
		"nose": nose_node,
		"mains": main_nodes,
	}

func _lower_launch_wheels_to_deck(aircraft: RigidBody3D, wheel_nodes: Array[Node3D], deck_y: float) -> void:
	if wheel_nodes.is_empty():
		aircraft.global_position.y = deck_y
		return

	var contact_offset: float = _get_deck_contact_visual_offset(aircraft)
	var lowest_world_y: float = INF
	for gear in wheel_nodes:
		var gear_world_y: float = gear.global_position.y - contact_offset
		if gear_world_y < lowest_world_y:
			lowest_world_y = gear_world_y
	aircraft.global_position.y += deck_y - lowest_world_y

func _get_deck_contact_visual_offset(aircraft: RigidBody3D) -> float:
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module == null:
		return 0.0
	var offset = landing_gear_module.get("deck_contact_visual_offset_m")
	if offset == null:
		return 0.0
	return maxf(float(offset), 0.0)

func _settle_launch_aircraft_on_wheels(aircraft: RigidBody3D, wheel_nodes: Array[Node3D], deck_y: float) -> void:
	if wheel_nodes.is_empty():
		aircraft.global_position.y = deck_y
		return

	var wheel_split: Dictionary = _get_launch_nose_and_main_nodes(aircraft, wheel_nodes)
	var nose_node: Node3D = wheel_split.get("nose") as Node3D
	var main_nodes: Array[Node3D] = wheel_split.get("mains", []) as Array[Node3D]
	var max_pitch: float = deg_to_rad(launch_deck_pitch_contact_max_deg)

	for _i in range(4):
		if is_instance_valid(nose_node) and main_nodes.size() >= 2 and max_pitch > 0.0:
			var nose_local: Vector3 = aircraft.to_local(nose_node.global_position)
			var main_avg_local: Vector3 = Vector3.ZERO
			var main_avg_world_y: float = 0.0
			for wheel in main_nodes:
				main_avg_local += aircraft.to_local(wheel.global_position)
				main_avg_world_y += wheel.global_position.y
			main_avg_local /= float(main_nodes.size())
			main_avg_world_y /= float(main_nodes.size())

			var longitudinal_span: float = absf(nose_local.z - main_avg_local.z)
			var height_error: float = nose_node.global_position.y - main_avg_world_y
			if longitudinal_span > 0.001 and absf(height_error) > 0.002:
				var pitch_step: float = clampf(atan2(height_error, longitudinal_span), -max_pitch, max_pitch)
				if absf(pitch_step) >= deg_to_rad(0.02):
					var x_axis: Vector3 = aircraft.global_transform.basis.x.normalized()
					var adjusted_basis: Basis = aircraft.global_transform.basis.rotated(x_axis, pitch_step).orthonormalized()
					var adjusted_transform: Transform3D = aircraft.global_transform
					adjusted_transform.basis = adjusted_basis
					aircraft.global_transform = adjusted_transform

		_lower_launch_wheels_to_deck(aircraft, wheel_nodes, deck_y)

	var final_heights: Array[String] = []
	for wheel in wheel_nodes:
		final_heights.append(str(snappedf(wheel.global_position.y - deck_y, 0.001)))

func _apply_launch_three_wheel_pitch_correction(aircraft: RigidBody3D, wheel_nodes: Array[Node3D]) -> void:
	if wheel_nodes.size() < 3 or launch_deck_pitch_contact_max_deg <= 0.0:
		return

	var nose_node: Node3D = null
	var main_nodes: Array[Node3D] = []
	var landing_gear_module := _find_landing_gear_module(aircraft)
	if landing_gear_module:
		var nose_index := int(landing_gear_module.get("nose_gear_index"))
		if nose_index >= 0 and nose_index < wheel_nodes.size():
			nose_node = wheel_nodes[nose_index]

	if nose_node == null:
		for wheel in wheel_nodes:
			var name_l := wheel.name.to_lower()
			if "nose" in name_l or "center" in name_l:
				nose_node = wheel
				break
	if nose_node == null:
		return

	for wheel in wheel_nodes:
		if wheel == nose_node:
			continue
		main_nodes.append(wheel)
	if main_nodes.size() < 2:
		return

	var nose_local := aircraft.to_local(nose_node.global_position)
	var main_avg := Vector3.ZERO
	for wheel in main_nodes:
		main_avg += aircraft.to_local(wheel.global_position)
	main_avg /= float(main_nodes.size())

	var dz := nose_local.z - main_avg.z
	var dy := nose_local.y - main_avg.y
	if absf(dz) < 0.001 or absf(dy) < 0.0005:
		return

	var max_pitch := deg_to_rad(launch_deck_pitch_contact_max_deg)
	var pitch_correction := clampf(atan2(dy, dz), -max_pitch, max_pitch)
	if absf(pitch_correction) < deg_to_rad(0.05):
		return

	var x_axis := aircraft.global_transform.basis.x.normalized()
	var adjusted_basis := aircraft.global_transform.basis.rotated(x_axis, pitch_correction).orthonormalized()
	var adjusted_transform := aircraft.global_transform
	adjusted_transform.basis = adjusted_basis
	aircraft.global_transform = adjusted_transform

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

func _get_deck_local_y() -> float:
	if deck_marker and deck_marker is Node3D:
		return (deck_marker as Node3D).position.y
	return _flight_deck_local_offset_y

func _get_all_tractor_nodes() -> Array[Node3D]:
	var tractor_nodes: Array[Node3D] = []
	var carrier := get_parent()
	if carrier == null:
		return tractor_nodes
	for node in carrier.find_children("*", "", true, false):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if node.get_parent() != carrier:
			continue
		if node is SimpleTractorBot or node is TractorBot:
			tractor_nodes.append(node as Node3D)
	return tractor_nodes

func _get_extra_deck_tractor_bots() -> Array[Node3D]:
	var extras: Array[Node3D] = []
	var deck_y := _get_deck_height_y()
	var carrier := get_parent() as Node3D
	for node in _get_all_tractor_nodes():
		if tractor_bots.has(node):
			continue
		if absf(node.global_position.y - deck_y) > 2.5:
			continue
		if carrier != null:
			var local_pos := carrier.to_local(node.global_position)
			if absf(local_pos.x) > 25.0 or absf(local_pos.z) > 90.0:
				continue
		extras.append(node)
	return extras

func _get_tractor_cleanup_elevator_slots_local(count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var deck_local_y: float = _get_deck_local_y()
	var slot_offsets: Array[Vector3] = [
		Vector3(-6.0, 0.0, -3.0),
		Vector3(-2.0, 0.0, -3.0),
		Vector3(2.0, 0.0, -3.0),
		Vector3(6.0, 0.0, -3.0)
	]
	var base_local: Vector3 = elevator_pickup_marker.position if is_instance_valid(elevator_pickup_marker) else Vector3.ZERO
	for i in range(min(count, slot_offsets.size())):
		var slot_local: Vector3 = base_local + slot_offsets[i]
		slot_local.y = deck_local_y
		slots.append(slot_local)
	return slots

func _get_tractor_cleanup_hangar_slots_local(count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var hangar_local_y: float = _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
	var slot_offsets: Array[Vector3] = [
		Vector3(-9.0, 0.0, -8.0),
		Vector3(-3.0, 0.0, -8.0),
		Vector3(3.0, 0.0, -8.0),
		Vector3(9.0, 0.0, -8.0)
	]
	var base_local: Vector3 = elevator_pickup_marker.position if is_instance_valid(elevator_pickup_marker) else Vector3.ZERO
	for i in range(min(count, slot_offsets.size())):
		var slot_local: Vector3 = base_local + slot_offsets[i]
		slot_local.y = hangar_local_y
		slots.append(slot_local)
	return slots

func get_deck_height() -> float:
	"""Public method to get deck height for other components"""
	return _get_deck_height_y()

func _capture_aircraft_energy_state(aircraft: RigidBody3D) -> Array[Dictionary]:
	var containers: Array[Dictionary] = []
	for node in _get_all_children(aircraft):
		if "current_level" in node and "EnergyType" in node and "MaxCapacity" in node:
			containers.append({
				"path": str(aircraft.get_path_to(node)),
				"energy_type": str(node.get("EnergyType")),
				"current_level": float(node.get("current_level")),
				"active": bool(node.get("ContainerActive")),
			})
	return containers

func _restore_aircraft_energy_state(aircraft: RigidBody3D, energy_state: Array) -> void:
	for entry_variant in energy_state:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var node_path := NodePath(str(entry.get("path", "")))
		if node_path == NodePath():
			continue
		var container := aircraft.get_node_or_null(node_path)
		if container == null:
			continue
		if "ContainerActive" in container:
			container.set("ContainerActive", bool(entry.get("active", true)))
		if "current_level" in container:
			container.set("current_level", float(entry.get("current_level", container.get("current_level"))))
		if container.has_method("request_update_interface"):
			container.request_update_interface()
	if aircraft.has_method("prepare_energy_system"):
		aircraft.prepare_energy_system()

func _capture_aircraft_loadout_state(aircraft: RigidBody3D) -> Dictionary:
	var loadout: Array[Dictionary] = []
	for node in _get_all_children(aircraft):
		if node is Hardpoint:
			var hardpoint := node as Hardpoint
			var weapon_scene_path := ""
			var ammo_count := -1
			if is_instance_valid(hardpoint.weapon_instance):
				weapon_scene_path = hardpoint.weapon_instance.scene_file_path
				if weapon_scene_path == "" and hardpoint.mounted_weapon:
					weapon_scene_path = hardpoint.mounted_weapon.resource_path
				if "ammo_count" in hardpoint.weapon_instance:
					ammo_count = int(hardpoint.weapon_instance.get("ammo_count"))
			elif hardpoint.mounted_weapon:
				weapon_scene_path = hardpoint.mounted_weapon.resource_path
			loadout.append({
				"path": str(aircraft.get_path_to(hardpoint)),
				"weapon_scene": weapon_scene_path,
				"ammo_count": ammo_count,
			})
	var selected_weapon_type := ""
	var control_weapons := aircraft.find_child("ControlWeapons", true, false)
	if control_weapons and "selected_weapon_type" in control_weapons:
		selected_weapon_type = str(control_weapons.selected_weapon_type)
	return {
		"hardpoints": loadout,
		"selected_weapon_type": selected_weapon_type,
	}

func _restore_aircraft_loadout_state(aircraft: RigidBody3D, loadout_state: Dictionary) -> void:
	var hardpoints: Array = loadout_state.get("hardpoints", [])
	for entry_variant in hardpoints:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var hardpoint := aircraft.get_node_or_null(NodePath(str(entry.get("path", "")))) as Hardpoint
		if hardpoint == null:
			continue
		if is_instance_valid(hardpoint.weapon_instance):
			hardpoint.weapon_instance.queue_free()
			hardpoint.weapon_instance = null
		var weapon_scene_path := str(entry.get("weapon_scene", ""))
		if weapon_scene_path == "":
			hardpoint.mounted_weapon = null
			continue
		var weapon_scene := load(weapon_scene_path) as PackedScene
		hardpoint.mounted_weapon = weapon_scene
		if weapon_scene:
			hardpoint.mount_weapon_from_scene(weapon_scene)
			if is_instance_valid(hardpoint.weapon_instance) and "ammo_count" in hardpoint.weapon_instance:
				hardpoint.weapon_instance.set("ammo_count", int(entry.get("ammo_count", hardpoint.weapon_instance.get("ammo_count"))))
	var control_weapons := aircraft.find_child("ControlWeapons", true, false)
	if control_weapons:
		if "aircraft" in control_weapons and control_weapons.aircraft == null:
			control_weapons.aircraft = aircraft
		if control_weapons.has_method("find_hardpoints"):
			control_weapons.find_hardpoints()
		if control_weapons.has_method("categorize_weapons"):
			control_weapons.categorize_weapons()
		var selected_weapon_type := str(loadout_state.get("selected_weapon_type", ""))
		if selected_weapon_type != "" and "weapon_types" in control_weapons and selected_weapon_type in control_weapons.weapon_types:
			control_weapons.selected_weapon_type = selected_weapon_type
			control_weapons.selected_weapon_type_index = control_weapons.weapon_types.find(selected_weapon_type)

func _apply_ai_loadout_profile(aircraft: RigidBody3D, profile: String) -> void:
	var normalized_profile := profile.strip_edges().to_lower()
	if normalized_profile == "":
		return
	var hardpoints: Array[Hardpoint] = []
	for node in _get_all_children(aircraft):
		if node is Hardpoint:
			hardpoints.append(node as Hardpoint)
	if hardpoints.is_empty():
		return
	for i in range(hardpoints.size()):
		var hardpoint := hardpoints[i]
		var weapon_scene_path := _choose_ai_loadout_weapon_scene(hardpoint, i, normalized_profile)
		_mount_weapon_scene_on_hardpoint(hardpoint, weapon_scene_path)
	_refresh_weapon_controller_after_loadout(aircraft, normalized_profile)

func _choose_ai_loadout_weapon_scene(hardpoint: Hardpoint, hardpoint_index: int, profile: String) -> String:
	if profile == LOADOUT_INTERCEPT:
		if hardpoint_index == 0:
			return WEAPON_SCENE_20MM
		return WEAPON_SCENE_AA_MISSILE
	if profile == LOADOUT_CAP:
		var current_weapon_name := _get_hardpoint_weapon_name(hardpoint)
		if _is_gun_weapon_name(current_weapon_name):
			return ""
		if hardpoint_index == 0:
			return WEAPON_SCENE_ROCKET_POD
		return WEAPON_SCENE_20MM
	if profile == LOADOUT_STRIKE or profile == "cas":
		return WEAPON_SCENE_BOMB_RACK if hardpoint_index == 0 else WEAPON_SCENE_ROCKET_POD
	return ""

func _mount_weapon_scene_on_hardpoint(hardpoint: Hardpoint, weapon_scene_path: String) -> void:
	if hardpoint == null or weapon_scene_path == "":
		return
	var weapon_scene := load(weapon_scene_path) as PackedScene
	if weapon_scene == null:
		push_warning("[FlightDeckManager] Unable to load AI loadout weapon: %s" % weapon_scene_path)
		return
	if is_instance_valid(hardpoint.weapon_instance):
		hardpoint.weapon_instance.queue_free()
		hardpoint.weapon_instance = null
	hardpoint.mounted_weapon = weapon_scene
	hardpoint.mount_weapon_from_scene(weapon_scene)
	if is_instance_valid(hardpoint.weapon_instance) and hardpoint.weapon_instance is AAMissileLauncher:
		var launcher := hardpoint.weapon_instance as AAMissileLauncher
		launcher.max_ammo = max(launcher.max_ammo, 1)
		launcher.ammo_count = max(launcher.ammo_count, launcher.max_ammo)

func _get_hardpoint_weapon_name(hardpoint: Hardpoint) -> String:
	if hardpoint == null or not is_instance_valid(hardpoint.weapon_instance):
		return ""
	if "weapon_name" in hardpoint.weapon_instance:
		return str(hardpoint.weapon_instance.weapon_name)
	return ""

func _is_gun_weapon_name(weapon_name: String) -> bool:
	var lower_name := weapon_name.to_lower()
	return lower_name.find("autocannon") != -1 or lower_name.find("machine gun") != -1

func _refresh_weapon_controller_after_loadout(aircraft: RigidBody3D, profile: String) -> void:
	var control_weapons := aircraft.find_child("ControlWeapons", true, false)
	if not control_weapons:
		return
	if "aircraft" in control_weapons:
		control_weapons.aircraft = aircraft
	if control_weapons.has_method("find_hardpoints"):
		control_weapons.find_hardpoints()
	if control_weapons.has_method("categorize_weapons"):
		control_weapons.categorize_weapons()
	if not ("weapon_types" in control_weapons):
		return
	var preferred_type := "Bomb" if (profile == LOADOUT_STRIKE or profile == "cas") else "AAMissile"
	if profile == LOADOUT_CAP:
		preferred_type = "Autocannon"
	var selected_idx := -1
	for i in range(control_weapons.weapon_types.size()):
		var weapon_type := str(control_weapons.weapon_types[i])
		if weapon_type == preferred_type or (preferred_type == "Autocannon" and _is_gun_weapon_name(weapon_type)):
			selected_idx = i
			break
	if selected_idx == -1 and control_weapons.weapon_types.size() > 0:
		selected_idx = 0
	if selected_idx != -1:
		control_weapons.selected_weapon_type_index = selected_idx
		control_weapons.selected_weapon_type = control_weapons.weapon_types[selected_idx]

func _restore_aircraft_runtime_state_deferred(aircraft: RigidBody3D, aircraft_data: Dictionary) -> void:
	if not is_instance_valid(aircraft):
		return
	await get_tree().process_frame
	if not is_instance_valid(aircraft):
		return
	if aircraft_data.has("current_health") and "current_health" in aircraft:
		aircraft.set("current_health", float(aircraft_data.get("current_health", aircraft.get("current_health"))))
	_restore_aircraft_energy_state(aircraft, aircraft_data.get("energy_state", []))
	_restore_aircraft_loadout_state(aircraft, aircraft_data.get("loadout_state", {}))
	_apply_ai_loadout_profile(aircraft, str(aircraft_data.get("requested_ai_loadout_profile", "")))

func _extract_aircraft_data(aircraft: RigidBody3D) -> Dictionary:
	"""Extract aircraft data for storage"""
	var scene_file := aircraft.scene_file_path if aircraft.scene_file_path else ""
	var data = {
		"name": aircraft.name,
		"scene_file": scene_file,
		"scene": load(scene_file) as PackedScene if scene_file != "" else null,
		"position": aircraft.global_position,
		"rotation": aircraft.global_rotation,
		"scale": aircraft.scale,
		"current_health": aircraft.get("current_health"),
		"energy_state": _capture_aircraft_energy_state(aircraft),
		"loadout_state": _capture_aircraft_loadout_state(aircraft),
		# Store any custom properties you want to preserve
		"metadata": {}
	}

	# Copy any metadata
	for key in aircraft.get_meta_list():
		data.metadata[key] = aircraft.get_meta(key)

	return data

func _create_aircraft_at_hangar_level() -> RigidBody3D:
	"""Create aircraft at hangar level from stored data and template"""
	if stored_aircraft.is_empty():
		return null

	# Get the stored aircraft data (use first stored aircraft)
	var aircraft_data = stored_aircraft[0]  # We'll remove this after spawning
	if not _ensure_pilot_assigned_for_data(aircraft_data):
		push_warning("[FlightDeckManager] Retrieval blocked: no available pilot for aircraft.")
		return null
	if not _pending_ai_loadout_profile.is_empty():
		aircraft_data["requested_ai_loadout_profile"] = _pending_ai_loadout_profile
	stored_aircraft[0] = aircraft_data

	# Use scene embedded in data dict (e.g. Aircraft 2), otherwise fall back to template
	var scene_to_use: PackedScene = aircraft_data.get("scene", null)
	if not scene_to_use:
		var scene_file := str(aircraft_data.get("scene_file", ""))
		if scene_file != "":
			scene_to_use = load(scene_file) as PackedScene
	if not scene_to_use:
		scene_to_use = aircraft_template_scene
	if not scene_to_use:
		scene_to_use = load(DEFAULT_AIRCRAFT_SCENE_PATH)
		if not scene_to_use:
			return null


	# Instantiate new aircraft from template
	var aircraft = scene_to_use.instantiate() as RigidBody3D
	if not aircraft:
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
	_retrieval_sequence += 1
	aircraft.name = "%s_%d" % [aircraft_data.name, _retrieval_sequence]

	# Position aircraft on elevator platform at hangar level (where elevator currently is)
	var elevator_hangar_pos = elevator_pickup_marker.global_position
	elevator_hangar_pos.y = _get_elevator_platform_top_global_y(-10.0) + _get_gear_ground_offset(aircraft)
	aircraft.global_position = elevator_hangar_pos

	# Face aircraft toward deck forward (carrier's +Z) during retrieval
	var carrier_fwd := (get_parent() as Node3D).global_transform.basis.z
	aircraft.global_rotation = Vector3(0, atan2(carrier_fwd.x, carrier_fwd.z), 0)
	aircraft.scale = aircraft_data.scale
	if _is_helicopter_aircraft(aircraft):
		_straighten_retrieved_helicopter_on_deck(aircraft)

	# Restore metadata
	for key in aircraft_data.metadata:
		aircraft.set_meta(key, aircraft_data.metadata[key])
	if _is_helicopter_aircraft(aircraft):
		_straighten_retrieved_helicopter_on_deck(aircraft)
	_restore_aircraft_runtime_state_deferred.call_deferred(aircraft, aircraft_data)
	_resolve_carrier_manager()
	if not is_instance_valid(carrier_manager) or not carrier_manager.bind_pilot_to_live_aircraft(aircraft, aircraft_data):
		aircraft.queue_free()
		return null

	# Keep aircraft fully still during elevator movement.
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	return aircraft

func _spawn_tractorbots_at_aircraft(aircraft: RigidBody3D):
	"""Spawn tractorbots directly at aircraft wheel positions at hangar level"""

	var gear_colliders: Array[Node3D] = _get_launch_wheel_nodes(aircraft)
	if gear_colliders.is_empty():
		return

	# Position tractorbots directly at aircraft wheels
	for i in range(min(tractor_bots.size(), gear_colliders.size())):
		var bot = tractor_bots[i]
		var gear_collider = gear_colliders[i]
		if bot and gear_collider:
			# Position bot directly at the gear collider location
			bot.global_position = gear_collider.global_position
			bot.global_position.y = _get_elevator_platform_top_global_y(-10.0) + tractor_elevator_floor_offset_m

			# Activate bot for the aircraft
			if bot.has_method("activate"):
				var wheel_offset = gear_collider.global_position - aircraft.global_position
				bot.activate(aircraft, wheel_offset, gear_collider)
				bot.set("is_positioned", true)
			if bot.has_method("disable_movement"):
				bot.disable_movement()
	_tractorbots_in_hangar = false

func _start_elevator_sequence(aircraft: RigidBody3D):
	"""Start the elevator sequence - aircraft and tractorbots follow elevator down"""

	# Set state to STORING_IN_HANGAR so elevator signals work properly
	current_state = DeckState.STORING_IN_HANGAR
	_recovery_debug("elevator sequence started")
	_retrieval_top_handled = false

	# Ensure elevator signals are connected
	_ensure_elevator_signal_connections()

	# Keep active recovery tractorbots coupled to the aircraft during descent.
	_disable_tractor_bot_movement()

	# Start elevator moving down
	elevator.move_platform_down()

	# Start following the elevator with aircraft and tractorbots
	_follow_elevator_down(aircraft)


func _follow_elevator_down(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow the elevator down"""
	if not is_instance_valid(aircraft):
		_recovery_debug("follow elevator down skipped: invalid aircraft")
		return
	
	# Store reference to aircraft for elevator following
	_pending_store_aircraft = aircraft
	var aircraft_name := _aircraft_debug_name(aircraft)
	var last_aircraft_position := aircraft.global_position
	
	# Get initial positions relative to deck level (not elevator platform)
	var deck_height = _get_deck_height_y()
	var initial_aircraft_position = aircraft.global_position
	var active_bots: Array[Node3D] = []
	var active_bot_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot is Node3D and bool(bot.get("is_active")):
			active_bots.append(bot as Node3D)
			active_bot_offsets.append((bot as Node3D).global_position - aircraft.global_position)
	_set_manual_transport(aircraft, true)
	for bot in active_bots:
		_set_manual_transport(bot, true)
	var carrier := get_parent() as Node3D
	var aircraft_carrier_local: Vector3 = carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position
	
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
	
	# Start following the elevator platform
	while is_instance_valid(aircraft) and is_instance_valid(elevator) and not _is_elevator_physically_at_bottom():
		var elevator_top_y = _get_elevator_platform_top_global_y(-10.0)

		# Calculate aircraft position so its lowest gear is 0.2m above elevator platform
		var target_gear_height = elevator_top_y + target_gear_height_above_elevator
		var target_aircraft_y = target_gear_height - gear_offset_from_aircraft_center

		# Only update Y — carrier delta (LandCarrier._carry_deck_passengers) handles XZ
		if carrier:
			var aircraft_position := carrier.to_global(aircraft_carrier_local)
			aircraft_position.y = target_aircraft_y
			aircraft.global_position = aircraft_position
		else:
			aircraft.global_position.y = target_aircraft_y
		last_aircraft_position = aircraft.global_position
		for i in range(min(active_bots.size(), active_bot_offsets.size())):
			if is_instance_valid(active_bots[i]):
				var bot_position: Vector3 = aircraft.global_position + active_bot_offsets[i]
				bot_position.y = elevator_top_y + tractor_elevator_floor_offset_m
				active_bots[i].global_position = bot_position
		await get_tree().process_frame

	if not is_instance_valid(aircraft):
		_recovery_debug("aircraft became invalid while following elevator down name=%s last_pos=%s elevator_state=%s elevator_y=%.1f active_bots=%d" % [
			aircraft_name,
			_fmt_vec3(last_aircraft_position),
			str(elevator.current_state) if is_instance_valid(elevator) else "invalid",
			_get_elevator_platform_top_global_y(-10.0) if is_instance_valid(elevator) else NAN,
			active_bots.size(),
		])
		for bot in active_bots:
			_set_manual_transport(bot, false)
		return

	for i in range(min(active_bots.size(), active_bot_offsets.size())):
		if is_instance_valid(active_bots[i]):
			var bot_position: Vector3 = aircraft.global_position + active_bot_offsets[i]
			bot_position.y = _get_elevator_platform_top_global_y(-10.0) + tractor_elevator_floor_offset_m
			active_bots[i].global_position = bot_position
			_set_cleanup_idle_for_tractor_bot(active_bots[i])
			_set_manual_transport(active_bots[i], false)
	_set_manual_transport(aircraft, false)
	_tractorbots_in_hangar = not active_bots.is_empty()

	_recovery_debug("elevator reached bottom")

func _restore_aircraft_physics(aircraft_ref: Variant, keep_frozen: bool = false):
	"""Restore aircraft physics for launch.
	keep_frozen=true restores collisions/gravity but skips the unfreeze,
	used by the retrieval path where the aircraft is already correctly positioned."""
	if not is_instance_valid(aircraft_ref) or not (aircraft_ref is RigidBody3D):
		_recovery_debug("restore aircraft physics skipped: invalid aircraft")
		return
	var aircraft := aircraft_ref as RigidBody3D

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
	if not is_instance_valid(aircraft):
		_recovery_debug("restore aircraft physics aborted after first frame: invalid aircraft")
		return

	# Clear again after waiting
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	# Enable physics but keep aircraft frozen initially
	aircraft.set_gravity_scale(1.0)

	# Let gravity/physics state apply for a frame
	await get_tree().process_frame
	if not is_instance_valid(aircraft):
		_recovery_debug("restore aircraft physics aborted after gravity frame: invalid aircraft")
		return

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
		if aircraft.has_meta("carrier_transport_mode") and not _is_helicopter_aircraft(aircraft):
			aircraft.remove_meta("carrier_transport_mode")
		return

	# Normal path: aircraft was teleported to catapult, needs a brief unfreeze
	# so it can settle onto the deck under gravity before the catapult latches.
	aircraft.freeze = false
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	await get_tree().process_frame
	if not is_instance_valid(aircraft):
		_recovery_debug("restore aircraft physics aborted after unfreeze frame: invalid aircraft")
		return

	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO

	aircraft.collision_layer = _aircraft_original_collision_layer if _aircraft_original_collision_layer != 0 else default_layer
	aircraft.collision_mask  = _aircraft_original_collision_mask  if _aircraft_original_collision_mask  != 0 else default_mask

	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	if aircraft.has_meta("carrier_transport_mode"):
		aircraft.remove_meta("carrier_transport_mode")


func _start_retrieval_ascent_sequence(aircraft: RigidBody3D):
	"""Start the elevator ascent with aircraft and tractorbots"""
	if _is_helicopter_aircraft(aircraft):
		_straighten_retrieved_helicopter_on_deck(aircraft)

	# Tractorbots are already spawned at aircraft wheels, so just start elevator
	_spawn_tractorbots_at_aircraft(aircraft)
	_disable_tractor_bot_movement()

	# Start elevator moving up
	_retrieval_top_handled = false
	_ensure_elevator_signal_connections()
	elevator.move_platform_up()

	# Follow elevator up with aircraft and tractorbots
	_follow_elevator_up_for_retrieval(aircraft)

func _follow_elevator_up_for_retrieval(aircraft: RigidBody3D):
	"""Make aircraft and tractorbots follow the elevator up during retrieval"""
	if not is_instance_valid(aircraft):
		return

	# Disable collisions for the entire elevator ride — the aircraft passes through
	# the carrier structure and must not take damage from it.
	aircraft.collision_layer = 0
	aircraft.collision_mask = 0
	aircraft.freeze = true

	# Get initial positions relative to deck level
	var deck_height = _get_deck_height_y()
	var active_bots: Array[Node3D] = []
	var active_bot_offsets: Array[Vector3] = []
	for bot in tractor_bots:
		if bot and bot is Node3D and bool(bot.get("is_active")):
			active_bots.append(bot as Node3D)
			active_bot_offsets.append((bot as Node3D).global_position - aircraft.global_position)
	_set_manual_transport(aircraft, true)
	for bot in active_bots:
		_set_manual_transport(bot, true)
	var carrier := get_parent() as Node3D
	var aircraft_carrier_local: Vector3 = carrier.to_local(aircraft.global_position) if carrier else aircraft.global_position

	# Calculate gear offset from aircraft center using global Y (tilt-safe).
	# gear_to_body_offset = how far the aircraft body is above its lowest gear.
	var gear_colliders = _find_gear_colliders(aircraft)
	var lowest_gear_global_y := INF
	for gear in gear_colliders:
		if (gear as Node3D).global_position.y < lowest_gear_global_y:
			lowest_gear_global_y = (gear as Node3D).global_position.y
	var gear_to_body_offset := aircraft.global_position.y - lowest_gear_global_y
	var target_gear_height_above_elevator = 0.2  # 20cm above elevator platform

	# Follow until the platform is physically at top, not just state transitions.
	while is_instance_valid(aircraft) and is_instance_valid(elevator) and not _is_elevator_physically_at_top():
		var elevator_top_y = _get_elevator_platform_top_global_y(-10.0)

		# Aircraft body sits gear_to_body_offset above where the gear needs to be.
		var target_gear_height = elevator_top_y + target_gear_height_above_elevator
		var target_aircraft_y = target_gear_height + gear_to_body_offset

		# Only update Y — carrier delta (LandCarrier._carry_deck_passengers) handles XZ
		if carrier:
			var aircraft_position := carrier.to_global(aircraft_carrier_local)
			aircraft_position.y = target_aircraft_y
			aircraft.global_position = aircraft_position
		else:
			aircraft.global_position.y = target_aircraft_y
		for i in range(min(active_bots.size(), active_bot_offsets.size())):
			if is_instance_valid(active_bots[i]):
				var bot_position: Vector3 = aircraft.global_position + active_bot_offsets[i]
				bot_position.y = elevator_top_y + tractor_elevator_floor_offset_m
				active_bots[i].global_position = bot_position

		await get_tree().process_frame

	if not is_instance_valid(aircraft):
		for bot in active_bots:
			_set_manual_transport(bot, false)
		return

	for i in range(min(active_bots.size(), active_bot_offsets.size())):
		if is_instance_valid(active_bots[i]):
			var bot_position: Vector3 = aircraft.global_position + active_bot_offsets[i]
			bot_position.y = _get_elevator_platform_top_global_y(-0.5) + tractor_elevator_floor_offset_m
			active_bots[i].global_position = bot_position
			_set_manual_transport(active_bots[i], false)
	_set_manual_transport(aircraft, false)

	# Signal timing can vary (elevator_at_top/covers_opened may have fired early).
	# Force the handoff once we have physically reached top.
	if current_state == DeckState.RETRIEVING_FROM_HANGAR and not _retrieval_top_handled:
		_on_elevator_at_top()

func _complete_retrieval_sequence():
	"""Complete the retrieval by moving aircraft to launch position and restoring physics"""
	if _landing_test_active:
		if is_instance_valid(deck_aircraft):
			deck_aircraft.queue_free()
		deck_aircraft = null
		current_state = DeckState.IDLE
		return

	var aircraft = deck_aircraft
	if not is_instance_valid(aircraft):
		deck_aircraft = null
		current_state = DeckState.IDLE
		return
	if _is_helicopter_aircraft(aircraft):
		await _complete_helicopter_retrieval_sequence(aircraft)
		return

	# Move aircraft to catapult latch marker
	var target_position = Vector3.ZERO
	var launch_marker = get_tree().current_scene.find_child("catapult_latch_marker", true, false)

	if launch_marker and launch_marker is Node3D:
		target_position = (launch_marker as Node3D).global_position
	else:
		# Fallback - position forward of elevator
		target_position = elevator_pickup_marker.global_position + Vector3(0, 0, 20)

	var active_bots: Array[Node] = []
	for bot in tractor_bots:
		if bot and bool(bot.get("is_active")):
			active_bots.append(bot)
	if active_bots.is_empty():
		await _prepare_tractorbots_for_recovery_job()
		active_bots = _activate_tractor_bots(aircraft)
		if not active_bots.is_empty():
			await _wait_for_tractor_bots_positioned(active_bots)

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
	if not is_instance_valid(aircraft):
		_recovery_debug("retrieval completion aborted after restore: aircraft invalid")
		return

	# Lower the frozen aircraft so its wheels sit on the flight deck.
	# Must happen before tractor bots leave so they can support the aircraft.
	var deck_y := _get_deck_height_y()
	var landing_gear_nodes := _get_launch_wheel_nodes(aircraft)
	_settle_launch_aircraft_on_wheels(aircraft, landing_gear_nodes, deck_y)

	aircraft.set_meta("physics_ready_for_launch", true)

	# Retrieved aircraft stay AI-controlled until the player explicitly takes over.
	_configure_retrieved_aircraft_as_ai(aircraft, _retrieval_ai_land_after_launch)

	# Automatically start launch sequence
	
	request_launch_sequence(aircraft)
	_send_primary_tractorbots_to_hangar.call_deferred()


func _complete_helicopter_retrieval_sequence(aircraft: RigidBody3D) -> void:
	"""Move helicopters to a deck takeoff spot and skip the catapult launch."""
	var target_position := _get_helicopter_takeoff_position()
	if _heli_test_active:
		_log_heli_test("helicopter retrieval begin aircraft=%s pos=%s target=%s active_bots=%d" % [
			_aircraft_debug_name(aircraft),
			_fmt_vec3(aircraft.global_position) if is_instance_valid(aircraft) else "?",
			_fmt_vec3(target_position),
			tractor_bots.filter(func(bot): return bot and bool(bot.get("is_active"))).size(),
		])

	var active_bots: Array[Node] = []
	for bot in tractor_bots:
		if bot and bool(bot.get("is_active")):
			active_bots.append(bot)
	if active_bots.is_empty():
		await _prepare_tractorbots_for_recovery_job()
		if not is_instance_valid(aircraft):
			return
		active_bots = _activate_tractor_bots(aircraft)
		if not active_bots.is_empty():
			await _wait_for_tractor_bots_positioned(active_bots)

	if not is_instance_valid(aircraft):
		return
	var deck_height := _get_deck_height_y()
	var gear_colliders := _find_gear_colliders(aircraft)
	var target_gear_height := deck_height + _aircraft_lift_height
	if not gear_colliders.is_empty():
		# Use global Y so tilt doesn't corrupt the offset calculation.
		var lowest_gear_global_y := INF
		for gear in gear_colliders:
			if (gear as Node3D).global_position.y < lowest_gear_global_y:
				lowest_gear_global_y = (gear as Node3D).global_position.y
		var gear_to_body_offset := aircraft.global_position.y - lowest_gear_global_y
		var lift_aircraft_y := target_gear_height + gear_to_body_offset
		await _move_aircraft_horizontally(aircraft, Vector3(target_position.x, lift_aircraft_y, target_position.z))
	else:
		await _move_aircraft_smoothly(aircraft, target_position)

	if not is_instance_valid(aircraft):
		return
	if _heli_test_active:
		_log_heli_test("helicopter retrieval moved to deck spot aircraft=%s pos=%s" % [
			_aircraft_debug_name(aircraft),
			_fmt_vec3(aircraft.global_position),
		])
	await _restore_aircraft_physics(aircraft, true)
	if not is_instance_valid(aircraft):
		return
	var _settle_profiler_start: int = FrameProfiler.begin("FlightDeckManager.heli_retrieval_settle")
	var landing_gear_nodes := _get_launch_wheel_nodes(aircraft)
	_settle_launch_aircraft_on_wheels(aircraft, landing_gear_nodes, deck_height)
	_straighten_retrieved_helicopter_on_deck(aircraft)
	# Final safety pass: ensure no gear collider is below the deck surface.
	var heli_gear_colliders := _find_gear_colliders(aircraft)
	if not heli_gear_colliders.is_empty():
		var lowest_y := INF
		for g in heli_gear_colliders:
			var gy: float = (g as Node3D).global_position.y
			if gy < lowest_y:
				lowest_y = gy
		if lowest_y < deck_height:
			aircraft.global_position.y += deck_height - lowest_y
	FrameProfiler.end("FlightDeckManager.heli_retrieval_settle", _settle_profiler_start)

	var _ai_profiler_start: int = FrameProfiler.begin("FlightDeckManager.heli_retrieval_ai_enable")
	var heli_pilot := aircraft.find_child("HelicopterPilot", true, false)
	var ai_heli_landed := heli_pilot != null and heli_pilot.is_physics_processing()
	if not ai_heli_landed:
		_configure_retrieved_aircraft_as_player(aircraft)
	if not aircraft.is_in_group("friendlies"):
		aircraft.add_to_group("friendlies")
	if not ai_heli_landed and aircraft.is_in_group("ai_aircraft"):
		aircraft.remove_from_group("ai_aircraft")
	if aircraft.has_meta("controls_disabled"):
		aircraft.remove_meta("controls_disabled")
	if aircraft.has_meta("physics_ready_for_launch"):
		aircraft.remove_meta("physics_ready_for_launch")
	aircraft.set_meta("parking_brake", true)
	aircraft.set_meta("helicopter_deck_takeoff_ready", true)
	if aircraft.has_meta("carrier_transport_mode"):
		aircraft.remove_meta("carrier_transport_mode")
	var carrier_node := get_parent() as Node
	if carrier_node == null or not carrier_node.has_method("get_deck_reference_velocity_vector"):
		carrier_node = get_tree().get_first_node_in_group("carrier")
	var deck_velocity := Vector3.ZERO
	if carrier_node != null:
		deck_velocity = _get_node_velocity(carrier_node)
		aircraft.set_meta("helicopter_deck_reference_node", carrier_node)
		_set_aircraft_reference_node(aircraft, carrier_node)
	aircraft.freeze = true
	aircraft.linear_velocity = deck_velocity
	aircraft.angular_velocity = Vector3.ZERO
	if not ai_heli_landed:
		var ai_toggle = aircraft.find_child("AIToggle", true, false)
		if ai_toggle and ai_toggle.has_method("enable_ai"):
			ai_toggle.enable_ai()
	FrameProfiler.end("FlightDeckManager.heli_retrieval_ai_enable", _ai_profiler_start)

	current_state = DeckState.AIRCRAFT_ON_DECK
	deck_aircraft = aircraft
	if _heli_test_active:
		_log_heli_test("helicopter retrieval complete aircraft=%s freeze=%s brake=%s ready=%s transport=%s pos=%s" % [
			_aircraft_debug_name(aircraft),
			str(aircraft.freeze),
			str(bool(aircraft.get_meta("parking_brake", false))),
			str(bool(aircraft.get_meta("helicopter_deck_takeoff_ready", false))),
			str(bool(aircraft.get_meta("carrier_transport_mode", false))),
			_fmt_vec3(aircraft.global_position),
		])
	_send_primary_tractorbots_to_hangar.call_deferred()


func _straighten_retrieved_helicopter_on_deck(aircraft: RigidBody3D) -> void:
	if not is_instance_valid(aircraft):
		return
	aircraft.global_rotation = Vector3(0.0, _get_carrier_forward_yaw(), 0.0)
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO


func _get_helicopter_takeoff_position() -> Vector3:
	var carrier := get_parent() as Node3D
	if carrier == null:
		return (elevator_pickup_marker.global_position + Vector3(0, 0, 36.0)) if elevator_pickup_marker else Vector3.ZERO

	var elevator_local := Vector3.ZERO
	if elevator_pickup_marker and elevator_pickup_marker is Node3D:
		elevator_local = carrier.to_local((elevator_pickup_marker as Node3D).global_position)

	var front_local_z := 72.0
	var deck_end := carrier.get_node_or_null("DeckCenterEnd") as Node3D
	if deck_end != null:
		front_local_z = carrier.to_local(deck_end.global_position).z

	var target_local := elevator_local
	target_local.x = 0.0
	target_local.y = _get_deck_local_y()
	target_local.z = lerpf(elevator_local.z, front_local_z, 0.5)
	return carrier.to_global(target_local)


func _is_helicopter_aircraft(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if aircraft.get_meta("is_helicopter", false):
		return true
	if str(aircraft.get_meta("aircraft_role", "")).to_lower().find("helicopter") != -1:
		return true
	if aircraft.scene_file_path.to_lower().find("aircraft_9") != -1:
		return true
	return aircraft.name.to_lower().find("aircraft_9") != -1

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
	_set_manual_transport(aircraft, true)
	for bot in tractor_bots:
		if bot and bot.is_active:
			_set_manual_transport(bot, true)

	var distance = start_local.distance_to(target_local)
	var duration = distance / _aircraft_move_speed
	if _heli_test_active:
		_log_heli_test("move horizontal begin aircraft=%s dist=%.1f duration=%.1f start=%s target=%s active_bots=%d" % [
			_aircraft_debug_name(aircraft),
			distance,
			duration,
			_fmt_vec3(aircraft.global_position),
			_fmt_vec3(target_position),
			tractor_bots.filter(func(bot): return bot and bool(bot.get("is_active"))).size(),
		])


	var elapsed_time = 0.0

	while elapsed_time < duration and is_instance_valid(aircraft):
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
	if not is_instance_valid(aircraft):
		for bot in tractor_bots:
			if bot:
				_set_manual_transport(bot, false)
		return

	aircraft.global_position = carrier.to_global(target_local) if carrier else target_position
	aircraft.global_rotation = target_rotation
	if _heli_test_active:
		_log_heli_test("move horizontal complete aircraft=%s pos=%s" % [
			_aircraft_debug_name(aircraft),
			_fmt_vec3(aircraft.global_position),
		])

	# Final tractorbot positions
	for i in range(min(tractor_bots.size(), bot_offsets.size())):
		var bot = tractor_bots[i]
		if bot and bot.is_active:
			bot.global_position = aircraft.global_position + bot_offsets[i]
	for bot in tractor_bots:
		if bot:
			_set_manual_transport(bot, false)
	_set_manual_transport(aircraft, false)


func _move_tractorbots_to_staging():
	"""Move tractorbots to staging at a consistent speed, then deactivate them"""
	var primary_bots := _get_primary_tractor_bots()
	if primary_bots.is_empty():
		return
	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)
	var staging_slots := _get_primary_staging_slots_local(primary_bots.size())
	await _move_nodes_to_local_targets(primary_bots, staging_slots, _tractor_staging_speed)
	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)
	_tractorbots_in_hangar = false

func _get_primary_elevator_slots_local(count: int, platform_local_y: float) -> Array[Vector3]:
	var slots := _get_tractor_cleanup_elevator_slots_local(count)
	for i in range(slots.size()):
		var slot_local: Vector3 = slots[i]
		slot_local.y = platform_local_y
		slots[i] = slot_local
	return slots

func _wait_for_tractor_elevator_transfer() -> void:
	while _tractor_elevator_transfer_in_progress:
		await get_tree().process_frame

func _wait_for_elevator_bottom() -> void:
	while is_instance_valid(elevator) and elevator.current_state != elevator.ElevatorState.AT_BOTTOM:
		await get_tree().process_frame

func _follow_cleanup_tractors_with_elevator_up(nodes: Array[Node3D], local_slots: Array[Vector3]) -> void:
	if nodes.is_empty() or not elevator or not ("platform" in elevator):
		return
	while is_instance_valid(elevator) and not _is_elevator_physically_at_top():
		var bot_local_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
		for i in range(min(nodes.size(), local_slots.size())):
			if not is_instance_valid(nodes[i]):
				continue
			var target_local := local_slots[i]
			target_local.y = bot_local_y
			nodes[i].position = target_local
		await get_tree().process_frame
	var final_local_y := _get_elevator_platform_top_local_y(-0.5) + tractor_elevator_floor_offset_m
	for i in range(min(nodes.size(), local_slots.size())):
		if not is_instance_valid(nodes[i]):
			continue
		var final_local := local_slots[i]
		final_local.y = final_local_y
		nodes[i].position = final_local

func _prepare_tractorbots_for_recovery_job() -> void:
	_recovery_debug("preparing tractorbots for recovery job")
	await _wait_for_tractor_elevator_transfer()
	var primary_bots := _get_primary_tractor_bots()
	if primary_bots.is_empty() or not is_instance_valid(elevator_pickup_marker):
		_recovery_debug("tractor prep skipped: primary_bots=%d pickup_marker_valid=%s elevator_valid=%s" % [
			primary_bots.size(),
			str(is_instance_valid(elevator_pickup_marker)),
			str(elevator != null)
		])
		return

	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)

	var bots_need_elevator_fetch := false
	if elevator:
		var elevator_at_bottom: bool = "current_state" in elevator and elevator.current_state == elevator.ElevatorState.AT_BOTTOM
		bots_need_elevator_fetch = _tractorbots_in_hangar or (elevator_at_bottom and not _is_elevator_physically_at_top())

	var fetched_bots_from_hangar := false
	if bots_need_elevator_fetch:
		_tractor_elevator_transfer_in_progress = true
		_recovery_debug("fetching tractorbots from hangar elevator")
		if not ("current_state" in elevator and elevator.current_state == elevator.ElevatorState.AT_BOTTOM):
			if elevator.has_method("move_platform_down"):
				elevator.move_platform_down()
			await _wait_for_elevator_bottom()
		if not is_instance_valid(elevator):
			_tractor_elevator_transfer_in_progress = false
			return

		var bottom_slot_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
		var elevator_slots := _get_primary_elevator_slots_local(primary_bots.size(), bottom_slot_y)
		await _move_nodes_to_local_targets(primary_bots, elevator_slots, _tractor_staging_speed)
		if not is_instance_valid(elevator):
			_tractor_elevator_transfer_in_progress = false
			return

		if elevator.has_method("move_platform_up"):
			elevator.move_platform_up()
		await _follow_cleanup_tractors_with_elevator_up(primary_bots, elevator_slots)
		await _wait_for_elevator_top()
		_tractor_elevator_transfer_in_progress = false
		_tractorbots_in_hangar = false
		fetched_bots_from_hangar = true

	if not fetched_bots_from_hangar:
		var staging_slots := _get_primary_staging_slots_local(primary_bots.size())
		_recovery_debug("moving tractorbots to deck staging")
		await _move_nodes_to_local_targets(primary_bots, staging_slots, _tractor_staging_speed)
	else:
		_recovery_debug("tractorbots delivered by elevator; starting recovery from elevator slots")

	for bot in primary_bots:
		if bot.has_method("enable_movement"):
			bot.enable_movement()

	_tractorbots_in_hangar = false
	_recovery_debug("tractorbots ready on deck")

func _send_primary_tractorbots_to_hangar() -> void:
	if _tractor_elevator_transfer_in_progress:
		return
	if not is_instance_valid(elevator_pickup_marker) or not elevator:
		return

	var primary_bots := _get_primary_tractor_bots()
	if primary_bots.size() < PRIMARY_TRACTOR_COUNT:
		return

	_tractor_elevator_transfer_in_progress = true
	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)

	if not _is_elevator_physically_at_top():
		if elevator.has_method("move_platform_up"):
			elevator.move_platform_up()
		await _wait_for_elevator_top()
	if not is_instance_valid(elevator):
		_tractor_elevator_transfer_in_progress = false
		return

	var top_slot_y := _get_elevator_platform_top_local_y(-0.5) + tractor_elevator_floor_offset_m
	var elevator_slots := _get_primary_elevator_slots_local(primary_bots.size(), top_slot_y)
	await _move_nodes_to_local_targets(primary_bots, elevator_slots, _tractor_staging_speed)
	if not is_instance_valid(elevator):
		_tractor_elevator_transfer_in_progress = false
		return

	if elevator.has_method("move_platform_down"):
		elevator.move_platform_down()
	await _follow_cleanup_tractors_with_elevator_down(primary_bots, elevator_slots)
	await _wait_for_elevator_bottom()

	for bot in primary_bots:
		_set_cleanup_idle_for_tractor_bot(bot)

	_tractorbots_in_hangar = true
	_tractor_elevator_transfer_in_progress = false

func _set_cleanup_idle_for_tractor_bot(bot: Node3D) -> void:
	if not is_instance_valid(bot):
		return
	if bot.has_method("deactivate"):
		bot.deactivate()
	if bot.has_method("enable_movement"):
		bot.enable_movement()
	if bot.has_method("disable_movement"):
		bot.disable_movement()

func _move_nodes_to_local_targets(nodes: Array[Node3D], local_targets: Array[Vector3], speed: float) -> void:
	if nodes.is_empty() or local_targets.is_empty():
		return
	var max_distance: float = 0.0
	var start_positions: Array[Vector3] = []
	for i in range(nodes.size()):
		var node := nodes[i]
		if not is_instance_valid(node):
			start_positions.append(Vector3.ZERO)
			continue
		start_positions.append(node.position)
		if i < local_targets.size():
			max_distance = maxf(max_distance, node.position.distance_to(local_targets[i]))
	var duration: float = maxf(max_distance / maxf(speed, 0.1), 0.01)
	var elapsed: float = 0.0
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t := ease_in_out_cubic(clampf(elapsed / duration, 0.0, 1.0))
		for i in range(min(nodes.size(), local_targets.size())):
			if not is_instance_valid(nodes[i]):
				continue
			nodes[i].position = start_positions[i].lerp(local_targets[i], t)
		await get_tree().process_frame
	for i in range(min(nodes.size(), local_targets.size())):
		if not is_instance_valid(nodes[i]):
			continue
		nodes[i].position = local_targets[i]

func _follow_cleanup_tractors_with_elevator_down(nodes: Array[Node3D], local_slots: Array[Vector3]) -> void:
	if nodes.is_empty() or not elevator or not ("platform" in elevator):
		return
	while is_instance_valid(elevator) and elevator.current_state != elevator.ElevatorState.AT_BOTTOM:
		var bot_local_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
		for i in range(min(nodes.size(), local_slots.size())):
			if not is_instance_valid(nodes[i]):
				continue
			var target_local := local_slots[i]
			target_local.y = bot_local_y
			nodes[i].position = target_local
		await get_tree().process_frame
	var final_local_y := _get_elevator_platform_top_local_y(-10.0) + tractor_elevator_floor_offset_m
	for i in range(min(nodes.size(), local_slots.size())):
		if not is_instance_valid(nodes[i]):
			continue
		var final_local := local_slots[i]
		final_local.y = final_local_y
		nodes[i].position = final_local

func _wait_for_elevator_top() -> void:
	while is_instance_valid(elevator) and not _is_elevator_physically_at_top():
		await get_tree().process_frame

func _run_extra_tractor_cleanup() -> void:
	if _tractor_cleanup_batch.is_empty():
		_tractor_cleanup_batch.clear()
		_tractor_cleanup_in_progress = false
		if current_state == DeckState.TRACTOR_CLEANUP:
			current_state = DeckState.IDLE
		return

	var cleanup_batch: Array[Node3D] = _tractor_cleanup_batch.duplicate()
	for bot in cleanup_batch:
		if is_instance_valid(bot):
			bot.queue_free()

	_tractor_cleanup_batch.clear()
	_tractor_cleanup_in_progress = false
	current_state = DeckState.IDLE

func _maybe_dispatch_extra_tractor_cleanup() -> void:
	if _tractor_cleanup_in_progress or current_state != DeckState.IDLE:
		return
	var extras := _get_extra_deck_tractor_bots()
	if extras.is_empty():
		return
	var batch_size := mini(extras.size(), max(desired_deck_tractor_count, 1))
	_tractor_cleanup_batch.clear()
	for i in range(batch_size):
		_tractor_cleanup_batch.append(extras[i])
	_tractor_cleanup_in_progress = true
	current_state = DeckState.TRACTOR_CLEANUP
	_run_extra_tractor_cleanup.call_deferred()

func ease_in_out_cubic(t: float) -> float:
	"""Smooth easing function"""
	return 3.0 * t * t - 2.0 * t * t * t

# ============================================================================
# LANDING TEST MODE
# ============================================================================

func _get_all_landing_test_cleanup_aircraft() -> Array[RigidBody3D]:
	var all_aircraft: Array[RigidBody3D] = []
	var seen: Dictionary = {}
	for group_name in ["aircraft", "ai_aircraft", "friendlies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is RigidBody3D):
				continue
			var aircraft := node as RigidBody3D
			if not is_instance_valid(aircraft):
				continue
			var id := aircraft.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			all_aircraft.append(aircraft)
	return all_aircraft

func _enter_landing_test_isolation() -> void:
	_ai_launch_queue = 0
	_pending_flight_ops = null
	_pending_ai_loadout_profile = ""
	_retrieval_ai_land_after_launch = true
	_landing_test_timer = 0.0
	_landing_test_spawn_index = 0
	for aircraft in _get_all_landing_test_cleanup_aircraft():
		if _landing_test_aircraft.has(aircraft):
			continue
		print("[LandingTest] despawning non-test aircraft %s" % _aircraft_debug_name(aircraft))
		aircraft.queue_free()
	if is_instance_valid(deck_aircraft) and not _landing_test_aircraft.has(deck_aircraft):
		deck_aircraft = null
	if is_instance_valid(_pending_store_aircraft) and not _landing_test_aircraft.has(_pending_store_aircraft):
		_pending_store_aircraft = null
	_recovery_powerdown_in_progress = false
	_recovery_release_done = false
	_recovery_job_dispatched = false
	_pending_store_aircraft = null
	deck_aircraft = null
	_landing_clearance_aircraft = null
	_landing_clearance_queue.clear()
	current_state = DeckState.IDLE
	if catapult and catapult.has_method("_reset_state"):
		catapult._reset_state()

func _strip_test_aircraft_weapons(node: Node) -> void:
	if "mounted_weapon" in node:
		node.set("mounted_weapon", null)
	for child in node.get_children():
		_strip_test_aircraft_weapons(child)

func _spawn_recovery_debug_aircraft() -> void:
	if _landing_test_active:
		_landing_test_active = false
		for ac in _landing_test_aircraft:
			if is_instance_valid(ac):
				ac.queue_free()
		_landing_test_aircraft.clear()
		print("[RecoveryDebug] landing test mode OFF for single recovery spawn")

	var scene: PackedScene = aircraft_template_scene
	if not scene:
		scene = load(DEFAULT_AIRCRAFT_SCENE_PATH)
	if not scene:
		push_warning("[RecoveryDebug] Aircraft_5 scene not found")
		return

	var root: Node = get_tree().current_scene
	var carrier_node := get_tree().get_first_node_in_group("carrier") as Node3D
	if not is_instance_valid(root) or not is_instance_valid(carrier_node):
		push_warning("[RecoveryDebug] Missing scene root or carrier")
		return

	var carrier_forward := carrier_node.global_transform.basis.z
	carrier_forward.y = 0.0
	if carrier_forward.length_squared() <= 0.001:
		carrier_forward = Vector3.FORWARD
	carrier_forward = carrier_forward.normalized()

	var spawn_pos: Vector3 = carrier_node.global_position - carrier_forward * RECOVERY_DEBUG_SPAWN_DIST_M
	spawn_pos.y = carrier_node.global_position.y + RECOVERY_DEBUG_ALTITUDE_M

	var aircraft := scene.instantiate() as RigidBody3D
	if not is_instance_valid(aircraft):
		push_warning("[RecoveryDebug] Scene instantiate failed")
		return

	_recovery_debug_spawn_index += 1
	aircraft.name = "RecoveryDebug_%03d" % _recovery_debug_spawn_index
	_strip_test_aircraft_weapons(aircraft)
	root.add_child(aircraft)

	aircraft.global_position = spawn_pos
	var look_target := carrier_node.global_position
	look_target.y = spawn_pos.y
	aircraft.look_at(look_target, Vector3.UP)
	aircraft.rotate_y(PI)
	aircraft.linear_velocity = carrier_forward * LANDING_TEST_SPEED_MPS
	aircraft.angular_velocity = Vector3.ZERO

	var pilot := aircraft.find_child("AIPilot", true, false)
	if is_instance_valid(pilot) and pilot.has_method("start_straight_in_landing"):
		pilot.start_straight_in_landing()
	else:
		push_warning("[RecoveryDebug] AIPilot not found on spawned aircraft")

	var cg := aircraft.find_child("ControlLandingGear", true, false)
	if is_instance_valid(cg):
		get_tree().create_timer(0.1).timeout.connect(func():
			if not is_instance_valid(cg): return
			cg.send_to_landing_gears("stow")
			cg.send_to_tailhooks("stow")
			cg.send_to_tailhook_simple(false)
			cg.gear_down_state = false
			cg.tailhook_down_state = false
		)
		get_tree().create_timer(0.4).timeout.connect(func():
			if not is_instance_valid(cg): return
			cg.send_to_landing_gears("deploy")
			cg.send_to_tailhooks("deploy")
			cg.send_to_tailhook_simple(true)
			cg.gear_down_state = true
			cg.tailhook_down_state = true
		)
	print("[RecoveryDebug] spawned %s 1000m behind carrier at +100m, landing mode" % aircraft.name)

func _is_aircraft_eligible_for_return_command(aircraft: RigidBody3D) -> bool:
	if not is_instance_valid(aircraft):
		return false
	if aircraft == deck_aircraft or aircraft == _pending_store_aircraft:
		return false
	if aircraft.has_meta("carrier_transport_mode") and bool(aircraft.get_meta("carrier_transport_mode")):
		return false
	if aircraft.has_meta("parking_brake") and bool(aircraft.get_meta("parking_brake")):
		return false
	if aircraft.has_meta("controls_disabled") and bool(aircraft.get_meta("controls_disabled")):
		return false
	if aircraft.has_meta("arresting_engaged") and bool(aircraft.get_meta("arresting_engaged")):
		return false
	if _is_aircraft_blocking_landing_deck(aircraft):
		return false
	var pilot := aircraft.find_child("AIPilot", true, false)
	return is_instance_valid(pilot) and pilot.has_method("return_to_base")

func _command_closest_aircraft_to_return_to_base() -> void:
	var carrier := get_parent() as Node3D
	var origin: Vector3 = carrier.global_position if is_instance_valid(carrier) else Vector3.ZERO
	var best_aircraft: RigidBody3D = null
	var best_dist_sq: float = INF
	for aircraft in _get_all_aircraft_nodes():
		if not _is_aircraft_eligible_for_return_command(aircraft):
			continue
		var dist_sq: float = aircraft.global_position.distance_squared_to(origin)
		if dist_sq < best_dist_sq:
			best_aircraft = aircraft
			best_dist_sq = dist_sq
	if not is_instance_valid(best_aircraft):
		print("[FlightDeck] F3 return-to-base: no eligible AI aircraft found")
		return
	var pilot := best_aircraft.find_child("AIPilot", true, false)
	print("[FlightDeck] F3 return-to-base: commanding %s via recovery framework" % _aircraft_debug_name(best_aircraft))
	pilot.return_to_base()

func _spawn_landing_test_aircraft() -> void:
	var scene: PackedScene = aircraft_template_scene
	if not scene:
		scene = load(DEFAULT_AIRCRAFT_SCENE_PATH)
	if not scene:
		push_warning("[LandingTest] Aircraft_5 scene not found")
		return

	# Compute approach axis from waypoints; fall back to carrier orientation.
	var root: Node = get_tree().current_scene
	var carrier_node := get_tree().get_first_node_in_group("carrier") as Node3D
	if not is_instance_valid(carrier_node):
		push_warning("[LandingTest] No node in group 'carrier'")
		return

	var approach_dir := Vector3.ZERO
	var wp0 := root.find_child("approach_0", true, false) as Node3D
	var wp4 := root.find_child("approach_4", true, false) as Node3D
	if is_instance_valid(wp0) and is_instance_valid(wp4):
		var flat := wp4.global_position - wp0.global_position
		flat.y = 0.0
		if flat.length_squared() > 1.0:
			approach_dir = flat.normalized()
	if approach_dir == Vector3.ZERO:
		# Carrier's local -Z is its forward; approach comes from behind (+Z).
		approach_dir = carrier_node.global_transform.basis.z.normalized()
		approach_dir.y = 0.0
		approach_dir = approach_dir.normalized()

	# Randomise spawn: distance 1700-2300 m, lateral offset ±150 m, altitude ±60 m, speed ±15 m/s.
	var rand_dist: float  = LANDING_TEST_SPAWN_DIST_M + randf_range(-300.0, 300.0)
	var rand_alt: float   = LANDING_TEST_ALTITUDE_M   + randf_range(-60.0,  60.0)
	var rand_speed: float = LANDING_TEST_SPEED_MPS    + randf_range(-15.0,  15.0)
	var lateral_dir := approach_dir.rotated(Vector3.UP, PI * 0.5)
	var rand_lateral: float = randf_range(-150.0, 150.0)
	# Randomise heading ±20° off the approach axis
	var rand_yaw: float = randf_range(-20.0, 20.0)
	var rand_heading_dir := approach_dir.rotated(Vector3.UP, deg_to_rad(rand_yaw))

	var spawn_pos: Vector3 = carrier_node.global_position \
		- approach_dir * rand_dist \
		+ lateral_dir  * rand_lateral
	spawn_pos.y = carrier_node.global_position.y + rand_alt

	# Instantiate and place.
	var aircraft := scene.instantiate() as RigidBody3D
	if not is_instance_valid(aircraft):
		push_warning("[LandingTest] Scene instantiate failed")
		return
	_landing_test_spawn_index += 1
	var aircraft_name := "LandingTest_%03d" % _landing_test_spawn_index
	aircraft.name = aircraft_name
	aircraft.set_meta("landing_test_aircraft", true)
	# Clear weapons before entering the tree so Hardpoint._ready() skips mounting.
	_strip_test_aircraft_weapons(aircraft)
	root.add_child(aircraft)

	aircraft.global_position = spawn_pos
	# Face roughly toward the carrier (heading may be offset by rand_yaw).
	var look_target := carrier_node.global_position
	look_target.y = spawn_pos.y
	aircraft.look_at(look_target, Vector3.UP)
	aircraft.rotate_y(PI)  # Aircraft_5's nose is +Z; look_at aims -Z, so flip 180°.
	aircraft.rotate_y(deg_to_rad(rand_yaw))
	aircraft.linear_velocity = rand_heading_dir * rand_speed
	aircraft.angular_velocity = Vector3.ZERO

	# Start straight-in final approach (skips the downwind/base circuit).
	var pilot := aircraft.find_child("AIPilot", true, false)
	if is_instance_valid(pilot) and pilot.has_method("start_straight_in_landing"):
		pilot.start_straight_in_landing()
	else:
		push_warning("[LandingTest] AIPilot not found on spawned aircraft")

	# Cycle gear stow→deploy so the tailhook ends up deployed regardless of setup() order.
	var cg := aircraft.find_child("ControlLandingGear", true, false)
	if is_instance_valid(cg):
		get_tree().create_timer(0.1).timeout.connect(func():
			if not is_instance_valid(cg): return
			cg.send_to_landing_gears("stow")
			cg.send_to_tailhooks("stow")
			cg.send_to_tailhook_simple(false)
			cg.gear_down_state = false
			cg.tailhook_down_state = false
		)
		get_tree().create_timer(0.4).timeout.connect(func():
			if not is_instance_valid(cg): return
			cg.send_to_landing_gears("deploy")
			cg.send_to_tailhooks("deploy")
			cg.send_to_tailhook_simple(true)
			cg.gear_down_state = true
			cg.tailhook_down_state = true
		)

	_landing_test_aircraft.append(aircraft)
	print("[LandingTest] spawned %s at pos=(%.0f, %.0f, %.0f) approach_dir=(%.2f,%.0f,%.2f)" % [
		aircraft.name,
		spawn_pos.x, spawn_pos.y, spawn_pos.z,
		approach_dir.x, approach_dir.y, approach_dir.z])


func _toggle_heli_test_mode() -> void:
	_heli_test_active = not _heli_test_active

	if not _heli_test_active:
		_log_heli_test("mode OFF")
		FrameProfiler.set_enabled(false, "heli test off")
		# Despawn all live helicopters
		for node in get_tree().get_nodes_in_group("aircraft"):
			if node is RigidBody3D and _is_helicopter_aircraft(node as RigidBody3D):
				(node as RigidBody3D).queue_free()
		var poi_mgr_off := get_node_or_null("/root/POIManager")
		if poi_mgr_off and "reveals_disabled" in poi_mgr_off:
			poi_mgr_off.set("reveals_disabled", false)
		var dnc_off := get_tree().current_scene.find_child("DayNightCycle", true, false) if get_tree().current_scene else null
		if dnc_off and "freeze_daytime" in dnc_off:
			dnc_off.set("freeze_daytime", false)
			
		if is_instance_valid(_heli_ui_canvas):
			_heli_ui_canvas.queue_free()
			_heli_ui_canvas = null
			_heli_ui_label = null
			
		return

	# Disable other test modes
	if _landing_test_active:
		_landing_test_active = false
		for ac in _landing_test_aircraft:
			if is_instance_valid(ac):
				ac.queue_free()
		_landing_test_aircraft.clear()
	FrameProfiler.set_enabled(true, "heli test")
	_disable_enemies_for_heli_test()

	# Despawn all non-helicopter aircraft across all relevant groups
	var seen: Array[RigidBody3D] = []
	for group in ["aircraft", "ai_aircraft", "friendlies", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			if not (node is RigidBody3D):
				continue
			var ac := node as RigidBody3D
			if seen.has(ac):
				continue
			seen.append(ac)
			if _is_helicopter_aircraft(ac):
				continue
			if ac == deck_aircraft:
				deck_aircraft = null
			ac.queue_free()

	# Clear any queued/stored fixed-wing aircraft so they don't pop out of the hangar
	stored_aircraft.clear()
	_pending_store_aircraft = null
	_landing_clearance_aircraft = null
	_landing_clearance_queue.clear()
	current_state = DeckState.IDLE

	# Wipe helicopter logs so this test session starts clean, including retrieved-name variants.
	var user_dir := DirAccess.open("user://")
	if user_dir:
		user_dir.list_dir_begin()
		var filename := user_dir.get_next()
		while not filename.is_empty():
			if not user_dir.current_is_dir() and filename.begins_with("heli_crash_report") and filename.ends_with(".log"):
				user_dir.remove(filename)
			filename = user_dir.get_next()
		user_dir.list_dir_end()
	var aggregate_log := FileAccess.open("user://heli_crash_report.log", FileAccess.WRITE)
	if aggregate_log:
		aggregate_log.store_line("=" .repeat(72))
		aggregate_log.store_line("HELICOPTER TEST LOG")
		aggregate_log.store_line("Started: %s" % Time.get_datetime_string_from_system())
		aggregate_log.store_line("Includes compact flight summaries from Aircraft_9/Aircraft_10/Aircraft_11 helicopter pilots.")
		aggregate_log.store_line("Crash/fault reports include the last few seconds of HELI_AI output.")
		aggregate_log.store_line("=" .repeat(72))
		aggregate_log.store_line("")
		aggregate_log.close()
	_log_heli_test("mode ON")
	_log_heli_test("crash logs cleared: user://heli_crash_report.log")

	var poi_mgr := get_node_or_null("/root/POIManager")
	if poi_mgr and "reveals_disabled" in poi_mgr:
		poi_mgr.set("reveals_disabled", true)
	var dnc := get_tree().current_scene.find_child("DayNightCycle", true, false) if get_tree().current_scene else null
	if dnc and "freeze_daytime" in dnc:
		dnc.set("freeze_daytime", true)

	_heli_test_timer = 0.0  # trigger first spawn immediately
	_heli_test_spawn_index = 0

	_heli_test_start_time_msec = Time.get_ticks_msec()
	for key in _heli_test_stats.keys():
		_heli_test_stats[key] = {"spawned": 0, "lz": 0, "carrier": 0, "crash": 0}

	_heli_ui_canvas = CanvasLayer.new()
	_heli_ui_canvas.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bg.offset_left = 20.0
	bg.offset_top = 20.0
	bg.offset_right = 450.0
	bg.offset_bottom = 150.0
	_heli_ui_canvas.add_child(bg)
	_heli_ui_label = Label.new()
	_heli_ui_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_heli_ui_label.offset_left = 10.0
	_heli_ui_label.offset_top = 10.0
	_heli_ui_label.add_theme_font_override("font", ThemeDB.fallback_font)
	bg.add_child(_heli_ui_label)
	add_child(_heli_ui_canvas)


func _disable_enemies_for_heli_test() -> void:
	var enemy_ops := get_node_or_null("/root/EnemyOpsManager")
	if enemy_ops and enemy_ops.has_method("disable_for_heli_test"):
		enemy_ops.disable_for_heli_test()

	var base_manager := get_node_or_null("/root/EnemyBaseManager")
	if base_manager and base_manager.has_method("disable_for_heli_test"):
		base_manager.disable_for_heli_test()

	for spawner in get_tree().get_nodes_in_group("enemy_aircraft_spawner"):
		if spawner and spawner.has_method("disable_for_heli_test"):
			spawner.disable_for_heli_test()
	var scene_root := get_tree().current_scene
	if scene_root:
		var named_spawner := scene_root.find_child("EnemyAircraftSpawner", true, false)
		if named_spawner and named_spawner.has_method("disable_for_heli_test"):
			named_spawner.disable_for_heli_test()

	var cleaned := 0
	var seen: Dictionary = {}
	for group_name in ["enemies", "enemy_bases", "gun_emplacements", "ground_vehicles", "ai_aircraft"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Node) or not is_instance_valid(node):
				continue
			var id := (node as Node).get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			if not _is_enemy_cleanup_node(node as Node):
				continue
			(node as Node).queue_free()
			cleaned += 1
	_log_heli_test("enemies disabled; cleaned %d live enemy nodes" % cleaned)


func _is_enemy_cleanup_node(node: Node) -> bool:
	return node.is_in_group("enemies") \
			or node.is_in_group("enemy_bases") \
			or node.is_in_group("team_2")


func _spawn_heli_test_aircraft() -> void:
	var roster: Array[String] = ["Aircraft_9", "Aircraft_10", "Aircraft_11"]
	var aircraft_name: String = roster[_heli_test_spawn_index % roster.size()]
	_heli_test_spawn_index += 1
	var scene: PackedScene
	match aircraft_name:
		"Aircraft_9":  scene = aircraft_9_scene
		"Aircraft_10": scene = aircraft_10_scene
		"Aircraft_11": scene = aircraft_11_scene
	if not scene:
		scene = load("res://Aircraft/%s.tscn" % aircraft_name)
	if not scene:
		push_warning("[HeliTest] %s.tscn not found" % aircraft_name)
		return
	_queue_aircraft_scene_for_retrieval(aircraft_name, scene)
	record_heli_stat(aircraft_name, "spawned")
	_log_heli_test("queued %s retrieval" % aircraft_name)


func _log_heli_test(message: String) -> void:
	var line := "[HeliTest] %s" % message
	print(line)


# Returns how far the aircraft origin sits above its lowest gear contact point.
# Add this to any Y placement so gear rests on the surface rather than clipping through it.
# Falls back to 0.2 if no "gear_ground_point" group nodes are found on the aircraft.
func _get_gear_ground_offset(aircraft: RigidBody3D) -> float:
	var lowest_y: float = INF
	for child in aircraft.find_children("*", "Node3D", true, false):
		var n := child as Node3D
		if n.is_in_group("gear_ground_point"):
			# Convert to aircraft-local space to get the Y offset from the body origin
			var local_y: float = aircraft.to_local(n.global_position).y
			lowest_y = minf(lowest_y, local_y)
	if lowest_y == INF or lowest_y >= 0.0:
		return 0.2
	return -lowest_y
