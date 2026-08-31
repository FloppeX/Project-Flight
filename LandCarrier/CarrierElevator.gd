extends Node3D
class_name CarrierElevator

const PERIMETER_HAZARD_SHADER: Shader = preload("res://Shaders/carrier_elevator_hazard.gdshader")

# Simple elevator system for carrier hangar operations
# Moves platform up/down and manages covers

signal elevator_at_top
signal elevator_at_bottom
signal covers_closed
signal covers_opened

@export var platform_size: Vector3 = Vector3(10, 1, 15)
# Covers are rotated 90 degrees around Y, so cover_size.z becomes the width of
# each half across the opening and cover_size.x follows the carrier fore/aft.
@export var cover_size: Vector3 = Vector3(15, 0.2, 5)
@export var shaft_depth: float = 10.0
@export var start_at_bottom: bool = true
@export var move_speed: float = 1.5
@export var cover_slide_speed: float = 2.25
@export var cover_lift_speed: float = 0.75
## While sliding, the cover's top face remains this far below deck level.
@export_range(0.1, 1.5, 0.05) var cover_recess_depth_m: float = 0.4
## Small extra travel puts an open cover fully beneath the surrounding deck.
@export_range(0.0, 1.0, 0.05) var cover_recess_margin_m: float = 0.15
## The platform must clear this much below deck before the covers move inward.
@export_range(0.5, 5.0, 0.1) var cover_close_platform_clearance_m: float = 2.5
# Aircraft already occupy layers 1 and 10 (513). Put the moving carrier parts
# on layer 10 only so they support aircraft without colliding with their carrier
# parent on layer 1 while the covers slide into their open recesses.
@export_flags_3d_physics var platform_collision_layer: int = 512
@export_flags_3d_physics var platform_collision_mask: int = 512
@export_range(0.0, 1.0, 0.05) var platform_friction: float = 1.0
## Rendered surfaces sit slightly above the authored deck to avoid coplanar
## depth fighting. Physics remains exactly flush at local Y = 0.
@export_range(0.0, 0.1, 0.001) var visual_surface_offset_m: float = 0.025
@export_range(0.1, 1.0, 0.01) var perimeter_marking_width_m: float = 0.30
## Gap between the surface edge and the warning band's outer edge. Zero makes
## the marking begin exactly at the physical perimeter and extend inward.
@export_range(0.0, 0.5, 0.01) var marking_inset_m: float = 0.0
@export_range(0.05, 1.0, 0.01) var warning_stripe_width_m: float = 0.28
@export_range(0.0, 1.0, 0.05) var surface_emission_energy: float = 0.1
@export var platform_color: Color = Color(0.25, 0.32, 0.34, 1.0)
@export var cover_color: Color = Color(0.32, 0.36, 0.38, 1.0)
@export var perimeter_marking_color: Color = Color(0.95, 0.72, 0.08, 1.0)
@export var perimeter_marking_black_color: Color = Color(0.025, 0.03, 0.028, 1.0)
## Stationary wall fixtures make the platform and the shaft's vertical depth
## readable while the lift moves. Their local lights deliberately cast no
## shadows: each carrier has two shafts, so this keeps the added cost bounded.
@export var shaft_lights_enabled: bool = true
@export var shaft_light_color: Color = Color(1.0, 0.82, 0.58, 1.0)
@export_range(0.0, 8.0, 0.1) var shaft_light_energy: float = 4.2
@export_range(2.0, 14.0, 0.25) var shaft_light_range_m: float = 7.0
@export_range(0.0, 12.0, 0.25) var shaft_fixture_emission_energy: float = 4.0
@export_range(0.0, 0.6, 0.01) var shaft_fixture_wall_offset_m: float = 0.07
@export var moving_sound: AudioStream = preload("res://Audio/Carrier/elevator_moving_mono.wav")
@export var moving_sound_bus: String = "Master"
@export var moving_sound_min_volume_db: float = -20.0
@export var moving_sound_max_volume_db: float = -10.0
@export var moving_sound_pitch_min: float = 0.82
@export var moving_sound_pitch_max: float = 1.08
@export var moving_sound_silence_db: float = -80.0
@export var moving_sound_unit_size_m: float = 32.0
@export var moving_sound_max_distance_m: float = 240.0

