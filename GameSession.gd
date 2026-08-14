extends Node

const DEFAULT_CARRIER_NAME := "Land Carrier"
const DEFAULT_PRIMARY_COLOR := Color(0.28, 0.33, 0.38, 1.0)
const DEFAULT_SECONDARY_COLOR := Color(0.90, 0.75, 0.20, 1.0)
const DEFAULT_PATTERN_INDEX := 0
const DEFAULT_INSIGNIA_INDEX := 0
const MAP_OPEN_CANYONS := "open_canyons"
const MAP_LAYERED_BADLANDS := "layered_badlands"
const DEFAULT_MAP_ID := MAP_OPEN_CANYONS

var is_new_game: bool = false
var carrier_name: String = DEFAULT_CARRIER_NAME
var carrier_primary_color: Color = DEFAULT_PRIMARY_COLOR
var carrier_secondary_color: Color = DEFAULT_SECONDARY_COLOR
var carrier_pattern_index: int = DEFAULT_PATTERN_INDEX
var carrier_insignia_index: int = DEFAULT_INSIGNIA_INDEX
var selected_map_id: String = DEFAULT_MAP_ID


func configure_new_game(
		new_carrier_name: String,
		primary_color: Color,
		secondary_color: Color,
		pattern_index: int,
		insignia_index: int = DEFAULT_INSIGNIA_INDEX,
		map_id: String = DEFAULT_MAP_ID
) -> void:
	is_new_game = true
	carrier_name = _clean_carrier_name(new_carrier_name)
	carrier_primary_color = primary_color
	carrier_secondary_color = secondary_color
	carrier_pattern_index = maxi(pattern_index, 0)
	carrier_insignia_index = maxi(insignia_index, 0)
	selected_map_id = normalize_map_id(map_id)


func normalize_map_id(map_id: String) -> String:
	match map_id.strip_edges().to_lower():
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
	carrier_name = DEFAULT_CARRIER_NAME
	carrier_primary_color = DEFAULT_PRIMARY_COLOR
	carrier_secondary_color = DEFAULT_SECONDARY_COLOR
	carrier_pattern_index = DEFAULT_PATTERN_INDEX
	carrier_insignia_index = DEFAULT_INSIGNIA_INDEX
	selected_map_id = DEFAULT_MAP_ID


func _clean_carrier_name(value: String) -> String:
	var cleaned := value.strip_edges()
	if cleaned == "":
		return DEFAULT_CARRIER_NAME
	return cleaned.substr(0, 32)
