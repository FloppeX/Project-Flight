extends Control
## The MFD supplies its current aircraft on every update, including pooled panels.
var source_mfd: Node
var _state: Dictionary = {}
var _timer := 0.0
const REGIONS := {
	"fuselage": [Vector2(.43,.30),Vector2(.57,.30),Vector2(.56,.72),Vector2(.44,.72)],
	"cockpit": [Vector2(.44,.23),Vector2(.50,.18),Vector2(.56,.23),Vector2(.56,.36),Vector2(.44,.36)],
	"engine": [Vector2(.50,.03),Vector2(.55,.12),Vector2(.55,.22),Vector2(.45,.22),Vector2(.45,.12)],
	"left_wing": [Vector2(.43,.39),Vector2(.07,.54),Vector2(.07,.65),Vector2(.44,.55)],
	"right_wing": [Vector2(.57,.39),Vector2(.93,.54),Vector2(.93,.65),Vector2(.56,.55)],
	"tail": [Vector2(.45,.70),Vector2(.24,.82),Vector2(.24,.90),Vector2(.48,.84),Vector2(.50,.94),Vector2(.52,.84),Vector2(.76,.90),Vector2(.76,.82),Vector2(.55,.70)],
}

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_timer += delta
	if _timer < 0.1: return
	_timer = 0.0
	_state = {}
	if is_instance_valid(source_mfd) and is_instance_valid(source_mfd.aircraft):
		var model := source_mfd.aircraft.get_node_or_null("PartDamageModel") as AircraftPartDamageModel
		if model != null and is_instance_valid(model.systems):
			_state = model.systems.get_display_state()
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var font_size := clampi(int(size.x / 20.0), 9, 17)
	var diagram_size := Vector2(size.x, maxf(size.y * 0.67 - 14.0, 20.0))
	var origin := Vector2(0,16)
	if _state.is_empty():
		draw_string(font,Vector2(8,size.y*.5),"NO REGIONAL DATA",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color(.6,.8,.7))
		return
	var regions: Dictionary = _helicopter_regions() if _state.get("helicopter",false) else REGIONS
	if _state.get("helicopter",false):
		var rpm := float(_state.get("rotor_rpm",0.0))
		draw_string(font,Vector2(5,12),"ROTOR %d%%  %s" % [roundi(rpm*100),"AUTO" if _state.get("autorotating",false) else ""],HORIZONTAL_ALIGNMENT_LEFT,size.x-10,font_size,Color(1,.65,.13) if rpm<.75 else Color(.9,1,.92))
	for zone: String in regions:
		var points := PackedVector2Array()
		for point: Vector2 in regions[zone]: points.append(origin + point * diagram_size)
		var entry: Dictionary = _state.zones.get(zone,{})
		var health := float(entry.get("fraction",1.0))
		var destroyed := bool(entry.get("destroyed",false))
		var color := Color(.19,.40,.34)
		if health < .99: color = Color(1,.65,.13)
		if health < .3: color = Color(1,.20,.12)
		draw_colored_polygon(points,Color(color,.18 if not destroyed else .08))
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline,color,1.5,true)
		if destroyed:
			var box := Rect2(points[0],Vector2.ZERO)
			for point in points: box = box.expand(point)
			draw_line(box.position,box.end,color,2,true)
			draw_line(Vector2(box.end.x,box.position.y),Vector2(box.position.x,box.end.y),color,2,true)
	var warnings: PackedStringArray = _state.warnings
	var y := size.y * .70
	if warnings.is_empty(): warnings = PackedStringArray(["ALL AREAS INTACT"])
	# Rotate additional warnings as a group; none are silently discarded.
	var page := int(Time.get_ticks_msec() / 3500) % maxi(1,ceili(warnings.size()/3.0))
	for i in range(page*3,mini(page*3+3,warnings.size())):
		draw_string(font,Vector2(5,y),warnings[i],HORIZONTAL_ALIGNMENT_LEFT,size.x-10,font_size,Color(.9,1,.92))
		y += font_size + 4

func _helicopter_regions() -> Dictionary:
	var regions := {}
	regions["main_rotor"] = _circle(Vector2(.5,.38),Vector2(.42,.32))
	if _state.get("coaxial",false):
		regions["lower_rotor"] = _circle(Vector2(.5,.38),Vector2(.33,.24))
	regions["tail"] = [Vector2(.46,.51),Vector2(.54,.51),Vector2(.53,.83),Vector2(.69,.87),Vector2(.69,.91),Vector2(.5,.88),Vector2(.31,.91),Vector2(.31,.87),Vector2(.47,.83)]
	if not _state.get("coaxial",false):
		regions["tail_rotor"] = _circle(Vector2(.53,.87),Vector2(.12,.10))
	regions["fuselage"] = [Vector2(.4,.26),Vector2(.6,.26),Vector2(.59,.49),Vector2(.54,.61),Vector2(.46,.61),Vector2(.41,.49)]
	regions["cockpit"] = [Vector2(.4,.26),Vector2(.43,.17),Vector2(.5,.13),Vector2(.57,.17),Vector2(.6,.26)]
	regions["engine"] = [Vector2(.44,.37),Vector2(.56,.37),Vector2(.56,.48),Vector2(.44,.48)]
	return regions

func _circle(centre: Vector2, radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 40: points.append(centre+Vector2.from_angle(TAU*i/40.0)*radius)
	return points
