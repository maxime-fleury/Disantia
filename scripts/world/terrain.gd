extends StaticBody3D
## Procedural terrain: a square heightfield built from FastNoiseLite.
##
## The mesh and the collision shape are generated from the same cached height
## grid, so they cannot drift apart. One cell is exactly one world unit, which is
## what lets HeightMapShape3D (whose sample spacing is fixed at 1 unit by the
## physics server) line up perfectly with the visual mesh. To make a larger world,
## raise `grid` — the terrain is always `grid` units across.
##
## The mesh and the CollisionShape3D are created in code on _ready(). If you want
## to preview the terrain in the editor viewport, add `@tool` to the top of this
## file; it is left off so a mistake here can never break the editor.
##
## Collision defaults to HeightMapShape3D, which is what you want on the web
## build: it is far cheaper for the broadphase than an equivalent triangle soup.
## Set `collision_mode` to TRIMESH if you ever need pixel-exact stair collision.

enum CollisionMode {
	HEIGHTMAP, ## Cheap, one shape for the whole terrain. Recommended.
	TRIMESH,   ## Exact match to the rendered triangles. More expensive.
}

@export var grid: int = 320:
	set(value):
		grid = maxi(2, value)
## Lower than the terrain was first built at. Steep ground is where the collision
## feels worst — a body crossing a shoulder loses its footing and skitters down — so
## the relief was taken down rather than patched over in the controller, and taken down
## again when the map grew: the same relief spread over twice the distance is twice the
## walk for the same view, and a 320 m map at the old amplitude read as a long slog
## between hills rather than as open country.
@export var amplitude: float = 4.2
@export var noise_scale: float = 0.006
## Two, not three. The third octave is the fine detail — the metre-scale bumps that the
## step-up and the slope projection have to work for — and it is what makes a wide map
## feel scrapy underfoot. Two octaves of longer, lower hills is smoother ground to run
## across and cheaper to sample.
@export var octaves: int = 2:
	set(value):
		octaves = clampi(value, 1, 8)
## Raises the noise field to this power before scaling it, which flattens the middle
## of the range and shaves the extremes off the peaks. Above 1 the same noise reads as
## rolling country rather than as mountains: the drama is taken out without touching
## the shape, and it costs nothing at runtime.
@export var flatten_power: float = 1.4
@export var noise_seed: int = 20260921
## Terrain is blended flat inside this radius so there is a level home camp at the
## origin to spawn on.
@export var plateau_radius: float = 22.0
## Fraction of `plateau_radius` that is blended completely flat. The home camp is
## built inside this disc, so it has to be wide enough for a hut plus a fence.
@export var plateau_flat_fraction: float = 0.45

@export_group("Roads")
## How many roads leave the home camp. They radiate outwards, so however far you
## wander there is always a levelled way back.
@export var road_count: int = 11
## Half-width of the levelled strip, in metres. Wide enough for two bodies abreast.
@export var road_half_width: float = 3.4
## Extra distance beyond the strip over which the ground eases back into the
## hillside. The shoulder is what stops a road looking like a trench.
@export var road_shoulder: float = 5.0
## Steepest the road is allowed to climb, as metres of rise per metre travelled.
## Applied to the centre line, which is why a road takes the long way round a hill
## instead of going over it.
@export var road_grade: float = 0.11
## Spacing of the centre-line samples. Smaller follows the ground more exactly and
## costs more to carve.
@export var road_step: float = 2.5
@export var road_seed: int = 51207
@export var build_roads: bool = true

@export_group("Collision")
@export var collision_mode: CollisionMode = CollisionMode.HEIGHTMAP
@export var build_on_ready: bool = true

const COL_SAND := Color("b9a878")
const COL_GRASS := Color("4d7a38")
const COL_ROCK := Color("6e7178")
const COL_SNOW := Color("e9eff6")
const COL_CLIFF := Color("54565c")
const COL_ROAD := Color("8a7150")

