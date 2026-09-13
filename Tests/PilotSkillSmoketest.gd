extends Node
const Profile = preload("res://AI/PilotSkillProfile.gd")
const Track = preload("res://AI/VisualContactTrack.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _ready() -> void:
	var previous_recognition := INF
	var previous_error := INF
	for tier in 5:
		var profile := Profile.for_skill(tier)
		var track = Track.new()
		track.observe(Vector3(0, 1000, 500), Vector3(0, 0, 80), 0, profile)
		check(track.sample(0, 10).is_empty(), "Glimpse cannot expose target before recognition")
		check(track.is_recognizing(0) and not track.is_recognizing(0.3), "Recognition grace requires a fresh actual glimpse")
		var acquired := -1.0
		for tick in range(1, 41):
			var now := tick * 0.05
			track.observe(Vector3(0, 1000, 500 + now * 80), Vector3(0, 0, 80), now, profile)
			if acquired < 0 and not track.sample(now, 10).is_empty():
				acquired = now
		check(acquired > 0 and acquired < previous_recognition, "Recognition must improve across all five tiers")
		previous_recognition = acquired
		track.observe(Vector3(4, 1000, 660), Vector3(80, 0, 0), 2.05, profile)
		var error: float = track.velocity.distance_to(Vector3(80, 0, 0))
		check(error > 0 and error < previous_error, "Better pilots estimate a changed target velocity sooner, not perfectly")
		previous_error = error
		var remembered := track.sample(2.05, 10)
		track.visible = false
		track.observe(Vector3(9000, 1000, 9000), Vector3(0, 200, 0), 5, profile)
		var pending := track.sample(5, 10)
		check(not pending.visible and track.observed_at == 2.05, "Reacquisition delay must not leak new position or velocity")
		var before: Vector3 = pending.position
		track.shift_origin(Vector3(100, 0, 50))
		check(track.sample(5, 10).position.distance_to(before - Vector3(100, 0, 50)) < 0.01, "Estimated memory rebases exactly once")
		check(track.sample(20, 10).expired, "All skills lose expired memory")
		print("SKILL_PROBE tier=%d acquisition_s=%.2f velocity_step_error=%.2f" % [tier, acquired, error])
	var pilot := AIPilot.new()
	pilot.dogfight_corner_speed_mps = 91.0
	for tier in 5:
		pilot.skill = tier
		pilot.apply_skill_preset()
		var gain := pilot.dogfight_precision_direct_pitch_gain
		pilot.apply_skill_preset()
		check(pilot.dogfight_precision_direct_pitch_gain == gain, "Preset application is idempotent")
		check(gain == 26.0 and pilot.dogfight_precision_pid_scale == 0.55, "Every tier retains stable trimming authority")
		check(pilot.dogfight_corner_speed_mps == 91.0, "Skill cannot overwrite aircraft corner speed")
		check(pilot.dogfight_min_hit_chance == 0.72 and pilot.dogfight_fire_precise_min_blend == 0.90, "Shot patience is not a skill penalty")
		check(pilot.dogfight_fire_burst_s == 0.55 and pilot.dogfight_burst_cooldown_s == 0.22, "Neutral burst policy is shared across tiers")
	pilot.free()
	print("PILOT_SKILL_SMOKETEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
