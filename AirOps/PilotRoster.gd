extends Node

const CALLSIGN_SUFFIXES := ["lead", "two", "three", "four"]
const FLIGHT_TIME_XP_PER_SECOND: float = 1.0 / 30.0
const AIR_KILL_XP: int = 200
const GROUND_KILL_XP: int = 120
const DAMAGE_CREDIT_WINDOW_S: float = 45.0
const SHARED_KILL_MIN_DAMAGE_SHARE: float = 0.25
const SHARED_KILL_TOP_DAMAGE_MAX_SHARE: float = 0.75
const ROOKIE_XP: int = 300
const EXPERIENCED_XP: int = 1200
const VETERAN_XP: int = 3500
const ELITE_XP: int = 7500
const ACE_AIR_KILLS: int = 5
const PORTRAIT_CATALOG_PATH := "res://Images/Pilot Portraits/pilot_portrait_catalog.csv"
const PORTRAIT_DIRECTORY := "res://Images/Pilot Portraits/"

const ORIGIN_PORTRAIT_REGIONS := {
	"Ukraine": "Eastern Europe & Russia",
	"Brazil": "Latin America & Caribbean",
	"Philippines": "Southeast Asia",
	"Lebanon": "Middle East & North Africa",
	"Scotland": "Britain & Ireland",
	"French Canada": "North America",
	"Germany": "Western & Central Europe",
	"Jordan": "Middle East & North Africa",
	"Nigeria": "Sub-Saharan Africa",
}

