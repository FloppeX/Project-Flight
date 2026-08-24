extends Node

signal save_availability_changed(can_save: bool, message: String)
signal campaign_saved(path: String)
signal campaign_loaded(path: String)
signal save_failed(message: String)

const SAVE_FORMAT_VERSION := 1
const SAVE_PATH := "user://saves/campaign_01.json"
const TEMP_PATH := "user://saves/campaign_01.tmp"
const BACKUP_PATH := "user://saves/campaign_01.bak"
const GAME_SCENE := "res://Main_Scene.tscn"
const CALM_WINDOW_S := 5.0
const AUTOSAVE_INTERVAL_S := 120.0
const AVAILABILITY_POLL_INTERVAL_S := 0.25

var autosave_enabled := true
var _raw_blockers: Array[Dictionary] = []
var _calm_elapsed_s := 0.0
var _last_can_save := false
var _last_message := "Campaign is still starting"
var _autosave_elapsed_s := 0.0
var _last_saved_fingerprint := 0
var _restore_started := false
var _restore_wait_frames := 0
var _availability_poll_elapsed_s := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if OS.get_cmdline_user_args().has("--disable-campaign-autosave"):
		autosave_enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))


func _process(delta: float) -> void:
	if _try_begin_pending_restore():
		return
	if not _is_campaign_scene_ready():
		_set_cached_availability(false, "No active campaign")
		_calm_elapsed_s = 0.0
		_autosave_elapsed_s = 0.0
		_last_saved_fingerprint = 0
		_availability_poll_elapsed_s = 0.0
		return

	_availability_poll_elapsed_s += maxf(delta, 0.0)
	if _availability_poll_elapsed_s < AVAILABILITY_POLL_INTERVAL_S:
		return
	var sample_delta := _availability_poll_elapsed_s
	_availability_poll_elapsed_s = 0.0
	_raw_blockers = _collect_raw_blockers()
	if _raw_blockers.is_empty():
		_calm_elapsed_s = minf(_calm_elapsed_s + sample_delta, CALM_WINDOW_S)
	else:
		_calm_elapsed_s = 0.0
	var calm_remaining := maxf(CALM_WINDOW_S - _calm_elapsed_s, 0.0)
	var ready := _raw_blockers.is_empty() and calm_remaining <= 0.0
	var message := "Ready to save"
	if not _raw_blockers.is_empty():
		message = str(_raw_blockers[0].get("message", "Campaign state is busy"))
	elif not ready:
		message = "Area settling (%.1f s)" % calm_remaining
	_set_cached_availability(ready, message)

	if not ready or not autosave_enabled:
		_autosave_elapsed_s = 0.0
		return
	_autosave_elapsed_s += sample_delta
	if _autosave_elapsed_s >= AUTOSAVE_INTERVAL_S or _last_saved_fingerprint == 0:
		_autosave_elapsed_s = 0.0
		_save_campaign(true)


func can_save_campaign() -> bool:
	return _last_can_save


func get_save_status_message() -> String:
	return _last_message


func get_save_blockers() -> Array[Dictionary]:
	if _last_can_save:
		return []
	if not _raw_blockers.is_empty():
		return _raw_blockers.duplicate(true)
	return [{"code": "settling", "message": _last_message}]


func request_manual_save() -> Dictionary:
	# The pause menu reads a cached status because this autoload pauses with the
	# campaign. Re-check the live tree at click time so a same-frame launch or
	# contact cannot use an availability result from the previous frame.
	var live_blockers := _collect_raw_blockers(false)
	if not live_blockers.is_empty():
		_raw_blockers = live_blockers
		var live_message := str(live_blockers[0].get("message", "Campaign state is busy"))
		_set_cached_availability(false, live_message)
		return {"ok": false, "message": live_message}
	if not _last_can_save:
		return {"ok": false, "message": _last_message}
	return _save_campaign(false)


func has_valid_save() -> bool:
	return not load_save_metadata().is_empty()


func load_save_metadata() -> Dictionary:
	var state := _read_valid_save(SAVE_PATH)
	if state.is_empty():
		state = _read_valid_save(BACKUP_PATH)
	if state.is_empty():
		return {}
	var metadata_variant: Variant = state.get("metadata", {})
	return metadata_variant as Dictionary if metadata_variant is Dictionary else {}


func prepare_continue() -> Dictionary:
	var state := _read_valid_save(SAVE_PATH)
	var source_path := SAVE_PATH
	if state.is_empty():
		state = _read_valid_save(BACKUP_PATH)
		source_path = BACKUP_PATH
	if state.is_empty():
		return {"ok": false, "message": "No valid campaign save found"}
	if not GameSession.prepare_loaded_game(state):
		return {"ok": false, "message": "Campaign save is incompatible"}
	_restore_started = false
	_restore_wait_frames = 0
	return {"ok": true, "message": "Loading campaign", "path": source_path}


