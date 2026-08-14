extends RefCounted

## Tactical-map texture generation. Relief explains the terrain shape; the
## mobility mask exposes the same clearance classes used by NavGraph.

const VECTOR_VOID_COLOR: Color = Color("0e0e0e")
const IMPASSABLE_HEIGHT: float = -1e6
const RELIEF_LOW_COLOR: Color = Color("14181b")
const RELIEF_MID_COLOR: Color = Color("2b2d2b")
const RELIEF_HIGH_COLOR: Color = Color("605e55")
const RELIEF_CLIFF_COLOR: Color = Color("111315")
const CONTOUR_COLOR: Color = Color("92978f")

const VEHICLE_CLEARANCE_M: float = 60.0
const CARRIER_CLEARANCE_M: float = 120.0
## The 50 km navigation grid is 1251 px wide, while the tactical map is shown
## at roughly 600-900 px. Rendering near display resolution avoids a multi-
## second first-open stall without changing the full-resolution path data.
const MAX_RENDER_DIMENSION: int = 720
const MOBILITY_INTERIOR_MASK: int = 92
const MOBILITY_EDGE_MASK: int = 224
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
]

enum MobilityClass {
	BLOCKED,
	VEHICLE,
	CARRIER,
}


static func build_texture() -> ImageTexture:
	var textures := build_textures()
	return textures.get("relief") as ImageTexture


static func build_image() -> Image:
	var images := build_images()
	return images.get("relief") as Image


static func build_textures() -> Dictionary:
	var images := build_images()
	if images.is_empty():
		return {}
	var relief_image := images.get("relief") as Image
	var mobility_image := images.get("mobility") as Image
	if relief_image == null or mobility_image == null:
		return {}
	return {
		"relief": ImageTexture.create_from_image(relief_image),
		"mobility": ImageTexture.create_from_image(mobility_image),
		"height_min": float(images.get("height_min", 0.0)),
		"height_max": float(images.get("height_max", 0.0)),
		"contour_interval_m": float(images.get("contour_interval_m", 0.0)),
		"vehicle_cells": int(images.get("vehicle_cells", 0)),
		"carrier_cells": int(images.get("carrier_cells", 0)),
	}


static func build_images() -> Dictionary:
	var terrain_nav := _get_autoload("TerrainNavGrid")
	var nav_graph := _get_autoload("NavGraph")
	if terrain_nav == null or nav_graph == null:
		return {}
	if not bool(terrain_nav.call("is_ready")) or not bool(nav_graph.call("is_ready")):
		return {}
	var cols: int = int(terrain_nav.get("_cols"))
	var rows: int = int(terrain_nav.get("_rows"))
	var heights: PackedFloat32Array = terrain_nav.get("_heights")
	var clearance: PackedFloat32Array = nav_graph.get("_cl_map")
	var cell_size := float(terrain_nav.get("cell_size_m"))
	var render_data := _downsample_for_display(heights, clearance, cols, rows, cell_size)
	var render_heights: PackedFloat32Array = render_data.get("heights", PackedFloat32Array())
	var render_clearance: PackedFloat32Array = render_data.get("clearance", PackedFloat32Array())
	var render_cols := int(render_data.get("cols", cols))
	var render_rows := int(render_data.get("rows", rows))
	var render_cell_size := float(render_data.get("cell_size_m", cell_size))
	var layers := build_images_from_data(
		render_heights,
		render_clearance,
		render_cols,
		render_rows,
		render_cell_size,
		IMPASSABLE_HEIGHT
	)
	layers["source_cols"] = cols
	layers["source_rows"] = rows
	layers["render_cols"] = render_cols
	layers["render_rows"] = render_rows
	return layers