const PILOT_POOL: Array[Dictionary] = [
	{
		"id": "oleksandr_kovalenko",
		"rank": "Lt.",
		"name": "Oleksandr Kovalenko",
		"short_name": "Kovalenko",
		"gender": "male",
		"national_origin": "Ukraine",
		"language": "Ukrainian",
		"voice_prefix": "Ukrainian - ",
		"skill": "VETERAN",
		"experience_points": 4200,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "steady",
	},
	{
		"id": "rafael_costa",
		"rank": "Ens.",
		"name": "Rafael Costa",
		"short_name": "Costa",
		"gender": "male",
		"national_origin": "Brazil",
		"language": "Portuguese",
		"voice_prefix": "Brazilian male - ",
		"skill": "EXPERIENCED",
		"experience_points": 1800,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "confident",
	},
	{
		"id": "miguel_reyes",
		"rank": "Ens.",
		"name": "Miguel Reyes",
		"short_name": "Reyes",
		"gender": "male",
		"national_origin": "Philippines",
		"language": "Filipino",
		"voice_prefix": "Filipino - ",
		"skill": "EXPERIENCED",
		"experience_points": 1500,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "eager",
	},
	{
		"id": "nadia_haddad",
		"rank": "Lt.",
		"name": "Nadia Haddad",
		"short_name": "Haddad",
		"gender": "female",
		"national_origin": "Lebanon",
		"language": "Arabic",
		"voice_prefix": "Arabic female - ",
		"skill": "VETERAN",
		"experience_points": 3900,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "aggressive",
	},
	{
		"id": "fiona_macleod",
		"rank": "Lt. Cmdr.",
		"name": "Fiona MacLeod",
		"short_name": "MacLeod",
		"gender": "female",
		"national_origin": "Scotland",
		"language": "Scottish English",
		"voice_prefix": "Scottish female - ",
		"skill": "ELITE",
		"experience_points": 7800,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "cool",
	},
	{
		"id": "andres_bautista",
		"rank": "Lt.",
		"name": "Andres Bautista",
		"short_name": "Bautista",
		"gender": "male",
		"national_origin": "Philippines",
		"language": "Filipino",
		"voice_prefix": "Filipino - ",
		"skill": "VETERAN",
		"experience_points": 3600,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "practical",
	},
	{
		"id": "thiago_almeida",
		"rank": "Ens.",
		"name": "Thiago Almeida",
		"short_name": "Almeida",
		"gender": "male",
		"national_origin": "Brazil",
		"language": "Portuguese",
		"voice_prefix": "Brazilian male - ",
		"skill": "ROOKIE",
		"experience_points": 650,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "bold",
	},
	{
		"id": "celine_bouchard",
		"rank": "FO",
		"name": "Celine Bouchard",
		"short_name": "Bouchard",
		"gender": "female",
		"national_origin": "French Canada",
		"language": "Quebec French",
		"voice_prefix": "French Canadian female - ",
		"skill": "EXPERIENCED",
		"experience_points": 1900,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "spirited",
	},
	{
		"id": "klara_vogt",
		"rank": "Lt.",
		"name": "Klara Vogt",
		"short_name": "Vogt",
		"gender": "female",
		"national_origin": "Germany",
		"language": "German",
		"voice_prefix": "German female - ",
		"skill": "EXPERIENCED",
		"experience_points": 2300,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "methodical",
	},
	{
		"id": "mateo_santos",
		"rank": "Lt. Cmdr.",
		"name": "Mateo Santos",
		"short_name": "Santos",
		"gender": "male",
		"national_origin": "Philippines",
		"language": "Filipino",
		"voice_prefix": "Filipino - ",
		"skill": "VETERAN",
		"experience_points": 5000,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "decisive",
	},
	{
		"id": "ailsa_fraser",
		"rank": "Lt.",
		"name": "Ailsa Fraser",
		"short_name": "Fraser",
		"gender": "female",
		"national_origin": "Scotland",
		"language": "Scottish English",
		"voice_prefix": "Scottish female - ",
		"skill": "EXPERIENCED",
		"experience_points": 2500,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "dry",
	},
	{
		"id": "mara_schneider",
		"rank": "Ens.",
		"name": "Mara Schneider",
		"short_name": "Schneider",
		"gender": "female",
		"national_origin": "Germany",
		"language": "German",
		"voice_prefix": "German female - ",
		"skill": "ROOKIE",
		"experience_points": 900,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "careful",
	},
	{
		"id": "iryna_melnyk",
		"rank": "Lt.",
		"name": "Iryna Melnyk",
		"short_name": "Melnyk",
		"gender": "female",
		"national_origin": "Ukraine",
		"language": "Ukrainian",
		"voice_prefix": "Ukrainian - ",
		"skill": "VETERAN",
		"experience_points": 4100,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "intense",
	},
	{
		"id": "layla_mansour",
		"rank": "Lt. Cmdr.",
		"name": "Layla Mansour",
		"short_name": "Mansour",
		"gender": "female",
		"national_origin": "Jordan",
		"language": "Arabic",
		"voice_prefix": "Arabic female - ",
		"skill": "ELITE",
		"experience_points": 8200,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "fearless",
	},
	{
		"id": "anika_keller",
		"rank": "Lt.",
		"name": "Anika Keller",
		"short_name": "Keller",
		"gender": "female",
		"national_origin": "Germany",
		"language": "German",
		"voice_prefix": "German female - ",
		"skill": "VETERAN",
		"experience_points": 3300,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "precise",
	},
	{
		"id": "bruno_ferreira",
		"rank": "Ens.",
		"name": "Bruno Ferreira",
		"short_name": "Ferreira",
		"gender": "male",
		"national_origin": "Brazil",
		"language": "Portuguese",
		"voice_prefix": "Brazilian male - ",
		"skill": "EXPERIENCED",
		"experience_points": 2100,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "restless",
	},
	{
		"id": "chinedu_okafor",
		"rank": "Lt.",
		"name": "Chinedu Okafor",
		"short_name": "Okafor",
		"gender": "male",
		"national_origin": "Nigeria",
		"language": "Nigerian English",
		"voice_prefix": "Nigerian male - ",
		"skill": "EXPERIENCED",
		"experience_points": 2400,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "resourceful",
	},
	{
		"id": "eilidh_campbell",
		"rank": "Ens.",
		"name": "Eilidh Campbell",
		"short_name": "Campbell",
		"gender": "female",
		"national_origin": "Scotland",
		"language": "Scottish English",
		"voice_prefix": "Scottish female - ",
		"skill": "EXPERIENCED",
		"experience_points": 1700,
		"air_kills": 0,
		"ground_kills": 0,
		"temperament": "sharp",
	},
]

var _pilots_by_id: Dictionary = {}
var _assigned_pilot_id_by_callsign: Dictionary = {}
var _assigned_callsign_by_pilot_id: Dictionary = {}
var _assigned_aircraft_by_pilot_id: Dictionary = {}
var _flight_time_xp_remainder_by_pilot_id: Dictionary = {}
var _damage_credit_by_target_id: Dictionary = {}

func _ready() -> void:
	_build_pilot_index()

