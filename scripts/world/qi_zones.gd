extends Node3D
## Spirit zones: patches of ground where the qi runs strong enough that cultivating
## on them is faster.
##
## The boost multiplies *throughput*, not efficiency: standing in a zone burns qi
## faster and fills both meters proportionally faster, so a zone is a straight
## speed-up rather than a discount. That is deliberate — qi per second is the number
## the player is already watching on the HUD, so scaling it is the one change they can
## feel immediately, and it keeps the qi cost of a refinement meaningful instead of
## letting a zone quietly make qi free.
##
## Each zone carries a requirement on the cultivator's *stage*, which is what makes
## them worth walking to and what stops the best one being farmed from minute one.
## They are landmarks as much as bonuses: the column of light is visible over a hill,
## so "I will be able to use that one day" is legible from a distance.
##
## Placement is seeded and rejection-sampled rather than authored: the terrain is
## procedural, so a hand-placed coordinate would be a bet on the noise field, and a
## zone sitting on a cliff face looks like a bug rather than a feature.

## The catalogue, in the order they are placed — and the order is load-bearing, because a
## zone's index in this list *is* its ring. Zone 0 powers the home ring, zone 1 sits behind
## the first ward with a champion standing on it, and so on outwards. `Wards.RING_ZONES`
## names the same pairing from the other side; the two lists are read against each other and
## the suite checks that they agree.
##
## `reach` is the band of the map's half-extent a zone may be placed in, as (inner, outer)
## fractions. It used to be one shared band for all four, which meant a zone that powers the
## third ward could be found twenty metres from the fire.
##
## `required_tier` is a cultivation stage, and it is now the *weaker* of the two gates: the
## real one is the champion standing on the zone. It stays because a save can arrive from
## anywhere, and "this ground is dormant until stage five" is a better answer for a player
## who finds one early than a boost they have not earned.
const ZONE_DEFS: Array = [
	{
		"id": "spring", "name": "Spirit Spring", "radius": 9.0,
		"boost": 1.5, "required_tier": 0, "color": "6ec8ff",
		"reach": Vector2(0.27, 0.40),
	},
	{
		"id": "grove", "name": "Whispering Grove", "radius": 11.0,
		"boost": 2.0, "required_tier": 2, "color": "9fe0a0",
		"reach": Vector2(0.44, 0.62),
	},
	{
		"id": "vein", "name": "Earth Vein", "radius": 12.0,
		"boost": 2.5, "required_tier": 5, "color": "ffd76e",
		"reach": Vector2(0.67, 0.78),
	},
	{
		"id": "peak", "name": "Storm Peak", "radius": 13.0,
		"boost": 3.5, "required_tier": 9, "color": "c9a6ff",
		"reach": Vector2(0.83, 0.94),
	},
]

@export var zone_seed: int = 770316
## How far from the origin a zone has to be, so none of them straddles the home camp.
@export var camp_clearance: float = 38.0
## How far apart two zones have to be, so they never overlap into one big aura.
@export var zone_separation: float = 42.0
## A zone wants level ground; above this steepness it reads as a stain on a cliff.
@export var max_slope: float = 0.22

var _zones: Array = []
var _player: Node3D
var _announced: String = ""


func _ready() -> void:
	var terrain: Node = get_parent().get_node_or_null("Terrain")
	if terrain == null:
		push_warning("[qi] no terrain to place zones on")
		return
	_place(terrain)
	# Leaving the scene must not leave a boost applied to a body that is nowhere near
	# a zone any more.
	tree_exiting.connect(_clear)


