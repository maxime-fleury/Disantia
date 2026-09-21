extends Control
## The minimap: the ground, the roads, the spirit zones, the raider camps and you.
##
## It answers the one question a procedural world makes hard to answer — *where am I,
## and which way is the thing I am looking for* — and it answers it from the same data
## the world is built from rather than from a hand-drawn picture that could drift.
##
## The ground itself is baked once by the terrain (`map_image`) and drawn as a texture.
## Everything that can move or unlock is drawn on top each redraw: that split is what
## keeps this cheap enough to sit in a redraw loop, because the expensive half of the
## work is a still image.
##
## North is up. The world's -Z is north, so world Z maps straight onto screen Y and no
## rotation is involved anywhere — which is also why the map does not spin when the
## camera does. A rotating map is prettier and worse: the one thing a map is for is
## knowing which way the camp is, and a map that turns under you cannot be read at a
## glance.

## World layers, resolved once. Anything missing is simply not drawn, so the minimap
## degrades to a terrain picture instead of erroring if a node is absent.
var _terrain: Node
var _zones: Node
var _camps: Node
var _safe: Node3D
var _player: Node3D
var _elder: Node3D

## Colours, in one place so the map and its legend agree.
##
## Translucent, all of it. An opaque square in the corner of the screen hides the world
## behind it — including the part the player is standing in — and reads as a framed
## picture rather than as a map you are on. The ground shows through at a bit under
## three quarters, which is enough to place the map against the landscape while still
## being readable over it.
const OVERLAY_ALPHA := 0.42
const GROUND_ALPHA := 0.74
const COL_BACKDROP := Color(0.04, 0.05, 0.07, OVERLAY_ALPHA)
const COL_SAFE := Color("8fe3ff")
const COL_CAMP := Color("ff6b5a")
const COL_PLAYER := Color("fff3cf")
## The elder's marker wears the same amber the task panel and the settings headings do,
## so the thing that hands out tasks is recognisable without reading the legend.
const COL_ELDER := Color("ffd76e")
const COL_UNLOCKED := Color(1, 1, 1, 1)
## A zone you have not reached the stage for still has to be on the map — knowing
## something is out there and out of reach is the reason to keep cultivating.
const LOCKED_ALPHA := 0.42

var _refresh_accum: float = 0.0
var _reported: bool = false
## The terrain picture, wrapped once. `ImageTexture.create_from_image` uploads to the
## GPU, so doing it inside `_draw` would re-upload the whole map ten times a second.
var _ground_texture: ImageTexture
## How often the moving parts are re-read. The ground never changes; the player does,
## and ten times a second is smooth for a marker the width of a fingernail.
const REFRESH_SECONDS := 0.1


## The map's own side, in pixels. Smaller than it was, because the legend under it grew
## when it stopped being a sentence: nine honest one-line rows cost more height than three
## wrapped ones, and the height has to come from somewhere. The whole map still fits the
## canvas at 100% interface scale, which is the only number that matters.
const MAP_SIDE := 148


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_resolve()
	# A Control with no explicit size collapses to nothing inside a container, and a
	# minimap drawn into nothing is indistinguishable from a broken one.
	custom_minimum_size = Vector2(MAP_SIDE, MAP_SIDE)
	set_process(true)


func _resolve() -> void:
	var world: Node = get_tree().root.get_node_or_null("Main")
	if world == null:
		return
	_terrain = world.get_node_or_null("Terrain")
	_zones = world.get_node_or_null("QiZones")
	_camps = world.get_node_or_null("EnemyCamps")
	_safe = world.get_node_or_null("SafeZone") as Node3D
	if _safe == null:
		_safe = get_tree().get_first_node_in_group("safe_zone") as Node3D
	_player = world.get_node_or_null("Player") as Node3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_elder = get_tree().get_first_node_in_group("quest_npc") as Node3D


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum < REFRESH_SECONDS:
		return
	_refresh_accum = 0.0
	queue_redraw()


## Maps a world XZ onto the canvas. World -Z is north and north is up, so both axes
## scale straight through with no flip and no rotation.
func _to_map(point: Vector2) -> Vector2:
	var extent: float = _extent()
	if extent <= 0.0:
		return size * 0.5
	var px: float = minf(size.x, size.y) / extent
	return Vector2(size.x * 0.5 + point.x * px, size.y * 0.5 + point.y * px)


func _extent() -> float:
	if _terrain == null:
		return 0.0
	return float(_terrain.call("extent")) if _terrain.has_method("extent") else 0.0