func clear_cached_runtime_state() -> void:
	_raw_blockers.clear()
	_calm_elapsed_s = 0.0
	_last_can_save = false
	_last_message = "Campaign is still starting"
	_autosave_elapsed_s = 0.0
	_restore_started = false
	_restore_wait_frames = 0
	_availability_poll_elapsed_s = 0.0


func _set_cached_availability(ready: bool, message: String) -> void:
	var changed := ready != _last_can_save or message != _last_message
	_last_can_save = ready
	_last_message = message
	if changed:
		save_availability_changed.emit(ready, message)


func _collect_raw_blockers(prune_stale_contacts: bool = true) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	var carrier := get_tree().get_first_node_in_group("carrier") as Node3D
	if carrier == null or not is_instance_valid(carrier):
		blockers.append({"code": "no_carrier", "message": "Carrier is not ready"})
		return blockers
	if carrier.has_method("is_initial_placement_complete") \
	and not bool(carrier.call("is_initial_placement_complete")):
		blockers.append({"code": "world_starting", "message": "Campaign world is still starting"})

	var flight_deck := get_tree().get_first_node_in_group("flight_deck_manager")
	if flight_deck == null or not flight_deck.has_method("get_campaign_save_blocker"):
		blockers.append({"code": "deck_missing", "message": "Flight deck status is unavailable"})
	else:
		var deck_message := str(flight_deck.call("get_campaign_save_blocker"))
		if not deck_message.is_empty():
			blockers.append({"code": "deck_busy", "message": deck_message})

	var air_message := ""
	if AirOpsManager != null and AirOpsManager.has_method("get_campaign_save_blocker"):
		air_message = str(AirOpsManager.call("get_campaign_save_blocker", prune_stale_contacts))
	if not air_message.is_empty():
		blockers.append({"code": "air_ops", "message": air_message})

	var ground_message := ""
	if GroundOpsManager != null and GroundOpsManager.has_method("get_campaign_save_blocker"):
		ground_message = str(GroundOpsManager.call("get_campaign_save_blocker"))
	if not ground_message.is_empty():
		blockers.append({"code": "ground_ops", "message": ground_message})

	if WorldUnitIndex != null and WorldUnitIndex.has_method("get_report_stats"):
		var unit_stats: Dictionary = WorldUnitIndex.call("get_report_stats")
		if int(unit_stats.get("engagements", 0)) > 0:
			blockers.append({"code": "combat_active", "message": "Units are still engaged"})

	var enemy_message := ""
	if EnemyOpsManager != null and EnemyOpsManager.has_method("get_campaign_save_blocker"):
		enemy_message = str(EnemyOpsManager.call("get_campaign_save_blocker"))
	if not enemy_message.is_empty():
		blockers.append({"code": "enemy_ops", "message": enemy_message})

	if POIManager != null and POIManager.has_method("has_active_decision") \
	and bool(POIManager.call("has_active_decision")):
		blockers.append({"code": "decision_active", "message": "Resolve the current field decision first"})
	return blockers


func _save_campaign(automatic: bool) -> Dictionary:
	var was_paused := get_tree().paused
	get_tree().paused = true
	var campaign := _capture_campaign_state()
	get_tree().paused = was_paused
	if campaign.is_empty():
		var capture_error := "Could not capture campaign state"
		save_failed.emit(capture_error)
		return {"ok": false, "message": capture_error}
	var fingerprint := JSON.stringify(_encode_json_value(campaign)).hash()
	if automatic and fingerprint == _last_saved_fingerprint:
		return {"ok": true, "message": "Campaign unchanged"}
	var state := {
		"format_version": SAVE_FORMAT_VERSION,
		"metadata": {
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"saved_at_text": Time.get_datetime_string_from_system(false, true),
			"carrier_name": GameSession.carrier_name,
			"map_id": GameSession.selected_map_id,
			"automatic": automatic,
		},
		"campaign": campaign,
	}
	var encoded: Variant = _encode_json_value(state)
	var json_text := JSON.stringify(encoded, "  ")
	var write_result := _write_with_backup(json_text)
	if not bool(write_result.get("ok", false)):
		var write_error := str(write_result.get("message", "Could not write campaign save"))
		save_failed.emit(write_error)
		return write_result
	_last_saved_fingerprint = fingerprint
	campaign_saved.emit(SAVE_PATH)
	return {"ok": true, "message": "Campaign saved", "path": SAVE_PATH}


