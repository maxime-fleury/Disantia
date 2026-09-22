extends Node
## The tower: a hundred floors, ten bands, and a record of how far down the stair you got.
##
## **Why it is composed rather than written.** A hundred hand-built floors is a hundred rooms
## that look like the same room, and the author stops caring around the twentieth — which the
## player can feel. So a floor is *generated from its depth*, seeded, and the same floor is the
## same fight on every run: the composition is a function, and a function can be tuned at the
## hundredth floor as easily as at the first. The variety comes from the ten **bands** — a name,
## a colour, an enemy mix and a rule that changes — and from a twist on some floors, so that
## floor 47 is a *place in a journey* rather than the fifth repetition of a shape.
##
## **Why there is no healing in it.** This is the decision the whole thing rests on. The tower
## could have been a hundred fights with a rest between each; that is a ladder, and a ladder's
## only question is how long you are willing to keep pressing the button. Instead nothing
## inside gives anything back — no trance, no passive mending, no recall — so the only health
## you have on floor 60 is the health you carried up, and **depth is a resource**. That is what
## turns "how far can I get" into a question with an answer you choose: you leave with what you
## have, or you gamble the next floor on the day you are having. The pills you bought at
## Towerfall's square are the run's ammunition, and that is the whole reason a village at the
## foot of the tower exists.
##
## Every tenth floor is a named warden with its own health bar, and it is the wall a band is
## built around: the floors below it teach the band's trick and the boss asks whether you
## learned it. The last one is the point of the story.

signal entered(depth: int)
signal left_tower(deepest: int, reason: String)
signal floor_cleared(depth: int, reward: Dictionary)
signal record_broken(depth: int)

## The item id the tower's own material, so the forge and the bounties and this file all name
## the same thing.
const SPLINTER := "tower_splinter"

## Ten bands of ten. `rule` is the band's twist, applied by the world when it builds the stage;
## `count` adds bodies and `hp` multiplies the blows a floor's raider survives, which is the
## shape of the difficulty curve: more of them, then tougher ones, then both.
const BANDS: Array = [
	{
		"name": "The Lower Stair", "colour": Color("8d97a3"), "rule": "",
		"count": 0, "hp": 1.0, "damage": 1.0,
		"boss": "The Keeper of the Landing",
		"boss_line": "It has swept this landing for a hundred years and it will not be told to stop.",
	},
	{
		"name": "The Ash Landing", "colour": Color("e2734a"), "rule": "dark",
		"count": 1, "hp": 1.15, "damage": 1.1,
		"boss": "The Ash Warden",
		"boss_line": "It wears what the first ward left of its own champion.",
	},
	{
		"name": "The Iron Galleries", "colour": Color("9fb4c8"), "rule": "swift",
		"count": 1, "hp": 1.3, "damage": 1.2,
		"boss": "The Iron Steward",
		"boss_line": "Iron on every wall, and it has been counting the pieces.",
	},
	{
		"name": "The Choking Dark", "colour": Color("6a6f9a"), "rule": "dark",
		"count": 2, "hp": 1.5, "damage": 1.3,
		"boss": "The Blind Cantor",
		"boss_line": "It has not needed eyes for a long time.",
	},
	{
		"name": "The Long Ascent", "colour": Color("b9c8a0"), "rule": "reinforce",
		"count": 2, "hp": 1.7, "damage": 1.4,
		"boss": "The Tireless",
		"boss_line": "You have climbed further than it expected. It intends to fix that.",
	},
	{
		"name": "The Broken Sky", "colour": Color("8fd0ff"), "rule": "bolts",
		"count": 2, "hp": 2.0, "damage": 1.5,
		"boss": "The Sky-Eater",
		"boss_line": "The windows up here look out on nothing at all.",
	},
	{
		"name": "The Twelve Halls", "colour": Color("c9a6ff"), "rule": "swift",
		"count": 3, "hp": 2.3, "damage": 1.6,
		"boss": "The Twelfth Warden",
		"boss_line": "There were twelve of you once, it says. There is one of you now.",
	},
	{
		"name": "The Quiet Floors", "colour": Color("9a94a8"), "rule": "dark",
		"count": 3, "hp": 2.7, "damage": 1.8,
		"boss": "The Quiet One",
		"boss_line": "The floors it keeps are silent. It would like to keep yours.",
	},
	{
		"name": "The Ninth Landing", "colour": Color("ffd76e"), "rule": "bolts",
		"count": 4, "hp": 3.2, "damage": 2.0,
		"boss": "The Ninth's Shadow",
		"boss_line": "The Ninth left something behind on the way down. It has been waiting.",
	},
	{
		"name": "The Seat", "colour": Color("ffffff"), "rule": "bolts",
		"count": 4, "hp": 4.0, "damage": 2.4,
		"boss": "The Unnamed",
		"boss_line": "The wards were built around this floor, and this floor has been awake the whole time.",
	},
]

