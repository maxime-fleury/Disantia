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
var _landmarks: Node
var _cave: Node

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
## A site you have found wears the same green as the ring it leaves on the ground where
## the beacon was, so the mark on the map and the thing under your feet are one object.
const COL_FOUND := Color("cfe8b8")
## A champion, when the camp it holds has no colour of its own to wear.
const COL_CHAMPION := Color("ff9d5c")
## The tower is the tallest thing in the valley by an order of magnitude, so it gets the one
## mark that reads as *height* rather than as ground: a spire.
const COL_TOWER := Color("dce4f2")
## A zone you have not reached the stage for still has to be on the map — knowing
## something is out there and out of reach is the reason to keep cultivating.
const LOCKED_ALPHA := 0.42
## The Hollow. The one mark on this map that is a *hole* rather than a place: drawn as a dark
## disc with no fill, because what it says is "there is nothing to see in here".
const COL_CAVE := Color("b48cff")

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
	_landmarks = world.get_node_or_null("Landmarks")
	_cave = world.get_node_or_null("Cave")


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
		print("[minimap] %.0f px canvas, %d zones, %d camps, %d/%d sites found, %s, ground from the terrain map" % [
			size.x, _zone_count(), _camp_count(), landmark_counts().x, landmark_counts().y,
			Wards.summary()])
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
	_draw_wards()
	_draw_zones()
	_draw_villages()
	_draw_camps()
	_draw_tower()
	_draw_landmarks()
	_draw_caves()
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


## The wards you cannot pass, and the ones you have.
##
## This is the single most useful thing the map says now that the world is concentric, and
## it says it with one colour per wall rather than a label: an unbroken bright circle is a
## barrier, and the same circle drawn faint is a wall that is down. A legend row names the
## colour, so the map does not have to spell it out three times around the edge.
##
## Drawn under everything else, so a zone or a champion standing behind a wall is still
## visible through it — the wall is the structure, not the content.
func _draw_wards() -> void:
	var scale: float = _px_per_metre()
	if scale <= 0.0:
		return
	var centre: Vector2 = _to_map(Vector2.ZERO)
	for i in Wards.gate_count():
		var gate: Dictionary = Wards.GATES[i]
		var tint: Color = gate.get("color", Color("6ec8ff"))
		var locked: bool = i >= Wards.passed() and not Wards.is_open(i)
		var alpha: float = 0.62 if locked else 0.22
		draw_arc(centre, scale * Wards.radius_of(i), 0.0, TAU, 96,
			Color(tint, alpha), 1.8 if locked else 1.0, true)


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
		var warden: String = String(camp.get("warden", ""))
		if warden == "":
			continue
		# A champion wears the colour of the wall it stands behind, and a felled one is
		# drawn hollow: the map is the record of what is left to do, and a mark that stayed
		# solid after the fight was won would be a lie you would walk across the map to find.
		var tint: Color = camp.get("colour", COL_CHAMPION)
		var down: bool = Wards.warden_down(warden)
		if down:
			draw_polyline(_diamond_points(centre, 5.4, 7.6), Color(tint, 0.45), 1.2)
		else:
			_draw_diamond(centre, 5.4, 7.6, tint)


## The three villages, drawn as walled places rather than as dots: an outer ring for the
## palisade and a dot for the square inside it, in the village's own colour. A village is the
## one kind of place on this map that is *safe*, and the ring is what says so at a glance.
##
## A village you are wanted in turns red. The law is per-village — burning a camp in one is not
## the next one's business — so a single global "wanted" marker would be a lie about the three
## places it could be about.
func _draw_villages() -> void:
	for mark: Dictionary in village_marks():
		var at: Vector2 = mark["at"]
		var tint: Color = mark["tint"]
		var shut: bool = bool(mark["shut"])
		draw_arc(at, 5.6, 0.0, TAU, 22, Color(tint, 0.9 if not shut else 0.55), 1.5, true)
		draw_circle(at, 2.2, Color(tint, 0.85))
		# A tick across the square for the rungs of the ladder: one crime is a mark you can
		# still walk off, and an outlaw's village is crossed out.
		if int(mark["wanted"]) >= 2:
			draw_line(at - Vector2(3.0, -3.0), at + Vector2(3.0, -3.0), COL_CAMP, 1.4, true)
		# A gate that is down is drawn *open* — the ring broken on either side of the gate — and
		# the village under tonight's raid wears a ring of its own. Between them the map answers
		# the only two questions a raid raises: which one, and is it still open.
		if bool(mark["sacked"]):
			draw_arc(at, 5.6, -0.85, 0.85, 8, COL_CAMP, 2.0, true)
			draw_arc(at, 5.6, PI - 0.85, PI + 0.85, 8, COL_CAMP, 2.0, true)
		if bool(mark["raided"]):
			draw_arc(at, 8.8, 0.0, TAU, 26, Color(COL_CAMP, 0.8), 1.6, true)


