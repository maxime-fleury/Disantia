extends Node
## What the body is carrying, and what it is wearing.
##
## There was no item layer at all: every number in the game was the body's own, and the only
## things crystals bought were *ceilings* — the right bank for a game where everything else
## has to be trained, and useless for the other half of a role-playing game, which is the part
## where you find a thing and it changes how you play. Three villages selling the same shelf
## would have been one shop in three places, so the shelf is split across the valley: the
## wraps are at the home village, the blade is the smith's, the seal is at the foot of the
## tower. Walking to the next village is how you shop.
##
## **The one rule that keeps this from eating the game.** Gear *multiplies* what you trained;
## it never replaces it. A blade at its finest is ×1.30 on a fist that is already yours, so
## training ATTACK is still the whole of ATTACK — a flat "+20 ATTACK" sword would have made
## the training yard, the raiders and the whole first ten hours of the game pointless the
## moment a purse was big enough. The same goes the other way: a fresh body with the best
## blade in the valley still hits like a fresh body, because a multiplier on nothing is
## nothing.
##
## Materials are the other half. Champions and the tower drop what the forge needs, so
## "upgrade the coat" is a reason to fight the thing that has scales rather than a purchase
## made out of pocket change.

signal changed
signal material_gained(id: String, count: int, total: int)
signal item_gained(id: String, tier: int)
signal equipped_changed(slot: String, id: String)
signal used(id: String)

# --------------------------------------------------------------------- materials

## What the world gives up, and who gives it up. `colour` is inherited by whatever is made
## from it, which is what makes the tier of a piece readable on the body without a label.
const MATERIALS: Dictionary = {
	"hide_scrap": {"name": "Hide Scrap", "colour": Color("9c7b52"), "from": "the raiders of the near rings"},
	"iron_scale": {"name": "Iron Scale", "colour": Color("8d97a3"), "from": "the raiders past the second ward"},
	"ash_cinder": {"name": "Ash Cinder", "colour": Color("e2734a"), "from": "the Ash Champion's ground"},
	"iron_heart": {"name": "Iron Heart", "colour": Color("b7c6d6"), "from": "the Iron Champion's ground"},
	"ninth_ember": {"name": "Ninth Ember", "colour": Color("ffd76e"), "from": "the Ninth's ground"},
	"tower_splinter": {"name": "Tower Splinter", "colour": Color("c9a6ff"), "from": "the floors of the tower"},
	"vein_jade": {"name": "Vein Jade", "colour": Color("6ee7a8"), "from": "the Earth Vein's ground"},
	"spirit_dust": {"name": "Spirit Dust", "colour": Color("8fe3ff"), "from": "raiders, marks and caravans"},
}

# ------------------------------------------------------------------------ pieces

