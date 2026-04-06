extends Node
class_name CarrierManager

@export var starting_pilot_count: int = 30
@export var pilot_names_file_path: String = "res://docs/names.txt"
@export var pilot_callsigns_file_path: String = "res://docs/callsigns.txt"

# Carrier resources (minimal set for now).
@export var corium_units: float = 1000.0
@export var plasteel_units: float = 1000.0

var aircraft_registry: Dictionary = {}
var vehicle_registry: Dictionary = {}

const DEFAULT_PILOT_NAMES: Array[String] = ["Smith", "Johnson", "Williams", "Brown", "Jones"]
const DEFAULT_PILOT_CALLSIGNS: Array[String] = ["Skipper", "Goose", "Rook", "Falcon", "Hound"]
const PILOT_RANK_WEIGHTS: Array[String] = [
	"Fo", "Fo", "Fo", "Fo", "Fo",
	"Lt", "Lt", "Lt", "Lt",
	"Cpt", "Cpt", "Cpt",
	"Maj", "Maj",
	"LtCol",
	"Col"
]

var _pilot_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pilot_records: Dictionary = {}  # pilot_id -> Dictionary
var _pilot_order: Array[int] = []
var _active_pilot_by_aircraft_id: Dictionary = {}  # aircraft_instance_id -> pilot_id
var _next_pilot_id: int = 1
var _initialized: bool = false

func _ready() -> void:
	add_to_group("carrier_manager")
	ensure_initialized()

func ensure_initialized() -> void:
	if _initialized:
		return
	_pilot_rng.randomize()
	_initialize_pilot_roster()
	_initialized = true

func ensure_aircraft_data_has_pilot(aircraft_data: Dictionary) -> bool:
	ensure_initialized()
	var metadata := _ensure_metadata_dict(aircraft_data)
	var pilot_id := int(metadata.get("pilot_id", -1))
	if pilot_id > 0 and _pilot_exists_and_alive(pilot_id):
		_set_pilot_assignment(pilot_id, "hangar")
		_write_pilot_metadata(metadata, pilot_id)
		aircraft_data["metadata"] = metadata
		return true

	var available_id := _pick_available_pilot_id()
	if available_id <= 0:
		push_warning("[CarrierManager] No living unassigned pilots available for %s" % str(aircraft_data.get("name", "Aircraft")))
		return false

	_set_pilot_assignment(available_id, "hangar")
	_write_pilot_metadata(metadata, available_id)
	aircraft_data["metadata"] = metadata
	return true

func bind_pilot_to_live_aircraft(aircraft: RigidBody3D, aircraft_data: Dictionary) -> bool:
	if not is_instance_valid(aircraft):
		return false
	ensure_initialized()

	var metadata := _ensure_metadata_dict(aircraft_data)
	var pilot_id := int(metadata.get("pilot_id", -1))
	if pilot_id <= 0:
		if not ensure_aircraft_data_has_pilot(aircraft_data):
			return false
		metadata = _ensure_metadata_dict(aircraft_data)
		pilot_id = int(metadata.get("pilot_id", -1))

	if not _pilot_exists_and_alive(pilot_id):
		return false

	_set_pilot_assignment(pilot_id, "active")
	_write_pilot_metadata(metadata, pilot_id)
	aircraft_data["metadata"] = metadata
	_apply_metadata_to_aircraft(aircraft, metadata)

	var aircraft_id := aircraft.get_instance_id()
	_active_pilot_by_aircraft_id[aircraft_id] = pilot_id
	if aircraft.has_signal("destroyed"):
		var callback := Callable(self, "_on_assigned_aircraft_destroyed").bind(aircraft_id, pilot_id)
		if not aircraft.destroyed.is_connected(callback):
			aircraft.destroyed.connect(callback, CONNECT_ONE_SHOT)
	return true

func mark_aircraft_stored(aircraft: RigidBody3D, aircraft_data: Dictionary) -> void:
	ensure_initialized()
	var metadata := _ensure_metadata_dict(aircraft_data)
	var pilot_id := int(metadata.get("pilot_id", -1))
	if pilot_id <= 0:
		if not ensure_aircraft_data_has_pilot(aircraft_data):
			return
		metadata = _ensure_metadata_dict(aircraft_data)
		pilot_id = int(metadata.get("pilot_id", -1))

	if _pilot_exists_and_alive(pilot_id):
		_set_pilot_assignment(pilot_id, "hangar")
		_write_pilot_metadata(metadata, pilot_id)
		aircraft_data["metadata"] = metadata

	if is_instance_valid(aircraft):
		_active_pilot_by_aircraft_id.erase(aircraft.get_instance_id())

func get_pilot_roster_snapshot() -> Array[Dictionary]:
	ensure_initialized()
	var snapshot: Array[Dictionary] = []
	for pilot_id in _pilot_order:
		var pilot: Dictionary = (_pilot_records.get(pilot_id, {}) as Dictionary).duplicate(true)
		pilot["display_name"] = _format_pilot_display(pilot)
		snapshot.append(pilot)
	return snapshot

func get_pilot_display_name_from_aircraft(aircraft: RigidBody3D) -> String:
	if not is_instance_valid(aircraft):
		return ""
	if aircraft.has_meta("pilot_display_name"):
		return str(aircraft.get_meta("pilot_display_name"))
	var rank := str(aircraft.get_meta("pilot_rank", ""))
	var callsign := str(aircraft.get_meta("pilot_callsign", ""))
	var surname := str(aircraft.get_meta("pilot_name", ""))
	if rank == "" and callsign == "" and surname == "":
		return ""
	return "%s \"%s\" %s" % [rank, callsign, surname]

