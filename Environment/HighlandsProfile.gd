extends RefCounted
## Broad usable plateaus, with progressively rarer upper levels.
const REVISION := 27
const LEVEL_HEIGHT := 180.0


static func land_signal(main_signal: float, tributary_signal: float) -> float:
	return minf(main_signal, 0.09 + tributary_signal * 0.95)


static func regional_height(_x: float, _z: float, valley_height: float,
		main_signal: float, tributary_signal: float, district_noise: float) -> float:
	var land := land_signal(main_signal, tributary_signal)
	# Wide gaps between contours leave room for bases and vehicle manoeuvring.
	# Upper levels require both a wide landmass and favourable regional geology.
	var rise := smoothstep(0.20, 0.235, land)
	rise += smoothstep(0.34, 0.375, land)
	rise += smoothstep(0.43, 0.46, land) * smoothstep(-0.06, 0.02, district_noise)
	rise += smoothstep(0.55, 0.58, land) * smoothstep(0.03, 0.10, district_noise)
	return valley_height + rise * LEVEL_HEIGHT


static func floor_relief(x: float, z: float) -> float:
	return sin(x * 0.00043) * 14.0 + sin(z * 0.00031 + x * 0.00012) * 12.0


static func height(x: float, z: float, regional: float, _valley_height: float) -> float:
	return regional + floor_relief(x, z)
