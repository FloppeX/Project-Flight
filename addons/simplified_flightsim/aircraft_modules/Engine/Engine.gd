# The Engine module demonstrates how to deal with timed/animated features
# using Tweens and engine timers

extends AircraftModuleSpatial
class_name AircraftModule_Engine

signal update_interface(values)

@export var PowerFactor: float = 20.0
@export var EnginePosition: Vector3 = Vector3.ZERO # Deprecated, use node's own position instead

@export var propeller_node: NodePath = "../Model/propeller_spin"  # Adjust path
@onready var propeller = get_node_or_null(propeller_node)

@export var EngineSoundLoop: AudioStream
@export var EngineSoundStart: AudioStream
@export var EngineSoundStop: AudioStream
@export var GovernPropellerVisualSpeed: bool = false

@export var FuelRate: float = 1.0 # Fuel units per second, at max power
@export var ThrottleSpoolUpRate: float = 0.55 # Power units per second when increasing throttle
@export var ThrottleSpoolDownRate: float = 0.9 # Power units per second when reducing throttle
@export var EngineSoundResponseRate: float = 7.5 # How quickly loop pitch follows live engine power
@export var EngineLoopTargetVolumeDb: float = 4.0 # Propeller loop loudness at steady running power
@export_group("Propeller Blur")
@export var enable_propeller_blur: bool = true
@export var propeller_spin_axis_local: Vector3 = Vector3.BACK
@export var blur_start_power: float = 0.35
@export var blur_full_power: float = 0.85
@export var blur_response_hz: float = 10.0
@export var blade_min_alpha: float = 0.01
@export var disc_max_alpha: float = 1.0
@export var disc_name_keywords: PackedStringArray = PackedStringArray(["propeller disc", "disc"])
@export var blade_name_keywords: PackedStringArray = PackedStringArray(["blade", "blades", "prop_blade"])
@export var hub_name_keywords: PackedStringArray = PackedStringArray(["hub", "spinner", "cone"])

# You don't really *need* to use this property, as any node can receive the
# signals. This is just a helper to automatically connect all possible signals
# assigning the node just once 
@export var UINode: NodePath
@onready var ui_node = get_node_or_null(UINode)
@export var StartupInterlockNode: NodePath
@onready var startup_interlock_node = get_node_or_null(StartupInterlockNode)

var sfx_engine_loop = null
var sfx_engine_start = null
var sfx_engine_stop = null
var sfx_tween
var is_engine_working = false
var current_power = 0.0
var target_power = 0.0
var throttle_input = 0.0 # The user/AI's desired throttle setting
var _current_blur_t: float = 0.0
var _prop_blade_mesh_nodes: Array[MeshInstance3D] = []
var _prop_disc_mesh_nodes: Array[MeshInstance3D] = []
var _prop_hub_mesh_nodes: Array[MeshInstance3D] = []

var is_engine_changing_state = false

func _ready():
	
	if EngineSoundLoop:
		if EngineSoundLoop is AudioStreamWAV:
			EngineSoundLoop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sfx_engine_loop = AudioStreamPlayer3D.new()
		add_child(sfx_engine_loop)
		sfx_engine_loop.stream = EngineSoundLoop
		sfx_engine_loop.unit_size = 50.0     # Larger unit size for more consistent volume
		sfx_engine_loop.max_distance = 2000.0  # Much larger range - 2km
		sfx_engine_loop.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		sfx_engine_loop.add_to_group("3d_audio")  # Add to group for audio management
	
	if EngineSoundStart:
		sfx_engine_start = AudioStreamPlayer3D.new()
		add_child(sfx_engine_start)
		sfx_engine_start.stream = EngineSoundStart
		sfx_engine_start.unit_size = 50.0     
		sfx_engine_start.max_distance = 2000.0  # Much larger range - 2km
		sfx_engine_start.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		sfx_engine_start.add_to_group("3d_audio")  # Add to group for audio management
			
	if EngineSoundStop:
		sfx_engine_stop = AudioStreamPlayer3D.new()
		add_child(sfx_engine_stop)
		sfx_engine_stop.stream = EngineSoundStop
		sfx_engine_stop.unit_size = 50.0     
		sfx_engine_stop.max_distance = 2000.0  # Much larger range - 2km
		sfx_engine_stop.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		sfx_engine_stop.add_to_group("3d_audio")  # Add to group for audio management   
	
	if ui_node:
		connect("update_interface", Callable(ui_node, "update_interface"))
		
	_setup_propeller_blur()
	
	ProcessPhysics = true
	ModuleType = "engine"
	UsesEnergy = true
	EnergyType = "fuel"

func setup(aircraft_node):
	aircraft = aircraft_node
	request_update_interface()


