extends Node3D



# Any node can receive the "update_interface" signals from the Airplane modules
# This can be used to show realtime representations using the same data
# as the UI controls


@onready var blades = $Blades

@export var AccelSpeed: float = 0.5
@export var MaxRotationSpeed: float = 100.0
@export var disable_fast_rotor_shadows: bool = true
@export var shadow_disable_speed: float = 0.45
@export var shadow_restore_speed: float = 0.30

var mat
var rotation_speed = 0.0
var target_rotation_speed = 0.0
var is_changing_speed = false
var _rotor_shadow_casting: Dictionary = {}
var _fast_rotor_shadows_disabled: bool = false

func _ready():
	# Material must be made unique in order to have independent mesh copies
	mat = $Disc.get_surface_override_material(0).duplicate()
	$Disc.set_surface_override_material(0, mat)
	_cache_rotor_shadow_casting()

func _on_Engine_update_interface(values):
	target_rotation_speed = 0.0 if not values["engine_active"] else 0.2 + values["engine_power"]*0.8
	is_changing_speed = true

func _physics_process(delta):
	if is_changing_speed:
		var frame_move_delta = AccelSpeed * delta
		# Close enough to complete it?
		if abs(target_rotation_speed - rotation_speed) <= frame_move_delta:
			# Just complete it
			rotation_speed = target_rotation_speed
			is_changing_speed = false
		else:
			# Still some way to go
			rotation_speed += (frame_move_delta) if target_rotation_speed > rotation_speed else (-frame_move_delta)
		
		mat.albedo_color.a = clamp(rotation_speed, 0.0, 0.5)
	
	if rotation_speed > 0:
		blades.rotation.y -= MaxRotationSpeed * rotation_speed * delta
	_update_fast_rotor_shadow_casting()

func _cache_rotor_shadow_casting() -> void:
	_cache_shadow_casting_for_node(blades)
	_cache_shadow_casting_for_node($Disc)

func _cache_shadow_casting_for_node(node: Node) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		var id: int = geometry.get_instance_id()
		if not _rotor_shadow_casting.has(id):
			_rotor_shadow_casting[id] = int(geometry.cast_shadow)
	for child in node.get_children():
		_cache_shadow_casting_for_node(child)

func _update_fast_rotor_shadow_casting() -> void:
	if not disable_fast_rotor_shadows:
		if _fast_rotor_shadows_disabled:
			_set_fast_rotor_shadows_disabled(false)
		return
	if _fast_rotor_shadows_disabled:
		if rotation_speed <= maxf(shadow_restore_speed, 0.0):
			_set_fast_rotor_shadows_disabled(false)
	elif rotation_speed >= maxf(shadow_disable_speed, 0.0):
		_set_fast_rotor_shadows_disabled(true)

func _set_fast_rotor_shadows_disabled(disabled: bool) -> void:
	_fast_rotor_shadows_disabled = disabled
	_set_rotor_shadow_disabled_for_node(blades, disabled)
	_set_rotor_shadow_disabled_for_node($Disc, disabled)

func _set_rotor_shadow_disabled_for_node(node: Node, disabled: bool) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		var id: int = geometry.get_instance_id()
		if disabled:
			if not _rotor_shadow_casting.has(id):
				_rotor_shadow_casting[id] = int(geometry.cast_shadow)
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			var original: int = int(_rotor_shadow_casting.get(id, GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
			geometry.cast_shadow = original
	for child in node.get_children():
		_set_rotor_shadow_disabled_for_node(child, disabled)
