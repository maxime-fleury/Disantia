extends Node3D
## Orbiting third-person camera.
##
## Yaw lives on this node and pitch on the SpringArm3D below it. That split is
## deliberate: the player controller reads this node's global basis to turn WASD
## into camera-relative movement, and doing so stays correct only while this
## node holds no pitch of its own.
##
## Pointer lock needs a user gesture, which the browser will not grant on load,
## so the web build starts unlocked and locks on the first click. A translucent
## hint in the HUD says so.

@export var sensitivity: float = 0.0022
@export var pitch_min: float = -1.15
@export var pitch_max: float = 0.55
@export var start_pitch: float = -0.28
@export var start_distance: float = 6.0
@export var zoom_min: float = 2.2
@export var zoom_max: float = 13.0
@export var zoom_step: float = 0.7
@export var invert_y: bool = false
## Seconds for the arm to settle after a zoom step.
@export var zoom_smoothing: float = 12.0
## How fast the camera's *height* catches up with the body's. The rig is a child of the body, so
## without this the whole valley is thrown up and down the screen on every jump — the body moves
## a metre and the camera moves a metre with it on the same frame, which reads as the ground
## jumping rather than the player. One is a step; this makes it a spring.
@export var height_smoothing: float = 7.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _distance: float = 6.0
## The camera's own idea of how high it is, in world space. The rig's local y is set to
## `_smoothed_y - body_y` every frame, which is what keeps this node a child of the body while
## the height it sits at lags behind it.
var _smoothed_y: float = 0.0
var _have_y: bool = false

@onready var _arm: SpringArm3D = get_node_or_null("SpringArm3D")


func _ready() -> void:
	_pitch = start_pitch
	_distance = start_distance
	if _arm != null:
		_arm.spring_length = _distance
	_apply_rotation()
	# Locking the pointer during load is silently refused by browsers, so the web
	# build waits for a click instead.
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		_yaw -= motion.relative.x * sensitivity
		var dy: float = motion.relative.y * sensitivity
		_pitch = clampf(_pitch + (dy if invert_y else -dy), pitch_min, pitch_max)
		_apply_rotation()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _handle_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if button.pressed:
				_zoom(-zoom_step)
		MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				_zoom(zoom_step)
		MOUSE_BUTTON_LEFT:
			if button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _arm == null:
		return
	# Smooth the spring arm so wheel steps do not snap.
	_arm.spring_length = lerpf(
		_arm.spring_length, _distance, clampf(zoom_smoothing * delta, 0.0, 1.0)
	)
	_follow_height(delta)


## Trails the body's height rather than being welded to it.
##
## A ring of ground, a jump and a fall are the three times the body moves fast in this game, and
## in all three the camera should stay still while the *player* moves — which is what a person
## looking at a third-person game reads as the character jumping rather than the world. The lag
## is small on purpose: a metre and a half of smoothing would feel like the camera is drunk, and
## a tenth of a metre is enough to take the snap out.
func _follow_height(delta: float) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var world_y: float = body.global_position.y
	if not _have_y:
		_smoothed_y = world_y
		_have_y = true
	_smoothed_y = lerpf(_smoothed_y, world_y, clampf(height_smoothing * delta, 0.0, 1.0))
	# The body is at the feet and the arm hangs 1.5 m above them; this only ever *subtracts* the
	# part of the body's climb the camera has not caught up with yet.
	position.y = _smoothed_y - world_y


## Drops the smoothing, for a teleport. A warp puts the body somewhere else in one frame, and a
## camera that then flew across the valley to catch up would be worse than a cut.
func snap_height() -> void:
	_have_y = false


func _zoom(amount: float) -> void:
	_distance = clampf(_distance + amount, zoom_min, zoom_max)


func _apply_rotation() -> void:
	rotation.y = _yaw
	if _arm != null:
		_arm.rotation.x = _pitch


func yaw() -> float:
	return _yaw


func set_yaw(value: float) -> void:
	_yaw = value
	_apply_rotation()


func set_pitch(value: float) -> void:
	_pitch = clampf(value, pitch_min, pitch_max)
	_apply_rotation()


func is_pointer_locked() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