static func build_images_from_data(
		heights: PackedFloat32Array,
		clearance: PackedFloat32Array,
		cols: int,
		rows: int,
		cell_size_m: float,
		impassable_height: float = -1e6) -> Dictionary:
	var pixel_count := cols * rows
	if cols <= 1 or rows <= 1 or heights.size() != pixel_count or clearance.size() != pixel_count:
		return {}

	var min_height := INF
	var max_height := -INF
	for height in heights:
		if _is_passable_height(height, impassable_height):
			min_height = minf(min_height, height)
			max_height = maxf(max_height, height)
	if not is_finite(min_height) or not is_finite(max_height):
		return {}

	var height_span := maxf(max_height - min_height, 1.0)
	var contour_interval := _choose_contour_interval(height_span)
	var relief_data := PackedByteArray()
	var mobility_data := PackedByteArray()
	relief_data.resize(pixel_count * 4)
	mobility_data.resize(pixel_count * 4)
	var cell_size := maxf(cell_size_m, 1.0)
	var light := Vector3(-0.44, 0.78, -0.45).normalized()
	var vehicle_cells := 0
	var carrier_cells := 0

	for gz in range(rows):
		for gx in range(cols):
			var idx := gz * cols + gx
			var byte_idx := idx * 4
			var height: float = heights[idx]
			var relief_color := VECTOR_VOID_COLOR
			if _is_passable_height(height, impassable_height):
				var left_h := _valid_neighbour_height(heights, gx - 1, gz, cols, rows, height, impassable_height)
				var right_h := _valid_neighbour_height(heights, gx + 1, gz, cols, rows, height, impassable_height)
				var up_h := _valid_neighbour_height(heights, gx, gz - 1, cols, rows, height, impassable_height)
				var down_h := _valid_neighbour_height(heights, gx, gz + 1, cols, rows, height, impassable_height)
				var slope_x := (right_h - left_h) / (cell_size * 2.0)
				var slope_z := (down_h - up_h) / (cell_size * 2.0)
				var normal_inv_length := 1.0 / sqrt(slope_x * slope_x + slope_z * slope_z + 1.0)
				var hill_light := clampf(
					(-slope_x * light.x + light.y - slope_z * light.z) * normal_inv_length,
					0.0,
					1.0
				)
				var elevation_t := _smoothstep(0.0, 1.0, (height - min_height) / height_span)
				relief_color = _relief_color(elevation_t)
				var grade_degrees := rad_to_deg(atan(sqrt(slope_x * slope_x + slope_z * slope_z)))
				var cliff_t := _smoothstep(20.0, 42.0, grade_degrees)
				relief_color = relief_color.lerp(RELIEF_CLIFF_COLOR, cliff_t * 0.52)
				var brightness := lerpf(0.76, 1.16, hill_light)
				relief_color = Color(
					clampf(relief_color.r * brightness, 0.0, 1.0),
					clampf(relief_color.g * brightness, 0.0, 1.0),
					clampf(relief_color.b * brightness, 0.0, 1.0),
					1.0
				)
				var contour_index := int(floor(height / contour_interval))
				var contour_crossing := (
					int(floor(right_h / contour_interval)) != contour_index
					or int(floor(down_h / contour_interval)) != contour_index
				)
				if contour_crossing:
					var major_contour := posmod(contour_index, 4) == 0
					relief_color = relief_color.lerp(CONTOUR_COLOR, 0.40 if major_contour else 0.20)
			_write_color(relief_data, byte_idx, relief_color)

			var mobility_class := mobility_class_for_clearance(clearance[idx])
			var vehicle_mask := 0
			var carrier_mask := 0
			if mobility_class == MobilityClass.VEHICLE:
				vehicle_cells += 1
				vehicle_mask = MOBILITY_EDGE_MASK if _is_clearance_boundary(
					clearance, gx, gz, cols, rows, VEHICLE_CLEARANCE_M
				) else MOBILITY_INTERIOR_MASK
			elif mobility_class == MobilityClass.CARRIER:
				carrier_cells += 1
				carrier_mask = MOBILITY_EDGE_MASK if _is_clearance_boundary(
					clearance, gx, gz, cols, rows, CARRIER_CLEARANCE_M
				) else MOBILITY_INTERIOR_MASK
			mobility_data[byte_idx] = vehicle_mask
			mobility_data[byte_idx + 1] = carrier_mask
			mobility_data[byte_idx + 2] = 0
			mobility_data[byte_idx + 3] = 255

	return {
		"relief": Image.create_from_data(cols, rows, false, Image.FORMAT_RGBA8, relief_data),
		"mobility": Image.create_from_data(cols, rows, false, Image.FORMAT_RGBA8, mobility_data),
		"height_min": min_height,
		"height_max": max_height,
		"contour_interval_m": contour_interval,
		"vehicle_cells": vehicle_cells,
		"carrier_cells": carrier_cells,
	}


static func sample_world_mobility_class(world_x: float, world_z: float) -> MobilityClass:
	var terrain_nav := _get_autoload("TerrainNavGrid")
	var nav_graph := _get_autoload("NavGraph")
	if terrain_nav == null or nav_graph == null:
		return MobilityClass.BLOCKED
	if not bool(terrain_nav.call("is_ready")) or not bool(nav_graph.call("is_ready")):
		return MobilityClass.BLOCKED
	var cell_size := maxf(float(terrain_nav.get("cell_size_m")), 1.0)
	var origin_x := float(terrain_nav.get("_origin_x"))
	var origin_z := float(terrain_nav.get("_origin_z"))
	var cols := int(terrain_nav.get("_cols"))
	var rows := int(terrain_nav.get("_rows"))
	var gx := int(floor((world_x - origin_x) / cell_size))
	var gz := int(floor((world_z - origin_z) / cell_size))
	if gx < 0 or gx >= cols or gz < 0 or gz >= rows:
		return MobilityClass.BLOCKED
	var clearance: PackedFloat32Array = nav_graph.get("_cl_map")
	var idx := gz * cols + gx
	if idx < 0 or idx >= clearance.size():
		return MobilityClass.BLOCKED
	return mobility_class_for_clearance(clearance[idx])


