extends Node
## The night the valley comes for somebody.
##
## Every system in this project until now has waited for the player. The camps smoke on the
## horizon whether or not anybody is looking, but nothing *happens*: no door is ever knocked on,
## no village is ever worse off for a night that passed, and a player who sits on a rock for an
## hour of real time loses nothing. That is the difference between a world and a diorama, and it
## is the whole reason this file exists.
##
## A raid is four events and one decision.
##
##   * **The warning, at nightfall.** Runners are seen on the road and one village is *named*, at
##     a stated hour. This is the part that matters: a raid the player cannot see coming is a tax,
##     and a raid they can is an appointment. Nothing else in the game tells them where to be.
##   * **The squad, an hour and a half later.** Bodies out of the treeline on the far side, at the
##     strength the valley has grown into — every ten floors of the tower and every dozen days add
##     another raider, and the band they belong to sets what one of them hits for.
##   * **The fight, which the player may join or miss.** These are the ordinary raiders the camps
##     spawn, with one difference: `brawl` is on, so they fight whoever is in front of them
##     instead of running past the watch at the player. The watch is two bodies a village, they
##     get up again, and a squad that is still standing at dawn is a squad that got in.
##   * **The cost, which is not a timer.** A village whose gate went down is *shut* — the stalls
##     are burned, the board is empty — and it stays shut until somebody pays to mend it. The
##     price rises with each time it has happened. That is the answer to "what do I do with my
##     power": the thing you can do that nobody else in the valley can is be *there*.
##
## What this deliberately is not: a schedule the player can farm. A raid only ever lands at
## night, only one runs at a time, and the nights between them are the point — the warning is
## worth something only if it is rare.

signal raid_called(village_id: String, size: int, at_hour: float)
signal raid_landed(village_id: String, size: int)
signal raid_ended(village_id: String, outcome: String, detail: String)

const EnemyFactory := preload("res://scripts/enemy/enemy_factory.gd")

## Nightfall, when the warning arrives. The dark is the run-up, which is why it is stated as an
## hour rather than "soon".
const CALL_HOUR := 19.5
## And an hour and a half of it before anybody is at the gate. Enough for a body on the far road
## to get there if they move, and not enough to finish a fight first.
const LAND_HOUR := 21.0
## A raid never lands on the player's first day: the first night of a save is for finding the
## camp, the well and the keys.
const FIRST_DAY := 2
## And never two nights running. One raid in three is a night worth preparing for; one raid a
## night is weather.
const NIGHT_GAP := 3
const SIZE_BASE := 3
const SIZE_MAX := 8
const HP_BASE := 105.0
const DAMAGE_BASE := 10.0
const CRYSTALS_BASE := 8
## How far out along the road the squad comes out of the trees, and where the body it walks at
## stands.
##
## The second number is the one that matters and it is deliberately *outside* the fence. A raid
## anchored inside the palisade would be a squad standing in the one place a raider may not walk —
## the sanctuary rule would switch its pursuit off and the gate would be attacked by nobody. Two
## metres out is the road outside the gate, which is exactly where the watch's own beat passes.
const STANDOFF := 9.0
const ANCHOR := 2.2
## What one raider felled in a village's defence is worth to that village, and what a gate that
## went down costs the one that failed to hold it. Both are small next to the price of the gate:
## losing the fight is supposed to be the expensive half.
const FELLED_REP := 3
const SACK_REP := -14
const REPAIR_BASE := 90
const REPAIR_STEP := 55

## village id -> how many times its gate has been broken. Saved, because a valley that forgot
## would mend itself every time the player quit.
var sacked: Dictionary = {}
## The last night a raid was called, so the gap survives a save. Clock day, not a wall clock.
var last_day: int = 0
var held: int = 0
var lost: int = 0
var calls: int = 0

## The night in progress, or empty. **Runtime only, and never saved**: the squad is a set of
## nodes in a world that is rebuilt from the seed on every launch, so a raid restored from a save
## would be a raid with no raiders in it — a village sacked by a fight that happened in a session
## the player has already closed.
var tonight: Dictionary = {}
var _root: Node3D


func _ready() -> void:
	set_process(true)
	var saved: Dictionary = PlayerData.take_loaded_module("raids")
	sacked = (saved.get("sacked", {}) as Dictionary).duplicate()
	last_day = int(saved.get("last_day", 0))
	held = int(saved.get("held", 0))
	lost = int(saved.get("lost", 0))
	calls = int(saved.get("calls", 0))
	Clock.phase_changed.connect(_on_phase)