enum ElevatorState {
	AT_TOP,
	MOVING_DOWN,
	AT_BOTTOM,
	COVERS_CLOSING,
	COVERS_CLOSED,
	COVERS_OPENING,
	MOVING_UP,
	COVERS_RAISING,
	COVERS_LOWERING
}

var current_state: ElevatorState = ElevatorState.AT_TOP
var platform: Node3D
var left_cover: Node3D
var right_cover: Node3D
var _platform_visual_root: Node3D
var _left_cover_visual_root: Node3D
var _right_cover_visual_root: Node3D
var _shaft_lighting_root: Node3D
# Animation targets
var platform_target_y: float = 0.0
var left_cover_target_x: float = 0.0
var right_cover_target_x: float = 0.0
var _platform_local_y: float = -0.5
var _left_cover_local_x: float = 0.0
var _right_cover_local_x: float = 0.0
var _cover_local_y: float = -0.1
var _cover_target_y: float = -0.1
var _moving_audio_player: AudioStreamPlayer3D
var _last_platform_y: float = 0.0
var _technical_index_preview_fraction: float = 0.0
var _platform_restraints: Dictionary = {}

func _ready():
	if bool(get_meta("technical_index_preview_component", false)):
		if not is_instance_valid(platform) or not is_instance_valid(left_cover) \
				or not is_instance_valid(right_cover):
			create_elevator_components(false)
		set_technical_index_preview_fraction(_technical_index_preview_fraction)
		return
	print("Setting up elevator system...")
	create_elevator_components()
	set_initial_state()
	print("Elevator setup complete.")

func create_elevator_components(include_audio: bool = true):
	if is_instance_valid(platform) and is_instance_valid(left_cover) \
			and is_instance_valid(right_cover) \
			and is_instance_valid(_platform_visual_root) \
			and is_instance_valid(_left_cover_visual_root) \
			and is_instance_valid(_right_cover_visual_root) \
			and (not shaft_lights_enabled or is_instance_valid(_shaft_lighting_root)):
		return
	# Create platform
	if not is_instance_valid(platform):
		platform = create_platform()
		add_child(platform)
		# PhysicsServer bodies do not reliably inherit a moving CharacterBody3D
		# parent's transform. Keep them world-space and explicitly anchor them to
		# the elevator's carrier-local animation coordinates every physics frame.
		platform.top_level = true
	if not is_instance_valid(_platform_visual_root):
		_platform_visual_root = _create_surface_visual(
			"PlatformRender",
			"PlatformVisual",
			platform_size,
			platform_color,
			0.65,
			0.38
		)
		add_child(_platform_visual_root)
	
	# Create covers
	if not is_instance_valid(left_cover):
		left_cover = create_cover("LeftCover")
		add_child(left_cover)
		left_cover.top_level = true
	if not is_instance_valid(_left_cover_visual_root):
		_left_cover_visual_root = _create_surface_visual(
			"LeftCoverRender",
			"LeftCoverVisual",
			cover_size,
			cover_color,
			0.55,
			0.42
		)
		add_child(_left_cover_visual_root)
	if not is_instance_valid(right_cover):
		right_cover = create_cover("RightCover")
		add_child(right_cover)
		right_cover.top_level = true
	if not is_instance_valid(_right_cover_visual_root):
		_right_cover_visual_root = _create_surface_visual(
			"RightCoverRender",
			"RightCoverVisual",
			cover_size,
			cover_color,
			0.55,
			0.42
		)
		add_child(_right_cover_visual_root)
	if shaft_lights_enabled and not is_instance_valid(_shaft_lighting_root):
		_shaft_lighting_root = _create_shaft_lighting()
		add_child(_shaft_lighting_root)
	_sync_physical_transforms()
	_sync_visual_transforms()
	if include_audio:
		_setup_moving_audio()


