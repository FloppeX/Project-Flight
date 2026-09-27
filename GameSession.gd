extends Node

const DEFAULT_CARRIER_NAME := "Land Carrier"
const DEFAULT_PRIMARY_COLOR := Color(0.28, 0.33, 0.38, 1.0)
const DEFAULT_SECONDARY_COLOR := Color(0.90, 0.75, 0.20, 1.0)
const DEFAULT_PATTERN_INDEX := 0
const DEFAULT_INSIGNIA_INDEX := 0
const MAP_OPEN_CANYONS := "open_canyons"
const MAP_LAYERED_BADLANDS := "layered_badlands"
const MAP_CANYON_HIGHLANDS := "canyon_highlands"
const DEFAULT_MAP_ID := MAP_OPEN_CANYONS

var is_new_game: bool = false
var is_trailer_scenario: bool = false
# Filming preferences only; intentionally survive scenario resets, never saved
# into a campaign or held as references to live aircraft.
var trailer_camera_presets: Dictionary = {}
var carrier_name: String = DEFAULT_CARRIER_NAME
var carrier_primary_color: Color = DEFAULT_PRIMARY_COLOR
var carrier_secondary_color: Color = DEFAULT_SECONDARY_COLOR
var carrier_pattern_index: int = DEFAULT_PATTERN_INDEX
var carrier_insignia_index: int = DEFAULT_INSIGNIA_INDEX
var selected_map_id: String = DEFAULT_MAP_ID
var public_approval: int = 100
var wildlife_incidents: int = 0
var _pending_save_state: Dictionary = {}


func _ready() -> void:
	get_tree().scene_changed.connect(_watch_current_scene)
	_watch_current_scene.call_deferred()


func _watch_current_scene() -> void:
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and not scene.tree_exiting.is_connected(reset_runtime_operations):
		scene.tree_exiting.connect(reset_runtime_operations, CONNECT_ONE_SHOT)


func reset_runtime_operations() -> void:
	# Autoloads outlive scenes. Reset before the next scene can register units;
	# leave pending checkpoint data and user preferences intact.
	for service_name in ["OperationsCoordinator", "AirOpsManager", "GroundOpsManager", "EnemyOpsManager"]:
		var service := get_node_or_null("/root/" + service_name)
		if is_instance_valid(service):
			service.reset_runtime_state()
	var saves := get_node_or_null("/root/SaveGameManager")
	if is_instance_valid(saves):
		saves.clear_cached_runtime_state()


func configure_new_game(
		new_carrier_name: String,
		primary_color: Color,
		secondary_color: Color,
		pattern_index: int,
		insignia_index: int = DEFAULT_INSIGNIA_INDEX,
		map_id: String = DEFAULT_MAP_ID
) -> void:
	reset_runtime_operations()
	is_new_game = true
	is_trailer_scenario = false
	_pending_save_state.clear()
	carrier_name = _clean_carrier_name(new_carrier_name)
	carrier_primary_color = primary_color
	carrier_secondary_color = secondary_color
	carrier_pattern_index = maxi(pattern_index, 0)
	carrier_insignia_index = maxi(insignia_index, 0)
	selected_map_id = normalize_map_id(map_id)
	public_approval = 100
	wildlife_incidents = 0
	if PilotRoster != null and is_instance_valid(PilotRoster) \
	and PilotRoster.has_method("start_new_campaign"):
		PilotRoster.start_new_campaign()
	var poi_manager := get_node_or_null("/root/POIManager")
	if poi_manager != null and poi_manager.has_method("start_new_campaign"):
		poi_manager.call("start_new_campaign")


func normalize_map_id(map_id: String) -> String:
	match map_id.strip_edges().to_lower():
		MAP_CANYON_HIGHLANDS:
			return MAP_CANYON_HIGHLANDS
		MAP_LAYERED_BADLANDS:
			return MAP_LAYERED_BADLANDS
		_:
			return MAP_OPEN_CANYONS


