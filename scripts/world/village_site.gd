extends Node3D
## One village, standing in the world.
##
## A village is not a camp with nicer props. A camp is *pressure* — a fire, a banner and people
## who want you gone — and a village is the opposite of that: the one kind of place on the map
## where the game is not about you. So the things that make it read as one are all about being
## *lived in*: a levelled square, a palisade mended in two different woods, a well, a market
## with somebody's crates still stacked on it, a beacon so you can see the way home from a hill,
## and a watch house with a door that can be shut.
##
## Two frames live in this file and mixing them is the one way to get it badly wrong, so it is
## worth stating: **props, the square, the palisade and the beacon are in the site's own frame**
## (`position` on the site node carries the x/z, the y values are already world heights), while
## **`_local()` returns world** — it is what the people, the guards' beats and the registry are
## given, because a walker's position must not care where its parent happens to be.
##
## The assembly is the same trick the home camp uses — every piece is placed by its **measured
## bounding box** rather than by its origin, so the kits' disagreement about where an origin
## lives never has to be known. What is new here is that the ground is *flattened first*: the
## plaza is a disc at the highest ground in the village, with a stone skirt down to the terrain,
## so the huts, the stalls and the fences can be placed at one height instead of each one
## sitting at a different angle on a hillside. A square is a *made* thing, and the making is
## visible.
##
## The village is also a sanctuary. It registers itself with `Haven`, so raiders will not follow
## anybody inside the palisade — and the guards walk *outside* it, which is where the fighting
## is meant to happen.

const PROPS := "res://assets/props/"
const STRUCTURES := "res://assets/structures/"
const VillageNpcScript := preload("res://scripts/world/village_npc.gd")
const GuardScript := preload("res://scripts/world/guard.gd")

@export var village_id: String = ""

## Handed in by the placer rather than looked up, because a site is a *child* of the placer:
## `get_parent().get_node_or_null("Terrain")` from inside here asks the Villages node, which
## has no Terrain, and the whole village then quietly declines to exist.
var terrain_node: Node = null

var _terrain: Node
var _def: Dictionary = {}
var _centre: Vector3 = Vector3.ZERO
var _level: float = 0.0
var _yaw: float = 0.0
var _radius: float = 17.0
var _people: Array = []
var _guards: Array = []
var _lockup_door: CollisionShape3D
var _pieces: int = 0
var _blocks: int = 0


func _ready() -> void:
	_terrain = terrain_node if terrain_node != null else get_parent().get_node_or_null("Terrain")
	if _terrain == null:
		push_warning("[village] no terrain to build on")
		return
	_def = Villages.def(village_id)
	if _def.is_empty():
		push_warning("[village] unknown village '%s'" % village_id)
		return
	if not bool(_terrain.call("is_generated")):
		_terrain.call("generate")
	_centre = _pick_ground()
	_radius = float(_def["radius"])
	_level = _level_for(_centre, _radius)
	# The one line that has to happen before a single piece is placed. Everything a village
	# builds is built in the site's own frame — the square and the beacon around (0, 0), the
	# props by bare offsets — and only the *heights* are absolute, because the terrain function
	# is what returns them. So the node carries the x/z and its y stays zero. A site that is
	# never moved builds its plaza over the middle of the map: three villages stacked on the
	# spawn camp, a square of made ground ten metres above the fire, and every downward ray in
	# the world landing on a village floor instead of the terrain.
	position = Vector3(_centre.x, 0.0, _centre.z)
	# In the group so that the things that need to *find* a village — the raids, looking for the
	# gate they came for — can ask the site that built it rather than re-deriving the same disc
	# from the registry and getting the gate on the wrong side of the fence.
	add_to_group("village_site")
	_build_square()
	_build_palisade()
	_build_huts()
	_build_market()
	_build_specialty()
	_build_lockup()
	_build_beacon()
	_build_props()
	_place_people()
	_place_guards()
	_register()
	print("[village] %s at %.0f m: %d pieces, %d blockers, %d people, %d guards" % [
		String(_def["name"]), Vector2(_centre.x, _centre.z).length(),
		_pieces, _blocks, _people.size(), _guards.size(),
	])


