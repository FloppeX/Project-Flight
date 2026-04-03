extends RefCounted

const VECTOR_VOID_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
const VECTOR_LOW_COLOR: Color = Color(0.03, 0.10, 0.05, 1.0)
const VECTOR_RAISED_COLOR: Color = Color(0.10, 0.28, 0.11, 1.0)
const VECTOR_HIGH_COLOR: Color = Color(0.20, 0.48, 0.21, 1.0)

static func build_texture() -> ImageTexture:
	var img := build_image()
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

static func build_image() -> Image:
	if not TerrainNavGrid.is_ready():
		return null
	var cols: int = TerrainNavGrid._cols
	var rows: int = TerrainNavGrid._rows
	if cols <= 1 or rows <= 1:
		return null
	var h_ceil: float = TerrainNavGrid._h_min_passable + TerrainNavGrid.low_level_tolerance_m
	var max_slope_m: float = NavGraph.max_slope_m if NavGraph != null else 18.0
	var raised_threshold_y: float = h_ceil + maxf(max_slope_m * 1.5, 24.0)
	var high_threshold_y: float = raised_threshold_y + maxf(max_slope_m * 3.0, 45.0)
	var img := Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	for gz in range(rows):
		for gx in range(cols):
			var idx: int = gz * cols + gx
			var h: float = TerrainNavGrid._heights[idx]
			var color: Color = VECTOR_VOID_COLOR
			if h > TerrainNavGrid.IMPASSABLE * 0.5:
				color = VECTOR_LOW_COLOR
				if h >= high_threshold_y:
					color = VECTOR_HIGH_COLOR
				elif h >= raised_threshold_y:
					color = VECTOR_RAISED_COLOR
			img.set_pixel(gx, gz, color)
	return img
