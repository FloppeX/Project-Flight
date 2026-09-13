extends Node3D
## Opt-in visible scenario-5 observer. No forces, damage immunity or mid-flight resets.
const CASES := [
	{"label": "waveoff_50m", "behind_m": 500.0, "alt_m": 50.5, "speed_mps": 60.0, "fpa_deg": 5.9, "force_height_m": 50.0, "press_final": true},
	{"label": "waveoff_50m_steep", "behind_m": 350.0, "alt_m": 50.5, "speed_mps": 65.0, "fpa_deg": 12.0, "force_height_m": 50.0, "press_final": true},
	{"label": "waveoff_20m", "behind_m": 300.0, "alt_m": 20.5, "speed_mps": 60.0, "fpa_deg": 5.9, "force_height_m": 20.0, "press_final": true},
	{"label": "waveoff_10m", "behind_m": 180.0, "alt_m": 10.5, "speed_mps": 64.0, "fpa_deg": 5.9, "force_height_m": 10.0, "press_final": true},
	{"label": "automatic_high_miss", "behind_m": 200.0, "alt_m": 72.0, "speed_mps": 60.0, "fpa_deg": 5.9, "press_final": true},
	{"label": "deliberate_missed_wire", "behind_m": 700.0, "alt_m": 95.0, "speed_mps": 60.0, "fpa_deg": 5.9, "miss_wire": true, "press_final": true},
	{"label": "touchdown_bolter", "behind_m": 150.0, "alt_m": 9.5, "speed_mps": 55.0, "fpa_deg": 3.0, "miss_wire": true, "suppress_automatic_miss": true, "press_final": true},
]

const LANDING_RETRY_CASES := [
	{"label": "normal_d1000_v60", "behind_m": 1000.0, "alt_m": 105.0, "speed_mps": 60.0, "fpa_deg": 5.9, "press_final": true},
	{"label": "normal_d700_v60", "behind_m": 700.0, "alt_m": 73.0, "speed_mps": 60.0, "fpa_deg": 5.9, "press_final": true},
	{"label": "normal_d1000_v70", "behind_m": 1000.0, "alt_m": 105.0, "speed_mps": 70.0, "fpa_deg": 5.9, "press_final": true},
	{"label": "high_d200_retry", "behind_m": 200.0, "alt_m": 72.0, "speed_mps": 60.0, "fpa_deg": 5.9, "press_final": true},
]

var harness: Node
var landing_retry_mode := false
var camera: Camera3D
var label: Label
var tracked_id := 0
var telemetry_timer := 0.0

func _ready() -> void:
	process_priority = 100
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Project Flight - landing retry test" if landing_retry_mode else "Project Flight - go-around test")
		camera = Camera3D.new()
		camera.fov = 65.0
		camera.far = 30000.0
		add_child(camera)
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		label = Label.new()
		label.position = Vector2(25, 95)
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.text = ("HOOK-DOWN LANDING TEST" if landing_retry_mode else "GO-AROUND TEST") + " — waiting for carrier placement"
		layer.add_child(label)

