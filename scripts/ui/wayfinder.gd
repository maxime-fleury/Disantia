extends Control
## A mark at the edge of the screen pointing at the next place worth walking to.
##
## Nine sites stand in the world under nine pillars of light, and the light is the call —
## but only if you happen to be facing it, off a ridge, with the draw distance on your
## side. Standing in the bottom of a valley with a treeline in front of you, the world
## reads as empty, and *empty* is the one thing an open world cannot be. This is the
## missing half of the beacons: get close enough that the light is a real destination, or
## turn around and pick a different one.
##
## It points at exactly one thing — the nearest site you have not found — and it stops
## pointing once there is nothing left to find. That restraint is the design: a screen
## with six markers on it is a checklist, and a checklist is the opposite of exploring.
## The map answers "where am I and what is out there"; this answers the smaller, more
## urgent question of which way to walk *now*.
##
## Drawn onto the HUD rather than built as world geometry: the thing it has to do is stay
## at the edge of the screen, which is a statement about the screen and not about the
## world. Nothing here is a physics query or a node — it is a projection and a clamped
## point, recomputed each frame because both the player and the target move.

## How far from the screen edge the marker is held. Enough that the ring and the label
## under it are never half off-screen.
const EDGE_INSET := 58.0
const RING_RADIUS := 9.0
## Where the ring sits relative to the ground: a beacon's column is six metres tall, and
## pointing at its feet puts the mark under the terrain whenever the ground rises.
const AIM_HEIGHT := 2.6

## Colour, and the reason it is not one of the map's four. The map's palette is a
## vocabulary — cyan is safety, red is raiders, amber is the elder — and a mark that means
## "somewhere you have not been" is a different kind of statement, so it wears the pale
## light of the thing it is pointing at.
const COL_SIGHT := Color("ffeec2")

## Set by the HUD while a full-screen panel is open. The panels dim the world behind them,
## and a bright marker drawn over the dim is the one thing on screen that would not be
## part of the panel.
var suppressed: bool = false
@export var enabled: bool = true

var _landmarks: Node
var _player: Node3D
var _name: String = ""
var _metres: float = 0.0
var _point: Vector2 = Vector2.ZERO
var _offscreen: bool = false
var _active: bool = false


func _ready() -> void:
	name = "Wayfinder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchors *and* offsets. `set_anchors_preset` on its own keeps the control's current
	# rect — which, one line after being instantiated, is zero by zero — so the marker
	# would spend the rest of the session computing its edge at size 0 and clamping to
	# nothing. The offsets are what make it fill the layer it is drawn on.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(true)


func _process(_delta: float) -> void:
	_update()


