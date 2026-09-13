extends RefCounted
## Authored events, not a physics replay. Equal-time events keep file order.
var events: Array[Dictionary] = []
var cursor := 0
var elapsed := 0.0
var error := ""

func configure(data: Variant) -> bool:
	events.clear()
	cursor = 0
	elapsed = 0.0
	error = ""
	if not data is Dictionary or int(data.get("version", 0)) != 1 or not data.get("events") is Array:
		return _fail("Expected version 1 and an events array")
	var ids := {}
	var previous_time := -1.0
	for entry in data.events:
		if not entry is Dictionary:
			return _fail("Each event must be an object")
		var id := str(entry.get("id", ""))
		if not _number(entry.get("time")):
			return _fail("Event time must be a finite number")
		var time := float(entry.get("time", -1.0))
		if id.is_empty() or ids.has(id) or not is_finite(time) or time < 0.0 or time < previous_time:
			return _fail("Events need unique ids and nonnegative times in ascending order")
		ids[id] = true
		previous_time = time
		var action := str(entry.get("action", ""))
		if action not in ["cue", "spawn", "launch"]:
			return _fail("Unknown action: %s" % action)
		if action == "spawn":
			if str(entry.get("kind", "")) not in ["aircraft", "ground"] or str(entry.get("scene", "")).is_empty():
				return _fail("Spawn needs kind aircraft/ground and scene")
			if not _valid_vector(entry.get("position")):
				return _fail("Spawn position needs three finite numbers")
			if not _number(entry.get("team")) or float(entry.team) not in [1.0, 2.0]:
				return _fail("Team must be 1 (friendly) or 2 (enemy)")
			if not _number(entry.get("heading_deg", 0)) or not _number(entry.get("speed_mps", 0)) or float(entry.get("speed_mps", 0)) < 0:
				return _fail("Heading and nonnegative speed must be finite")
		if action == "launch":
			if not _number(entry.get("count")) or float(entry.count) != floorf(float(entry.count)) or int(entry.count) < 1 or int(entry.count) > 6:
				return _fail("Launch count must be an integer from 1 to 6")
		events.append(entry.duplicate(true))
	return true

func advance(delta: float) -> Array[Dictionary]:
	elapsed += maxf(delta, 0.0)
	var due: Array[Dictionary] = []
	while cursor < events.size() and float(events[cursor].time) <= elapsed:
		due.append(events[cursor])
		cursor += 1
	return due

func _valid_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)): return false
	return true

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _fail(message: String) -> bool:
	error = message
	events.clear()
	return false
