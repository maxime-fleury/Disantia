extends Node
## The three villages, their people, and the thing each of them wants.
##
## The world had one place in it. The camp had a fire, an elder who counted things and a
## shelf, and everything else you could walk to was either a raider camp or a light on a pole.
## A valley with one settlement in it is a level; a valley with three is a *country*, and the
## difference is not the number of doors — it is that the third one has heard of the first.
##
## So this file holds the three of them as data, and the thing that makes them a place rather
## than three copies of one shop is that each is *for* something:
##
##   Hollowmere  the road's start. Hide, a healer, and the first thing anybody asks of you.
##   Stonewatch  the forge. The only smith in the valley, and the only place a piece of gear
##               can be made better.
##   Towerfall   the tower's foot. The best shelf, the scholar, and the last wall's gossip.
##
## **The chains are the linearity.** Each village's keeper has three steps, and the last step
## of each hands a physical parcel to the next village's keeper — so the story is a road with
## three stops and a reason to walk it, rather than a valley with three shops in it. The
## parcel is a real thing in the belt, and the hand-off is a real walk: the ward that stands
## between two villages wants a realm, so the delivery is gated by the same progression the
## whole game is, instead of by a dialogue flag.
##
## Everything here is *data plus counters*: the world builds itself from the tables, the HUD
## reads the counters, and neither knows what a quest is.

signal changed
## A step's progress moved, or a chain advanced. One signal, because a panel that has to
## remember which of six things to listen to stops updating the day a seventh arrives.
signal chain_advanced(village_id: String, step: Dictionary)
signal reputation_changed(village_id: String, total: int, reason: String)

## The villages, in the order the road reaches them. `road` is the index into the terrain's
## own road network, which is what puts every village *on* a road rather than near one: the
## caravans, the guards' patrols and the signposts all read the same roads, and a village
## that was placed off one would have been unreachable by everything except the player.
##
## `radius` is the whole footprint — the palisade, the ring of houses and the square inside it
## all scale off this one number — and `huts` is how many roofs stand in it, so the three read
## as a hamlet, a town and a city rather than as the same village three times at three sizes.
## A bigger radius is not free: the ground has to be level across it, and the builder searches
## for a spot that is, so a number this large is a claim about the terrain as much as about
## the village.
##
## `reach` is a fraction of the map's half-extent like every other placement rule in the
## project, so the world stays one table that scales with the terrain.
const VILLAGES: Array = [
	{
		"id": "hollowmere", "name": "Hollowmere", "subtitle": "the road's start",
		"road": 1, "reach": 0.20, "offset": 9.5, "radius": 26.0,
		"colour": Color("7fb069"), "huts": 6,
		"specialty": "healer",
		"flavour": "Hollowmere — a well, four roofs, and a palisade somebody mended twice.",
		"welcome": "You came down the road, so you are somebody's news. Sit. Nothing here is in a hurry.",
		"wares": ["jade_wraps", "traveller_hide", "spring_charm"],
		"potions": ["mending_pill", "qi_pill"],
	},
	{
		"id": "stonewatch", "name": "Stonewatch", "subtitle": "the forge",
		"road": 4, "reach": 0.47, "offset": 10.5, "radius": 38.0,
		"colour": Color("d9824a"), "huts": 10,
		"specialty": "smith",
		"flavour": "Stonewatch — hammer, smoke, and a palisade of new-cut timber.",
		"welcome": "Mind the sparks. Everything here is either being made or being repaired.",
		"wares": ["ash_blade", "iron_shell", "vein_talisman"],
		"potions": ["qi_pill", "spirit_ward"],
	},
	{
		"id": "towerfall", "name": "Towerfall", "subtitle": "the tower's foot",
		"road": 7, "reach": 0.685, "offset": 11.0, "radius": 52.0,
		"colour": Color("8f8fe0"), "huts": 15,
		"specialty": "scholar",
		"flavour": "Towerfall — the spire's shadow lies over the whole square, and nobody looks up.",
		"welcome": "You have seen it. Everybody who arrives has seen it. The question is why you came anyway.",
		"wares": ["wind_edge", "storm_robe", "peak_seal"],
		"potions": ["mending_pill", "qi_pill", "blood_elixir"],
	},
]

