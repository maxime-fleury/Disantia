extends Node3D
## Raider camps: the world's pressure, one ring at a time.
##
## Each camp is a fire, a few props, a banner and a handful of raiders with a shared home
## position. They are placed by rejection sampling on level, well-separated ground rather
## than at authored coordinates, because the terrain is procedural: a hand-picked spot would
## be a bet on the noise field, and a camp half-buried in a hillside reads as a bug when the
## whole point is that it is a *place*.
##
## What changed when the wards went in is that `distance from the fire` is no longer what
## decides which camp is hard. The map is concentric now, and a camp's difficulty is the ring
## it stands in — so the hardest fight in the game is not the one furthest away, it is the
## one behind the last wall. A camp is also density-controlled by ring, which is how the
## near ground stays a place you can learn to run in.
##
## The three champion camps are the exception to the sampling: each is placed *on* the spirit
## zone of its ring, because that is the entire point of a champion. They hold the ground
## that makes the next realm cheap, which turns "walk to the zone" into a fight you choose the
## moment for, and turns a ring into a chapter rather than a distance.

const STRUCTURES := "res://assets/structures/"
const PROPS := "res://assets/props/"
const EnemyScript := preload("res://scripts/enemy/enemy.gd")

## The rings, counted outward from the fire, with the ground each one owns.
##
## `inner`/`outer` are fractions of the map's half-extent, so the whole world layout is one
## table that scales with the terrain rather than a set of distances that have to be edited
## whenever it grows. `hp`, `damage` and `crystals` are what a raider in that ring is worth;
## `camps` and `raiders` are how much of it there is to meet.
const RINGS: Array = [
	{"inner": 0.30, "outer": 0.40, "camps": 2, "raiders": 2,
		"hp": 0.70, "damage": 8.0, "crystals": 2},
	{"inner": 0.44, "outer": 0.62, "camps": 2, "raiders": 2,
		"hp": 1.00, "damage": 11.0, "crystals": 3},
	{"inner": 0.66, "outer": 0.78, "camps": 2, "raiders": 2,
		"hp": 1.60, "damage": 16.0, "crystals": 5},
	{"inner": 0.82, "outer": 0.955, "camps": 1, "raiders": 1,
		"hp": 2.40, "damage": 22.0, "crystals": 8},
]

## Hit points of a plain raider in ring 0, before the ring's multiplier.
const RAIDER_HP := 55.0
const RAIDER_ATTACK_XP := 26.0

@export var camp_seed: int = 88211
## How far from the origin the nearest camp may be. Comfortably outside the safe zone
## radius, so a camp is never visible from inside the wards.
@export var camp_clearance: float = 44.0
@export var camp_separation: float = 54.0
## How far an ordinary camp has to stay from a spirit zone, measured from the zone's rim.
##
## A camp's raiders do not attack while the player is inside the camp wards, but a spirit
## zone is not a ward — and a zone with a raider camp leaning on it is a zone you cannot
## cultivate in at all, because every blow taken stops the trance. Nothing was keeping the
## two apart, and one of the two rings' worth of camps landed close enough to the spring to
## make the whole zone useless. The suite caught it as a *rate* — cultivating in the zone
## measured slower than cultivating on bare ground.
##
## The champions' camps are exempt: standing on the zone is what a champion is for.
@export var zone_clearance: float = 26.0
## A camp wants level ground for the same reason a spirit zone does.
@export var max_slope: float = 0.26
## Raiders are placed in a ring this far from the fire.
@export var raider_ring: float = 2.6
## Raiders standing around a champion. Fewer than a normal camp: the champion is the fight,
## and three extra bodies in front of it is a queue rather than a boss.
@export var champion_retinue: int = 2

