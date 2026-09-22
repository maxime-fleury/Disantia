extends Node3D
## Places to find.
##
## The map is 320 metres of good ground with nothing in it, which is the one thing that
## keeps a world from being worth walking across. The roads were levelled, the hills
## generated, the camps stocked — and a player who walked for two minutes arrived
## somewhere that looked exactly like where they left. Nothing was ever *there*.
##
## So this file is the answer to "what is over that hill": nine sites, one per road, each
## one a small arrangement of kit pieces standing on ground that has been empty since it
## was generated. Walk into one and it is yours — crystals, and usually something that
## makes the body permanently better.
##
## Three rules make them a reason to travel rather than a chore list:
##
##   * **One per road, somewhere along it.** Every site sits beside a levelled road at a
##     random distance out, so following a road is how you find them and no two are on
##     the same route. Nothing here is signposted; the roads are the signpost.
##   * **The beacon.** An undiscovered site wears a tall column of light you can see from
##     high ground and from across a valley. Finding one puts it out. That light going
##     dark is the whole reward loop in one image: the map stops calling and starts being
##     a map.
##   * **Once, permanently.** A site pays on the first entry and never again, and what it
##     paid is remembered in the save. Walking back is allowed; farming is not.

## How close the player has to get for a site to count as found. Generous — this is a
## discovery, not a platform test, and a site you can see but cannot touch is a bug.
const DISCOVER_RADIUS := 8.0

## The sites, in the order they are handed to the roads. `crystals` is the purse, and
## `boon` is the permanent gift: a stat cap raised by that much, once, forever.
##
## Every site is *named* rather than numbered, because a name is what makes arriving
## somewhere feel like arriving rather than like triggering. Two sites never share a name
## because each kind appears once.
const KINDS: Array = [
	{
		"id": "circle", "name": "The Standing Circle",
		"blurb": "Seven stones on their ends, and a cold fire between them.",
		"crystals": 5, "boon": {"stat": "qi", "amount": 6.0},
	},
	{
		"id": "gate", "name": "The Fallen Gate",
		"blurb": "A doorway to a wall that is no longer there.",
		"crystals": 4, "boon": {"stat": "hp", "amount": 14.0},
	},
	{
		"id": "watch", "name": "The Grey Watch",
		"blurb": "A tower with the roof gone and the torch still lit.",
		"crystals": 7, "boon": {"stat": "defense", "amount": 2.0},
	},
	{
		"id": "shrine", "name": "The Quiet Shrine",
		"blurb": "Somebody kept this swept. Somebody still does.",
		"crystals": 6, "boon": {"stat": "qi", "amount": 8.0},
	},
	{
		"id": "cairn", "name": "The Traveller's Cairn",
		"blurb": "Stones piled by every hand that passed, and a chest at its foot.",
		"crystals": 9, "boon": {"stat": "hp", "amount": 10.0},
	},
	{
		"id": "forge", "name": "The Cold Forge",
		"blurb": "An anvil, a whetstone, and a stand with no weapon on it.",
		"crystals": 6, "boon": {"stat": "attack", "amount": 2.0},
	},
	{
		"id": "wreck", "name": "The Broken Cart",
		"blurb": "Whatever it carried is scattered downhill from here.",
		"crystals": 8, "boon": {"stat": "speed", "amount": 0.6},
	},
	{
		"id": "hollow", "name": "The Hollow Oak",
		"blurb": "Old enough to have been a landmark before there were roads.",
		"crystals": 5, "boon": {"stat": "jump", "amount": 0.35},
	},
	{
		"id": "sundered", "name": "The Sundered Stones",
		"blurb": "Split clean through, and not by weather.",
		"crystals": 10, "boon": {"stat": "attack", "amount": 3.0},
	},
]

const PROPS := "res://assets/props/"
const STRUCTURES := "res://assets/structures/"
const NATURE := "res://assets/nature/"

