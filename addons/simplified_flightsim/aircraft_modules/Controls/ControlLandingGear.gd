extends AircraftModule
class_name AircraftModule_ControlLandingGear

@export var RestrictGearToTag: bool = false
@export var SearchTag: String = ""
@export var ControlActive: bool = true
@export var UseToggleAction: bool = true

var landing_gear_modules: Array = []
var gear_down_state: bool = true  # tracked locally for the toggle

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

func _physics_process(_delta: float) -> void:
	if (not ControlActive) or landing_gear_modules.is_empty():
		return

	# Toggle (one button)
	if UseToggleAction and Input.is_action_just_pressed("gear_toggle"):
		if gear_down_state:
			send_to_landing_gears("stow")
			gear_down_state = false
		else:
			send_to_landing_gears("deploy")
			gear_down_state = true

	# Direct commands (work alongside toggle)
	if Input.is_action_just_pressed("gear_deploy"):
		send_to_landing_gears("deploy")
		gear_down_state = true

	if Input.is_action_just_pressed("gear_stow"):
		send_to_landing_gears("stow")
		gear_down_state = false

func receive_input(_event: InputEvent) -> void:
	# Polling mode; keep stub for framework compatibility
	pass

func send_to_landing_gears(method_name: String, arguments: Array = []) -> void:
	for gear in landing_gear_modules:
		gear.callv(method_name, arguments)
