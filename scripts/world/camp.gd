extends Node3D
## Builds the home camp at the foot of the mountain: a hut, a fence ring around
## it, a training yard and a fire circle, all from the CC0 Medieval Village and
## Fantasy Props kits.
##
## Two things make this work without hand-typing hundreds of transforms:
##
##   * Every piece is placed by its *measured* bounding box, never by its origin.
##     These kits disagree about where the origin lives — a roof's is inside its
##     own volume, a banner's is halfway up the pole — so `_place` re-centres the
##     footprint on the requested spot and drops the bounding box's lowest point
##     onto the requested floor. A roof is then simply "sit the eaves on the wall
##     top", and no model's authoring convention has to be known.
##   * Pieces are stacked off each other's reported heights, so the hut's roof
##     follows whatever the wall piece actually measures rather than a number
##     copied out of the kit's readme.
##
## Collision is one box per piece, sized from the same bounding box, with the
## doorway given three boxes instead so you can walk in through it.

const PROPS := "res://assets/props/"
const STRUCTURES := "res://assets/structures/"

## Radius of the fence ring. The terrain is levelled inside
## `plateau_flat_fraction * plateau_radius` = 9.9 units, so the ring sits just
## outside it and follows the ground where it gently falls away. That leaves the
## training yard — everything inside the ring — dead level to run and strike on.
const FENCE_RADIUS := 10.5
const FENCE_COUNT := 32

@export var enabled: bool = true
## Skips building the camp, for comparing the raw terrain.
@export var fire_flicker: bool = true

var _terrain: Node
var _pieces: int = 0
var _blocks: int = 0
var _posts: int = 0
var _fires: Array[OmniLight3D] = []
var _fire_phase: float = 0.0


func _ready() -> void:
	if not enabled:
		return
	_terrain = get_node_or_null("../Terrain")
	if _terrain == null:
		push_warning("[camp] no Terrain sibling to build on")
		return
	if not bool(_terrain.call("is_generated")):
		_terrain.call("generate")

	var started: int = Time.get_ticks_msec()
	# The hut's local +Z faces the fire at the origin, so its door opens onto the
	# camp rather than into the hillside behind it.
	var hut_centre := Vector2(-4.8, -3.4)
	var hut_yaw: float = rad_to_deg(atan2(-hut_centre.x, -hut_centre.y))
	_build_hut(hut_centre, hut_yaw)
	_build_fence_ring()
	_build_training_yard()
	_build_fire_circle()
	_build_store()
	_build_posts()
	print("[camp] %d pieces, %d blockers, %d posts in %d ms" % [
		_pieces, _blocks, _posts, Time.get_ticks_msec() - started,
	])


func _process(delta: float) -> void:
	if not fire_flicker or _fires.is_empty():
		return
	# Two out-of-phase sines beat a single one: the light never settles into an
	# obvious pulse, which is all a campfire needs to read as alive.
	_fire_phase += delta
	for i in _fires.size():
		var phase: float = _fire_phase * 6.0 + float(i) * 2.3
		_fires[i].light_energy = 1.7 * (0.86 + 0.10 * sin(phase) + 0.06 * sin(phase * 2.7))


# ------------------------------------------------------------------- placement

## Places one kit piece so that its bounding box is centred on (x, z) and its
## lowest point rests on `floor_y`, then gives it a collision box.
##
## Returns the pivot, which carries the piece's measured size as metadata so
## callers can stack the next piece on top of it.
func _place(path: String, x: float, z: float, yaw_degrees: float, floor_y: float,
		solid: bool = true) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = path.get_file().get_basename()
	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("[camp] missing piece %s" % path)
		pivot.set_meta("size", Vector3.ZERO)
		return pivot
	var piece: Node3D = scene.instantiate()
	pivot.add_child(piece)
	var bounds: AABB = _bounds(piece)
	piece.position = -bounds.position - bounds.size * Vector3(0.5, 0.0, 0.5)
	pivot.position = Vector3(x, floor_y, z)
	pivot.rotation.y = deg_to_rad(yaw_degrees)
	add_child(pivot)
	pivot.set_meta("size", bounds.size)

	_pieces += 1
	if solid:
		_block(pivot, AABB(Vector3(-bounds.size.x * 0.5, 0.0, -bounds.size.z * 0.5), bounds.size))
	return pivot


