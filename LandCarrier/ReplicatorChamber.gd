extends Node3D
## Reusable low-poly chamber. Visual state comes from the saved replicator job.
const CATALOG := preload("res://LandCarrier/ReplicatorCatalog.gd")
const SECTIONS := preload("res://LandCarrier/ReplicatorMeshSections.gd")
const SHIELD_APOTHEM := 5.65
const OCTAGON_FACE := 2.0 * SHIELD_APOTHEM * tan(PI / 8.0)
const CEILING_HEIGHT := 7.525 # Flush with the top of the white fabrication ring.
const DEFAULT_SHIELD_OPACITY := 0.83
const MOTION := preload("res://LandCarrier/ReplicatorArmMotion.gd")
const MODEL_PATH := "res://Models/Replicator/replicator.blend"
var export_source := false # Used only by tools/export_replicator.gd.
var _model: Node3D
var _shield: Node3D
var _platform: Node3D
var _platform_home: Transform3D
var _platform_to_chamber: Transform3D
var _camera: Camera3D
var _product: Node3D
var _pieces: Array[Dictionary] = []
var _arms: Array[Dictionary] = []
var _clock := 0.0
var _state := {"phase": "idle", "progress": 0.0, "shield": 0.0, "rollout": 0.0, "stage": -1}
var _hum: AudioStreamPlayer
var _audio_enabled := false
var _product_recipe := "kmv_explorer"
var _source_piece_count := 0
var _products: Dictionary = {}
var _motion := MOTION.new()
var _job_id := -1
var _last_progress := 0.0
var _feed_initialized := false
var _shield_material: StandardMaterial3D
var _shield_opacity := DEFAULT_SHIELD_OPACITY

func _ready() -> void:
	# This isolated camera scene is animated at render cadence, not physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if export_source:
		set_process(false)
		_build_chamber_source()
		return
	_build_chamber()
	_platform_home = _platform.transform
	_platform_to_chamber = global_transform.affine_inverse() * _platform.global_transform
	_build_product()
	_section_product()
	_remember_product()
	_hum = AudioStreamPlayer.new()
	var hum := preload("res://Audio/cockpit/electrical_hum_2.wav").duplicate() as AudioStreamWAV
	hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum.loop_begin = 0
	hum.loop_end = int(hum.get_length() * hum.mix_rate)
	_hum.stream = hum
	_hum.volume_db = -24.0
	add_child(_hum)

func resume_feed() -> void:
	# The next snapshot includes work completed while this feed was hidden.
	_feed_initialized = false

func get_shield_opacity() -> float:
	return _shield_opacity

func set_shield_opacity(value: float) -> void:
	_shield_opacity = clampf(value, 0.0, 1.0)
	if is_instance_valid(_shield_material):
		var tint := _shield_material.albedo_color
		tint.a = _shield_opacity
		_shield_material.albedo_color = tint

func set_feed_state(state: Dictionary, audio_enabled: bool = false) -> void:
	var recipe_id := str(state.get("recipe", _product_recipe))
	var next_job := int(state.get("job_id", _job_id))
	var reset := not _feed_initialized or recipe_id != _product_recipe or next_job != _job_id or float(state.progress) < _last_progress
	if reset:
		_motion.reset_job()
	_job_id = next_job
	_last_progress = float(state.progress)
	if not recipe_id.is_empty() and recipe_id != _product_recipe:
		_product.visible = false
		_product_recipe = recipe_id
		if _products.has(recipe_id):
			var cached: Dictionary = _products[recipe_id]
			_product = cached.node
			_pieces = cached.pieces
			_source_piece_count = cached.source_piece_count
		else:
			_pieces = []
			_build_product()
			_section_product()
			_remember_product()
	if reset:
		# A feed opened/restored partway through a job shows the work already done
		# off camera. During uninterrupted viewing, only beam contact primes parts.
		var completed := mini(_pieces.size() - 1, int(float(state.progress) * _pieces.size()))
		for index in range(_pieces.size()):
			_pieces[index].primed = float(state.progress) > 0.0 and index <= completed
			_pieces[index].preweld_seconds = 0.0
			_pieces[index].preweld_arm = -1
	_feed_initialized = true
	_state = state
	_audio_enabled = audio_enabled
	if not audio_enabled and is_instance_valid(_hum):
		_hum.stop()