var _noise: FastNoiseLite
var _heights: PackedFloat32Array = PackedFloat32Array()
## 1 on a road's centre line, fading to 0 at the edge of its shoulder. Kept so the
## vertex colours can paint the road in and so the tests can measure the carve.
var _road: PackedFloat32Array = PackedFloat32Array()
var _roads: Array = []
## Set once the grid is final (roads included). Until then `height_at` has to
## evaluate the noise, because that is what is filling the grid.
var _heights_ready: bool = false
var _origin_height: float = 0.0
var _extent: float = 0.0
## Baked once per generation, because `map_image` is asked for by a redraw loop.
var _map_image: Image = null
var _mesh: MeshInstance3D
var _shape_node: CollisionShape3D


func _ready() -> void:
	if build_on_ready:
		generate()


# ----------------------------------------------------------------- generation

## Rebuilds the mesh and the collision shape. Safe to call repeatedly.
func generate() -> void:
	var started: int = Time.get_ticks_msec()
	_setup_noise()
	_extent = float(grid) * 0.5
	_origin_height = _raw_height(0.0, 0.0)

	var verts: int = grid + 1
	var count: int = verts * verts

	# Pass 1: heights. Cached so the normal pass does not have to re-sample the
	# noise nine times per vertex.
	_heights_ready = false
	_heights.resize(count)
	_road.resize(count)
	_road.fill(0.0)
	for j in verts:
		var z: float = -_extent + float(j)
		var row: int = j * verts
		for i in verts:
			_heights[row + i] = height_at(-_extent + float(i), z)

	# Between pass 1 and pass 2, so both the mesh *and* the HeightMapShape3D the
	# collision is built from see the same levelled ground. Carving the mesh alone
	# would leave the road looking flat and behaving like a hillside.
	_roads = []
	if build_roads:
		_carve_roads()
	_heights_ready = true
	# A regenerated terrain has a new picture; the old one is the previous world.
	_map_image = null

	# Pass 2: normals and vertex colours from the cached grid.
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(count)
	normals.resize(count)
	colors.resize(count)
	for j in verts:
		for i in verts:
			var idx: int = j * verts + i
			var h: float = _heights[idx]
			positions[idx] = Vector3(-_extent + float(i), h, -_extent + float(j))
			var n := _normal_at(i, j)
			normals[idx] = n
			var colour: Color = _color_at(h, n)
			# The levelled strip is painted as packed dirt, which is the only thing that
			# tells a player where the roads are from a distance.
			if _road[idx] > 0.0:
				colour = colour.lerp(COL_ROAD, _road[idx] * 0.8)
			colors[idx] = colour

	var indices := _build_indices(verts)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_ensure_nodes()
	_mesh.mesh = mesh
	_build_collision(mesh)

	var aabb: AABB = mesh.get_aabb()
	print("[terrain] %d cells, %d verts, %d triangles, height %.1f..%.1f, %d ms, collision=%s" % [
		grid, count, indices.size() / 3, aabb.position.y, aabb.end.y,
		Time.get_ticks_msec() - started, CollisionMode.keys()[collision_mode],
	])


func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = noise_seed
	_noise.frequency = noise_scale
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = octaves
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5


func _ensure_nodes() -> void:
	if _mesh == null or not is_instance_valid(_mesh):
		_mesh = get_node_or_null("Mesh") as MeshInstance3D
		if _mesh == null:
			_mesh = MeshInstance3D.new()
			_mesh.name = "Mesh"
			add_child(_mesh)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mesh.material_override = material

	if _shape_node == null or not is_instance_valid(_shape_node):
		_shape_node = get_node_or_null("Shape") as CollisionShape3D
		if _shape_node == null:
			_shape_node = CollisionShape3D.new()
			_shape_node.name = "Shape"
			add_child(_shape_node)


func _build_collision(mesh: Mesh) -> void:
	if collision_mode == CollisionMode.TRIMESH:
		_shape_node.shape = mesh.create_trimesh_shape()
		return
	# HeightMapShape3D samples are 1 world unit apart and the shape is centred on
	# its origin spanning ±(verts-1)/2, which is exactly where the mesh vertices
	# sit. map_data is laid out row-major with Z as the row, matching _heights.
	var hm := HeightMapShape3D.new()
	hm.map_width = grid + 1
	hm.map_depth = grid + 1
	hm.map_data = _heights
	_shape_node.shape = hm