## Stands on level ground beside the road it belongs to, for the reason every placement in this
## project rejection-samples: the terrain is procedural, and a village square built on a
## hillside is a village square that slides off it.
func _pick_ground() -> Vector3:
	# The last village is the tower's, and it is placed *against* the tower rather than by its
	# own road: "at the foot of the tower" is the whole point of the place, and two independent
	# placements would have put it a hundred metres up a different road.
	if bool(_def.get("at_tower", false)):
		var tower: Node = get_tree().get_first_node_in_group("tower_site")
		if tower != null and tower.has_method("base_position"):
			var at: Vector3 = tower.call("base_position")
			# A turn about the map's centre keeps the same distance out and puts the village
			# beside the tower instead of inside it.
			var angle: float = float(_def.get("beside", 0.20))
			var cos_a: float = cos(angle)
			var sin_a: float = sin(angle)
			var x: float = at.x * cos_a - at.z * sin_a
			var z: float = at.x * sin_a + at.z * cos_a
			return Vector3(x, float(_terrain.call("surface_height_at", x, z)), z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6111 + village_id.hash()
	var extent: float = float(_terrain.call("extent"))
	var target: float = extent * float(_def["reach"])
	var roads: Array = _terrain.call("roads")
	var road: int = int(_def["road"])
	var best := Vector3.ZERO
	var best_score: float = INF
	for attempt in 40:
		var at := Vector2(0.0, target)
		if road >= 0 and road < roads.size():
			at = _point_along(roads[road]["points"], target)
		# Beside the road, not on it: the road is what the village is *on*, and a square in the
		# middle of the traffic is a square nobody built.
		var sideways := Vector2(at.y, -at.x).normalized() * float(_def["offset"])
		var spin: float = rng.randf_range(-0.7, 0.7)
		var offset: Vector2 = sideways.rotated(spin)
		var x: float = at.x + offset.x
		var z: float = at.y + offset.y
		var score: float = _worst_slope(x, z, _radius_guess())
		if score < best_score:
			best_score = score
			best = Vector3(x, float(_terrain.call("surface_height_at", x, z)), z)
		if score < 0.06:
			break
	return best


func _radius_guess() -> float:
	return float(_def.get("radius", 17.0))


## The point on a road's centre line at a distance along it.
func _point_along(points: PackedVector2Array, want: float) -> Vector2:
	var travelled: float = 0.0
	var at := Vector2(points[0])
	for i in range(1, points.size()):
		var step: float = points[i - 1].distance_to(points[i])
		if travelled + step >= want:
			return points[i - 1].lerp(points[i], (want - travelled) / maxf(0.1, step))
		travelled += step
		at = points[i]
	return at


## The steepest ground anywhere in the disc, so the search can prefer a flat site.
func _worst_slope(x: float, z: float, radius: float) -> float:
	var worst: float = 0.0
	for i in 9:
		var angle: float = TAU * float(i) / 9.0
		for r: float in [0.0, radius * 0.5, radius]:
			worst = maxf(worst, float(_terrain.call(
				"slope_at", x + cos(angle) * r, z + sin(angle) * r
			)))
	return worst


## The highest ground in the village disc, plus a little. The square is built at this height, so
## every hut and fence sits on the same level surface and the skirt covers the difference.
func _level_for(centre: Vector3, radius: float) -> float:
	var top: float = float(_terrain.call("surface_height_at", centre.x, centre.z))
	for i in 12:
		var angle: float = TAU * float(i) / 12.0
		for r: float in [radius * 0.5, radius]:
			top = maxf(top, float(_terrain.call(
				"surface_height_at", centre.x + cos(angle) * r, centre.z + sin(angle) * r
			)))
	return top + 0.25


# ------------------------------------------------------------------ the square

func _build_square() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Square"
	var mesh := CylinderMesh.new()
	mesh.top_radius = _radius
	mesh.bottom_radius = _radius + 0.6
	# Deep enough to bury the difference between the highest and lowest ground in the disc, so
	# no gap can open under the palisade on the downhill side.
	mesh.height = 6.0
	mesh.radial_segments = 40
	plate.mesh = mesh
	plate.material_override = _mat(Color("77694f"), 0.95)
	plate.position = Vector3(0.0, _level - 3.0, 0.0)
	add_child(plate)

	var body := StaticBody3D.new()
	body.name = "SquareBody"
	add_child(body)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = _radius
	cylinder.height = 6.0
	shape.shape = cylinder
	shape.position = plate.position
	body.add_child(shape)
	_blocks += 1

	# A ring of stone at the rim, which is the edge of the made ground and the thing that stops
	# the square reading as a disc of brown floating on a hillside.
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = _radius - 0.5
	torus.outer_radius = _radius + 0.25
	rim.mesh = torus
	rim.material_override = _mat(Color("5b5a58"), 0.95)
	rim.position = Vector3(0.0, _level + 0.06, 0.0)
	add_child(rim)


## The palisade, with a wide gate on the road side. The gate is *the* thing that makes a village
## a place: two banners, two torches and an opening you can see the light through.
func _build_palisade() -> void:
	# One panel per 3.6 m of fence, so the wall follows the village rather than the other way
	# round. A fixed count is fine while every village is the same size and silently leaves a
	# bigger one with holes in its palisade the moment they are not — which is exactly what
	# happened when Towerfall and Stonewatch grew.
	var count: int = maxi(30, int(round(TAU * _radius / 3.6)))
	var arc: float = TAU / float(count)
	# The gate faces the way the road came in, which is where the player arrives from.
	var gate_angle: float = _yaw
	# And the gate is a gate rather than a gap: wider in a bigger place, in proportion.
	var gap: int = maxi(3, int(round(float(count) * 0.09)))
	for k in count:
		var delta: float = wrapf(arc * float(k) - gate_angle, -PI, PI)
		if absf(delta) < arc * float(gap) * 0.5:
			continue
		var theta: float = arc * float(k)
		var x: float = cos(theta) * _radius
		var z: float = sin(theta) * _radius
		_place(STRUCTURES + "Prop_WoodenFence_Single.gltf", x, z, rad_to_deg(theta) + 90.0, _level)
	var post := STRUCTURES + "Prop_WoodenFence_Extension1.gltf"
	for k in [gap + 1, gap + 2, count - gap - 1, count - gap - 2]:
		var theta: float = arc * float(k)
		_place(post, cos(theta) * _radius, sin(theta) * _radius, rad_to_deg(theta) + 90.0, _level)
	# Banners and torches either side of the opening.
	for side: float in [-1.0, 1.0]:
		var a: float = gate_angle + side * arc * float(gap) * 0.55
		_place(PROPS + "Banner_1.gltf", cos(a) * (_radius - 0.4), sin(a) * (_radius - 0.4),
			rad_to_deg(a) + 180.0, _level)
		_place(PROPS + "Torch_Metal.gltf", cos(a) * (_radius - 1.8), sin(a) * (_radius - 1.8),
			0.0, _level)
		var glow := OmniLight3D.new()
		glow.light_color = Color("ffb066")
		glow.light_energy = 1.1
		glow.omni_range = 12.0
		glow.shadow_enabled = false
		glow.position = Vector3(cos(a) * (_radius - 1.8), _level + 2.4, sin(a) * (_radius - 1.8))
		add_child(glow)


## Four or five roofs, laid around the square so the middle stays open. Each is the camp's hut
## assembled the same way — modular walls read off the kit's own measured height — but smaller,
## because these are houses rather than a hall.
func _build_huts() -> void:
	var count: int = int(_def.get("huts", 4))
	var spot: float = 0.62
	for i in count:
		var angle: float = _yaw + PI + TAU * (float(i) + 0.5) / float(count) * 0.82
		var r: float = _radius * spot
		var centre := Vector2(cos(angle) * r, sin(angle) * r)
		_hut(centre, rad_to_deg(angle) + 180.0)


func _hut(centre: Vector2, yaw_degrees: float) -> void:
	var yaw: float = deg_to_rad(yaw_degrees)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(cos(yaw), -sin(yaw))
	var floor_path := STRUCTURES + "Floor_WoodLight.gltf"
	var wall := STRUCTURES + "Wall_Plaster_Straight.gltf"
	var wall_top: float = _level
	for ix: float in [-1.0, 1.0]:
		for iz: float in [-1.0, 1.0]:
			var at: Vector2 = centre + side * ix + fwd * iz
			_place(floor_path, at.x, at.y, yaw_degrees, _level, false)
	var first: Node3D = _place(wall, (centre + side * -1.0 + fwd * -2.0).x,
		(centre + side * -1.0 + fwd * -2.0).y, yaw_degrees, _level)
	wall_top = _level + _size_of(first).y
	var door_at: Vector2 = centre + side * -1.0 + fwd * 2.0
	var door: Node3D = _place(STRUCTURES + "Wall_Plaster_Door_Round.gltf",
		door_at.x, door_at.y, yaw_degrees, _level, false)
	_door_wall(door)
	_place(wall, (centre + side * 1.0 + fwd * 2.0).x, (centre + side * 1.0 + fwd * 2.0).y,
		yaw_degrees, _level)
	_place(STRUCTURES + "Wall_Plaster_Window_Wide_Round.gltf",
		(centre + side * 1.0 + fwd * -2.0).x, (centre + side * 1.0 + fwd * -2.0).y,
		yaw_degrees, _level)
	for iz: float in [-1.0, 1.0]:
		for ix: float in [-2.0, 2.0]:
			_place(wall, (centre + side * ix + fwd * iz).x, (centre + side * ix + fwd * iz).y,
				yaw_degrees + 90.0, _level)
	_place(STRUCTURES + "Roof_RoundTiles_4x4.gltf", centre.x, centre.y, yaw_degrees, wall_top)
	# A vine and a lamp, so no two houses are quite the same building.
	_place(STRUCTURES + "Prop_Vine1.gltf", (centre + fwd * -2.4).x, (centre + fwd * -2.4).y,
		yaw_degrees, _level, false)


func _build_market() -> void:
	var angle: float = _yaw + 2.2
	var at := Vector2(cos(angle), sin(angle)) * (_radius * 0.52)
	var table: Node3D = _place(PROPS + "Table_Large.gltf", at.x, at.y, rad_to_deg(angle) + 90.0, _level)
	_place(PROPS + "Banner_1.gltf", at.x + 1.6, at.y + 1.2, rad_to_deg(angle) + 90.0, _level)
	_place(PROPS + "Crate_Wooden.gltf", at.x - 1.9, at.y + 0.6, 14.0, _level)
	_place(PROPS + "Barrel.gltf", at.x + 0.4, at.y - 2.0, 0.0, _level)
	_place(PROPS + "Barrel.gltf", at.x + 1.5, at.y - 2.4, 0.0, _level)
	_place(PROPS + "Pot_1.gltf", at.x - 1.2, at.y + 2.2, 0.0, _level)
	_place(PROPS + "Scroll_1.gltf", at.x, at.y, 24.0,
		_level + _size_of(table).y + 0.01, false)

	# The well, in the middle of the square, which is what a square is *for*.
	var well: Node3D = _place(PROPS + "Cauldron.gltf", 0.0, 0.0, 0.0, _level)
	if well != null:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.0
		torus.outer_radius = 1.5
		ring.mesh = torus
		ring.material_override = _mat(Color("6a675f"), 0.9)
		ring.position = Vector3(0.0, 0.1, 0.0)
		well.add_child(ring)
		_place(PROPS + "Stool.gltf", 2.4, 1.0, 0.0, _level)


## Whatever the village is *for*. This is the building the place is named after in the player's
## head: the forge at Stonewatch, the herbalist's house at Hollowmere, the scholar's at the
## tower's foot. Every village having the same four buildings is how three villages become one.
func _build_specialty() -> void:
	match String(_def.get("specialty", "")):
		"smith":
			var angle: float = _yaw - 1.5
			var at := Vector2(cos(angle), sin(angle)) * (_radius * 0.62)
			var anvil: Node3D = _place(PROPS + "Anvil.gltf", at.x, at.y, 20.0, _level)
			_place(PROPS + "Whetstone.gltf", at.x + 1.4, at.y + 0.4, 30.0, _level)
			_place(PROPS + "WeaponStand.gltf", at.x - 1.6, at.y + 1.0, -60.0, _level)
			_place(PROPS + "Bench.gltf", at.x + 0.4, at.y + 2.2, 0.0, _level)
			_place(PROPS + "Banner_1.gltf", at.x + 2.4, at.y - 1.4, 0.0, _level)
			if anvil != null:
				var glow := OmniLight3D.new()
				glow.light_color = Color("ff7a3c")
				glow.light_energy = 1.9
				glow.omni_range = 9.0
				glow.shadow_enabled = false
				glow.position = Vector3(0.0, 0.6, 0.0)
				anvil.add_child(glow)
		"healer":
			var angle: float = _yaw + 3.4
			var at := Vector2(cos(angle), sin(angle)) * (_radius * 0.58)
			_place(PROPS + "Table_Large.gltf", at.x, at.y, 0.0, _level)
			_place(PROPS + "Pot_1.gltf", at.x + 0.8, at.y + 0.9, 0.0, _level)
			_place(PROPS + "Pot_1.gltf", at.x - 0.9, at.y + 0.7, 0.0, _level)
			_place(PROPS + "Barrel.gltf", at.x + 1.8, at.y - 1.2, 0.0, _level)
			_place(PROPS + "Stool.gltf", at.x - 0.2, at.y + 1.9, 0.0, _level)
		"scholar":
			var angle: float = _yaw + 0.6
			var at := Vector2(cos(angle), sin(angle)) * (_radius * 0.60)
			_place(PROPS + "Bookcase_2.gltf", at.x, at.y, rad_to_deg(angle) + 180.0, _level)
			_place(PROPS + "Table_Large.gltf", at.x + 1.0, at.y + 1.8, 0.0, _level)
			_place(PROPS + "Scroll_1.gltf", at.x + 0.6, at.y + 2.0, 12.0, _level + 0.9, false)
			_place(PROPS + "Stool.gltf", at.x + 2.0, at.y + 0.6, 0.0, _level)


## A two-by-two watch house with a door that `Law` can shut. The only building in the world with
## a door that means anything.
func _build_lockup() -> void:
	var angle: float = _yaw + PI * 0.62
	var at := Vector2(cos(angle), sin(angle)) * (_radius * 0.60)
	var yaw_degrees: float = rad_to_deg(angle) + 180.0
	var yaw: float = deg_to_rad(yaw_degrees)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(cos(yaw), -sin(yaw))
	var wall := STRUCTURES + "Wall_Plaster_Straight.gltf"
	for ix: float in [-1.0, 1.0]:
		for iz: float in [-1.0, 1.0]:
			var tile: Vector2 = at + side * ix + fwd * iz
			_place(STRUCTURES + "Floor_WoodLight.gltf", tile.x, tile.y, yaw_degrees, _level, false)
	var first: Node3D = _place(wall, (at + side * -1.0 + fwd * -2.0).x,
		(at + side * -1.0 + fwd * -2.0).y, yaw_degrees, _level)
	var wall_top: float = _level + _size_of(first).y
	var door_at: Vector2 = at + side * 1.0 + fwd * 2.0
	var door: Node3D = _place(STRUCTURES + "Wall_Plaster_Door_Round.gltf",
		door_at.x, door_at.y, yaw_degrees, _level, false)
	_lockup_door = _door_shape(door, false)
	for iz: float in [-1.0, 1.0]:
		for ix: float in [-2.0, 2.0]:
			_place(wall, (at + side * ix + fwd * iz).x, (at + side * ix + fwd * iz).y,
				yaw_degrees + 90.0, _level)
	_place(wall, (at + side * 1.0 + fwd * -2.0).x, (at + side * 1.0 + fwd * -2.0).y,
		yaw_degrees, _level)
	_place(STRUCTURES + "Roof_RoundTiles_4x4.gltf", at.x, at.y, yaw_degrees, wall_top)
	_place(PROPS + "Torch_Metal.gltf", (at + side * 2.2 + fwd * 2.2).x,
		(at + side * 2.2 + fwd * 2.2).y, 0.0, _level)


## The way home, visible from a hill. The same idiom the spirit zones use — a column of light —
## because it is the one thing in this world that already means "there is something there".
func _build_beacon() -> void:
	var tint: Color = _def["colour"]
	var column := MeshInstance3D.new()
	column.name = "Beacon"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.7
	mesh.bottom_radius = 1.6
	mesh.height = 16.0
	mesh.radial_segments = 16
	column.mesh = mesh
	column.material_override = _glow(tint, 0.22)
	column.position = Vector3(0.0, _level + 8.0, 0.0)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(column)

	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.5
	light.omni_range = 26.0
	light.shadow_enabled = false
	light.position = Vector3(0.0, _level + 3.0, 0.0)
	add_child(light)

	# A signpost at the gate naming the place, which is the cheapest thing in the world that
	# makes an arrival feel like an arrival.
	var board := Label3D.new()
	board.name = "VillageSign"
	board.text = String(_def["name"]).to_upper()
	board.font_size = 140
	board.pixel_size = 0.0075
	board.outline_size = 24
	board.outline_modulate = Color(0.05, 0.05, 0.07)
	board.modulate = tint.lightened(0.45)
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.position = Vector3(cos(_yaw) * (_radius + 3.0), _level + 3.4, sin(_yaw) * (_radius + 3.0))
	add_child(board)


func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711 + village_id.hash()
	var kinds: Array = [
		PROPS + "Barrel.gltf", PROPS + "Crate_Wooden.gltf", PROPS + "Pot_1.gltf",
		PROPS + "Bench.gltf", PROPS + "Stool.gltf",
	]
	for i in int(round(10.0 * _radius / 17.0)):
		var angle: float = rng.randf_range(0.0, TAU)
		var r: float = sqrt(rng.randf()) * _radius * 0.78
		var kind: String = String(kinds[rng.randi_range(0, kinds.size() - 1)])
		_place(kind, cos(angle) * r, sin(angle) * r, rng.randf_range(0.0, 360.0), _level)


# ---------------------------------------------------------------------- people

func _place_people() -> void:
	for entry: Dictionary in Villages.people_of(village_id):
		var npc: Node = VillageNpcScript.new()
		npc.name = String(entry["id"]).capitalize()
		npc.set("person_id", String(entry["id"]))
		npc.set("village_id", village_id)
		npc.set("npc_name", String(entry["name"]))
		npc.set("role", String(entry["role"]))
		npc.set("robe_color", entry["colour"])
		npc.set("target_height", 1.68)
		add_child(npc)
		var at: Vector2 = entry.get("at", Vector2.ZERO)
		var spot := _local(at)
		npc.global_position = Vector3(spot.x, _level, spot.y)
		npc.set("facing_degrees", rad_to_deg(atan2(-at.x, -at.y)))
		_people.append(npc)


## The watch scales with the fence. Two men on a twenty-two metre square is a village; two men
## walking the outside of a thirty-three metre one is a village that has already been robbed.
## This is also what the raids are measured against, so a bigger village is a harder night.
func _place_guards() -> void:
	var count: int = 2 + int(_radius / 14.0)
	for i in count:
		var guard: Node = GuardScript.new()
		guard.name = "%sGuard%d" % [village_id.capitalize(), i]
		guard.set("village_id", village_id)
		guard.set("guard_name", "%s Watch" % String(_def["name"]))
		guard.set("target_height", 1.78)
		guard.set("robe_color", (Color(_def["colour"]) as Color).darkened(0.35))
		add_child(guard)
		var angle: float = _yaw + (float(i) - 0.5) * 1.2
		var r: float = _radius + 3.5
		var spot := Vector2(cos(angle), sin(angle))
		var post := _local(Vector2(spot.x * r, spot.y * r))
		guard.global_position = Vector3(post.x, _level, post.y)
		# The beat: out past the gate, a circuit of the fence, and back. Walked on the terrain,
		# not on the square, because the guards' business is outside.
		var route := PackedVector2Array()
		for k in 10:
			var a: float = _yaw + float(k) * TAU / 10.0
			var rr: float = _radius + 4.0 + (1.6 if k % 2 == 0 else 0.0)
			route.append(_local(Vector2(cos(a) * rr, sin(a) * rr)))
		guard.set("route", route)
		_guards.append(guard)


func _register() -> void:
	var flat := Vector2(_centre.x, _centre.z)
	Villages.register_site(village_id, String(_def["name"]), flat, _radius + 3.0)
	Haven.register({
		"id": village_id,
		"name": String(_def["name"]),
		"kind": "village",
		"centre": Vector3(_centre.x, _level, _centre.z),
		"radius": _radius - 0.6,
		"wake": Vector3(_centre.x, _level + 1.2, _centre.z),
		"enter": String(_def["flavour"]),
		"exit": "You walk out through %s's gate." % String(_def["name"]),
	})
	tree_exiting.connect(func() -> void: Haven.unregister(village_id))
	if _lockup_door != null:
		var inside := Vector3(_centre.x, _level + 1.0, _centre.z)
		var outside := Vector3(
			_centre.x + cos(_yaw) * (_radius + 4.0), _level + 1.0,
			_centre.z + sin(_yaw) * (_radius + 4.0)
		)
		Law.register_cell(village_id, inside, outside, _lockup_door)


func _local(at: Vector2) -> Vector2:
	return Vector2(_centre.x + at.x, _centre.z + at.y)


# -------------------------------------------------------------------- placement

## Places a kit piece so its box is centred on (x, z) and its lowest point rests on `floor_y`.
## The rule the whole project places props by, and the reason a piece can be swapped for another
## from the same kit without a hand-tuned height.
func _place(path: String, x: float, z: float, yaw_degrees: float, floor_y: float,
		solid: bool = true) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = path.get_file().get_basename()
	var scene: PackedScene = load(path)
	if scene == null:
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


## A doorway framed by three boxes, so the opening stays open. Used by every house with a door.
func _door_wall(door: Node3D) -> void:
	_door_shape(door, true)


## Returns the lintel piece, which is the collision `Law` opens and shuts for the watch house.
func _door_shape(door: Node3D, solid_jambs: bool) -> CollisionShape3D:
	var size: Vector3 = _size_of(door)
	var depth: float = size.z * 0.55
	var jamb: float = size.x * 0.20
	if solid_jambs:
		_block(door, AABB(Vector3(-size.x * 0.5, 0.0, -depth * 0.5), Vector3(jamb, size.y, depth)))
		_block(door, AABB(Vector3(size.x * 0.5 - jamb, 0.0, -depth * 0.5),
			Vector3(jamb, size.y, depth)))
	var lintel := StaticBody3D.new()
	lintel.name = "Lintel"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x - jamb * 2.0, size.y * 0.32, depth)
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.84, 0.0)
	lintel.add_child(shape)
	door.add_child(lintel)
	_blocks += 1
	return shape


