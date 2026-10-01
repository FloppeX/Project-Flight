extends Node

class Deck:
	extends FlightDeckManager
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _disable(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_disable(child)

func _run() -> void:
	var deck := Deck.new()
	add_child(deck)
	for model in [2, 4]:
		var aircraft := load("res://Aircraft/Aircraft_%d.tscn" % model).instantiate() as RigidBody3D
		aircraft.freeze = true
		add_child(aircraft)
		await get_tree().process_frame
		_disable(aircraft)
		deck._apply_ai_loadout_profile(aircraft, "gun_only")
		var state := deck._capture_aircraft_loadout_state(aircraft)
		for entry in state.hardpoints:
			entry.ammo_count = 0
		# Resume an empty aircraft in flight: never grant ammunition on load.
		await deck._restore_aircraft_runtime_state_deferred(aircraft, {"loadout_state": state})
		var controller := aircraft.get_node("ControlWeapons")
		for hp in controller.hardpoints:
			if is_instance_valid(hp.weapon_instance) and hp.weapon_instance.ammo_count != 0:
				failures.append("Airborne checkpoint refilled aircraft %d" % model)
		# The same stored loadout receives supplies for a new hangar sortie.
		await deck._restore_aircraft_runtime_state_deferred(aircraft, {
			"loadout_state": state, "requested_ai_loadout_profile": "gun_only"})
		var armed := false
		for hp in controller.hardpoints:
			if is_instance_valid(hp.weapon_instance):
				armed = armed or hp.weapon_instance.ammo_count > 0
		if not armed:
			failures.append("Patrol sortie launched empty: aircraft %d" % model)
		aircraft.queue_free()
		await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	print("SORTIE_REARM_%s" % ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)
