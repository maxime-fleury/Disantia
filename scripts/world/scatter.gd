extends Node3D
## Dresses the terrain in the Stylized Nature kit (KayKit, CC0).
##
## Rendering is one MultiMesh per (species, chunk) pair, so three thousand tufts
## of grass cost a few dozen draw calls instead of three thousand scene nodes.
## The chunking is not decoration: a MultiMesh is submitted as a single draw, so
## one whole-terrain MultiMesh could never be frustum-culled and every blade in
## the valley would run through the vertex shader every frame. Splitting the map
## into 32-unit tiles lets the camera throw most of it away for free.
##
## Collision is deliberately separate from drawing. Trees get a bare StaticBody3D
## holding a trunk cylinder and *no* mesh at all, so the tree you cannot walk
## through is the same tree the MultiMesh draws — at no extra draw call, and
## without paying for a per-instance scene. Anything a person would brush past
## (grass, flowers, pebbles) gets no collision at all.
##
## Placement is a jittered grid rather than pure random points: one candidate per
## `spacing` cell, nudged within the cell. That gives even coverage with no
## clumping, and it is fully deterministic, so the same seed always grows the same
## forest — which is what makes the headless self-test able to assert on it.

## One entry per model. Bands are in the same 0..1 altitude space the terrain's
## vertex colours use (`t` in terrain.gd::_color_at), so "grass on the mid
## slopes" means the same thing to both systems.
##
##   spacing   side of one candidate cell, in world units
##   density   chance that a candidate is accepted
##   band      min/max altitude, 0 = lowest ground, 1 = highest peak
##
## The ground cover — grass, pebbles, flowers, ferns — has been cut back hard from where
## it started. At the original densities the two grass species alone were seven thousand
## of the world's ten thousand instances, which read as a lawn with trees in it rather
## than as a landscape: you could not see the ground, the roads, or the rocks, and the
## horizon was a green haze. Trees were trimmed only slightly; they are the landscape.
##   slope_min/max  allowed steepness (1 - normal.y)
##   collide   trunk cylinder radius at scale 1; 0 disables collision
const SPECIES: Array = [
	{
		"label": "CommonTree_1", "path": "res://assets/nature/CommonTree_1.gltf",
		"spacing": 9.0, "density": 0.24, "scale": Vector2(0.85, 1.30),
		"band": Vector2(0.20, 0.70), "slope_min": 0.0, "slope_max": 0.45,
		"tilt": 4.0, "sink": 0.06, "collide": 0.30, "trunk_height": 5.0,
	},
	{
		"label": "CommonTree_3", "path": "res://assets/nature/CommonTree_3.gltf",
		"spacing": 9.0, "density": 0.21, "scale": Vector2(0.85, 1.25),
		"band": Vector2(0.22, 0.72), "slope_min": 0.0, "slope_max": 0.45,
		"tilt": 4.0, "sink": 0.06, "collide": 0.30, "trunk_height": 5.5,
	},
	{
		"label": "Pine_1", "path": "res://assets/nature/Pine_1.gltf",
		"spacing": 9.5, "density": 0.24, "scale": Vector2(0.85, 1.25),
		"band": Vector2(0.45, 0.95), "slope_min": 0.0, "slope_max": 0.55,
		"tilt": 3.0, "sink": 0.08, "collide": 0.32, "trunk_height": 5.0,
	},
	{
		"label": "Pine_3", "path": "res://assets/nature/Pine_3.gltf",
		"spacing": 9.5, "density": 0.20, "scale": Vector2(0.85, 1.20),
		"band": Vector2(0.48, 0.98), "slope_min": 0.0, "slope_max": 0.55,
		"tilt": 3.0, "sink": 0.08, "collide": 0.32, "trunk_height": 5.0,
	},
	{
		"label": "TwistedTree_1", "path": "res://assets/nature/TwistedTree_1.gltf",
		"spacing": 28.0, "density": 0.70, "scale": Vector2(0.70, 1.00),
		"band": Vector2(0.40, 0.95), "slope_min": 0.0, "slope_max": 0.50,
		"tilt": 5.0, "sink": 0.10, "collide": 0.42, "trunk_height": 7.0,
	},
	{
		"label": "DeadTree_1", "path": "res://assets/nature/DeadTree_1.gltf",
		"spacing": 21.0, "density": 0.35, "scale": Vector2(0.80, 1.15),
		"band": Vector2(0.05, 0.55), "slope_min": 0.0, "slope_max": 0.50,
		"tilt": 5.0, "sink": 0.08, "collide": 0.26, "trunk_height": 5.0,
	},
	{
		"label": "Bush_Common", "path": "res://assets/nature/Bush_Common.gltf",
		"spacing": 9.5, "density": 0.11, "scale": Vector2(0.80, 1.25),
		"band": Vector2(0.10, 0.65), "slope_min": 0.0, "slope_max": 0.35,
		"tilt": 8.0, "sink": 0.05, "collide": 0.0,
	},
	{
		"label": "Bush_Common_Flowers", "path": "res://assets/nature/Bush_Common_Flowers.gltf",
		"spacing": 10.0, "density": 0.09, "scale": Vector2(0.80, 1.20),
		"band": Vector2(0.15, 0.60), "slope_min": 0.0, "slope_max": 0.30,
		"tilt": 8.0, "sink": 0.05, "collide": 0.0,
	},
	{
		"label": "Grass_Common_Tall", "path": "res://assets/nature/Grass_Common_Tall.gltf",
		"spacing": 5.0, "density": 0.30, "scale": Vector2(0.75, 1.35),
		"band": Vector2(0.05, 0.60), "slope_min": 0.0, "slope_max": 0.30,
		"tilt": 12.0, "sink": 0.03, "collide": 0.0, "shadow": false,
	},
	{
		"label": "Grass_Wispy_Short", "path": "res://assets/nature/Grass_Wispy_Short.gltf",
		"spacing": 5.0, "density": 0.26, "scale": Vector2(0.75, 1.30),
		"band": Vector2(0.05, 0.62), "slope_min": 0.0, "slope_max": 0.32,
		"tilt": 12.0, "sink": 0.03, "collide": 0.0, "shadow": false,
	},
	{
		"label": "Fern_1", "path": "res://assets/nature/Fern_1.gltf",
		"spacing": 9.0, "density": 0.08, "scale": Vector2(0.22, 0.36),
		"band": Vector2(0.12, 0.62), "slope_min": 0.0, "slope_max": 0.35,
		"tilt": 10.0, "sink": 0.04, "collide": 0.0,
	},
	{
		"label": "Plant_1_Big", "path": "res://assets/nature/Plant_1_Big.gltf",
		"spacing": 9.5, "density": 0.05, "scale": Vector2(0.70, 1.10),
		"band": Vector2(0.08, 0.55), "slope_min": 0.0, "slope_max": 0.30,
		"tilt": 10.0, "sink": 0.04, "collide": 0.0,
	},
	{
		"label": "Flower_3_Group", "path": "res://assets/nature/Flower_3_Group.gltf",
		"spacing": 5.5, "density": 0.10, "scale": Vector2(0.70, 1.20),
		"band": Vector2(0.15, 0.62), "slope_min": 0.0, "slope_max": 0.30,
		"tilt": 10.0, "sink": 0.03, "collide": 0.0, "shadow": false,
	},
	{
		"label": "Mushroom_Common", "path": "res://assets/nature/Mushroom_Common.gltf",
		"spacing": 7.5, "density": 0.05, "scale": Vector2(0.70, 1.40),
		"band": Vector2(0.15, 0.70), "slope_min": 0.0, "slope_max": 0.35,
		"tilt": 12.0, "sink": 0.02, "collide": 0.0, "shadow": false,
	},
	# Rocks want broken ground, and these floors have now been wrong twice — both times
	# too high for the ground they were sitting on, and both times silently. They were
	# 0.10-0.12 while the terrain was mountainous; flattening it to 9 m of relief put the
	# whole map's steepest point at 0.175, then flattening it again to 7.7 m of relief on
	# twice the ground put the steepest point a species is ever *offered* at 0.054. A
	# floor of 0.015 against that admitted 1.4% of candidates: six rocks on a 320 m map.
	# The measured share of the current ground at each floor is what set these, and a
	# species that falls below a dozen instances now says so out loud on boot — see
	# `_report_starved_species`, which is what caught this. A rock on gentle ground is
	# normal; a rock that never appears is a hole in the landscape.
	{
		"label": "Rock_Medium_1", "path": "res://assets/nature/Rock_Medium_1.gltf",
		"spacing": 8.0, "density": 0.34, "scale": Vector2(0.70, 1.40),
		"band": Vector2(0.0, 1.0), "slope_min": 0.004, "slope_max": 1.0,
		"tilt": 14.0, "sink": 0.35, "collide": 0.0,
	},
	{
		"label": "Rock_Medium_2", "path": "res://assets/nature/Rock_Medium_2.gltf",
		"spacing": 8.0, "density": 0.30, "scale": Vector2(0.70, 1.40),
		"band": Vector2(0.0, 1.0), "slope_min": 0.006, "slope_max": 1.0,
		"tilt": 14.0, "sink": 0.35, "collide": 0.0,
	},
	{
		"label": "Rock_Medium_3", "path": "res://assets/nature/Rock_Medium_3.gltf",
		"spacing": 9.0, "density": 0.26, "scale": Vector2(0.70, 1.40),
		"band": Vector2(0.02, 1.0), "slope_min": 0.009, "slope_max": 1.0,
		"tilt": 14.0, "sink": 0.35, "collide": 0.0,
	},
	{
		"label": "Pebble_Round_3", "path": "res://assets/nature/Pebble_Round_3.gltf",
		"spacing": 6.5, "density": 0.10, "scale": Vector2(0.70, 1.60),
		"band": Vector2(0.0, 0.75), "slope_min": 0.0, "slope_max": 0.35,
		"tilt": 16.0, "sink": 0.02, "collide": 0.0, "shadow": false,
	},
	{
		"label": "Pebble_Square_2", "path": "res://assets/nature/Pebble_Square_2.gltf",
		"spacing": 6.5, "density": 0.09, "scale": Vector2(0.70, 1.60),
		"band": Vector2(0.0, 0.72), "slope_min": 0.0, "slope_max": 0.35,
		"tilt": 16.0, "sink": 0.02, "collide": 0.0, "shadow": false,
	},
]