func prepare_technical_index_preview() -> bool:
	create_elevator_components(false)
	if not is_instance_valid(platform) or not is_instance_valid(left_cover) \
			or not is_instance_valid(right_cover):
		return false
	# The index scales and rotates the whole carrier model. Physics-synchronized
	# child transforms would be converted back through that scaled parent and drift
	# away from their authored local positions. Preview animation is purely visual.
	set_physics_process(false)
	for moving_part in [platform, left_cover, right_cover]:
		if moving_part is AnimatableBody3D:
			var preview_body := moving_part as AnimatableBody3D
			preview_body.sync_to_physics = false
			preview_body.collision_layer = 0
			preview_body.collision_mask = 0
			preview_body.top_level = false
	set_technical_index_preview_fraction(0.0 if start_at_bottom else 1.0)
	return true


func set_technical_index_preview_fraction(up_fraction: float) -> void:
	_technical_index_preview_fraction = clampf(up_fraction, 0.0, 1.0)
	if not is_instance_valid(platform) or not is_instance_valid(left_cover) \
			or not is_instance_valid(right_cover):
		return

	var elapsed := _technical_index_preview_fraction * get_technical_index_preview_duration()
	var lower_duration := cover_recess_depth_m / maxf(cover_lift_speed, 0.01)
	var slide_duration := _cover_slide_travel() / maxf(cover_slide_speed, 0.01)
	var platform_duration := _platform_travel() / maxf(move_speed, 0.01)
	var lower_fraction := _smooth_preview_fraction(_phase_fraction(elapsed, 0.0, lower_duration))
	var slide_fraction := _smooth_preview_fraction(_phase_fraction(elapsed, lower_duration, slide_duration))
	var platform_fraction := _smooth_preview_fraction(
		_phase_fraction(elapsed, lower_duration + slide_duration, platform_duration)
	)

	_platform_local_y = lerpf(-shaft_depth, _platform_deck_y(), platform_fraction)
	_cover_local_y = lerpf(_cover_deck_y(), _cover_recess_y(), lower_fraction)
	_left_cover_local_x = lerpf(-_cover_closed_center_x(), -_cover_open_center_x(), slide_fraction)
	_right_cover_local_x = lerpf(_cover_closed_center_x(), _cover_open_center_x(), slide_fraction)
	_sync_physical_transforms()
	_sync_visual_transforms()


func get_technical_index_preview_fraction() -> float:
	return _technical_index_preview_fraction


func get_technical_index_preview_duration() -> float:
	var platform_duration := _platform_travel() / maxf(move_speed, 0.01)
	var cover_slide_duration := _cover_slide_travel() / maxf(cover_slide_speed, 0.01)
	var cover_lift_duration := cover_recess_depth_m / maxf(cover_lift_speed, 0.01)
	return platform_duration + cover_slide_duration + cover_lift_duration


func get_technical_index_preview_kind() -> StringName:
	return &"elevator"


func _smooth_preview_fraction(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)


func _phase_fraction(elapsed: float, phase_start: float, phase_duration: float) -> float:
	return clampf((elapsed - phase_start) / maxf(phase_duration, 0.01), 0.0, 1.0)


func _platform_deck_y() -> float:
	return -platform_size.y * 0.5


func _platform_travel() -> float:
	return maxf(shaft_depth + _platform_deck_y(), 0.0)


func _cover_deck_y() -> float:
	return -cover_size.y * 0.5


func _cover_recess_y() -> float:
	return _cover_deck_y() - cover_recess_depth_m


func _cover_closed_center_x() -> float:
	return platform_size.x * 0.25


func _cover_open_center_x() -> float:
	return platform_size.x * 0.5 + cover_size.z * 0.5 + cover_recess_margin_m


func _cover_slide_travel() -> float:
	return maxf(_cover_open_center_x() - _cover_closed_center_x(), 0.0)

func create_platform() -> Node3D:
	var platform_node := AnimatableBody3D.new()
	platform_node.name = "Platform"
	platform_node.sync_to_physics = true
	platform_node.collision_layer = platform_collision_layer
	platform_node.collision_mask = platform_collision_mask
	platform_node.physics_material_override = _create_platform_physics_material()
	
	var collision := CollisionShape3D.new()
	collision.name = "PlatformCollision"
	var box_shape := BoxShape3D.new()
	box_shape.size = platform_size
	collision.shape = box_shape
	platform_node.add_child(collision)
	
	# Position platform so its top surface is flush with carrier deck
	platform_node.position.y = -platform_size.y / 2.0
	
	return platform_node

