extends Node3D
class_name VehicleBayManager

## Manages ground vehicle deployment and retrieval from the carrier's vehicle bay.

signal vehicle_deployed(vehicle: Node3D)
signal platoon_deployed(platoon: GroundVehiclePlatoon)
signal vehicle_retrieved(vehicle: Node3D)
signal platoon_retrieved()

@export var vehicle_scene: PackedScene
@export var max_bay_capacity: int = 16
@export var deploy_interval_s: float = 3.0
@export var retrieve_interval_s: float = 3.0
const PLATOON_SIZE: int = 4

enum BayState { IDLE, DEPLOYING, RETRIEVING }
var state: BayState = BayState.IDLE

var _carrier: LandCarrier
var _ramp: VehicleRamp

# Deployment
var _deploy_queue: int = 0
var _deploy_timer: float = 0.0
var _current_platoon: GroundVehiclePlatoon = null
var _deploy_pending_vehicles: int = 0  # vehicles still on ramp/bay

# Retrieval
var _retrieve_vehicles: Array[Node3D] = []  # vehicles ordered to retrieve
var _retrieve_timer: float = 0.0

# Bay storage
var stored_vehicles: int = 0

func _unhandled_input(event: InputEvent) -> void:
	return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			var gom := _get_ground_ops()
			if gom:
				for pname in gom.PLATOON_NAMES:
					var p: GroundVehiclePlatoon = gom.platoons[pname]
					if p.get_members().is_empty():
						gom.deploy(pname)
						break
			else:
				deploy_platoon()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_B:
			var gom := _get_ground_ops()
			if gom:
				# Retrieve the last deployed platoon that has members
				for i in range(gom.PLATOON_NAMES.size() - 1, -1, -1):
					var pname: String = gom.PLATOON_NAMES[i]
					var p: GroundVehiclePlatoon = gom.platoons[pname]
					if not p.get_members().is_empty():
						gom.retrieve(pname)
						break
			get_viewport().set_input_as_handled()

func _ready() -> void:
	_carrier = get_parent() as LandCarrier
	if not _carrier:
		push_warning("VehicleBayManager: Parent is not LandCarrier")
		return
	call_deferred("_find_ramp")

	if not vehicle_scene:
		vehicle_scene = load("res://GroundVehicle/vehicle_friendly_light.tscn")

	stored_vehicles = max_bay_capacity

func _find_ramp() -> void:
	if _carrier:
		_ramp = _carrier.vehicle_ramp as VehicleRamp

func _get_ground_ops() -> Node:
	return get_tree().root.get_node_or_null("GroundOpsManager")

func _physics_process(delta: float) -> void:
	match state:
		BayState.DEPLOYING:
			if _deploy_queue <= 0:
				_finish_deployment()
				return
			_deploy_timer -= delta
			if _deploy_timer <= 0.0:
				_spawn_next_vehicle()
		BayState.RETRIEVING:
			_process_retrieval(delta)

# ── Deploy ───────────────────────────────────────────────────────────────────

func deploy_platoon() -> void:
	var p := GroundVehiclePlatoon.new()
	p.name = "VehiclePlatoon_anon"
	p.team = 1
	get_tree().current_scene.add_child(p)
	p.set_protect_node(_carrier, 250.0)
	deploy_platoon_for(p)

func deploy_platoon_for(platoon: GroundVehiclePlatoon) -> void:
	var count: int = mini(PLATOON_SIZE, stored_vehicles)
	if count <= 0:
		push_warning("VehicleBayManager: No vehicles in bay to deploy")
		return
	if not _ramp:
		_find_ramp()
	if not _ramp:
		push_warning("VehicleBayManager: No ramp found")
		return

	if _ramp.is_stowed():
		_ramp.deploy()

	_current_platoon = platoon
	_deploy_queue = count
	_deploy_pending_vehicles = 0
	_deploy_timer = 2.0
	state = BayState.DEPLOYING
	print("[VehicleBay] Deploying %d vehicles for %s" % [count, platoon.name])

func _spawn_next_vehicle() -> void:
	if not vehicle_scene or not _ramp or not _carrier:
		_deploy_queue = 0
		return
	if not _ramp.is_deployed():
		# A queued platoon can be accepted while the previous platoon's ramp is
		# still stowing. Once it reaches STOWED, start the next deployment instead
		# of waiting forever for a ramp nobody has told to open again.
		if _ramp.is_stowed():
			_ramp.deploy()
		_deploy_timer = 0.5
		return
	if stored_vehicles <= 0:
		_deploy_queue = 0
		return

	var vehicle: Node3D = vehicle_scene.instantiate()
	get_tree().current_scene.add_child(vehicle)

	# Assign to platoon immediately so the vehicle has an objective when deploy ends
	if _current_platoon and is_instance_valid(_current_platoon) and vehicle.has_method("assign_platoon"):
		vehicle.assign_platoon(_current_platoon)

	var spawn_local: Vector3 = _ramp.get_bay_spawn_local()
	var hinge_local: Vector3 = _ramp.get_hinge_local()
	vehicle.start_deploy(_carrier, spawn_local, hinge_local.z)

	if vehicle.has_signal("deploy_complete"):
		vehicle.deploy_complete.connect(_on_vehicle_deployed, CONNECT_ONE_SHOT)

	_deploy_queue -= 1
	_deploy_pending_vehicles += 1
	_deploy_timer = deploy_interval_s
	stored_vehicles -= 1
	print("[VehicleBay] Vehicle spawned, %d remaining in queue, %d in bay" % [_deploy_queue, stored_vehicles])