## One entry per piece of gear. `at` is the village whose shelf carries it, which is the whole
## geography of shopping; `slot` is what it competes with; `base` is the crystal price at its
## first tier, and every tier after that costs `base * tier` in crystals plus materials.
##
## Effects are shares rather than numbers — see the note at the top of the file.
const PIECES: Array = [
	{
		"id": "jade_wraps", "name": "Jade Wraps", "slot": "weapon", "at": "hollowmere",
		"base": 38, "material": "hide_scrap", "blurb": "Strips of hide wound tight. Every blow is yours, only more so.",
	},
	{
		"id": "ash_blade", "name": "Ash Blade", "slot": "weapon", "at": "stonewatch",
		"base": 120, "material": "ash_cinder", "blurb": "Quenched in the Ash Champion's own cinder.",
	},
	{
		"id": "wind_edge", "name": "Wind Edge", "slot": "weapon", "at": "towerfall",
		"base": 280, "material": "tower_splinter", "blurb": "Ground out of a splinter of the tower's own stair.",
	},
	{
		"id": "traveller_hide", "name": "Traveller's Hide", "slot": "armour", "at": "hollowmere",
		"base": 44, "material": "hide_scrap", "blurb": "Cured hide. It stops the road, not a champion.",
	},
	{
		"id": "iron_shell", "name": "Iron Shell Coat", "slot": "armour", "at": "stonewatch",
		"base": 130, "material": "iron_scale", "blurb": "Scale over leather. The smith's answer to a fist.",
	},
	{
		"id": "storm_robe", "name": "Storm Silk Robe", "slot": "armour", "at": "towerfall",
		"base": 300, "material": "ninth_ember", "blurb": "Silk the colour of the sky over the outer reach.",
	},
	{
		"id": "spring_charm", "name": "Springwater Charm", "slot": "charm", "at": "hollowmere",
		"base": 34, "material": "spirit_dust", "blurb": "A stone from the Spirit Spring, on a cord.",
	},
	{
		"id": "vein_talisman", "name": "Vein Talisman", "slot": "charm", "at": "stonewatch",
		"base": 110, "material": "vein_jade", "blurb": "Jade cut from the Earth Vein. It breathes with you.",
	},
	{
		"id": "peak_seal", "name": "Peak Seal", "slot": "charm", "at": "towerfall",
		"base": 260, "material": "iron_heart", "blurb": "A seal from the Storm Peak, worn as a claim.",
	},
	{
		# The one piece that makes no number bigger. A night in this valley is a real night —
		# the light goes, the raiders see further and the raids only ever land in the dark — and
		# the honest answer to it used to be a fire and a wait. Its tiers are the *lit radius*
		# rather than a share of anything the body trained, which is why it lives here and not
		# on the elder's shelf: buying it is a purchase, upgrading it is a reason to walk to
		# the smith, and carrying it changes what the player can do at an hour rather than in a
		# fight. See `scripts/player/lantern.gd` for what the tiers are worth.
		"id": "traveller_lamp", "name": "Traveller's Lamp", "slot": "lamp", "at": "hollowmere",
		"base": 24, "material": "spirit_dust",
		"blurb": "A hooded lamp on a belt hook. It lights the road, not the fight.",
	},
]

## Roman-ish tier names, so an upgraded piece says what it is without a number.
const TIERS: Array = ["", "plain", "good", "fine", "master", "peerless"]
const TIER_MAX := 5

# ------------------------------------------------------------------ consumables

## Things you can use. Each one is a button on the belt, so the belt is limited to four:
## a bar of twenty potions is a bar nobody reads.
##
## The mending pill is the one that matters most, because it is the way out of a wound that
## costs crystals instead of a walk. A death is then a bill rather than a timer — and a bill
## can be paid, dodged, or *not* paid and carried, which are three decisions where a timer had
## none.
const CONSUMABLES: Array = [
	{
		"id": "mending_pill", "name": "Mending Pill", "at": ["hollowmere", "towerfall"],
		"price": 18, "blurb": "Closes one wound, or pours back a third of your health.",
	},
	{
		"id": "qi_pill", "name": "Qi Pill", "at": ["hollowmere", "stonewatch", "towerfall"],
		"price": 14, "blurb": "A deep breath, bottled. Restores 45% of the pool.",
	},
	{
		"id": "blood_elixir", "name": "Blood Elixir", "at": ["towerfall"],
		"price": 40, "blurb": "+35% on every blow for 45 seconds.",
	},
	{
		"id": "spirit_ward", "name": "Spirit Ward", "at": ["stonewatch"],
		"price": 52, "blurb": "Six tenths of every blow turned aside for 30 seconds.",
	},
]

const BELT_SIZE := 4

## Material id -> count. Materials survive everything except being spent.
var materials: Dictionary = {}
## Piece id -> tier owned (0 or absent = not owned).
var owned: Dictionary = {}
## Slot -> piece id currently worn. One per slot, because a role is a choice.
var equipped: Dictionary = {}
## Consumable id -> count carried.
var belt: Dictionary = {}

## The timed effects a consumable buys, kept here rather than in PlayerData because they are
## things in the world that will run out. Milliseconds on the engine clock.
var _attack_until_ms: int = 0
var _ward_until_ms: int = 0
const ELIXIR_SECONDS := 45.0
const WARD_SECONDS := 30.0
const ELIXIR_MULTIPLIER := 1.35
const WARD_MULTIPLIER := 0.60