func _process(delta: float) -> void:
	_build_pilot_index()
	for pilot_id in _assigned_callsign_by_pilot_id.keys():
		if not _pilots_by_id.has(pilot_id):
			continue
		if not _is_pilot_actively_flying(str(pilot_id)):
			continue
		var pilot: Dictionary = _pilots_by_id[pilot_id]
		pilot["mission_time_s"] = float(pilot.get("mission_time_s", 0.0)) + delta
		pilot["current_sortie_time_s"] = float(pilot.get("current_sortie_time_s", 0.0)) + delta
		var xp_remainder := float(_flight_time_xp_remainder_by_pilot_id.get(pilot_id, 0.0))
		xp_remainder += delta * FLIGHT_TIME_XP_PER_SECOND
		var earned_xp := int(floor(xp_remainder))
		if earned_xp > 0:
			xp_remainder -= float(earned_xp)
			_add_experience(pilot, earned_xp)
			_apply_pilot_to_assigned_aircraft(str(pilot_id))
		_flight_time_xp_remainder_by_pilot_id[pilot_id] = xp_remainder

func get_carrier_roster() -> Array[Dictionary]:
	_build_pilot_index()
	var result: Array[Dictionary] = []
	for pilot_id in _sorted_pilot_ids():
		var pilot := _pilot_with_assignment(pilot_id)
		if not pilot.is_empty():
			result.append(pilot)
	return result

func get_pilot_for_callsign(callsign: String) -> Dictionary:
	_build_pilot_index()
	var key := _normalize_callsign(callsign)
	var pilot_id := str(_assigned_pilot_id_by_callsign.get(key, ""))
	if pilot_id == "":
		return {}
	return _pilot_with_assignment(pilot_id)

func get_voice_prefix_for_callsign(callsign: String) -> String:
	var pilot := get_pilot_for_callsign(callsign)
	return str(pilot.get("voice_prefix", ""))

func assign_aircraft_to_callsign(aircraft: Node3D, callsign: String) -> void:
	if not is_instance_valid(aircraft):
		return
	_build_pilot_index()
	var key := _normalize_callsign(callsign)
	if key == "":
		return
	var pilot_id := _pilot_id_for_aircraft(aircraft)
	if pilot_id == "":
		pilot_id = _assigned_pilot_id_for_callsign(key)
	if pilot_id == "":
		pilot_id = _pick_available_pilot_id()
	if pilot_id == "":
		return
	_assign_pilot_to_callsign(pilot_id, key)
	_apply_pilot_to_aircraft(aircraft, _pilot_with_assignment(pilot_id))

func release_callsign(callsign: String) -> void:
	var key := _normalize_callsign(callsign)
	if key == "":
		return
	var pilot_id := str(_assigned_pilot_id_by_callsign.get(key, ""))
	if pilot_id != "":
		_assigned_callsign_by_pilot_id.erase(pilot_id)
	_assigned_pilot_id_by_callsign.erase(key)

func record_kill_for_aircraft(aircraft: Node3D, target: Node3D) -> void:
	if not is_instance_valid(aircraft):
		return
	_build_pilot_index()
	var pilot_id := _pilot_id_for_aircraft(aircraft)
	if pilot_id == "" or not _pilots_by_id.has(pilot_id):
		return
	_award_kill_credit(pilot_id, target, 1.0)

func report_damage(attacker: Node, target: Node, damage_amount: float) -> void:
	if damage_amount <= 0.0:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	_build_pilot_index()
	var attacker_aircraft := _find_aircraft_node(attacker)
	if attacker_aircraft == null:
		return
	var pilot_id := _pilot_id_for_aircraft(attacker_aircraft)
	if pilot_id == "" or not _pilots_by_id.has(pilot_id):
		return
	var target_id := target.get_instance_id()
	var now_s := Time.get_ticks_msec() * 0.001
	var record: Dictionary = _damage_credit_by_target_id.get(target_id, {
		"target": target,
		"entries": {},
		"connected": false,
	})
	var entries: Dictionary = record.get("entries", {})
	var pilot_entry: Dictionary = entries.get(pilot_id, {
		"damage": 0.0,
		"last_damage_s": now_s,
	})
	pilot_entry["damage"] = float(pilot_entry.get("damage", 0.0)) + damage_amount
	pilot_entry["last_damage_s"] = now_s
	entries[pilot_id] = pilot_entry
	record["entries"] = entries
	record["target"] = target
	if not bool(record.get("connected", false)) and target.has_signal("destroyed"):
		target.connect("destroyed", func(_arg: Variant = null) -> void:
			_resolve_damage_credit_for_target(target_id)
		)
		record["connected"] = true
	_damage_credit_by_target_id[target_id] = record