func save_data() -> Dictionary:
	return {
		"sacked": sacked.duplicate(),
		"last_day": last_day,
		"held": held,
		"lost": lost,
		"calls": calls,
	}


func reset() -> void:
	sacked.clear()
	last_day = 0
	held = 0
	lost = 0
	calls = 0
	tonight.clear()


# ------------------------------------------------------------------ the calling

func _on_phase(phase: String) -> void:
	if phase == "night":
		maybe_call()


## Decides whether tonight is a raid night, and calls one if it is. Public and free of the input
## layer so the suite drives exactly what the clock drives.
##
## The village is picked by rotation rather than by anything about the player. A raid is supposed
## to be the one thing in the valley that is *not* about them — it is what the raiders were doing
## before anybody arrived, and a schedule that bent towards the player's reputation would make
## the warning a consequence instead of news.
func maybe_call() -> bool:
	if not tonight.is_empty():
		return false
	if Clock.day < FIRST_DAY or Clock.day < last_day + NIGHT_GAP:
		return false
	var order: Array = Villages.all()
	if order.is_empty():
		return false
	var pick: Dictionary = order[int(Clock.day) % order.size()]
	return call_raid(String(pick["id"]), strength(), LAND_HOUR)


## Marks a village, states the hour, and tells the player. The announcement is the feature: the
## rest of this file is what happens to a player who did not come.
func call_raid(village_id: String, size: int, at_hour: float) -> bool:
	if village_id == "" or not tonight.is_empty():
		return false
	if Villages.def(village_id).is_empty():
		return false
	last_day = Clock.day
	tonight = {
		"village": village_id,
		"size": maxi(1, size),
		"at_hour": at_hour,
		"landed": false,
		"squad": [],
	}
	calls += 1
	PlayerData.mark_dirty()
	var name_of: String = String(Villages.def(village_id)["name"])
	PlayerData.log_message.emit(
		"Runners on the road at dusk. %s is marked tonight — %d raiders, at the gate by %02d:00."
		% [name_of, int(tonight["size"]), int(at_hour)],
		"damage"
	)
	Audio.play("error", -3.0)
	raid_called.emit(village_id, int(tonight["size"]), at_hour)
	return true


## How many bodies come, off the player's own progress: the tower is the valley's depth gauge, so
## every ten floors is one more raider, and the days themselves season the camps a little.
func strength() -> int:
	var from_tower: int = int(Tower.deepest / 10)
	var from_days: int = int(Clock.day / 12)
	return clampi(SIZE_BASE + from_tower + from_days, SIZE_BASE, SIZE_MAX)


## What one raider of the current band hits for, takes, and pays. Hung off the *tower band* the
## player has reached rather than off the day number, so a raid escalates with what the valley has
## already been shown a body can do — and a player who never climbs is not ground down by a clock
## they are not looking at. The multipliers are the tower's own, read here rather than copied, so
## the third band's raiders are the third band's raiders wherever they are met.
func bite() -> Dictionary:
	var depth: int = maxi(1, Tower.deepest)
	var band: Dictionary = Tower.band_of(depth)
	return {
		"hp": HP_BASE * float(band["hp"]),
		"damage": DAMAGE_BASE * float(band["damage"]),
		"crystals": CRYSTALS_BASE + Tower.band_index(depth),
		"colour": band["colour"],
	}


# ---------------------------------------------------------------- the landing

func _process(_delta: float) -> void:
	if tonight.is_empty():
		return
	if not bool(tonight["landed"]):
		if Clock.hour_float() >= float(tonight["at_hour"]):
			land()
		return
	# Broken as soon as the last of them is down, which is what makes helping *feel* like
	# something: the raid ends on the blow that finishes it rather than at a fixed hour. And a
	# squad still standing when the sun comes up got what it came for.
	if standing() == 0:
		_close("held")
	elif not Clock.is_night():
		_close("sacked")