## What the map is about to draw, as data.
##
## The same reason `landmark_counts` exists: a test cannot read pixels, and a mark worked out
## twice — once for the screen and once for the check — is a check that stays green while the
## screen goes wrong.
func village_marks() -> Array:
	var out: Array = []
	var raided: String = String(Raids.tonight.get("village", ""))
	for entry: Dictionary in Villages.all():
		var village_id: String = String(entry["id"])
		var site: Dictionary = Haven.site(village_id)
		if site.is_empty():
			continue
		var centre: Vector3 = site["centre"]
		var tint: Color = entry.get("colour", COL_SAFE)
		var wanted: int = Law.wanted_at(village_id)
		if wanted > 0:
			tint = COL_CAMP.lerp(tint, 0.25)
		out.append({
			"id": village_id,
			"at": _to_map(Vector2(centre.x, centre.z)),
			"tint": tint,
			"wanted": wanted,
			"shut": Law.shops_closed(village_id),
			"sacked": Raids.is_sacked(village_id),
			"raided": raided == village_id,
		})
	return out


## The Hollow, as a dark disc: the one place on this map that is drawn as an absence.
##
## It is on the map from the first minute, unlike the nine sites, and that is the point of the
## difference: those are *discoveries* and this is a *destination*. Knowing a hole in the rock
## exists on the far side of the valley is what sends a player to a merchant for a lamp, and a
## tool nobody knows to want is a tool that never gets bought. The ring around it is how far its
## roof reaches, which is the one thing about it the map can honestly say.
func _draw_caves() -> void:
	for mark: Dictionary in cave_marks():
		var at: Vector2 = mark["at"]
		draw_circle(at, float(mark["radius"]), Color(0.02, 0.02, 0.04, 0.72))
		draw_arc(at, float(mark["radius"]), 0.0, TAU, 30, Color(COL_CAVE, 0.75), 1.3, true)
		if bool(mark["taken"]):
			draw_circle(at, 2.0, Color(COL_FOUND, 0.9))
		else:
			draw_arc(at, 2.6, 0.0, TAU, 16, Color(COL_CAVE, 0.95), 1.4, true)


## What the cave marks are about to be, as data — the same reason `village_marks` exists.
func cave_marks() -> Array:
	if _cave == null or not _cave.has_method("summary"):
		return []
	var summary: Dictionary = _cave.call("summary") as Dictionary
	if summary.is_empty():
		return []
	var at: Vector3 = summary["at"]
	return [{
		"at": _to_map(Vector2(at.x, at.z)),
		"radius": _px_per_metre() * float(summary["interior"]),
		"taken": bool(summary["taken"]),
		"inside": bool(summary["inside"]),
	}]


## The tower, as a spire: a triangle and a mast, so it is legible at four pixels and readable
## as *tall* rather than as another ring on the ground.
func _draw_tower() -> void:
	var site: Node = get_tree().get_first_node_in_group("tower_site")
	if site == null or not site.has_method("base_position"):
		return
	var base: Vector3 = site.call("base_position")
	var at: Vector2 = _to_map(Vector2(base.x, base.z))
	if Tower.inside():
		draw_circle(at, 6.4, Color(COL_TOWER, 0.35))
	draw_line(at - Vector2(0.0, 7.0), at + Vector2(0.0, 1.2), Color(COL_TOWER, 0.85), 1.6, true)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -7.4), at + Vector2(-3.4, -1.6), at + Vector2(3.4, -1.6),
	]), COL_TOWER)


