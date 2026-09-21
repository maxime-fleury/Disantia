extends Node3D
## Raider camps: the world's pressure.
##
## Each camp is a fire, a few props, a banner and a handful of raiders with a shared
## home position. They are placed by rejection sampling on level, well-separated
## ground rather than at authored coordinates, because the terrain is procedural: a
## hand-picked spot would be a bet on the noise field, and a camp half-buried in a
## hillside reads as a bug when the whole point is that it is a *place*.
##
## They are kept away from the home camp much further than the spirit zones are, so
## that leaving the safe zone never means being in a fight a second later, and they
## are kept off the roads' immediate shoulders so that a road stays a way past trouble
## rather than into it.

const STRUCTURES := "res://assets/structures/"
const PROPS := "res://assets/props/"

## How many camps the world gets. Every one carries `raiders`, so this is also the
## number of fights available at once.
@export var camp_count: int = 5
@export var camp_seed: int = 88211
## Raiders per camp. Two guards read as a camp; five would read as a wall.
@export var raiders: int = 3
## How far from the origin the nearest camp may be. Comfortably outside the safe zone
## radius, so a camp is never visible from inside the wards.
@export var camp_clearance: float = 46.0
@export var camp_separation: float = 54.0
## A camp wants level ground for the same reason a spirit zone does.
@export var max_slope: float = 0.26
## Raiders are placed in a ring this far from the fire.
@export var raider_ring: float = 2.6
## Hit points scale with distance from home, so the far camps are the hard ones.
@export var far_camp_hp_bonus: float = 0.5

## The band of the map's half-extent a camp may sit in, as fractions. Named because two
## other things key off them: the difficulty curve measures a camp against the furthest a
## camp can be, and that is `REACH_MAX`, not a number of metres that has to be edited
## whenever the map grows.
const REACH_MIN := 0.34
const REACH_MAX := 0.74

var _camps: Array = []
var _enemies: Array = []
var _terrain: Node
## Half the map's width, resolved once during placement. Kept as a field because the
## difficulty curve needs it too, and a curve that re-derives the map size for itself is
## a second opinion about how big the world is.
var _extent: float = 64.0
## Seeded, like the scatter and the spirit zones. A camp's own layout comes out of this
## rather than the global RNG: the ground a raider stands on decides which of them a
## blow lands on, so an unseeded camp is a world that is subtly different every launch
## — and a raid that went one way yesterday for no reason the player can see.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_terrain = get_parent().get_node_or_null("Terrain")
	if _terrain == null:
		push_warning("[camps] no terrain to place camps on")
		return
	_place()
	print("[camps] %d camps, %d raiders: %s" % [
		_camps.size(), _enemies.size(),
		", ".join(_camps.map(func(c: Dictionary) -> String:
			return "%s(%.0f m, %d raiders)" % [
				c["name"], c["distance"], int(c["raiders"])])),
	])


func _place() -> void:
	_extent = 64.0
	if _terrain.has_method("extent"):
		_extent = float(_terrain.call("extent"))
	var extent: float = _extent
	_rng.seed = camp_seed
	var rng: RandomNumberGenerator = _rng
	var attempts: int = 0
	while _camps.size() < camp_count and attempts < 900:
		attempts += 1
		var angle: float = rng.randf_range(0.0, TAU)
		# Inside the inscribed disc of the square map, so a camp's props fit.
		var reach: float = extent * rng.randf_range(REACH_MIN, REACH_MAX)
		var x: float = cos(angle) * reach
		var z: float = sin(angle) * reach
		var distance: float = Vector2(x, z).length()
		if distance < camp_clearance:
			continue
		var too_close: bool = false
		for camp: Dictionary in _camps:
			var centre: Vector3 = camp["position"]
			if Vector2(x - centre.x, z - centre.z).length() < camp_separation:
				too_close = true
				break
		if too_close:
			continue
		if _terrain.has_method("slope_at") and float(_terrain.call("slope_at", x, z)) > max_slope:
			continue
		_build(name_for(_camps.size()), Vector3(x, float(_terrain.call("surface_height_at", x, z)), z), distance)


## Camp names are a list rather than generated, because a name is flavour and flavour
## that comes out of a loop reads like one.
const NAMES: Array = [
	"Bandit Hollow", "Ashfall Camp", "The Broken Wheel",
	"Thornwatch", "Cinder Camp", "Wolfrest", "Greyridge Camp",
]


func name_for(index: int) -> String:
	return String(NAMES[index % NAMES.size()])


