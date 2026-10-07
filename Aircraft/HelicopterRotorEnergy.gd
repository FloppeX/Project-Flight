extends RefCounted
## Normalized rotor kinetic energy. Collective remains controllable after engine loss.
var rpm := 0.0
var collective := 0.0
var drive := 0.0
var autorotating := false

func step(delta: float, command: float, running: bool, engine_health: float,
		rotor_health: float, inflow: float, supported: bool, unfolded: bool) -> void:
	collective = move_toward(collective, clampf(command, 0.0, 1.0), delta * 1.8)
	drive = (0.2 + 0.8 * engine_health) if running and engine_health > 0.0 else 0.0
	autorotating = drive == 0.0 and rpm > 0.12 and not supported
	if rotor_health <= 0.0 or not unfolded:
		rpm = 0.0
		drive = 0.0
		autorotating = false
		return
	if drive > 0.0:
		var governed := sqrt(minf(1.0, drive / maxf(collective, 0.56)))
		rpm = move_toward(rpm, governed, delta * (0.18 if rpm < governed else 0.5))
	elif supported:
		rpm = move_toward(rpm, 0.0, delta * 0.12)
	else:
		# Descent through a lightly loaded disc sustains energy. High collective
		# spends it during the landing flare; a stalled rotor cannot wind up for free.
		var wind_drive := minf(maxf(inflow, 0.0), 25.0) * 0.07 * pow(1.0-collective, 2.0)
		wind_drive *= smoothstep(0.12, 0.45, rpm) * rotor_health
		var load := (0.035 + 0.38 * collective * collective) * rpm
		rpm = sqrt(clampf(rpm * rpm + (wind_drive - load) * delta, 0.0, 1.21))

func lift_multiplier(hover_collective: float, ground_bonus: float, translational_bonus: float,
		maximum: float, rotor_health: float, inflow: float) -> float:
	var result := collective / maxf(hover_collective, 0.01) * rpm * rpm * ground_bonus * translational_bonus
	if autorotating:
		result += minf(maxf(inflow, 0.0), 20.0) ** 2 * 0.016 * rpm * rpm * (1.0-collective)
	var limit := maximum * drive if drive > 0.0 else maximum
	return clampf(result * rotor_health, 0.0, limit)