func _size_of(pivot: Node3D) -> Vector3:
	return pivot.get_meta("size", Vector3.ZERO)


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


func _mat(tint: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = roughness
	material.metallic = 0.0
	return material


func _glow(tint: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	const EMISSION_SHARE := 0.32
	material.albedo_color = Color(
		tint.r * (1.0 - EMISSION_SHARE), tint.g * (1.0 - EMISSION_SHARE),
		tint.b * (1.0 - EMISSION_SHARE), alpha)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = EMISSION_SHARE
	return material


# --------------------------------------------------------------------- querying

## A point on the line through the gate, `metres` outside the palisade — or negative for inside
## it. The gate is the one part of a village that is a *direction* rather than a place, and the
## two things that care are the raid that comes up the road and anything that wants to put a body
## down where a body arriving would be standing.
##
## The height is the terrain's, not the plaza's: eight metres out is the road, and the road is
## not flat.
func gate_point(metres: float) -> Vector3:
	var x: float = _centre.x + cos(_yaw) * (_radius + metres)
	var z: float = _centre.z + sin(_yaw) * (_radius + metres)
	var y: float = _level
	if _terrain != null and _terrain.has_method("surface_height_at"):
		y = float(_terrain.call("surface_height_at", x, z))
	return Vector3(x, y, z)


func centre() -> Vector3:
	return _centre


func level_height() -> float:
	return _level


func people() -> Array:
	return _people.duplicate()


func guards() -> Array:
	return _guards.duplicate()


func radius() -> float:
	return _radius


func summary() -> Dictionary:
	return {
		"id": village_id, "pieces": _pieces, "blocks": _blocks,
		"people": _people.size(), "guards": _guards.size(),
	}