func _process(delta: float) -> void:
	_clock += delta
	var working: bool = str(_state.phase) == "fabricating" and bool(_state.get("powered", true))
	_shield.position.y = (1.0 - float(_state.shield)) * 6.0
	# Telescoping panels retract into the ring instead of protruding above it.
	_shield.scale.y = maxf(0.002, float(_state.shield))
	_shield.visible = float(_state.shield) > 0.001
	var progress := clampf(float(_state.progress), 0.0, 1.0)
	_product.visible = int(_state.stage) >= 0
	_platform.position.z = _platform_home.origin.z + smoothstep(0.0, 1.0, float(_state.rollout)) * 17.0
	var active := mini(_pieces.size() - 1, int(progress * _pieces.size()))
	var duration := float(CATALOG.recipe(_product_recipe).get("duration_s", 90.0))
	# Reach upcoming sections ahead of their material delivery, instead of
	# chasing a layer that has already appeared. Keep the lead spatially small.
	var available := mini(_pieces.size() - 1, active + maxi(4, int(_pieces.size() * 4.0 / duration)))
	_motion.advance(delta, working, _pieces, available, clampf(duration / 90.0, 0.22, 1.0))
	for index in range(_pieces.size()):
		(_pieces[index].node as Node3D).visible = _product.visible and bool(_pieces[index].get("primed", false))
	for index in range(_arms.size()):
		var arm := _arms[index]
		var pose: Dictionary = _motion.poses[index]
		var job: Dictionary = _motion.jobs[index]
		var shoulder: Vector3 = pose.shoulder
		var pulse := _clock * 11.0 + index * 1.8
		var tip: Vector3 = pose.wrist
		var active_arm: bool = working and int(job.piece_index) >= 0 and job.mode in ["approach", "weld", "rest"]
		var target: Vector3 = job.target if active_arm else tip - Vector3.UP * 0.5
		arm["tip_position"] = tip
		var elbow: Vector3 = pose.elbow
		_pose_link(arm.upper, shoulder, elbow)
		_pose_link(arm.forearm, elbow, tip)
		(arm.joint as Node3D).position = elbow
		(arm.tool as Node3D).position = tip
		var direction := (tip - target).normalized() if active_arm else Vector3.UP
		var tool_x := direction.cross(Vector3.FORWARD).normalized()
		if tool_x.length_squared() < 0.1:
			tool_x = direction.cross(Vector3.RIGHT).normalized()
		(arm.tool as Node3D).basis = Basis(tool_x, direction, tool_x.cross(direction).normalized())
		var nozzle := tip - direction * 0.5
		var contact: bool = active_arm and job.mode == "weld" and nozzle.distance_to(target) < 0.85
		arm["weld_target"] = target
		arm["piece_index"] = int(job.piece_index) if active_arm else -1
		arm["contact"] = contact
		(arm.light as OmniLight3D).position = Vector3(0, -0.5, 0)
		(arm.light as OmniLight3D).light_energy = (3.0 + 4.0 * pow(maxf(sin(pulse), 0.0), 8.0)) if contact else 0.0
		(arm.sparks as CPUParticles3D).emitting = contact
		(arm.sparks as Node3D).position = target
		(arm.glow as MeshInstance3D).visible = contact
		(arm.glow as Node3D).position = target
		(arm.glow as Node3D).scale = Vector3.ONE * (0.9 + 0.2 * maxf(sin(pulse), 0.0))
		(arm.laser as MeshInstance3D).visible = contact and sin(pulse) > -0.5
		_pose_link(arm.laser, nozzle, target + direction * -0.025)
	if working and _audio_enabled:
		if not _hum.playing:
			_hum.play()
	else:
		_hum.stop()