func _resolve_damage_credit_for_target(target_id: int) -> void:
	if not _damage_credit_by_target_id.has(target_id):
		return
	var record: Dictionary = _damage_credit_by_target_id[target_id]
	var target_ref = record.get("target", null)
	var target := target_ref as Node3D if target_ref is Node3D else null
	var entries: Dictionary = record.get("entries", {})
	var now_s := Time.get_ticks_msec() * 0.001
	var recent_entries: Array[Dictionary] = []
	var total_damage := 0.0
	for pilot_id in entries.keys():
		var entry: Dictionary = entries[pilot_id]
		if now_s - float(entry.get("last_damage_s", -INF)) > DAMAGE_CREDIT_WINDOW_S:
			continue
		var damage := float(entry.get("damage", 0.0))
		if damage <= 0.0:
			continue
		recent_entries.append({
			"pilot_id": str(pilot_id),
			"damage": damage,
		})
		total_damage += damage
	_damage_credit_by_target_id.erase(target_id)
	if recent_entries.is_empty() or total_damage <= 0.0:
		return
	recent_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("damage", 0.0)) > float(b.get("damage", 0.0))
	)
	var top: Dictionary = recent_entries[0]
	var top_share := float(top.damage) / total_damage
	if recent_entries.size() >= 2:
		var second: Dictionary = recent_entries[1]
		var second_share := float(second.damage) / total_damage
		if second_share >= SHARED_KILL_MIN_DAMAGE_SHARE and top_share <= SHARED_KILL_TOP_DAMAGE_MAX_SHARE:
			_award_kill_credit(str(top.pilot_id), target, 0.5)
			_award_kill_credit(str(second.pilot_id), target, 0.5)
			return
	_award_kill_credit(str(top.pilot_id), target, 1.0)

func _award_kill_credit(pilot_id: String, target: Node3D, credit: float = 1.0) -> void:
	if pilot_id == "" or not _pilots_by_id.has(pilot_id):
		return
	var pilot: Dictionary = _pilots_by_id[pilot_id]
	var ground_kill := _is_ground_target(target)
	if ground_kill:
		pilot["ground_kills"] = float(pilot.get("ground_kills", 0.0)) + credit
	else:
		pilot["air_kills"] = float(pilot.get("air_kills", 0.0)) + credit
		_refresh_ace_status(pilot)
	var base_xp := GROUND_KILL_XP if ground_kill else AIR_KILL_XP
	_add_experience(pilot, int(round(float(base_xp) * credit)))
	_apply_pilot_to_assigned_aircraft(pilot_id)

func _build_pilot_index() -> void:
	if not _pilots_by_id.is_empty():
		return
	for pilot_template in PILOT_POOL:
		var pilot := pilot_template.duplicate(true)
		var pilot_id := str(pilot.get("id", ""))
		if pilot_id != "":
			_ensure_pilot_career_fields(pilot)
			_pilots_by_id[pilot_id] = pilot
	_assign_pilot_portraits()

func _assign_pilot_portraits() -> void:
	var catalog := _load_portrait_catalog()
	if catalog.is_empty():
		push_warning("PilotRoster: Portrait catalog is empty or unavailable")
		return
	var used_filenames: Dictionary = {}
	for pilot_id in _sorted_pilot_ids():
		if not _pilots_by_id.has(pilot_id):
			continue
		var pilot: Dictionary = _pilots_by_id[pilot_id]
		var filename := _choose_portrait_filename(pilot, catalog, used_filenames)
		if filename == "":
			continue
		var portrait_path := PORTRAIT_DIRECTORY + filename
		if not ResourceLoader.exists(portrait_path):
			push_warning("PilotRoster: Missing portrait texture %s" % portrait_path)
			continue
		pilot["portrait_path"] = portrait_path
		used_filenames[filename] = true

