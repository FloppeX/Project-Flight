extends CPUParticles3D
## Steam vents along the moving shuttle only during the powered launch stroke.

var _controller: Node3D
var _wind_field: Node

func _ready() -> void:
	_controller = get_parent() as Node3D
	name = "LaunchSteam"
	add_to_group("origin_shifter")
	process_physics_priority = 10
	emitting = false
	local_coords = false
	amount = 90
	lifetime = 1.8
	randomness = 0.2
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(0.18, 0.03, 0.35)
	spread = 32.0
	direction = Vector3.UP
	initial_velocity_min = 0.8
	initial_velocity_max = 1.8
	gravity = Vector3(0, 0.2, 0)
	scale_amount_min = 0.7
	scale_amount_max = 1.3
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.35))
	growth.add_point(Vector2(1.0, 1.0))
	scale_amount_curve = growth
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.5, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.09), Color(1, 1, 1, 0)])
	color_ramp = fade
	# Match DustEffect's translucent low-poly puffs, with a neutral white tint.
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	var puff := SphereMesh.new()
	puff.radial_segments = 4
	puff.rings = 2
	puff.radius = 1.0
	puff.height = 2.0
	puff.material = material
	mesh = puff
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _physics_process(_delta: float) -> void:
	var shuttle: Node3D = _controller.get("shuttle")
	var aircraft: Variant = _controller.get("_aircraft")
	var active := bool(_controller.get("launch_steam_enabled")) \
		and bool(_controller.get("_launching")) \
		and bool(_controller.get("_latched")) \
		and is_instance_valid(aircraft) and is_instance_valid(shuttle)
	emitting = active
	if not active:
		return
	global_position = shuttle.global_position + _controller.global_basis.y.normalized() * 0.15
	global_basis = Basis.IDENTITY
	if not is_instance_valid(_wind_field):
		_wind_field = get_tree().get_first_node_in_group("atmospheric_wind")
	var wind := Vector3.ZERO
	if is_instance_valid(_wind_field):
		wind = _wind_field.call("get_velocity_at", global_position)
	# Steam inherits carrier motion, not the shuttle's launch velocity. Existing
	# particles remain in world space when the shuttle returns to its start.
	var carrier := _controller.get_parent() as CharacterBody3D
	var carrier_velocity := carrier.velocity if carrier != null else Vector3.ZERO
	var jet := carrier_velocity + Vector3.UP * 1.3
	direction = jet.normalized()
	initial_velocity_min = maxf(jet.length() - 0.5, 0.1)
	initial_velocity_max = jet.length() + 0.5
	gravity = wind * 0.35 + Vector3.UP * 0.2

func apply_origin_shift(_offset: Vector3) -> void:
	# CPU particle positions cannot be translated individually. Clear the brief
	# trail at rebasing instead of leaving a streak across the origin jump.
	var was_emitting := emitting
	restart()
	emitting = was_emitting