## How far down a road a site may sit, as a fraction of that road's length, and how far
## off the centre line. The band keeps sites out of the home camp at one end and off the
## very rim of the map at the other, where the road runs out.
##
## The per-site bands below sit inside these, and they are in KINDS order — site 0 takes the
## first road, and so on — so the list is a route rather than a set of distances.
const ALONG_MIN := 0.28
const ALONG_MAX := 0.90

## Where each site stands, in KINDS order. Three in the ring you start in, then two, three
## and one further out.
##
## Sites used to be scattered randomly along whichever road they landed on, which made the
## nine places an even sprinkle of distances: none in particular close, none in particular
## far, and no ring with a guaranteed thing to find. The elder's chain asks for two of the
## old places early — and *early* is inside the first ward, which a realm cannot open for
## some minutes — so there have to be two of them inside it, and each ring out has to have
## its own share. A random sprinkle cannot promise either.
##
## The numbers are read against the wards: ring 0 ends at 0.4125 of the half-extent, the
## second ring at 0.65 and the third at 0.80. A band that drifts across a boundary is a site
## in the wrong chapter, and the suite checks exactly that.
const SITE_BANDS: Array = [
	Vector2(0.28, 0.31), Vector2(0.32, 0.35), Vector2(0.38, 0.42),
	Vector2(0.47, 0.53), Vector2(0.55, 0.61),
	Vector2(0.68, 0.72), Vector2(0.73, 0.76), Vector2(0.77, 0.79),
	Vector2(0.86, 0.90),
]
const SIDE_MIN := 7.0
const SIDE_MAX := 12.5
## Ground a site will stand on. Steeper than this and the pieces sink into a slope.
const MAX_SLOPE := 0.2

@export var enabled: bool = true
@export var landmark_seed: int = 60417

var _terrain: Node
var _player: Node3D
var _sites: Array = []
var _rng := RandomNumberGenerator.new()
var _found_this_frame: int = 0


func _ready() -> void:
	if not enabled:
		return
	_terrain = get_parent().get_node_or_null("Terrain")
	_player = get_parent().get_node_or_null("Player") as Node3D
	if _terrain == null or not _terrain.has_method("roads"):
		push_warning("[landmarks] no terrain or roads to place along")
		return
	_place()
	_restore_found()
	print("[landmarks] %d sites along the roads (%s), %d already found" % [
		_sites.size(), _spread(), discovered_count()
	])


# --------------------------------------------------------------------- placement

func _place() -> void:
	var roads: Array = _terrain.call("roads")
	if roads.is_empty():
		return
	_rng.seed = landmark_seed
	# One site per road, taking the roads in order so the network is used end to end
	# rather than the sites piling onto whichever route happened to be first.
	var index: int = 0
	for kind: Dictionary in KINDS:
		if index >= roads.size():
			break
		var road: Dictionary = roads[index]
		var band: Vector2 = SITE_BANDS[index % SITE_BANDS.size()]
		index += 1
		# Its own stretch of the road, with a looser idea of "level enough" on each retry.
		#
		# The *band* is a promise and the slope is a preference, which is why only the second
		# one moves: a site that drifts out of its ring to find a flat patch is a site in the
		# wrong chapter, and a ring with nothing to find in it is a ring with no reason to be
		# walked. Standing on a gentle slope is a far smaller problem than either.
		var spot: Vector2 = _spot_on(road, band)
		if spot == Vector2.ZERO:
			spot = _spot_on(road, band, 0.08)
		if spot == Vector2.ZERO:
			spot = _spot_on(road, band, 0.20)
		if spot == Vector2.ZERO:
			continue
		_build(kind, road, spot)
	# The leftover roads are left alone on purpose: the sites are nine specific places,
	# not a quota, and a tenth one made of the same pieces would read as filler.


## How many sites landed in each ring, for the boot line. The suite asserts on the same
## claim — a ring with nothing to find in it is a ring with no reason to walk it.
func sites_in_ring(ring: int) -> Array:
	var out: Array = []
	for site: Dictionary in _sites:
		var at: Vector3 = site["position"]
		if Wards.ring_at(at) == ring:
			out.append(site)
	return out