func _load_portrait_catalog() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var file := FileAccess.open(PORTRAIT_CATALOG_PATH, FileAccess.READ)
	if file == null:
		return entries
	if not file.eof_reached():
		file.get_csv_line() # Column names.
	while not file.eof_reached():
		var fields := file.get_csv_line()
		if fields.size() < 4:
			continue
		var filename := str(fields[0]).strip_edges()
		if filename == "":
			continue
		entries.append({
			"filename": filename,
			"presentation": str(fields[1]).strip_edges().to_lower(),
			"strong_regions": _split_catalog_regions(str(fields[2])),
			"additional_regions": _split_catalog_regions(str(fields[3])),
		})
	return entries

func _split_catalog_regions(value: String) -> Array[String]:
	var regions: Array[String] = []
	for part in value.split(";", false):
		var region := str(part).strip_edges()
		if region != "":
			regions.append(region)
	return regions

func _choose_portrait_filename(
	pilot: Dictionary,
	catalog: Array[Dictionary],
	used_filenames: Dictionary
) -> String:
	var target_presentation := _portrait_presentation_for_gender(str(pilot.get("gender", "")))
	var target_region := str(ORIGIN_PORTRAIT_REGIONS.get(str(pilot.get("national_origin", "")), ""))
	var candidates: Array[Dictionary] = []
	for entry in catalog:
		var presentation := str(entry.get("presentation", ""))
		var presentation_score := 0
		if presentation == target_presentation:
			presentation_score = 1000
		elif presentation == "ambiguous/androgynous":
			presentation_score = 500
		else:
			continue
		var region_score := 0
		var strong_regions: Array = entry.get("strong_regions", [])
		var additional_regions: Array = entry.get("additional_regions", [])
		if target_region != "" and target_region in strong_regions:
			region_score = 100
		elif target_region != "" and target_region in additional_regions:
			region_score = 50
		candidates.append({
			"filename": str(entry.get("filename", "")),
			"score": presentation_score + region_score,
		})
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := int(a.get("score", 0))
		var b_score := int(b.get("score", 0))
		if a_score != b_score:
			return a_score > b_score
		return str(a.get("filename", "")) < str(b.get("filename", ""))
	)

	# Select within each suitability tier using the stable pilot ID hash. This
	# avoids clustering every roster around the first few catalog images while
	# keeping portrait identity deterministic between runs.
	var pilot_id := str(pilot.get("id", ""))
	var stable_seed := int(pilot_id.hash()) & 0x7fffffff
	var candidate_index := 0
	while candidate_index < candidates.size():
		var tier_score := int(candidates[candidate_index].get("score", 0))
		var tier_end := candidate_index + 1
		while tier_end < candidates.size() and int(candidates[tier_end].get("score", 0)) == tier_score:
			tier_end += 1
		var tier_size := tier_end - candidate_index
		var tier_offset := stable_seed % tier_size
		for offset in range(tier_size):
			var index := candidate_index + ((tier_offset + offset) % tier_size)
			var filename := str(candidates[index].get("filename", ""))
			if filename != "" and not used_filenames.has(filename):
				return filename
		candidate_index = tier_end
	return ""

func _portrait_presentation_for_gender(gender: String) -> String:
	match gender.strip_edges().to_lower():
		"male":
			return "masculine-presenting"
		"female":
			return "feminine-presenting"
		_:
			return "ambiguous/androgynous"

func _pilot_with_assignment(pilot_id: String) -> Dictionary:
	if not _pilots_by_id.has(pilot_id):
		return {}
	var pilot: Dictionary = (_pilots_by_id[pilot_id] as Dictionary).duplicate(true)
	var assigned_callsign := str(_assigned_callsign_by_pilot_id.get(pilot_id, ""))
	pilot["assigned_callsign"] = _display_callsign(assigned_callsign) if assigned_callsign != "" else ""
	pilot["status"] = "assigned" if assigned_callsign != "" else "available"
	return pilot

func _pilot_id_for_aircraft(aircraft: Node3D) -> String:
	var pilot_id := str(aircraft.get_meta("pilot_roster_id", ""))
	if pilot_id != "" and _pilots_by_id.has(pilot_id):
		return pilot_id
	return ""

func _assigned_pilot_id_for_callsign(callsign: String) -> String:
	var pilot_id := str(_assigned_pilot_id_by_callsign.get(callsign, ""))
	if pilot_id != "" and _pilots_by_id.has(pilot_id):
		return pilot_id
	return ""