const FLOORS := 100
const FLOOR_HEIGHT := 4.6
## The depth a run has reached. Nothing resets it: a record is the whole reward structure of a
## thing you are supposed to fail at.
var deepest: int = 0
## Where the body is standing: 0 means the ground outside.
var current: int = 0
## Floors whose first-clear reward has already been paid. Firsts only — the hundredth clear of
## floor 12 paying a cap would make the tower a farm instead of a climb.
var cleared: Dictionary = {}
var runs: int = 0
var deaths_inside: int = 0

## What the door answers to. Two wards is two chapters of the game, which is roughly where a
## body can survive the first band; the gate is a *read* of the world rather than a key, so it
## opens the moment the player has done the thing rather than when they find the item.
const REQUIRED_WARDS := 2
const REQUIRED_REALM := 2


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_module("tower")
	deepest = clampi(int(saved.get("deepest", 0)), 0, FLOORS)
	cleared = saved.get("cleared", {})
	runs = int(saved.get("runs", 0))
	deaths_inside = int(saved.get("deaths_inside", 0))


func save_data() -> Dictionary:
	# `current` is deliberately not saved: a session that ends inside the tower ends at its
	# door, because a body restored into floor 71 with no run behind it is a body with the
	# record and none of the work.
	return {"deepest": deepest, "cleared": cleared, "runs": runs, "deaths_inside": deaths_inside}


func reset() -> void:
	deepest = 0
	current = 0
	cleared.clear()
	runs = 0
	deaths_inside = 0


# -------------------------------------------------------------------- the door

func unlocked() -> bool:
	return Wards.passed() >= REQUIRED_WARDS or Cultivation.realm_index() >= REQUIRED_REALM


func locked_reason() -> String:
	if unlocked():
		return ""
	return "The door answers %s, or two wards crossed. You are %s." % [
		Wards.realm_label_of(REQUIRED_WARDS - 1) if REQUIRED_WARDS <= Wards.gate_count() else "a higher realm",
		Cultivation.realm_label(),
	]


func inside() -> bool:
	return current > 0


# ------------------------------------------------------------- composition

func band_of(depth: int) -> Dictionary:
	return BANDS[clampi((depth - 1) / 10, 0, BANDS.size() - 1)]


func band_index(depth: int) -> int:
	return clampi((depth - 1) / 10, 0, BANDS.size() - 1)


func is_boss_floor(depth: int) -> bool:
	return depth > 0 and depth % 10 == 0


