extends Node
## Every place in the world a body is safe standing in, in one list.
##
## There used to be exactly one, and the code said so: `safe_zone.gd` built the bubble over
## the home camp, and everything that cared about safety asked *the scene* for it — the enemy
## looked up the first node in a group, the controller asked the same node whether the player
## was inside it, the map drew it. That is fine right up until there is a second one. A
## village with a fence, a well and two people in it is a place nothing should follow you
## into, and with the rule nailed to one node the second village would have been scenery with
## raiders standing in it.
##
## So the rule lives here and the places register themselves. A village and the home camp are
## the same kind of thing to every system that asks: an enemy refuses to *enter* either and
## will not follow a body into one, and a beaten body wakes inside the nearest one rather
## than the only one. The difference between them is only the name that gets printed when you
## cross the line, which is the part the player actually reads.
##
## `wake` is where a body comes to inside a site. It is stored at registration rather than
## asked for later because where the ground is belongs to whoever built the place — the camp
## has a levelled plateau, a village has a plaza, and neither should be re-derived here.

signal entered(id: String, site: Dictionary)
signal left(id: String, site: Dictionary)
## A site was registered or removed: the map and the guards redraw.
signal changed

const HOME_ID := "camp"

## id -> {id, name, kind, centre, radius, wake, enter, exit}
var _sites: Dictionary = {}
## The site the player is standing in, or "" — cached so a crossing is one event rather
## than a per-frame comparison for every listener.
var _inside: String = ""

var _player: Node3D


## Adds a safe place, or replaces the one with this id. Idempotent on purpose: the world is
## rebuilt from scratch in the suite and on every launch, so a site that registered itself
## twice must be one site.
func register(site: Dictionary) -> void:
	var id: String = String(site.get("id", ""))
	if id == "":
		return
	var centre: Vector3 = site.get("centre", Vector3.ZERO)
	_sites[id] = {
		"id": id,
		"name": String(site.get("name", "somewhere")),
		"kind": String(site.get("kind", "village")),
		"centre": centre,
		"radius": maxf(1.0, float(site.get("radius", 12.0))),
		"wake": site.get("wake", centre + Vector3.UP),
		"enter": String(site.get("enter", "")),
		"exit": String(site.get("exit", "")),
	}
	changed.emit()


func unregister(id: String) -> void:
	if _sites.erase(id):
		if _inside == id:
			_inside = ""
		changed.emit()


func sites() -> Array:
	return _sites.values()


func has(id: String) -> bool:
	return _sites.has(id)


func site(id: String) -> Dictionary:
	return _sites.get(id, {})


## The home camp, which is also the fallback when a body is beaten somewhere with nothing
## built yet.
func home() -> Dictionary:
	return site(HOME_ID)


## The site whose disc contains a point, or an empty dictionary. Flat in XZ for a village —
## a fence is a fence however high you jump — but the camp's own bubble is asked of the
## `safe_zone` node so the camp keeps its spherical boundary. See `contains`.
func site_at(point: Vector3) -> Dictionary:
	for entry: Dictionary in _sites.values():
		var centre: Vector3 = entry["centre"]
		var dx: float = point.x - centre.x
		var dz: float = point.z - centre.z
		var radius: float = float(entry["radius"])
		if dx * dx + dz * dz <= radius * radius:
			return entry
	return {}


## True when a point is inside any sanctuary. This is the question the enemies and the
## guards ask, and it is deliberately one question rather than "is it the camp" — every
## place a person lives is a place a raider may not walk into.
func contains(point: Vector3) -> bool:
	var entry: Dictionary = site_at(point)
	if entry.is_empty():
		return false
	if String(entry["kind"]) == "camp":
		var zone: Node = zone_node()
		if zone != null and zone.has_method("contains"):
			return bool(zone.call("contains", point))
	return true


func inside_id() -> String:
	return _inside


func inside() -> Dictionary:
	return site(_inside)


## Where a beaten body wakes: the nearest sanctuary's own wake point. Asked with the
## position the body fell at, because the walk back is the only thing a death costs and a
## walk of two hundred metres is a cost paid in boredom.
func wake_point_for(point: Vector3) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_distance: float = INF
	for entry: Dictionary in _sites.values():
		var centre: Vector3 = entry["centre"]
		var d: float = Vector2(point.x - centre.x, point.z - centre.z).length()
		if d < best_distance:
			best_distance = d
			best = entry["wake"]
	if best_distance < INF:
		return best
	return _fallback_wake()


func nearest(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for entry: Dictionary in _sites.values():
		var centre: Vector3 = entry["centre"]
		var d: float = Vector2(point.x - centre.x, point.z - centre.z).length()
		if d < best_distance:
			best_distance = d
			best = entry
	return best


## The node that owns the home camp's spherical boundary, if the world has been built.
func zone_node() -> Node:
	return get_tree().get_first_node_in_group("safe_zone")


func _fallback_wake() -> Vector3:
	var terrain: Node = get_tree().root.get_node_or_null("Main/Terrain")
	if terrain != null and terrain.has_method("spawn_point"):
		return terrain.call("spawn_point", 1.5)
	return Vector3(0.0, 1.5, 0.0)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var now: Dictionary = site_at(_player.global_position)
	var id: String = String(now.get("id", ""))
	if id == _inside:
		return
	var was: Dictionary = site(_inside)
	_inside = id
	if not was.is_empty():
		var leaving: String = String(was.get("exit", ""))
		if leaving != "":
			PlayerData.log_message.emit(leaving, "damage" if now.is_empty() else "info")
		left.emit(String(was["id"]), was)
	if now.is_empty():
		return
	# What a village says when you walk in. One line, named, and only on the way in: this is
	# the fourth thing the player learns about the world and the cheapest one to write.
	var line: String = String(now.get("enter", ""))
	if line != "":
		PlayerData.log_message.emit(line, "info")
	entered.emit(id, now)


func summary() -> Dictionary:
	var names: Array = []
	for entry: Dictionary in _sites.values():
		names.append("%s(%.0f m)" % [entry["name"], float(entry["radius"])])
	return {"sites": _sites.size(), "names": names}