func _pick_available_pilot_id() -> String:
	for pilot_id in _sorted_pilot_ids():
		if not _assigned_callsign_by_pilot_id.has(pilot_id):
			return pilot_id
	return ""

func _assign_pilot_to_callsign(pilot_id: String, callsign: String) -> void:
	if not _pilots_by_id.has(pilot_id):
		return
	var old_callsign := str(_assigned_callsign_by_pilot_id.get(pilot_id, ""))
	if old_callsign != "" and old_callsign != callsign:
		_assigned_pilot_id_by_callsign.erase(old_callsign)
	var replaced_pilot_id := str(_assigned_pilot_id_by_callsign.get(callsign, ""))
	if replaced_pilot_id != "" and replaced_pilot_id != pilot_id:
		_assigned_callsign_by_pilot_id.erase(replaced_pilot_id)
		_assigned_aircraft_by_pilot_id.erase(replaced_pilot_id)
	if old_callsign == "":
		var pilot: Dictionary = _pilots_by_id[pilot_id]
		pilot["sorties_flown"] = int(pilot.get("sorties_flown", 0)) + 1
		pilot["current_sortie_time_s"] = 0.0
	_assigned_pilot_id_by_callsign[callsign] = pilot_id
	_assigned_callsign_by_pilot_id[pilot_id] = callsign

func _apply_pilot_to_aircraft(aircraft: Node3D, pilot: Dictionary) -> void:
	if pilot.is_empty():
		return
	var display_callsign := str(pilot.get("assigned_callsign", ""))
	var pilot_id := str(pilot.get("id", ""))
	if pilot_id != "":
		_assigned_aircraft_by_pilot_id[pilot_id] = aircraft
	aircraft.set_meta("pilot_identity", pilot.duplicate(true))
	aircraft.set_meta("pilot_roster_id", pilot_id)
	aircraft.set_meta("pilot_callsign", display_callsign)
	aircraft.set_meta("pilot_rank", str(pilot.get("rank", "")))
	aircraft.set_meta("pilot_name", str(pilot.get("short_name", pilot.get("name", ""))))
	aircraft.set_meta("pilot_full_name", str(pilot.get("name", "")))
	aircraft.set_meta("pilot_gender", str(pilot.get("gender", "")))
	aircraft.set_meta("pilot_national_origin", str(pilot.get("national_origin", "")))
	aircraft.set_meta("pilot_language", str(pilot.get("language", "")))
	aircraft.set_meta("pilot_temperament", str(pilot.get("temperament", "")))
	aircraft.set_meta("pilot_experience_points", int(pilot.get("experience_points", 0)))
	aircraft.set_meta("pilot_air_kills", float(pilot.get("air_kills", 0.0)))
	aircraft.set_meta("pilot_ground_kills", float(pilot.get("ground_kills", 0.0)))
	aircraft.set_meta("pilot_ace_status", str(pilot.get("ace_status", "")))
	aircraft.set_meta("pilot_ace_level", int(pilot.get("ace_level", 0)))
	aircraft.set_meta("pilot_mission_time_s", float(pilot.get("mission_time_s", 0.0)))
	aircraft.set_meta("pilot_current_sortie_time_s", float(pilot.get("current_sortie_time_s", 0.0)))
	aircraft.set_meta("pilot_sorties_flown", int(pilot.get("sorties_flown", 0)))
	aircraft.set_meta("pilot_display_name", _format_display_name(pilot))
	_apply_skill_to_aircraft(aircraft, str(pilot.get("skill", "EXPERIENCED")))

func _apply_pilot_to_assigned_aircraft(pilot_id: String) -> void:
	if not _pilots_by_id.has(pilot_id):
		return
	var aircraft_ref = _assigned_aircraft_by_pilot_id.get(pilot_id, null)
	if not is_instance_valid(aircraft_ref):
		_assigned_aircraft_by_pilot_id.erase(pilot_id)
		return
	_apply_pilot_to_aircraft(aircraft_ref as Node3D, _pilot_with_assignment(pilot_id))

func _ensure_pilot_career_fields(pilot: Dictionary) -> void:
	pilot["air_kills"] = float(pilot.get("air_kills", 0.0))
	pilot["ground_kills"] = float(pilot.get("ground_kills", 0.0))
	pilot["experience_points"] = int(pilot.get("experience_points", 0))
	pilot["mission_time_s"] = float(pilot.get("mission_time_s", 0.0))
	pilot["current_sortie_time_s"] = float(pilot.get("current_sortie_time_s", 0.0))
	pilot["sorties_flown"] = int(pilot.get("sorties_flown", 0))
	_refresh_ace_status(pilot)
	_refresh_skill_from_experience(pilot)