func _process(delta: float) -> void:
	telemetry_timer -= delta
	for name in harness.get("_attempts"):
		var attempt: Dictionary = harness.get("_attempts")[name]
		if str(attempt.get("outcome", "")) != "":
			continue
		var craft_value: Variant = attempt.get("node")
		if not is_instance_valid(craft_value):
			continue
		var craft := craft_value as RigidBody3D
		var pilot := craft.find_child("AIPilot", true, false)
		var carrier: Node3D = harness.call("_carrier")
		if not is_instance_valid(pilot) or not is_instance_valid(carrier):
			continue
		var entry: Dictionary = attempt.get("entry_case", {})
		var height := craft.global_position.y - float(harness.call("_landing_test_deck_y", carrier))
		var bank := rad_to_deg(atan2(craft.global_basis.x.y, craft.global_basis.y.y))
		var state := int(pilot.get("current_state"))
		var age := float(harness.get("_elapsed_s")) - float(attempt.get("spawn_t", 0.0))
		var hook: Area3D = pilot.call("_get_landing_sight_hook_sensor")
		var hook_armed := is_instance_valid(hook) and hook.monitoring
		var hook_status := "ACTIVE" if hook_armed else "inactive"
		var aero := craft.get_node_or_null("SimpleAero")
		var flap_position := float(aero.call("_get_flap_position")) if is_instance_valid(aero) else 0.0
		var flap_status := flap_position > 0.5
		if not attempt.has("observed_flap_status") or bool(attempt.observed_flap_status) != flap_status:
			print("[GoAroundTest] FLAPS %s state=%d actual=%.2f effective_stall=%.1f floor=%.1f age=%.1f" % [
				entry.label, state, flap_position, aero.call("get_effective_stall_speed_mps"),
				pilot.call("_get_landing_stall_floor_mps"), age])
			attempt["observed_flap_status"] = flap_status
		if str(attempt.get("observed_hook_status", "")) != hook_status:
			print("[GoAroundTest] HOOK %s state=%d sensor=%s age=%.1f" % [entry.label, state, hook_status, age])
			attempt["observed_hook_status"] = hook_status
		if state == 16:
			var hook_key := "hook_armed_final_samples" if hook_armed else "hook_inactive_final_samples"
			attempt[hook_key] = int(attempt.get(hook_key, 0)) + 1
		if not landing_retry_mode and bool(entry.get("miss_wire", false)):
			# Deliberately retract only the hook, not gear/flaps. The pilot must detect
			# the real missed last wire; the test does not manufacture a bolter state.
			var gear: Variant = pilot.get("control_gear")
			if is_instance_valid(gear):
				if gear.has_method("send_to_tailhooks"):
					gear.call("send_to_tailhooks", "stow")
				if gear.has_method("send_to_tailhook_simple"):
					gear.call("send_to_tailhook_simple", false)
		if not landing_retry_mode and state == 16 and age >= 0.25 and entry.has("force_height_m") \
				and not bool(attempt.get("test_forced", false)):
			attempt["test_forced"] = bool(pilot.call("request_landing_wave_off", "test: " + str(entry.label)))
			print("[GoAroundTest] TRIGGER %s height=%.1f speed=%.1f vs=%.1f bank=%.1f" % [entry.label, height, craft.linear_velocity.length(), craft.linear_velocity.y, bank])
		if state == 17:
			attempt["escape_seen"] = true
		var clear_of_carrier := bool(pilot.call("_is_bolter_clear_of_carrier"))
		var stable := bool(attempt.get("escape_seen", false)) and clear_of_carrier and height >= 35.0 \
			and absf(bank) < 15.0 and craft.linear_velocity.y >= 0.0 \
			and craft.linear_velocity.length() >= float(pilot.call("_get_landing_stall_floor_mps")) + 5.0
		attempt["escape_stable_s"] = float(attempt.get("escape_stable_s", 0.0)) + delta if stable else 0.0
		if telemetry_timer <= 0.0:
			print("[GoAroundTest] SAMPLE %s age=%.1f state=%d h=%.1f speed=%.1f vs=%.1f bank=%.1f inputs=%.2f/%.2f/%.2f load=%.2f/%.2f safety=%s" % [
				entry.label, age, state, height, craft.linear_velocity.length(), craft.linear_velocity.y, bank,
				pilot.get("roll_input"), pilot.get("pitch_input"), pilot.get("throttle_input"),
				pilot.get("_coordinated_turn_measured_g"), pilot.get("_coordinated_turn_target_g"), pilot.get("_safety_override_active")])
			telemetry_timer = 0.25 if state == 17 or height < 30.0 else 1.0
		if is_instance_valid(camera):
			var forward := craft.linear_velocity.normalized()
			forward.y = 0.0
			forward = forward.normalized() if forward.length_squared() > 0.01 else carrier.global_basis.z
			var wanted := craft.global_position - forward * 38.0 + carrier.global_basis.x * 12.0 + Vector3.UP * 10.0
			camera.global_position = wanted if tracked_id != craft.get_instance_id() else camera.global_position.lerp(wanted, 1.0 - exp(-delta * 5.0))
			tracked_id = craft.get_instance_id()
			camera.look_at(craft.global_position + forward * 15.0, Vector3.UP)
			camera.make_current()
			var purpose := "HOOK HELD RETRACTED ON PURPOSE — missed-wire test" if bool(entry.get("miss_wire", false)) \
				else ("FORCED WAVE-OFF — not a landing attempt" if entry.has("force_height_m") else "AUTOMATIC ABORT — high approach test")
			if landing_retry_mode:
				purpose = "NORMAL HOOK CONTROL — retry until stopped catch | Hook sensor: " + hook_status
				purpose += "\nFlaps %.0f%% | Landing speed floor %.1f m/s" % [flap_position * 100.0, pilot.call("_get_landing_stall_floor_mps")]
			label.text = "%s — %s %d/%d: %s\n%s\nHeight %.1f m | Speed %.1f m/s | V/S %+.1f m/s | Bank %+.1f°\n%s | Power %.0f%% | Pitch %+.2f\n%s" % [
				"LANDING RETRY" if landing_retry_mode else "GO-AROUND TEST",
				str(attempt.get("aircraft_model", "Aircraft")),
				attempt.spawn_index, int(harness.get("_attempt_limit")), entry.label, purpose, height, craft.linear_velocity.length(), craft.linear_velocity.y, bank,
				"GO AROUND" if state == 17 else "APPROACH / REJOIN", float(pilot.get("throttle_input")) * 100.0,
				pilot.get("pitch_input"), JSON.stringify(harness.get("_tally"))]
		if not landing_retry_mode and float(attempt.get("escape_stable_s", 0.0)) >= 2.0:
			print("[GoAroundTest] ESCAPED %s age=%.1f touchdown=%s" % [entry.label, age, attempt.get("touchdown_class", "NONE")])
			harness.call("_finish", name, "ESCAPED")
		break
