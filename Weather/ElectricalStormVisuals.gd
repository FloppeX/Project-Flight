extends Node3D
## Brief icy charge filaments beneath the darkened dust layer.

const SPARK_COUNT := 28

var _storm: Node3D
var _rng := RandomNumberGenerator.new()
var _spark_root: Node3D
var _sparks: Array[Node3D] = []
var _spark_timer_s := 0.0

func setup(storm: Node3D) -> void:
	_storm = storm
	_rng.randomize()
	_spark_root = Node3D.new()
	_spark_root.name = "CloudSparks"
	add_child(_spark_root)
	_make_sparks()
	visible = false

func update_visuals(delta: float, lower_world_y: float, _upper_world_y: float) -> void:
	if _storm == null or not _storm.active:
		visible = false
		return
	visible = true
	_spark_root.global_position = Vector3(_storm.global_position.x,
		lower_world_y - 85.0, _storm.global_position.z)
	_spark_timer_s += delta
	if _spark_timer_s >= 0.16:
		_spark_timer_s = 0.0
		_randomize_sparks()

func _make_sparks() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.77, 0.92, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.70, 0.88, 1.0)
	material.emission_energy_multiplier = 6.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.94, 0.98, 1.0, 0.7))
	gradient.set_color(1, Color(0.55, 0.82, 1.0, 0.0))
	var glow_texture := GradientTexture2D.new()
	glow_texture.width = 64
	glow_texture.height = 64
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(0.5, 0.0)
	glow_texture.gradient = gradient
	for i in SPARK_COUNT:
		var spark := Node3D.new()
		spark.name = "Spark%02d" % i
		_spark_root.add_child(spark)
		_add_spark_segment(spark, Vector3(-15, 8, 0), Vector3(2, -12, 5), material)
		_add_spark_segment(spark, Vector3(2, -12, 5), Vector3(14, -27, -4), material)
		var glow := Sprite3D.new()
		glow.texture = glow_texture
		glow.pixel_size = 0.9
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		glow.shaded = false
		glow.modulate = Color(0.83, 0.94, 1.0, 0.5)
		spark.add_child(glow)
		spark.visible = false
		_sparks.append(spark)

func _add_spark_segment(parent: Node3D, start: Vector3, finish: Vector3,
		material: Material) -> void:
	var delta := finish - start
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.5
	mesh.bottom_radius = 2.5
	mesh.height = delta.length()
	mesh.radial_segments = 4
	mesh.material = material
	var segment := MeshInstance3D.new()
	segment.mesh = mesh
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(segment)
	segment.transform = Transform3D(Basis(Quaternion(Vector3.UP, delta.normalized())), (start + finish) * 0.5)

func _randomize_sparks() -> void:
	var radius: float = float(_storm.get("cloud_radius_m"))
	for spark in _sparks:
		spark.visible = _rng.randf() < 0.22
		if not spark.visible:
			continue
		var angle := _rng.randf_range(0.0, TAU)
		var distance := sqrt(_rng.randf()) * radius * 0.82
		spark.position = Vector3(cos(angle) * distance, _rng.randf_range(-75.0, 35.0),
			sin(angle) * distance)
		spark.rotation.y = _rng.randf_range(-PI, PI)
		spark.scale = Vector3.ONE * _rng.randf_range(0.7, 1.6)