## Rejection-samples each catalogue entry until it finds level, well-separated ground inside
## that entry's own ring.
##
## Each zone gets its own attempt budget and its own band, and a zone whose band turns out to
## be all hillside relaxes *outward* rather than being given up on: the inner edge is the
## part that matters (a zone must be on the far side of the ward whose ring it powers), and
## the outer band is only there to keep it away from the rim. The last resort widens the
## slope it will accept, because a zone on a gentle hill is a much smaller problem than a
## ring with no zone in it at all.
func _place(terrain: Node) -> void:
	var extent: float = 64.0
	if terrain.has_method("extent"):
		extent = float(terrain.call("extent"))
	var rng := RandomNumberGenerator.new()
	rng.seed = zone_seed
	var notes: Array = []
	for index in ZONE_DEFS.size():
		var defn: Dictionary = ZONE_DEFS[index]
		var band: Vector2 = defn.get("reach", Vector2(0.30, 0.76))
		var placed: Dictionary = _sample(index, defn, band, terrain, rng, 0.0)
		if placed.is_empty():
			placed = _sample(index, defn, band, terrain, rng, 0.5)
		if placed.is_empty():
			placed = _sample(index, defn, band, terrain, rng, 1.0)
		if placed.is_empty():
			push_warning("[qi] no ground for %s in %.2f–%.2f" % [defn["name"], band.x, band.y])
			continue
		_zones.append(placed)
		_build(placed)
		notes.append("%s(ring %d, r=%.0f m, x%.1f%s)" % [
			placed["name"], index,
			Vector2(placed["position"].x, placed["position"].z).length(),
			float(placed["boost"]),
			"" if placed["relax"] == 0.0 else ", relaxed",
		])
	print("[qi] %d/%d zones placed: %s" % [
		_zones.size(), ZONE_DEFS.size(), ", ".join(notes),
	])


## One zone's search. `relax` walks the band's outer edge out towards the rim and loosens
## the slope it will accept, so a stubborn ring still gets its zone.
func _sample(index: int, defn: Dictionary, band: Vector2,
		terrain: Node, rng: RandomNumberGenerator, relax: float) -> Dictionary:
	var extent: float = float(terrain.call("extent"))
	var outer: float = lerpf(band.y, 0.965, relax)
	var slope_limit: float = lerpf(max_slope, max_slope * 2.4, relax)
	for attempt in 240:
		var angle: float = rng.randf_range(0.0, TAU)
		# Inside the far corners: the terrain is square, so the inscribed disc is the only
		# region where a radius-sized disc is guaranteed to fit.
		var reach: float = extent * rng.randf_range(band.x, outer)
		var x: float = cos(angle) * reach
		var z: float = sin(angle) * reach
		if Vector2(x, z).length() < camp_clearance:
			continue
		# Not on top of a village, and not on the tower's step: a zone is a patch of wild ground,
		# and the whole point of the settlements is that they are the places it is not.
		if Villages.near_site(x, z, 10.0):
			continue
		var too_close: bool = false
		for other: Dictionary in _zones:
			var centre: Vector3 = other["position"]
			if Vector2(x - centre.x, z - centre.z).length() < zone_separation:
				too_close = true
				break
		if too_close:
			continue
		if terrain.has_method("slope_at") and float(terrain.call("slope_at", x, z)) > slope_limit:
			continue
		var entry: Dictionary = defn.duplicate()
		entry["ring"] = index
		entry["relax"] = relax
		entry["position"] = Vector3(x, float(terrain.call("surface_height_at", x, z)), z)
		return entry
	return {}


func _build(zone: Dictionary) -> void:
	var radius: float = float(zone["radius"])
	var tint: Color = Color(String(zone["color"]))
	var root := Node3D.new()
	root.name = "Zone_" + String(zone["id"])
	root.position = zone["position"]
	add_child(root)
	zone["node"] = root

	# A flat ring is the cheapest thing that reads as "a place" rather than as a
	# puddle, and it marks the boundary the boost actually uses.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.5, radius - 0.35)
	torus.outer_radius = radius
	ring.mesh = torus
	ring.material_override = _glow(tint, 0.8)
	ring.position = Vector3(0.0, 0.14, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)

	# The column, so the zone can be found from high ground. Tall and faint: a zone
	# you can see across the valley is a destination, one you trip over is scenery.
	var column := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.10
	cylinder.bottom_radius = radius * 0.20
	cylinder.height = 9.0
	column.mesh = cylinder
	column.material_override = _glow(tint, 0.11)
	column.position = Vector3(0.0, 4.5, 0.0)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(column)

	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = tint
	light.light_energy = 1.4
	light.omni_range = radius * 1.1
	light.position = Vector3(0.0, 1.7, 0.0)
	light.shadow_enabled = false
	root.add_child(light)