func _build_indices(verts: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	indices.resize(grid * grid * 6)
	var w: int = 0
	for j in grid:
		for i in grid:
			var a: int = j * verts + i
			var b: int = a + 1
			var c: int = a + verts
			var d: int = c + 1
			# Godot's front faces are wound so that the right-hand normal points
			# *away* from the front, which for an upward-facing quad means a
			# downward right-hand normal. Verified against an engine-authored
			# PlaneMesh by tests/self_test.gd::_test_winding — flip these six
			# assignments and the terrain renders inside-out.
			indices[w] = a
			indices[w + 1] = b
			indices[w + 2] = c
			indices[w + 3] = b
			indices[w + 4] = d
			indices[w + 5] = c
			w += 6
	return indices


# ----------------------------------------------------------------------- roads

## Levels a radiating road network into the height grid.
##
## A road is a centre line plus a strip: the line's own heights are smoothed and
## grade-limited first, then the strip is written flat across that line, and a
## shoulder eases it back into whatever the hillside was doing. Grade limiting is what
## makes a road worth walking: it goes round a rise rather than over it, so it is the
## one piece of ground a body can cross at full speed without skidding.
##
## The lines start at the origin, which is the levelled home plateau, and the limit is
## applied outward from there — so every road leaves camp at camp height instead of
## starting with a step.
func _carve_roads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = road_seed
	var reach: float = _extent * 0.94
	for k in road_count:
		var heading: float = (TAU / float(road_count)) * float(k) + rng.randf_range(-0.32, 0.32)
		var points := PackedVector2Array()
		var samples := PackedFloat32Array()
		var travelled: float = 0.0
		while travelled < reach:
			# A road wanders rather than running dead straight, so that it reads as a
			# route and can drift around the worst of the ground.
			var wander: float = 0.0
			if travelled > 14.0:
				wander = _noise.get_noise_2d(travelled * 0.05 + float(k) * 71.0, 0.0) * 0.34
			var dir: float = heading + wander
			var at := Vector2(cos(dir) * travelled, sin(dir) * travelled)
			points.append(at)
			samples.append(surface_height_at(at.x, at.y))
			travelled += road_step
		_grade_line(samples)
		_roads.append({"points": points, "heights": samples, "heading": heading})
		_rasterise(points, samples)
	print("[terrain] %d roads, half-width %.1f, shoulder %.1f, grade %.2f" % [
		_roads.size(), road_half_width, road_shoulder, road_grade,
	])


## Smooths a centre line and clamps its gradient. Repeated a few times, because
## levelling a rise while walking outward leaves a step at the same place when the
## same line is read back the other way.
func _grade_line(samples: PackedFloat32Array) -> void:
	var drop: float = road_grade * road_step
	for pass_index in 6:
		for i in range(1, samples.size()):
			samples[i] = clampf(samples[i], samples[i - 1] - drop, samples[i - 1] + drop)
		for i in range(samples.size() - 2, -1, -1):
			samples[i] = clampf(samples[i], samples[i + 1] - drop, samples[i + 1] + drop)


## Writes one road's strip into the grid. Blended from the *pre-road* heights, kept in
## a copy, or two roads crossing would each blend the other's result again.
func _rasterise(points: PackedVector2Array, samples: PackedFloat32Array) -> void:
	var verts: int = grid + 1
	var whole: float = road_half_width + road_shoulder
	var span: int = int(ceilf(whole)) + 1
	var base: PackedFloat32Array = _heights.duplicate()
	for p in points.size():
		var centre: Vector2 = points[p]
		var height: float = samples[p]
		var i0: int = maxi(0, int(floorf(centre.x + _extent)) - span)
		var i1: int = mini(grid, int(ceilf(centre.x + _extent)) + span)
		var j0: int = maxi(0, int(floorf(centre.y + _extent)) - span)
		var j1: int = mini(grid, int(ceilf(centre.y + _extent)) + span)
		for j in range(j0, j1 + 1):
			var z: float = -_extent + float(j)
			for i in range(i0, i1 + 1):
				var x: float = -_extent + float(i)
				var d: float = Vector2(x - centre.x, z - centre.y).length()
				if d > whole:
					continue
				var weight: float = 1.0 if d <= road_half_width \
					else 1.0 - smoothstep(road_half_width, whole, d)
				var idx: int = j * verts + i
				if weight <= _road[idx]:
					continue
				_road[idx] = weight
				_heights[idx] = lerpf(base[idx], height, weight)


## The road network as placed: each entry carries its centre-line `points`, the
## graded `heights` along it, and the heading it left camp on. Read by the signposts,
## which is what turns a road into a destination rather than a path.
func roads() -> Array:
	return _roads.duplicate(true)


## 0..1 road coverage at a world XZ, by the same bilinear read the height uses.
func road_weight_at(x: float, z: float) -> float:
	if _road.is_empty():
		return 0.0
	var fx: float = x + _extent
	var fz: float = z + _extent
	var i: int = clampi(int(floorf(fx)), 0, grid - 1)
	var j: int = clampi(int(floorf(fz)), 0, grid - 1)
	var tx: float = clampf(fx - float(i), 0.0, 1.0)
	var tz: float = clampf(fz - float(j), 0.0, 1.0)
	return lerpf(
		lerpf(_cached_road(i, j), _cached_road(i + 1, j), tx),
		lerpf(_cached_road(i, j + 1), _cached_road(i + 1, j + 1), tx),
		tz
	)


func _cached_road(i: int, j: int) -> float:
	var verts: int = grid + 1
	return _road[clampi(j, 0, grid) * verts + clampi(i, 0, grid)]


# -------------------------------------------------------------------- sampling

func _raw_height(x: float, z: float) -> float:
	var n: float = _noise.get_noise_2d(x, z)
	# Signed power, so the sign survives: negative values have to stay below the water
	# line rather than being folded up into hills.
	var shaped: float = signf(n) * pow(absf(n), flatten_power)
	return shaped * amplitude


## Terrain height at any world XZ. Used for spawns, teleports and the HUD.
##
## Before the grid exists this is the continuous noise plus the home plateau. Once
## the grid is built it is a bilinear read of that grid instead, because the grid is
## then the truth: the mesh is built from it, the collision shape is built from it,
## and the roads are carved into it. A caller that asked the noise instead would be
## told about ground that is no longer there.
func height_at(x: float, z: float) -> float:
	if _heights_ready:
		return surface_height_at(x, z)
	var h: float = _raw_height(x, z)
	if plateau_radius > 0.0:
		var d: float = sqrt(x * x + z * z)
		if d < plateau_radius:
			h = lerp(_origin_height, h, smoothstep(plateau_radius * plateau_flat_fraction, plateau_radius, d))
	return h


func _cached_height(i: int, j: int) -> float:
	var verts: int = grid + 1
	return _heights[clampi(j, 0, grid) * verts + clampi(i, 0, grid)]


func _normal_at(i: int, j: int) -> Vector3:
	# Central difference of the height field: for y = h(x, z) the surface normal
	# is proportional to (-dh/dx, 1, -dh/dz).
	var left: float = _cached_height(i - 1, j)
	var right: float = _cached_height(i + 1, j)
	var near: float = _cached_height(i, j - 1)
	var far: float = _cached_height(i, j + 1)
	return Vector3(left - right, 2.0, near - far).normalized()


func _color_at(h: float, n: Vector3) -> Color:
	var t: float = clampf(inverse_lerp(-amplitude * 0.6, amplitude, h), 0.0, 1.0)
	var c: Color
	if t < 0.18:
		c = COL_SAND.lerp(COL_GRASS, smoothstep(0.0, 0.18, t))
	elif t < 0.5:
		c = COL_GRASS
	elif t < 0.82:
		c = COL_GRASS.lerp(COL_ROCK, smoothstep(0.5, 0.82, t))
	else:
		c = COL_ROCK.lerp(COL_SNOW, smoothstep(0.82, 1.0, t))
	# Steep faces are bare rock whatever their altitude.
	var steep: float = smoothstep(0.30, 0.62, 1.0 - n.y)
	return c.lerp(COL_CLIFF, steep)


# --------------------------------------------------------------------- helpers

## True once the height grid exists, so other systems can tell whether
## `surface_height_at` is safe to call.
func is_generated() -> bool:
	return not _heights.is_empty()


## Height of the *rendered* surface at any world XZ, by bilinear interpolation of
## the same grid the mesh and the collision shape are built from.
##
## This is not the same as `height_at`: that one evaluates the continuous noise,
## while the mesh is a piecewise-linear interpolation between grid samples half a
## metre of slope apart. The difference is centimetres — which is exactly the
## difference between a crate resting on the ground and a crate hanging in the
## air — so anything placed *on* the terrain should ask for this one. The physics
## server interpolates the HeightMapShape3D the same way, so a prop placed here
## sits on the collision surface too.
func surface_height_at(x: float, z: float) -> float:
	if _heights.is_empty():
		return height_at(x, z)
	var fx: float = x + _extent
	var fz: float = z + _extent
	var i: int = clampi(int(floorf(fx)), 0, grid - 1)
	var j: int = clampi(int(floorf(fz)), 0, grid - 1)
	var tx: float = clampf(fx - float(i), 0.0, 1.0)
	var tz: float = clampf(fz - float(j), 0.0, 1.0)
	return lerpf(
		lerpf(_cached_height(i, j), _cached_height(i + 1, j), tx),
		lerpf(_cached_height(i, j + 1), _cached_height(i + 1, j + 1), tx),
		tz
	)


## Steepness as `1 - normal.y`: 0 is flat, 1 is a vertical wall. Same formula the
## vertex colours use, so scatter placement and terrain paint agree about where
## the cliffs are.
func slope_at(x: float, z: float) -> float:
	var d: float = 1.0
	var normal := Vector3(
		surface_height_at(x - d, z) - surface_height_at(x + d, z),
		2.0 * d,
		surface_height_at(x, z - d) - surface_height_at(x, z + d)
	)
	return 1.0 - normal.normalized().y


func extent() -> float:
	return _extent


func size_units() -> float:
	return float(grid)


## Flat-ish spot at the origin, for the initial spawn.
func spawn_point(extra_height: float = 2.0) -> Vector3:
	return Vector3(0.0, height_at(0.0, 0.0) + extra_height, 0.0)


## A top-down picture of the ground, coloured with the very ramp the mesh wears and
## shaded by the very normals it uses.
##
## Built from the cached grid rather than by re-sampling the noise, so the map cannot
## disagree with the terrain underfoot, and baked once because the minimap redraws
## every tenth of a second and this is a still picture. The hillshade is the part that
## makes it readable: without it every gentle slope is the same green and the only
## thing a map can tell you is where the cliffs are, which is the one thing you can
## already see from where you are standing.
func map_image(target: int = 256) -> Image:
	if _map_image != null:
		return _map_image
	if _heights.is_empty():
		return Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var verts: int = grid + 1
	var image := Image.create(verts, verts, false, Image.FORMAT_RGBA8)
	var sun := Vector3(-0.45, 0.8, -0.4).normalized()
	for j in verts:
		for i in verts:
			var idx: int = j * verts + i
			var colour: Color = _color_at(_heights[idx], _normal_at(i, j))
			if _road[idx] > 0.0:
				colour = colour.lerp(COL_ROAD, _road[idx] * 0.8)
			var shade: float = clampf(0.70 + 0.44 * _normal_at(i, j).dot(sun), 0.42, 1.22)
			image.set_pixel(i, j, Color(colour.r * shade, colour.g * shade, colour.b * shade))
	if target > 0 and target != verts:
		image.resize(target, target, Image.INTERPOLATE_BILINEAR)
	_map_image = image
	return image


func height_range() -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	for h in _heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return Vector2(lo, hi)