var _camps: Array = []
var _enemies: Array = []
var _left_out: Array = []
var _terrain: Node
## Half the map's width, resolved once during placement.
var _extent: float = 64.0
## Seeded, like the scatter and the spirit zones: the ground a raider stands on decides which
## of them a blow lands on, so an unseeded camp is a world that is subtly different every
## launch — and a raid that went one way yesterday for no reason the player can see.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_terrain = get_parent().get_node_or_null("Terrain")
	if _terrain == null:
		push_warning("[camps] no terrain to place camps on")
		return
	_extent = 64.0
	if _terrain.has_method("extent"):
		_extent = float(_terrain.call("extent"))
	# Late enough that the autoload exists, early enough that the walls, the zones and the
	# map all divide by the same number this file does.
	Wards.extent = _extent
	_place()
	print("[camps] %d camps, %d raiders, %d champions: %s" % [
		_camps.size(), _enemies.size() - _champion_count(), _champion_count(),
		", ".join(_camps.map(func(c: Dictionary) -> String:
			return "%s(ring %d, %.0f m, %d%s)" % [
				c["name"], int(c["ring"]), float(c["distance"]), int(c["raiders"]),
				"" if String(c["warden"]) == "" else " + champion"])),
	])


## A decision outlives the session it was made in, and the world is built from scratch every
## launch — so a camp that was burned has to be burned again the moment the camp exists, or
## the save would record the choice and the ground would quietly disagree with it.
func _apply_decisions() -> void:
	var subject: String = PlayerData.decision_subject("camp")
	var key: String = PlayerData.chosen_option("camp")
	if subject == "" or key == "":
		return
	resolve_camp(subject, key, false)


func _place() -> void:
	_rng.seed = camp_seed
	var name_index: int = 0
	for ring in RINGS.size():
		var spec: Dictionary = RINGS[ring]
		for i in int(spec["camps"]):
			var spot: Vector3 = _sample_ground(float(spec["inner"]), float(spec["outer"]), 0.0)
			if spot == Vector3.INF:
				continue
			_build(name_for(name_index), spot, ring, {})
			name_index += 1
	_place_champions()


## Puts each champion, and its retinue, on the spirit zone of the ring it holds.
##
## The zone is asked for rather than searched for, so the champion stands on the ground the
## boost actually uses — including the case where the zone was placed with a relaxed band,
## which a second copy of the layout maths here would not have known about.
func _place_champions() -> void:
	var zones: Node = get_parent().get_node_or_null("QiZones")
	if zones == null or not zones.has_method("zones"):
		push_warning("[camps] no qi zones; the champions have nowhere to stand")
		return
	var placed: Array = zones.call("zones")
	for gate: Dictionary in Wards.GATES:
		var warden: Dictionary = gate["warden"]
		if Wards.warden_down(String(warden["id"])):
			# Felled in an earlier session. The camp does not come back either: the ring it
			# held stays yours, which is what walking back out here has to keep meaning.
			_left_out.append(String(warden["id"]))
			continue
		var ring: int = int(warden["ring"])
		var zone: Dictionary = {}
		for candidate: Dictionary in placed:
			if int(candidate.get("ring", -1)) == ring:
				zone = candidate
				break
		if zone.is_empty():
			push_warning("[camps] no zone in ring %d for %s" % [ring, warden["label"]])
			continue
		var centre: Vector3 = zone["position"]
		# The fire goes beside the zone rather than in the middle of it, so the champion is
		# visibly standing over the ground it is denying you rather than in a camp that
		# happens to be nearby.
		var offset: Vector2 = Vector2(cos(_rng.randf_range(0.0, TAU)), sin(_rng.randf_range(0.0, TAU)))
		offset *= float(zone["radius"]) + 3.2
		var spot := Vector3(
			centre.x + offset.x,
			float(_terrain.call("surface_height_at", centre.x + offset.x, centre.z + offset.y)),
			centre.z + offset.y
		)
		# The gate's colour comes along, so a champion wears the colour of the wall it stands
		# behind and the map, the fence and the enemy in front of you all agree.
		var champion: Dictionary = warden.duplicate()
		champion["colour"] = gate.get("color", Color("ffd76e"))
		_build(String(zone["name"]) + " Camp", spot, ring, champion)