func create_cover(name: String) -> Node3D:
	var cover_node := AnimatableBody3D.new()
	cover_node.name = name
	cover_node.sync_to_physics = true
	cover_node.collision_layer = platform_collision_layer
	cover_node.collision_mask = platform_collision_mask
	cover_node.physics_material_override = _create_platform_physics_material()
	
	var collision := CollisionShape3D.new()
	collision.name = "%sCollision" % name
	var box_shape := BoxShape3D.new()
	box_shape.size = cover_size
	collision.shape = box_shape
	cover_node.add_child(collision)
	
	# Rotate covers 90 degrees so their long sides face each other
	cover_node.rotation.y = PI / 2
	
	# Position covers so their top surface is flush with carrier deck
	cover_node.position.y = -cover_size.y / 2.0
	
	return cover_node


func _create_surface_visual(
		root_name: String,
		mesh_name: String,
		size: Vector3,
		color: Color,
		metallic: float,
		roughness: float
) -> Node3D:
	# Keep rendering out of the physics-synchronised body. AnimatableBody3D owns
	# only collision; this ordinary Node3D mirrors it and remains on the normal
	# render path used by the carrier's other generated parts.
	var visual_root := Node3D.new()
	visual_root.name = root_name
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = visual_surface_offset_m
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	# The lift spends most of its travel inside a shadowed shaft. A restrained
	# emission contribution preserves its colour without making it self-lit.
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = surface_emission_energy
	mesh_instance.material_override = material
	visual_root.add_child(mesh_instance)
	_add_perimeter_markings(
		visual_root,
		size.x,
		size.z,
		size.y * 0.5 + visual_surface_offset_m
	)
	return visual_root


func _create_shaft_lighting() -> Node3D:
	var lighting_root := Node3D.new()
	lighting_root.name = "ShaftLighting"

	# Two opposing fixtures at two elevations reveal the full 10 m travel and
	# keep the light pools within the opening. The fixtures are attached to the
	# stationary elevator root rather than the moving platform render root.
	var upper_y := -minf(shaft_depth * 0.28, 2.8)
	var lower_y := -maxf(shaft_depth * 0.72, shaft_depth - 2.8)
	var light_index := 0
	for fixture_y in [upper_y, lower_y]:
		for wall_sign in [-1.0, 1.0]:
			_add_shaft_light_fixture(lighting_root, light_index, wall_sign, fixture_y)
			light_index += 1
	return lighting_root


func _add_shaft_light_fixture(
		parent: Node3D,
		fixture_index: int,
		wall_sign: float,
		fixture_y: float
) -> void:
	var fixture := Node3D.new()
	fixture.name = "ShaftLightFixture%d" % fixture_index
	parent.add_child(fixture)

	var wall_x := wall_sign * (platform_size.x * 0.5 + shaft_fixture_wall_offset_m)
	fixture.position = Vector3(wall_x, fixture_y, 0.0)

	var housing := MeshInstance3D.new()
	housing.name = "ShaftLightHousing%d" % fixture_index
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(0.16, 0.58, 1.45)
	housing.mesh = housing_mesh
	var housing_material := StandardMaterial3D.new()
	housing_material.albedo_color = Color(0.055, 0.065, 0.068, 1.0)
	housing_material.metallic = 0.7
	housing_material.roughness = 0.34
	housing.material_override = housing_material
	fixture.add_child(housing)

	var lens := MeshInstance3D.new()
	lens.name = "ShaftLightLens%d" % fixture_index
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(0.05, 0.34, 1.12)
	lens.mesh = lens_mesh
	lens.position.x = -wall_sign * 0.105
	var lens_material := StandardMaterial3D.new()
	lens_material.albedo_color = shaft_light_color
	lens_material.roughness = 0.24
	lens_material.emission_enabled = true
	lens_material.emission = shaft_light_color
	lens_material.emission_energy_multiplier = shaft_fixture_emission_energy
	lens.material_override = lens_material
	fixture.add_child(lens)

	if shaft_light_energy <= 0.001:
		return
	var light := OmniLight3D.new()
	light.name = "ShaftLight%d" % fixture_index
	light.light_color = shaft_light_color
	light.light_energy = shaft_light_energy
	light.omni_range = shaft_light_range_m
	light.omni_attenuation = 1.45
	light.shadow_enabled = false
	# Move the source just clear of the lens so the wall does not absorb the
	# centre of the pool when shadows are enabled globally for other lights.
	light.position.x = -wall_sign * 0.55
	fixture.add_child(light)