## The people of a village, as offsets from its square. Five or six to a village, which is
## what a *place* needs and not a crowd: a keeper with the village's business, a merchant with
## its share of the valley's shelves, a clerk with the board, whichever specialist the place is
## for, and one or two people who simply live here.
##
## `role` is the whole behaviour. `folk` have no panel and no chain — they have a line that
## changes with your name and your reputation, and that is the cheapest way in the game to make
## a settlement read as inhabited rather than as a row of vending machines.
const PEOPLE: Array = [
	# ------------------------------------------------------------------ Hollowmere
	{
		"id": "hollowmere_keeper", "village": "hollowmere", "role": "keeper",
		"name": "Elder Mei", "at": Vector2(3.4, -3.0), "colour": Color("4f7a52"),
	},
	{
		"id": "hollowmere_merchant", "village": "hollowmere", "role": "merchant",
		"name": "Tao the Pedlar", "at": Vector2(-4.2, 1.4), "colour": Color("7a5a3c"),
	},
	{
		"id": "hollowmere_healer", "village": "hollowmere", "role": "healer",
		"name": "Grandmother Nuo", "at": Vector2(1.2, 4.2), "colour": Color("6f8f9a"),
	},
	{
		"id": "hollowmere_clerk", "village": "hollowmere", "role": "clerk",
		"name": "Watchman Gu", "at": Vector2(-1.8, -4.6), "colour": Color("59606e"),
	},
	{
		"id": "hollowmere_folk", "village": "hollowmere", "role": "folk",
		"name": "Little Shen", "at": Vector2(-5.6, -2.2), "colour": Color("a8794f"),
	},
	# ----------------------------------------------------------------- Stonewatch
	{
		"id": "stonewatch_keeper", "village": "stonewatch", "role": "keeper",
		"name": "Warden Bai", "at": Vector2(4.0, -3.4), "colour": Color("7a4630"),
	},
	{
		"id": "stonewatch_merchant", "village": "stonewatch", "role": "merchant",
		"name": "Sister Lan", "at": Vector2(-4.6, 2.0), "colour": Color("8f5a76"),
	},
	{
		"id": "stonewatch_smith", "village": "stonewatch", "role": "smith",
		"name": "Forgemaster Du", "at": Vector2(-1.4, 5.0), "colour": Color("8a4a2a"),
	},
	{
		"id": "stonewatch_clerk", "village": "stonewatch", "role": "clerk",
		"name": "Sergeant Ou", "at": Vector2(-2.4, -4.8), "colour": Color("4d5566"),
	},
	{
		"id": "stonewatch_folk", "village": "stonewatch", "role": "folk",
		"name": "Apprentice Fen", "at": Vector2(6.0, 0.6), "colour": Color("9c7048"),
	},
	# ----------------------------------------------------------------- Towerfall
	{
		"id": "towerfall_keeper", "village": "towerfall", "role": "keeper",
		"name": "Scholar Yun", "at": Vector2(3.8, -3.8), "colour": Color("5a5f9a"),
	},
	{
		"id": "towerfall_merchant", "village": "towerfall", "role": "merchant",
		"name": "Iron Auntie", "at": Vector2(-5.0, 1.6), "colour": Color("8a6a4a"),
	},
	{
		"id": "towerfall_clerk", "village": "towerfall", "role": "clerk",
		"name": "Captain Zhu", "at": Vector2(-2.0, -5.0), "colour": Color("3f4a5e"),
	},
	{
		"id": "towerfall_healer", "village": "towerfall", "role": "healer",
		"name": "Physician Rao", "at": Vector2(1.6, 4.6), "colour": Color("5f8f86"),
	},
	{
		"id": "towerfall_folk", "village": "towerfall", "role": "folk",
		"name": "Old Wen", "at": Vector2(-0.6, 6.2), "colour": Color("7f7a6a"),
	},
]