func _build(camp_name: String, centre: Vector3, distance: float) -> void:
	var root := Node3D.new()
	root.name = "Camp_" + camp_name.replace(" ", "")
	root.position = centre
	add_child(root)
	root.add_to_group("enemy_camp")

	var yaw: float = _rng.randf_range(0.0, TAU)
	# A fire is the anchor: it is the point the leash is measured from, so it is placed
	# first and everything else hangs off it.
	var cauldron: Node3D = _place_piece(PROPS + "Cauldron.gltf", root, 0.0, 0.0, yaw, centre)
	var glow := OmniLight3D.new()
	glow.name = "FireGlow"
	glow.light_color = Color("ff8a3c")
	glow.light_energy = 2.0
	glow.omni_range = 13.0
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 1.5, 0.0)
	root.add_child(glow)

	# The banner is what makes a camp findable: it is the tallest thing in one, and it
	# is what the signposts point you towards.
	var banner_spot: Vector2 = Vector2(cos(yaw + 1.1), sin(yaw + 1.1)) * 2.3
	_place_piece(PROPS + "Banner_1.gltf", root, banner_spot.x, banner_spot.y, yaw + 2.5, centre)
	var props: Array = ["Barrel.gltf", "Crate_Wooden.gltf", "Pot_1.gltf", "Bench.gltf", "Dummy.gltf"]
	for i in props.size():
		var angle: float = yaw + float(i) * 1.35
		var at: Vector2 = Vector2(cos(angle), sin(angle)) * _rng.randf_range(2.4, 3.8)
		_place_piece(PROPS + String(props[i]), root, at.x, at.y, _rng.randf_range(0.0, TAU), centre)

	var placed: int = 0
	for i in raiders:
		var angle: float = yaw + TAU * float(i) / float(maxi(1, raiders))
		var at: Vector2 = Vector2(cos(angle), sin(angle)) * raider_ring
		var spot := Vector3(centre.x + at.x, centre.y, centre.z + at.y)
		var enemy: Node3D = _spawn_raider(spot, distance)
		if enemy != null:
			placed += 1
	_camps.append({
		"name": camp_name,
		"position": centre,
		"distance": distance,
		"node": root,
		"fire": cauldron,
		"raiders": placed,
	})


## Places a kit piece so it sits on the ground. Every kit disagrees about where its
## origin lives, so the piece's own measured box decides: the lowest point goes on the
## surface at the spot it was placed.
func _place_piece(path: String, parent: Node3D, dx: float, dz: float, yaw: float, origin: Vector3) -> Node3D:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var piece: Node3D = scene.instantiate()
	parent.add_child(piece)
	var ground: float = float(_terrain.call("surface_height_at", origin.x + dx, origin.z + dz))
	var box: AABB = _bounds(piece)
	piece.position = Vector3(dx, ground - origin.y - box.position.y, dz)
	piece.rotation.y = yaw
	return piece


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


func _spawn_raider(spot: Vector3, distance: float) -> Node3D:
	var enemy := CharacterBody3D.new()
	enemy.name = "Raider"
	enemy.set_script(load("res://scripts/enemy/enemy.gd"))
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.86, 0.0)
	enemy.add_child(shape)
	# Set before the raider enters the tree: `_ready` fills its health from `max_hp`, so
	# a value written afterwards would leave a forward camp as soft as the first one.
	#
	# Both curves are fractions of how far a camp *can* be, not of a fixed number of
	# metres. They used to divide by 200 and by 90, and those constants were the map's
	# size written down twice: on a 112 m half-extent the camps topped out at 41% of the
	# bonus, so the difficulty curve was really a third of a curve, and growing the map
	# would have quietly flattened what was left of it. `reach_max` is the same fraction
	# the placer draws from, which is what keeps the far camp exactly as far as it says.
	var reach_max: float = maxf(1.0, _extent * REACH_MAX)
	var scale: float = 1.0 + far_camp_hp_bonus * clampf(distance / reach_max, 0.0, 1.0)
	enemy.set("max_hp", 55.0 * scale)
	enemy.set("crystals", 2 + int(round(distance / (reach_max * 0.55))))
	enemy.set("home", spot)
	enemy.position = spot
	add_child(enemy)
	_enemies.append(enemy)
	return enemy


# -------------------------------------------------------------------- querying

func camps() -> Array:
	return _camps.duplicate()


func enemies() -> Array:
	return _enemies.duplicate()


func raider_count() -> int:
	return _enemies.size()


## Nearest camp to a world position, or an empty dictionary. Used by the signposts.
func nearest_camp(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for camp: Dictionary in _camps:
		var centre: Vector3 = camp["position"]
		var d: float = Vector2(position.x - centre.x, position.z - centre.z).length()
		if d < best_distance:
			best_distance = d
			best = camp
	return best