## Sites you have found, and nothing else.
##
## Undiscovered sites are deliberately absent. Each one already stands in the world under
## a pillar of light you can see from high ground — that is the call, and a walk to a
## beacon is an adventure. Drawing all nine on the map instead would turn each of them into
## a coordinate to walk to, which is the same information with the exploring taken out.
##
## What the map does say is how many there are, in the legend: a count is the one honest
## hint, because it tells the player there is more out there without telling them where.
func _draw_landmarks() -> void:
	if _landmarks == null or not _landmarks.has_method("sites"):
		return
	for site: Dictionary in _landmarks.call("sites"):
		if not bool(site.get("discovered", false)):
			continue
		var at: Vector3 = site["position"]
		var centre: Vector2 = _to_map(Vector2(at.x, at.z))
		# A square: the only shape on this map that is neither a ring, a dot nor an arrow.
		draw_rect(Rect2(centre - Vector2(2.4, 2.4), Vector2(4.8, 4.8)), COL_FOUND, true)
		draw_rect(Rect2(centre - Vector2(3.8, 3.8), Vector2(7.6, 7.6)),
			Color(COL_FOUND, 0.5), false, 1.0)


## How many sites have been found, and how many there are. Public for the legend and for
## the boot line.
func landmark_counts() -> Vector2i:
	if _landmarks == null or not _landmarks.has_method("sites"):
		return Vector2i.ZERO
	var found: int = 0
	var total: int = 0
	for site: Dictionary in _landmarks.call("sites"):
		total += 1
		if bool(site.get("discovered", false)):
			found += 1
	return Vector2i(found, total)


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
	draw_colored_polygon(_diamond_points(centre, half_w, half_h), tint)
	draw_polyline(_diamond_points(centre, half_w, half_h),
		Color(0.05, 0.05, 0.07, 0.9), 1.0)


func _diamond_points(centre: Vector2, half_w: float, half_h: float) -> PackedVector2Array:
	return PackedVector2Array([
		centre + Vector2(0.0, -half_h), centre + Vector2(half_w, 0.0),
		centre + Vector2(0.0, half_h), centre + Vector2(-half_w, 0.0),
		centre + Vector2(0.0, -half_h),
	])


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
func cave_note() -> String:
	if _cave == null or not _cave.has_method("summary"):
		return ""
	var summary: Dictionary = _cave.call("summary") as Dictionary
	if summary.is_empty():
		return ""
	if bool(summary["taken"]):
		return "emptied"
	return "you will need a light"


func legend() -> Array:
	var elder_note: String = "a reward is waiting" if elder_reward_waiting() else ""
	var counts: Vector2i = landmark_counts()
	var site_note: String = ""
	if counts.y > 0:
		site_note = "%d of %d found" % [counts.x, counts.y]
	# One row for the tower and none for the villages. The legend is a column in a panel with a
	# fixed corner, and every row it gains pushes the panel up into the action panel above it —
	# a cost the map's own marks do not have. The villages are drawn as rings with squares in
	# them, which is legible next to the camps' rings, and the tower is the one mark that has to
	# be *named*: it is where the record is.
	var wanted_note: String = ""
	for entry: Dictionary in Villages.all():
		var village_id: String = String(entry["id"])
		if Law.wanted_at(village_id) <= 0:
			continue
		var owed: int = Law.fine(village_id)
		wanted_note = "%s wants %d" % [String(entry["name"]), owed]
		if Law.shops_closed(village_id):
			wanted_note = "%s is shut to you" % String(entry["name"])
		break
	var rows: Array = [
		{"color": COL_PLAYER, "text": "You", "note": ""},
		{"color": COL_SAFE, "text": "Camp wards", "note": wanted_note},
		{"color": COL_CAMP, "text": "Raider camp", "note": ""},
		{"color": COL_TOWER, "text": "Village / tower",
			"note": "%d floors, deepest %d" % [Tower.FLOORS, Tower.deepest]},
		{"color": COL_ELDER, "text": "The elder", "note": elder_note},
		{"color": COL_FOUND, "text": "Site you found", "note": site_note},
		# One row for the Hollow, and it earns its place: it is the only mark on the map that
		# answers a question about *gear* rather than about danger.
		{"color": COL_CAVE, "text": "The Hollow", "note": cave_note()},
	]
	# The wards, one row per gate, and the one you are working towards is the bright one.
	# Named with the realm that opens it, because that is the entire question the wall poses.
	for i in Wards.gate_count():
		var gate: Dictionary = Wards.GATES[i]
		var locked: bool = i >= Wards.passed() and not Wards.is_open(i)
		rows.append({
			"color": gate.get("color", COL_SAFE) if locked else Color(0.55, 0.6, 0.66),
			"text": String(gate["name"]),
			"note": ("needs %s" % Wards.realm_label_of(i)) if locked else "open",
		})
	var felled: int = Wards.felled_count()
	rows.append({
		"color": COL_CHAMPION, "text": "Champion",
		"note": "%d of %d felled" % [felled, Wards.warden_count()],
	})
	return rows


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