func apply_to_carrier(carrier: Node) -> void:
	if carrier == null or not is_instance_valid(carrier):
		return
	carrier.set_meta("carrier_display_name", carrier_name)
	var livery := get_node_or_null("/root/Livery")
	if livery != null and livery.has_method("set_player_livery"):
		livery.call("set_player_livery", carrier_primary_color, carrier_secondary_color, carrier_pattern_index)
		if livery.has_method("set_player_insignia"):
			livery.call("set_player_insignia", carrier_insignia_index)
		livery.call("apply", carrier)
	elif livery != null and livery.has_method("apply"):
		livery.call("apply", carrier)


func reset_to_defaults() -> void:
	is_new_game = false
	is_trailer_scenario = false
	_pending_save_state.clear()
	carrier_name = DEFAULT_CARRIER_NAME
	carrier_primary_color = DEFAULT_PRIMARY_COLOR
	carrier_secondary_color = DEFAULT_SECONDARY_COLOR
	carrier_pattern_index = DEFAULT_PATTERN_INDEX
	carrier_insignia_index = DEFAULT_INSIGNIA_INDEX
	selected_map_id = DEFAULT_MAP_ID
	public_approval = 100
	wildlife_incidents = 0


func prepare_loaded_game(save_state: Dictionary) -> bool:
	if save_state.is_empty():
		return false
	var campaign_variant: Variant = save_state.get("campaign", {})
	if not (campaign_variant is Dictionary):
		return false
	var campaign := campaign_variant as Dictionary
	var session_variant: Variant = campaign.get("session", {})
	if not (session_variant is Dictionary):
		return false
	_pending_save_state = save_state.duplicate(true)
	is_trailer_scenario = false
	var session := session_variant as Dictionary
	is_new_game = false
	carrier_name = _clean_carrier_name(str(session.get("carrier_name", DEFAULT_CARRIER_NAME)))
	carrier_primary_color = session.get("carrier_primary_color", DEFAULT_PRIMARY_COLOR) as Color
	carrier_secondary_color = session.get("carrier_secondary_color", DEFAULT_SECONDARY_COLOR) as Color
	carrier_pattern_index = maxi(int(session.get("carrier_pattern_index", DEFAULT_PATTERN_INDEX)), 0)
	carrier_insignia_index = maxi(int(session.get("carrier_insignia_index", DEFAULT_INSIGNIA_INDEX)), 0)
	selected_map_id = normalize_map_id(str(session.get("selected_map_id", DEFAULT_MAP_ID)))
	public_approval = clampi(int(session.get("public_approval", 100)), 0, 100)
	wildlife_incidents = maxi(int(session.get("wildlife_incidents", 0)), 0)
	return true


func has_pending_save_state() -> bool:
	return not _pending_save_state.is_empty()


func peek_pending_save_state() -> Dictionary:
	return _pending_save_state


func peek_pending_campaign_state() -> Dictionary:
	var campaign_variant: Variant = _pending_save_state.get("campaign", {})
	return campaign_variant as Dictionary if campaign_variant is Dictionary else {}


func finish_loaded_game() -> void:
	_pending_save_state.clear()


func capture_save_state() -> Dictionary:
	return {
		"carrier_name": carrier_name,
		"carrier_primary_color": carrier_primary_color,
		"carrier_secondary_color": carrier_secondary_color,
		"carrier_pattern_index": carrier_pattern_index,
		"carrier_insignia_index": carrier_insignia_index,
		"selected_map_id": selected_map_id,
		"public_approval": public_approval,
		"wildlife_incidents": wildlife_incidents,
	}


func record_wildlife_kill() -> int:
	wildlife_incidents += 1
	public_approval = maxi(public_approval - 15, 0)
	return public_approval


func _clean_carrier_name(value: String) -> String:
	var cleaned := value.strip_edges()
	if cleaned == "":
		return DEFAULT_CARRIER_NAME
	return cleaned.substr(0, 32)