func _capture_campaign_state() -> Dictionary:
	var carrier := get_tree().get_first_node_in_group("carrier")
	var flight_deck := get_tree().get_first_node_in_group("flight_deck_manager")
	var carrier_manager := get_tree().get_first_node_in_group("carrier_manager")
	var terrain := get_tree().get_first_node_in_group("terrain_provider") as Node3D
	if carrier == null or flight_deck == null or carrier_manager == null:
		return {}
	var vehicle_bay: Node = carrier.get("vehicle_bay") as Node
	var scene := get_tree().current_scene
	var friendly_air_ops: Dictionary = AirOpsManager.call(
		"capture_save_state", flight_deck
	) if AirOpsManager.has_method("capture_save_state") else {"flights": []}
	var friendly_ground_ops: Dictionary = GroundOpsManager.call(
		"capture_save_state"
	) if GroundOpsManager.has_method("capture_save_state") else {"platoons": []}
	if friendly_air_ops.is_empty() or friendly_ground_ops.is_empty():
		return {}
	return {
		"session": GameSession.capture_save_state(),
		"world": {
			"terrain_bake_center": TerrainNavGrid.get_bake_center(),
			"terrain_position": terrain.position if terrain != null else Vector3.ZERO,
		},
		"carrier": carrier.call("capture_save_state") if carrier.has_method("capture_save_state") else {},
		"carrier_manager": carrier_manager.call("capture_save_state") if carrier_manager.has_method("capture_save_state") else {},
		"pilot_roster": PilotRoster.call("capture_save_state") if PilotRoster.has_method("capture_save_state") else {},
		"flight_deck": flight_deck.call("capture_save_state") if flight_deck.has_method("capture_save_state") else {},
		"vehicle_bay": vehicle_bay.call("capture_save_state") if vehicle_bay != null and vehicle_bay.has_method("capture_save_state") else {},
		"friendly_air_ops": friendly_air_ops,
		"friendly_ground_ops": friendly_ground_ops,
		"map_fog": MapFogOfWar.call("capture_save_state") if MapFogOfWar.has_method("capture_save_state") else {},
		"pois": POIManager.call("capture_save_state") if POIManager.has_method("capture_save_state") else {},
		"enemy_bases": EnemyBaseManager.call("capture_save_state") if EnemyBaseManager.has_method("capture_save_state") else {},
		"enemy_ops": EnemyOpsManager.call("capture_save_state") if EnemyOpsManager.has_method("capture_save_state") else {},
		"scenario": scene.call("capture_save_state") if scene != null and scene.has_method("capture_save_state") else {},
	}


func _write_with_backup(json_text: String) -> Dictionary:
	return _write_with_backup_at_paths(json_text, SAVE_PATH, TEMP_PATH, BACKUP_PATH)


func _write_with_backup_at_paths(
		json_text: String,
		save_path: String,
		temp_path: String,
		backup_path: String
) -> Dictionary:
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not open temporary save file"}
	file.store_string(json_text)
	file.close()
	var verify := _read_valid_save(temp_path)
	if verify.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return {"ok": false, "message": "Campaign save failed validation"}
	var save_abs := ProjectSettings.globalize_path(save_path)
	var backup_abs := ProjectSettings.globalize_path(backup_path)
	var temp_abs := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_abs)
		var backup_error := DirAccess.rename_absolute(save_abs, backup_abs)
		if backup_error != OK:
			return {"ok": false, "message": "Could not rotate previous campaign save"}
	var promote_error := DirAccess.rename_absolute(temp_abs, save_abs)
	if promote_error != OK:
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(save_path):
			DirAccess.rename_absolute(backup_abs, save_abs)
		return {"ok": false, "message": "Could not promote campaign save"}
	return {"ok": true, "message": "Campaign saved"}


func _read_valid_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var decoded: Variant = _decode_json_value(parsed)
	if not (decoded is Dictionary):
		return {}
	var state := decoded as Dictionary
	if int(state.get("format_version", -1)) != SAVE_FORMAT_VERSION:
		return {}
	if not (state.get("metadata", null) is Dictionary) or not (state.get("campaign", null) is Dictionary):
		return {}
	return state


func _try_begin_pending_restore() -> bool:
	if not GameSession.has_pending_save_state():
		_restore_started = false
		_restore_wait_frames = 0
		return false
	if _restore_started:
		return true
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != GAME_SCENE:
		return false
	if not TerrainNavGrid.is_ready():
		return true
	var carrier := get_tree().get_first_node_in_group("carrier")
	if carrier == null or not is_instance_valid(carrier):
		return true
	if carrier.has_method("is_initial_placement_complete") \
	and not bool(carrier.call("is_initial_placement_complete")):
		return true
	_restore_wait_frames += 1
	if _restore_wait_frames < 2:
		return true
	_restore_started = true
	call_deferred("_restore_pending_campaign")
	return true