func _draw() -> void:
	# The one boot line this subsystem gets, said on the first frame it is actually
	# drawn on rather than in `_ready`: a minimap built before its panel has been laid
	# out would report a size of zero, which is the failure worth reporting.
	if not _reported:
		_reported = true
		print("[minimap] %.0f px canvas, %d zones, %d camps, ground from the terrain map" % [
			size.x, _zone_count(), _camp_count()])
	if _terrain == null:
		_resolve()
	if size.x < 8.0 or size.y < 8.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), COL_BACKDROP, true)
	var side: float = minf(size.x, size.y)
	var ground: Texture2D = _ground()
	if ground != null:
		# Drawn see-through rather than baked see-through: the terrain's own map image is
		# opaque and shared with nothing else, so the blend belongs at the point of use.
		draw_texture_rect(ground, Rect2(Vector2.ZERO, Vector2(side, side)), false,
			Color(1.0, 1.0, 1.0, GROUND_ALPHA))
	_draw_safe_zone()
	_draw_zones()
	_draw_camps()
	_draw_elder()
	_draw_player()
	_draw_compass()
	# A border last, so the map reads as an object rather than as a hole in the HUD.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.47, 0.58, 0.55), false, 1.0)


func _ground() -> Texture2D:
	if _terrain == null or not _terrain.has_method("map_image"):
		return null
	if _ground_texture == null:
		var image: Image = _terrain.call("map_image", 224) as Image
		if image == null:
			return null
		_ground_texture = ImageTexture.create_from_image(image)
	return _ground_texture


## The wards, as a circle. Drawn before the zones so a spirit zone near the camp is not
## hidden behind the boundary.
func _draw_safe_zone() -> void:
	if _safe == null:
		return
	var radius: float = float(_safe.get("radius"))
	var centre: Vector2 = _to_map(Vector2(_safe.global_position.x, _safe.global_position.z))
	draw_arc(centre, _px_per_metre() * radius, 0.0, TAU, 64, Color(COL_SAFE, 0.7), 1.5, true)
	draw_arc(centre, _px_per_metre() * radius * 0.55, 0.0, TAU, 48,
		Color(COL_SAFE, 0.16), 1.0, true)


func _draw_zones() -> void:
	if _zones == null or not _zones.has_method("zones"):
		return
	var scale: float = _px_per_metre()
	for zone: Dictionary in _zones.call("zones"):
		var at: Vector3 = zone["position"]
		var centre: Vector2 = _to_map(Vector2(at.x, at.z))
		var tint := Color(String(zone["color"]))
		# Locked zones are what the map is for as much as the rest: they are the
		# reason to go and cultivate somewhere you can see and cannot yet use.
		var unlocked: bool = Cultivation.tier >= int(zone["required_tier"])
		var alpha: float = COL_UNLOCKED.a if unlocked else LOCKED_ALPHA
		var radius: float = scale * float(zone["radius"])
		draw_circle(centre, radius, Color(tint.r, tint.g, tint.b, 0.16 * alpha))
		draw_arc(centre, radius, 0.0, TAU, 48, Color(tint, 0.85 * alpha), 1.6, true)
		draw_circle(centre, 2.0, Color(tint, alpha))


func _draw_camps() -> void:
	if _camps == null or not _camps.has_method("camps"):
		return
	for camp: Dictionary in _camps.call("camps"):
		var at: Vector3 = camp["position"]
		var centre: Vector2 = _to_map(Vector2(at.x, at.z))
		# A ring for the fire, a dot for the camp: enough to read as hostile at a
		# glance without needing a legend.
		draw_arc(centre, 4.5, 0.0, TAU, 20, Color(COL_CAMP, 0.8), 1.4, true)
		draw_circle(centre, 2.0, COL_CAMP)


## The elder, as a diamond, and the one mark on this map that moves on its own.
##
## A task that is finished but unclaimed is the one thing in the game that is *waiting on
## you* — it pays out crystals and abilities and it waits indefinitely — and the elder is
## the only place to collect it. So the mark breathes while a reward is pending, and sits
## still the rest of the time: motion on a map means "there is something here for you",
## which only stays true if it is used for nothing else.
func _draw_elder() -> void:
	if _elder == null:
		return
	var centre: Vector2 = _to_map(Vector2(_elder.global_position.x, _elder.global_position.z))
	_draw_diamond(centre, 4.2, 6.2, COL_ELDER)
	if not elder_reward_waiting():
		return
	var pulse: float = 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) / 260.0)
	draw_arc(centre, 7.0 + 2.0 * pulse, 0.0, TAU, 20,
		Color(COL_ELDER, 0.35 + 0.4 * pulse), 1.4, true)


## True when a finished task is waiting to be claimed at the elder.
##
## Read through the autoload rather than cached: the task chain is advanced from a dozen
## places, and a cached copy here is one more thing that has to be told when it moves.
func elder_reward_waiting() -> bool:
	var quests: Node = get_node_or_null("/root/Quests")
	if quests == null or not quests.has_method("claimable"):
		return false
	return not (quests.call("claimable") as Dictionary).is_empty()