## What each keeper's chain asks, in order. `kind` is the event and `target` the amount; the
## same vocabulary `Quests.report` already speaks, plus the three this file adds — `deliver`,
## `materials` and `floor`, which are reported by the delivery, the forge and the tower.
##
## `parcel` is the physical thing the step puts in your hands. It is the whole reason the
## villages are a road: the last step of one village is *carrying something to the next*, and
## the thing is in the belt until it gets there.
const CHAINS: Dictionary = {
	"hollowmere": [
		{
			"id": "hm_listen", "title": "What the valley is",
			"detail": "Stand still and let Elder Mei tell you what you have walked into.",
			"kind": "talk", "target": 1.0,
			"reward": {"crystals": 12, "rep": 1},
		},
		{
			"id": "hm_circle", "title": "The Standing Circle",
			"detail": "There is a place up the road nobody tends and everybody knows. Find it.",
			"kind": "discover", "target": 1.0,
			"reward": {"crystals": 20, "rep": 1, "cap": {"qi": 25.0}},
		},
		{
			"id": "hm_letter", "title": "A sealed letter",
			"detail": "Carry Mei's letter to Warden Bai in Stonewatch, past the ward.",
			"kind": "deliver", "target": 1.0, "to": "stonewatch",
			"parcel": {"id": "mei_letter", "name": "Mei's sealed letter"},
			"reward": {"crystals": 30, "rep": 2},
		},
	],
	"stonewatch": [
		{
			"id": "sw_scales", "title": "Scales for the forge",
			"detail": "Du will work for four Hide Scrap. The near raiders carry them.",
			"kind": "materials", "target": 4.0, "material": "hide_scrap",
			"reward": {"crystals": 25, "rep": 2},
		},
		{
			"id": "sw_harden", "title": "Something worth wearing",
			"detail": "Have anything forged to *good* — one upgrade at the anvil.",
			"kind": "forge_tier", "target": 2.0,
			"reward": {"crystals": 35, "rep": 2, "cap": {"attack": 6.0}},
		},
		{
			"id": "sw_blade", "title": "The blade goes south",
			"detail": "Du has finished a commission for Towerfall. Carry it there.",
			"kind": "deliver", "target": 1.0, "to": "towerfall",
			"parcel": {"id": "du_commission", "name": "Du's commission, wrapped in oilcloth"},
			"reward": {"crystals": 60, "rep": 3},
		},
	],
	"towerfall": [
		{
			"id": "tf_what", "title": "Why the tower is here",
			"detail": "Scholar Yun has been reading the same three pages for nine years.",
			"kind": "talk", "target": 1.0,
			"reward": {"crystals": 40, "rep": 2},
		},
		{
			"id": "tf_ten", "title": "Ten floors",
			"detail": "Come back from the tenth floor of the tower alive.",
			"kind": "floor", "target": 10.0,
			"reward": {"crystals": 90, "rep": 3, "cap": {"hp": 120.0}},
		},
		{
			"id": "tf_ground", "title": "The Ninth's ground",
			"detail": "The last champion is standing on the last spirit zone. Take it from it.",
			"kind": "warden", "target": 1.0, "warden": "the_ninth",
			"reward": {"crystals": 220, "rep": 4, "cap": {"attack": 30.0}},
		},
		{
			"id": "tf_top", "title": "The top of the stair",
			"detail": "Nothing in the valley has ever reached the hundredth floor.",
			"kind": "floor", "target": 100.0,
			"reward": {"crystals": 600, "rep": 6, "cap": {"qi": 400.0, "hp": 600.0}},
		},
	],
}

## What the folk say, by how well the village knows you. One line each rather than a
## conversation: a street with four people on it who each have a dialogue tree is a street
## nobody walks down twice.
const FOLK_LINES: Array = [
	"They look at you the way people look at weather coming in.",
	"You are somebody's rumour now, you know.",
	"Somebody said your name in the square and nobody asked who.",
	"They have stopped asking what you want and started asking what you need.",
]

## Reputation steps. A number would be a stat; a word is something the player can hold.
## What being wanted costs on top of everything else, per rung of the ladder. A village will
## still sell to a body the watch is watching — that is what makes the rung a *price* instead of
## a door — and the top rung shuts the shutters instead, which is where `Law.shops_closed`
## takes over.
##
## Applied inside `price_factor` rather than at the shelf, so it is a fact about every price in
## the game at once: the wares, the pills and the anvil all multiply by this number, and none of
## them had to be changed to learn about the law.
const LAW_SURCHARGE: Array = [1.0, 1.15, 1.35, 1.6]
const REP_STEPS: Array = [0, 4, 10, 18]
const REP_LABELS: Array = ["a stranger", "known", "trusted", "kin"]

## Progress per step, keyed "<village>:<step id>", and the step each village is on.
var progress: Dictionary = {}
var steps_done: Dictionary = {}
## Villages whose chain has been started by talking to the keeper.
var started: Dictionary = {}
var reputation: Dictionary = {}
## Parcels in hand: parcel id -> name. Physical things, and the belt is not a quest log.
var parcels: Dictionary = {}
## The step a parcel was given for, so a hand-off cannot be claimed by walking back.
var _parcel_step: Dictionary = {}
## Steps claimed, for the HUD and the log.
var _history: Array = []

## Where the world actually put them, as flat discs — plus the tower, which is a place people
## keep their distance from for the same reason a village is.
##
## Runtime only, never saved: the terrain is procedural and rebuilt from a seed every launch, so
## a stored position would be a position in a world that no longer exists. What needs it are the
## *other* placers — the scatter, the camps and the spirit zones all ask before they drop
## something on ground that somebody lives on.
var sites: Dictionary = {}


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_module("villages")
	progress = saved.get("progress", {})
	steps_done = saved.get("steps_done", {})
	started = saved.get("started", {})
	reputation = saved.get("reputation", {})
	parcels = saved.get("parcels", {})
	_parcel_step = saved.get("parcel_step", {})
	_history = saved.get("history", [])


func save_data() -> Dictionary:
	return {
		"progress": progress, "steps_done": steps_done, "started": started,
		"reputation": reputation, "parcels": parcels, "parcel_step": _parcel_step,
		"history": _history,
	}


