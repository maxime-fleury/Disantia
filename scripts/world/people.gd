extends Node3D
## Puts the cast in the world.
##
## The people are built from the story's own table rather than listed in the scene file, which
## is the whole reason this is a script: the number of people standing in the world and the
## number of people the story knows about cannot drift apart. That drift is exactly how a game
## ends up with one character in it while its dialogue file describes four.
##
## Placement is in two flavours. Somebody with an offset stands on the camp plateau at that
## offset from the fire, so moving the fire moves them. Somebody with a road index is put down
## on that road a little way out and walks it for the rest of the run — and that one is worth
## the extra code, because a road with a figure on it stops being a texture and starts being
## the reason the road was drawn.

const VillagerScript := preload("res://scripts/world/villager.gd")
## How far along its road a walker starts, so nobody begins in the player's face.
const ROAD_START := 34.0

var _villagers: Array = []
var _terrain: Node


func _ready() -> void:
	_terrain = get_tree().root.get_node_or_null("Main/Terrain")
	place()
	var walkers: int = 0
	for node: Node in _villagers:
		if bool(node.call("is_on_road")):
			walkers += 1
	print("[people] %d in the world, %d of them walking a road: %s" % [
		_villagers.size(), walkers, _names(),
	])


## Builds every person in the cast. Public, so the tests can rebuild the crowd after moving
## the world under it.
func place() -> void:
	for entry: Dictionary in Story.cast():
		var id: String = String(entry["id"])
		var villager: Node = VillagerScript.new()
		villager.name = id.capitalize()
		villager.set("person_id", id)
		villager.set("npc_name", String(entry["name"]))
		villager.set("robe_color", entry["colour"])
		villager.set("target_height", 1.68)
		add_child(villager)
		_villagers.append(villager)
		if entry.has("road"):
			villager.set("road_index", int(entry["road"]))
			villager.call("take_to_road", _road(int(entry["road"])))
			continue
		var offset: Vector2 = entry.get("at", Vector2.ZERO)
		_stand_at(villager, Vector3(offset.x, 0.0, offset.y))
		villager.set("facing_degrees", 180.0 if offset.y > 0.0 else 0.0)
		if bool(entry.get("wanders", false)):
			# A short beat walked over and over instead of a road: somebody moving about the
			# place they live. Same code as the road walkers, three points instead of forty —
			# the difference between a figure on a road and a figure at a fire is entirely
			# how far apart the points are.
			villager.call("take_to_road", _beat(offset))


## Stands somebody on the ground at a point offset from the camp fire at the origin.
func _stand_at(villager: Node, offset: Vector3) -> void:
	var y: float = 0.0
	if _terrain != null and _terrain.has_method("surface_height_at"):
		y = float(_terrain.call("surface_height_at", offset.x, offset.z))
	villager.global_position = Vector3(offset.x, y, offset.z)


## One road's points, walked forward from a fixed distance in so a walker always starts at the
## same place — the same road, the same figure, every launch.
func _road(index: int) -> PackedVector2Array:
	if _terrain == null or not _terrain.has_method("roads"):
		return PackedVector2Array()
	var roads: Array = _terrain.call("roads")
	if index < 0 or index >= roads.size():
		return PackedVector2Array()
	var points: PackedVector2Array = roads[index]["points"]
	if points.size() < 2:
		return PackedVector2Array()
	var travelled: float = 0.0
	for i in range(1, points.size()):
		var segment: float = points[i - 1].distance_to(points[i])
		if travelled + segment >= ROAD_START:
			return PackedVector2Array(points.slice(i - 1))
		travelled += segment
	return points


## A three-point walk around a spot: out along one shoulder, across, and back.
func _beat(centre: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		centre,
		centre + Vector2(2.6, 0.0),
		centre + Vector2(1.3, 2.3),
	])


func _names() -> String:
	var out: Array = []
	for node: Node in _villagers:
		out.append(String(node.get("npc_name")))
	return ", ".join(out)


func villagers() -> Array:
	return _villagers.duplicate()


func count() -> int:
	return _villagers.size()


## The person nearest a world position, or null. Used by the tests to walk up to somebody
## without knowing where the crowd was placed.
func nearest(position: Vector3) -> Node3D:
	var best: Node3D
	var best_distance: float = INF
	for node: Node in _villagers:
		var person := node as Node3D
		if person == null or not is_instance_valid(person):
			continue
		var d: float = Vector2(
			person.global_position.x - position.x, person.global_position.z - position.z
		).length()
		if d < best_distance:
			best_distance = d
			best = person
	return best
