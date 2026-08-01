class_name FlightPlan
extends RefCounted

const AirTaskModel: Script = preload("res://AI/AirTask.gd")

## Tactical path produced for an AirTask and consumed by the shared path follower.
##
## Positions are full world-space Vector3 points. Altitude is therefore part of the
## path geometry rather than a separate lateral-controller mode. Per-leg metadata
## describes speed, tactical role and optional straight/arc geometry without exposing
## mission decisions or aircraft control inputs to the follower.

var plan_name: String = ""
var legs: Array[Dictionary] = []
var follow_carrier: bool = false
var loop: bool = false
var capture_radius_m: float = -1.0
var source_task_kind: int = AirTaskModel.Kind.NONE
var metadata: Dictionary = {}


static func from_legs(
	name: String,
	source_legs: Array,
	follows_carrier: bool = false,
	loops: bool = false,
	default_capture_radius_m: float = -1.0
) -> FlightPlan:
	var plan := FlightPlan.new()
	plan.plan_name = name
	plan.follow_carrier = follows_carrier
	plan.loop = loops
	plan.capture_radius_m = default_capture_radius_m
	for leg_variant in source_legs:
		if leg_variant is Dictionary:
			plan.legs.append((leg_variant as Dictionary).duplicate(true))
		elif leg_variant is Vector3:
			plan.legs.append({"position": leg_variant})
	return plan


func is_empty() -> bool:
	return legs.is_empty()


func duplicate_plan() -> FlightPlan:
	var copy := FlightPlan.from_legs(
		plan_name,
		legs,
		follow_carrier,
		loop,
		capture_radius_m
	)
	copy.source_task_kind = source_task_kind
	copy.metadata = metadata.duplicate(true)
	return copy


func get_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for leg: Dictionary in legs:
		var position: Variant = leg.get("position", leg.get("waypoint", Vector3.INF))
		if position is Vector3:
			positions.append(position)
	return positions


func describe() -> String:
	return "%s legs=%d loop=%s carrier_relative=%s" % [
		plan_name,
		legs.size(),
		str(loop),
		str(follow_carrier),
	]