func _restore_pending_campaign() -> void:
	var state := GameSession.peek_pending_save_state()
	var campaign_variant: Variant = state.get("campaign", {})
	if not (campaign_variant is Dictionary):
		_restore_failed("Campaign save has no state payload")
		return
	var campaign := campaign_variant as Dictionary
	var carrier := get_tree().get_first_node_in_group("carrier")
	var carrier_manager := get_tree().get_first_node_in_group("carrier_manager")
	var flight_deck := get_tree().get_first_node_in_group("flight_deck_manager")
	if carrier == null or carrier_manager == null or flight_deck == null:
		_restore_failed("Campaign systems were not ready")
		return
	if carrier_manager.has_method("restore_save_state"):
		carrier_manager.call("restore_save_state", campaign.get("carrier_manager", {}))
	if PilotRoster.has_method("restore_save_state"):
		PilotRoster.call("restore_save_state", campaign.get("pilot_roster", {}))
	if flight_deck.has_method("restore_save_state"):
		flight_deck.call("restore_save_state", campaign.get("flight_deck", {}))
	var vehicle_bay: Node = carrier.get("vehicle_bay") as Node
	if vehicle_bay != null and vehicle_bay.has_method("restore_save_state"):
		vehicle_bay.call("restore_save_state", campaign.get("vehicle_bay", {}))
	if carrier.has_method("restore_save_state"):
		carrier.call("restore_save_state", campaign.get("carrier", {}))
	if AirOpsManager.has_method("restore_save_state") \
	and not bool(AirOpsManager.call(
		"restore_save_state", campaign.get("friendly_air_ops", {}), flight_deck
	)):
		_restore_failed("Friendly flights could not be restored")
		return
	if GroundOpsManager.has_method("restore_save_state") \
	and not bool(GroundOpsManager.call(
		"restore_save_state", campaign.get("friendly_ground_ops", {})
	)):
		_restore_failed("Friendly ground platoons could not be restored")
		return
	if MapFogOfWar.has_method("restore_save_state"):
		MapFogOfWar.call("restore_save_state", campaign.get("map_fog", {}))
	if POIManager.has_method("restore_save_state"):
		POIManager.call("restore_save_state", campaign.get("pois", {}))
	if EnemyOpsManager.has_method("restore_save_state"):
		EnemyOpsManager.call("restore_save_state", campaign.get("enemy_ops", {}), EnemyBaseManager.get_all_bases())
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("restore_save_state"):
		scene.call("restore_save_state", campaign.get("scenario", {}))
	GameSession.finish_loaded_game()
	_raw_blockers.clear()
	_calm_elapsed_s = 0.0
	_last_saved_fingerprint = JSON.stringify(_encode_json_value(campaign)).hash()
	_set_cached_availability(false, "Loaded campaign is settling")
	campaign_loaded.emit(SAVE_PATH)
	print("[SaveGame] Campaign restored")


func _restore_failed(message: String) -> void:
	GameSession.finish_loaded_game()
	_restore_started = false
	save_failed.emit(message)
	push_error("[SaveGame] %s" % message)


func _is_campaign_scene_ready() -> bool:
	return get_tree().current_scene != null \
		and get_tree().current_scene.scene_file_path == GAME_SCENE \
		and not GameSession.has_pending_save_state()


func _encode_json_value(value: Variant) -> Variant:
	if value is Vector2:
		return {"__type": "Vector2", "v": [value.x, value.y]}
	if value is Vector2i:
		return {"__type": "Vector2i", "v": [value.x, value.y]}
	if value is Vector3:
		return {"__type": "Vector3", "v": [value.x, value.y, value.z]}
	if value is Color:
		return {"__type": "Color", "v": [value.r, value.g, value.b, value.a]}
	if value is PackedByteArray:
		return {"__type": "PackedByteArray", "v": Marshalls.raw_to_base64(value)}
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_encode_json_value(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value.keys():
			result[str(key)] = _encode_json_value(value[key])
		return result
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return null


func _decode_json_value(value: Variant) -> Variant:
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_decode_json_value(item))
		return result
	if value is Dictionary:
		var dict := value as Dictionary
		var type_name := str(dict.get("__type", ""))
		var raw: Variant = dict.get("v", null)
		if type_name == "Vector2" and raw is Array and raw.size() >= 2:
			return Vector2(float(raw[0]), float(raw[1]))
		if type_name == "Vector2i" and raw is Array and raw.size() >= 2:
			return Vector2i(int(raw[0]), int(raw[1]))
		if type_name == "Vector3" and raw is Array and raw.size() >= 3:
			return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
		if type_name == "Color" and raw is Array and raw.size() >= 4:
			return Color(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
		if type_name == "PackedByteArray":
			return Marshalls.base64_to_raw(str(raw))
		var result: Dictionary = {}
		for key in dict.keys():
			result[key] = _decode_json_value(dict[key])
		return result
	return value