func _spread() -> String:
	var parts: Array = []
	for ring in Wards.RING_ZONES.size():
		parts.append("ring %d: %d" % [ring, sites_in_ring(ring).size()])
	return ", ".join(parts)


## Walks a road's centre line looking for ground a site can stand on, and returns the
## position offset to the side of it. `Vector2.ZERO` means the whole road was too steep,
## which is a reason to skip the road rather than to build a site in a bad place.
func _spot_on(road: Dictionary, band: Vector2 = Vector2(ALONG_MIN, ALONG_MAX),
		slack: float = 0.0) -> Vector2:
	var points: PackedVector2Array = road["points"]
	if points.size() < 8:
		return Vector2.ZERO
	var heading: float = float(road["heading"])
	var side: Vector2 = Vector2(cos(heading + PI * 0.5), sin(heading + PI * 0.5))
	var low: float = maxf(ALONG_MIN, band.x)
	var high: float = minf(ALONG_MAX, band.y)
	var slope_limit: float = MAX_SLOPE + slack
	for attempt in 14:
		var along: float = _rng.randf_range(low, high)
		var at: Vector2 = points[clampi(int(along * float(points.size())), 0, points.size() - 1)]
		var offset: float = _rng.randf_range(SIDE_MIN, SIDE_MAX)
		var spot: Vector2 = at + side * offset
		if _clear_of_everything(spot) and float(_terrain.call("slope_at", spot.x, spot.y)) <= slope_limit:
			return spot
	return Vector2.ZERO


## Sites keep their distance from each other and from the home camp. Two rewards within
## sight of each other are one reward, and the first site is not meant to be visible from
## the front gate.
func _clear_of_everything(spot: Vector2) -> bool:
	if spot.length() < 40.0:
		return false
	var extent: float = float(_terrain.call("extent"))
	if spot.length() > extent * 0.86:
		return false
	for site: Dictionary in _sites:
		var other: Vector3 = site["position"]
		if Vector2(spot.x - other.x, spot.y - other.z).length() < 45.0:
			return false
	return true


func _build(kind: Dictionary, road: Dictionary, spot: Vector2) -> void:
	var root := Node3D.new()
	var site_id: String = String(kind["id"])
	root.name = "Site_" + site_id
	var height: float = float(_terrain.call("surface_height_at", spot.x, spot.y))
	root.position = Vector3(spot.x, height, spot.y)
	add_child(root)
	root.add_to_group("landmark")
	# Facing the road it was found beside, so a site reads as a place you arrive at
	# rather than a pile someone dropped at a random angle.
	var yaw: float = float(road["heading"]) + PI * 0.5

	_furnish(site_id, root, yaw)

	var beacon: Node3D = _make_beacon(kind)
	root.add_child(beacon)

	root.set_meta("site_id", site_id)
	root.set_meta("site_name", String(kind["name"]))
	_sites.append({
		"id": site_id,
		"name": String(kind["name"]),
		"blurb": String(kind["blurb"]),
		"position": root.position,
		# How far off the road's centre line it stands. Recorded rather than re-measured
		# by whoever needs it, because "you find these by following a road" is a promise
		# about the world and a number in the data is the only way to check it.
		"road_distance": _road_offset(road, spot),
		"node": root,
		"beacon": beacon,
		"crystals": int(kind["crystals"]),
		"boon": kind["boon"],
		"discovered": false,
	})


## Distance from a spot to the nearest point on a road's centre line.
func _road_offset(road: Dictionary, spot: Vector2) -> float:
	var best: float = INF
	for point: Vector2 in road["points"]:
		best = minf(best, spot.distance_to(point))
	return 0.0 if best == INF else best