@export var enabled: bool = true
## Change this and the whole landscape regrows differently, reproducibly.
@export var rng_seed: int = 20260922
## Side of one chunk, in world units. Smaller culls in finer slices at the cost
## of more draw calls; 32 is the point where both stay cheap.
@export_range(8.0, 128.0, 1.0) var chunk_size: float = 32.0
## Nothing is scattered inside this radius: that disc belongs to the home camp.
@export var camp_clear_radius: float = 13.0
## Global multiplier on every species' density, for tuning without edits.
@export_range(0.0, 4.0, 0.05) var density_multiplier: float = 1.0
@export var cast_shadows: bool = true

var _terrain: Node
var _instances: int = 0
var _chunks: int = 0
var _trunk_bodies: int = 0
var _per_species: Dictionary = {}
## Per-species placement reasons, for the self-test. `_per_species` alone cannot say
## *why* a species is absent, which is the only interesting part of an absent species.
var _placement_audit: Dictionary = {}
var _missing: Array[String] = []
var _trunk_spots: Array = []


func _ready() -> void:
	if not enabled:
		return
	_terrain = get_node_or_null("../Terrain")
	if _terrain == null:
		push_warning("[scatter] no Terrain sibling to scatter over")
		return
	# Terrain is an earlier sibling and has built its height grid by now, but the
	# scatter is useless without it, so make the dependency explicit rather than
	# relying on scene order.
	if not bool(_terrain.call("is_generated")):
		_terrain.call("generate")

	var started: int = Time.get_ticks_msec()
	for spec: Dictionary in SPECIES:
		_scatter_species(spec)
	print("[scatter] %d instances of %d species in %d chunk meshes, %d trunk bodies, %d ms%s" % [
		_instances, _per_species.size(), _chunks, _trunk_bodies,
		Time.get_ticks_msec() - started,
		("  MISSING %s" % str(_missing)) if not _missing.is_empty() else "",
	])
	var counts: Array = []
	for label: String in _per_species:
		counts.append("%s=%d" % [label, _per_species[label]])
	print("[scatter] per species: %s" % " ".join(counts))
	_report_starved_species()