func reset() -> void:
	progress.clear()
	steps_done.clear()
	started.clear()
	reputation.clear()
	parcels.clear()
	_parcel_step.clear()
	_history.clear()
	changed.emit()


# ---------------------------------------------------------------- the catalogue

func def(village_id: String) -> Dictionary:
	for entry: Dictionary in VILLAGES:
		if String(entry["id"]) == village_id:
			return entry
	return {}


func all() -> Array:
	return VILLAGES.duplicate(true)


func person(id: String) -> Dictionary:
	for entry: Dictionary in PEOPLE:
		if String(entry["id"]) == id:
			return entry
	return {}


func people_of(village_id: String) -> Array:
	var out: Array = []
	for entry: Dictionary in PEOPLE:
		if String(entry["village"]) == village_id:
			out.append(entry)
	return out


func display_name(id: String) -> String:
	var entry: Dictionary = person(id)
	return String(entry.get("name", "Somebody"))


func register_site(id: String, site_name: String, centre: Vector2, radius: float) -> void:
	sites[id] = {"id": id, "name": site_name, "centre": centre, "radius": radius}


## True when a point is inside a place people live, plus a margin. Every other placer in the
## world asks this: a stand of pines through a village square, a raider camp against the gate or
## a spirit zone under somebody's bed are all the same bug — the ground was claimed twice.
func near_site(x: float, z: float, margin: float = 0.0) -> bool:
	for entry: Dictionary in sites.values():
		var centre: Vector2 = entry["centre"]
		if Vector2(x - centre.x, z - centre.y).length() <= float(entry["radius"]) + margin:
			return true
	return false


func site_names() -> Array:
	var out: Array = []
	for entry: Dictionary in sites.values():
		out.append(String(entry["name"]))
	return out


