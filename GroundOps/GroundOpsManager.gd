extends Node

const FrameProfiler: Script = preload("res://Debug/FrameProfiler.gd")

## Ground Operations Manager — autoload singleton.
##
## Manages four named platoons (Ember, Ferret, Grizzly, Hammer).
## Platoons deploy from the carrier vehicle bay and operate as cohesive units.
## Vehicles within a platoon stay 30-80m from each other and hold position
## when they have no active orders.
##
## Usage:
##   GroundOpsManager.order_move("Ember", target_position)
##   GroundOpsManager.order_attack("Ferret", target_node)
##   GroundOpsManager.order_protect("Grizzly", carrier_node)
##   GroundOpsManager.order_escort("Hammer")
##   GroundOpsManager.order_rtb("Hammer")
##   GroundOpsManager.deploy("Ember")

const PLATOON_NAMES := ["Ember", "Ferret", "Grizzly", "Hammer"]

@export var debug_print: bool = true
@export var maintain_carrier_escort: bool = true
@export var carrier_escort_min_vehicles: int = 2
@export var carrier_escort_desired_vehicles: int = 4
@export var carrier_escort_check_interval_s: float = 5.0
@export var carrier_escort_distance_m: float = 100.0

var platoons: Dictionary = {}  # name → GroundVehiclePlatoon

var _carrier: Node3D = null
var _vehicle_bay: VehicleBayManager = null
var _escort_check_timer_s: float = 0.0

# Deploy queue — platoon names waiting to be deployed
var _deploy_queue: Array[String] = []
var _deploying_platoon_name: String = ""

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	for pname in PLATOON_NAMES:
		var p := GroundVehiclePlatoon.new()
		p.name = "Platoon_" + pname
		p.platoon_id = pname
		p.team = 1
		# Tighter cohesion: 30-80m spacing
		p.protect_slot_radius_m = 60.0
		p.attack_slot_radius_m = 80.0
		add_child(p)
		platoons[pname] = p
	print("[GroundOps] Ready — platoons: %s" % ", ".join(PLATOON_NAMES))

func _process(delta: float) -> void:
	var _profiler_start: int = FrameProfiler.begin("GroundOpsManager.process")
	_process_deploy_queue()
	if maintain_carrier_escort:
		_escort_check_timer_s -= delta
		if _escort_check_timer_s <= 0.0:
			_escort_check_timer_s = carrier_escort_check_interval_s
			_ensure_carrier_escort()
	FrameProfiler.end("GroundOpsManager.process", _profiler_start)

# ── Carrier / Bay references ─────────────────────────────────────────────────

func _refresh_carrier() -> void:
	if _carrier and is_instance_valid(_carrier):
		return
	var carriers := get_tree().get_nodes_in_group("carrier")
	_carrier = carriers[0] if not carriers.is_empty() else null

func _refresh_vehicle_bay() -> void:
	if _vehicle_bay and is_instance_valid(_vehicle_bay):
		return
	_refresh_carrier()
	if _carrier and _carrier is LandCarrier:
		_vehicle_bay = (_carrier as LandCarrier).vehicle_bay as VehicleBayManager

# ── Deploy ───────────────────────────────────────────────────────────────────

## Deploy a platoon by name from the vehicle bay.
func deploy(platoon_name: String) -> void:
	if platoon_name not in platoons:
		push_warning("[GroundOps] Unknown platoon: %s" % platoon_name)
		return
	var p: GroundVehiclePlatoon = platoons[platoon_name]
	if p.get_members().size() > 0:
		if debug_print:
			print("[GroundOps] %s already has %d members, skipping deploy" % [platoon_name, p.get_members().size()])
		return
	if platoon_name in _deploy_queue or _deploying_platoon_name == platoon_name:
		return
	_deploy_queue.append(platoon_name)
	if debug_print:
		print("[GroundOps] %s queued for deployment" % platoon_name)