## Rejection-samples level, well-separated ground inside a band of the map. `relax` widens
## the band outward and the slope it will accept, so a ring whose ground is all hillside
## still gets its camps rather than quietly getting none.
func _sample_ground(inner: float, outer: float, relax: float) -> Vector3:
	var width: float = lerpf(outer, 0.965, relax)
	var slope_limit: float = lerpf(max_slope, max_slope * 2.4, relax)
	for attempt in 400:
		var angle: float = _rng.randf_range(0.0, TAU)
		var reach: float = _extent * _rng.randf_range(inner, width)
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
		if _terrain.has_method("slope_at") and float(_terrain.call("slope_at", x, z)) > slope_limit:
			continue
		if Villages.near_site(x, z, 12.0):
			continue
		if not _clear_of_zones(Vector2(x, z)):
			continue
		return Vector3(x, float(_terrain.call("surface_height_at", x, z)), z)
	# Nothing in the strict band. One more pass with the whole ring opened up, because a ring
	# with no camp in it is a hundred metres of nothing.
	if relax < 1.0:
		return _sample_ground(inner, outer, 1.0)
	return Vector3.INF


## True when a spot is far enough from every spirit zone to leave it usable. Read from the
## zones node rather than from a copy, so a zone that was placed with a relaxed band is still
## respected by the camp placer.
func _clear_of_zones(at: Vector2) -> bool:
	var zones: Node = get_parent().get_node_or_null("QiZones")
	if zones == null or not zones.has_method("zones"):
		return true
	for zone: Dictionary in zones.call("zones"):
		var centre: Vector3 = zone["position"]
		var reach: float = float(zone["radius"]) + zone_clearance
		if Vector2(at.x - centre.x, at.y - centre.z).length() < reach:
			return false
	return true


## Camp names are a list rather than generated, because a name is flavour and flavour that
## comes out of a loop reads like one.
const NAMES: Array = [
	"Bandit Hollow", "Ashfall Camp", "The Broken Wheel", "Thornwatch",
	"Cinder Camp", "Wolfrest", "Greyridge Camp", "The Long Reach", "Saltmarsh Watch",
]


func name_for(index: int) -> String:
	return String(NAMES[index % NAMES.size()])


func _build(camp_name: String, centre: Vector3, ring: int, warden: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Camp_" + camp_name.replace(" ", "")
	root.position = centre
	add_child(root)
	root.add_to_group("enemy_camp")

	var yaw: float = _rng.randf_range(0.0, TAU)
	# A fire is the anchor: it is the point the leash is measured from, so it is placed first
	# and everything else hangs off it.
	var cauldron: Node3D = _place_piece(PROPS + "Cauldron.gltf", root, 0.0, 0.0, yaw, centre)
	var glow := OmniLight3D.new()
	glow.name = "FireGlow"
	glow.light_color = Color("ff8a3c")
	glow.light_energy = 2.0
	glow.omni_range = 13.0
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 1.5, 0.0)
	root.add_child(glow)

	# The banner is what makes a camp findable: it is the tallest thing in one, and it is what
	# the signposts point you towards.
	var banner_spot: Vector2 = Vector2(cos(yaw + 1.1), sin(yaw + 1.1)) * 2.3
	_place_piece(PROPS + "Banner_1.gltf", root, banner_spot.x, banner_spot.y, yaw + 2.5, centre)
	var props: Array = ["Barrel.gltf", "Crate_Wooden.gltf", "Pot_1.gltf", "Bench.gltf", "Dummy.gltf"]
	for i in props.size():
		var angle: float = yaw + float(i) * 1.35
		var at: Vector2 = Vector2(cos(angle), sin(angle)) * _rng.randf_range(2.4, 3.8)
		_place_piece(PROPS + String(props[i]), root, at.x, at.y, _rng.randf_range(0.0, TAU), centre)

	# A champion's camp is a champion and a retinue, not a crowd.
	var count: int = champion_retinue if not warden.is_empty() else int(RINGS[ring]["raiders"])
	var placed: int = 0
	for i in count:
		var angle: float = yaw + TAU * float(i) / float(maxi(1, count))
		var at: Vector2 = Vector2(cos(angle), sin(angle)) * raider_ring
		if _spawn_raider(centre, at, ring, root) != null:
			placed += 1
	if not warden.is_empty():
		var champion := _spawn_champion(centre, ring, warden, root)
		placed += 1 if champion != null else 0
	_camps.append({
		"name": camp_name,
		"position": centre,
		"ring": ring,
		"distance": Vector2(centre.x, centre.z).length(),
		"node": root,
		"fire": cauldron,
		"raiders": placed,
		"warden": String(warden.get("id", "")),
		"warden_label": String(warden.get("label", "")),
		"colour": warden.get("colour", Color("ff6b5a")),
	})