## The whole floor, as data. Deterministic: same depth, same fight, every run — which is what
## makes a record a thing a player can *learn* rather than a lottery they survived.
##
## Health is expressed in **blows of the player's own fist**, exactly like a champion and for
## exactly the same reason: a floor whose health is a fixed number stops being a fight the
## moment ATTACK outgrows it, so the tower would get easier the further the player climbed it.
## The belt of a run is then about the flasks rather than about the numbers, and the fight at
## floor 80 is a fight at any level of the save.
func plan(depth: int) -> Dictionary:
	var d: int = clampi(depth, 1, FLOORS)
	var band: Dictionary = band_of(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + d
	var boss: bool = is_boss_floor(d)
	var band_step: int = d - (band_index(d) * 10)
	var twists: Array = []
	# One twist on a floor that is not a boss, two on the ones nearest the top of a band. The
	# twist is what the player reads when the door opens — it is announced, not discovered.
	if not boss and band_step % 3 == 0:
		twists.append("rich")
	if not boss and band_step % 4 == 0:
		twists.append("crowded")
	if boss:
		twists.append("boss")
	var count: int = 1 + int(band["count"]) + (1 if twists.has("crowded") else 0)
	# Health, in swings of the player's own fist. The band's multiplier is folded in here rather
	# than applied twice: a floor that both multiplied its health *and* multiplied the swings a
	# band wanted was quadratic, and the fortieth floor of a quadratic curve is not a fight, it
	# is a wall with a number on it. A regular floor stays a handful of swings at any depth and a
	# boss is the only thing that takes a minute — which is what makes a boss floor read as one.
	var blows: float = ((13.0 + 1.4 * float(band_index(d))) if boss else (3.0 + 0.05 * float(d))) \
		* float(band["hp"])
	var crystals: int = 4 + int(float(d) * 0.8)
	if twists.has("rich"):
		crystals *= 2
	return {
		"depth": d,
		"band": band_index(d),
		"band_name": String(band["name"]),
		"colour": band["colour"],
		"rule": String(band["rule"]),
		"boss": boss,
		"boss_name": String(band["boss"]) if boss else "",
		"boss_line": String(band["boss_line"]) if boss else "",
		"line": _floor_line(d, rng, boss),
		"count": 1 if boss else count,
		"retinue": count if boss else 0,
		"blows": blows,
		"damage": (9.0 + 1.5 * float(d)) * float(band["damage"]),
		"crystals": crystals,
		"twists": twists,
		"bolts": String(band["rule"]) == "bolts" or (boss and d >= 90),
	}


## One line at the door, so a floor is a place rather than a number. Seeded off the depth, so
## floor 43 says the same thing the second time you stand in front of it.
const FLOOR_LINES: Array = [
	"The stair turns, and the air changes.",
	"Somebody scratched a count into the wall here. The last number is not finished.",
	"A landing with no window, and a draught coming from somewhere.",
	"Old blood on the floor, and a broom left standing in it.",
	"The steps are worn deepest in the middle, from feet that were not hurrying.",
	"A door in the wall that opens onto more wall.",
	"Something has been stacked here, neatly, for a long time.",
	"The light comes from the stone itself on this floor.",
	"Names, cut into the wall in a hand that gets worse as it goes down.",
	"Quiet, in the way a room is quiet after an argument.",
]


func _floor_line(depth: int, rng: RandomNumberGenerator, boss: bool) -> String:
	if boss:
		# A boss floor's line is its own, because the thing on it is the floor.
		return String(BANDS[band_index(depth)]["boss_line"])
	return String(FLOOR_LINES[rng.randi_range(0, FLOOR_LINES.size() - 1)])


## What a floor pays the *first* time it is cleared. Every tenth floor pays a permanent cap on
## top of the crystals, which is the thing that makes a long climb worth the flasks: the tower
## is not a place to farm, it is a place that *changes what the body is capable of*.
func first_clear_reward(depth: int) -> Dictionary:
	var d: int = clampi(depth, 1, FLOORS)
	if bool(cleared.get(d, false)):
		return {}
	var band: Dictionary = band_of(d)
	var reward: Dictionary = {
		"crystals": (12 + d * 2) if is_boss_floor(d) else (4 + d / 3),
		"materials": {},
	}
	if is_boss_floor(d):
		reward["materials"][SPLINTER] = 2 + band_index(d)
		reward["cap"] = {
			"hp": 40.0 * (1.0 + float(band_index(d)) * 0.5),
			"qi": 20.0 * (1.0 + float(band_index(d)) * 0.5),
		}
	else:
		reward["materials"][SPLINTER] = 1
	return reward


# -------------------------------------------------------------------- the run

## The floor the next run starts at: one past everything cleared. A tower whose record is a
## fast-travel point is a tower you can *return to* — nobody wants to re-fight the thirty
## floors they already know to find out whether they can beat the thirty-first, and a game that
## makes them has confused content with patience.
func frontier() -> int:
	return clampi(deepest + 1, 1, FLOORS)


## Walks in. `at_frontier` steps off at the deepest floor cleared so far plus one; otherwise
## the run starts at the stairhead, which is what a player who wants the whole climb again
## picks. Cleared floors are empty on the way up, so even the ground floor is a walk.
func enter(at_frontier: bool = false) -> bool:
	if not unlocked():
		Audio.play("error", -6.0)
		return false
	runs += 1
	current = frontier() if at_frontier else 1
	PlayerData.mark_dirty()
	PlayerData.log_message.emit(
		"The door lets you in at floor %d — %s." % [current, String(band_of(current)["name"])],
		"info"
	)
	Audio.play("ui_open", -2.0)
	entered.emit(current)
	return true


func ascend() -> bool:
	if current <= 0 or current >= FLOORS:
		return false
	current += 1
	PlayerData.mark_dirty()
	entered.emit(current)
	return true


func descend() -> bool:
	if current <= 1:
		return false
	current -= 1
	entered.emit(current)
	return true


func leave(reason: String = "walked out") -> void:
	if current == 0:
		return
	current = 0
	PlayerData.mark_dirty()
	left_tower.emit(deepest, reason)


## The floor's enemies are all down. Pays the first-clear reward, once, and opens the gate.
func clear_floor(depth: int) -> Dictionary:
	var reward: Dictionary = first_clear_reward(depth)
	var paid: Array = []
	# The record is the deepest floor *cleared*, not the deepest one stood on: a record you can
	# set by walking into a room is not a record.
	if depth > deepest:
		deepest = depth
		if depth % 10 == 0:
			PlayerData.log_message.emit(
				"Floor %d. %s — the deepest anybody has taken this stair." % [
					depth, String(band_of(depth)["name"]),
				],
				"breakthrough"
			)
		record_broken.emit(depth)
	if not reward.is_empty():
		cleared[depth] = true
		if reward.has("crystals"):
			PlayerData.add_crystals(int(reward["crystals"]))
			paid.append("+%d crystals" % int(reward["crystals"]))
		var forge: Node = get_node_or_null("/root/Forge")
		if forge != null and reward.has("materials"):
			for material: String in (reward["materials"] as Dictionary):
				forge.call("add_material", material, int((reward["materials"] as Dictionary)[material]), false)
				paid.append("%s ×%d" % [
					String(forge.call("material_name", material)),
					int((reward["materials"] as Dictionary)[material]),
				])
		if reward.has("cap"):
			for stat_id: String in (reward["cap"] as Dictionary):
				var granted: float = PlayerData.grant_cap(stat_id, float((reward["cap"] as Dictionary)[stat_id]))
				if granted > 0.0:
					paid.append("%s cap +%s" % [PlayerData.label(stat_id), String.num(granted, 1)])
		PlayerData.mark_dirty()
	PlayerData.log_message.emit(
		"Floor %d of %d cleared.%s" % [
			depth, FLOORS, "" if paid.is_empty() else "  " + ", ".join(paid),
		],
		"gain"
	)
	Audio.play("confirm", -1.0)
	floor_cleared.emit(depth, reward)
	return reward


## Beaten inside. The record stands — a run you died on still got you there — and the body is
## put back on the ground, which is what the door's step is for.
func died_inside() -> void:
	if current == 0:
		return
	deaths_inside += 1
	var where: int = current
	current = 0
	PlayerData.mark_dirty()
	PlayerData.add_wound()
	PlayerData.log_message.emit(
		"The tower puts you out. Floor %d stands at %d.%s" % [
			where, deepest,
			"" if deepest < FLOORS else " Nothing in the valley has been further.",
		],
		"damage"
	)
	left_tower.emit(deepest, "carried out")


## What the HUD prints while inside, and the reason the floor number is worth printing at all.
func readout() -> Dictionary:
	if current <= 0:
		return {"inside": false, "deepest": deepest, "floors": FLOORS}
	var plan_here: Dictionary = plan(current)
	return {
		"inside": true,
		"depth": current,
		"floors": FLOORS,
		"band": String(plan_here["band_name"]),
		"colour": plan_here["colour"],
		"boss": bool(plan_here["boss"]),
		"deepest": deepest,
		"line": String(plan_here["line"]),
		"twists": plan_here["twists"],
	}


func summary() -> String:
	return "deepest %d/%d, %d runs, %d cleared, %d deaths inside" % [
		deepest, FLOORS, runs, cleared.size(), deaths_inside,
	]
