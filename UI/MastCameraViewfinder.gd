extends Control

## Static optical framing aid, shared by the monitor feed and fullscreen camera.
## The open centre keeps small tracked contacts visible.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var scale_factor := size.y / 360.0
	var half_frame := Vector2(64.0, 42.0) * scale_factor
	var arm := 12.0 * scale_factor
	var segments: Array[Vector2] = []
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner := center + half_frame * Vector2(x, y)
			segments.append_array([corner + Vector2(-x * arm, 0), corner,
				corner, corner + Vector2(0, -y * arm)])
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		segments.append_array([center + direction * 5.0 * scale_factor,
			center + direction * 10.0 * scale_factor])
	var lines := PackedVector2Array(segments)
	# Scale the frame geometry, but keep the strokes fine at fullscreen sizes.
	var stroke_width := clampf(0.4 * scale_factor, 0.6, 1.2)
	draw_multiline(lines, Color(0.0, 0.06, 0.04, 0.45), stroke_width + 0.8, true)
	draw_multiline(lines, Color(0.65, 1.0, 0.8, 0.8), stroke_width, true)