## Puts the squad in the world, outside the far side of the village. Public so a test can land a
## raid at a stated hour without waiting on the clock.
func land() -> bool:
	if tonight.is_empty() or bool(tonight["landed"]):
		return false
	var village_id: String = String(tonight["village"])
	var site_node: Node3D = _site_of(village_id)
	if site_node == null or not site_node.has_method("gate_point"):
		return false
	var size: int = int(tonight["size"])
	var stats: Dictionary = bite()
	var scale: float = 1.0 + 0.05 * float(size)
	_root = _spawn_root()
	if _root == null:
		return false
	# Up the road at the gate, and at it. The squad spawns out in the dark and walks the last
	# seven metres at the *gate*, which is what makes this a raid rather than a patrol: the watch
	# is at that gate, and the leash is anchored two metres outside it all night.
	var anchor: Vector3 = site_node.call("gate_point", ANCHOR)
	var gate: Vector3 = site_node.call("gate_point", STANDOFF)
	var along := Vector2(gate.x - anchor.x, gate.z - anchor.z).normalized()
	var aside := Vector2(-along.y, along.x)
	var squad: Array = []
	for i in size:
		var spread: float = (float(i) - float(size - 1) * 0.5) * 1.6
		var spot := Vector3(
			gate.x + aside.x * spread,
			0.0,
			gate.z + aside.y * spread
		)
		spot.y = _ground_height(spot.x, spot.z)
		var enemy: CharacterBody3D = EnemyFactory.make(scale, "Raider")
		EnemyFactory.configure(
			enemy, float(stats["hp"]), float(stats["damage"]), int(stats["crystals"]),
			anchor, stats["colour"], 24.0, 64.0, 0.0
		)
		# The two properties that make this a raid rather than a camp. `brawl` sends it at the
		# watch instead of past it; `INF` means a body that goes down stays down, which is what
		# "the squad is broken" is measured in.
		enemy.set("brawl", true)
		enemy.set("respawn_seconds", INF)
		_root.add_child(enemy)
		enemy.global_position = spot
		enemy.died.connect(_on_felled)
		squad.append(enemy)
	tonight["landed"] = true
	tonight["squad"] = squad
	var name_of: String = String(Villages.def(village_id)["name"])
	PlayerData.log_message.emit(
		"%d raiders are at %s's gate, and the watch is standing in front of it."
		% [size, name_of], "damage"
	)
	Audio.play("error", -1.0)
	raid_landed.emit(village_id, size)
	return true


