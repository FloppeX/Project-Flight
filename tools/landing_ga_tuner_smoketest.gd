extends SceneTree

const TUNER_SCRIPT := preload("res://AI/LandingGeneticTuner.gd")
const TEMP_PATHS := [
	"user://landing_ga_smoketest_state.json",
	"user://landing_ga_smoketest.log",
	"user://landing_ga_smoketest_champion.json",
	"user://landing_ga_smoketest_project.log",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in TEMP_PATHS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var tuner := Node.new()
	tuner.set_script(TUNER_SCRIPT)
	tuner.set("population_size", 4)
	tuner.set("case_count", 2)
	tuner.set("curriculum_level_count", 2)
	tuner.set("curriculum_promote_catches", 1)
	tuner.set("state_path", TEMP_PATHS[0])
	tuner.set("log_path", TEMP_PATHS[1])
	tuner.set("champion_project_path", TEMP_PATHS[2])
	tuner.set("project_log_path", TEMP_PATHS[3])
	root.add_child(tuner)
	for trial in range(8):
		var assignment: Dictionary = tuner.call("next_assignment")
		var caught := trial % 2 == 0
		tuner.call("record_result", assignment, {
			"outcome": "CAUGHT" if caught else "BOLTER",
			"duration_s": 90.0 + trial,
			"reached_glideslope": true,
			"reached_final": true,
			"min_remaining_m": 2.0,
			"min_lateral_m": 1.5 + trial * 0.1,
			"min_vertical_m": 1.0,
			"final_samples": 100,
			"mean_fpv_yaw_error_deg": 1.0 + trial * 0.1,
			"mean_fpv_pitch_error_deg": 0.8,
		})
	var status: Dictionary = tuner.call("get_status")
	var passed := int(status.get("generation", -1)) == 1 \
		and int(status.get("curriculum", -1)) == 1 \
		and int(status.get("candidate", -1)) == 0 \
		and int(status.get("case", -1)) == 0 \
		and FileAccess.file_exists(TEMP_PATHS[2])
	print("LANDING_GA_SMOKETEST %s status=%s" % ["PASS" if passed else "FAIL", JSON.stringify(status)])
	tuner.queue_free()
	for path in TEMP_PATHS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if passed else 1)
