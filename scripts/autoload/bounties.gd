extends Node
## The board in every village: names, and what they are worth.
##
## The raider camps are the world's pressure and they are also its most *repeatable* content —
## ten camps, three rings, one fight that gets harder the further out you go. What they were
## missing was a reason to go to a particular one: a camp you have already cleared pays the
## same as a camp you have not, so the camps stop being places and become a bar that refills.
##
## A bounty is that reason. It takes an ordinary raider standing at a named camp and makes it a
## *person*: a name over its head, more health, more weight behind its swing, and a price that
## is paid at the village that posted it. Nothing about the fight is new — the mark is the same
## body with the same AI, and that is the point: the board gives the existing world a reason.
##
## Boards refresh with the clock, one name at a time. A bounty you have taken stays taken
## until it is settled, because a contract that expires while you are walking towards it would
## be a contract nobody takes twice.

signal changed
signal taken(slot: Dictionary)
signal mark_felled(slot: Dictionary)

const BOARD_SIZE := 3

## What a mark is called, and the camp it stands at does the rest: "Iron-Hand of Bandit Hollow"
## reads like somebody the road has met, which a generated id never would.
const NAMES: Array = [
	"Iron-Hand", "Nine-Finger", "The Butcher", "Salt-Eye", "Widowmaker",
	"The Quiet Brother", "Red Lian", "Hollow Chen", "The Leash", "Ox",
]

## village id -> array of slots. A slot is the whole contract: where, who, how much.
var boards: Dictionary = {}
## Bounty id -> the node spawned for it, so a settled contract can be found again.
var _marks: Dictionary = {}
var _next_id: int = 1
## The day the boards were last filled, so a new dawn can put a new name up without touching
## the ones already paid for.
var _filled_day: int = -1


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_module("bounties")
	boards = saved.get("boards", {})
	_filled_day = int(saved.get("filled_day", -1))
	_next_id = int(saved.get("next_id", 1))
	if Sky != null:
		Clock.day_passed.connect(func(_day: int) -> void: refresh(true))
	# The boards are filled on the first frame rather than here: the camps are built by the
	# scene, and a board that named a camp before the camp existed would post a bounty on
	# nowhere.
	call_deferred("refresh", false)


func save_data() -> Dictionary:
	return {"boards": boards, "filled_day": _filled_day, "next_id": _next_id}


func reset() -> void:
	boards.clear()
	_marks.clear()
	_filled_day = -1


# ------------------------------------------------------------------- the board

## Tops every village's board up to three contracts. `new_day` only lets the board *replace* a
## name nobody has taken: the contracts in progress are the player's business and not the
## clock's.
func refresh(new_day: bool = false) -> void:
	var camps: Array = _camps()
	if camps.is_empty():
		return
	if new_day:
		for village_id: String in boards.keys():
			var kept: Array = []
			for slot: Dictionary in boards[village_id]:
				if bool(slot.get("taken", false)):
					kept.append(slot)
			boards[village_id] = kept
	for entry: Dictionary in Villages.all():
		var village_id: String = String(entry["id"])
		var slots: Array = boards.get(village_id, [])
		var index: int = 0
		while _open_count(slots) < BOARD_SIZE and index < 24:
			index += 1
			slots.append(_generate(village_id, int(entry["reach"] * 1000.0), index, camps))
		boards[village_id] = slots
	_filled_day = Clock.day
	PlayerData.mark_dirty()
	changed.emit()


func _open_count(slots: Array) -> int:
	var open: int = 0
	for slot: Dictionary in slots:
		if not bool(slot.get("claimed", false)):
			open += 1
	return open