func process_physic_frame(delta):
	if aircraft and is_engine_working:
		_update_power_response(delta)

		var fuel_budget = current_power * FuelRate * delta
		if not aircraft.request_energy(EnergyType, fuel_budget):
			engine_stop()
			return
		
		var force_vector = -global_transform.basis.z * PowerFactor * current_power
		
		# Engine position must be in local position but global rotation
		var engine_rotated_position = global_transform.origin - aircraft.global_transform.origin
		aircraft.apply_force(force_vector, engine_rotated_position)
		
	# Spin propeller directly
		if propeller is Node3D and (current_power > 0.0 or (GovernPropellerVisualSpeed and is_engine_working)):
			var visual_power: float = 1.0 if GovernPropellerVisualSpeed else current_power
			var prop_speed = visual_power * 50.0 + 5.0  # RPM based on power
			var spin_axis: Vector3 = propeller_spin_axis_local
			if spin_axis.length_squared() <= 0.0001:
				spin_axis = Vector3.BACK
			var propeller_node_3d := propeller as Node3D
			propeller_node_3d.rotate_object_local(spin_axis.normalized(), prop_speed * delta)

		_update_engine_sound(delta)

	_update_propeller_blur_visuals(delta)

# -----------------------------------------------------------------------------

func request_update_interface():
	var message = {
		"engine_active": is_engine_working,
		"engine_power": current_power
	}
	emit_signal("update_interface", message)

func power_to_pitch(value: float) -> float:
	return 0.2 + value*0.8

func engine_start():
	if is_engine_changing_state:
		return
	
	is_engine_changing_state = true

	if startup_interlock_node != null and startup_interlock_node.has_method("prepare_for_engine_start"):
		await startup_interlock_node.prepare_for_engine_start()
	
	if not is_engine_working:
		if sfx_engine_loop:
			sfx_engine_loop.volume_db = -40
			sfx_engine_loop.pitch_scale = 0.2
		
	
	if sfx_engine_loop:
		if sfx_tween:
			sfx_tween.kill()
		sfx_tween = create_tween()
		sfx_tween.tween_property(sfx_engine_loop, "volume_db", EngineLoopTargetVolumeDb, 1.0)
		sfx_tween.tween_property(sfx_engine_loop, "pitch_scale", power_to_pitch(current_power), 1.0)
		sfx_engine_loop.play()
	
	if sfx_engine_start:
		sfx_engine_start.play()
	
	await get_tree().create_timer(1.0).timeout
	
	is_engine_working = true
	request_update_interface()
	
	is_engine_changing_state = false

func engine_stop():
	if is_engine_changing_state:
		return
	
	if not is_engine_working:
		return
	
	is_engine_changing_state = true

	is_engine_working = false
	current_power = 0.0
	target_power = 0.0
	
	request_update_interface()
	
	if sfx_engine_loop:
		if sfx_tween:
			sfx_tween.kill()
		sfx_tween = create_tween()
		sfx_tween.tween_property(sfx_engine_loop, "pitch_scale", power_to_pitch(0.0), 1.0)
		
		await sfx_tween.finished
		
		sfx_tween = create_tween()
		sfx_tween.tween_property(sfx_engine_loop, "volume_db", EngineLoopTargetVolumeDb, 1.0)
	
	await get_tree().create_timer(1.0).timeout
	if sfx_engine_loop:
		sfx_engine_loop.stop()
	request_update_interface()
	
	is_engine_changing_state = false

func engine_set_power(value: float):
	var requested_power: float = clamp(value, 0.0, 1.0)
	target_power = requested_power
	throttle_input = requested_power
	
	# If engine is not working and power is requested, start the engine first
	if not is_engine_working and requested_power > 0.01:
		if not is_engine_changing_state:
			engine_start()
		return
	
	# If engine is working and power is 0, stop the engine
	if is_engine_working and requested_power <= 0.01:
		engine_stop()
		return
	
	# Only set power if engine is working
	if not is_engine_working:
		return

func set_power_after_start(value: float):
	"""Legacy helper kept for compatibility with older call sites."""
	engine_set_power(value)



func engine_increase_power(step: float):
	var new_value = clamp(current_power + step, 0.0, 1.0)
	if new_value != current_power:
		engine_set_power(new_value)

func is_running() -> bool:
	return is_engine_working

func get_throttle_ratio() -> float:
	# Returns the current throttle as a value from 0.0 to 1.0
	return current_power

func set_throttle_input(new_throttle: float):
	# Allows external systems like the catapult to command throttle directly
	# while still using the engine's internal spool response.
	engine_set_power(new_throttle)

func process_input(input_actions):
	if input_actions.engine_power_up > 0.0:
		throttle_input = clamp(throttle_input + input_actions.engine_power_up * 0.01, 0.0, 1.0)
	if input_actions.engine_power_down > 0.0:
		throttle_input = clamp(throttle_input - input_actions.engine_power_down * 0.01, 0.0, 1.0)
		
	engine_set_power(throttle_input)