## How much of the total gear effect is live, for the HUD's little readout.
const WEAPON_PER_TIER := 0.06
const ARMOUR_PER_TIER := 0.05
const CHARM_REGEN_PER_TIER := 0.10
const ARMOUR_FLOOR := 0.60


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_module("forge")
	materials = saved.get("materials", {})
	owned = saved.get("owned", {})
	equipped = saved.get("equipped", {})
	belt = saved.get("belt", {})
	_prune()


## A save can outlive a catalogue — a piece renamed, a slot dropped — and a worn item that no
## longer exists is a multiplier with nothing behind it. Cheaper to check once than to guard
## every read.
func _prune() -> void:
	for slot: String in equipped.keys():
		var id: String = String(equipped[slot])
		if def(id).is_empty() or tier_of(id) <= 0:
			equipped.erase(slot)
	for key: String in materials.keys():
		if not MATERIALS.has(key):
			materials.erase(key)
		else:
			materials[key] = maxi(0, int(materials[key]))
	for key: String in belt.keys():
		if consumable(key).is_empty():
			belt.erase(key)


func save_data() -> Dictionary:
	return {"materials": materials, "owned": owned, "equipped": equipped, "belt": belt}


func reset() -> void:
	materials.clear()
	owned.clear()
	equipped.clear()
	belt.clear()
	_attack_until_ms = 0
	_ward_until_ms = 0
	changed.emit()


# ------------------------------------------------------------------ the catalogue

func def(id: String) -> Dictionary:
	for piece: Dictionary in PIECES:
		if String(piece["id"]) == id:
			return piece
	return {}


func consumable(id: String) -> Dictionary:
	for entry: Dictionary in CONSUMABLES:
		if String(entry["id"]) == id:
			return entry
	return {}


## Everything a given village's shelves carry: the pieces whose `at` is this village, plus the
## consumables that list it.
func stock_here(village_id: String) -> Dictionary:
	var pieces: Array = []
	for piece: Dictionary in PIECES:
		if String(piece["at"]) == village_id:
			pieces.append(piece)
	var potions: Array = []
	for entry: Dictionary in CONSUMABLES:
		var where: Array = entry["at"]
		if where.has(village_id):
			potions.append(entry)
	return {"pieces": pieces, "consumables": potions}


func tier_of(id: String) -> int:
	return clampi(int(owned.get(id, 0)), 0, TIER_MAX)


func tier_name(id: String) -> String:
	var tier: int = tier_of(id)
	return String(TIERS[tier]) if tier > 0 else "not owned"


func material_count(id: String) -> int:
	return int(materials.get(id, 0))


func material_name(id: String) -> String:
	var entry: Dictionary = MATERIALS.get(id, {})
	return String(entry.get("name", id))


func add_material(id: String, count: int, announce: bool = true) -> int:
	if count <= 0 or not MATERIALS.has(id):
		return 0
	materials[id] = material_count(id) + count
	PlayerData.mark_dirty()
	if announce:
		PlayerData.log_message.emit(
			"%s ×%d.  (%d held)" % [material_name(id), count, material_count(id)], "gain"
		)
	material_gained.emit(id, count, material_count(id))
	changed.emit()
	return material_count(id)


## What a ring's raiders are carrying. The rings are the map's difficulty ladder, so they are
## its material ladder too: the near rings give the first piece its materials, and the far
## rings give the last one its.
func material_for_ring(ring: int) -> String:
	if ring <= 1:
		return "hide_scrap"
	if ring == 2:
		return "iron_scale"
	return "vein_jade"


## The chance an ordinary raider of that ring drops one at all. High enough that a handful of
## fights pays for the first upgrade, low enough that the shelf is not free.
func drop_chance_for_ring(ring: int) -> float:
	return 0.34 if ring <= 1 else (0.30 if ring == 2 else 0.28)


# ----------------------------------------------------------------------- money

## Crystal price of a piece at its next tier. A tier-1 blade is the price on the shelf; the
## fifth is five times that, so the last upgrade of a piece is a decision rather than a
## formality.
func price_of(id: String) -> int:
	var piece: Dictionary = def(id)
	if piece.is_empty():
		return 0
	var next: int = tier_of(id) + 1
	# Reputation is the discount and the only one in the game that moves: a village that
	# trusts you charges less, which is the plainest reason to do anything for anybody.
	return maxi(1, int(round(float(piece["base"]) * float(next) * Villages.price_factor(String(piece["at"])))))


