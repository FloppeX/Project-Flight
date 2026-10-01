extends Node3D
## Two room displays share one sampled deck status; missing data stays red.

@export var manager_path: NodePath = NodePath("../FlightDeckManager")
const READY_COLOR := Color(0.05, 0.85, 0.24)
const HOLD_COLOR := Color(1.0, 0.055, 0.025)
var _poll_remaining := 0.0
var _last_status: Dictionary = {}
var _lamp_phase := true

func _ready() -> void:
	refresh()

func _process(delta: float) -> void:
	_poll_remaining -= delta
	if _poll_remaining <= 0.0:
		_poll_remaining = 1.0
		refresh()
	update_lamps(fmod(Time.get_ticks_msec() / 1000.0, 1.2) < 0.75)

func refresh() -> void:
	var manager := get_node_or_null(manager_path)
	var status := {"land_available": false, "launch_available": false,
		"land_reason": "OFFLINE", "launch_reason": "OFFLINE"}
	if is_instance_valid(manager) and manager.has_method("get_deck_signal_status"):
		status = manager.get_deck_signal_status()
	apply_status(status)

func apply_status(status: Dictionary) -> void:
	if status == _last_status: return
	_last_status = status.duplicate()
	for room in get_children():
		for operation in ["Land", "Launch"]:
			var reason := room.get_node(operation + "/Reason") as Label3D
			reason.text = str(status.get(operation.to_lower() + "_reason", "OFFLINE"))
	update_lamps(_lamp_phase, true)

func update_lamps(bright_phase: bool, force: bool = false) -> void:
	if bright_phase == _lamp_phase and not force: return
	_lamp_phase = bright_phase
	for room in get_children():
		for operation in ["Land", "Launch"]:
			var key: String = operation.to_lower()
			var ready := bool(_last_status.get(key + "_available", false))
			var active_key := "landing_active" if operation == "Land" else "launch_active"
			var dimmed := bool(_last_status.get(active_key, false)) and not bright_phase
			var lens := room.get_node(operation + "/Lens") as MeshInstance3D
			var material := lens.material_override as StandardMaterial3D
			if material == null:
				material = StandardMaterial3D.new()
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.emission_enabled = true
				material.emission_energy_multiplier = 0.7
				lens.material_override = material
			var color := READY_COLOR if ready else HOLD_COLOR
			material.albedo_color = color * (0.18 if dimmed else 1.0)
			material.emission = material.albedo_color
