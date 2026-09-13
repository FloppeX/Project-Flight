extends Node3D
## Small reusable animation interface; movement remains owned by the actor.
@onready var animation_player: AnimationPlayer = $AnimationPlayer
var _walking := false
var _walk_speed := 1.0
var _mug_insignia: MeshInstance3D
var _mug_insignia_material: ShaderMaterial

func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)
	_mug_insignia = find_child("CoffeeMug_Insignia", true, false) as MeshInstance3D
	Livery.player_insignia_changed.connect(_update_mug_insignia)
	_update_mug_insignia(Livery.get_player_insignia_texture())

func _update_mug_insignia(texture: Texture2D) -> void:
	if _mug_insignia == null:
		return
	if texture == null:
		_mug_insignia.material_override = null
		return
	if _mug_insignia_material == null:
		_mug_insignia_material = ShaderMaterial.new()
		_mug_insignia_material.shader = preload("res://Models/Characters/CoffeeMugInsignia.gdshader")
	var aspect := float(texture.get_width()) / maxf(texture.get_height(), 1.0)
	_mug_insignia_material.set_shader_parameter("insignia_texture", texture)
	_mug_insignia_material.set_shader_parameter("uv_scale", Vector2(maxf(1.0, 1.0/aspect), maxf(1.0, aspect)))
	_mug_insignia.material_override = _mug_insignia_material

func play_sip() -> void:
	if _walking:
		return
	animation_player.speed_scale = 1.0
	animation_player.play(&"Coffee_Sip", 0.18)

## 2.4 m/s matches the regular officer's authored walk reference speed.
func set_walking(walking: bool, speed_mps: float = 2.4) -> void:
	_walk_speed = clampf(speed_mps / 2.4, 0.05, 3.0)
	if walking == _walking:
		if walking:
			animation_player.speed_scale = _walk_speed
		return
	_walking = walking
	_play_locomotion()

func _play_locomotion() -> void:
	animation_player.speed_scale = _walk_speed if _walking else 1.0
	animation_player.play(&"Coffee_Walk" if _walking else &"Coffee_Hold", 0.18)

func _on_animation_finished(animation: StringName) -> void:
	if animation == &"Coffee_Sip":
		_play_locomotion()