## What the forge wants besides crystals for the next tier. Costed in the material the piece
## is *made of*, so a blade of ash needs more ash, and the count climbs with the tier.
func upgrade_materials(id: String) -> Dictionary:
	var piece: Dictionary = def(id)
	if piece.is_empty():
		return {}
	var next: int = tier_of(id) + 1
	if next > TIER_MAX:
		return {}
	var material: String = String(piece["material"])
	return {material: 1 + 2 * next}


func can_buy(id: String) -> bool:
	if def(id).is_empty() or tier_of(id) > 0:
		return false
	return PlayerData.crystals >= price_of(id)


## Buying puts the piece on its first tier and wears it straight away: a purchase that then
## has to be equipped by hand is a step nobody enjoys.
func buy(id: String) -> bool:
	if not can_buy(id):
		Audio.play("error", -8.0)
		return false
	var piece: Dictionary = def(id)
	if not PlayerData.spend_crystals(price_of(id)):
		return false
	owned[id] = 1
	equip(id)
	PlayerData.log_message.emit(
		"%s — %s %s.  -%d crystals." % [
			String(piece["name"]), String(TIERS[1]), String(piece["slot"]), price_of(id),
		],
		"gain"
	)
	Audio.play("coin", -1.0)
	item_gained.emit(id, 1)
	changed.emit()
	return true


func materials_ready(id: String) -> bool:
	var want: Dictionary = upgrade_materials(id)
	for material: String in want:
		if material_count(material) < int(want[material]):
			return false
	return true


func can_upgrade(id: String) -> bool:
	var tier: int = tier_of(id)
	if tier <= 0 or tier >= TIER_MAX:
		return false
	return materials_ready(id) and PlayerData.crystals >= price_of(id)


## Forges one tier higher. Returns whether anything happened, so the button cannot pay twice.
func upgrade(id: String) -> bool:
	if not can_upgrade(id):
		Audio.play("error", -8.0)
		return false
	var cost: int = price_of(id)
	var want: Dictionary = upgrade_materials(id)
	if not PlayerData.spend_crystals(cost):
		return false
	for material: String in want:
		materials[material] = material_count(material) - int(want[material])
	var next: int = tier_of(id) + 1
	owned[id] = next
	PlayerData.log_message.emit(
		"%s forged to %s (tier %d).  -%d crystals." % [
			String(def(id)["name"]), String(TIERS[next]), next, cost,
		],
		"breakthrough"
	)
	Audio.play("breakthrough", -2.0)
	equipped_changed.emit(String(def(id)["slot"]), String(equipped.get(String(def(id)["slot"]), "")))
	changed.emit()
	return true


func equip(id: String) -> void:
	var piece: Dictionary = def(id)
	if piece.is_empty() or tier_of(id) <= 0:
		return
	var slot: String = String(piece["slot"])
	equipped[slot] = id
	PlayerData.mark_dirty()
	equipped_changed.emit(slot, id)
	changed.emit()


func equipped_in(slot: String) -> String:
	return String(equipped.get(slot, ""))


func slot_tier(slot: String) -> int:
	return tier_of(equipped_in(slot))


# ----------------------------------------------------------------------- effects

## What the body's own training is multiplied by. Everything below is a *share*, and the
## caller (PlayerData) is the one holding the number being multiplied — which is the whole
## reason a piece of gear cannot outgrow the person wearing it.
func strike_multiplier() -> float:
	return 1.0 + WEAPON_PER_TIER * float(slot_tier("weapon"))


func damage_taken_multiplier() -> float:
	var share: float = ARMOUR_PER_TIER * float(slot_tier("armour"))
	return maxf(ARMOUR_FLOOR, 1.0 - share)


func regen_multiplier_for(stat_id: String) -> float:
	if stat_id != "qi":
		return 1.0
	return 1.0 + CHARM_REGEN_PER_TIER * float(slot_tier("charm"))


## A charm is also a deeper pool to spend, in the share of what the body already holds.
func charm_share() -> float:
	return 0.07 * float(slot_tier("charm"))