## The arrangement each site is made of. A dictionary of kit pieces placed at fixed
## offsets per site rather than a general algorithm: nine hand-made places read as nine
## places, and a loop that scatters three rocks and a barrel reads as a loop that
## scattered three rocks and a barrel.
func _furnish(site_id: String, root: Node3D, yaw: float) -> void:
	match site_id:
		"circle":
			for i in 7:
				var angle: float = yaw + TAU * float(i) / 7.0
				_piece(NATURE, "Rock_Medium_1.gltf", root, angle, 4.2, 0.7, TAU * float(i) / 7.0)
			_piece(PROPS, "Cauldron.gltf", root, yaw, 0.0, 1.0, 0.0)
		"gate":
			_piece(STRUCTURES, "Wall_Arch.gltf", root, yaw, 0.0, 1.0, 0.0)
			_piece(STRUCTURES, "Prop_WoodenFence_Extension1.gltf", root, yaw + 1.5, 2.6, 1.0, 0.3)
			_piece(STRUCTURES, "Prop_WoodenFence_Extension1.gltf", root, yaw - 1.5, 2.6, 1.0, -0.3)
			_piece(STRUCTURES, "Floor_WoodLight.gltf", root, yaw + PI, 1.4, 1.0, 0.7)
		"watch":
			_piece(PROPS, "Banner_1.gltf", root, yaw, 0.0, 1.0, 0.0)
			_piece(STRUCTURES, "Wall_Plaster_Straight.gltf", root, yaw + 1.2, 1.6, 1.0, 0.0)
			_piece(STRUCTURES, "Wall_Plaster_Window_Wide_Round.gltf", root, yaw - 1.2, 1.6, 1.0, PI)
			_piece(PROPS, "Torch_Metal.gltf", root, yaw + 2.4, 2.0, 1.0, 0.0)
			_piece(PROPS, "Torch_Metal.gltf", root, yaw - 2.4, 2.0, 1.0, 0.0)
		"shrine":
			_piece(STRUCTURES, "Floor_WoodLight.gltf", root, yaw, 0.0, 1.6, 0.0)
			_piece(STRUCTURES, "Wall_Plaster_Straight.gltf", root, yaw + PI, 2.2, 1.0, PI)
			_piece(PROPS, "Cauldron.gltf", root, yaw + 0.9, 1.6, 0.9, 0.0)
			_piece(PROPS, "Bookcase_2.gltf", root, yaw - 1.6, 2.0, 0.9, 0.4)
		"cairn":
			for i in 6:
				var angle: float = TAU * float(i) / 6.0
				_piece(NATURE, "Rock_Medium_2.gltf", root, angle, 1.6 + 0.35 * float(i % 3), 0.55,
					TAU * float(i) / 6.0)
			_piece(PROPS, "Chest_Wood.gltf", root, yaw + 2.0, 2.4, 1.0, yaw)
			_piece(NATURE, "Rock_Medium_3.gltf", root, 0.0, 0.0, 0.9, 0.0)
		"forge":
			_piece(PROPS, "Anvil.gltf", root, yaw, 0.0, 1.0, 0.0)
			_piece(PROPS, "Whetstone.gltf", root, yaw + 1.4, 1.9, 1.0, 0.0)
			_piece(PROPS, "WeaponStand.gltf", root, yaw - 1.4, 2.1, 1.0, 0.0)
			_piece(PROPS, "Banner_1.gltf", root, yaw + PI, 2.6, 1.0, 0.0)
		"wreck":
			_piece(PROPS, "Crate_Wooden.gltf", root, yaw, 0.0, 1.0, 0.0)
			_piece(PROPS, "Crate_Wooden.gltf", root, yaw + 0.9, 1.5, 0.8, 0.5)
			_piece(PROPS, "Barrel.gltf", root, yaw - 1.1, 1.9, 1.0, 0.0)
			_piece(PROPS, "Barrel.gltf", root, yaw - 1.9, 2.7, 0.9, 0.0)
			_piece(PROPS, "Pot_1.gltf", root, yaw + 2.2, 2.4, 1.2, 0.0)
			_piece(PROPS, "Bench.gltf", root, yaw + PI, 2.0, 1.0, PI * 0.3)
		"hollow":
			_piece(NATURE, "TwistedTree_1.gltf", root, yaw, 0.0, 1.6, 0.0)
			_piece(NATURE, "Mushroom_Common.gltf", root, yaw + 0.9, 1.7, 1.4, 0.0)
			_piece(NATURE, "Mushroom_Common.gltf", root, yaw - 1.2, 2.1, 1.1, 0.0)
			_piece(NATURE, "Rock_Medium_3.gltf", root, yaw - 0.4, 2.6, 0.6, 0.0)
			_piece(PROPS, "Chest_Wood.gltf", root, yaw + PI, 2.4, 0.9, yaw)
		"sundered":
			for i in 4:
				var angle: float = yaw + TAU * float(i) / 4.0 + 0.4
				_piece(NATURE, "Rock_Medium_1.gltf", root, angle, 3.4, 1.35, angle)
			_piece(NATURE, "Rock_Medium_2.gltf", root, yaw, 0.6, 1.1, 0.0)
			_piece(PROPS, "Scroll_1.gltf", root, yaw, 1.6, 1.6, 0.0)


