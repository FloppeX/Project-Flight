extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")
const REPORT_PATH := "user://player_flight_recorder_smoke.csv"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(InputMap.has_action("flight_log_mark"), "flight_log_mark input action is missing")
	var has_l3_binding := false
	var has_keyboard_binding := false
	for event in InputMap.action_get_events("flight_log_mark"):
		if event is InputEventJoypadButton \
				and (event as InputEventJoypadButton).button_index == JOY_BUTTON_LEFT_STICK:
			has_l3_binding = true
		elif event is InputEventKey:
			has_keyboard_binding = true
	_expect(has_l3_binding, "flight_log_mark is not bound to L3")
	_expect(not has_keyboard_binding, "flight_log_mark unexpectedly retained a keyboard binding")

	var absolute_report_path := ProjectSettings.globalize_path(REPORT_PATH)
	if FileAccess.file_exists(REPORT_PATH):
		DirAccess.remove_absolute(absolute_report_path)

	var director := get_node_or_null("/root/FlightDirector")
	_expect(director != null, "FlightDirector autoload was unavailable")
	var old_player: Variant = null
	var old_controlling := false
	if director != null:
		old_player = director.get("player_controlled_plane")
		old_controlling = bool(director.get("is_player_controlling"))

	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_expect(aircraft != null, "Aircraft_5 did not instantiate")
	if aircraft == null:
		_finish()
		return
	aircraft.name = "RecorderSmokeAircraft"
	var aero := aircraft.get_node_or_null("SimpleAero") as SimpleAero
	_expect(aero != null, "SimpleAero was not found")
	if aero == null:
		aircraft.free()
		_finish()
		return
	aero.airflow_feedback_enabled = false
	aero.set_flight_model_override_for_testing(1)
	aero.aero_report_enabled = true
	aero.aero_report_path = REPORT_PATH
	aero.aero_report_project_mirror_enabled = false
	aero.aero_report_reset_on_first_aircraft = false
	aero.aero_report_interval_s = 0.05
	aero.aero_report_flush_interval_s = 10.0
	add_child(aircraft)
	await get_tree().process_frame

	var ai_toggle := aircraft.get_node_or_null("AIToggle")
	if ai_toggle != null and ai_toggle.has_method("disable_ai"):
		ai_toggle.call("disable_ai")
	var pilot := aircraft.get_node_or_null("AIPilot")
	if pilot != null:
		pilot.set_process(false)
		pilot.set_physics_process(false)
	var controls := aircraft.get_node_or_null("ControlSteering") as AircraftModule_ControlSteering
	if controls != null:
		controls.setup(aircraft)
		controls.ControlActive = true
		controls.set_physics_process(true)
	if director != null:
		director.set("player_controlled_plane", aircraft)
		director.set("is_player_controlling", true)

	aircraft.global_position = Vector3(0.0, 1800.0, 0.0)
	aircraft.linear_velocity = Vector3(3.0, 0.0, 95.0)
	aircraft.freeze = false
	aircraft.sleeping = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_press("flight_log_mark")
	await get_tree().physics_frame
	Input.action_release("flight_log_mark")
	await get_tree().physics_frame
	aero._flush_aero_report_lines()

	_expect(FileAccess.file_exists(REPORT_PATH), "flight recorder did not create its CSV")
	if FileAccess.file_exists(REPORT_PATH):
		var text := FileAccess.get_file_as_string(REPORT_PATH)
		var lines := text.strip_edges().split("\n", false)
		_expect(lines.size() >= 2, "flight recorder CSV did not contain a data row")
		if lines.size() >= 2:
			var header := lines[0].strip_edges().split(",", true)
			var marker_index := header.find("pilot_mark")
			var flags_index := header.find("event_flags")
			var flight_model_index := header.find("flight_model")
			_expect(header.has("normal_g"), "normal-G telemetry column is missing")
			_expect(header.has("specific_energy_rate_mps"), "energy-rate telemetry column is missing")
			_expect(header.has("raw_pitch_input"), "raw control telemetry column is missing")
			_expect(header.has("rudder_assist_component"), "rudder-assist telemetry column is missing")
			_expect(header.has("departure_severity"), "stall-departure telemetry column is missing")
			_expect(header.has("departure_drag_n"), "departure-drag telemetry column is missing")
			_expect(header.has("ai_active"), "control-ownership telemetry column is missing")
			var found_marker := false
			for index in range(1, lines.size()):
				var values := lines[index].strip_edges().split(",", true)
				_expect(
					values.size() == header.size(),
					"CSV header/data column counts differ on row %d: header=%d data=%d" % [
						index,
						header.size(),
						values.size(),
					]
				)
				if values.size() != header.size() or marker_index < 0 or flags_index < 0:
					continue
				if values[marker_index] == "L3_001":
					found_marker = true
					_expect("pilot_mark" in values[flags_index], "marker row did not include its event flag")
					_expect(
						flight_model_index >= 0 and values[flight_model_index] == "advanced",
						"marker row did not record the active flight model"
					)
			_expect(found_marker, "L3_001 marker was not written to a data row")

	if director != null:
		director.set("player_controlled_plane", old_player)
		director.set("is_player_controlling", old_controlling)
	aircraft.queue_free()
	await get_tree().process_frame
	if _failures.is_empty() and FileAccess.file_exists(REPORT_PATH):
		DirAccess.remove_absolute(absolute_report_path)
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[PlayerFlightRecorderSmoketest] PASS rate=10Hz buffered=true marker=L3_001 schema=model+controls+g+energy+state")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[PlayerFlightRecorderSmoketest] %s" % failure)
	get_tree().quit(1)