func _initialize_pilot_roster() -> void:
	_pilot_records.clear()
	_pilot_order.clear()
	_active_pilot_by_aircraft_id.clear()
	_next_pilot_id = 1

	var total_pilots := maxi(starting_pilot_count, 0)
	if total_pilots <= 0:
		return

	var raw_names := _load_text_lines(pilot_names_file_path)
	var raw_callsigns := _load_text_lines(pilot_callsigns_file_path)
	var surnames := _generate_unique_values(raw_names, DEFAULT_PILOT_NAMES, total_pilots)
	var callsigns := _generate_unique_values(raw_callsigns, DEFAULT_PILOT_CALLSIGNS, total_pilots)
	surnames.shuffle()
	callsigns.shuffle()

	for i in range(total_pilots):
		var pilot_id := _next_pilot_id
		_next_pilot_id += 1
		var rank := _pick_weighted_rank()
		var pilot := {
			"id": pilot_id,
			"name": surnames[i],
			"callsign": callsigns[i],
			"rank": rank,
			"skill": rank,
			"alive": true,
			"assignment": "available",
			"status": "READY"
		}
		_pilot_records[pilot_id] = pilot
		_pilot_order.append(pilot_id)

func _load_text_lines(path: String) -> Array[String]:
	var lines: Array[String] = []
	if path.is_empty() or not FileAccess.file_exists(path):
		return lines
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return lines
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line != "":
			lines.append(line)
	return lines

func _generate_unique_values(source: Array[String], fallback: Array[String], needed: int) -> Array[String]:
	var pool: Array[String] = source.duplicate()
	if pool.is_empty():
		pool = fallback.duplicate()
	if pool.is_empty():
		pool = ["Unknown"]
	pool.shuffle()

	var values: Array[String] = []
	var idx := 0
	while values.size() < needed:
		var base: String = pool[idx % pool.size()]
		if idx >= pool.size():
			base = "%s %d" % [base, int(idx / pool.size()) + 1]
		values.append(base)
		idx += 1
	return values

func _pick_weighted_rank() -> String:
	if PILOT_RANK_WEIGHTS.is_empty():
		return "Fo"
	return PILOT_RANK_WEIGHTS[_pilot_rng.randi_range(0, PILOT_RANK_WEIGHTS.size() - 1)]

func _pick_available_pilot_id() -> int:
	var available: Array[int] = []
	for pilot_id in _pilot_order:
		var pilot: Dictionary = _pilot_records.get(pilot_id, {})
		if bool(pilot.get("alive", false)) and str(pilot.get("assignment", "")) == "available":
			available.append(pilot_id)
	if available.is_empty():
		return -1
	return available[_pilot_rng.randi_range(0, available.size() - 1)]

func _pilot_exists_and_alive(pilot_id: int) -> bool:
	if not _pilot_records.has(pilot_id):
		return false
	var pilot: Dictionary = _pilot_records[pilot_id]
	return bool(pilot.get("alive", false))

func _set_pilot_assignment(pilot_id: int, assignment: String) -> void:
	if not _pilot_records.has(pilot_id):
		return
	var pilot: Dictionary = (_pilot_records[pilot_id] as Dictionary).duplicate(true)
	pilot["assignment"] = assignment
	match assignment:
		"active":
			pilot["status"] = "ACTIVE"
		"hangar":
			pilot["status"] = "HANGAR"
		"kia":
			pilot["alive"] = false
			pilot["status"] = "KIA"
		_:
			pilot["status"] = "READY"
	_pilot_records[pilot_id] = pilot

func _write_pilot_metadata(metadata: Dictionary, pilot_id: int) -> void:
	if not _pilot_records.has(pilot_id):
		return
	var pilot: Dictionary = _pilot_records[pilot_id]
	metadata["pilot_id"] = pilot_id
	metadata["pilot_rank"] = str(pilot.get("rank", "Fo"))
	metadata["pilot_skill"] = str(pilot.get("skill", metadata.get("pilot_rank", "Fo")))
	metadata["pilot_callsign"] = str(pilot.get("callsign", "Rook"))
	metadata["pilot_name"] = str(pilot.get("name", "Unknown"))
	metadata["pilot_display_name"] = _format_pilot_display(pilot)

func _ensure_metadata_dict(aircraft_data: Dictionary) -> Dictionary:
	var metadata_value = aircraft_data.get("metadata", {})
	if typeof(metadata_value) != TYPE_DICTIONARY:
		metadata_value = {}
	var metadata: Dictionary = metadata_value
	aircraft_data["metadata"] = metadata
	return metadata

func _apply_metadata_to_aircraft(aircraft: RigidBody3D, metadata: Dictionary) -> void:
	for key in ["pilot_id", "pilot_rank", "pilot_skill", "pilot_callsign", "pilot_name", "pilot_display_name"]:
		if metadata.has(key):
			aircraft.set_meta(key, metadata[key])

func _format_pilot_display(pilot: Dictionary) -> String:
	var rank := str(pilot.get("rank", "Fo"))
	var callsign := str(pilot.get("callsign", "Rook"))
	var surname := str(pilot.get("name", "Unknown"))
	return "%s \"%s\" %s" % [rank, callsign, surname]

func _on_assigned_aircraft_destroyed(aircraft_instance_id: int, pilot_id: int) -> void:
	_active_pilot_by_aircraft_id.erase(aircraft_instance_id)
	if not _pilot_exists_and_alive(pilot_id):
		return
	_set_pilot_assignment(pilot_id, "kia")
	var pilot: Dictionary = _pilot_records.get(pilot_id, {})
	print("[CarrierManager] Pilot KIA: %s" % _format_pilot_display(pilot))