## Places one kit piece at a polar offset from the site's centre and drops it onto the
## terrain. Every kit disagrees about where its origin lives, so the piece's own measured
## box decides: the lowest point of it goes on the surface at the spot it was placed.
func _piece(dir: String, file: String, root: Node3D, angle: float, distance: float,
		scale: float, spin: float) -> Node3D:
	var scene: PackedScene = load(dir + file)
	if scene == null:
		return null
	var piece: Node3D = scene.instantiate()
	root.add_child(piece)
	var dx: float = cos(angle) * distance
	var dz: float = sin(angle) * distance
	var ground: float = float(_terrain.call(
		"surface_height_at", root.position.x + dx, root.position.z + dz
	))
	piece.scale = Vector3.ONE * scale
	var box: AABB = _bounds(piece)
	piece.position = Vector3(dx, ground - root.position.y - box.position.y * scale, dz)
	piece.rotation.y = spin
	return piece


## Measured bounds of a kit piece, in its parent's space. The same walk the camps use:
## mesh by mesh through the whole subtree, because these kits nest their meshes several
## levels down and half of them have their origin at the top of the model rather than
## the bottom.
func _bounds(node: Node, from: Transform3D = Transform3D.IDENTITY) -> AABB:
	var here: Transform3D = from * (node as Node3D).transform if node is Node3D else from
	var box := AABB()
	var found: bool = false
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			box = here * mesh_node.mesh.get_aabb()
			found = true
	for child in node.get_children():
		var child_box: AABB = _bounds(child, here)
		if child_box.size.is_zero_approx():
			continue
		box = box.merge(child_box) if found else child_box
		found = true
	return box if found else AABB()


# ----------------------------------------------------------------------- beaconing

