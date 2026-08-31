extends Node

const MAIN_SCENE := preload("res://Main_Scene.tscn")
const ELEVATOR_SCRIPT := preload("res://LandCarrier/CarrierElevator.gd")
const TRACER_VISUAL_FACTORY := preload("res://Projectiles/Bullet/TracerVisualFactory.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := MAIN_SCENE.instantiate()
	var world_environment := main_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var environment := world_environment.environment if world_environment != null else null
	_expect(environment != null, "main scene WorldEnvironment is missing")
	if environment != null:
		_expect(environment.glow_enabled, "main scene HDR glow is disabled")
		_expect(float(environment.get("glow_levels/1")) >= 0.35, "tight glow level is too weak for narrow tracers")
		_expect(environment.glow_normalized, "glow levels are not normalized")
		_expect(environment.glow_hdr_threshold >= 1.25, "glow threshold is low enough to bloom ordinary surfaces")
		_expect(environment.glow_hdr_threshold <= 2.0, "glow threshold is too high for carrier light lenses")
		_expect(environment.glow_intensity <= 0.65, "global glow intensity is not restrained")
		_expect(environment.glow_bloom <= 0.15, "global full-screen bloom is not restrained")

	var tracer_material := TRACER_VISUAL_FACTORY.create_glow_material(Color.YELLOW, 5.0)
	_expect(tracer_material.emission_enabled, "tracer material is not emissive")
	if environment != null:
		_expect(tracer_material.emission_energy_multiplier > environment.glow_hdr_threshold, "tracer emission does not clear the glow threshold")

	var elevator := ELEVATOR_SCRIPT.new() as CarrierElevator
	elevator.set_meta("technical_index_preview_component", true)
	add_child(elevator)
	await get_tree().process_frame
	var shaft_lighting_root := elevator.get_shaft_lighting_root()
	_expect(shaft_lighting_root != null, "carrier elevator shaft lighting is missing")
	var lenses := shaft_lighting_root.find_children("ShaftLightLens*", "MeshInstance3D", true, false) if shaft_lighting_root != null else []
	_expect(lenses.size() == 4, "carrier elevator does not expose four glowing lenses")
	for lens_node in lenses:
		var lens := lens_node as MeshInstance3D
		var lens_material := lens.material_override as StandardMaterial3D if lens != null else null
		_expect(lens_material != null and lens_material.emission_enabled, "carrier shaft lens is not emissive")
		if lens_material != null and environment != null:
			_expect(lens_material.emission_energy_multiplier > environment.glow_hdr_threshold, "carrier shaft lens does not clear the glow threshold")

	main_scene.free()
	elevator.free()
	if _failures.is_empty():
		print("[EmissiveGlowSmoketest] PASS hdr_threshold=1.5 restrained_bloom carrier_lenses=4 tracer_energy=5.0")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[EmissiveGlowSmoketest] FAIL %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
