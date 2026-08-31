extends SceneTree

const PilotAppearance := preload("res://Aircraft/PilotAppearance.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var pilot_roster := root.get_node_or_null("PilotRoster")
	if pilot_roster == null or not is_instance_valid(pilot_roster):
		_fail("PilotRoster autoload is unavailable")
		_finish()
		return

	pilot_roster.call("start_new_campaign", 1801)
	var first_roster: Array[Dictionary] = pilot_roster.call("get_carrier_roster")
	_validate_campaign_roster(first_roster)
	var first_signature := _identity_signature(first_roster)

	pilot_roster.call("start_new_campaign", 2903)
	var second_roster: Array[Dictionary] = pilot_roster.call("get_carrier_roster")
	_validate_campaign_roster(second_roster)
	_expect(
		_identity_signature(second_roster) != first_signature,
		"different campaign seeds generate different pilot identities"
	)

	# A saved campaign must restore its exact generated roster rather than
	# rerolling names or personal callsigns when loaded.
	var saved_state: Dictionary = pilot_roster.call("capture_save_state")
	pilot_roster.call("start_new_campaign", 3907)
	_expect(bool(pilot_roster.call("restore_save_state", saved_state)), "saved pilot roster restores")
	_expect(
		_identity_signature(pilot_roster.call("get_carrier_roster")) == _identity_signature(second_roster),
		"save/load preserves the campaign roster"
	)

	# Draw and release the entire roster. The shuffled bag should use every
	# available pilot once before recycling anyone, while formation positions
	# remain separate from persistent personal callsigns.
	pilot_roster.call("start_new_campaign", 4909)
	var campaign_roster: Array[Dictionary] = pilot_roster.call("get_carrier_roster")
	var roster_size := campaign_roster.size()
	var selected_pilot_ids: Dictionary = {}
	for index in range(roster_size):
		var aircraft := Node3D.new()
		aircraft.name = "PilotRosterMock%d" % index
		root.add_child(aircraft)
		pilot_roster.call("assign_aircraft_to_callsign", aircraft, "Carrier Pilot %d" % index)
		var station := "Archer %d" % (index + 1)
		pilot_roster.call("assign_aircraft_to_flight_callsign", aircraft, station)

		var pilot_id := str(aircraft.get_meta("pilot_roster_id", ""))
		var personal_callsign := str(aircraft.get_meta("pilot_callsign", ""))
		var display_name := str(aircraft.get_meta("pilot_display_name", ""))
		_expect(pilot_id != "", "flight receives a roster pilot")
		_expect(not selected_pilot_ids.has(pilot_id), "pilot draw does not repeat before roster exhaustion")
		_expect(personal_callsign != "", "assigned pilot keeps a personal callsign")
		_expect(personal_callsign.to_lower() != station.to_lower(), "flight station does not replace personal callsign")
		_expect(display_name.contains('"%s"' % personal_callsign), "display name uses the personal callsign")
		_expect(not display_name.contains(station), "display name excludes the formation station")
		_expect(
			str(aircraft.get_meta("pilot_flight_callsign", "")).to_lower() == station.to_lower(),
			"formation station remains available as separate metadata"
		)
		var station_pilot: Dictionary = pilot_roster.call("get_pilot_for_callsign", station)
		_expect(str(station_pilot.get("id", "")) == pilot_id, "formation radio lookup resolves the assigned pilot")
		_expect(
			PilotAppearance.is_valid_palette(aircraft.get_meta(PilotAppearance.META_KEY, {}))
					and aircraft.get_meta(PilotAppearance.META_KEY, {}) \
					== station_pilot.get(PilotAppearance.IDENTITY_FIELD, {}),
			"aircraft receives its assigned pilot's persistent appearance"
		)
		selected_pilot_ids[pilot_id] = true
		pilot_roster.call("release_aircraft", aircraft)
		aircraft.free()

	_expect(selected_pilot_ids.size() == roster_size, "the randomized draw rotates through the whole roster")
	_finish()


func _validate_campaign_roster(roster: Array[Dictionary]) -> void:
	_expect(not roster.is_empty(), "campaign roster is populated")
	var names: Dictionary = {}
	var callsigns: Dictionary = {}
	var helmet_combinations: Dictionary = {}
	for pilot in roster:
		var full_name := str(pilot.get("name", "")).strip_edges()
		var callsign := str(pilot.get("callsign", "")).strip_edges()
		_expect(full_name != "", "campaign pilot has a name")
		_expect(callsign != "", "campaign pilot has a personal callsign")
		_expect(not names.has(full_name.to_lower()), "campaign pilot names are unique")
		_expect(not callsigns.has(callsign.to_lower()), "campaign pilot callsigns are unique")
		var palette: Variant = pilot.get(PilotAppearance.IDENTITY_FIELD, null)
		_expect(PilotAppearance.is_valid_palette(palette), "campaign pilot has a valid appearance palette")
		if PilotAppearance.is_valid_palette(palette):
			var colors := palette as Dictionary
			helmet_combinations[
				"%s|%s" % [colors.get("helmet_color_1"), colors.get("helmet_color_2")]
			] = true
		names[full_name.to_lower()] = true
		callsigns[callsign.to_lower()] = true
	_expect(helmet_combinations.size() > 1, "campaign pilots have visibly varied helmet palettes")


func _identity_signature(roster: Array[Dictionary]) -> String:
	var identities: Array[String] = []
	for pilot in roster:
		identities.append("%s|%s|%s" % [
			pilot.get("name", ""),
			pilot.get("callsign", ""),
			pilot.get(PilotAppearance.IDENTITY_FIELD, {}),
		])
	identities.sort()
	return "\n".join(identities)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_fail(description)


func _fail(description: String) -> void:
	_failures.append(description)
	push_error("[PilotRosterRandomizationSmoketest] FAIL: %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("[PilotRosterRandomizationSmoketest] PASS")
		quit(0)
		return
	print("[PilotRosterRandomizationSmoketest] %d failure(s)" % _failures.size())
	quit(1)
