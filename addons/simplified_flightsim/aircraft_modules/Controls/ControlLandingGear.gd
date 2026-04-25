extends AircraftModule
class_name AircraftModule_ControlLandingGear

@export var RestrictGearToTag: bool = false
@export var SearchTag: String = ""
@export var ControlActive: bool = true
@export var UseToggleAction: bool = true
@export var LockGearDeployed: bool = false
@export var debug_enabled: bool = false

# Optional direct gear collider control (assign in editor)
@export var nose_gear_collider_path: NodePath
@export var left_main_gear_collider_path: NodePath
@export var right_main_gear_collider_path: NodePath

# Optional additional visual roots (assign any Node3D that should hide/show with gear)
@export var gear_visual_root_paths: Array[NodePath] = []

var landing_gear_modules: Array = []
var gear_down_state: bool = true  # tracked locally for the toggle (true = gear deployed)
var tailhook_down_state: bool = false
var tailhook_modules: Array = []
var tailhook_simple_nodes: Array = []
var _rescan_timer_s: float = 0.0
@export var rescan_interval_s: float = 1.0  # periodically try to rediscover gear modules

var _nose_cs: CollisionShape3D
var _left_cs: CollisionShape3D
var _right_cs: CollisionShape3D
var _visual_roots: Array = []   # resolved Node3D roots for visuals

func _ready() -> void:
	# Polling (no event-based input)
	ReceiveInput = false

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node
	_discover_modules()

	# Resolve optional colliders
	_nose_cs = aircraft.get_node_or_null(nose_gear_collider_path) as CollisionShape3D
	_left_cs = aircraft.get_node_or_null(left_main_gear_collider_path) as CollisionShape3D
	_right_cs = aircraft.get_node_or_null(right_main_gear_collider_path) as CollisionShape3D
	# Fallback: resolve by common node names if not assigned
	if _nose_cs == null:
		_nose_cs = _find_node_by_name(aircraft, "CenterGearCollider") as CollisionShape3D
	if _left_cs == null:
		_left_cs = _find_node_by_name(aircraft, "LeftGearCollider") as CollisionShape3D
	if _right_cs == null:
		_right_cs = _find_node_by_name(aircraft, "RightGearCollider") as CollisionShape3D
	if debug_enabled:
		print("[GEAR] collider refs: nose=", _nose_cs, " left=", _left_cs, " right=", _right_cs)
	# Resolve optional visual roots
	_visual_roots.clear()
	for p in gear_visual_root_paths:
		var n = aircraft.get_node_or_null(p)
		if n and n is Node3D:
			_visual_roots.append(n)
	# Pull visuals from first LandingGear module if available
	if _visual_roots.is_empty() and landing_gear_modules.size() > 0:
		var lg = _resolve_gear_module(landing_gear_modules[0])
		if lg:
			var arr = lg.get("gear_visuals")
			if arr != null and typeof(arr) == TYPE_ARRAY:
				for v in arr:
					if v is NodePath:
						var nn = aircraft.get_node_or_null(v)
						if nn and nn is Node3D:
							_visual_roots.append(nn)
					elif v is Node3D:
						_visual_roots.append(v)
	if debug_enabled:
		print("[GEAR] visual roots: ", _visual_roots)

	# Force starting state: gear DEPLOYED, tailhook STOWED
	send_to_landing_gears("deploy")
	_set_collider_disabled(false)
	gear_down_state = true

	# Force tailhook stowed at startup regardless of gear state
	send_to_tailhooks("stow")
	send_to_tailhook_simple(false)
	tailhook_down_state = false

func _discover_modules() -> void:
	# Discover landing gear modules (optionally filtered by tag)
	if RestrictGearToTag:
		landing_gear_modules = aircraft.find_modules_by_type_and_tag("landing_gear", SearchTag)
	else:
		landing_gear_modules = aircraft.find_modules_by_type("landing_gear")
	# Fallback: recursively find AircraftModule_LandingGear nodes if none discovered
	if landing_gear_modules.is_empty():
		var found: Array = []
		_collect_gears_recursive(aircraft, found)
		if not found.is_empty():
			landing_gear_modules = found
	if debug_enabled:
		print("[GEAR] discovered ", landing_gear_modules.size(), " gear module(s)")
	# Discover tailhook modules and simple TailHook nodes (for deploy/stow API)
	if RestrictGearToTag:
		tailhook_modules = aircraft.find_modules_by_type_and_tag("tailhook", SearchTag)
	else:
		tailhook_modules = aircraft.find_modules_by_type("tailhook")
	tailhook_simple_nodes = get_tree().get_nodes_in_group("tailhook")
	var hook_node = aircraft.get_node_or_null("TailHook")
	if hook_node and not tailhook_simple_nodes.has(hook_node):
		tailhook_simple_nodes.append(hook_node)
	if debug_enabled:
		print("[GEAR] tailhooks: modules=", tailhook_modules.size(), " simple=", tailhook_simple_nodes.size())

func _collect_gears_recursive(n: Node, out: Array) -> void:
	if n is AircraftModule_LandingGear:
		out.append(n)
	for c in n.get_children():
		_collect_gears_recursive(c, out)