func _get_platform_local_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, _platform_local_y, 0.0))


func _get_left_cover_local_transform() -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, PI / 2.0),
		Vector3(_left_cover_local_x, _cover_local_y, 0.0)
	)


func _get_right_cover_local_transform() -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, PI / 2.0),
		Vector3(_right_cover_local_x, _cover_local_y, 0.0)
	)


func _sync_physical_part(part: Node3D, local_transform: Transform3D) -> void:
	if not is_instance_valid(part):
		return
	if part.top_level and is_inside_tree():
		part.global_transform = global_transform * local_transform
	else:
		# Technical Index bodies are non-physical carrier children so they retain
		# the preview model's scale and orientation.
		part.transform = local_transform


func _sync_physical_transforms() -> void:
	_sync_physical_part(platform, _get_platform_local_transform())
	_sync_physical_part(left_cover, _get_left_cover_local_transform())
	_sync_physical_part(right_cover, _get_right_cover_local_transform())


func _sync_visual_transforms() -> void:
	# Render roots stay ordinary carrier children. Never copy a physics body's
	# compensated local transform here: that is what left the old visuals behind
	# when the carrier moved.
	if is_instance_valid(_platform_visual_root):
		_platform_visual_root.transform = _get_platform_local_transform()
	if is_instance_valid(_left_cover_visual_root):
		_left_cover_visual_root.transform = _get_left_cover_local_transform()
	if is_instance_valid(_right_cover_visual_root):
		_right_cover_visual_root.transform = _get_right_cover_local_transform()


func get_platform_local_y() -> float:
	return _platform_local_y


func get_cover_local_y() -> float:
	return _cover_local_y


func get_platform_visual_root() -> Node3D:
	return _platform_visual_root


func get_left_cover_visual_root() -> Node3D:
	return _left_cover_visual_root


func get_right_cover_visual_root() -> Node3D:
	return _right_cover_visual_root


func get_shaft_lighting_root() -> Node3D:
	return _shaft_lighting_root


func _add_perimeter_markings(parent: Node3D, width: float, depth: float, surface_y: float) -> void:
	var strip_height := 0.012
	var half_width := width * 0.5
	var half_depth := depth * 0.5
	var band_width := minf(perimeter_marking_width_m, minf(half_width, half_depth))
	var inset := minf(marking_inset_m, minf(half_width, half_depth) - band_width)
	# The band sits wholly on the top face: its outer edge follows the physical
	# perimeter and its width extends inward. Front/back strips own the corners;
	# shortening the side strips avoids coplanar overlap there.
	var outer_width := maxf(width - inset * 2.0, band_width)
	var side_depth := maxf(depth - (inset + band_width) * 2.0, band_width)
	var strip_center_x := half_width - inset - band_width * 0.5
	var strip_center_z := half_depth - inset - band_width * 0.5
	var strip_specs := [
		[Vector3(outer_width, strip_height, band_width), Vector3(0.0, surface_y + strip_height * 0.5, -strip_center_z)],
		[Vector3(outer_width, strip_height, band_width), Vector3(0.0, surface_y + strip_height * 0.5, strip_center_z)],
		[Vector3(band_width, strip_height, side_depth), Vector3(-strip_center_x, surface_y + strip_height * 0.5, 0.0)],
		[Vector3(band_width, strip_height, side_depth), Vector3(strip_center_x, surface_y + strip_height * 0.5, 0.0)],
	]
	for i in range(strip_specs.size()):
		var strip_data: Array = strip_specs[i]
		var strip := MeshInstance3D.new()
		strip.name = "PerimeterMarking%d" % i
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = strip_data[0] as Vector3
		strip.mesh = strip_mesh
		strip.position = strip_data[1] as Vector3
		var marking_material := ShaderMaterial.new()
		marking_material.shader = PERIMETER_HAZARD_SHADER
		marking_material.set_shader_parameter("warning_yellow", perimeter_marking_color)
		marking_material.set_shader_parameter("warning_black", perimeter_marking_black_color)
		marking_material.set_shader_parameter("stripe_width_m", warning_stripe_width_m)
		marking_material.set_shader_parameter("marking_offset_xz", Vector2(strip.position.x, strip.position.z))
		strip.material_override = marking_material
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(strip)