func _process_deploy_queue() -> void:
	if _deploy_queue.is_empty():
		return
	_refresh_vehicle_bay()
	if not _vehicle_bay:
		return
	# Only deploy one platoon at a time
	if _vehicle_bay.state != VehicleBayManager.BayState.IDLE:
		return

	var pname: String = _deploy_queue.pop_front()
	_deploying_platoon_name = pname
	var p: GroundVehiclePlatoon = platoons[pname]

	# Default undeployed platoons escort the carrier.
	_refresh_carrier()
	if _carrier and not p.has_active_objective():
		p.set_escort_carrier(_carrier, 100.0)

	# Tell the bay to deploy, and we'll assign vehicles to this platoon
	_vehicle_bay.deploy_platoon_for(p)
	if not _vehicle_bay.platoon_deployed.is_connected(_on_platoon_deployed):
		_vehicle_bay.platoon_deployed.connect(_on_platoon_deployed, CONNECT_ONE_SHOT)
	if debug_print:
		print("[GroundOps] Deploying %s — rally 100m behind carrier" % pname)

func _on_platoon_deployed(platoon: GroundVehiclePlatoon) -> void:
	if debug_print:
		print("[GroundOps] %s deployed with %d vehicles" % [_deploying_platoon_name, platoon.get_members().size()])
	# Default to carrier escort only if the player/AI has not already assigned a task.
	_refresh_carrier()
	if _carrier and not platoon.has_active_objective():
		platoon.set_escort_carrier(_carrier, 100.0)
		if debug_print:
			print("[GroundOps] %s — defaulting to carrier escort" % _deploying_platoon_name)
	_deploying_platoon_name = ""

# ── Orders ───────────────────────────────────────────────────────────────────

## Move platoon to a world position.
func order_move(platoon_name: String, target: Vector3) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	p.set_move_objective(target)
	_ensure_platoon_deployed(platoon_name, p)
	if debug_print:
		print("[GroundOps] %s — move to %s" % [platoon_name, str(target)])

## Attack a specific node (enemy position, structure, etc).
func order_attack(platoon_name: String, target_node: Node3D, radius_m: float = 300.0) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	p.set_attack_node(target_node, radius_m)
	_ensure_platoon_deployed(platoon_name, p)
	if debug_print:
		print("[GroundOps] %s — attack %s" % [platoon_name, target_node.name])

func order_attack_position(platoon_name: String, target_position: Vector3, radius_m: float = 300.0) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	p.set_attack_position(target_position, radius_m)
	_ensure_platoon_deployed(platoon_name, p)
	if debug_print:
		print("[GroundOps] %s — attack position %s" % [platoon_name, str(target_position)])

## Protect a node (carrier, position, etc).
func order_protect(platoon_name: String, target_node: Node3D, radius_m: float = 250.0) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	p.set_protect_node(target_node, radius_m)
	_ensure_platoon_deployed(platoon_name, p)
	if debug_print:
		print("[GroundOps] %s — protect %s" % [platoon_name, target_node.name])

func order_protect_position(platoon_name: String, target_position: Vector3, radius_m: float = 250.0) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	p.set_protect_position(target_position, radius_m)
	_ensure_platoon_deployed(platoon_name, p)
	if debug_print:
		print("[GroundOps] %s — protect position %s" % [platoon_name, str(target_position)])

## Escort the carrier — vehicles form up at corners and hold position.
func order_escort(platoon_name: String, distance_m: float = 100.0) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	_refresh_carrier()
	if not _carrier:
		push_warning("[GroundOps] No carrier found for escort order")
		return
	p.set_escort_carrier(_carrier, distance_m)
	_ensure_platoon_deployed(platoon_name, p)
	if debug_print:
		print("[GroundOps] %s — escort carrier at %.0fm" % [platoon_name, distance_m])

## Return to base: recall a deployed platoon to a carrier-side rally area.
func order_rtb(platoon_name: String, distance_m: float = 90.0) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	_refresh_carrier()
	if not _carrier:
		push_warning("[GroundOps] No carrier found for RTB order")
		return
	if not p.has_members():
		if debug_print:
			print("[GroundOps] %s has no deployed vehicles to return" % platoon_name)
		return
	p.set_return_to_base(_carrier, distance_m)
	if debug_print:
		print("[GroundOps] %s - return to base" % platoon_name)

