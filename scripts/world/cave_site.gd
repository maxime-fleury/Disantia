extends Node3D
## The Hollow — the one place on the map the sky does not reach.
##
## Every other site in this valley is *found*: a beacon you can see from a hill, a road that
## leads to it, a name on the minimap. That is the right design for nine places and it is the
## wrong one for a tenth, because it makes the lamp a stat rather than a tool. The lamp was
## bought, carried, and upgraded at an anvil to light a *circle* — and until there was somewhere
## the circle was the only light you had, it was decoration.
##
## So this is the answer to "what is the lamp for": a hollow in the rock, roofed, with no
## ambient light inside it at all. Two rules do the work, and neither of them is a special case
## bolted onto the game:
##
##   * **The roof is geometry.** A stone dome over the clearing, so the sun genuinely does not
##     get in — the shadows are the engine's, not a shader trick. It is a *hill* from outside
##     and a cave from within, which is exactly what a cave is.
##   * **The Hollow is dark to the clock, not just to the eye.** `Clock.set_darkness_floor` says
##     it is dark here whatever the hour, which is what makes the lamp strike. That single line
##     is why the lamp lights in a cave at noon without the lantern knowing the cave exists: it
##     asks the clock, and the clock is answering about the place.
##
## What is in it: four dwellers with a short leash, and a cold stone on a slab with the Ninth's
## mark on it. The prize is an *interactable* like every other, so the same line at the foot of
## the screen says what E does — but the prompt only appears when the body is standing at the
## slab, and in the dark, without a lamp, the body does not find the slab.
##
## The one mechanical bite: **unlit inside, a strike lands for half.** You cannot aim at what you
## cannot see, the same reason the damage numbers are drawn at all. It is a rule the player can
## feel in the first fight and reason about immediately, which is more than any of the numbers
## here can say.

const NATURE := "res://assets/nature/"
const PROPS := "res://assets/props/"
const STRUCTURES := "res://assets/structures/"

## Flat radius of the inside. Big enough for four body-lengths of darkness around the slab, small
## enough that the dome is a hill rather than a stadium.
const INTERIOR := 15.5
## Half-angle of the opening, in radians. The mouth faces the home camp, so the walk in from the
## road arrives at it head-on rather than circling the hill looking for the way.
const MOUTH_ARC := 0.62
## Where it stands: a fraction of the map's half-extent from the origin, on a bearing. Half the
## map out, which puts it *past the first ward* — a lamp is bought in a village, the villages are
## opened by the elder's chain, and a hollow you can walk to in the first minute is a hollow you
## walk into without the one object it is about.
const DISTANCE_SHARE := 0.52
const BEARING_DEGREES := 131.0
## How far the hill keeps from anything else that is already standing somewhere: the nine sites,
## the raider camps, the spirit zones and the tower. A rock dome dropped on top of a beacon is a
## discovery buried under a hill, and the failure would look like a missing site.
const CLEARANCE := 36.0

## How often the place checks whether the body is in it. A cave is a room you walk into, not a
## trigger you cross, and the cost of noticing late is a frame of sunlight on the wall.
const POLL := 0.2
const PRIZE_RADIUS := 3.4
## The save's name for this place, in the same list the nine sites use, so "found" is remembered
## by the same mechanism and survives a reload for the same reason.
const PRIZE_ID := "hollow"
const NAME := "The Hollow"

## The dwellers. Few and slow to notice, because the dark is the difficulty here and four things
## that see in it are already four too many.
const DWELLERS := 4
const DWELLER_HP := 78.0
const DWELLER_DAMAGE := 11.0
const DWELLER_CRYSTALS := 9
## They notice you late and let go early. A body that walks in without a lamp has to be able to
## walk back out: a fight in the pitch dark against something that will not let go is not a
## lesson, it is a reload.
const DWELLER_AGGRO := 10.0
const DWELLER_LEASH := 16.0

const PRIZE_CRYSTALS := 45
const PRIZE_BOONS: Array = [["qi", 16.0], ["attack", 4.0]]

const ROCK_TINT := Color("3b3a3c")
const INNER_TINT := Color("15161a")

@export var enabled: bool = true
@export var cave_seed: int = 90211

var _terrain: Node
var _player: Node3D
var _lantern: Node
var _camera: Camera3D
var _environment: Environment
var _rng := RandomNumberGenerator.new()
var _slab: Node3D
var _chest: Node3D
var _dwellers: Array[Node3D] = []