func _update_power_response(delta: float) -> void:
	var previous_power: float = current_power
	var spool_rate: float = ThrottleSpoolUpRate if target_power >= current_power else ThrottleSpoolDownRate
	current_power = move_toward(current_power, target_power, maxf(spool_rate, 0.01) * delta)
	if not is_equal_approx(current_power, previous_power):
		request_update_interface()

func _update_engine_sound(delta: float) -> void:
	if sfx_engine_loop == null:
		return
	var response_t: float = clampf(EngineSoundResponseRate * delta, 0.0, 1.0)
	sfx_engine_loop.pitch_scale = lerpf(sfx_engine_loop.pitch_scale, power_to_pitch(current_power), response_t)

func _setup_propeller_blur() -> void:
	if not enable_propeller_blur:
		return
	if propeller == null or not is_instance_valid(propeller):
		return

	_prop_blade_mesh_nodes.clear()
	_prop_disc_mesh_nodes.clear()
	_prop_hub_mesh_nodes.clear()
	var mesh_nodes: Array[MeshInstance3D] = []
	_collect_propeller_mesh_nodes(propeller, mesh_nodes)
	_classify_propeller_mesh_nodes(mesh_nodes)
	_update_propeller_blur_visuals(1.0)

func _classify_propeller_mesh_nodes(mesh_nodes: Array[MeshInstance3D]) -> void:
	var non_disc_meshes: Array[MeshInstance3D] = []
	for mesh_instance in mesh_nodes:
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		if mesh_instance.mesh == null:
			continue
		if _is_disc_mesh_name(mesh_instance.name):
			_prop_disc_mesh_nodes.append(mesh_instance)
		else:
			non_disc_meshes.append(mesh_instance)
			if _is_hub_mesh_name(mesh_instance.name):
				_prop_hub_mesh_nodes.append(mesh_instance)

	for mesh_instance in non_disc_meshes:
		if _is_hub_mesh_name(mesh_instance.name):
			continue
		if _is_blade_mesh_name(mesh_instance.name):
			_prop_blade_mesh_nodes.append(mesh_instance)

	# Fallback path for older assets that may not name blades.
	if _prop_blade_mesh_nodes.is_empty():
		for mesh_instance in non_disc_meshes:
			if _is_hub_mesh_name(mesh_instance.name):
				continue
			_prop_blade_mesh_nodes.append(mesh_instance)

	# Final fallback if we only have one mesh and no naming clues.
	if _prop_blade_mesh_nodes.is_empty():
		_prop_blade_mesh_nodes = non_disc_meshes

func _is_disc_mesh_name(mesh_name: String) -> bool:
	var lowered_name: String = mesh_name.to_lower()
	for token_variant in disc_name_keywords:
		var token: String = str(token_variant).to_lower()
		if token.is_empty():
			continue
		if lowered_name.find(token) >= 0:
			return true
	return false

func _is_blade_mesh_name(mesh_name: String) -> bool:
	var lowered_name: String = mesh_name.to_lower()
	for token_variant in blade_name_keywords:
		var token: String = str(token_variant).to_lower()
		if token.is_empty():
			continue
		if lowered_name.find(token) >= 0:
			return true
	return false

func _is_hub_mesh_name(mesh_name: String) -> bool:
	var lowered_name: String = mesh_name.to_lower()
	for token_variant in hub_name_keywords:
		var token: String = str(token_variant).to_lower()
		if token.is_empty():
			continue
		if lowered_name.find(token) >= 0:
			return true
	return false

func _collect_propeller_mesh_nodes(node: Node, out_nodes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out_nodes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_propeller_mesh_nodes(child, out_nodes)

func _update_propeller_blur_visuals(delta: float) -> void:
	if not enable_propeller_blur:
		return

	var denom: float = maxf(blur_full_power - blur_start_power, 0.001)
	var target_t: float = clampf((current_power - blur_start_power) / denom, 0.0, 1.0)
	var response_t: float = clampf(blur_response_hz * delta, 0.0, 1.0)
	_current_blur_t = lerpf(_current_blur_t, target_t, response_t)
	var blade_alpha: float = lerpf(1.0, blade_min_alpha, _current_blur_t)
	var disc_alpha: float = clampf(disc_max_alpha * _current_blur_t, 0.0, 1.0)
	for blade_mesh in _prop_blade_mesh_nodes:
		_apply_mesh_alpha(blade_mesh, blade_alpha)
	for disc_mesh in _prop_disc_mesh_nodes:
		_apply_mesh_alpha(disc_mesh, disc_alpha)
	for hub_mesh in _prop_hub_mesh_nodes:
		_apply_mesh_alpha(hub_mesh, 1.0)

func _apply_mesh_alpha(mesh_instance: MeshInstance3D, alpha: float) -> void:
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		return
	var clamped_alpha: float = clampf(alpha, 0.0, 1.0)
	mesh_instance.visible = clamped_alpha > 0.001
	mesh_instance.transparency = 1.0 - clamped_alpha
