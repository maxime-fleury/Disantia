extends Node
## Who finds the body, and what they do with it.
##
## Losing used to be the same event everywhere: the cultivator collapsed, woke at the nearest
## sanctuary, and nothing had happened. That is deliberately gentle — there is no death screen
## and no debuff — but it also means the map has no *stakes*, because every fight on it ends in
## the same silence no matter where it was fought. Walking away from a beating was free, so the
## only thing making a fight tense was the fight.
##
## This is the fix, and it is a rule rather than a timer: **the body is found by whoever is
## nearest**, and there are three of those plus nobody.
##
##   * **A watchman finds you while you are wanted** → the cell. Everything is kept, the fine
##     stands, and the door is a decision (pay, or force it and be remembered) rather than a
##     wait. Being caught is the *interesting* failure, which is the opposite of what a timer
##     would have made it.
##   * **You fell within sight of a raider camp** → the purse. Half of it. They are the only
##     thing on the map that takes rather than punishes, and this is the one moment they get to
##     behave like what they are.
##   * **A villager finds you on a road near a village** → the healer. Nothing is lost and a
##     wound closes, which makes the villages *worth* being near when you are weak: the safest
##     ground in the game is also the only place a beating ever repaid anything.
##   * **Nobody** → the old event, whole and on the road, and the walk back is the cost.
##
## Nothing here is a multiplier on the player and nothing here reads HP: the decision is a
## *position*, so what a death costs is a question about where the fight happened. That is what
## makes it legible — a player learns in one night that the ring around a camp is expensive.

## How close a camp has to be for its raiders to be the ones who find you. A little wider than
## the camp's own footprint, because a body that crawled away from the fire is still within a
## minute's walk of it.
const CAMP_REACH := 58.0
## How far outside a village's walls a villager would still be the one to come across you.
const VILLAGE_REACH := 34.0
## The share of the purse a raider takes. Half, not all: the walk back from the far side of the
## valley is already the real price, and a wipe on top of it would make one bad fight end a
## session's worth of shopping.
const ROBBED_SHARE := 0.5


## What would happen to a body that falls at `position`, without touching anything. Pure, so the
## rule can be checked against every place on the map rather than by dying in each of them.
func outcome_at(position: Vector3) -> Dictionary:
	var village_id: String = Law.jailed_in()
	if village_id != "":
		# Already behind a door: there is no fourth party to be found by.
		return {"kind": "cell", "village": village_id, "detail": "the same cell"}
	var wanted: Array = _wanted_villages(position)
	if not wanted.is_empty():
		return {"kind": "cell", "village": String(wanted[0]),
			"detail": "a watchman recognises your face"}
	var camp: Dictionary = _nearest_camp(position)
	if not camp.is_empty():
		return {"kind": "robbed", "camp": String(camp.get("name", "")),
			"detail": "a raider goes through your purse"}
	var village: Dictionary = _nearest_village(position)
	if not village.is_empty():
		return {"kind": "healer", "village": String(village["id"]),
			"detail": "a villager drags you to the healer"}
	return {"kind": "road", "detail": "nobody"}


## The event itself: decided, applied, and *said*. The prose lives here rather than at the call
## site because which of the four happened is the whole content, and a caller that had to write
## its own sentence about it would eventually write a different one.
func found(position: Vector3) -> Dictionary:
	var outcome: Dictionary = outcome_at(position)
	counts[String(outcome["kind"])] = int(counts.get(String(outcome["kind"]), 0)) + 1
	last = outcome
	match String(outcome["kind"]):
		"cell":
			_wake_in_a_cell(outcome)
		"robbed":
			_wake_robbed(outcome)
		"healer":
			_wake_healed(outcome)
		_:
			_wake_whole(position)
	return outcome


# ------------------------------------------------------------------------ the four

## Somebody carried you in. The watch house is the one place on this list where a loss is worth
## having: everything is kept, and what happens next is the player's decision.
func _wake_in_a_cell(outcome: Dictionary) -> void:
	var village_id: String = String(outcome["village"])
	if not Law.imprison(village_id):
		Law.arrest(_player_position(), village_id)
	PlayerData.log_message.emit(
		"%s. They put you behind the door rather than in the road."
		% String(outcome["detail"]).capitalize(), "damage"
	)