## Places a kit piece so it sits on the ground. Every kit disagrees about where its origin
## lives, so the piece's own measured box decides: the lowest point goes on the surface at
## the spot it was placed.
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


## A new enemy with a capsule and the raider script, set up before it enters the tree:
## `_ready` fills its health from `max_hp` and sizes its model from `scale_factor`, so a
## value written afterwards would leave the far rings as soft as the first one.
func _spawn_enemy(scale_factor: float) -> CharacterBody3D:
	var enemy := CharacterBody3D.new()
	enemy.name = "Raider"
	enemy.set_script(EnemyScript)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36 * scale_factor
	capsule.height = 1.7 * scale_factor
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.86 * scale_factor, 0.0)
	enemy.add_child(shape)
	enemy.set("scale_factor", scale_factor)
	return enemy


## Every enemy is a *child of its camp*, so its own position is relative to the fire and its
## `home` — which the AI measures in world space, and which is what a leashed raider walks
## back to — has to be worked out from the camp's placement rather than handed the same
## vector twice. Giving both the same number puts the guard one camp-width away from its own
## fire: it then stands at twice the distance it was placed at, leashed to a home that is
## nowhere near the ground it is supposed to be guarding.
func _local_spot(centre: Vector3, dx: float, dz: float) -> Vector3:
	return Vector3(dx, float(_terrain.call("surface_height_at", centre.x + dx, centre.z + dz)) - centre.y, dz)


func _spawn_raider(centre: Vector3, offset: Vector2, ring: int, root: Node3D) -> Node3D:
	var spec: Dictionary = RINGS[ring]
	var local: Vector3 = _local_spot(centre, offset.x, offset.y)
	var enemy: CharacterBody3D = _spawn_enemy(1.0)
	enemy.set("max_hp", RAIDER_HP * float(spec["hp"]))
	enemy.set("attack_damage", float(spec["damage"]))
	enemy.set("crystals", int(spec["crystals"]))
	enemy.set("attack_xp", RAIDER_ATTACK_XP)
	enemy.set("home", centre + local)
	enemy.position = local
	root.add_child(enemy)
	_enemies.append(enemy)
	return enemy


## One of the named champions. Health is the player's own blow multiplied by the champion's
## `hp_blows`, so a champion is always about that many swings from dead — see the note on
## `Wards.GATES` for why that is the opposite of what a raider does.
func _spawn_champion(centre: Vector3, ring: int, warden: Dictionary,
		root: Node3D) -> Node3D:
	var id: String = String(warden["id"])
	if Wards.warden_down(id):
		return null
	var local: Vector3 = _local_spot(centre, 0.0, 0.0)
	var enemy: CharacterBody3D = _spawn_enemy(float(warden["scale"]))
	var blows: float = float(warden["hp_blows"])
	var hp: float = clampf(
		PlayerData.strike_damage() * blows, float(warden["hp_floor"]), float(warden["hp_ceil"])
	)
	enemy.name = String(warden["label"]).replace(" ", "")
	enemy.set("max_hp", hp)
	enemy.set("attack_damage", float(warden["damage"]))
	enemy.set("crystals", int(warden["crystals"]))
	enemy.set("display_name", String(warden["label"]))
	enemy.set("warden_id", id)
	enemy.set("reward_caps", warden["reward"])
	enemy.set("rune_color", Color(warden.get("colour", Color("ffd76e"))))
	enemy.set("bolt_damage", float(warden.get("bolt_damage", 0.0)))
	# A champion is harder to run away from than a raider without being inescapable: it sees
	# further and holds its ground longer, and past its leash it still goes home.
	enemy.set("aggro_radius", 20.0)
	enemy.set("leash_radius", 34.0)
	enemy.set("give_up_radius", 34.0)
	enemy.set("respawn_seconds", INF)
	enemy.set("home", centre + local)
	enemy.position = local
	root.add_child(enemy)
	_enemies.append(enemy)
	return enemy