## Adds a static box to a placed piece. The box is in the pivot's own frame: the
## origin is the centre of the footprint and y = 0 is the piece's lowest point,
## which is where the piece's bounding box now sits.
func _block(pivot: Node3D, box: AABB) -> void:
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return
	var body := StaticBody3D.new()
	body.name = "Blocker"
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = box.size
	shape.shape = cube
	shape.position = box.position + box.size * 0.5
	body.add_child(shape)
	pivot.add_child(body)
	_blocks += 1


func _size_of(pivot: Node3D) -> Vector3:
	return pivot.get_meta("size", Vector3.ZERO)


## Highest surface height over a small footprint, so a building's floor rests on
## top of the ground everywhere rather than being buried on its uphill corner.
func _base_for(x: float, z: float, half: float) -> float:
	var top: float = -INF
	for i in 3:
		for j in 3:
			top = maxf(top, float(_terrain.call(
				"surface_height_at",
				x + lerpf(-half, half, float(i) * 0.5),
				z + lerpf(-half, half, float(j) * 0.5)
			)))
	return top + 0.06


func _ground(x: float, z: float) -> float:
	return float(_terrain.call("surface_height_at", x, z))


# ------------------------------------------------------------------------ hut

## A 4x4 hut from 2-unit modular walls: four floor tiles, eight wall pieces (one
## a doorway, two windows) and one roof.
func _build_hut(centre: Vector2, yaw_degrees: float) -> void:
	var yaw: float = deg_to_rad(yaw_degrees)
	var fwd := Vector2(sin(yaw), cos(yaw))   # the hut's local +Z, in world XZ
	var side := Vector2(cos(yaw), -sin(yaw)) # the hut's local +X
	var base: float = _base_for(centre.x, centre.y, 2.6)
	var floor_path := STRUCTURES + "Floor_WoodLight.gltf"

	# Floor: four 2x2 tiles. A wood plank 2 cm thick is a terrible thing to stand
	# on, so the blocker beneath is given some depth.
	for ix: float in [-1.0, 1.0]:
		for iz: float in [-1.0, 1.0]:
			var at: Vector2 = centre + side * ix + fwd * iz
			var tile: Node3D = _place(floor_path, at.x, at.y, yaw_degrees, base, false)
			_block(tile, AABB(Vector3(-1.0, -0.5, -1.0), Vector3(2.0, 0.52, 2.0)))

	# Walls. The pieces running along local Z need a quarter turn on top of the
	# hut's own yaw, which is the whole trick to assembling a modular kit.
	var straight := STRUCTURES + "Wall_Plaster_Straight.gltf"
	var window_piece := STRUCTURES + "Wall_Plaster_Window_Wide_Round.gltf"
	# The wall pieces all share the same height; read it off one of them so the
	# roof follows the kit rather than a constant copied into this file.
	var wall_top: float = base + _size_of(
		_place(straight, _at(centre, side, fwd, -1.0, -2.0).x,
			_at(centre, side, fwd, -1.0, -2.0).y, yaw_degrees, base)
	).y

	# The doorway is on the local +Z wall, the one facing the camp, and it gets
	# three boxes instead of one so the opening stays open.
	var door_at: Vector2 = _at(centre, side, fwd, -1.0, 2.0)
	var door: Node3D = _place(STRUCTURES + "Wall_Plaster_Door_Round.gltf",
		door_at.x, door_at.y, yaw_degrees, base, false)
	_door_blockers(door)

	var south_east: Vector2 = _at(centre, side, fwd, 1.0, 2.0)
	_place(straight, south_east.x, south_east.y, yaw_degrees, base)
	var north_east: Vector2 = _at(centre, side, fwd, 1.0, -2.0)
	_place(window_piece, north_east.x, north_east.y, yaw_degrees, base)
	var west_north: Vector2 = _at(centre, side, fwd, -2.0, -1.0)
	_place(straight, west_north.x, west_north.y, yaw_degrees + 90.0, base)
	var west_south: Vector2 = _at(centre, side, fwd, -2.0, 1.0)
	_place(window_piece, west_south.x, west_south.y, yaw_degrees + 90.0, base)
	var east_north: Vector2 = _at(centre, side, fwd, 2.0, -1.0)
	_place(straight, east_north.x, east_north.y, yaw_degrees + 90.0, base)
	var east_south: Vector2 = _at(centre, side, fwd, 2.0, 1.0)
	_place(straight, east_south.x, east_south.y, yaw_degrees + 90.0, base)

	# Roof: its bounding box's lowest ring is the eave, so dropping its lowest
	# point onto the wall top seats it correctly and lets the eaves overhang.
	_place(STRUCTURES + "Roof_RoundTiles_4x4.gltf",
		centre.x, centre.y, yaw_degrees, wall_top)

	# A vine up the outside of the back wall, the only piece here that lets the
	# nature kit lean on the architecture.
	var back: Vector2 = centre + side * -1.0 + fwd * -2.35
	_place(STRUCTURES + "Prop_Vine1.gltf", back.x, back.y, yaw_degrees, base, false)

	# Inside: a bookcase against the back wall and a chest by the door.
	var shelf: Vector2 = centre + fwd * -1.55
	_place(PROPS + "Bookcase_2.gltf", shelf.x, shelf.y, yaw_degrees + 180.0, base)
	var crate: Vector2 = centre + side * 1.2 + fwd * 1.25
	_place(PROPS + "Chest_Wood.gltf", crate.x, crate.y, yaw_degrees + 150.0, base)