## Everything the marker needs, recomputed rather than cached: the player walks, the
## camera swings and the last site gets found, and each of those changes the answer.
##
## Split out of `_draw` so the self-test can ask what it is pointing at without a frame
## having been rendered — a marker that only exists during drawing can only be checked by
## looking at the screen, which is exactly what is not available here.
func _update() -> void:
	_active = false
	if not enabled or suppressed:
		queue_redraw()
		return
	var landmarks: Node = _resolve_landmarks()
	var player: Node3D = _resolve_player()
	if landmarks == null or player == null or not landmarks.has_method("nearest_unfound"):
		queue_redraw()
		return
	var site: Dictionary = landmarks.call("nearest_unfound", player.global_position)
	if site.is_empty():
		queue_redraw()
		return

	var where: Vector3 = site["position"] as Vector3
	var world: Vector3 = where + Vector3(0.0, AIM_HEIGHT, 0.0)
	# The site's own distance, measured flat by the thing that chose it. Recomputing it from
	# here would be the same number twice and, on any axis but XZ, a different one.
	_metres = float(site.get("distance", 0.0))
	_name = String(site["name"])
	_active = true

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen: Vector2 = camera.unproject_position(world)
	# A point behind the camera projects to somewhere on the wrong side of the screen —
	# Godot does not fold it back — so it is reflected through the centre before being
	# clamped. Without this the marker flips sides as you turn past the target, which
	# reads as the game losing track of where it is pointing.
	_offscreen = camera.is_position_behind(world)
	if _offscreen:
		screen = size * 0.5 - (screen - size * 0.5)
	if size.x < EDGE_INSET * 2.0 or size.y < EDGE_INSET * 2.0:
		_point = screen
		_offscreen = false
	else:
		_point = Vector2(
			clampf(screen.x, EDGE_INSET, size.x - EDGE_INSET),
			clampf(screen.y, EDGE_INSET, size.y - EDGE_INSET)
		)
		_offscreen = _offscreen or not screen.is_equal_approx(_point)
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var font: Font = ThemeDB.fallback_font
	draw_arc(_point, RING_RADIUS, 0.0, TAU, 28, Color(COL_SIGHT, 0.85), 1.6, true)
	draw_circle(_point, 2.4, COL_SIGHT)
	# Off the edge of the screen, a ring says where the thing is but not that it is out of
	# sight; a wedge pointing outward says both at once.
	if _offscreen:
		var outward: Vector2 = (_point - size * 0.5)
		outward = Vector2(0.0, -1.0) if outward.length_squared() < 1.0 else outward.normalized()
		var side := Vector2(-outward.y, outward.x)
		draw_colored_polygon(PackedVector2Array([
			_point + outward * (RING_RADIUS + 7.0),
			_point + side * 5.0 + outward * RING_RADIUS,
			_point - side * 5.0 + outward * RING_RADIUS,
		]), Color(COL_SIGHT, 0.9))

	# The reading itself, under the ring: how far and which one. Both, because a distance
	# with no name is a number and a name with no distance is a guess about how far a
	# walk it is — and the walk is the decision the player is making.
	var text: String = "%s   %s m" % [_name, _metres_text()]
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var at := Vector2(_point.x - width * 0.5, _point.y + 26.0)
	at.x = clampf(at.x, 4.0, maxf(4.0, size.x - width - 4.0))
	at.y = clampf(at.y, 14.0, maxf(14.0, size.y - 6.0))
	# A plate under the reading. The mark is held in from the edge of the screen, which is
	# exactly where this HUD's own panels live, so it will cross one sooner or later — and
	# a distance printed over the event log is a distance nobody can read.
	var plate := Rect2(at - Vector2(5.0, 12.0), Vector2(width + 10.0, 18.0))
	draw_rect(plate, Color(0.03, 0.04, 0.06, 0.74), true)
	draw_rect(plate, Color(COL_SIGHT, 0.30), false, 1.0)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(COL_SIGHT, 0.95))


## Distance, rounded to something a person would say out loud. Metres under a kilometre —
## the whole world is 320 of them — and kilometres above it, for the day the map grows.
func _metres_text() -> String:
	if _metres >= 1000.0:
		return "%.1fkm" % (_metres / 1000.0)
	return str(int(round(_metres)))


func _resolve_landmarks() -> Node:
	if _landmarks != null and is_instance_valid(_landmarks):
		return _landmarks
	_landmarks = get_tree().root.get_node_or_null("Main/Landmarks")
	if _landmarks == null:
		_landmarks = get_tree().get_first_node_in_group("landmarks")
	return _landmarks


func _resolve_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


# ------------------------------------------------------------------------ queries

## True while it is pointing at something. False once every site is found, which is the
## end of the tutorial this marker quietly is.
func active() -> bool:
	return _active


func target_name() -> String:
	return _name


func target_metres() -> float:
	return _metres


## Where the mark ended up, inside the screen. Public because "the marker stays on screen"
## is the property that a projection bug breaks, and it cannot be seen from the numbers
## the marker was built from.
func marker_point() -> Vector2:
	return _point


func text() -> String:
	return "%s   %s m" % [_name, _metres_text()]