## Names any species that placed almost nothing, and the reason it was turned away.
##
## The rock species once went to zero instances without a word: their slope thresholds
## were written for a mountainous map, the ground was flattened, and a filter that admits
## half a percent of the terrain placed nothing at all — while the instance total stayed
## comfortably large, so nothing looked wrong. A species that is *nearly* extinct is the
## same bug half-done, and the fix is the same: say so, with the numbers, at the only
## moment they exist.
const STARVED_BELOW := 12


func _report_starved_species() -> void:
	for label: String in _placement_audit:
		var audit: Dictionary = _placement_audit[label]
		if int(audit["placed"]) >= STARVED_BELOW:
			continue
		print("[scatter] STARVED %s: %d placed, steepest ground offered %.3f against a floor of %.3f — rejected %d for slope, %d for altitude, %d for density" % [
			label, int(audit["placed"]), float(audit["steepest"]), float(audit["slope_min"]),
			int(audit["rejected_slope"]), int(audit["rejected_band"]),
			int(audit["rejected_density"]),
		])


# ------------------------------------------------------------------- placement

func _scatter_species(spec: Dictionary) -> void:
	var scene: PackedScene = load(String(spec["path"]))
	if scene == null:
		_missing.append(String(spec["label"]))
		return
	var probe: Node = scene.instantiate()
	var source: MeshInstance3D = _first_mesh(probe)
	if source == null:
		probe.free()
		_missing.append(String(spec["label"]))
		return
	# The mesh resource outlives the throwaway instance, so the probe is only ever
	# asked "which model is this?" and then released.
	var mesh: Mesh = _tintable_mesh(source.mesh)
	probe.free()

	var extent: float = float(_terrain.call("size_units"))
	var half: float = extent * 0.5
	var amplitude: float = float(_terrain.get("amplitude"))
	var lowest: float = -amplitude * 0.6
	var spacing: float = maxf(0.5, float(spec["spacing"]))
	var steps: int = maxi(1, int(ceil(extent / spacing)))
	var band: Vector2 = spec["band"]
	var slope_min: float = float(spec.get("slope_min", 0.0))
	var slope_max: float = float(spec.get("slope_max", 1.0))
	var scale_range: Vector2 = spec["scale"]
	var tilt_max: float = float(spec.get("tilt", 0.0))
	var sink: float = float(spec.get("sink", 0.0))
	var collide: float = float(spec.get("collide", 0.0))
	var density: float = clampf(float(spec["density"]) * density_multiplier, 0.0, 1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + String(spec["label"]).hash()
	var clear_sq: float = camp_clear_radius * camp_clear_radius
	var buckets: Dictionary = {}
	var placed: int = 0
	# Why a species placed nothing is the whole question when one silently vanishes,
	# and "its slopes were all too gentle" and "your density is 0.01" look identical
	# from the instance count. Tallied per reason, so the answer is in the log.
	var rejected := {"clear": 0, "density": 0, "band": 0, "slope": 0}
	var steepest: float = 0.0

	for cz in steps:
		for cx in steps:
			# Jitter inside the cell keeps the grid from reading as a lattice while
			# still guaranteeing one candidate per cell.
			var x: float = -half + float(cx) * spacing + rng.randf_range(0.0, spacing)
			var z: float = -half + float(cz) * spacing + rng.randf_range(0.0, spacing)
			if x * x + z * z < clear_sq:
				rejected["clear"] += 1
				continue
			if rng.randf() > density:
				rejected["density"] += 1
				continue
			var h: float = float(_terrain.call("surface_height_at", x, z))
			var altitude: float = clampf(inverse_lerp(lowest, amplitude, h), 0.0, 1.0)
			if altitude < band.x or altitude > band.y:
				rejected["band"] += 1
				continue
			var slope: float = float(_terrain.call("slope_at", x, z))
			# Only counted for candidates that already passed the altitude test, so this
			# is the steepest ground the species was actually offered.
			steepest = maxf(steepest, slope)
			if slope < slope_min or slope > slope_max:
				rejected["slope"] += 1
				continue

			var size: float = rng.randf_range(scale_range.x, scale_range.y)
			var yaw: float = rng.randf_range(0.0, TAU)
			var lean := Vector3(
				deg_to_rad(rng.randf_range(-tilt_max, tilt_max)),
				0.0,
				deg_to_rad(rng.randf_range(-tilt_max, tilt_max))
			)
			var place := Transform3D()
			place.basis = Basis.from_euler(lean).rotated(Vector3.UP, yaw).scaled(
				Vector3(size, size, size)
			)
			# Sunk by a fraction of the instance's own height so a tilted trunk
			# never shows daylight under it.
			place.origin = Vector3(x, h - sink * size, z)

			var key := Vector2i(
				int(floorf((x + half) / chunk_size)),
				int(floorf((z + half) / chunk_size))
			)
			if not buckets.has(key):
				buckets[key] = {"moves": [], "trunks": []}
			buckets[key]["moves"].append(place)
			placed += 1
			if collide > 0.0:
				buckets[key]["trunks"].append(Vector4(x, h, z, size))

	for key: Vector2i in buckets:
		_emit_chunk(spec, mesh, key, buckets[key])
	var label: String = String(spec["label"])
	_per_species[label] = placed
	_placement_audit[label] = {
		"placed": placed, "steepest": steepest,
		"slope_min": slope_min, "slope_max": slope_max,
		"band": band, "density": float(spec["density"]),
		"clear": rejected["clear"], "rejected_density": rejected["density"],
		"rejected_band": rejected["band"], "rejected_slope": rejected["slope"],
	}


func _emit_chunk(spec: Dictionary, mesh: Mesh, _key: Vector2i, bucket: Dictionary) -> void:
	var moves: Array = bucket["moves"]
	if moves.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = moves.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + String(spec["label"]).hash() + moves.size()
	for i in moves.size():
		multimesh.set_instance_transform(i, moves[i])
		# A gentle per-instance tint, so a hillside of one model does not read as
		# a hillside of one clone. It arrives on the vertex colour channel, which
		# is why the mesh is rebuilt with that channel present.
		var lift: float = rng.randf_range(0.86, 1.14)
		multimesh.set_instance_color(i, Color(
			lift * rng.randf_range(0.97, 1.05), lift, lift * rng.randf_range(0.95, 1.04)
		))

	var node := MultiMeshInstance3D.new()
	node.name = "Chunk_%d_%d" % [_key.x, _key.y]
	node.multimesh = multimesh
	var want_shadow: bool = cast_shadows and bool(spec.get("shadow", true))
	node.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if want_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(node)

	_instances += moves.size()
	_chunks += 1

	var collide: float = float(spec.get("collide", 0.0))
	if collide <= 0.0:
		return
	var trunk_height: float = float(spec.get("trunk_height", 4.0))
	var sink: float = float(spec.get("sink", 0.0))
	for entry: Vector4 in bucket["trunks"]:
		_build_trunk(Vector3(entry.x, entry.y, entry.z), entry.w, collide, trunk_height, sink)


## The invisible wall that makes a tree solid. It carries no mesh: the MultiMesh
## is already drawing the trunk in exactly this spot.
func _build_trunk(at: Vector3, size: float, radius: float, height: float, sink: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Trunk"
	body.position = at
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius * size
	cylinder.height = height * size
	var shape := CollisionShape3D.new()
	shape.shape = cylinder
	# Bury the base a little so a gap never opens on a slope, and start the
	# cylinder at the ground rather than centred on it.
	shape.position = Vector3(0.0, cylinder.height * 0.5 - maxf(0.3, sink * 2.0), 0.0)
	body.add_child(shape)
	add_child(body)
	_trunk_bodies += 1
	_trunk_spots.append(Vector4(at.x, at.y, at.z, cylinder.radius))


# ------------------------------------------------------------------- mesh prep

## A copy of an imported mesh whose surfaces can actually receive a MultiMesh
## instance colour.
##
## An instance colour rides in on the vertex colour channel, so that channel has
## to exist and the material has to be told to use it. Imported glTF meshes here
## carry no vertex colours at all, so one is added and filled with white — which
## leaves a plain MeshInstance3D sharing this mesh looking exactly as before,
## while the MultiMesh can tint each instance.
func _tintable_mesh(source: Mesh) -> Mesh:
	var out := ArrayMesh.new()
	for i in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(i)
		var has_colors: bool = false
		if typeof(arrays[Mesh.ARRAY_COLOR]) == TYPE_PACKED_COLOR_ARRAY:
			has_colors = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
		if not has_colors:
			var colors := PackedColorArray()
			colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			colors.fill(Color.WHITE)
			arrays[Mesh.ARRAY_COLOR] = colors
		out.add_surface_from_arrays(source.surface_get_primitive_type(i), arrays)
		var material: Material = source.surface_get_material(i)
		if material is BaseMaterial3D:
			var tintable: BaseMaterial3D = (material as BaseMaterial3D).duplicate()
			tintable.vertex_color_use_as_albedo = true
			out.surface_set_material(i, tintable)
		elif material != null:
			out.surface_set_material(i, material)
	return out


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node
		if instance.mesh != null and instance.mesh.get_surface_count() > 0:
			return instance
	for child in node.get_children():
		var found: MeshInstance3D = _first_mesh(child)
		if found != null:
			return found
	return null


# -------------------------------------------------------------------- reporting

## Counts for the headless self-test, and for reading the cost of a density tweak.
func summary() -> Dictionary:
	return {
		"instances": _instances,
		"chunk_meshes": _chunks,
		"trunk_bodies": _trunk_bodies,
		"species": _per_species.size(),
		"missing": _missing.duplicate(),
	}


func species_counts() -> Dictionary:
	return _per_species.duplicate()


## Per-species counts *and* the reasons the rest were turned away: the steepest ground
## offered, the active slope window and altitude band, and how many candidates each
## test rejected. Enough to name the constraint that emptied a species.
func placement_audit() -> Dictionary:
	return _placement_audit.duplicate(true)


## Trunk positions and radii as (x, ground y, z, radius). The self-test needs
## these to confirm that the invisible trunk sits where the drawn tree is, which
## nothing else in the scene can prove.
func trunk_points(count: int) -> Array:
	var out: Array = []
	if _trunk_spots.is_empty() or count <= 0:
		return out
	var step: int = maxi(1, _trunk_spots.size() / count)
	var i: int = 0
	while out.size() < count and i < _trunk_spots.size():
		out.append(_trunk_spots[i])
		i += step
	return out


## Transforms read back out of the built MultiMeshes. These are the very numbers
## the renderer consumes, so the self-test checks what is on screen rather than
## the intent behind it.
func sample_transforms(count: int) -> Array:
	var sources: Array = []
	for child in get_children():
		if child is MultiMeshInstance3D:
			var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
			if mm != null and mm.instance_count > 0:
				sources.append(mm)
	var out: Array = []
	if sources.is_empty():
		return out
	var per_source: int = maxi(1, int(ceil(float(count) / float(sources.size()))))
	for mm: MultiMesh in sources:
		for k in per_source:
			if out.size() >= count:
				return out
			var index: int = int(float(k) / float(per_source) * float(mm.instance_count))
			out.append(mm.get_instance_transform(clampi(index, 0, mm.instance_count - 1)))
	return out