## The village a position is nearest to, by the square it belongs to. Used by the guards, the
## crimes and the caravans: "which village does this belong to" is asked in six places and
## answered in one.
func nearest_to(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for entry: Dictionary in VILLAGES:
		var site: Dictionary = Haven.site(String(entry["id"]))
		if site.is_empty():
			continue
		var centre: Vector3 = site["centre"]
		var d: float = Vector2(position.x - centre.x, position.z - centre.z).length()
		if d < best_distance:
			best_distance = d
			best = entry
	return best


# ---------------------------------------------------------------------- reputation

func rep_of(village_id: String) -> int:
	return int(reputation.get(village_id, 0))


func rep_label(village_id: String) -> String:
	var total: int = rep_of(village_id)
	var step: int = 0
	for i in REP_STEPS.size():
		if total >= int(REP_STEPS[i]):
			step = i
	return String(REP_LABELS[step])


## What this village's shelves charge, as a factor. Trust is a discount and it is the plainest
## reason in the game to do anything for anybody: four ranks take a fifth off the top.
func price_factor(village_id: String) -> float:
	var total: int = rep_of(village_id)
	var step: int = 0
	for i in REP_STEPS.size():
		if total >= int(REP_STEPS[i]):
			step = i
	var wanted: int = 0
	if Law != null:
		wanted = Law.wanted_at(village_id)
	return (1.0 - 0.055 * float(step)) * float(LAW_SURCHARGE[clampi(wanted, 0, LAW_SURCHARGE.size() - 1)])


func adjust_rep(village_id: String, amount: int, reason: String) -> void:
	if village_id == "" or amount == 0:
		return
	var before: int = rep_of(village_id)
	reputation[village_id] = maxi(0, before + amount)
	PlayerData.mark_dirty()
	reputation_changed.emit(village_id, rep_of(village_id), reason)
	if amount > 0 and rep_label(village_id) != rep_label_from(before):
		PlayerData.log_message.emit(
			"%s counts you %s now." % [String(def(village_id).get("name", village_id)), rep_label(village_id)],
			"gain"
		)
	changed.emit()


func rep_label_from(total: int) -> String:
	var step: int = 0
	for i in REP_STEPS.size():
		if total >= int(REP_STEPS[i]):
			step = i
	return String(REP_LABELS[step])


# ------------------------------------------------------------------ the chains

func chain(village_id: String) -> Array:
	return (CHAINS.get(village_id, []) as Array).duplicate(true)


func step_index(village_id: String) -> int:
	return int(steps_done.get(village_id, 0))


func started_chain(village_id: String) -> bool:
	return bool(started.get(village_id, false))


## The step this village is on, or an empty dictionary when the chain is finished.
func current_step(village_id: String) -> Dictionary:
	var steps: Array = CHAINS.get(village_id, [])
	var index: int = step_index(village_id)
	if index < 0 or index >= steps.size():
		return {}
	return (steps[index] as Dictionary).duplicate(true)


func step_progress(village_id: String) -> float:
	var step: Dictionary = current_step(village_id)
	if step.is_empty():
		return 0.0
	var target: float = maxf(0.001, float(step["target"]))
	return clampf(float(progress.get(_key(village_id, String(step["id"])), 0.0)) / target, 0.0, 1.0)


func step_ready(village_id: String) -> bool:
	var step: Dictionary = current_step(village_id)
	return not step.is_empty() and step_progress(village_id) >= 1.0


func _key(village_id: String, step_id: String) -> String:
	return "%s:%s" % [village_id, step_id]


## Counts an event against the step that wants it. Called by everything that already knows a
## fact, the same way `Quests.report` is — the alternative is this file polling the world,
## which would be a per-frame read of six systems to find one number that moves once a minute.
func report(kind: String, amount: float, extra: String = "") -> void:
	if amount <= 0.0:
		return
	for village: Dictionary in VILLAGES:
		var village_id: String = String(village["id"])
		var step: Dictionary = current_step(village_id)
		if step.is_empty() or not bool(started.get(village_id, false)):
			continue
		if String(step["kind"]) != kind:
			continue
		# A step can want a *particular* material, a particular warden or a particular
		# village, and one that did not would count the wrong event for the wrong place.
		if step.has("material") and String(step["material"]) != extra:
			continue
		if step.has("warden") and String(step["warden"]) != extra:
			continue
		if kind == "deliver" and String(step.get("to", "")) != extra:
			continue
		var key: String = _key(village_id, String(step["id"]))
		var target: float = float(step["target"])
		var now: float = minf(target, float(progress.get(key, 0.0)) + amount)
		progress[key] = now
		changed.emit()
		if now >= target:
			PlayerData.log_message.emit(
				"%s: \\\"%s\\\" is done. Come and tell me." % [String(village["name"]), String(step["title"])],
				"info"
			)


## Hands in the finished step and opens the next one. Returns what was paid, so a caller can
## print it and cannot report a reward the world did not give.
func claim(village_id: String) -> Dictionary:
	var step: Dictionary = current_step(village_id)
	if step.is_empty() or not step_ready(village_id):
		return {}
	var paid: Array = []
	var reward: Dictionary = step.get("reward", {})
	if reward.has("crystals"):
		PlayerData.add_crystals(int(reward["crystals"]))
		paid.append("+%d crystals" % int(reward["crystals"]))
	if reward.has("cap"):
		for stat_id: String in (reward["cap"] as Dictionary):
			var granted: float = PlayerData.grant_cap(stat_id, float((reward["cap"] as Dictionary)[stat_id]))
			if granted > 0.0:
				paid.append("%s +%s" % [PlayerData.label(stat_id), String.num(granted, 1)])
	if reward.has("rep"):
		adjust_rep(village_id, int(reward["rep"]), "a step finished")
		paid.append("+%d standing" % int(reward["rep"]))
	# The parcel goes into the belt here rather than at the end of the chain, because the
	# carrying is the content: a step whose job is "take this there" has to hand you the thing.
	if step.has("parcel"):
		var parcel: Dictionary = step["parcel"]
		parcels[String(parcel["id"])] = String(parcel["name"])
		_parcel_step[String(parcel["id"])] = String(step["id"])
		paid.append("carrying: %s" % String(parcel["name"]))
		PlayerData.log_message.emit(
			"You are carrying %s." % String(parcel["name"]), "info"
		)
	steps_done[village_id] = step_index(village_id) + 1
	_history.append({"village": village_id, "step": String(step["id"])})
	PlayerData.mark_dirty()
	PlayerData.log_message.emit(
		"%s: \\\"%s\\\" — %s" % [
			String(def(village_id).get("name", village_id)), String(step["title"]),
			", ".join(paid) if not paid.is_empty() else "noted",
		],
		"breakthrough"
	)
	Audio.play("confirm", -2.0)
	chain_advanced.emit(village_id, step)
	changed.emit()
	return {"step": step, "paid": paid}


## True while this village is the one a carried parcel is addressed to.
func expects_parcel(village_id: String) -> String:
	var step: Dictionary = current_step(village_id)
	if step.is_empty() or String(step["kind"]) != "deliver":
		return ""
	if String(step.get("to", "")) != village_id:
		return ""
	var parcel: Dictionary = step.get("parcel", {})
	return String(parcel.get("id", ""))


## Somebody in *another* village handing over what this one is waiting for. Returns the parcel
## name when the hand-off happened.
func deliver_at(village_id: String) -> String:
	var wanted: String = expects_parcel(village_id)
	if wanted == "":
		return ""
	if not parcels.has(wanted):
		return ""
	var name: String = String(parcels[wanted])
	parcels.erase(wanted)
	_parcel_step.erase(wanted)
	report("deliver", 1.0, village_id)
	PlayerData.log_message.emit("%s handed over." % name, "gain")
	Audio.play("book", -2.0)
	return name


func carrying() -> Array:
	var out: Array = []
	for id: String in parcels:
		out.append({"id": id, "name": String(parcels[id])})
	return out


# --------------------------------------------------------------------- the panels

## What the board in this village is offering, as the HUD draws it: the keeper's current step
## plus where this village stands.
func board(village_id: String) -> Dictionary:
	var village: Dictionary = def(village_id)
	var step: Dictionary = current_step(village_id)
	return {
		"village": village_id,
		"name": String(village.get("name", "")),
		"subtitle": String(village.get("subtitle", "")),
		"rep": rep_of(village_id),
		"rep_label": rep_label(village_id),
		"started": started_chain(village_id),
		"step": step,
		"progress": step_progress(village_id),
		"ready": step_ready(village_id),
		"carrying": carrying(),
	}


## Starts the chain when the keeper is first spoken to. Kept here rather than in the keeper's
## dialogue so that a chain cannot be half-started by a caller that forgot.
func open_chain(village_id: String) -> void:
	if started_chain(village_id):
		return
	started[village_id] = true
	PlayerData.mark_dirty()
	var step: Dictionary = current_step(village_id)
	PlayerData.log_message.emit(
		"%s has work for you." % String(def(village_id).get("name", village_id)), "info"
	)
	chain_advanced.emit(village_id, step)
	changed.emit()


## What the folk say. Reputation and name are the two things a passer-by can plausibly know,
## and they are the two the rest of the world already moves.
func folk_line(village_id: String) -> String:
	var total: int = rep_of(village_id)
	var index: int = 0
	for i in REP_STEPS.size():
		if total >= int(REP_STEPS[i]):
			index = i
	return String(FOLK_LINES[clampi(index, 0, FOLK_LINES.size() - 1)])


## The shelf this village sells, as the HUD wants it. Assembled from the Forge's catalogue
## rather than copied here, so a piece added to the valley appears on exactly one shelf and
## the two files cannot disagree about what is for sale where.
func shelf(village_id: String) -> Dictionary:
	var out: Dictionary = {"pieces": [], "consumables": []}
	# A village whose gate went down has no market. Emptied here, at the one door everything
	# buys through, rather than at each panel: the shelf is what the HUD draws, the forge
	# stocks and the price is quoted against, so closing it here closes all of them.
	if Raids.is_sacked(village_id):
		return out
	var forge: Node = get_node_or_null("/root/Forge")
	if forge == null or not forge.has_method("stock_here"):
		return out
	var stock: Dictionary = forge.call("stock_here", village_id)
	for piece: Dictionary in (stock["pieces"] as Array):
		var id: String = String(piece["id"])
		out["pieces"].append({
			"id": id, "name": String(piece["name"]),
			"slot": String(piece["slot"]), "blurb": String(piece["blurb"]),
			"tier": int(forge.call("tier_of", id)),
			"tier_name": String(forge.call("tier_name", id)),
			"price": int(forge.call("price_of", id)),
			"can_buy": bool(forge.call("can_buy", id)),
			"materials": forge.call("upgrade_materials", id),
			"material_name": String(forge.call("material_name", String(piece["material"]))),
			"have": int(forge.call("material_count", String(piece["material"]))),
		})
	for potion: Dictionary in (stock["consumables"] as Array):
		var pid: String = String(potion["id"])
		out["consumables"].append({
			"id": pid, "name": String(potion["name"]),
			"blurb": String(potion["blurb"]),
			"price": int(round(float(potion["price"]) * price_factor(village_id))),
			"carried": int(forge.call("carried", pid)),
		})
	return out


# --------------------------------------------------------------------- panels

## A panel as **data**. The HUD draws rows and hands back the id of the one that was pressed;
## this file decides what that means.
##
## One panel shape for four screens — a shelf, an anvil, a board of names and a village's own
## record — because four bespoke panels is four interfaces to keep in step with the systems
## behind them, and the systems are the part that changes. A row is a label, a detail line, a
## price on the right, and an id that means something to `invoke`.
func panel(kind: String, village_id: String) -> Dictionary:
	match kind:
		"shop":
			return _shop_panel(village_id)
		"forge":
			return _forge_panel(village_id)
		"bounties":
			return _bounty_panel(village_id)
		"board":
			return _board_panel(village_id)
	return {"title": kind, "subtitle": "", "rows": [], "kind": kind, "village": village_id}


## What pressing a row means. Returns a line for the log, or "" when the thing simply happened.
## Every action is checked here rather than in the HUD, so the panel cannot sell something the
## system behind it would have refused.
func invoke(kind: String, id: String, village_id: String) -> String:
	var forge: Node = get_node_or_null("/root/Forge")
	match kind:
		"shop":
			if forge == null:
				return ""
			if id.begins_with("wear:"):
				var wear: String = id.trim_prefix("wear:")
				forge.call("equip", wear)
				return "%s is on." % String(forge.call("def", wear).get("name", wear))
			if id.begins_with("piece:"):
				var piece: String = id.trim_prefix("piece:")
				if not bool(forge.call("can_buy", piece)):
					return "Not enough crystals for that one."
				var name: String = String(forge.call("def", piece).get("name", piece))
				forge.call("buy", piece)
				return "%s is yours, and it is on you." % name
			if id.begins_with("potion:"):
				var potion: String = id.trim_prefix("potion:")
				if not bool(forge.call("buy_consumable", potion)):
					return "Not enough crystals for another."
				return "One in the belt."
		"forge":
			if forge == null or not id.begins_with("forge:"):
				return ""
			var piece2: String = id.trim_prefix("forge:")
			if not bool(forge.call("can_upgrade", piece2)):
				return "Not enough of what it is made of, or not enough crystals."
			var forged_name: String = String(forge.call("def", piece2).get("name", piece2))
			forge.call("upgrade", piece2)
			return "%s comes off the anvil better than it went on." % forged_name
		"bounties":
			if id.begins_with("take:"):
				var take_id: String = id.trim_prefix("take:")
				if not Bounties.take(take_id):
					return "That name cannot be taken from here."
				return ""
			if id.begins_with("claim:"):
				var paid: Array = Bounties.claim(id.trim_prefix("claim:"))
				if paid.is_empty():
					return "Nothing of yours to settle there."
				return "Settled: %s" % ", ".join(paid)
	return ""


func _shop_panel(village_id: String) -> Dictionary:
	var village: Dictionary = def(village_id)
	var stock: Dictionary = shelf(village_id)
	var forge: Node = get_node_or_null("/root/Forge")
	var rows: Array = []
	for piece: Dictionary in (stock["pieces"] as Array):
		var tier: int = int(piece["tier"])
		if tier <= 0:
			rows.append({
				"id": "piece:%s" % String(piece["id"]),
				"label": String(piece["name"]),
				"detail": "%s — %s" % [String(piece["slot"]), String(piece["blurb"])],
				"right": "%d crystals" % int(piece["price"]),
				"enabled": bool(piece["can_buy"]),
			})
			continue
		var worn: bool = forge != null and String(forge.call("equipped_in", String(piece["slot"]))) == String(piece["id"])
		rows.append({
			"id": "wear:%s" % String(piece["id"]),
			"label": "%s (%s)" % [String(piece["name"]), String(piece["tier_name"])],
			"detail": "%s%s" % [
				"Worn now." if worn else "Yours, and not on.",
				" The anvil at Stonewatch can take it further." if tier < 5 else " Nothing better exists.",
			],
			"right": "worn" if worn else "wear it",
			"enabled": not worn,
		})
	for potion: Dictionary in (stock["consumables"] as Array):
		rows.append({
			"id": "potion:%s" % String(potion["id"]),
			"label": String(potion["name"]),
			"detail": "%s  (%d in the belt)" % [String(potion["blurb"]), int(potion["carried"])],
			"right": "%d crystals" % int(potion["price"]),
			"enabled": PlayerData.crystals >= int(potion["price"]),
		})
	var subtitle: String = "%s — %s.  You are %s here (%d).  %d crystals." % [
		String(village.get("name", "")), String(village.get("subtitle", "")),
		rep_label(village_id), rep_of(village_id), PlayerData.crystals,
	]
	# The shelf is empty because the gate is down, and the panel has to say which of the two
	# reasons it is: a shut door because the watch is hunting you and a shut door because the
	# village was burned last night are the same picture with opposite answers.
	if Raids.is_sacked(village_id):
		var mended: int = Raids.repair_cost(village_id)
		subtitle = "%s — the market is ash. The gate is down; %d crystals mends it, and any door in the square will take it." % [
			String(village.get("name", "")), mended
		]
	elif Law.shops_closed(village_id):
		subtitle = "The shutters are up. %s will not sell to an outlaw." % String(village.get("name", ""))
	elif Law.wanted_at(village_id) > 0:
		# Said out loud, because a price that quietly doubles is indistinguishable from a bug —
		# and because the surcharge is a thing the player is meant to feel and pay off.
		subtitle += "  Everything is %d%% dearer until they forget." % int(
			(LAW_SURCHARGE[clampi(Law.wanted_at(village_id), 0, LAW_SURCHARGE.size() - 1)] - 1.0)
				* 100.0)
	return {"title": "%s — what is for sale" % String(village.get("name", "")), "subtitle": subtitle,
		"rows": rows, "kind": "shop", "village": village_id}


func _forge_panel(village_id: String) -> Dictionary:
	var forge: Node = get_node_or_null("/root/Forge")
	var rows: Array = []
	if forge != null:
		for piece: Dictionary in (forge.get("PIECES") as Array):
			var id: String = String(piece["id"])
			var tier: int = int(forge.call("tier_of", id))
			if tier <= 0:
				continue
			var want: Dictionary = forge.call("upgrade_materials", id)
			var need_text: String = ""
			for material: String in want:
				need_text = "%s ×%d (you have %d)" % [
					String(forge.call("material_name", material)), int(want[material]),
					int(forge.call("material_count", material)),
				]
			var maxed: bool = tier >= int(forge.get("TIER_MAX"))
			rows.append({
				"id": "forge:%s" % id,
				"label": "%s — %s" % [String(piece["name"]), String(forge.call("tier_name", id))],
				"detail": "Nothing better exists." if maxed else "%s and %d crystals." % [
					need_text, int(forge.call("price_of", id))],
				"right": "done" if maxed else "%d crystals" % int(forge.call("price_of", id)),
				"enabled": bool(forge.call("can_upgrade", id)),
			})
	if rows.is_empty():
		rows.append({
			"id": "", "label": "Nothing to forge yet",
			"detail": "Buy something to wear first — the traders at the other villages keep the pieces.",
			"right": "", "enabled": false,
		})
	return {
		"title": "Forgemaster Du — the anvil",
		"subtitle": "Material and crystals, and it comes out better than it went on. It will never "
			+ "be worth more than the arm swinging it.",
		"rows": rows, "kind": "forge", "village": village_id,
	}


func _bounty_panel(village_id: String) -> Dictionary:
	var rows: Array = []
	for entry: Dictionary in Bounties.claimable(village_id):
		rows.append({
			"id": "claim:%s" % String(entry["id"]),
			"label": "%s — settled" % String(entry["name"]),
			"detail": "It is down. Collect.",
			"right": "+%d crystals" % int(entry["crystals"]),
			"enabled": true,
		})
	for entry: Dictionary in Bounties.slots(village_id):
		if bool(entry["claimed"]):
			continue
		if bool(entry["felled"]):
			continue
		var taken: bool = bool(entry["taken"])
		rows.append({
			"id": "take:%s" % String(entry["id"]),
			"label": "%s" % String(entry["name"]),
			"detail": "%s%s  %d crystals on the body." % [
				String(entry["camp"]), ", taken — it is waiting for you." if taken else "",
				int(entry["crystals"]),
			],
			"right": "taken" if taken else "take it",
			"enabled": not taken,
		})
	if rows.is_empty():
		rows.append({
			"id": "", "label": "Nothing on the board",
			"detail": "The clerk will have new names by tomorrow.",
			"right": "", "enabled": false,
		})
	return {
		"title": "%s — the board" % String(def(village_id).get("name", "")),
		"subtitle": "A name is a contract. Take one and the body stands at that camp until it "
			+ "is down, then bring the proof back here.",
		"rows": rows, "kind": "bounties", "village": village_id,
	}


func _board_panel(village_id: String) -> Dictionary:
	var village: Dictionary = def(village_id)
	var rows: Array = []
	var carrying: Array = carrying()
	for parcel: Dictionary in carrying:
		rows.append({
			"id": "", "label": "Carrying: %s" % String(parcel["name"]),
			"detail": "Somebody in another village is waiting for it.",
			"right": "", "enabled": false,
		})
	var step: Dictionary = current_step(village_id)
	if not step.is_empty():
		rows.append({
			"id": "", "label": String(step["title"]),
			"detail": String(step["detail"]),
			"right": "%d%%" % int(round(step_progress(village_id) * 100.0)),
			"enabled": false,
		})
	for done: Dictionary in _history:
		if String(done["village"]) != village_id:
			continue
		rows.append({
			"id": "", "label": "Done: %s" % String(done["step"]),
			"detail": "", "right": "✓", "enabled": false,
		})
	return {
		"title": "%s — the record" % String(village.get("name", "")),
		"subtitle": "You are %s here (%d standing). Everything %s has asked of you is on this page."
			% [rep_label(village_id), rep_of(village_id), String(village.get("name", ""))],
		"rows": rows, "kind": "board", "village": village_id,
	}


func summary() -> Dictionary:
	var out: Array = []
	for entry: Dictionary in VILLAGES:
		var id: String = String(entry["id"])
		out.append("%s(rep %d, step %d/%d)" % [
			String(entry["name"]), rep_of(id), step_index(id), chain(id).size(),
		])
	return {
		"villages": VILLAGES.size(), "people": PEOPLE.size(), "state": out,
		"placed": sites.keys(),
	}