## One contract: a camp, a name, and a price that scales with the ring the camp stands in —
## which is what keeps the board useful at every level instead of only at the start.
func _generate(village_id: String, salt: int, index: int, camps: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = village_id.hash() + salt + index * 7919 + Clock.day * 104729
	var camp: Dictionary = camps[rng.randi_range(0, camps.size() - 1)]
	var ring: int = clampi(int(camp.get("ring", 0)), 0, 3)
	var name: String = "%s of %s" % [
		String(NAMES[rng.randi_range(0, NAMES.size() - 1)]), String(camp["name"]),
	]
	return {
		"id": "bounty_%d" % _next_id,
		"village": village_id,
		"name": name,
		"camp": String(camp["name"]),
		"ring": ring,
		"hp_blows": 5.0 + 2.0 * float(ring),
		"damage": 11.0 + 6.0 * float(ring),
		"scale": 1.14 + 0.07 * float(ring),
		"crystals": 26 + 24 * ring,
		"rep": 2,
		"material": _material_for(ring),
		"taken": bool(false),
		"felled": bool(false),
		"claimed": bool(false),
	}


func _material_for(ring: int) -> String:
	var forge: Node = get_node_or_null("/root/Forge")
	if forge != null and forge.has_method("material_for_ring"):
		return String(forge.call("material_for_ring", ring))
	return "hide_scrap"


func next_id() -> String:
	_next_id += 1
	PlayerData.mark_dirty()
	return "bounty_%d" % (_next_id - 1)


func slots(village_id: String) -> Array:
	return (boards.get(village_id, []) as Array).duplicate(true)


func slot(id: String) -> Dictionary:
	for village_id: String in boards:
		for entry: Dictionary in boards[village_id]:
			if String(entry["id"]) == id:
				return entry
	return {}


# ----------------------------------------------------------------- taking one

## Takes a contract and puts the mark in the world: the ordinary raider at that camp is
## replaced by a named one, stronger, standing where its friends stand. Until it is taken the
## board is a rumour; this is the moment it becomes a body.
func take(id: String) -> bool:
	var entry: Dictionary = slot(id)
	if entry.is_empty() or bool(entry["taken"]) or bool(entry["felled"]):
		Audio.play("error", -8.0)
		return false
	var camp: Dictionary = _camp_named(String(entry["camp"]))
	if camp.is_empty():
		Audio.play("error", -8.0)
		return false
	var mark: Node3D = _spawn_mark(entry, camp)
	if mark == null:
		return false
	entry["taken"] = true
	_marks[id] = mark
	PlayerData.mark_dirty()
	PlayerData.log_message.emit(
		"%s is at %s, in the ring past the %s ward. %d crystals when it is down." % [
			String(entry["name"]), String(entry["camp"]),
			["first", "second", "third", "outer"][clampi(int(entry["ring"]), 0, 3)],
			int(entry["crystals"]),
		],
		"info"
	)
	Audio.play("confirm", -3.0)
	taken.emit(entry)
	changed.emit()
	return true


## A named body at the camp, spawned as the camp's own child so it walks home to the fire like
## everything else stationed there.
func _spawn_mark(entry: Dictionary, camp: Dictionary) -> Node3D:
	var root: Node3D = camp.get("node")
	if root == null or not is_instance_valid(root):
		return null
	var centre: Vector3 = camp.get("position", Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = String(entry["id"]).hash()
	var angle: float = rng.randf_range(0.0, TAU)
	var offset := Vector2(cos(angle), sin(angle)) * rng.randf_range(2.0, 3.6)
	var terrain: Node = get_tree().root.get_node_or_null("Main/Terrain")
	var ground: float = centre.y
	var spot := Vector3(centre.x + offset.x, centre.y, centre.z + offset.y)
	if terrain != null and terrain.has_method("surface_height_at"):
		ground = float(terrain.call("surface_height_at", spot.x, spot.z))
	var local: Vector3 = Vector3(spot.x - centre.x, ground - centre.y, spot.z - centre.z)
	var factory: GDScript = load("res://scripts/enemy/enemy_factory.gd")
	var enemy: CharacterBody3D = factory.make(float(entry["scale"]), String(entry["name"]))
	var hp: float = maxf(60.0, PlayerData.strike_damage() * float(entry["hp_blows"]))
	factory.configure(enemy, hp, float(entry["damage"]), 8, centre + local, Color("ff9a5c"), 22.0, 34.0)
	enemy.set("display_name", String(entry["name"]))
	enemy.set("bounty_id", String(entry["id"]))
	enemy.set("respawn_seconds", INF)
	enemy.position = local
	root.add_child(enemy)
	return enemy


## Called by the enemy itself when it goes down. Paying is a separate act: the board is at the
## village and the fight is out in the ring, and the walk back is what makes the board a place.
func felled(bounty_id: String) -> void:
	var entry: Dictionary = slot(bounty_id)
	if entry.is_empty() or bool(entry["felled"]):
		return
	entry["felled"] = true
	_marks.erase(bounty_id)
	PlayerData.mark_dirty()
	PlayerData.log_message.emit(
		"%s is down. The board in %s owes you %d crystals." % [
			String(entry["name"]), String(Villages.def(String(entry["village"])).get("name", "")),
			int(entry["crystals"]),
		],
		"breakthrough"
	)
	Audio.play("breakthrough", -3.0)
	mark_felled.emit(entry)
	changed.emit()


## Settles a felled contract at the clerk. Returns what was paid.
func claim(id: String) -> Array:
	var entry: Dictionary = slot(id)
	if entry.is_empty() or not bool(entry["felled"]) or bool(entry["claimed"]):
		return []
	entry["claimed"] = true
	var paid: Array = []
	PlayerData.add_crystals(int(entry["crystals"]))
	paid.append("+%d crystals" % int(entry["crystals"]))
	Villages.adjust_rep(String(entry["village"]), int(entry["rep"]), "a mark brought in")
	paid.append("+%d standing" % int(entry["rep"]))
	var forge: Node = get_node_or_null("/root/Forge")
	if forge != null and String(entry.get("material", "")) != "":
		forge.call("add_material", String(entry["material"]), 2, false)
		paid.append("%s ×2" % String(forge.call("material_name", String(entry["material"]))))
	PlayerData.mark_dirty()
	PlayerData.log_message.emit(
		"%s settled: %s" % [String(entry["name"]), ", ".join(paid)], "gain"
	)
	Audio.play("coin", -1.0)
	changed.emit()
	return paid


# -------------------------------------------------------------------- querying

func _camps() -> Array:
	var node: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	if node == null or not node.has_method("camps"):
		return []
	var out: Array = []
	for camp: Dictionary in node.call("camps"):
		# A champion's camp is a chapter, not a job: the board never posts a bounty on a boss.
		if String(camp.get("warden", "")) != "":
			continue
		out.append(camp)
	return out


func _camp_named(name: String) -> Dictionary:
	for camp: Dictionary in _camps():
		if String(camp["name"]) == name:
			return camp
	return {}


## The nearest taken contract to a position, for the wayfinder: one name at a time, because a
## map with three markers on it is a checklist.
func nearest_taken(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for id: String in _marks:
		var mark: Node3D = _marks[id]
		if mark == null or not is_instance_valid(mark):
			continue
		var entry: Dictionary = slot(id)
		if entry.is_empty() or bool(entry["felled"]):
			continue
		var d: float = Vector2(
			mark.global_position.x - position.x, mark.global_position.z - position.z
		).length()
		if d < best_distance:
			best_distance = d
			entry["distance"] = d
			entry["position"] = mark.global_position
			best = entry
	return best


## Settled and unclaimed contracts for a village, which is what the clerk's board shows first.
func claimable(village_id: String) -> Array:
	var out: Array = []
	for entry: Dictionary in boards.get(village_id, []):
		if bool(entry.get("felled", false)) and not bool(entry.get("claimed", false)):
			out.append(entry)
	return out


func summary() -> Dictionary:
	var out: Array = []
	for village_id: String in boards:
		var open: int = 0
		for entry: Dictionary in boards[village_id]:
			if not bool(entry["claimed"]):
				open += 1
		out.append("%s=%d" % [village_id, open])
	return {"village": out, "marks_in_world": _marks.size(), "day": _filled_day}