var _placed: bool = false
var _inside: bool = false
var _timer: float = 0.0
## How many times the body has walked in. A count rather than a flag so a check can tell "entered"
## from "never got there".
var entrances: int = 0
var _taken: bool = false
var _roused: bool = false


func _ready() -> void:
	if not enabled:
		return
	_terrain = get_parent().get_node_or_null("Terrain")
	_player = get_parent().get_node_or_null("Player") as Node3D
	if _player != null:
		_lantern = _player.get_node_or_null("Lantern")
		_camera = _player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	if _terrain == null:
		push_warning("[cave] no terrain to stand on")
		return
	add_to_group("cave")
	_rng.seed = cave_seed
	# Placed on the first frame rather than here. `_place` has to see the nine sites, the camps,
	# the zones and the tower, and a sibling's `_ready` has not run yet when this one does — the
	# order of the scene file would become load-bearing, and the failure is a hill on top of
	# something the player was meant to find.
	set_process(true)
	_taken = PlayerData.found_landmarks.has(PRIZE_ID)


# ------------------------------------------------------------------------ placement

## A level spot on the chosen bearing, walked outward if the first choice is water-thin, inside a
## village, or inside the home camp. Every other site on the map is placed by the roads; this one
## is placed by the hill it is a hole in, so it does its own search.
func _place() -> void:
	var share: float = DISTANCE_SHARE
	var bearing: float = deg_to_rad(BEARING_DEGREES)
	for attempt in 24:
		var reach: float = float(_terrain.call("extent")) * share
		var spot := Vector2(cos(bearing) * reach, sin(bearing) * reach)
		var height: float = float(_terrain.call("surface_height_at", spot.x, spot.y))
		if _good_ground(spot) and float(_terrain.call("slope_at", spot.x, spot.y)) <= 0.16:
			position = Vector3(spot.x, height, spot.y)
			return
		# Out and around: a fraction further each time and a fifth of a turn over, which walks a
		# spiral rather than a line — a bearing that lands in a village has to be able to find the
		# far side of the map.
		share = minf(0.52, share + 0.012)
		bearing += 0.41
	position = Vector3(60.0, float(_terrain.call("surface_height_at", 60.0, 60.0)), 60.0)


func _good_ground(spot: Vector2) -> bool:
	if spot.length() < 90.0:
		return false
	if spot.length() > float(_terrain.call("extent")) * 0.72:
		return false
	if Haven.contains(Vector3(spot.x, 0.0, spot.y)):
		return false
	for standing: Vector3 in _occupied():
		if Vector2(spot.x - standing.x, spot.y - standing.z).length() < CLEARANCE + INTERIOR:
			return false
	# Clear of the villages by more than the radius of the hill: a hollow that opens inside a
	# town's walls is a town with a hole in it, and the music would rather agree with the map.
	for village: Dictionary in Villages.all():
		var site: Dictionary = Haven.site(String(village["id"]))
		if site.is_empty():
			continue
		var centre: Vector3 = site["centre"]
		if Vector2(spot.x - centre.x, spot.y - centre.z).length() < float(site["radius"]) + INTERIOR + 8.0:
			return false
	return true


## The ground the hill stands on, resolved through the same door the rest of the world uses.
func ground_at(x: float, z: float) -> float:
	return float(_terrain.call("surface_height_at", x, z))


## Everything already standing somewhere that this hill has to keep away from. Asked of the
## groups and the autoloads rather than of a list kept here, so a tenth site or a new zone is
## respected without anybody remembering to add it.
func _occupied() -> Array:
	var out: Array = []
	for node: Node in get_tree().get_nodes_in_group("landmark"):
		if node is Node3D:
			out.append((node as Node3D).global_position)
	var sites: Node = get_parent().get_node_or_null("Landmarks")
	if sites != null and sites.has_method("sites"):
		for site: Dictionary in sites.call("sites"):
			out.append(site["position"] as Vector3)
	var camps: Node = get_parent().get_node_or_null("EnemyCamps")
	if camps != null and camps.has_method("camps"):
		for camp: Dictionary in camps.call("camps"):
			out.append(camp["position"] as Vector3)
	var zones: Node = get_parent().get_node_or_null("QiZones")
	if zones != null and zones.has_method("zones"):
		for zone: Dictionary in zones.call("zones"):
			out.append(zone["position"] as Vector3)
	var tower: Node = get_tree().get_first_node_in_group("tower_site")
	if tower != null and tower.has_method("base_position"):
		out.append(tower.call("base_position") as Vector3)
	return out


