extends Node3D
## Signposts along the roads.
##
## A road is only a route if it goes somewhere, so each signpost names the nearest
## landmark — a spirit zone, a raider camp, or the home camp — and says which way
## along the road it lies. They are built from primitives rather than from the kit,
## because the kits ship no sign: a plank, a post and a Label3D that faces the road
## is a sign, and it costs three draws.
##
## The signs are what the player reads to decide where to go, so the text is the
## feature: "Whispering Grove  62 m" beats a landmark they cannot see over a hill.

const POST_COLOR := Color("6b4c31")
const PLANK_COLOR := Color("8a6a44")

@export var enabled: bool = true
## Where along a road a sign stands, as fractions of that road's own length.
##
## These used to be distances in metres, which was a bug waiting to happen twice over:
## the network shipped with two signs per road instead of three because the third
## distance was past the end of a shorter road, and then the map grew again and every
## sign stayed exactly where it was, bunched into the first two thirds of a road twice
## as long. A fraction cannot outlive what it is a fraction of.
@export var at_fractions: Array = [0.17, 0.41, 0.64, 0.86]
## How far off the road's centre line a sign stands, so it is not in the way.
@export var side_offset: float = 5.3
@export var post_height: float = 2.1
@export var plank_size: Vector3 = Vector3(2.3, 0.62, 0.12)

var _terrain: Node
var _zones: Node
var _camps: Node
var _signs: int = 0


func _ready() -> void:
	if not enabled:
		return
	_terrain = get_parent().get_node_or_null("Terrain")
	_zones = get_parent().get_node_or_null("QiZones")
	_camps = get_parent().get_node_or_null("EnemyCamps")
	if _terrain == null or not _terrain.has_method("roads"):
		push_warning("[signs] no roads to sign")
		return
	_build()
	print("[signs] %d signposts along %d roads" % [_signs, (_terrain.call("roads") as Array).size()])


func _build() -> void:
	var roads: Array = _terrain.call("roads")
	for index in roads.size():
		var road: Dictionary = roads[index]
		var points: PackedVector2Array = road["points"]
		# The road's own measured length, not the reach it was asked for: the centre line
		# stops wherever the ground said stop, and a fraction of a length that was never
		# achieved is how a sign ends up in the last metre of a road.
		var length: float = _length_of(points)
		for fraction: float in at_fractions:
			var want: float = length * clampf(float(fraction), 0.0, 0.95)
			var at: Vector2 = _point_at(points, want)
			if at == Vector2.ZERO and want > 1.0:
				continue
			_place_sign(road, at, want, int(index))


## Total length of a sampled centre line.
func _length_of(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


## The road's centre-line point a given distance out, by walking the samples. A road
## is sampled at a fixed spacing, so this is a lookup rather than a curve fit.
func _point_at(points: PackedVector2Array, travelled: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var step: float = float(_terrain.get("road_step"))
	var index: int = int(round(travelled / maxf(0.1, step)))
	if index >= points.size():
		return Vector2.ZERO
	return points[index]


func _place_sign(road: Dictionary, at: Vector2, travelled: float, road_index: int) -> void:
	var heading: float = float(road["heading"])
	# Perpendicular to the road, so the sign faces somebody walking down it.
	var side: Vector2 = Vector2(cos(heading + PI * 0.5), sin(heading + PI * 0.5))
	var spot := Vector2(at.x + side.x * side_offset, at.y + side.y * side_offset)
	var ground: float = float(_terrain.call("surface_height_at", spot.x, spot.y))

	var root := Node3D.new()
	root.name = "Signpost_%d" % _signs
	root.position = Vector3(spot.x, ground, spot.y)
	root.rotation.y = heading + PI * 0.5
	# Which road this sign belongs to, and how far along it. Not used by the sign itself:
	# it is how the network can be counted from outside, and counting signs per road is the
	# check that catches a distance that has fallen past the end of a road — which is how
	# the whole map once shipped with two signs a road instead of three, silently.
	root.set_meta("road_index", road_index)
	root.set_meta("travelled", travelled)
	add_child(root)
	root.add_to_group("signpost")

	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.16, post_height, 0.16)
	post.mesh = post_mesh
	post.material_override = _wood(POST_COLOR)
	post.position = Vector3(0.0, post_height * 0.5, 0.0)
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(post)

	var plank := MeshInstance3D.new()
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = plank_size
	plank.mesh = plank_mesh
	plank.material_override = _wood(PLANK_COLOR)
	plank.position = Vector3(0.0, post_height - 0.35, 0.0)
	root.add_child(plank)

	var destination: Dictionary = _destination(at)
	var arrow: String = "-->" if destination["side"] else "<--"
	var label := Label3D.new()
	label.name = "Text"
	label.text = "%s  %s  %d m" % [
		String(destination["name"]).to_upper(), arrow, int(round(float(destination["distance"]))),
	]
	label.font_size = 96
	label.pixel_size = 0.008
	label.outline_size = 14
	label.outline_modulate = Color(0.08, 0.06, 0.04)
	label.modulate = Color("f6ecdc")
	label.position = Vector3(0.0, post_height - 0.35, 0.09)
	root.add_child(label)
	_signs += 1


## The nearest thing worth walking to from where the sign stands, and which side of the
## road it is on. Home counts, because a player who is lost needs that most of all.
func _destination(at: Vector2) -> Dictionary:
	var best: Dictionary = {"name": "Home camp", "distance": at.length(), "side": false}
	var here := Vector3(at.x, 0.0, at.y)
	if _zones != null and _zones.has_method("zones"):
		for zone: Dictionary in _zones.call("zones"):
			var centre: Vector3 = zone["position"]
			var d: float = Vector2(centre.x - at.x, centre.z - at.y).length()
			if d < float(best["distance"]):
				best = {
					"name": String(zone["name"]),
					"distance": d,
					"side": _is_right_of(at, Vector2(centre.x, centre.z), here),
				}
	if _camps != null and _camps.has_method("camps"):
		for camp: Dictionary in _camps.call("camps"):
			var centre: Vector3 = camp["position"]
			var d: float = Vector2(centre.x - at.x, centre.z - at.y).length()
			if d < float(best["distance"]):
				best = {
					"name": String(camp["name"]),
					"distance": d,
					"side": _is_right_of(at, Vector2(centre.x, centre.z), here),
				}
	return best


## Which way the destination lies relative to the road the sign belongs to, so the
## arrow points the right way. `at` is the road point, `target` the destination.
func _is_right_of(at: Vector2, target: Vector2, _here: Vector3) -> bool:
	var previous: Vector2 = _road_heading_point(at)
	var forward: Vector2 = (at - previous)
	if forward.length_squared() < 0.0001:
		return false
	forward = forward.normalized()
	var right := Vector2(-forward.y, forward.x)
	return (target - at).dot(right) > 0.0


## The next point back along the road, so the sign can tell which way "forward" is.
func _road_heading_point(at: Vector2) -> Vector2:
	var roads: Array = _terrain.call("roads")
	for road: Dictionary in roads:
		var points: PackedVector2Array = road["points"]
		for i in points.size():
			if points[i].distance_to(at) < 0.5 and i > 0:
				return points[i - 1]
	return at - Vector2(1.0, 0.0)


func _wood(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.9
	material.metallic = 0.0
	return material


func sign_count() -> int:
	return _signs