func _add_experience(pilot: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	pilot["experience_points"] = int(pilot.get("experience_points", 0)) + amount
	_refresh_skill_from_experience(pilot)

func _refresh_skill_from_experience(pilot: Dictionary) -> void:
	var xp := int(pilot.get("experience_points", 0))
	if xp >= ELITE_XP:
		pilot["skill"] = "ELITE"
	elif xp >= VETERAN_XP:
		pilot["skill"] = "VETERAN"
	elif xp >= EXPERIENCED_XP:
		pilot["skill"] = "EXPERIENCED"
	elif xp >= ROOKIE_XP:
		pilot["skill"] = "ROOKIE"
	else:
		pilot["skill"] = "RECRUIT"

func _refresh_ace_status(pilot: Dictionary) -> void:
	var air_kills := float(pilot.get("air_kills", 0.0))
	var ace_level := int(floor(air_kills / float(ACE_AIR_KILLS)))
	pilot["ace_level"] = ace_level
	if ace_level <= 0:
		pilot["ace_status"] = ""
	elif ace_level == 1:
		pilot["ace_status"] = "Ace"
	elif ace_level == 2:
		pilot["ace_status"] = "Double Ace"
	elif ace_level == 3:
		pilot["ace_status"] = "Triple Ace"
	else:
		pilot["ace_status"] = "%dx Ace" % ace_level

func _is_pilot_actively_flying(pilot_id: String) -> bool:
	var aircraft_ref = _assigned_aircraft_by_pilot_id.get(pilot_id, null)
	if not is_instance_valid(aircraft_ref):
		return false
	var aircraft := aircraft_ref as Node3D
	if bool(aircraft.get_meta("carrier_transport_mode", false)):
		return false
	if bool(aircraft.get_meta("parking_brake", false)):
		return false
	return true

func _find_aircraft_node(node: Node) -> Node3D:
	var current := node
	while current != null:
		if current is Node3D and (current.is_in_group("aircraft") or current.is_in_group("ai_aircraft") or current is Aircraft):
			return current as Node3D
		current = current.get_parent()
	return null

func _apply_skill_to_aircraft(aircraft: Node3D, skill_name: String) -> void:
	var ai_pilot := aircraft.find_child("AIPilot", true, false) as AIPilot
	if ai_pilot == null:
		return
	ai_pilot.skill = _skill_to_ai_value(skill_name)
	ai_pilot.apply_skill_preset()

func _skill_to_ai_value(skill_name: String) -> AIPilot.AIPilotSkill:
	match skill_name.to_upper():
		"RECRUIT":
			return AIPilot.AIPilotSkill.RECRUIT
		"ROOKIE":
			return AIPilot.AIPilotSkill.ROOKIE
		"VETERAN":
			return AIPilot.AIPilotSkill.VETERAN
		"ELITE":
			return AIPilot.AIPilotSkill.ELITE
		_:
			return AIPilot.AIPilotSkill.EXPERIENCED

func _format_display_name(pilot: Dictionary) -> String:
	var callsign := str(pilot.get("assigned_callsign", ""))
	if callsign == "":
		return "%s %s" % [str(pilot.get("rank", "")), str(pilot.get("short_name", pilot.get("name", "")))]
	return "%s \"%s\" %s" % [
		str(pilot.get("rank", "")),
		callsign,
		str(pilot.get("short_name", pilot.get("name", ""))),
	]

func _sorted_pilot_ids() -> Array[String]:
	var result: Array[String] = []
	for pilot_template in PILOT_POOL:
		var pilot_id := str(pilot_template.get("id", ""))
		if pilot_id != "":
			result.append(pilot_id)
	return result

func _normalize_callsign(callsign: String) -> String:
	return callsign.strip_edges().to_lower()

func _display_callsign(callsign: String) -> String:
	var words := callsign.split(" ", false)
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)

func _is_ground_target(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	return target.is_in_group("ground_vehicles") \
		or target.is_in_group("turrets") \
		or target.is_in_group("buildings") \
		or target.is_in_group("enemy_structures")