## A diamond, the one shape on the map that is neither a ring nor an arrow.
func _draw_diamond(centre: Vector2, half_w: float, half_h: float, tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		centre + Vector2(0.0, -half_h), centre + Vector2(half_w, 0.0),
		centre + Vector2(0.0, half_h), centre + Vector2(-half_w, 0.0),
	]), tint)
	draw_polyline(PackedVector2Array([
		centre + Vector2(0.0, -half_h), centre + Vector2(half_w, 0.0),
		centre + Vector2(0.0, half_h), centre + Vector2(-half_w, 0.0),
		centre + Vector2(0.0, -half_h),
	]), Color(0.05, 0.05, 0.07, 0.9), 1.0)


func _draw_player() -> void:
	if _player == null:
		return
	var centre: Vector2 = _to_map(Vector2(_player.global_position.x, _player.global_position.z))
	# Facing comes from the body, not the camera, so the arrow agrees with where the
	# character is actually pointing when the camera is swung around.
	var facing: Vector3 = -_player.global_transform.basis.z
	var heading := Vector2(facing.x, facing.z)
	if heading.length_squared() < 0.0001:
		heading = Vector2(0.0, -1.0)
	heading = heading.normalized()
	var side := Vector2(-heading.y, heading.x)
	var nose: Vector2 = centre + heading * 6.0
	var left: Vector2 = centre - heading * 3.0 + side * 3.6
	var right: Vector2 = centre - heading * 3.0 - side * 3.6
	draw_colored_polygon(PackedVector2Array([nose, left, right]), COL_PLAYER)
	draw_arc(centre, 7.5, 0.0, TAU, 24, Color(COL_PLAYER, 0.45), 1.0, true)


## N at the top, and the distance scale underneath it. A map with no scale is a
## picture: two hundred metres of world compress into the same square whatever the
## world is, so the only way to read distance off it is to be told one.
func _draw_compass() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(size.x * 0.5 - 4.0, 13.0), "N", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 11, Color(1, 1, 1, 0.75))
	var extent: float = _extent()
	if extent <= 0.0:
		return
	var px: float = _px_per_metre() * 50.0
	var y: float = size.y - 8.0
	var x: float = size.x * 0.5
	draw_line(Vector2(x - px * 0.5, y), Vector2(x + px * 0.5, y), Color(1, 1, 1, 0.7), 1.0)
	draw_string(font, Vector2(x + px * 0.5 + 4.0, y + 4.0), "50 m",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))


func _zone_count() -> int:
	if _zones == null or not _zones.has_method("zones"):
		return 0
	return (_zones.call("zones") as Array).size()


func _camp_count() -> int:
	if _camps == null or not _camps.has_method("camps"):
		return 0
	return (_camps.call("camps") as Array).size()


func _px_per_metre() -> float:
	var extent: float = _extent()
	if extent <= 0.0:
		return 0.0
	return minf(size.x, size.y) / extent


# ------------------------------------------------------------------- the legend

## What the map's marks mean. Returned as (swatch colour, text) pairs so the panel can
## label itself without a second copy of the palette living in the HUD — the one failure a
## legend can have that is worse than having no legend is a chip that disagrees with the
## dot it is explaining.
##
## The full name, not a bare noun. "wards" against a cyan ring is a guess for a player who
## has not read the help strip; "camp wards (safe)" is not, and the legend is the one place
## with room for it.
func legend() -> Array:
	var elder_note: String = "a reward is waiting" if elder_reward_waiting() else ""
	return [
		{"color": COL_PLAYER, "text": "You", "note": ""},
		{"color": COL_SAFE, "text": "Camp wards", "note": ""},
		{"color": COL_CAMP, "text": "Raider camp", "note": ""},
		{"color": COL_ELDER, "text": "The elder", "note": elder_note},
	]


## The spirit zones in placement order, for the HUD's legend row.
func zone_legend() -> Array:
	if _zones == null or not _zones.has_method("zones"):
		return []
	var out: Array = []
	for zone: Dictionary in _zones.call("zones"):
		var locked: bool = Cultivation.tier < int(zone["required_tier"])
		out.append({
			"color": Color(String(zone["color"])),
			"text": String(zone["name"]),
			"locked": locked,
			# The stage you need, and what it does for you. A map that names four pillars
			# and explains none of them is a list of nouns; the numbers are the reason to
			# walk to one.
			"note": ("needs stage %d" % int(zone["required_tier"])) if locked else (
				"x%.1f qi" % float(zone["boost"])),
		})
	return out