## High-level request: find or deploy a platoon to escort the carrier.
## Prefers a deployed platoon not already escorting. If none available, deploys one.
func request_escort() -> void:
	_refresh_carrier()
	if not _carrier:
		push_warning("[GroundOps] No carrier found for escort request")
		return

	# 1. Find a deployed platoon that isn't already escorting
	for pname in PLATOON_NAMES:
		var p: GroundVehiclePlatoon = platoons[pname]
		if p.get_members().size() > 0 and p.objective_type != GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER:
			order_escort(pname)
			return

	# 2. Already escorting? Nothing to do
	for pname in PLATOON_NAMES:
		var p: GroundVehiclePlatoon = platoons[pname]
		if p.get_members().size() > 0 and p.objective_type == GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER:
			if debug_print:
				print("[GroundOps] %s is already escorting" % pname)
			return

	# 3. No deployed platoons — deploy one and it will default to escort
	for pname in PLATOON_NAMES:
		var p: GroundVehiclePlatoon = platoons[pname]
		if p.get_members().is_empty() and pname not in _deploy_queue and _deploying_platoon_name != pname:
			deploy(pname)
			if debug_print:
				print("[GroundOps] Deploying %s for carrier escort" % pname)
			return

	if debug_print:
		print("[GroundOps] No platoons available for escort")

## Clear orders — platoon holds position.
func _ensure_carrier_escort() -> void:
	_refresh_carrier()
	if not _carrier:
		return
	var desired_count: int = maxi(carrier_escort_desired_vehicles, carrier_escort_min_vehicles)
	var escort_count: int = _count_escort_vehicles()
	if escort_count >= desired_count:
		return
	if _has_pending_escort_deploy():
		return

	var undeployed := _find_undeployed_platoon_name()
	if undeployed != "":
		var p: GroundVehiclePlatoon = platoons[undeployed]
		p.set_escort_carrier(_carrier, carrier_escort_distance_m)
		deploy(undeployed)
		if debug_print:
			print("[GroundOps] Maintaining carrier escort: deploying %s (%d/%d vehicles)" % [undeployed, escort_count, desired_count])
		return

	if escort_count >= carrier_escort_min_vehicles:
		return

	var fallback := _find_reassignable_platoon_name()
	if fallback != "":
		order_escort(fallback, carrier_escort_distance_m)
		if debug_print:
			print("[GroundOps] Maintaining minimum escort: reassigning %s (%d/%d vehicles)" % [fallback, escort_count, carrier_escort_min_vehicles])

func _count_escort_vehicles() -> int:
	var count: int = 0
	for pname in PLATOON_NAMES:
		var p: GroundVehiclePlatoon = platoons[pname]
		if p.objective_type == GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER:
			count += p.get_members().size()
	return count

func _has_pending_escort_deploy() -> bool:
	if _deploying_platoon_name != "":
		var deploying: GroundVehiclePlatoon = platoons.get(_deploying_platoon_name, null)
		if deploying and deploying.objective_type == GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER:
			return true
	for pname in _deploy_queue:
		var p: GroundVehiclePlatoon = platoons.get(pname, null)
		if p and p.objective_type == GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER:
			return true
	return false

func _find_undeployed_platoon_name() -> String:
	for pname in PLATOON_NAMES:
		var p: GroundVehiclePlatoon = platoons[pname]
		if p.has_members():
			continue
		if pname in _deploy_queue or _deploying_platoon_name == pname:
			continue
		return pname
	return ""

func _find_reassignable_platoon_name() -> String:
	for pname in PLATOON_NAMES:
		var p: GroundVehiclePlatoon = platoons[pname]
		if not p.has_members():
			continue
		if p.objective_type == GroundVehiclePlatoon.ObjectiveType.ESCORT_CARRIER:
			continue
		if p.objective_type in [GroundVehiclePlatoon.ObjectiveType.NONE, GroundVehiclePlatoon.ObjectiveType.RETURN_TO_BASE]:
			return pname
	return ""

