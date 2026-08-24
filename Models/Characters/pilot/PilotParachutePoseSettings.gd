class_name PilotParachutePoseSettings
extends Resource
## Editable local-space rotation offsets applied after the raw Mixamo parachute
## frame is sampled. Keeping the defaults at zero preserves the source clip.

@export_group("Left Arm")
@export var left_shoulder_degrees: Vector3 = Vector3.ZERO
@export var left_upper_arm_degrees: Vector3 = Vector3.ZERO
@export var left_forearm_degrees: Vector3 = Vector3.ZERO
@export var left_hand_degrees: Vector3 = Vector3.ZERO

@export_group("Right Arm")
@export var right_shoulder_degrees: Vector3 = Vector3.ZERO
@export var right_upper_arm_degrees: Vector3 = Vector3.ZERO
@export var right_forearm_degrees: Vector3 = Vector3.ZERO
@export var right_hand_degrees: Vector3 = Vector3.ZERO

@export_group("Hands")
## Zero retains the animation's grip; one blends the animated thumb and index
## bones fully back to their authored rest rotations.
@export_range(0.0, 1.0, 0.01) var grip_relaxation: float = 0.0


func reset_to_raw_clip() -> void:
	left_shoulder_degrees = Vector3.ZERO
	left_upper_arm_degrees = Vector3.ZERO
	left_forearm_degrees = Vector3.ZERO
	left_hand_degrees = Vector3.ZERO
	right_shoulder_degrees = Vector3.ZERO
	right_upper_arm_degrees = Vector3.ZERO
	right_forearm_degrees = Vector3.ZERO
	right_hand_degrees = Vector3.ZERO
	grip_relaxation = 0.0