## One soft glowing surface. Emission is a share of the tint rather than a bonus on
## top of it, so a pale element cannot sum past white and lose its colour.
func _glow(tint: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	const EMISSION_SHARE := 0.3
	material.albedo_color = Color(
		tint.r * (1.0 - EMISSION_SHARE), tint.g * (1.0 - EMISSION_SHARE),
		tint.b * (1.0 - EMISSION_SHARE), alpha)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = EMISSION_SHARE
	return material


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_parent().get_node_or_null("Player") as Node3D
		if _player == null:
			return
	var zone: Dictionary = zone_at(_player.global_position)
	if zone.is_empty():
		_clear()
		return
	var required: int = int(zone["required_tier"])
	var ring: int = int(zone.get("ring", 0))
	# Two ways for a zone to be dormant, and they are different answers for the player:
	# a champion is standing on it, or the cultivator has not reached the stage it wants.
	var awake: bool = Wards.zone_awake(ring)
	var unlocked: bool = awake and Cultivation.tier >= required
	Cultivation.zone_name = String(zone["name"])
	Cultivation.zone_required_tier = required
	Cultivation.zone_locked = not unlocked
	Cultivation.zone_boost = float(zone["boost"]) if unlocked else 1.0
	_announce(zone, unlocked, awake, ring)


## Says something once per zone rather than once per frame, which is the difference
## between an event log and a stutter.
func _announce(zone: Dictionary, unlocked: bool, awake: bool, ring: int) -> void:
	var key: String = "%s:%s:%s" % [zone["id"], unlocked, awake]
	if key == _announced:
		return
	_announced = key
	if unlocked:
		Cultivation.log_message.emit(
			"Spirit zone: %s — cultivating here runs at ×%.1f."
			% [zone["name"], float(zone["boost"])], "cultivate")
		return
	if not awake:
		# Naming the champion is the whole message: it is the only way to wake the ground,
		# and "something is standing on it" is what makes the zone a place to fight for
		# rather than a place to walk to.
		var warden: Dictionary = Wards.warden_of_ring(ring)
		Cultivation.log_message.emit(
			"%s is asleep — %s is standing on it." % [
				zone["name"], String(warden.get("label", "something")),
			], "damage")
		return
	Cultivation.log_message.emit(
		"%s is dormant for you. It answers at stage %s."
		% [zone["name"], _numeral(int(zone["required_tier"]))], "info")


func _clear() -> void:
	_announced = ""
	Cultivation.zone_name = ""
	Cultivation.zone_boost = 1.0
	Cultivation.zone_locked = false
	Cultivation.zone_required_tier = 0


# -------------------------------------------------------------------- querying

## The zone whose disc contains a world position, or an empty dictionary. Flat in XZ:
## a zone is a region of ground, so being above it in a jump does not leave it.
func zone_at(position: Vector3) -> Dictionary:
	for zone: Dictionary in _zones:
		var centre: Vector3 = zone["position"]
		var dx: float = position.x - centre.x
		var dz: float = position.z - centre.z
		var radius: float = float(zone["radius"])
		if dx * dx + dz * dz <= radius * radius:
			return zone
	return {}


func zone_count() -> int:
	return _zones.size()


func zones() -> Array:
	return _zones.duplicate()


## Roman numerals, matching the stage label over the character's head.
func _numeral(value: int) -> String:
	if value <= 0:
		return "-"
	var digits: Array = [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]
	var out: String = ""
	var left: int = value
	for pair: Array in digits:
		while left >= int(pair[0]):
			out += String(pair[1])
			left -= int(pair[0])
	return out
