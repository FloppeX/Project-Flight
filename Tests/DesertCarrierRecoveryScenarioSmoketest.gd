extends SceneTree

const MODE_PATH := "res://Scenario/CarrierCombatTestMode.gd"
const MANAGER_PATH := "res://Scenario/ScenarioManager.gd"
const FLIGHT_DECK_PATH := "res://LandCarrier/FlightDeckManager.gd"
const RUNNER_PATH := "res://tools/run_carrier_desert_recovery_test.ps1"
const EXPECTED_MODELS: PackedStringArray = [
	"Aircraft_1", "Aircraft_2", "Aircraft_5", "Aircraft_7", "Aircraft_8",
]
const EXPECTED_STAGES: PackedStringArray = [
	"launch_complete", "outbound_complete", "rtb_started",
	"recovery_route", "pre_landing", "final_handoff", "confirmed_landing",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var mode_source := _read_text(MODE_PATH)
	if mode_source.is_empty():
		_fail("could not read carrier recovery harness")
		return
	for required_text in [
		"const PROFILE_DESERT_RECOVERY := \"desert_recovery\"",
		"@export_range(1, 8, 1) var desert_recovery_active_cap: int = 6",
		"@export_range(0, 1000, 1) var desert_recovery_target_traps: int = 24",
		"rolling_finite_cohort = false",
		"_ensure_desert_recovery_hangar_stock()",
		"prioritize_ai_launch_refill_over_waiting_recovery",
		"var request_count := rolling_active_aircraft_max - committed_active",
		"_request_desert_recovery_launches()",
		"DESERT_REFILL_WAIT",
		"DESERT_REFILL_ORDER requested=%d queued=%d active=%d committed=%d/%d",
		"_desert_recovery_site_is_open(candidate_position)",
		"desert_recovery_outbound_distance_m: float = 10000.0",
		"desert_recovery_open_radius_m: float = 900.0",
		"desert_recovery_final_corridor_length_m: float = 3200.0",
		"desert_recovery_final_corridor_half_width_m: float = 350.0",
		"desert_recovery_final_corridor_max_relief_m: float = 80.0",
		"_desert_recovery_final_corridor_is_open(",
		"desert_recovery_recall_arm_fraction: float = 0.5",
		"DESERT_RECALL_ARMED",
		"random_delay_after_halfway",
		"OpsOrderModel.recover()",
		"desert_recovery_diagnostic_final_attempt: bool = true",
		"recovery_diagnostic_force_final_handoff",
		"strict_gate_passed=%s diagnostic_override=%s",
	]:
		if not mode_source.contains(required_text):
			_fail("missing dedicated recovery contract: %s" % required_text)
			return
	for model in EXPECTED_MODELS:
		if not mode_source.contains("\"%s\"" % model):
			_fail("recovery roster omits %s" % model)
			return
		var scene_text := _read_text("res://Aircraft/%s.tscn" % model).replace(" ", "")
		for required_node in ["name=\"AIPilot\"", "name=\"LandingGear\"", "name=\"TailHook\""]:
			if not scene_text.contains(required_node):
				_fail("%s lacks recovery node %s" % [model, required_node])
				return
	for stage_key in EXPECTED_STAGES:
		if not mode_source.contains("\"%s\"" % stage_key):
			_fail("missing staged telemetry counter: %s" % stage_key)
			return
	var flight_deck_source := _read_text(FLIGHT_DECK_PATH)
	for scheduling_contract in [
		"var prioritize_ai_launch_refill_over_waiting_recovery: bool = false",
		"or prioritize_ai_launch_refill_over_waiting_recovery",
		"and not prioritize_ai_launch_refill_over_waiting_recovery",
		"prioritize_ai_launch_refill_over_waiting_recovery and _ai_launch_queue > 0",
	]:
		if not flight_deck_source.contains(scheduling_contract):
			_fail("missing refill deck priority contract: %s" % scheduling_contract)
			return

	# Final capture authority remains in AIPilot. The profile may request a noisy
	# diagnostic attempt, but must not tune strict final or wire thresholds.
	for token in [
		"recovery_final_handoff_max_lateral_error_m",
		"recovery_final_handoff_max_track_error_deg",
		"recovery_final_handoff_max_bank_deg",
	]:
		if mode_source.contains("set(\"%s\"" % token) \
				or mode_source.contains("pilot.set(\"%s\"" % token):
			_fail("scenario overrides strict final gate: %s" % token)
			return

	var manager_source := _read_text(MANAGER_PATH)
	if not manager_source.contains("CARRIER_DESERT_RECOVERY_PROFILE") \
			or not manager_source.contains("return \"open_canyons\""):
		_fail("desert profile does not force the open-canyons terrain baseline")
		return
	var runner_source := _read_text(RUNNER_PATH)
	if not runner_source.contains("[ValidateRange(1, 8)]") \
			or not runner_source.contains("[int]$ActiveAircraft = 6") \
			or not runner_source.contains("[int]$TargetTraps = 24") \
			or not runner_source.contains("--rolling-target-traps=$TargetTraps") \
			or not runner_source.contains("--test-profile=desert_recovery"):
		_fail("focused runner does not expose the six-to-eight active cap")
		return

	var selector: Variant = JSON.parse_string(
		_read_text("res://Scenario/carrier_desert_recovery_test.json")
	)
	if not (selector is Dictionary) \
			or int((selector as Dictionary).get("scenario", -1)) != 6 \
			or str((selector as Dictionary).get("profile", "")) != "desert_recovery":
		_fail("dedicated scenario selector is invalid")
		return

	var ai_source := _read_text("res://AI/AIPilot.gd")
	for diagnostic_token in [
		"[AIPilot RECOVERY_HANDOFF] diagnostic_override",
		"failed_gate_summary",
		"normal_gate_passed=false",
		"_landing_snap(\"DIAGNOSTIC-HANDOFF\"",
		"[AIPilot FINAL_OUTCOME] aircraft=%s handoff=%s outcome=%s",
	]:
		if not ai_source.contains(diagnostic_token):
			_fail("missing noisy final-attempt telemetry: %s" % diagnostic_token)
			return

	print("[DesertCarrierRecoveryScenarioSmoketest] PASS cap=6 expandable=8 target_traps=24 rolling_refill=full_deficit launch_priority=waiting_recovery models=1,2,5,7,8 outbound=10km recall=random_after_halfway autonomous=launch+outbound+recall+recovery telemetry=gate_failures+7_stages diagnostic_final=true final_capture+wire_gates=unchanged")
	quit(0)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _fail(reason: String) -> void:
	push_error("[DesertCarrierRecoveryScenarioSmoketest] FAIL %s" % reason)
	quit(1)