func get_platform_body() -> AnimatableBody3D:
	return platform as AnimatableBody3D


func has_physical_platform() -> bool:
	var platform_body := get_platform_body()
	return platform_body != null and platform_body.get_node_or_null("PlatformCollision") is CollisionShape3D


## Tie-down used while an aircraft is being transported. The aircraft remains a
## live RigidBody3D with gravity and collision; the joint represents wheel chocks
## and deck restraints rather than turning the body into a ghost.
func create_platform_restraint(body: RigidBody3D) -> Generic6DOFJoint3D:
	if not is_instance_valid(body):
		return null
	var platform_body := get_platform_body()
	if platform_body == null:
		return null
	var existing_joint := _platform_restraints.get(body.get_instance_id()) as Generic6DOFJoint3D
	if is_instance_valid(existing_joint):
		return existing_joint
	release_platform_restraint(body)
	var joint := Generic6DOFJoint3D.new()
	joint.name = "ElevatorRestraint_%s" % body.name
	joint.exclude_nodes_from_collision = false
	var joint_parent: Node = get_tree().current_scene
	if joint_parent == null:
		joint_parent = get_tree().root
	joint_parent.add_child(joint)
	joint.global_transform = body.global_transform
	joint.node_a = joint.get_path_to(body)
	joint.node_b = joint.get_path_to(platform_body)
	for axis_name in ["x", "y", "z"]:
		joint.set("linear_limit_%s/enabled" % axis_name, true)
		joint.set("linear_limit_%s/lower_distance" % axis_name, 0.0)
		joint.set("linear_limit_%s/upper_distance" % axis_name, 0.0)
		joint.set("angular_limit_%s/enabled" % axis_name, true)
		joint.set("angular_limit_%s/lower_angle" % axis_name, 0.0)
		joint.set("angular_limit_%s/upper_angle" % axis_name, 0.0)
	var instance_id := body.get_instance_id()
	_platform_restraints[instance_id] = joint
	var exiting_callback := _release_platform_restraint_id.bind(instance_id)
	if not body.tree_exiting.is_connected(exiting_callback):
		body.tree_exiting.connect(exiting_callback, CONNECT_ONE_SHOT)
	return joint


func release_platform_restraint(body: RigidBody3D) -> void:
	if not is_instance_valid(body):
		return
	_release_platform_restraint_id(body.get_instance_id())


func _release_platform_restraint_id(instance_id: int) -> void:
	var joint := _platform_restraints.get(instance_id) as Generic6DOFJoint3D
	_platform_restraints.erase(instance_id)
	if is_instance_valid(joint):
		joint.queue_free()


func _exit_tree() -> void:
	for joint_variant in _platform_restraints.values():
		var joint := joint_variant as Generic6DOFJoint3D
		if is_instance_valid(joint):
			joint.queue_free()
	_platform_restraints.clear()


func _create_platform_physics_material() -> PhysicsMaterial:
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = platform_friction
	physics_material.rough = true
	physics_material.bounce = 0.0
	return physics_material

func set_initial_state():
	if start_at_bottom:
		_platform_local_y = -shaft_depth
		platform_target_y = -shaft_depth
		_left_cover_local_x = -_cover_closed_center_x()
		_right_cover_local_x = _cover_closed_center_x()
		_cover_local_y = _cover_deck_y()
		_cover_target_y = _cover_deck_y()
		current_state = ElevatorState.AT_BOTTOM
		_last_platform_y = _platform_local_y
		left_cover_target_x = _left_cover_local_x
		right_cover_target_x = _right_cover_local_x
		_sync_physical_transforms()
		_sync_visual_transforms()
		print("Elevator initialized at bottom")
		return

	# Platform starts at top (flush with deck)
	_platform_local_y = _platform_deck_y()
	platform_target_y = _platform_deck_y()

	# Covers start open inside their below-deck recesses.
	_left_cover_local_x = -_cover_open_center_x()
	_right_cover_local_x = _cover_open_center_x()
	_cover_local_y = _cover_recess_y()
	_cover_target_y = _cover_recess_y()
	left_cover_target_x = _left_cover_local_x
	right_cover_target_x = _right_cover_local_x
	
	current_state = ElevatorState.AT_TOP
	_last_platform_y = _platform_local_y
	_sync_physical_transforms()
	_sync_visual_transforms()
	print("Elevator initialized at top")

