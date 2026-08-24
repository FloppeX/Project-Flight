extends Node

const AircraftOutlineRenderer = preload("res://tools/AircraftOutlineRenderer.gd")
const OUTLINE_PATH_FORMAT := "res://Images/Aircraft Outlines/aircraft_%d.png"
const AIRCRAFT_COUNT := 12
const EXPECTED_SIZE := Vector2i(512, 512)

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_helicopter_render_jobs()
	var aircraft_1_image: Image = null
	for aircraft_index in range(1, AIRCRAFT_COUNT + 1):
		var outline_path := OUTLINE_PATH_FORMAT % aircraft_index
		var outline_texture := load(outline_path) as Texture2D
		_expect(outline_texture != null, "Aircraft %d outline imports as a texture" % aircraft_index)
		if outline_texture == null:
			continue
		var image := outline_texture.get_image()
		_expect(image != null and not image.is_empty(), "Aircraft %d outline loads" % aircraft_index)
		if image == null or image.is_empty():
			continue
		image.convert(Image.FORMAT_RGBA8)
		_validate_common_icon_properties(image, aircraft_index)
		if aircraft_index == 1:
			aircraft_1_image = image

	if aircraft_1_image != null:
		_validate_aircraft_1_orientation(aircraft_1_image)
	_finish()


func _validate_common_icon_properties(image: Image, aircraft_index: int) -> void:
	var label := "Aircraft %d" % aircraft_index
	_expect(image.get_size() == EXPECTED_SIZE, "%s outline is 512 by 512 pixels" % label)
	_expect(image.get_pixel(0, 0).a <= 0.001, "%s background remains transparent" % label)

	var bounds := _alpha_bounds(image)
	_expect(maxf(bounds.size.x, bounds.size.y) > 380.0, "%s uses the available canvas" % label)
	_expect(minf(bounds.size.x, bounds.size.y) > 120.0, "%s silhouette is visible on both axes" % label)
	if aircraft_index >= 9:
		_expect(bounds.size.x > 300.0, "%s includes its circular rotor-radius outline" % label)
	_expect(bounds.position.x > 0.0 and bounds.position.y > 0.0, "%s keeps transparent padding" % label)
	_expect(bounds.end.x < EXPECTED_SIZE.x and bounds.end.y < EXPECTED_SIZE.y, "%s does not touch the canvas edge" % label)

	var color_counts := _count_fill_and_outline_pixels(image)
	_expect(int(color_counts.get("fill", 0)) > 1000, "%s contains the pale silhouette fill" % label)
	_expect(int(color_counts.get("outline", 0)) > 300, "%s contains the dark exterior outline" % label)


func _validate_helicopter_render_jobs() -> void:
	var helicopter_job_count := 0
	for job_variant in AircraftOutlineRenderer.JOBS:
		if not job_variant is Dictionary:
			continue
		var job := job_variant as Dictionary
		var name := str(job.get("name", ""))
		var index := int(name.trim_prefix("aircraft_"))
		if index < 9:
			continue
		helicopter_job_count += 1
		var rotor_disc_paths: Array = job.get("rotor_disc_paths", [])
		_expect(not rotor_disc_paths.is_empty(), "%s measures an authored rotor radius" % name)
		var include_paths: Array = job.get("include_paths", [])
		for include_path_variant in include_paths:
			_expect(
				not str(include_path_variant).to_lower().contains("rotorassembly"),
				"%s excludes main-rotor blade geometry" % name
			)
	_expect(helicopter_job_count == 4, "renderer defines four helicopter outline jobs")


func _validate_aircraft_1_orientation(image: Image) -> void:
	var bounds := _alpha_bounds(image)
	if bounds.size.y <= 0.0:
		return
	var nose_row := int(bounds.position.y + bounds.size.y * 0.12)
	var tail_row := int(bounds.position.y + bounds.size.y * 0.92)
	var nose_width := _alpha_width_on_row(image, nose_row)
	var tail_width := _alpha_width_on_row(image, tail_row)
	_expect(nose_width > 0, "Aircraft 1 nose is visible near the top of the icon")
	_expect(tail_width > nose_width * 2, "Aircraft 1 is oriented nose-up rather than tail-up")


func _alpha_bounds(image: Image) -> Rect2:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	var found := false
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.01:
				continue
			var point := Vector2(x, y)
			min_point = min_point.min(point)
			max_point = max_point.max(point)
			found = true
	if not found:
		return Rect2()
	return Rect2(min_point, max_point - min_point + Vector2.ONE)


func _alpha_width_on_row(image: Image, y: int) -> int:
	var min_x := image.get_width()
	var max_x := -1
	for x in range(image.get_width()):
		if image.get_pixel(x, y).a > 0.05:
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
	return max_x - min_x + 1 if max_x >= min_x else 0


func _count_fill_and_outline_pixels(image: Image) -> Dictionary:
	var fill_count := 0
	var outline_count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.9:
				continue
			var luminance := (color.r + color.g + color.b) / 3.0
			if luminance > 0.7:
				fill_count += 1
			elif luminance < 0.25:
				outline_count += 1
	return {"fill": fill_count, "outline": outline_count}


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("[AircraftOutlineRendererSmoketest] FAIL: %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("[AircraftOutlineRendererSmoketest] PASS")
		get_tree().quit(0)
		return
	print("[AircraftOutlineRendererSmoketest] %d failure(s)" % _failures.size())
	get_tree().quit(1)
