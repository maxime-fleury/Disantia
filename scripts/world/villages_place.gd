extends Node3D
## Puts the villages in the world.
##
## Built from the table for the same reason the cast of people is: the number of villages
## standing on the map and the number of villages the story knows about cannot drift apart if
## there is only one list. A hand-placed node per village is how a project ends up with a
## delivery addressed to a town that was cut in the last pass.

const VillageSiteScript := preload("res://scripts/world/village_site.gd")

var _sites: Array = []


func _ready() -> void:
	var terrain: Node = get_parent().get_node_or_null("Terrain")
	for entry: Dictionary in Villages.all():
		var site: Node3D = VillageSiteScript.new()
		site.name = "Village_" + String(entry["id"])
		site.set("village_id", String(entry["id"]))
		site.set("terrain_node", terrain)
		add_child(site)
		_sites.append(site)
	var report: Array = []
	for site: Node in _sites:
		if site.has_method("summary"):
			var summary: Dictionary = site.call("summary")
			report.append("%s(%.0f m, %d people, %d guards)" % [
				String(summary["id"]),
				Vector2(site.call("centre").x, site.call("centre").z).length(),
				int(summary["people"]), int(summary["guards"]),
			])
	print("[villages] %d built: %s" % [_sites.size(), ", ".join(report)])


func sites() -> Array:
	return _sites.duplicate()


## The village whose disc contains a world position, or an empty dictionary. Read by the HUD,
## the raids and the cartographers.
func village_at(position: Vector3) -> Dictionary:
	for site: Node in _sites:
		var centre: Vector3 = site.call("centre")
		var radius: float = float(site.call("radius")) + 5.0
		if Vector2(position.x - centre.x, position.z - centre.z).length() <= radius:
			return Villages.def(String(site.get("village_id")))
	return {}


func nearest_village(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for site: Node in _sites:
		var centre: Vector3 = site.call("centre")
		var d: float = Vector2(position.x - centre.x, position.z - centre.z).length()
		if d < best_distance:
			best_distance = d
			best = Villages.def(String(site.get("village_id")))
	return best
