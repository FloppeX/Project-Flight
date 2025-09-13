extends AircraftModule
class_name AircraftModule_ControlLandingGear

@export var RestrictGearToTag: bool = false
@export var SearchTag: String = ""
@export var ControlActive: bool = true
@export var UseToggleAction: bool = true

var landing_gear_modules: Array = []
var gear_down_state: bool = true  # tracked locally for the toggle
var tailhook_modules: Array = []
var tailhook_simple_nodes: Array = []

func _ready() -> void:
	# Polling (no event-based input)
	ReceiveInput = false

func setup(aircraft_node: Node) -> void:
	aircraft = aircraft_node
	if RestrictGearToTag:
		landing_gear_modules = aircraft.find_modules_by_type_and_tag("landing_gear", SearchTag)
	else:
		landing_gear_modules = aircraft.find_modules_by_type("landing_gear")
	print("landing_gear found: %s" % str(landing_gear_modules))
	# Also find tailhooks
	if RestrictGearToTag:
		tailhook_modules = aircraft.find_modules_by_type_and_tag("tailhook", SearchTag)
	else:
		tailhook_modules = aircraft.find_modules_by_type("tailhook")
	# Also support simple tailhook nodes via group or known path
	tailhook_simple_nodes = get_tree().get_nodes_in_group("tailhook")
	var hook_node = aircraft.get_node_or_null("TailHook")
	if hook_node and not tailhook_simple_nodes.has(hook_node):
		tailhook_simple_nodes.append(hook_node)
	# Sync tailhook state to current gear state on spawn
	if landing_gear_modules.size() > 0:
		var gear0 = landing_gear_modules[0]
		var gear_down_now: bool = true
		var prop = null
		if gear0:
			prop = gear0.get("is_deployed")
		if prop != null:
			gear_down_now = bool(prop)
		gear_down_state = gear_down_now
		if gear_down_state:
			send_to_tailhooks("deploy")
			send_to_tailhook_simple(true)
		else:
			send_to_tailhooks("stow")
			send_to_tailhook_simple(false)
	else:
		# If no landing gear found, default to deployed for hooks
		gear_down_state = true
		send_to_tailhooks("deploy")
		send_to_tailhook_simple(true)

func _physics_process(_delta: float) -> void:
	if (not ControlActive) or landing_gear_modules.is_empty():
		return

	# Toggle (one button)
	if UseToggleAction and Input.is_action_just_pressed("gear_toggle"):
		if gear_down_state:
			send_to_landing_gears("stow")
			send_to_tailhooks("stow")
			send_to_tailhook_simple(false)
			gear_down_state = false
		else:
			send_to_landing_gears("deploy")
			send_to_tailhooks("deploy")
			send_to_tailhook_simple(true)
			gear_down_state = true

	# Direct commands (work alongside toggle)
	if Input.is_action_just_pressed("gear_deploy"):
		send_to_landing_gears("deploy")
		send_to_tailhooks("deploy")
		send_to_tailhook_simple(true)
		gear_down_state = true

	if Input.is_action_just_pressed("gear_stow"):
		send_to_landing_gears("stow")
		send_to_tailhooks("stow")
		send_to_tailhook_simple(false)
		gear_down_state = false

func receive_input(_event: InputEvent) -> void:
	# Polling mode; keep stub for framework compatibility
	pass

func send_to_landing_gears(method_name: String, arguments: Array = []) -> void:
	for gear in landing_gear_modules:
		gear.callv(method_name, arguments)

func send_to_tailhooks(method_name: String, arguments: Array = []) -> void:
	for hook in tailhook_modules:
		hook.callv(method_name, arguments)

func send_to_tailhook_simple(deploying: bool) -> void:
	for n in tailhook_simple_nodes:
		if deploying and n.has_method("deploy"):
			n.deploy()
		elif (not deploying) and n.has_method("stow"):
			n.stow()