## World XZ of a point expressed in the hut's own frame. `side` is the hut's
## local +X in world XZ and `fwd` its local +Z, so this is just a 2D change of
## basis — which is why the hut can be dropped in at any yaw.
func _at(centre: Vector2, side: Vector2, fwd: Vector2, lx: float, lz: float) -> Vector2:
	return centre + side * lx + fwd * lz


## Framing a doorway with a single box would wall it up, so the two jambs and the
## lintel get a box each and the middle stays walkable.
func _door_blockers(door: Node3D) -> void:
	var size: Vector3 = _size_of(door)
	var depth: float = size.z * 0.55
	var jamb: float = size.x * 0.20
	_block(door, AABB(Vector3(-size.x * 0.5, 0.0, -depth * 0.5),
		Vector3(jamb, size.y, depth)))
	_block(door, AABB(Vector3(size.x * 0.5 - jamb, 0.0, -depth * 0.5),
		Vector3(jamb, size.y, depth)))
	_block(door, AABB(Vector3(-size.x * 0.5 + jamb, size.y * 0.68, -depth * 0.5),
		Vector3(size.x - jamb * 2.0, size.y * 0.32, depth)))


# ---------------------------------------------------------------- the grounds

## A ring of fence with two gaps: a narrow back door at +Z and a wide gateway at
## -Z, which is the direction the player faces on spawn.
func _build_fence_ring() -> void:
	var arc: float = TAU / float(FENCE_COUNT)
	var gaps: Array = [31, 0, 14, 15, 16, 17]
	var fence := STRUCTURES + "Prop_WoodenFence_Single.gltf"
	for k in FENCE_COUNT:
		if gaps.has(k):
			continue
		var theta: float = arc * float(k)
		var x: float = FENCE_RADIUS * sin(theta)
		var z: float = FENCE_RADIUS * cos(theta)
		# Yaw = theta because a piece's long axis is its local X, and the tangent
		# of a circle parametrised as (sin, cos) is exactly (cos, -sin).
		_place(fence, x, z, rad_to_deg(theta), _ground(x, z))


func _build_training_yard() -> void:
	_place(PROPS + "WeaponStand.gltf", 6.4, -4.7, -90.0, _ground(6.4, -4.7))
	_place(PROPS + "Whetstone.gltf", 5.0, -4.5, 25.0, _ground(5.0, -4.5))
	_place(PROPS + "Anvil.gltf", 7.7, -4.4, 8.0, _ground(7.7, -4.4))
	_place(PROPS + "Bench.gltf", 6.3, -5.9, 0.0, _ground(6.3, -5.9))