## The village that built the gate the squad is walking at. Found by the group the site puts
## itself in, because the gate's *direction* is the site's own business — the registry knows the
## disc and nothing about which side of it the road came in from.
func _site_of(village_id: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("village_site"):
		var site := node as Node3D
		if site != null and String(site.get("village_id")) == village_id:
			return site
	return null


## Where the squad is parented. The world is `Main`, and a raid is nobody's child in particular,
## so a root of its own keeps it out of the camps' and the tower's books.
func _spawn_root() -> Node3D:
	var scene: Node = get_tree().current_scene
	if scene is Node3D:
		return scene as Node3D
	return null


func _ground_height(x: float, z: float) -> float:
	var terrain: Node = get_tree().root.get_node_or_null("Main/Terrain")
	if terrain != null and terrain.has_method("surface_height_at"):
		return float(terrain.call("surface_height_at", x, z))
	return 0.0


## One of the squad is down. The body pays for itself (the enemy script does that), and the
## village notices — unless the village is currently hunting the body that just helped it, which
## is a state the law can absolutely reach and is worth saying out loud rather than silently
## rewarding.
##
## Guarded on membership rather than trusting the connection: a squad the raids have already
## let go of is a squad whose deaths are none of this file's business.
func _on_felled(felled: Node3D) -> void:
	if tonight.is_empty():
		return
	if not (tonight.get("squad", []) as Array).has(felled):
		return
	var village_id: String = String(tonight["village"])
	if Law.wanted_at(village_id) >= 2:
		PlayerData.log_message.emit(
			"The watch sees you put one down, and remembers what you are.", "damage"
		)
		return
	Villages.adjust_rep(village_id, FELLED_REP, "stood with the watch")
	Villages.report("kill", 1.0, village_id)
	PlayerData.log_message.emit(
		"%s's watch sees it. They will remember your face for the right reason."
		% String(Villages.def(village_id)["name"]), "gain"
	)


# ------------------------------------------------------------------ the outcome

## How many of the squad are still on their feet.
func standing() -> int:
	var count: int = 0
	for node: Node in (tonight.get("squad", []) as Array):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and bool(enemy.call("is_dead")):
			continue
		count += 1
	return count


func _close(outcome: String) -> void:
	if tonight.is_empty():
		return
	var village_id: String = String(tonight["village"])
	var name_of: String = String(Villages.def(village_id)["name"])
	var detail: String = ""
	if outcome == "held":
		held += 1
		Villages.adjust_rep(village_id, 4, "the gate held the night")
		detail = "%s held. The watch walks its beat in the morning." % name_of
		PlayerData.log_message.emit(detail, "gain")
		Audio.play("confirm", -2.0)
	else:
		lost += 1
		sack(village_id)
		detail = "%s's gate is down, and the stalls with it." % name_of
	_free_squad()
	tonight.clear()
	last_day = Clock.day
	PlayerData.mark_dirty()
	raid_ended.emit(village_id, outcome, detail)


## The gate comes down. Its own function because there are two ways to reach this — losing the
## night, and a future where something else breaks a village — and the price of it is the one
## thing every caller has to agree about.
func sack(village_id: String) -> void:
	if village_id == "":
		return
	sacked[village_id] = int(sacked.get(village_id, 0)) + 1
	Villages.adjust_rep(village_id, SACK_REP, "the gate went down")
	PlayerData.log_message.emit(
		"%s is open. They went through the fence and out the far side — the market is burned, and "
		% String(Villages.def(village_id).get("name", village_id))
		+ "it stays shut until somebody mends the gate. %d crystals." % repair_cost(village_id),
		"damage"
	)
	PlayerData.mark_dirty()


func _free_squad() -> void:
	for node: Node in (tonight.get("squad", []) as Array):
		var enemy := node as Node3D
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_free()


## Cancel whatever is in progress — used by the suite between sections, and by a progress reset.
func clear() -> void:
	_free_squad()
	tonight.clear()


# ------------------------------------------------------------------- the repair

func is_sacked(village_id: String) -> bool:
	return int(sacked.get(village_id, 0)) > 0


func sacked_count(village_id: String) -> int:
	return int(sacked.get(village_id, 0))


## What mending it costs. Rising with each time the place has been broken, so the third raid on
## the same village is a real bill and not pocket change.
func repair_cost(village_id: String) -> int:
	return REPAIR_BASE + REPAIR_STEP * sacked_count(village_id)


func can_repair(village_id: String) -> bool:
	return is_sacked(village_id) and PlayerData.crystals >= repair_cost(village_id)


## Pays for the gate. Returns whether it was mended, so the caller can say why not.
func repair(village_id: String) -> bool:
	if not is_sacked(village_id):
		return false
	if not PlayerData.spend_crystals(repair_cost(village_id)):
		return false
	# The first raid on it is forgotten by the ledger; the count is *how many times it has
	# happened*, and a gate that has been mended is a gate that is standing.
	sacked.erase(village_id)
	Villages.adjust_rep(village_id, 6, "paid for the gate")
	var name_of: String = String(Villages.def(village_id).get("name", village_id))
	PlayerData.log_message.emit(
		"The gate at %s goes back up. Somebody says so, and nobody looks at you for long."
		% name_of, "info"
	)
	Audio.play("confirm", -1.0)
	PlayerData.mark_dirty()
	return true


# --------------------------------------------------------------------- reading

## One line for the HUD, or "" when the valley is quiet. Leads with whatever is imminent, because
## this is the one strip on screen a player reads while doing something else.
func warning() -> String:
	if tonight.is_empty():
		var broken: String = worst_sacked()
		if broken == "":
			return ""
		return "%s IS OPEN — %d crystals mends the gate" % [
			String(Villages.def(broken).get("name", broken)).to_upper(), repair_cost(broken)
		]
	var village_id: String = String(tonight["village"])
	var name_of: String = String(Villages.def(village_id).get("name", village_id)).to_upper()
	if bool(tonight["landed"]):
		return "RAID ON %s — %d still standing" % [name_of, standing()]
	return "%s IS MARKED TONIGHT — be at the gate by %02d:00" % [
		name_of, int(tonight["at_hour"])
	]


## The broken village worth naming on a one-line strip: the nearest one, because a gate in the
## ground on the far side of the valley is not a thing the player can act on.
func worst_sacked() -> String:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var best: String = ""
	var best_distance: float = INF
	for village_id: String in sacked:
		var site: Dictionary = Haven.site(village_id)
		if site.is_empty():
			continue
		if player == null:
			return village_id
		var centre: Vector2 = Vector2(site["centre"].x, site["centre"].z)
		var d: float = Vector2(player.global_position.x, player.global_position.z).distance_to(centre)
		if d < best_distance:
			best_distance = d
			best = village_id
	return best


func scheduled() -> bool:
	return not tonight.is_empty()


func summary() -> Dictionary:
	return {
		"tonight": tonight.duplicate(),
		"standing": standing(),
		"sacked": sacked.duplicate(),
		"held": held,
		"lost": lost,
		"calls": calls,
		"next_day": last_day + NIGHT_GAP,
	}