func get_debug_snapshot() -> Dictionary:
	var visible_pieces := 0
	for piece in _pieces:
		if (piece.node as Node3D).visible:
			visible_pieces += 1
	var contacts := 0
	var connected_targets := 0
	var modes: Array[String] = []
	for arm in _arms:
		contacts += 1 if bool(arm.get("contact", false)) else 0
		var piece_index := int(arm.get("piece_index", -1))
		if piece_index >= 0 and piece_index < _pieces.size():
			connected_targets += 1 if bool(_pieces[piece_index].connected_seam) else 0
	for job in _motion.jobs:
		modes.append(str(job.mode))
	return {"arms": _arms.size(), "piece_count": _pieces.size(), "visible_pieces": visible_pieces,
		"source_piece_count": _source_piece_count, "welding_contacts": contacts, "connected_targets": connected_targets,
		"shield_apothem": SHIELD_APOTHEM, "pad_apothem": SHIELD_APOTHEM,
		"arm_modes": modes, "all_arms_stowed": _motion.all_stowed(), "welding_passes": _motion.passes,
		"platform_position": _platform.position.z,
		"shield_opacity": _shield_opacity,
		"shield_height": _shield.position.y, "stage": int(_state.stage), "hum_playing": _hum.playing,
		"recipe": _product_recipe, "product_scale": _product.scale.x}