func _physics_process(delta: float):
	animate_platform(delta)
	animate_covers(delta)
	_sync_physical_transforms()
	_sync_visual_transforms()
	_update_moving_audio(delta)
	check_state_transitions()

	pass


func _process(_delta: float) -> void:
	# AnimatableBody3D finalises its interpolated transform in the physics step.
	# Mirror once more before rendering so the separate surfaces cannot trail it
	# by a physics frame.
	if not bool(get_meta("technical_index_preview_component", false)):
		_sync_physical_transforms()
	_sync_visual_transforms()

func animate_platform(delta: float):
	if abs(_platform_local_y - platform_target_y) > 0.01:
		var next_y := move_toward(_platform_local_y, platform_target_y, move_speed * delta)
		_platform_local_y = clampf(next_y, -shaft_depth, -platform_size.y / 2.0)
		# Debug: Print movement occasionally (disabled for cleaner output)
		# if Engine.get_process_frames() % 30 == 0:  # Every half second at 60fps
		#	print("[Elevator] Moving - Current Y: ", _platform_local_y, " Target Y: ", platform_target_y, " State: ", current_state)
	else:
		_platform_local_y = platform_target_y

func animate_covers(delta: float):
	# Left cover
	if abs(_left_cover_local_x - left_cover_target_x) > 0.01:
		_left_cover_local_x = move_toward(_left_cover_local_x, left_cover_target_x, cover_slide_speed * delta)
	else:
		_left_cover_local_x = left_cover_target_x
	
	# Right cover
	if abs(_right_cover_local_x - right_cover_target_x) > 0.01:
		_right_cover_local_x = move_toward(_right_cover_local_x, right_cover_target_x, cover_slide_speed * delta)
	else:
		_right_cover_local_x = right_cover_target_x

	if absf(_cover_local_y - _cover_target_y) > 0.005:
		_cover_local_y = move_toward(_cover_local_y, _cover_target_y, cover_lift_speed * delta)
	else:
		_cover_local_y = _cover_target_y

func move_platform_down():
	if current_state == ElevatorState.AT_BOTTOM:
		return
	current_state = ElevatorState.MOVING_DOWN
	platform_target_y = -shaft_depth
	_set_covers_open_target()
	_cover_target_y = _cover_recess_y()

func move_platform_up():
	if current_state == ElevatorState.AT_TOP:
		return
	# The deck plates first sink beneath the deck, then slide into their pockets.
	# The platform cannot rise until the opening is physically clear.
	platform_target_y = -shaft_depth
	_set_covers_closed_target()
	_cover_target_y = _cover_recess_y()
	current_state = ElevatorState.COVERS_LOWERING

func _set_covers_closed_target() -> void:
	left_cover_target_x = -_cover_closed_center_x()
	right_cover_target_x = _cover_closed_center_x()

func _set_covers_open_target() -> void:
	left_cover_target_x = -_cover_open_center_x()
	right_cover_target_x = _cover_open_center_x()

func close_covers():
	current_state = ElevatorState.COVERS_CLOSING
	_cover_target_y = _cover_recess_y()
	_set_covers_closed_target()

func open_covers():
	current_state = ElevatorState.COVERS_LOWERING
	_cover_target_y = _cover_recess_y()