## The column of light. It is the only thing on the map that says "come here", and it is
## deliberately the only thing: the camps have smoke, the zones have their own pillars,
## and an undiscovered site has this.
func _make_beacon(kind: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Beacon"
	var tint := Color("ffe6a8")

	var column := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.35
	cylinder.bottom_radius = 0.9
	cylinder.height = 26.0
	column.mesh = cylinder
	column.material_override = _glow(tint, 0.12)
	column.position = Vector3(0.0, 13.0, 0.0)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(column)

	var light := OmniLight3D.new()
	light.name = "BeaconLight"
	light.light_color = tint
	light.light_energy = 2.2
	light.omni_range = 22.0
	light.position = Vector3(0.0, 3.0, 0.0)
	light.shadow_enabled = false
	root.add_child(light)
	return root


func _glow(tint: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(tint, alpha)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.7
	return material


# ---------------------------------------------------------------------- discovery

func _process(_delta: float) -> void:
	if _sites.is_empty() or _player == null:
		return
	var at: Vector3 = _player.global_position
	for site: Dictionary in _sites:
		if bool(site["discovered"]):
			continue
		var centre: Vector3 = site["position"]
		# Measured flat: a site at the top of a rise must be enterable from below, and a
		# sphere check would refuse a player standing at its foot.
		if Vector2(at.x - centre.x, at.z - centre.z).length() > DISCOVER_RADIUS:
			continue
		_discover(site)


func _discover(site: Dictionary) -> void:
	site["discovered"] = true
	var node: Node3D = site["node"]
	var beacon: Node3D = site["beacon"]
	if beacon != null:
		beacon.visible = false
	# A ring on the ground where the light was: the place stays marked, it just stops
	# shouting. Anything else would make a found site indistinguishable from terrain.
	var ring := MeshInstance3D.new()
	ring.name = "FoundRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 3.4
	torus.outer_radius = 3.9
	ring.mesh = torus
	ring.material_override = _glow(Color("cfe8b8"), 0.5)
	ring.position = Vector3(0.0, 0.2, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring)

	PlayerData.mark_landmark_found(String(site["id"]))
	PlayerData.add_crystals(int(site["crystals"]))
	var boon: Dictionary = site["boon"]
	var granted: String = ""
	# `PlayerData.has(...)` is not a function on a Node, and this line used to say exactly
	# that. The call failed, and — the part that mattered — a failed call in the middle of a
	# method takes the rest of the method with it: the crystals went in, the cap boon never
	# did, and neither did `Quests.report("discover")` two statements below. So the elder's
	# "find two of the old places" could never be completed, the chain that hands out the air
	# jumps and the dash stalled on it forever, and the only visible symptom was a task bar
	# that did not move. The guard is asked of the stat table now, which is where the answer
	# actually lives.
	if not boon.is_empty() and PlayerData.has_stat(boon_stat(boon)):
		var stat_id: String = String(boon["stat"])
		var amount: float = float(boon["amount"])
		var gained: float = PlayerData.grant_cap(stat_id, amount)
		if gained > 0.0:
			granted = "  %s cap +%s." % [
				String(PlayerData.def(stat_id).get("label", stat_id)),
				String.num(gained, 2),
			]
	Quests.report("discover", 1.0)
	PlayerData.log_message.emit(
		"%s — %s  +%d crystals.%s" % [
			String(site["name"]), String(site["blurb"]), int(site["crystals"]), granted
		],
		"gain"
	)
	Audio.play("confirm", -3.0, 1.05)
	_found_this_frame += 1


func boon_stat(boon: Dictionary) -> String:
	return String(boon.get("stat", ""))


## Restores which sites were already found. The save stores ids rather than a count: a
## count would pay out the wrong sites after any change to the list, which is exactly the
## kind of thing a save file is not allowed to get wrong.
func _restore_found() -> void:
	var found: Array = PlayerData.found_landmarks
	for site: Dictionary in _sites:
		if not found.has(String(site["id"])):
			continue
		site["discovered"] = true
		var beacon: Node3D = site["beacon"]
		if beacon != null:
			beacon.visible = false


# ------------------------------------------------------------------------ queries

func sites() -> Array:
	return _sites


func discovered_count() -> int:
	var count: int = 0
	for site: Dictionary in _sites:
		if bool(site["discovered"]):
			count += 1
	return count


func total_count() -> int:
	return _sites.size()


func at(position: Vector3, radius: float = DISCOVER_RADIUS) -> Dictionary:
	for site: Dictionary in _sites:
		var centre: Vector3 = site["position"]
		if Vector2(position.x - centre.x, position.z - centre.z).length() <= radius:
			return site
	return {}


## The nearest site nobody has found yet: where it is, what it is called, and how far off
## it is. Used by the HUD's compass to keep one mark on the screen pointed at something,
## which is the difference between a map and a direction.
##
## The position comes back with the name rather than the caller looking the site up again,
## because "the nearest one" and "the one whose coordinates you then fetch" are two
## different answers as soon as the site list is walked differently.
func nearest_unfound(from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for site: Dictionary in _sites:
		if bool(site["discovered"]):
			continue
		var centre: Vector3 = site["position"]
		var distance: float = Vector2(from.x - centre.x, from.z - centre.z).length()
		if distance < best_distance:
			best_distance = distance
			best = site
	if best.is_empty():
		return {}
	return {
		"name": String(best["name"]),
		"distance": best_distance,
		"position": best["position"] as Vector3,
	}
