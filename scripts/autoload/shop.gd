extends Node
## What crystals are for.
##
## They were not for anything. The quest chain paid them, the raiders dropped them, the
## sites out in the world paid them, and the purse went up — and `spend_crystals` had no
## callers anywhere in the project. A currency that cannot be spent is a score, and a
## score that does nothing is the flattest reward a game can give: the number moves and the
## world does not.
##
## So this is the counter. Elder Shufen sells caps, because a cap is the one thing that is
## worth buying in a game where everything else has to be *earned by doing it*: you cannot
## buy speed, you can only buy the ceiling you are allowed to train speed up to. That
## keeps the bargain the rest of the game makes — training is always the work — while
## making the crystals from a hard camp worth the walk.
##
## Every ware is repeatable with a rising price, so the purse always has somewhere to go
## and the price curve is the pacing. The two ability wares are bounded on purpose: past
## four air jumps and a 0.4 s dash the character stops moving like a person.

signal purchased(ware: Dictionary, count: int)

const WARES: Array = [
	{
		"id": "hide", "name": "Toughened hide",
		"detail": "+8 HP held", "stat": "hp", "amount": 8.0,
		"base": 6, "step": 4,
	},
	{
		"id": "dantian", "name": "Deeper dantian",
		"detail": "+5 QI held", "stat": "qi", "amount": 5.0,
		"base": 8, "step": 6,
	},
	{
		"id": "hands", "name": "Heavier hands",
		"detail": "+0.8 ATTACK", "stat": "attack", "amount": 0.8,
		"base": 10, "step": 6,
	},
	{
		"id": "skin", "name": "Calloused skin",
		"detail": "+0.8 DEFENSE", "stat": "defense", "amount": 0.8,
		"base": 10, "step": 6,
	},
	{
		"id": "legs", "name": "Harder legs",
		"detail": "+0.4 m/s SPEED cap", "stat": "speed", "amount": 0.4,
		"base": 12, "step": 8,
	},
	{
		"id": "soles", "name": "Spring soles",
		"detail": "+0.20 m JUMP cap", "stat": "jump", "amount": 0.2,
		"base": 14, "step": 9,
	},
	{
		"id": "step", "name": "Sharper step",
		"detail": "-0.2 s dash cooldown", "ability": "dash_cooldown", "delta": -0.2,
		"base": 16, "step": 12, "floor": 0.4,
	},
	{
		"id": "airstep", "name": "Air step",
		"detail": "+1 jump in mid-air", "ability": "air_jumps", "delta": 1.0,
		"base": 34, "step": 26, "ceiling": 4.0,
	},
]

## How many times each ware has been bought. Kept in the save: a shop that forgets is a
## shop that sells you the same thing at the starting price forever.
var bought: Dictionary = {}

## What a decision somewhere else in the world did to the shelf. One is the shipped price;
## the elder's recovered ledger sets it below one for the rest of the run. It lives in the
## save because a discount that lasted until the next launch would make the choice that
## earned it a session-long trinket rather than a decision.
var discount: float = 1.0


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_shop()
	if not saved.is_empty():
		bought = saved.get("bought", {})
		discount = clampf(float(saved.get("discount", 1.0)), 0.25, 1.0)


func set_discount(factor: float) -> void:
	discount = clampf(factor, 0.25, 1.0)
	PlayerData.mark_dirty()


func def(id: String) -> Dictionary:
	for ware: Dictionary in WARES:
		if String(ware["id"]) == id:
			return ware
	return {}


func count(id: String) -> int:
	return int(bought.get(id, 0))


## What the next one costs. Rises with every purchase, so the tenth rank of a ware is a
## decision rather than a formality.
func price(id: String) -> int:
	var ware: Dictionary = def(id)
	if ware.is_empty():
		return 0
	var base: int = int(ware["base"]) + int(ware["step"]) * count(id)
	# Floored at one crystal rather than allowed to round to nothing: a shelf that hands out
	# its wares for free stops being a shelf, however generous the player has been.
	return maxi(1, int(round(float(base) * discount)))


## True when there is still something left to buy. The two bounded wares are bounded in
## different directions: air jumps count up to a ceiling, the cooldown counts down to a
## floor, and both are asked of PlayerData rather than tracked here — a shop with its own
## copy of the current cooldown is a shop that can sell you one you already have.
func available(id: String) -> bool:
	var ware: Dictionary = def(id)
	if ware.is_empty():
		return false
	if not ware.has("ability"):
		return true
	var id_ability: String = String(ware["ability"])
	var current: float = _ability_value(id_ability)
	if ware.has("ceiling"):
		return current < float(ware["ceiling"])
	return current > float(ware["floor"])


func can_buy(id: String) -> bool:
	return available(id) and PlayerData.crystals >= price(id)


## Buys one. Returns whether the sale went through, so the button cannot pay twice.
func buy(id: String) -> bool:
	if not can_buy(id):
		Audio.play("error", -8.0)
		return false
	var ware: Dictionary = def(id)
	if not PlayerData.spend_crystals(price(id)):
		return false
	bought[id] = count(id) + 1

	if ware.has("stat"):
		var gained: float = PlayerData.grant_cap(String(ware["stat"]), float(ware["amount"]))
		PlayerData.log_message.emit(
			"%s — %s cap +%s.  -%d crystals." % [
				String(ware["name"]),
				String(PlayerData.def(String(ware["stat"])).get("label", ware["stat"])),
				String.num(gained, 2), price(id),
			],
			"gain"
		)
	else:
		var ability: String = String(ware["ability"])
		var next: float = _ability_value(ability) + float(ware["delta"])
		if ware.has("ceiling"):
			next = minf(next, float(ware["ceiling"]))
		if ware.has("floor"):
			next = maxf(next, float(ware["floor"]))
		PlayerData.unlock_ability(ability, next)
		PlayerData.log_message.emit(
			"%s — %s.  -%d crystals." % [String(ware["name"]), String(ware["detail"]), price(id)],
			"gain"
		)
	Audio.play("coin", -2.0)
	PlayerData._dirty = true
	purchased.emit(ware, count(id))
	return true


## Read out of PlayerData rather than remembered here: the cooldown is also lowered by
## a task reward, and a shop that kept its own copy would happily sell a rank the player
## already owns.
func _ability_value(ability: String) -> float:
	match ability:
		"air_jumps":
			return float(PlayerData.air_jumps())
		"dash_cooldown":
			return PlayerData.dash_cooldown()
	return 0.0


func save_data() -> Dictionary:
	return {"bought": bought, "discount": discount}


func reset() -> void:
	bought.clear()
	discount = 1.0


## The purse against everything on the shelf, for the boot log and the self-test: a shop
## nobody can afford is a shop that does not exist.
func summary() -> Dictionary:
	var cheapest: int = 9999
	var total: int = 0
	for ware: Dictionary in WARES:
		var cost: int = price(String(ware["id"]))
		cheapest = mini(cheapest, cost)
		total += cost
	return {
		"wares": WARES.size(),
		"cheapest": cheapest,
		"first_pass": total,
		"crystals": PlayerData.crystals,
	}