static func mobility_class_for_clearance(clearance_m: float) -> MobilityClass:
	if clearance_m >= CARRIER_CLEARANCE_M:
		return MobilityClass.CARRIER
	if clearance_m >= VEHICLE_CLEARANCE_M:
		return MobilityClass.VEHICLE
	return MobilityClass.BLOCKED


static func mobility_class_label(mobility_class: MobilityClass) -> String:
	match mobility_class:
		MobilityClass.CARRIER:
			return "CARRIER CORRIDOR"
		MobilityClass.VEHICLE:
			return "VEHICLE CORRIDOR"
		_:
			return "GROUND ROUTE BLOCKED"


static func _relief_color(elevation_t: float) -> Color:
	if elevation_t < 0.56:
		return RELIEF_LOW_COLOR.lerp(RELIEF_MID_COLOR, elevation_t / 0.56)
	return RELIEF_MID_COLOR.lerp(RELIEF_HIGH_COLOR, (elevation_t - 0.56) / 0.44)


static func _choose_contour_interval(height_span: float) -> float:
	var target := maxf(height_span / 12.0, 1.0)
	for interval in [5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0]:
		if interval >= target:
			return interval
	return 2000.0


static func _valid_neighbour_height(
		heights: PackedFloat32Array,
		gx: int,
		gz: int,
		cols: int,
		rows: int,
		fallback: float,
		impassable_height: float) -> float:
	if gx < 0 or gx >= cols or gz < 0 or gz >= rows:
		return fallback
	var height: float = heights[gz * cols + gx]
	return height if _is_passable_height(height, impassable_height) else fallback


static func _is_clearance_boundary(
		clearance: PackedFloat32Array,
		gx: int,
		gz: int,
		cols: int,
		rows: int,
		threshold_m: float) -> bool:
	for offset in CARDINAL_OFFSETS:
		var nx := gx + offset.x
		var nz := gz + offset.y
		if nx < 0 or nx >= cols or nz < 0 or nz >= rows:
			return true
		if clearance[nz * cols + nx] < threshold_m:
			return true
	return false


static func _is_passable_height(height: float, impassable_height: float) -> bool:
	return is_finite(height) and height > impassable_height * 0.5


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / maxf(edge1 - edge0, 0.00001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _write_color(data: PackedByteArray, byte_idx: int, color: Color) -> void:
	data[byte_idx] = int(round(clampf(color.r, 0.0, 1.0) * 255.0))
	data[byte_idx + 1] = int(round(clampf(color.g, 0.0, 1.0) * 255.0))
	data[byte_idx + 2] = int(round(clampf(color.b, 0.0, 1.0) * 255.0))
	data[byte_idx + 3] = int(round(clampf(color.a, 0.0, 1.0) * 255.0))


static func _downsample_for_display(
		heights: PackedFloat32Array,
		clearance: PackedFloat32Array,
		cols: int,
		rows: int,
		cell_size_m: float) -> Dictionary:
	var stride := maxi(1, int(ceil(float(maxi(cols, rows)) / float(MAX_RENDER_DIMENSION))))
	if stride == 1:
		return {
			"heights": heights,
			"clearance": clearance,
			"cols": cols,
			"rows": rows,
			"cell_size_m": cell_size_m,
		}
	var render_cols := int(ceil(float(cols) / float(stride)))
	var render_rows := int(ceil(float(rows) / float(stride)))
	var render_heights := PackedFloat32Array()
	var render_clearance := PackedFloat32Array()
	render_heights.resize(render_cols * render_rows)
	render_clearance.resize(render_cols * render_rows)
	for render_z in range(render_rows):
		for render_x in range(render_cols):
			var source_x0 := render_x * stride
			var source_z0 := render_z * stride
			var source_x1 := mini(source_x0 + stride, cols)
			var source_z1 := mini(source_z0 + stride, rows)
			var center_x := mini(source_x0 + int(stride / 2), cols - 1)
			var center_z := mini(source_z0 + int(stride / 2), rows - 1)
			var render_idx := render_z * render_cols + render_x
			render_heights[render_idx] = heights[center_z * cols + center_x]
			# Preserve narrow legal corridors at overview scale. This affects only
			# raster visibility; hover and path orders still query the source graph.
			var block_max_clearance := 0.0
			for source_z in range(source_z0, source_z1):
				for source_x in range(source_x0, source_x1):
					block_max_clearance = maxf(
						block_max_clearance,
						clearance[source_z * cols + source_x]
					)
			render_clearance[render_idx] = block_max_clearance
	return {
		"heights": render_heights,
		"clearance": render_clearance,
		"cols": render_cols,
		"rows": render_rows,
		"cell_size_m": cell_size_m * float(stride),
	}


static func _get_autoload(autoload_name: String) -> Node:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return null
	return scene_tree.root.get_node_or_null(autoload_name)
