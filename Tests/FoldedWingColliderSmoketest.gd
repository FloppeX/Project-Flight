extends Node3D

const AIRCRAFT_1_SCENE: PackedScene = preload("res://Aircraft/Aircraft_1.tscn")
const AIRCRAFT_2_SCENE: PackedScene = preload("res://Aircraft/Aircraft_2.tscn")
const AIRCRAFT_5_SCENE: PackedScene = preload("res://Aircraft/Aircraft_5.tscn")

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_aircraft(AIRCRAFT_1_SCENE, NodePath("WingFold"), "Aircraft 1")
	await _check_aircraft(AIRCRAFT_2_SCENE, NodePath("WingFold"), "Aircraft 2")
	await _check_aircraft(AIRCRAFT_5_SCENE, NodePath("WingFold5"), "Aircraft 5")
	_finish()


func _check_aircraft(scene: PackedScene, controller_path: NodePath, label: String) -> void:
	var aircraft := scene.instantiate() as RigidBody3D
	_expect(aircraft != null, "%s did not instantiate" % label)
	if aircraft == null:
		return
	aircraft.freeze = true
	add_child(aircraft)
	await get_tree().process_frame

	var controller := aircraft.get_node_or_null(controller_path)
	var broad_wing_collider := aircraft.get_node_or_null("WingCollider") as CollisionShape3D
	_expect(controller != null, "%s has no wing-fold controller" % label)
	_expect(broad_wing_collider != null, "%s has no broad wing collider" % label)
	if controller == null or broad_wing_collider == null:
		aircraft.free()
		await get_tree().process_frame
		return

	controller.set_process(false)
	controller.call("set_technical_index_preview_fraction", 0.0)
	_expect(not broad_wing_collider.disabled, "%s collider is disabled while unfolded" % label)
	controller.call("set_technical_index_preview_fraction", 0.25)
	_expect(broad_wing_collider.disabled, "%s collider remains active during folding" % label)
	controller.call("set_technical_index_preview_fraction", 1.0)
	_expect(broad_wing_collider.disabled, "%s collider remains active while folded" % label)
	controller.call("set_technical_index_preview_fraction", 0.0)
	_expect(not broad_wing_collider.disabled, "%s collider did not return after unfolding" % label)

	aircraft.free()
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FOLDED_WING_COLLIDER_SMOKETEST_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FoldedWingColliderSmoketest] %s" % failure)
	get_tree().quit(1)