func _wake_robbed(outcome: Dictionary) -> void:
	var taken: int = PlayerData.take_crystals(int(floor(float(PlayerData.crystals) * ROBBED_SHARE)))
	warp_home(_player_position())
	PlayerData.log_message.emit(
		"%s — %s. %d crystals lighter, and your gear is where you left it."
		% [String(outcome["detail"]).capitalize(), String(outcome.get("camp", "a camp")), taken],
		"damage"
	)
	Audio.play("error", -4.0, 0.8)


## The one outcome worth walking into. A wound closes, which is the only thing in the game that
## gives a wound back for free — and it is why the roads between the villages are the safest
## ground in the valley rather than merely the busiest.
func _wake_healed(outcome: Dictionary) -> void:
	var closed: bool = PlayerData.clear_wound()
	warp_home(_player_position())
	var name: String = String(Villages.def(String(outcome["village"])).get("name", "a village"))
	PlayerData.log_message.emit(
		"%s — %s. %s" % [
			String(outcome["detail"]).capitalize(), name,
			"One of your wounds is closed." if closed else "You are patched up and sent on your way.",
		],
		"gain"
	)
	Audio.play("confirm", -4.0, 1.1)


func _wake_whole(position: Vector3) -> void:
	warp_home(position)
	var entry: Dictionary = Haven.nearest(position)
	var where: String = "the camp"
	if not entry.is_empty() and String(entry["kind"]) == "village":
		where = String(entry["name"])
	PlayerData.log_message.emit("You wake in %s, whole." % where, "info")


## Where a beaten body comes to. The nearest sanctuary, not the only one: the walk out there was
## the cost and it was paid, so charging for it twice is not a rule a game can afford.
func warp_home(from: Vector3) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("warp_to"):
		return
	player.call("warp_to", Haven.wake_point_for(from))


# ---------------------------------------------------------------------- the reading

## The villages that would arrest this body, nearest first. Wanted is per village, so being an
## outlaw in one does not hand you to the watch of another.
func _wanted_villages(position: Vector3) -> Array:
	var out: Array = []
	for entry: Dictionary in Villages.all():
		var village_id: String = String(entry["id"])
		if Law.wanted_at(village_id) <= 0:
			continue
		var site: Dictionary = Haven.site(village_id)
		if site.is_empty():
			continue
		# The village's own ground plus the territory its watch patrols — the same reach the law
		# already uses to decide what a crime is, read here rather than re-invented.
		var centre: Vector3 = site["centre"]
		var reach: float = maxf(float(site["radius"]), Law.TERRITORY) + VILLAGE_REACH
		if Vector2(position.x - centre.x, position.z - centre.z).length() > reach:
			continue
		# Any rung at all. A watchman does not walk past a body lying in his street with a wanted
		# man's face on it and leave him there; the *sentence* is what scales with the ladder,
		# and that is the fine and the guards, not whether you are picked up.
		out.append(village_id)
	return out


func _nearest_camp(position: Vector3) -> Dictionary:
	var camps: Node = get_parent().get_node_or_null("Main/EnemyCamps")
	if camps == null or not camps.has_method("camps"):
		return {}
	var best: Dictionary = {}
	var best_distance: float = CAMP_REACH
	for camp: Dictionary in camps.call("camps"):
		var at: Vector3 = camp["position"]
		var distance: float = Vector2(position.x - at.x, position.z - at.z).length()
		if distance < best_distance:
			best_distance = distance
			best = camp
	return best


func _nearest_village(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for entry: Dictionary in Villages.all():
		var village_id: String = String(entry["id"])
		var site: Dictionary = Haven.site(village_id)
		if site.is_empty():
			continue
		var centre: Vector3 = site["centre"]
		var distance: float = Vector2(position.x - centre.x, position.z - centre.z).length()
		if distance > float(site["radius"]) + VILLAGE_REACH:
			continue
		if distance < best_distance:
			best_distance = distance
			best = {"id": village_id, "name": String(entry["name"]), "distance": distance}
	return best


func _player_position() -> Vector3:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	return Vector3.ZERO if player == null else player.global_position


var counts: Dictionary = {}
var last: Dictionary = {}


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_module("fate")
	var kept: Variant = saved.get("counts", {})
	if typeof(kept) == TYPE_DICTIONARY:
		counts = kept


func save_data() -> Dictionary:
	return {"counts": counts}


func reset() -> void:
	counts = {}
	last = {}


func summary() -> String:
	if counts.is_empty():
		return "nothing has found you yet"
	var parts: Array = []
	for kind: String in counts:
		parts.append("%s x%d" % [kind, int(counts[kind])])
	return ", ".join(parts)