# ------------------------------------------------------------------------- belt

func carried(id: String) -> int:
	return int(belt.get(id, 0))


func buy_consumable(id: String) -> bool:
	var entry: Dictionary = consumable(id)
	if entry.is_empty():
		return false
	var price: int = int(round(float(entry["price"]) * Villages.price_factor(
		String((entry["at"] as Array)[0]))))
	if PlayerData.crystals < price:
		Audio.play("error", -8.0)
		return false
	if not PlayerData.spend_crystals(price):
		return false
	belt[id] = carried(id) + 1
	PlayerData.log_message.emit(
		"%s ×1.  (%d carried, -%d crystals)" % [String(entry["name"]), carried(id), price],
		"gain"
	)
	Audio.play("coin", -3.0)
	changed.emit()
	return true


## Uses one. Returns whether it did anything, so a belt button cannot eat a pill on a body
## that had nothing wrong with it.
func use(id: String) -> bool:
	if carried(id) <= 0:
		Audio.play("error", -8.0)
		return false
	var entry: Dictionary = consumable(id)
	if entry.is_empty():
		return false
	var worked: bool = false
	match id:
		"mending_pill":
			if PlayerData.wounds > 0:
				PlayerData.clear_wound()
				worked = true
			elif PlayerData.get_value("hp") < PlayerData.get_cap("hp") - 0.5:
				PlayerData.restore("hp", PlayerData.get_cap("hp") * 0.34)
				worked = true
		"qi_pill":
			if PlayerData.get_value("qi") < PlayerData.get_cap("qi") - 0.5:
				PlayerData.restore("qi", PlayerData.get_cap("qi") * 0.45)
				worked = true
		"blood_elixir":
			_attack_until_ms = Time.get_ticks_msec() + int(ELIXIR_SECONDS * 1000.0)
			worked = true
			PlayerData.log_message.emit(
				"Blood Elixir — every blow lands heavier for %.0fs." % ELIXIR_SECONDS, "breakthrough"
			)
		"spirit_ward":
			_ward_until_ms = Time.get_ticks_msec() + int(WARD_SECONDS * 1000.0)
			worked = true
			PlayerData.log_message.emit(
				"Spirit Ward — the blows come in at six tenths for %.0fs." % WARD_SECONDS, "breakthrough"
			)
	if not worked:
		Audio.play("error", -8.0)
		return false
	belt[id] = carried(id) - 1
	if int(belt[id]) <= 0:
		belt.erase(id)
	Audio.play("confirm", -3.0)
	used.emit(id)
	changed.emit()
	return true


## The belt as the HUD wants it: four slots, in a fixed order, each with a count.
func belt_slots() -> Array:
	var out: Array = []
	for entry: Dictionary in CONSUMABLES:
		var id: String = String(entry["id"])
		out.append({
			"id": id, "name": String(entry["name"]),
			"count": carried(id), "blurb": String(entry["blurb"]),
		})
		if out.size() >= BELT_SIZE:
			break
	return out


func attack_tonic() -> float:
	if Time.get_ticks_msec() >= _attack_until_ms:
		return 1.0
	return ELIXIR_MULTIPLIER


func ward_tonic() -> float:
	if Time.get_ticks_msec() >= _ward_until_ms:
		return 1.0
	return WARD_MULTIPLIER


func tonic_seconds_left() -> float:
	var left: int = maxi(_attack_until_ms, _ward_until_ms) - Time.get_ticks_msec()
	return maxf(0.0, float(left) / 1000.0)


# -------------------------------------------------------------------- reporting

## Everything the panel and the boot log need in one call.
func summary() -> Dictionary:
	var worn: Array = []
	for slot: String in ["weapon", "armour", "charm"]:
		var id: String = equipped_in(slot)
		if id == "":
			continue
		worn.append("%s(%s %d)" % [slot, id, slot_tier(slot)])
	var held: Array = []
	for material: String in MATERIALS:
		if material_count(material) > 0:
			held.append("%s=%d" % [material, material_count(material)])
	return {
		"owned": owned.size(),
		"worn": worn,
		"materials": held,
		"strike": strike_multiplier(),
		"taken": damage_taken_multiplier(),
	}