# --------------------------------------------------------------------------- the hill

func _build() -> void:
	var mouth: float = deg_to_rad(BEARING_DEGREES) + PI
	var rim_count: int = 16
	for i in rim_count:
		var angle: float = TAU * float(i) / float(rim_count)
		# The gap. Facing the way the body came from, so the light of the road is behind you when
		# you look in.
		if absf(wrapf(angle - mouth, -PI, PI)) < MOUTH_ARC:
			continue
		var distance: float = INTERIOR + _rng.randf_range(-0.6, 1.4)
		var piece: Node3D = _piece(NATURE, "Rock_Medium_%d.gltf" % (1 + i % 3), angle, distance,
			_rng.randf_range(1.5, 2.4), _rng.randf_range(0.0, TAU))
		if piece != null:
			_tint(piece, ROCK_TINT)
	# The lintel: two stones upright at the mouth and one across the top. Without it the opening
	# reads as a gap between boulders rather than as a way in.
	for side in [-1.0, 1.0]:
		var jamb: Node3D = _piece(NATURE, "Rock_Medium_1.gltf",
			mouth + side * MOUTH_ARC, INTERIOR - 0.4, 2.6, side * 0.3)
		if jamb != null:
			_tint(jamb, ROCK_TINT)
			jamb.translate(Vector3(0.0, 1.1, 0.0))
	var head: Node3D = _piece(NATURE, "Rock_Medium_3.gltf", mouth, INTERIOR - 0.2, 3.1, 0.0)
	if head != null:
		_tint(head, ROCK_TINT)
		head.translate(Vector3(0.0, 4.1, 0.0))

	_roof()

	# What is on the floor. Mushrooms, because a cave that has been sealed for long enough grows
	# them and because they are the one thing in the pack that reads as *underground*.
	for i in 9:
		var angle: float = _rng.randf_range(0.0, TAU)
		var distance: float = _rng.randf_range(3.0, INTERIOR - 2.0)
		_piece(NATURE, "Mushroom_Common.gltf", angle, distance, _rng.randf_range(0.8, 1.5), 0.0)
	for i in 5:
		var angle: float = _rng.randf_range(0.0, TAU)
		_piece(NATURE, "Pebble_Round_3.gltf", angle, _rng.randf_range(2.0, INTERIOR - 1.0), 1.6, 0.0)

	# The slab the stone sits on, at the back of the room, as far from the mouth as the hill allows.
	var far: float = mouth + PI
	_slab = _piece(STRUCTURES, "Floor_WoodLight.gltf", far, INTERIOR - 4.2, 1.4, 0.0)
	_chest = _piece(PROPS, "Chest_Wood.gltf", far, INTERIOR - 4.2, 1.0, 0.4)
	if _chest != null:
		_chest.name = "Prize"
	# Two torches nobody has lit, so the room says what it wants before the player has a lamp.
	_piece(PROPS, "Torch_Metal.gltf", far - 0.7, INTERIOR - 6.0, 1.0, 0.0)
	_piece(PROPS, "Torch_Metal.gltf", far + 0.7, INTERIOR - 6.0, 1.0, 0.0)


## The roof, and the whole of the darkness.
##
## Two hemispheres of the same mesh: a rock-coloured one seen from outside, and a smaller, almost
## black one seen from within. Two rather than one because a single dome either hides the hill
## from the road or shows the inside of the rock to the player — and a cave that is a hole from
## outside and a room from inside is the entire point. Nothing else in this file makes it dark:
## the sun is stopped by the stone and the shadows are the engine's.
func _roof() -> void:
	var outer := MeshInstance3D.new()
	outer.name = "Crown"
	var shell := SphereMesh.new()
	shell.is_hemisphere = true
	shell.radius = INTERIOR + 1.9
	shell.height = INTERIOR * 0.62
	shell.radial_segments = 40
	shell.rings = 14
	outer.mesh = shell
	outer.material_override = _stone(ROCK_TINT.lightened(0.06), 0.95)
	outer.position = Vector3(0.0, -0.4, 0.0)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# The seam under the rim: the crown meets the ground at its own edge and a rock ring drawn on
	# top of that edge hides the join, which is the only place a hemisphere looks like a hemisphere.
	add_child(outer)

	var inner := MeshInstance3D.new()
	inner.name = "Vault"
	var hollow := SphereMesh.new()
	hollow.is_hemisphere = true
	hollow.radius = INTERIOR + 1.1
	hollow.height = INTERIOR * 0.58
	hollow.radial_segments = 40
	hollow.rings = 14
	# Seen from inside. `flip_faces` on the mesh rather than `CULL_FRONT` on the material, because
	# it is the same sphere and this way the interior is lit by the normals that actually face it.
	hollow.flip_faces = true
	inner.mesh = hollow
	inner.material_override = _stone(INNER_TINT, 1.0)
	inner.position = Vector3(0.0, -0.2, 0.0)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inner)