func _build_fire_circle() -> void:
	var fire_x: float = 0.0
	var fire_z: float = 4.8
	# A cauldron doubles as the fire pit, with a warm light standing in the flame.
	var cauldron: Node3D = _place(PROPS + "Cauldron.gltf",
		fire_x, fire_z, 0.0, _ground(fire_x, fire_z))
	var glow := OmniLight3D.new()
	glow.name = "FireGlow"
	glow.light_color = Color("ff9a4d")
	glow.light_energy = 1.7
	glow.omni_range = 11.0
	glow.position = Vector3(0.0, 1.15, 0.0)
	cauldron.add_child(glow)
	_fires.append(glow)

	var table: Node3D = _place(PROPS + "Table_Large.gltf", 3.7, 6.0, 90.0, _ground(3.7, 6.0))
	# The scroll sits on the table, so it is stacked off the table's own height.
	_place(PROPS + "Scroll_1.gltf", 3.6, 6.1, 30.0,
		_ground(3.7, 6.0) + _size_of(table).y + 0.01, false)
	_place(PROPS + "Bench.gltf", -3.1, 4.3, 90.0, _ground(-3.1, 4.3))
	_place(PROPS + "Bench.gltf", 3.1, 3.4, -90.0, _ground(3.1, 3.4))
	_place(PROPS + "Stool.gltf", -1.5, 6.2, 0.0, _ground(-1.5, 6.2))
	_place(PROPS + "Stool.gltf", 1.6, 6.3, 0.0, _ground(1.6, 6.3))
	_place(PROPS + "Pot_1.gltf", 0.9, 5.6, 0.0, _ground(0.9, 5.6))
	_place(PROPS + "Torch_Metal.gltf", 2.3, 4.0, 0.0, _ground(2.3, 4.0))


## A row of striking posts close enough to the spawn to be the first thing a new
## cultivator walks into, plus two in the yard proper. They are the whole reason
## ATTACK can be raised at all, so they are placed where the player already is
## rather than somewhere they have to be told about.
func _build_posts() -> void:
	for spot: Vector2 in [
		Vector2(0.9, -3.4), Vector2(2.5, -3.7), Vector2(4.1, -4.0),
		Vector2(5.7, -2.5), Vector2(7.2, -3.2),
	]:
		_build_post(spot.x, spot.y, randf_range(-25.0, 25.0))


## A post is a StaticBody3D carrying the dummy script, with the model hung off a
## pivot of its own so a blow can lean the post without moving its collision —
## the body you cannot walk through stays exactly where it was drawn.
func _build_post(x: float, z: float, yaw_degrees: float) -> Node3D:
	var post := StaticBody3D.new()
	post.name = "TrainingPost"
	post.set_script(load("res://scripts/world/training_dummy.gd"))
	post.position = Vector3(x, _ground(x, z), z)
	post.rotation.y = deg_to_rad(yaw_degrees)

	var pivot := Node3D.new()
	pivot.name = "Pivot"
	post.add_child(pivot)

	var scene: PackedScene = load(PROPS + "Dummy.gltf")
	if scene == null:
		push_warning("[camp] no dummy model for the training posts")
		return post
	var piece: Node3D = scene.instantiate()
	pivot.add_child(piece)
	var bounds: AABB = _bounds(piece)
	piece.position = -bounds.position - bounds.size * Vector3(0.5, 0.0, 0.5)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape.shape = box
	shape.position = Vector3(0.0, bounds.size.y * 0.5, 0.0)
	post.add_child(shape)

	add_child(post)
	_posts += 1
	_pieces += 1
	_blocks += 1
	return post


func _build_store() -> void:
	var barrel := PROPS + "Barrel.gltf"
	_place(barrel, -2.6, -1.0, 0.0, _ground(-2.6, -1.0))
	_place(barrel, -2.0, -2.3, 0.0, _ground(-2.0, -2.3))
	_place(barrel, -3.4, -1.9, 0.0, _ground(-3.4, -1.9))
	_place(PROPS + "Crate_Wooden.gltf", -6.4, 0.4, 12.0, _ground(-6.4, 0.4))
	_place(PROPS + "Crate_Wooden.gltf", -7.5, -0.6, -18.0, _ground(-7.5, -0.6))
	_place(PROPS + "Pot_1.gltf", -5.4, 0.9, 0.0, _ground(-5.4, 0.9))
	# Two banners flanking the wide north gateway, facing whoever walks in.
	_place(PROPS + "Banner_1.gltf", 4.9, -9.0, 0.0, _ground(4.9, -9.0))
	_place(PROPS + "Banner_1.gltf", -4.9, -9.0, 0.0, _ground(-4.9, -9.0))


# -------------------------------------------------------------------- geometry

## Bounding box of everything under `node`, in `node`'s own parent frame. Walks
## the tree because a kit piece is a scene: the mesh is rarely the root.
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


func summary() -> Dictionary:
	return {
		"pieces": _pieces, "blockers": _blocks, "lights": _fires.size(), "posts": _posts,
	}