func _on_vehicle_deployed(vehicle: Node3D) -> void:
	_deploy_pending_vehicles -= 1
	emit_signal("vehicle_deployed", vehicle)
	print("[VehicleBay] Vehicle deployed at %s" % str(vehicle.global_position))

func _finish_deployment() -> void:
	if _deploy_pending_vehicles > 0:
		return  # Wait for all vehicles to clear the ramp
	state = BayState.IDLE
	if _current_platoon and is_instance_valid(_current_platoon):
		emit_signal("platoon_deployed", _current_platoon)
		print("[VehicleBay] Platoon %s fully deployed" % _current_platoon.name)
	_current_platoon = null
	_stow_ramp()

# ── Retrieve ─────────────────────────────────────────────────────────────────

## Retrieve a list of vehicles back into the bay.
func retrieve_vehicles(vehicles: Array[Node3D]) -> void:
	if vehicles.is_empty():
		return
	if not _ramp:
		_find_ramp()
	if not _ramp:
		push_warning("VehicleBayManager: No ramp found")
		return

	# Rally point in carrier-local space: 50m behind the hinge (-Z)
	var hinge_local: Vector3 = _ramp.get_hinge_local()
	var bay_local: Vector3 = _ramp.get_bay_spawn_local()
	var rally_local: Vector3 = Vector3(0.0, hinge_local.y, hinge_local.z - 50.0)

	# Collect valid vehicles first so we can pass the full sibling list
	var valid_vehicles: Array[Node3D] = []
	for v in vehicles:
		if v and is_instance_valid(v) and v.has_method("start_retrieve"):
			valid_vehicles.append(v)
		else:
			print("[VehicleBay] Skipping invalid vehicle in retrieve list")

	print("[VehicleBay] %d valid vehicles out of %d passed" % [valid_vehicles.size(), vehicles.size()])

	# Tell all vehicles to rally simultaneously
	for v in valid_vehicles:
		v.start_retrieve(_carrier, rally_local, hinge_local.z, bay_local.z, hinge_local.y, valid_vehicles)
		_retrieve_vehicles.append(v)

	state = BayState.RETRIEVING
	_retrieve_timer = 0.0
	print("[VehicleBay] Retrieving %d vehicles" % _retrieve_vehicles.size())

func _process_retrieval(delta: float) -> void:
	# Clean dead vehicles from queue
	_retrieve_vehicles = _retrieve_vehicles.filter(func(v): return v and is_instance_valid(v))

	# No vehicles left — done
	if _retrieve_vehicles.is_empty():
		state = BayState.IDLE
		emit_signal("platoon_retrieved")
		print("[VehicleBay] All vehicles retrieved")
		_stow_ramp()
		return

	# Deploy ramp once a vehicle is waiting at the rally point
	if _ramp and _ramp.is_stowed():
		for v in _retrieve_vehicles:
			if v.has_method("is_waiting_for_ramp") and v.is_waiting_for_ramp():
				_ramp.deploy()
				_retrieve_timer = 2.0  # Wait for ramp to finish deploying
				print("[VehicleBay] Vehicle at rally — deploying ramp")
				break
		return

	# Wait for interval timer
	if _retrieve_timer > 0.0:
		_retrieve_timer -= delta
		return

	# Find next vehicle that's waiting at rally
	if not _ramp or not _ramp.is_deployed():
		return  # Wait for ramp

	for v in _retrieve_vehicles:
		if v.has_method("is_waiting_for_ramp") and v.is_waiting_for_ramp():
			v.begin_ramp_ascent()
			_retrieve_timer = retrieve_interval_s
			if v.has_signal("retrieve_complete"):
				v.retrieve_complete.connect(_on_vehicle_retrieved.bind(v), CONNECT_ONE_SHOT)
			print("[VehicleBay] Vehicle ascending ramp")
			return

func _on_vehicle_retrieved(vehicle: Node3D) -> void:
	_retrieve_vehicles.erase(vehicle)
	stored_vehicles += 1
	emit_signal("vehicle_retrieved", vehicle)
	print("[VehicleBay] Vehicle stored, %d in bay" % stored_vehicles)

func _stow_ramp() -> void:
	if _ramp and _ramp.is_deployed():
		_ramp.stow()
		print("[VehicleBay] Stowing ramp")


func capture_save_state() -> Dictionary:
	return {"stored_vehicles": stored_vehicles}


func restore_save_state(save_state: Dictionary) -> bool:
	if save_state.is_empty():
		return false
	stored_vehicles = clampi(int(save_state.get("stored_vehicles", max_bay_capacity)), 0, max_bay_capacity)
	state = BayState.IDLE
	_deploy_queue = 0
	_deploy_pending_vehicles = 0
	_current_platoon = null
	_retrieve_vehicles.clear()
	return true
