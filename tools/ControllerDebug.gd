extends Node

# Attach this to any node and it will print controller inputs to help you map them
# Press F12 to toggle debug output

var debug_enabled = false

func _input(event):
	return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		debug_enabled = !debug_enabled
		print("Controller debug: ", "ENABLED" if debug_enabled else "DISABLED")

	if not debug_enabled:
		return

	if event is InputEventJoypadMotion:
		# Only print if the value is significant (not just noise)
		if abs(event.axis_value) > 0.1:
			print("Joypad Axis ", event.axis, " = ", event.axis_value)

	elif event is InputEventJoypadButton:
		if event.pressed:
			print("Joypad Button ", event.button_index, " pressed")