func _material(color: Color, metal: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.65
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material

func _box(parent: Node3D, dimensions: Vector3, location: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(parent, mesh, location, material)

func _mesh(parent: Node3D, mesh: Mesh, location: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = location
	parent.add_child(instance)
	return instance

func _cylinder(parent: Node3D, radius: float, height: float, location: Vector3, material: Material, sides: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	return _mesh(parent, mesh, location, material)

func _build_chamber() -> void:
	# The legacy geometry export tool can still bootstrap without an import.
	var baking := false
	for arg in OS.get_cmdline_args():
		baking = baking or arg.ends_with("export_replicator.gd")
	if not ResourceLoader.exists(MODEL_PATH) or baking:
		_build_chamber_source()
		return
	_model = (load(MODEL_PATH) as PackedScene).instantiate()
	_model.name = "ReplicatorModel"
	add_child(_model)
	# Blender's scene import wraps the authored Replicator empty in a scene root.
	var rig: Node3D = _model.get_node("Replicator")
	_platform = rig.get_node("TransferPlatform")
	_shield = rig.get_node("DescendingShield")
	# Each feed owns its opacity; do not mutate the shared imported material.
	for panel: MeshInstance3D in _shield.find_children("*", "MeshInstance3D", true, false):
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if panel.name.begins_with("ShieldPanel"):
			if _shield_material == null:
				_shield_material = panel.get_active_material(0).duplicate() as StandardMaterial3D
				# GLTF BLEND imports with a depth prepass; retain the feed's original
				# alpha blending so weld glow remains visible through all faces.
				_shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			panel.material_override = _shield_material
	set_shield_opacity(_shield_opacity)
	for index in range(4):
		var arm_root: Node3D = rig.get_node("Arms/Arm_%d" % index)
		var arm := {"upper": arm_root.get_node("Upper_%d" % index), "forearm": arm_root.get_node("Forearm_%d" % index),
			"joint": arm_root.get_node("Joint_%d" % index), "tool": arm_root.get_node("Tool_%d" % index)}
		_add_arm_effects(arm)
		_arms.append(arm)
	_setup_lighting_camera()

func _add_arm_effects(arm: Dictionary) -> void:
	var tool: Node3D = arm.tool
	var weld := _material(Color("ffad44"), 0.0, 9.0)
	var weld_core := _material(Color("ffe5aa"), 0.0, 12.0)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb866")
	light.omni_range = 4.5
	light.light_energy = 0.0
	tool.add_child(light)
	var laser := _cylinder(self, 0.022, 1, Vector3.ZERO, weld)
	var pool_mesh := SphereMesh.new()
	pool_mesh.radius = 0.07
	pool_mesh.height = 0.14
	var glow := _mesh(self, pool_mesh, Vector3.ZERO, weld_core)
	glow.visible = false
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sparks := CPUParticles3D.new()
	sparks.amount = 26
	sparks.lifetime = 0.45
	sparks.emitting = false
	sparks.direction = Vector3(0, -0.25, 1)
	sparks.spread = 70.0
	sparks.initial_velocity_min = 1.2
	sparks.initial_velocity_max = 3.0
	sparks.gravity = Vector3(0, -5, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.5
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.035
	spark_mesh.height = 0.09
	spark_mesh.material = weld
	sparks.mesh = spark_mesh
	add_child(sparks)
	arm.merge({"light": light, "laser": laser, "sparks": sparks, "glow": glow})

func _octagon_segment(parent: Node3D, apothem: float, height: float, depth: float, elevation: float, angle: float, material: Material) -> MeshInstance3D:
	# Mitred end planes pass through the octagon centre. Inner and outer edges
	# therefore meet their neighbours exactly, even on the thick upper housing.
	var inner := (apothem - depth * 0.5) * tan(PI / 8.0)
	var outer := (apothem + depth * 0.5) * tan(PI / 8.0)
	var half_height := height * 0.5
	var half_depth := depth * 0.5
	var corners := PackedVector3Array([
		Vector3(-inner, -half_height, -half_depth), Vector3(inner, -half_height, -half_depth),
		Vector3(outer, -half_height, half_depth), Vector3(-outer, -half_height, half_depth),
		Vector3(-inner, half_height, -half_depth), Vector3(inner, half_height, -half_depth),
		Vector3(outer, half_height, half_depth), Vector3(-outer, half_height, half_depth)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for face in [[0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7], [0, 3, 2, 1], [4, 5, 6, 7]]:
		var normal := -(corners[face[1]] - corners[face[0]]).cross(corners[face[2]] - corners[face[0]]).normalized()
		for corner in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(normal)
			surface.set_uv(uvs[corner])
			surface.add_vertex(corners[face[corner]])
	surface.index()
	var segment := _mesh(parent, surface.commit(), Vector3(sin(angle) * apothem, elevation, cos(angle) * apothem), material)
	segment.rotation.y = angle
	return segment

func _build_chamber_source() -> void:
	var ivory := _material(Color("d7d1be"), 0.35)
	var yellow := _material(Color("e8a52d"), 0.4)
	var dark := _material(Color("303b40"), 0.6)
	var floor_mat := _material(Color("414a4e"), 0.15)
	var white_light := _material(Color("ffe2a9"), 0.0, 3.0)
	_box(self, Vector3(21, 0.25, 32), Vector3(0, -0.18, 8.25), floor_mat)
	# The machine is installed in a compact carrier compartment. Its overhead
	# drives sit above the ceiling; only the ring and working arms are exposed.
	var ceiling := _box(self, Vector3(21, 0.35, 32), Vector3(0, CEILING_HEIGHT + 0.175, 8.25), floor_mat)
	ceiling.name = "CarrierCeiling"
	_box(self, Vector3(21, CEILING_HEIGHT, 0.3), Vector3(0, CEILING_HEIGHT * 0.5, -7.4), dark)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(0.3, CEILING_HEIGHT, 32), Vector3(side * 10.5, CEILING_HEIGHT * 0.5, 8.25), dark)
		_box(self, Vector3(0.16, 0.35, 32), Vector3(side * 10.3, CEILING_HEIGHT - 0.175, 8.25), ivory)
		_box(self, Vector3(0.1, 0.12, 30), Vector3(side * 10.3, 0.65, 8.25), yellow)
		_box(self, Vector3(2.4, 0.08, 0.45), Vector3(side * 7.4, CEILING_HEIGHT - 0.08, -2.5), white_light)
	_platform = Node3D.new()
	_platform.name = "TransferPlatform"
	add_child(_platform)
	# Build pad is level with the surrounding floor; rim and lanes mark it out.
	# Cylinder radii are circumradii, whereas panels sit on the apothem.
	# Rotate the vertices half a face so every flat edge follows a shield panel.
	for layer in [[SHIELD_APOTHEM + 0.18, -0.04, yellow, "BuildPadRim"], [SHIELD_APOTHEM, -0.035, dark, "BuildPadSeal"], [SHIELD_APOTHEM - 0.16, -0.03, floor_mat, "BuildPadFloor"]]:
		var pad := _cylinder(_platform if layer[3] == "BuildPadFloor" else self, float(layer[0]) / cos(PI / 8.0), 0.10, Vector3(0, layer[1], 0), layer[2])
		pad.name = layer[3]
		pad.rotation.y = PI / 8.0
	for index in range(8):
		var angle := index * TAU / 8.0
		var border := _octagon_segment(_platform, 5.45, 0.035, 0.06, 0.04, angle, yellow)
		border.name = "TrayBorder_%02d" % index
	for lane in [-1.8, 1.8]:
		_box(self, Vector3(0.12, 0.015, 27.0), Vector3(lane, 0.02, 10), yellow)
	# Embedded transfer rails and a marked docking room beyond the chamber.
	for side in [-1.0, 1.0]:
		_box(self, Vector3(0.25, 0.03, 28), Vector3(side * 3.8, 0.015, 10), dark)
		_box(_platform, Vector3(0.12, 0.04, 7.0), Vector3(side * 3.8, 0.04, 0), yellow)
		_box(self, Vector3(0.5, 3.6, 0.6), Vector3(side * 6.3, 1.8, 14), ivory)
		_box(self, Vector3(0.3, 0.16, 0.7), Vector3(side * 6.3, 3.3, 14), white_light)
		_box(self, Vector3(0.25, 3.6, 10), Vector3(side * 7.0, 1.8, 19), dark)
	_box(self, Vector3(21, CEILING_HEIGHT, 0.25), Vector3(0, CEILING_HEIGHT * 0.5, 24), dark)
	for stripe in range(9):
		var mark := _box(self, Vector3(0.5, 0.025, 0.12), Vector3(-2.3 + stripe * 0.57, 0.025, 5.3), yellow)
		mark.rotation.y = -PI / 4.0
	_shield = Node3D.new()
	_shield.name = "DescendingShield"
	add_child(_shield)
	var glass := _material(Color(0.27, 0.38, 0.39, _shield_opacity), 0.15)
	_shield_material = glass
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for index in range(8):
		var angle := index * TAU / 8.0
		var radial := Vector3(sin(angle), 0, cos(angle))
		var ring_segment := _octagon_segment(self, 5.7, 1.15, 0.85, 6.95, angle, ivory)
		ring_segment.name = "UpperOctagon_%02d" % index
		var vent := _box(self, Vector3(0.8, 0.12, 0.06), radial * 6.15 + Vector3(0, 7.17, 0), dark)
		vent.rotation.y = angle
		var lower_rail := _octagon_segment(self, 5.7, 0.22, 0.95, 6.3, angle, dark)
		lower_rail.name = "LowerOctagonRail_%02d" % index
		var lamp := _box(self, Vector3(1.15, 0.1, 0.3), radial * 5.25 + Vector3(0, 6.15, 0), white_light)
		lamp.rotation.y = angle
		var shield_panel := _octagon_segment(_shield, SHIELD_APOTHEM, 5.9, 0.06, 3.0, angle, glass)
		shield_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_octagon_segment(_shield, SHIELD_APOTHEM, 0.13, 0.16, 0.09, angle, yellow)
		var rib := _box(self, Vector3(0.35, 1.48, 1.1), radial * 5.72 + Vector3(0, 6.95, 0), yellow)
		rib.rotation.y = angle
	# Rear columns carry the ring without blocking the roll-out lane.
	for side in [-1.0, 1.0]:
		_box(self, Vector3(0.7, 7.8, 0.8), Vector3(side * 4.4, 3.85, -4.4), ivory)
		_box(self, Vector3(0.24, 6.8, 0.22), Vector3(side * 4.4, 3.4, -3.9), dark)
	for index in range(4):
		var upper := _box(self, Vector3(0.55, 1, 0.6), Vector3.ZERO, yellow)
		_box(upper, Vector3(0.32, 0.65, 0.64), Vector3.ZERO, dark)
		var forearm := _box(self, Vector3(0.35, 1, 0.4), Vector3.ZERO, ivory)
		_box(forearm, Vector3(0.38, 0.3, 0.44), Vector3(0, -0.2, 0), yellow)
		var joint := _cylinder(self, 0.4, 0.65, Vector3.ZERO, dark)
		joint.rotation.z = PI / 2.0
		var tool := _box(self, Vector3(0.3, 0.55, 0.3), Vector3.ZERO, yellow)
		_cylinder(tool, 0.06, 0.3, Vector3(0, -0.35, 0), dark)
		var arm := {"upper": upper, "forearm": forearm, "joint": joint, "tool": tool}
		_add_arm_effects(arm)
		_arms.append(arm)
	_setup_lighting_camera()

func _setup_lighting_camera() -> void:
	for side in [-1.0, 1.0]:
		var room_light := OmniLight3D.new()
		room_light.position = Vector3(side * 7.4, 6.8, -2.5)
		room_light.light_color = Color("ffe2bf")
		room_light.light_energy = 2.0
		room_light.omni_range = 15.0
		add_child(room_light)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("202c34")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("bed2d9")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	environment.environment = env
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 1.7
	key.shadow_enabled = true
	add_child(key)
	var camera := Camera3D.new()
	_camera = camera
	camera.name = "ChamberCamera"
	camera.position = Vector3(9.0, 5.4, 12.5)
	add_child(camera)
	camera.look_at(Vector3(0, 3.5, 0))
	camera.fov = 50.0
	camera.current = true

func _pose_link(link: Node3D, start: Vector3, end: Vector3) -> void:
	var direction := end - start
	link.position = (start + end) * 0.5
	var y := direction.normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.1:
		x = y.cross(Vector3.RIGHT).normalized()
	link.basis = Basis(x, y, x.cross(y).normalized())
	link.scale = Vector3(1, direction.length(), 1)

func _build_product() -> void:
	_product = Node3D.new()
	_product.name = "StagedProduct"
	_platform.add_child(_product)
	var recipe := CATALOG.recipe(_product_recipe)
	if str(recipe.get("category", "")) == "ORDNANCE":
		_build_ordnance(recipe)
		_seat_product_on_platform()
		_product.visible = false
		return
	if str(recipe.get("category", "")) == "AIRFRAMES":
		_build_airframe(recipe)
		_seat_product_on_platform()
		_product.visible = false
		return
	_product.scale = Vector3.ONE * 0.65
	var chassis_material := _material(Color("4e595b"), 0.6)
	for side in [-1.1, 1.1]:
		var beam := _box(_product, Vector3(0.22, 0.24, 7.5), Vector3(side, 0.35, 0), chassis_material)
		_pieces.append({"node": beam, "stage": 0})
	for crossbar in [-2.5, 0.0, 2.5]:
		var beam := _box(_product, Vector3(2.5, 0.24, 0.18), Vector3(0, 0.35, crossbar), chassis_material)
		_pieces.append({"node": beam, "stage": 0})
	# Copy visual nodes only, retaining authored transforms/meshes. No vehicle AI,
	# weapons, physics or groups run inside the camera feed.
	var source := (load(str(recipe.get("scene", "res://GroundVehicle/ground_vehicle_1.tscn"))) as PackedScene).instantiate()
	for child in source.get_children():
		if child.name == "Body" or str(child.name).begins_with("wheel_"):
			_copy_visual(child, _product, 2 if str(child.name).begins_with("wheel_") else 0)
	source.free()
	_seat_product_on_platform()
	_product.visible = false

func _seat_product_on_platform() -> void:
	# Read the authored deck mesh, excluding the raised border and decorations.
	# Work in tray space so either mesh edits or moving the tray empty are kept.
	var floor_mesh := _platform.get_node("BuildPadFloor") as MeshInstance3D
	var floor_to_platform := _platform.global_transform.affine_inverse() * floor_mesh.global_transform
	var floor_bounds: AABB = floor_to_platform * floor_mesh.get_aabb()
	var product_bounds: AABB = _product.transform * _visual_bounds(_product)
	_product.position.y += floor_bounds.end.y - product_bounds.position.y

func _build_airframe(recipe: Dictionary) -> void:
	var source := (load(str(recipe.scene)) as PackedScene).instantiate()
	for child in source.get_children():
		var label := str(child.name).to_lower()
		if label.begins_with("aircraft_") or "gearrig" in label or label in ["rotorassembly", "tailrotor"]:
			_copy_visual(child, _product, 1, true)
	source.free()
	var bounds := _visual_bounds(_product)
	var span := maxf(bounds.size.x, bounds.size.z)
	# Fit the authored aircraft into the pad without changing its source scene.
	var fit := minf(1.0, 8.0 / maxf(span, 0.01))
	_product.scale = Vector3.ONE * fit
	var metal := _material(Color("69777b"), 0.65)
	var frame_y := bounds.position.y + bounds.size.y * 0.35
	for side in [-0.35, 0.35]:
		var beam := _box(_product, Vector3(0.12, 0.12, bounds.size.z * 0.8), Vector3(side, frame_y, bounds.get_center().z), metal)
		_pieces.append({"node": beam, "stage": 0})

func _visual_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var transform_to_root := Transform3D.IDENTITY
		var ancestor: Node3D = mesh
		while ancestor != node:
			transform_to_root = ancestor.transform * transform_to_root
			ancestor = ancestor.get_parent() as Node3D
		var mesh_bounds: AABB = transform_to_root * mesh.get_aabb()
		bounds = bounds.merge(mesh_bounds) if found else mesh_bounds
		found = true
	return bounds

func _build_ordnance(recipe: Dictionary) -> void:
	if str(recipe.id) in ["bombs", "rockets", "bullets"]:
		var source := (load(str(recipe.build_scene)) as PackedScene).instantiate()
		_copy_visual(source, _product, 0)
		source.free()
		return
	var olive := _material(Color("62674b"), 0.25)
	var yellow := _material(Color("e8a52d"), 0.25)
	var brass := _material(Color("bba36b"), 0.6)
	var crate := _box(_product, Vector3(3.4, 0.22, 2.5), Vector3(0, 0.15, 0), olive)
	_pieces.append({"node": crate, "stage": 0})
	for side in [-1.7, 1.7]:
		var wall := _box(_product, Vector3(0.12, 0.65, 2.5), Vector3(side, 0.45, 0), yellow)
		_pieces.append({"node": wall, "stage": 1})
	var holder := Node3D.new()
	_product.add_child(holder)
	var source := (load(str(recipe.scene)) as PackedScene).instantiate()
	_copy_visual(source, holder, 2)
	source.free()
	var bounds := _visual_bounds(holder)
	var span := maxf(0.01, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	var fit := 2.2 / span
	holder.scale = Vector3.ONE * fit
	holder.position = Vector3(0, 0.8 - bounds.position.y * fit, -bounds.get_center().z * fit)
	var packing := _box(_product, Vector3(3.4, 0.12, 0.18), Vector3(0, 0.75, 1.16), yellow)
	_pieces.append({"node": packing, "stage": 3})
	var seal := _box(_product, Vector3(1.2, 0.12, 0.14), Vector3(0, 0.3, 1.3), brass)
	_pieces.append({"node": seal, "stage": 4})

func _section_product() -> void:
	var originals := _pieces.duplicate()
	_source_piece_count = originals.size()
	_pieces.clear()
	for original in originals:
		var visual: MeshInstance3D = original.node
		# Weld targets must include the authored tray elevation, just like the mesh.
		var to_chamber := _platform_to_chamber * _product.transform
		var relative := Transform3D.IDENTITY
		var ancestor: Node3D = visual
		while ancestor != _product:
			relative = ancestor.transform * relative
			ancestor = ancestor.get_parent() as Node3D
		to_chamber *= relative
		var sections := SECTIONS.split(visual.mesh, to_chamber)
		# Keep the hierarchy as a transform/skin reference, but render derivatives.
		visual.layers = 0
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for section in sections:
			var fragment := MeshInstance3D.new()
			fragment.name = str(visual.name) + "_Section_" + str(section.cell)
			fragment.mesh = section.mesh
			fragment.material_override = visual.material_override
			fragment.skin = visual.skin
			fragment.skeleton = visual.skeleton
			fragment.transform = visual.transform
			for surface in range(section.surfaces.size()):
				fragment.set_surface_override_material(surface, visual.get_surface_override_material(section.surfaces[surface]))
			visual.get_parent().add_child(fragment)
			fragment.visible = false
			var bounds := AABB(section.points[0], Vector3.ZERO)
			for point in section.points:
				bounds = bounds.expand(point)
			var seams: Array = section.seams
			if seams.is_empty():
				seams = [[section.points[0], section.points[1]]]
			_pieces.append({"node": fragment, "cell": section.cell, "bounds": bounds, "center": bounds.get_center(), "seams": seams, "weld_seams": [], "connected_seam": false, "primed": false, "stage": 0})
	_pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.center.y, b.center.y):
			return a.center.y < b.center.y
		return a.center.z < b.center.z if not is_equal_approx(a.center.z, b.center.z) else a.center.x < b.center.x)
	# Match shared surface edges to previously built sections. The first section
	# has no neighbour yet; subsequent welds prefer these joining seams.
	var edge_owners: Dictionary = {}
	for index in range(_pieces.size()):
		var piece := _pieces[index]
		piece.stage = mini(4, int(index * 5.0 / _pieces.size()))
		for seam in piece.seams:
			var key := _edge_key(seam)
			if edge_owners.has(key) and int(edge_owners[key]) < index:
				piece.weld_seams.append(seam)
				edge_owners[key] = index
			else:
				edge_owners[key] = index
		piece.connected_seam = not piece.weld_seams.is_empty()
		if piece.weld_seams.is_empty():
			piece.weld_seams = piece.seams.slice(0, mini(6, piece.seams.size()))

func _edge_key(seam: Array) -> String:
	var a := str(Vector3i(((seam[0] as Vector3) * 1000.0).round()))
	var b := str(Vector3i(((seam[1] as Vector3) * 1000.0).round()))
	return a + "/" + b if a < b else b + "/" + a

func _remember_product() -> void:
	_products[_product_recipe] = {"node": _product, "pieces": _pieces, "source_piece_count": _source_piece_count}

func _copy_visual(source: Node, parent: Node3D, stage: int, airframe: bool = false) -> void:
	if not source is Node3D or source is CollisionObject3D or source is CollisionShape3D:
		return
	if airframe and "rotor disc" in str(source.name).to_lower():
		return
	var copy: Node3D
	var chosen_stage := stage
	if airframe:
		var label := str(source.name).to_lower()
		if "wing" in label or "stabiliz" in label or "rotor" in label or "blade" in label or "propeller" in label:
			chosen_stage = 2
		if "gear" in label or "skid" in label or "wheel" in label or "door" in label:
			chosen_stage = 3
		if "cockpit" in label or "canopy" in label or "glass" in label or "window" in label or "seat" in label or "instrument" in label:
			chosen_stage = 4
	if "Turret" in str(source.name):
		chosen_stage = 4
	if source is MeshInstance3D:
		var source_mesh := source as MeshInstance3D
		var visual := MeshInstance3D.new()
		visual.mesh = source_mesh.mesh
		visual.material_override = source_mesh.material_override
		visual.skin = source_mesh.skin
		visual.skeleton = source_mesh.skeleton
		for surface in range(source_mesh.get_surface_override_material_count()):
			visual.set_surface_override_material(surface, source_mesh.get_surface_override_material(surface))
		copy = visual
		if chosen_stage == 0:
			var label := str(source.name).to_lower()
			chosen_stage = 3 if "door" in label or "roof" in label or "window" in label else 1
		_pieces.append({"node": copy, "stage": chosen_stage})
	elif source is Skeleton3D:
		var original := source as Skeleton3D
		var skeleton := Skeleton3D.new()
		for bone in range(original.get_bone_count()):
			skeleton.add_bone(original.get_bone_name(bone))
		for bone in range(original.get_bone_count()):
			skeleton.set_bone_parent(bone, original.get_bone_parent(bone))
			skeleton.set_bone_rest(bone, original.get_bone_rest(bone))
			skeleton.set_bone_pose_position(bone, original.get_bone_pose_position(bone))
			skeleton.set_bone_pose_rotation(bone, original.get_bone_pose_rotation(bone))
			skeleton.set_bone_pose_scale(bone, original.get_bone_pose_scale(bone))
		copy = skeleton
	else:
		copy = Node3D.new()
	copy.name = source.name
	copy.transform = (source as Node3D).transform
	parent.add_child(copy)
	for child in source.get_children():
		_copy_visual(child, copy, chosen_stage, airframe)
