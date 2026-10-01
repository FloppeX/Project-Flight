extends Button
var airframe_id := ""
var draggable := false

func _get_drag_data(_position: Vector2) -> Variant:
	if not draggable:
		return null
	var preview := Label.new()
	preview.text = "AIRCRAFT " + airframe_id.right(5).to_upper()
	preview.add_theme_color_override("font_color", Color("76c7c7"))
	set_drag_preview(preview)
	return {"airframe_id": airframe_id}