func order_hold(platoon_name: String) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	p.objective_type = GroundVehiclePlatoon.ObjectiveType.NONE
	p.protected_node = null
	p.attack_node = null
	p.escort_node = null
	# Clear member waypoints so they stop moving
	for member in p.get_members():
		if member.has_method("set_patrol_waypoints"):
			var empty: Array[Vector3] = []
			member.set_patrol_waypoints(empty)
	if debug_print:
		print("[GroundOps] %s — hold position" % platoon_name)

## Retrieve a platoon back to the carrier.
func retrieve(platoon_name: String) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	var members := p.get_members()
	if debug_print:
		print("[GroundOps] %s — %d registered members" % [platoon_name, members.size()])
	if members.is_empty():
		if debug_print:
			print("[GroundOps] %s has no members to retrieve" % platoon_name)
		return
	_refresh_vehicle_bay()
	if not _vehicle_bay:
		push_warning("[GroundOps] No vehicle bay found for retrieval")
		return
	# Clear platoon objective so vehicles stop their current task
	p.objective_type = GroundVehiclePlatoon.ObjectiveType.NONE
	_vehicle_bay.retrieve_vehicles(members)
	if debug_print:
		print("[GroundOps] %s — retrieving %d vehicles" % [platoon_name, members.size()])

## Pursue nearby enemies.
func order_pursue(platoon_name: String, range_m: float = 1200.0) -> void:
	var p := _get_platoon(platoon_name)
	if not p:
		return
	p.set_pursue_enemies(range_m)
	_ensure_platoon_deployed(platoon_name, p)
	if debug_print:
		print("[GroundOps] %s — pursue enemies within %.0fm" % [platoon_name, range_m])

# ── Queries ──────────────────────────────────────────────────────────────────

func get_platoon(platoon_name: String) -> GroundVehiclePlatoon:
	# Dictionaries can retain a reference after a test scenario frees the platoon node.
	# Validate as Variant before the typed return; returning the stale object itself is
	# what produces "Trying to return a previously freed instance".
	var candidate: Variant = platoons.get(platoon_name, null)
	if not is_instance_valid(candidate):
		platoons.erase(platoon_name)
		return null
	return candidate as GroundVehiclePlatoon

func get_platoon_names() -> Array[String]:
	var result: Array[String] = []
	for platoon_name in PLATOON_NAMES:
		result.append(platoon_name)
	return result

func get_platoon_status(platoon_name: String) -> Dictionary:
	var p := get_platoon(platoon_name)
	if not p:
		return {}
	_refresh_carrier()
	var has_members: bool = p.has_members()
	var position: Vector3 = p.get_contact_position() if has_members else (_carrier.global_position if _carrier and is_instance_valid(_carrier) else Vector3.ZERO)
	return {
		"kind": "platoon",
		"name": platoon_name,
		"objective": p.get_objective_name(),
		"strength": p.get_members().size(),
		"deployed": has_members,
		"queued": platoon_name in _deploy_queue or _deploying_platoon_name == platoon_name,
		"position": position,
		"active_waypoints": p.get_active_waypoints(),
	}

func get_platoon_of(vehicle: Node3D) -> GroundVehiclePlatoon:
	for pname in PLATOON_NAMES:
		var p: GroundVehiclePlatoon = platoons[pname]
		if vehicle in p.get_members():
			return p
	return null

func print_status() -> void:
	for pname in PLATOON_NAMES:
		var p: GroundVehiclePlatoon = platoons[pname]
		var members := p.get_members()
		var obj_name: String = GroundVehiclePlatoon.ObjectiveType.keys()[p.objective_type]
		print("[GroundOps] %s: %d vehicles, objective=%s" % [pname, members.size(), obj_name])

# ── Internal ─────────────────────────────────────────────────────────────────

func _get_platoon(platoon_name: String) -> GroundVehiclePlatoon:
	if platoon_name not in platoons:
		push_warning("[GroundOps] Unknown platoon: %s" % platoon_name)
		return null
	return platoons[platoon_name]

func _ensure_platoon_deployed(platoon_name: String, platoon: GroundVehiclePlatoon) -> void:
	if platoon == null or not is_instance_valid(platoon):
		return
	if platoon.has_members():
		return
	deploy(platoon_name)