## Places a kit piece at a polar offset from the centre and drops it onto the terrain, by the
## piece's own measured box — the same walk the landmarks and the camps use, because every kit in
## this project disagrees about where its origin lives.
func _piece(dir: String, file: String, angle: float, distance: float, scale: float,
		spin: float) -> Node3D:
	var scene: PackedScene = load(dir + file)
	if scene == null:
		return null
	var piece: Node3D = scene.instantiate()
	add_child(piece)
	var dx: float = cos(angle) * distance
	var dz: float = sin(angle) * distance
	var ground: float = ground_at(position.x + dx, position.z + dz)
	piece.scale = Vector3.ONE * scale
	var box: AABB = _bounds(piece)
	piece.position = Vector3(dx, ground - position.y - box.position.y * scale, dz)
	piece.rotation.y = spin
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


## Repaints a kit piece's meshes, so the rocks of the hill read as *this* rock rather than as the
## same grey boulder that stands in nine other places.
func _tint(node: Node, colour: Color, from: Transform3D = Transform3D.IDENTITY) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _stone(colour, 0.9)
	for child in node.get_children():
		_tint(child, colour, from)


func _stone(colour: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = 0.0
	return material


# -------------------------------------------------------------------------- the dark

## A flat circle, like the safe zone: a cave is a room you are either in or out of, and a sphere
## check would make the mouth a wall.
##
## False until the hill has been placed. It has to be: before placement the node sits at the
## origin and the player spawns at the origin, so an unplaced hill would swallow the body on the
## first frame and the game would start in the dark.
func contains(point: Vector3) -> bool:
	if not _placed:
		return false
	return Vector2(point.x - position.x, point.z - position.z).length() <= INTERIOR


func mouth_point() -> Vector3:
	var angle: float = deg_to_rad(BEARING_DEGREES) + PI
	return position + Vector3(cos(angle) * (INTERIOR + 1.0), 0.0, sin(angle) * (INTERIOR + 1.0))


func _process(delta: float) -> void:
	if not _placed:
		_place()
		_build()
		_placed = true
		print("[cave] %s at %s (%d dwellers, prize %s)" % [
			NAME, position, DWELLERS, "taken" if _taken else "untouched"
		])
	poll(delta)


## The room's clock, stepped. Separated from `_process` so a body can be walked in and out of
## here in one call: a check that has to sleep for a poll interval on a headless frame budget is
## a check that passes for the wrong reason.
func poll(delta: float) -> void:
	if _player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = POLL
	var now: bool = contains(_player.global_position)
	if now != _inside:
		_inside = now
		if now:
			_enter()
		else:
			_leave()
	if _inside:
		# Every poll rather than once on the way in: the lamp is lit and put out by the clock and
		# the tier, so a body can carry one in unlit and light it at the slab. Nothing here has to
		# know why the light changed, and the two cannot drift apart.
		PlayerData.unlit = not lit()


## Walking in: the world stops reaching the room, and the room wakes up.
func _enter() -> void:
	entrances += 1
	Clock.set_darkness_floor(1.0)
	if _camera != null:
		_camera.environment = _cave_environment()
	if not _roused:
		_rouse()
	PlayerData.log_message.emit("%s — the light stops at the mouth." % NAME, "info")
	if not lit():
		PlayerData.log_message.emit(
			"It is too dark in here to see your own hands. A lamp would change that.", "damage"
		)
	Audio.play("ui_close", -6.0, 0.7)
	# The bed changes on its own: the director asks where the body is, and this place answers.
	Music.set_region("cave")


func _leave() -> void:
	# Handed back to the clock and the sky rather than turned off, because both of them are still
	# running: the hour never stopped while the body was inside.
	Clock.set_darkness_floor(0.0)
	if _camera != null:
		_camera.environment = null
	PlayerData.unlit = false
	Audio.play("ui_open", -6.0, 1.1)


## The environment the camera renders while the body is in here.
##
## This is what "no ambient light inside" is made of: a background that is not the sky at all, and
## an ambient term small enough that the interior of the vault goes black between the lamp and
## the walls. The fog is short and cold so that the far side of the room fades rather than
## resolving, which is what makes fifteen metres feel like a chamber instead of a clearing.
func _cave_environment() -> Environment:
	if _environment != null:
		return _environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("04050a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("0a0d16")
	env.ambient_light_energy = 0.16
	env.fog_enabled = true
	env.fog_light_color = Color("0a0d14")
	env.fog_density = 0.055
	env.fog_sun_scatter = 0.0
	_environment = env
	return env


## Whether the body's own lamp is lighting the room. Asked of the lantern rather than tracked, so
## a lamp bought, upgraded or ignited after the body walked in is answered for immediately.
func lit() -> bool:
	if _lantern == null or not _lantern.has_method("is_lit"):
		return false
	return bool(_lantern.call("is_lit"))


# ----------------------------------------------------------------------- what lives here

## Built on the first entrance rather than at load. Four bodies standing in a dark room nobody has
## ever walked into are four bodies the player can hear walking about from the road.
func _rouse() -> void:
	_roused = true
	var factory: GDScript = load("res://scripts/enemy/enemy_factory.gd")
	for i in DWELLERS:
		var angle: float = TAU * float(i) / float(DWELLERS) + _rng.randf_range(-0.3, 0.3)
		var distance: float = _rng.randf_range(6.0, INTERIOR - 5.0)
		var at := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var enemy: CharacterBody3D = factory.make(1.12, "HollowThing")
		enemy.position = at + Vector3(0.0, 0.6, 0.0)
		factory.configure(enemy, DWELLER_HP, DWELLER_DAMAGE, DWELLER_CRYSTALS,
			position + at, Color("4a3f6b"), DWELLER_AGGRO, DWELLER_LEASH)
		add_child(enemy)
		_dwellers.append(enemy)


func dwellers() -> Array:
	return _dwellers


# ---------------------------------------------------------------------------- the prize

## The stone on the slab. The prompt only appears when the body is at the slab, and in here that is
## not a formality: finding it means having walked the room with a light.
func interact_prompt() -> String:
	if _taken or _player == null or _chest == null:
		return ""
	if _flat_distance(_player.global_position, _chest.global_position) > PRIZE_RADIUS:
		return ""
	return Loc.say("take the cold stone")


func _unhandled_input(event: InputEvent) -> void:
	if _taken or not event.is_action_pressed("interact"):
		return
	if interact_prompt() == "":
		return
	take()
	get_viewport().set_input_as_handled()


## The handover. Crystals and two caps, and the place is marked found through the same door the
## nine sites use — one list, one mechanism, so a reload restores it for the same reason it
## restores a landmark.
func take() -> Dictionary:
	if _taken:
		return {}
	_taken = true
	PlayerData.mark_landmark_found(PRIZE_ID)
	PlayerData.add_crystals(PRIZE_CRYSTALS)
	var granted: Array = []
	for pair: Array in PRIZE_BOONS:
		var stat_id: String = String(pair[0])
		if not PlayerData.has_stat(stat_id):
			continue
		var amount: float = PlayerData.grant_cap(stat_id, float(pair[1]))
		if amount > 0.0:
			granted.append("%s cap +%s" % [
				String(PlayerData.def(stat_id).get("label", stat_id)), String.num(amount, 0)
			])
	if _chest != null:
		_chest.visible = false
		Audio.play_at("confirm", _chest.global_position, -1.0, 0.9, 40.0)
	Audio.play("breakthrough", -4.0, 0.85)
	PlayerData.log_message.emit(
		"%s — a cold stone, scratched with the mark of the Ninth.  +%d crystals.%s" % [
			NAME, PRIZE_CRYSTALS, ("  " + ", ".join(granted) + ".") if not granted.is_empty() else ""
		],
		"gain"
	)
	Quests.report("discover", 1.0)
	return {"crystals": PRIZE_CRYSTALS, "boons": granted}


## True once the stone is off the slab. Public because the story wants to know: taking it is the
## first thing in the game the player does that somebody else will care about.
func taken() -> bool:
	return _taken


func inside() -> bool:
	return _inside


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func summary() -> Dictionary:
	return {
		"at": position,
		"interior": INTERIOR,
		"inside": _inside,
		"lit": lit(),
		"taken": _taken,
		"dwellers": _dwellers.size(),
		"entrances": entrances,
	}