func _physics_process(delta: float) -> void:
	if not ControlActive:
		return

	# Periodic rediscovery in case setup order delayed population
	_rescan_timer_s -= delta
	if landing_gear_modules.is_empty() and _rescan_timer_s <= 0.0 and aircraft:
		_discover_modules()
		_rescan_timer_s = max(0.1, rescan_interval_s)

	# Toggle (one button): stow both, then deploy both, alternating
	if UseToggleAction and Input.is_action_just_pressed("gear_toggle"):
		if debug_enabled:
			print("[GEAR] toggle pressed; gears=", landing_gear_modules.size(), " hooks=", tailhook_modules.size(), "/", tailhook_simple_nodes.size())
		if LockGearDeployed:
			send_to_landing_gears("deploy")
			_set_collider_disabled(false)
			gear_down_state = true
			if tailhook_down_state:
				send_to_tailhooks("stow")
				send_to_tailhook_simple(false)
				tailhook_down_state = false
			else:
				send_to_tailhooks("deploy")
				send_to_tailhook_simple(true)
				tailhook_down_state = true
			return
		if gear_down_state:
			send_to_landing_gears("stow")
			send_to_tailhooks("stow")
			send_to_tailhook_simple(false)
			_set_collider_disabled(true)
			gear_down_state = false
			tailhook_down_state = false
		else:
			send_to_landing_gears("deploy")
			send_to_tailhooks("deploy")
			send_to_tailhook_simple(true)
			_set_collider_disabled(false)
			gear_down_state = true
			tailhook_down_state = true

	# Direct commands (work alongside toggle)
	if Input.is_action_just_pressed("gear_deploy"):
		if debug_enabled:
			print("[GEAR] deploy; gears=", landing_gear_modules.size())
		send_to_landing_gears("deploy")
		send_to_tailhooks("deploy")
		send_to_tailhook_simple(true)
		_set_collider_disabled(false)
		gear_down_state = true
		tailhook_down_state = true

	if Input.is_action_just_pressed("gear_stow"):
		if debug_enabled:
			print("[GEAR] stow; gears=", landing_gear_modules.size())
		if LockGearDeployed:
			send_to_landing_gears("deploy")
			send_to_tailhooks("stow")
			send_to_tailhook_simple(false)
			_set_collider_disabled(false)
			gear_down_state = true
			tailhook_down_state = false
			return
		send_to_landing_gears("stow")
		send_to_tailhooks("stow")
		send_to_tailhook_simple(false)
		_set_collider_disabled(true)
		gear_down_state = false
		tailhook_down_state = false

func receive_input(_event: InputEvent) -> void:
	# Polling mode; keep stub for framework compatibility
	pass

func send_to_landing_gears(method_name: String, arguments: Array = []) -> void:
	for gear in landing_gear_modules:
		if not is_instance_valid(gear):
			continue
		var target := _resolve_gear_module(gear)
		if target and is_instance_valid(target) and target.has_method(method_name):
			target.callv(method_name, arguments)
			if debug_enabled:
				print("[GEAR] ", method_name, " called on ", target)
		else:
			if debug_enabled:
				print("[GEAR] gear node missing method ", method_name, ": ", gear)

func _resolve_gear_module(n: Node) -> Node:
	if not is_instance_valid(n):
		return null
	# If node is already a gear module, return it; else search children
	if n is AircraftModule_LandingGear:
		return n
	for c in n.get_children():
		if not is_instance_valid(c):
			continue
		if c is AircraftModule_LandingGear:
			return c
		var deep := _resolve_gear_module(c)
		if deep:
			return deep
	return null

func send_to_tailhooks(method_name: String, arguments: Array = []) -> void:
	for hook in tailhook_modules:
		if hook and is_instance_valid(hook) and hook.has_method(method_name):
			hook.callv(method_name, arguments)
			if debug_enabled:
				print("[HOOK] ", method_name, " called on ", hook)

func send_to_tailhook_simple(deploying: bool) -> void:
	for n in tailhook_simple_nodes:
		if not n or not is_instance_valid(n):
			continue
		if deploying and n.has_method("deploy"):
			n.deploy()
			if debug_enabled:
				print("[HOOK] deploy called on simple node ", n)
		elif (not deploying) and n.has_method("stow"):
			n.stow()
			if debug_enabled:
				print("[HOOK] stow called on simple node ", n)

func _set_collider_disabled(disabled: bool) -> void:
	# Directly toggle assigned colliders, independent of module wiring
	if _nose_cs:
		_nose_cs.disabled = disabled
		if debug_enabled:
			print("[GEAR] nose collider ", ("DISABLED" if disabled else "ENABLED"), ": ", _nose_cs)
	if _left_cs:
		_left_cs.disabled = disabled
		if debug_enabled:
			print("[GEAR] left collider ", ("DISABLED" if disabled else "ENABLED"), ": ", _left_cs)
	if _right_cs:
		_right_cs.disabled = disabled
		if debug_enabled:
			print("[GEAR] right collider ", ("DISABLED" if disabled else "ENABLED"), ": ", _right_cs)
	if debug_enabled and not _visual_roots.is_empty():
		print("[GEAR] visual roots managed by LandingGear module: ", _visual_roots.size())

func _set_descendant_visuals_visible(root: Node, visible: bool) -> int:
	# Recursively toggle visibility of all Node3D descendants of root
	var count := 0
	var stack := [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for child in n.get_children():
			stack.append(child)
			if child is Node3D:
				(child as Node3D).visible = visible
				count += 1
	return count

func _set_node3d_tree_visible(node: Node3D, visible: bool) -> void:
	# Toggle node and all Node3D descendants
	node.visible = visible
	for child in node.get_children():
		if child is Node3D:
			_set_node3d_tree_visible(child as Node3D, visible)

func _find_node_by_name(root: Node, name: String) -> Node:
	if not root:
		return null
	if root.name == name:
		return root
	for c in root.get_children():
		var r = _find_node_by_name(c, name)
		if r:
			return r
	return null