func check_state_transitions():
	match current_state:
		ElevatorState.MOVING_DOWN:
			# Once the lift has cleared the doorway, slide both plates inward while
			# they remain safely below the deck surface.
			if _platform_local_y <= _platform_deck_y() - cover_close_platform_clearance_m:
				_set_covers_closed_target()
				_cover_target_y = _cover_recess_y()
				current_state = ElevatorState.COVERS_CLOSING
		
		ElevatorState.COVERS_CLOSING:
			if covers_are_horizontally_closed():
				_cover_target_y = _cover_deck_y()
				current_state = ElevatorState.COVERS_RAISING

		ElevatorState.COVERS_RAISING:
			if covers_are_raised():
				emit_signal("covers_closed")
				current_state = ElevatorState.COVERS_CLOSED
		
		ElevatorState.COVERS_CLOSED:
			if _platform_local_y <= -shaft_depth + 0.01:
				current_state = ElevatorState.AT_BOTTOM
				emit_signal("elevator_at_bottom")

		ElevatorState.COVERS_LOWERING:
			if covers_are_recessed():
				_set_covers_open_target()
				current_state = ElevatorState.COVERS_OPENING

		ElevatorState.COVERS_OPENING:
			if covers_are_open():
				emit_signal("covers_opened")
				platform_target_y = _platform_deck_y()
				current_state = ElevatorState.MOVING_UP
		
		ElevatorState.MOVING_UP:
			if covers_are_open() and _platform_local_y >= _platform_deck_y() - 0.01:
				current_state = ElevatorState.AT_TOP
				emit_signal("elevator_at_top")

func covers_are_closed() -> bool:
	return covers_are_horizontally_closed() and covers_are_raised()


func covers_are_horizontally_closed() -> bool:
	var left_closed := absf(_left_cover_local_x + _cover_closed_center_x()) < 0.1
	var right_closed := absf(_right_cover_local_x - _cover_closed_center_x()) < 0.1
	return left_closed and right_closed


func covers_are_raised() -> bool:
	return absf(_cover_local_y - _cover_deck_y()) < 0.03


func covers_are_recessed() -> bool:
	return absf(_cover_local_y - _cover_recess_y()) < 0.03

func covers_are_open() -> bool:
	var left_open := absf(_left_cover_local_x + _cover_open_center_x()) < 0.1
	var right_open := absf(_right_cover_local_x - _cover_open_center_x()) < 0.1
	return left_open and right_open and covers_are_recessed()

func get_status() -> Dictionary:
	return {
		"state": current_state,
		"platform_y": _platform_local_y,
		"platform_target_y": platform_target_y,
		"cover_y": _cover_local_y,
		"cover_target_y": _cover_target_y,
		"covers_closed": covers_are_closed(),
		"covers_open": covers_are_open()
	}

func _setup_moving_audio() -> void:
	if moving_sound == null or platform == null:
		return

	if moving_sound is AudioStreamWAV:
		moving_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD

	_moving_audio_player = AudioStreamPlayer3D.new()
	_moving_audio_player.name = "ElevatorMovingAudio"
	_moving_audio_player.stream = moving_sound
	_moving_audio_player.bus = moving_sound_bus
	_moving_audio_player.max_distance = moving_sound_max_distance_m
	_moving_audio_player.unit_size = moving_sound_unit_size_m
	_moving_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_moving_audio_player.volume_db = moving_sound_silence_db
	_moving_audio_player.pitch_scale = moving_sound_pitch_min
	_moving_audio_player.add_to_group("3d_audio")
	platform.add_child(_moving_audio_player)
	_moving_audio_player.call_deferred("play")

func _update_moving_audio(delta: float) -> void:
	if _moving_audio_player == null or platform == null:
		return

	var movement_speed_mps: float = 0.0
	if delta > 0.0:
		movement_speed_mps = absf(_platform_local_y - _last_platform_y) / delta
	_last_platform_y = _platform_local_y

	var speed_factor := clampf(movement_speed_mps / maxf(move_speed, 0.01), 0.0, 1.0)
	speed_factor = speed_factor * speed_factor * (3.0 - 2.0 * speed_factor)
	var target_volume := moving_sound_silence_db if movement_speed_mps < 0.01 else lerpf(moving_sound_min_volume_db, moving_sound_max_volume_db, speed_factor)
	var target_pitch := lerpf(moving_sound_pitch_min, moving_sound_pitch_max, speed_factor)
	var blend := clampf(delta * 6.0, 0.0, 1.0)
	_moving_audio_player.volume_db = lerpf(_moving_audio_player.volume_db, target_volume, blend)
	_moving_audio_player.pitch_scale = lerpf(_moving_audio_player.pitch_scale, target_pitch, blend)
	if not _moving_audio_player.playing:
		_moving_audio_player.call_deferred("play")
