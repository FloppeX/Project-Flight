extends Node3D

const PopupLogic = preload("res://AI/HelicopterPopup.gd")
class ProbePilot extends HelicopterPilot:
	var burst := false
	var column_clear := true
	var releases := 0
	func _get_ground_height_at_position(p: Vector3) -> float:
		return 110.0 if absf(p.x) <= 800 and p.z >= -560 and p.z <= -480 else 0.0
	func _popup_column_clear(_low: Vector3, _high: Vector3) -> bool: return column_clear
	func _atk_rocket_burst_in_progress() -> bool: return burst
	func _fly_popup_hold(_hold: Vector3, _target: Vector3, _firing: bool, _delta: float) -> void: pass
	func _atk_aim_and_fire(_range: float) -> void: releases += 1
	func _atk_begin_egress(reason: String) -> void:
		_atk_tuning_exit_reason = reason
		_atk_state = AtkState.EGRESS
var failures := 0
func _ready() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var ridge := func(p: Vector3) -> float:
		return 110.0 if absf(p.x) <= 800 and p.z >= -560 and p.z <= -480 else 0.0
	var low := Vector3(0,80,-680)
	var target := Vector3(0,4,0)
	var plan: Dictionary = PopupLogic.choose(low, target, 807, 80, 160, ridge)
	check(not plan.is_empty(), "ridge offers a pop-up")
	if not plan.is_empty():
		check(PopupLogic.hidden(plan.hide, target, ridge), "rotor-height concealed at low station")
		check(PopupLogic.firing_line_clear(plan.fire, target, ridge), "raised firing line clears ridge")
		check(PopupLogic.concealed_route(plan.hide, plan.relocate, target, ridge), "relocation stays concealed")
		check(plan.hide.distance_to(plan.relocate) >= 120, "relocation is a different position")
		var controller = PopupLogic.new()
		controller.begin(plan.duplicate())
		controller.shift(Vector3(100, 0, 200))
		check(controller.plan.hide == plan.hide - Vector3(100,0,200), "origin shift moves pop-up anchors")
	check(PopupLogic.choose(low,target,807,80,160,func(_p): return 0.0).is_empty(), "no fake cover on flat terrain")
	check(PopupLogic.choose(low,target,807,80,160,func(_p): return NAN).is_empty(), "unknown terrain fails closed")
	check(PopupLogic.choose(low,target,807,80,16,ridge).is_empty(), "insufficient rise room rejected")
	check(not PopupLogic.firing_line_clear(low,target,ridge), "cannot shoot through cover")
	_check_phases(plan)
	var rocket := load("res://Weapons/RocketPod/rocket_pod.tscn") as PackedScene
	var gun := load("res://Weapons/Guns/Hardpoint/15mm_machine_gun_hardpoint.tscn") as PackedScene
	for model in [9,10,11]:
		var craft := (load("res://Aircraft/Aircraft_%d.tscn" % model) as PackedScene).instantiate()
		add_child(craft)
		var points: Array[Hardpoint] = []
		collect(craft, points)
		check(points.size() == (1 if model == 11 else 2), "expected hardpoint count")
		for hp in points:
			check(not hp.gun_only, "helicopter station is not gun-only")
			check(hp.mount_weapon_from_scene(rocket), "rocket mount accepted")
			check(hp.weapon_instance is RocketPod, "real rocket pod installed")
			check(hp.mount_weapon_from_scene(gun), "gun option retained")
		craft.queue_free()
		await get_tree().process_frame
	print("HELI_POPUP_SMOKE failures=%d" % failures)
	get_tree().quit(1 if failures else 0)

func collect(node: Node, points: Array[Hardpoint]) -> void:
	if node is Hardpoint: points.append(node)
	for child in node.get_children(): collect(child, points)

func _check_phases(plan: Dictionary) -> void:
	if plan.is_empty(): return
	var body := RigidBody3D.new()
	body.freeze = true
	add_child(body)
	var foe := Node3D.new()
	add_child(foe)
	foe.position = plan.target
	var pilot := ProbePilot.new()
	pilot.combat_report_enabled = false
	pilot.combat_tuning_enabled = false
	pilot.crash_log_enabled = false
	body.add_child(pilot)
	pilot.set_physics_process(false)
	pilot.aircraft = body
	pilot._atk_target = foe
	pilot._atk_state = HelicopterPilot.AtkState.POPUP
	pilot._popup.begin(plan.duplicate())
	body.position = plan.hide
	pilot._update_popup_attack(0.02)
	check(pilot._popup.phase == PopupLogic.Phase.RISE, "settled concealed arrival starts rise")
	body.position = plan.fire
	pilot._update_popup_attack(0.02)
	check(pilot._popup.phase == PopupLogic.Phase.FIRE, "clear settled high station permits fire phase")
	pilot._atk_rocket_volleys_fired = 1
	pilot._popup.elapsed = 12
	pilot.burst = true
	pilot._update_popup_attack(0.02)
	check(pilot._popup.phase == PopupLogic.Phase.FIRE, "normal ongoing salvo is not cut short by fire window")
	pilot.burst = false
	pilot._update_popup_attack(0.02)
	check(pilot._popup.phase == PopupLogic.Phase.DESCEND and pilot._popup.reason == "salvo_complete", "completed salvo starts concealment")
	body.position = plan.hide
	pilot._update_popup_attack(0.02)
	check(pilot._popup.phase == PopupLogic.Phase.RELOCATE, "hide before moving to another position")
	body.position = plan.relocate
	pilot._update_popup_attack(0.02)
	check(pilot._atk_state == HelicopterPilot.AtkState.SELECT and pilot._popup.plan.is_empty(), "relocated cycle resets cleanly")
	check(pilot._popup_last_site == plan.hide, "remember used firing site")
	# Losing the target is not a reason to hover exposed indefinitely.
	pilot._popup.begin(plan.duplicate())
	pilot._popup.set_phase(PopupLogic.Phase.RISE)
	pilot._atk_state = HelicopterPilot.AtkState.POPUP
	pilot._atk_target = null
	pilot._popup_validation_s = 0
	body.position = plan.fire
	pilot._update_popup_attack(0.02)
	check(pilot._popup.phase == PopupLogic.Phase.DESCEND, "lost target descends behind cover")
	pilot._atk_target = foe
	pilot._popup.set_phase(PopupLogic.Phase.RISE)
	pilot._popup_validation_s = 0
	pilot.column_clear = false
	pilot._update_popup_attack(0.02)
	check(pilot._atk_state == HelicopterPilot.AtkState.EGRESS, "blocked ascent triggers escape")
	pilot._popup.begin(plan.duplicate())
	pilot._atk_state = HelicopterPilot.AtkState.POPUP
	pilot._popup.elapsed = 50
	pilot._update_popup_attack(0.02)
	check(pilot._atk_state == HelicopterPilot.AtkState.EGRESS, "phase watchdog escapes instead of waiting forever")
	pilot._popup.begin(plan.duplicate())
	pilot._atk_state = HelicopterPilot.AtkState.POPUP
	pilot._commanded_attack_target = foe
	pilot.command_hover(Vector3(0, 80, -900))
	check(pilot._popup.plan.is_empty() and pilot._atk_target == null and pilot._commanded_attack_target == null, "new command cancels pop-up ownership")
	body.queue_free()
	foe.queue_free()