func _champion_count() -> int:
	var total: int = 0
	for enemy: Node in _enemies:
		if enemy.get("warden_id") != null and String(enemy.get("warden_id")) != "":
			total += 1
	return total


# -------------------------------------------------------------------- querying

func camps() -> Array:
	return _camps.duplicate()


func enemies() -> Array:
	return _enemies.duplicate()


func raider_count() -> int:
	var total: int = 0
	for enemy: Node in _enemies:
		if not bool(enemy.call("is_champion")):
			total += 1
	return total


## Wardens whose champion was never built because the ring was already held when the world was
## made. Recorded rather than recomputed, and `_place_champions` is the only thing that can
## record it: by the time anybody asks, the save that came in has been reset and this question
## — "is the world supposed to have a champion fewer than the table lists" — has no other
## answer. The suite is the caller.
func warden_left_out() -> Array:
	return _left_out.duplicate()


## Raiders still on their feet. The count that means something after a decision: the bodies a
## camp has lost stay in `_enemies` — they are nodes waiting to be restocked — so counting the
## list would report a camp that is no longer standing.
func living_raiders() -> int:
	var total: int = 0
	for enemy: Node in _enemies:
		if bool(enemy.call("is_champion")) or bool(enemy.call("is_dead")):
			continue
		total += 1
	return total


## The champions standing in the world this session, by warden id.
func champions() -> Array:
	var out: Array = []
	for enemy: Node in _enemies:
		if bool(enemy.call("is_champion")):
			out.append(enemy)
	return out


## The champion a couple of metres away from a position, or null. Used by the tests and by
## anything that needs to find a boss without knowing where its camp went.
func champion_near(position: Vector3, radius: float = 6.0) -> Node3D:
	var best: Node3D
	var best_distance: float = radius
	for enemy: Node3D in champions():
		var d: float = Vector2(
			enemy.global_position.x - position.x, enemy.global_position.z - position.z
		).length()
		if d <= best_distance:
			best_distance = d
			best = enemy
	return best


## The world's side of the camp decision.
##
## Burn: the camp's raiders are taken out of it through the ordinary death path, so the
## spoils and the training land where they always do. Spare: the raiders stay standing and
## lose their interest in the player. Champions are left alone in both cases — a named
## warden is not a decision made in a conversation, it is a fight that has to be fought.
##
## `announce` is off when this is being re-applied to a save, where there is nobody to tell.
func resolve_camp(camp_name: String, choice: String, announce: bool = true) -> int:
	var touched: int = 0
	for camp: Dictionary in _camps:
		if String(camp["name"]) != camp_name:
			continue
		var root: Node3D = camp["node"] as Node3D
		for node: Node in _enemies:
			var enemy: Node3D = node as Node3D
			if enemy == null or not is_instance_valid(enemy) or not root.is_ancestor_of(enemy):
				continue
			if enemy.has_method("is_champion") and bool(enemy.call("is_champion")):
				continue
			touched += 1
			if choice == "burn":
				var full: float = float(enemy.get("max_hp")) + 1.0
				enemy.call("take_hit", full, root.global_position)
			elif enemy.has_method("pacify"):
				enemy.call("pacify")
		if announce:
			PlayerData.log_message.emit(
				("%s burns — %d raiders did not leave it." if choice == "burn"
					else "%s is left standing. %d raiders will look the other way.")
					% [camp_name, touched],
				"breakthrough"
			)
		return touched
	return 0


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
