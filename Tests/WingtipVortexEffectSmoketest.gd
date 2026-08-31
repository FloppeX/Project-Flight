extends Node3D

const AIRCRAFT_SCENE: PackedScene = preload("res://Aircraft/Aircraft_14.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft := AIRCRAFT_SCENE.instantiate() as RigidBody3D
	_expect(aircraft != null, "Aircraft 14 did not instantiate")
	if aircraft == null:
		_finish()
		return
	aircraft.freeze = true
	add_child(aircraft)
	await get_tree().process_frame

	var effect := aircraft.get_node_or_null("WingtipVortexEffect") as WingtipVortexEffect
	var left_tip := aircraft.get_node_or_null("WingtipLeft") as Node3D
	var right_tip := aircraft.get_node_or_null("WingtipRight") as Node3D
	_expect(effect != null, "Aircraft 14 has no wingtip-vortex controller")
	_expect(left_tip != null and right_tip != null, "Aircraft 14 wingtip anchors are missing")
	if effect == null or left_tip == null or right_tip == null:
		aircraft.free()
		_finish()
		return
	_expect(bool(EnemyVisualBudget.call("_is_budget_effect_node", effect)), "aircraft visual budget does not recognize the vortex effect")

	_expect(left_tip.position.x > 3.0, "left wingtip anchor is not outboard")
	_expect(right_tip.position.x < -3.0, "right wingtip anchor is not outboard")
	_expect(absf(left_tip.position.x + right_tip.position.x) < 0.05, "wingtip anchors are not laterally mirrored")
	_expect(absf(left_tip.position.y - right_tip.position.y) < 0.05, "wingtip anchors have mismatched heights")
	_expect(absf(left_tip.position.z - right_tip.position.z) < 0.05, "wingtip anchors have mismatched fore-aft positions")

	var left_ribbon := effect.get_node_or_null("LeftVortexRibbon") as MeshInstance3D
	var right_ribbon := effect.get_node_or_null("RightVortexRibbon") as MeshInstance3D
	_expect(left_ribbon != null and right_ribbon != null, "wingtip ribbon meshes were not created")
	_expect(left_tip.get_node_or_null("LeftVortexParticles") == null, "left wingtip still creates a particle emitter")
	_expect(right_tip.get_node_or_null("RightVortexParticles") == null, "right wingtip still creates a particle emitter")
	if left_ribbon != null and right_ribbon != null:
		_expect(not left_ribbon.visible and not right_ribbon.visible, "ribbons appear before they have a trail path")

	var cruise_intensity := effect.calculate_maneuver_intensity(1.0, 4.0, 110.0)
	var turn_intensity := effect.calculate_maneuver_intensity(2.6, 9.0, 110.0)
	var hard_turn_intensity := effect.calculate_maneuver_intensity(3.5, 13.0, 120.0)
	_expect(cruise_intensity <= 0.001, "level cruise produces wingtip vapor")
	_expect(turn_intensity > 0.25 and turn_intensity < hard_turn_intensity, "maneuver vapor does not ramp with load")
	_expect(hard_turn_intensity > 0.95, "hard maneuver does not reach full vapor intensity")
	_expect(effect.calculate_maneuver_intensity(4.0, 14.0, 30.0) <= 0.001, "low-speed movement produces wingtip vapor")
	_expect(effect.calculate_maneuver_intensity(4.0, 14.0, 120.0, 0.1) <= 0.001, "folded wings produce wingtip vapor")

	effect.set_process(false)
	effect.call("_record_ribbon_samples", 1.0)
	aircraft.position += Vector3.FORWARD * 2.0
	effect.call("_record_ribbon_samples", 1.0)
	effect.call("_rebuild_ribbons")
	if left_ribbon != null and right_ribbon != null:
		var left_mesh := left_ribbon.mesh as ImmediateMesh
		var right_mesh := right_ribbon.mesh as ImmediateMesh
		_expect(left_ribbon.visible and right_ribbon.visible, "two-point paths do not reveal both ribbons")
		_expect(left_mesh != null and left_mesh.get_surface_count() == 1, "left ribbon did not build a triangle strip")
		_expect(right_mesh != null and right_mesh.get_surface_count() == 1, "right ribbon did not build a triangle strip")
	effect.set_visual_budget_enabled(false)
	_expect(not effect.is_processing(), "visual budget leaves the vortex controller processing")
	if left_ribbon != null and right_ribbon != null:
		_expect(not left_ribbon.visible and not right_ribbon.visible, "visual budget does not hide vortex ribbons")
		_expect((left_ribbon.mesh as ImmediateMesh).get_surface_count() == 0, "visual budget does not clear the left ribbon")
		_expect((right_ribbon.mesh as ImmediateMesh).get_surface_count() == 0, "visual budget does not clear the right ribbon")

	aircraft.free()
	await get_tree().process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("WINGTIP_VORTEX_EFFECT_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[WingtipVortexEffectSmoketest] %s" % failure)
	get_tree().quit(1)
