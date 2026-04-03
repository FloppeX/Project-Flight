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

@export var FuelRate: float = 1.0 # Fuel units per second, at max power
@export var ThrottleSpoolUpRate: float = 0.55 # Power units per second when increasing throttle
@export var ThrottleSpoolDownRate: float = 0.9 # Power units per second when reducing throttle
@export var EngineSoundResponseRate: float = 7.5 # How quickly loop pitch follows live engine power

# You don't really *need* to use this property, as any node can receive the
# signals. This is just a helper to automatically connect all possible signals
# assigning the node just once 
@export var UINode: NodePath
@onready var ui_node = get_node_or_null(UINode)

var sfx_engine_loop = null
var sfx_engine_start = null
var sfx_engine_stop = null
var sfx_tween
var is_engine_working = false
var current_power = 0.0
var target_power = 0.0
var throttle_input = 0.0 # The user/AI's desired throttle setting

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
		if propeller and current_power > 0.0:
			var prop_speed = current_power * 50.0 + 5.0  # RPM based on power
			propeller.rotate_z(prop_speed * delta)  # Adjust axis as needed

		_update_engine_sound(delta)

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
	
	if not is_engine_working:
		sfx_engine_loop.volume_db = -40
		sfx_engine_loop.pitch_scale = 0.2
		
	
	if sfx_tween:
		sfx_tween.kill()
	sfx_tween = create_tween()
	sfx_tween.tween_property(sfx_engine_loop, "volume_db", 1.0, 1.0)
	sfx_tween.tween_property(sfx_engine_loop, "pitch_scale", power_to_pitch(current_power), 1.0)
	sfx_engine_loop.play()
	
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
	
	if sfx_tween:
		sfx_tween.kill()
	sfx_tween = create_tween()
	sfx_tween.tween_property(sfx_engine_loop, "pitch_scale", power_to_pitch(0.0), 1.0)
	
	await sfx_tween.finished
	
	sfx_tween = create_tween()
	sfx_tween.tween_property(sfx_engine_loop, "volume_db", 1.0, 1.0)
	
	await get_tree().create_timer(1.0).timeout
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
