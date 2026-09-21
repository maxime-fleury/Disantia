extends Node
## Autoload. Owns the cultivator's body: every stat, the cap earned through play,
## the player's chosen operating point, and persistence.
##
## Stat model
## ----------
##   cap        the highest value the player has *earned*. Only ever grows, and
##              only from the actions listed in `earned_by`. This is the hard
##              ceiling the HUD sliders are clamped to.
##   current    resource stats only (QI, HP): the live value that is spent and
##              regenerates on its own.
##   allocated  trainable stats only (SPEED, JUMP): the value the player dialled
##              in with the HUD sliders, always clamped to `cap`.
##   progress   xp banked toward the next cap increase.
##
## `gain()` is the single funnel every action goes through, which is what makes
## the cultivation coefficient work: it scales *all* stat income at once.

signal stats_changed
signal stat_cap_gained(stat_id: String, old_cap: float, new_cap: float)
signal allocation_changed(stat_id: String, value: float)
signal aura_changed(element: String)
signal crystals_changed(total: int)
signal ability_unlocked(id: String)
signal log_message(text: String, kind: String)

const KIND_RESOURCE := "resource"
const KIND_TRAINABLE := "trainable"
const KIND_PASSIVE := "passive"

const STAT_ORDER: Array = ["qi", "hp", "speed", "jump", "defense", "attack", "body"]

## Each rank of constitution widens the HP cap by this fraction of itself. This is
## what makes physical training worth the bruises: it needs no qi at all, and it
## is the only path to a bigger body.
const BODY_HP_BONUS := 0.04

## Absolute ceilings, per stat, that no amount of training can pass.
##
## Everything else in this file grows without a bound, and for most stats that is right:
## a bigger health pool or a heavier blow has no point at which it stops being a stat. A
## jump does. Past twenty metres the body is not jumping any more, it is flying, and
## every hill, every fence and every raider camp that was laid out to be reached on foot
## stops meaning anything. The ceiling is what keeps the terrain a place you travel
## across rather than a place you skip over.
##
## Enforced in one helper and called from every place a cap can move — growth, the
## cross-stat grant, a breakthrough, and the save file — because a ceiling that holds
## against four of those five is a ceiling that does not hold.
const HARD_CAP: Dictionary = {
	"jump": 20.0,
}

## `need` is how much xp is required per cap increase, expressed as a multiple of
## the current cap. `cap_step` is how much the cap grows each time, as a fraction
## of the current cap. Both are fractions of the cap, so growth is a soft
## exponential: each rank is a little bigger and a little more expensive.
const STAT_DEFS: Dictionary = {
	"qi": {
		"label": "QI",
		"unit": "",
		"decimals": 1,
		"color": Color("6ec8ff"),
		"kind": KIND_RESOURCE,
		"base_cap": 50.0,
		"cap_step": 0.06,
		"need": 1.0,
		"xp_hint": "1 xp per 0.5 QI spent meditating",
		"earned_by": "Refining it while meditating",
	},
	"hp": {
		"label": "HP",
		"unit": "",
		"decimals": 1,
		"color": Color("ff5f6d"),
		"kind": KIND_RESOURCE,
		"base_cap": 100.0,
		"cap_step": 0.05,
		"need": 1.5,
		"xp_hint": "2 xp per point of damage weathered",
		"earned_by": "Weathering damage",
	},
	"speed": {
		"label": "SPEED",
		"unit": "m/s",
		"decimals": 2,
		"color": Color("7dff9b"),
		"kind": KIND_TRAINABLE,
		"base_cap": 5.0,
		"cap_step": 0.05,
		"need": 12.0,
		"xp_hint": "1 xp per metre run (hold Shift)",
		"earned_by": "Running (hold Shift)",
	},
	"jump": {
		"label": "JUMP",
		"unit": "m",
		"decimals": 2,
		"color": Color("ffd76e"),
		"kind": KIND_TRAINABLE,
		"base_cap": 1.6,
		"cap_step": 0.06,
		"need": 6.0,
		"xp_hint": "1 xp per jump, scaled by how high you jumped",
		"earned_by": "Jumping",
	},
	"defense": {
		"label": "DEFENSE",
		"unit": "",
		"decimals": 1,
		"color": Color("c9a6ff"),
		"kind": KIND_PASSIVE,
		"base_cap": 5.0,
		"cap_step": 0.05,
		"need": 2.0,
		"xp_hint": "0.5 xp per point of damage weathered",
		"earned_by": "Toughening up under damage",
	},
	"attack": {
		"label": "ATTACK",
		"unit": "",
		"decimals": 1,
		"color": Color("ff9d5c"),
		"kind": KIND_PASSIVE,
		"base_cap": 5.0,
		"cap_step": 0.05,
		"need": 4.0,
		"xp_hint": "1 xp per point of damage dealt to a post",
		"earned_by": "Striking the training posts",
	},
	"body": {
		"label": "BODY",
		"unit": "",
		"decimals": 1,
		"color": Color("9be8c8"),
		"kind": KIND_PASSIVE,
		"base_cap": 5.0,
		"cap_step": 0.06,
		"need": 5.0,
		"xp_hint": "1 xp per rep of physical training",
		"earned_by": "Pushups, squats and standing stance",
	},
}

## Fraction of the cap regenerated per second, for resources that refill on their
## own.
##
## Both are fractions of the *cap*, never flat amounts, which is what the health bar
## has to be: regeneration is a share of the pool, so training the pool up is what
## makes a body knit itself back together faster rather than merely last longer. A
## cap that doubles takes exactly twice the HP per second back.
const RESOURCE_REGEN: Dictionary = {
	"hp": 0.012,
	"qi": 0.05,
}

## Which pools are held at zero once emptied rather than trickling back up.
##
## Blood, and only blood. An emptied health pool that regenerates is a state nothing can
## ever observe: the body gets lifted off the floor by its own regeneration on the very
## next frame, so a collapse cannot happen, cannot be seen and cannot be tested.
##
## Breath is the opposite, and leaving qi in this list was a real dead end rather than a
## theoretical one. Qigong drains qi to the bottom of the bar *on purpose*, so a single
## session of cultivation to empty switched passive regen off for good: the pool sat at
## zero for the rest of the save, meditation bought nothing, and the player could never
## cultivate again. It is a rule about the pool, not about how fast it refills, which is
## why it is a list of its own rather than more entries in the rates above.
const HELD_AT_ZERO: Array = ["hp"]

## Everything the player has beyond the fundamentals. Kept as data rather than as a
## set of booleans so a quest can grant a named thing without this file needing to
## know which quest granted it, and so a new unlock is one dictionary entry.
const DEFAULT_ABILITIES: Dictionary = {
	## Jumps allowed after leaving the ground. 1 is a single jump; the air jump a task
	## can grant is what makes this grow.
	"air_jumps": 0,
	"dash": false,
	"dash_cooldown": 2.4,
}

## The one currency. Dropped by defeated raiders and handed out as a task reward,
## and a plain count because nothing about it grows or regenerates.
var crystals: int = 0
var abilities: Dictionary = DEFAULT_ABILITIES.duplicate(true)

## Scale applied to the whole interface, chosen in the settings panel. Fullscreen on
## a large monitor makes the default HUD look oversized, so the size is the player's
## call rather than a constant.
var ui_scale: float = 0.85
const UI_SCALE_MIN := 0.6
const UI_SCALE_MAX := 1.3

const SAVE_PATH := "user://disantia_save.json"
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 15.0

## Set by Cultivation. Multiplies every xp gain. Starts at 1.0.
var gain_coefficient: float = 1.0

## Which elemental aura the player has equipped, chosen in the settings panel.
## Cultivation owns the catalogue and the unlock rules; this is only the choice,
## so that it travels with the rest of the save.
var chosen_aura: String = ""

## True while the trance is running. Passive QI regen has to stop or it would cancel out
## the qigong drain and meditation would cost nothing. HP keeps regenerating: sitting
## still and healing is the point.
##
## Derived from the trance rather than set by it. It used to be a plain flag that
## `start_meditation` turned on and `stop_meditation` turned off — one writer per way out
## of the trance, and a trance that ends by any *other* path (a reset, a death, a path
## added later by someone who never saw this variable) leaves the flag stuck on. QI is then
## dead for the rest of the session, and the only symptom is a bar that never fills: the
## exact shape of the bug where qigong drained the pool to zero and nothing ever brought it
## back. Reading it from the trance makes that state unrepresentable.
var suppress_qi_regen: bool:
	get:
		return Cultivation.meditating

## Runtime state, keyed by stat id.
var stats: Dictionary = {}

## Player-chosen operating point for trainable stats.
var allocated: Dictionary = {}

## Where to drop the player on load.
var saved_position: Vector3 = Vector3.ZERO
var has_saved_position: bool = false

var _autosave_accum: float = 0.0
var _dirty: bool = false
var _loaded_cultivation: Dictionary = {}
var _cultivation_consumed: bool = false
var _loaded_quests: Dictionary = {}
var _quests_consumed: bool = false


func _ready() -> void:
	_build_defaults()
	if not load_game():
		log_message.emit("A new cultivator awakens.", "info")
	# Keep ticking while the window is unfocused so autosave stays predictable.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Browsers give no reliable "about to close" event, so losing focus counts as
## a checkpoint too. user:// is backed by IndexedDB in the web build.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _dirty:
			save_game()


func _process(delta: float) -> void:
	for id: String in RESOURCE_REGEN:
		if id == "qi" and suppress_qi_regen:
			continue
		var entry: Dictionary = stats[id]
		# An emptied pool stays empty only where that is the point. See HELD_AT_ZERO:
		# for blood it is what makes a collapse observable, and for breath the same rule
		# was a one-way door out of the cultivation loop.
		if float(entry["current"]) <= 0.0 and HELD_AT_ZERO.has(id):
			continue
		var cap: float = entry["cap"]
		entry["current"] = minf(cap, float(entry["current"]) + cap * float(RESOURCE_REGEN[id]) * delta)
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_SECONDS:
		_autosave_accum = 0.0
		if _dirty:
			save_game()


# ---------------------------------------------------------------- setup / defs

func _build_defaults() -> void:
	stats.clear()
	allocated.clear()
	for id: String in STAT_ORDER:
		var def: Dictionary = STAT_DEFS[id]
		var cap: float = def["base_cap"]
		stats[id] = {
			"cap": cap,
			"current": cap,
			"progress": 0.0,
		}
		if def["kind"] == KIND_TRAINABLE:
			allocated[id] = cap


func def(stat_id: String) -> Dictionary:
	return STAT_DEFS.get(stat_id, {})


func kind(stat_id: String) -> String:
	return String(def(stat_id).get("kind", KIND_PASSIVE))


func is_resource(stat_id: String) -> bool:
	return kind(stat_id) == KIND_RESOURCE


func is_trainable(stat_id: String) -> bool:
	return kind(stat_id) == KIND_TRAINABLE


func label(stat_id: String) -> String:
	return String(def(stat_id).get("label", stat_id.to_upper()))


func color(stat_id: String) -> Color:
	return def(stat_id).get("color", Color.WHITE)


# ------------------------------------------------------------------ power level

## How much of the score comes from one stat having doubled.
const POWER_PER_RATIO := 240
## And how much from one stage of cultivation.
const POWER_PER_STAGE := 600


## One number for everything the body has become.
##
## Each stat folds in as *how far its cap has grown from where it started* rather than
## as its raw value, because the stats do not share a unit: a metre of jump height and a
## point of qi cap cannot be added, and a score built by adding them would be arithmetic
## on nothing and would jump whenever a stat's units changed. A ratio is dimensionless,
## so a doubled jump and a doubled health pool are each worth the same, which is the
## only sane thing for a single number to mean.
##
## Cultivation is weighted heavily enough that a breakthrough always shows. That is the
## point of including it at all: stage is what the whole game is built around, and a
## power level that barely moved when you broke through would be measuring the wrong
## thing. It is also what makes the number keep climbing during a stretch of play where
## every stat is far from its next rank.
##
## The result is a plain integer with no unit. It is a score, and the only things it has
## to be are monotonic in every way the player can grow and honest about it — everything
## folded in here is a cap, and a cap only ever goes up.
func power_level() -> int:
	var total: float = 0.0
	for id: String in STAT_ORDER:
		var base: float = maxf(0.001, float(def(id).get("base_cap", 1.0)))
		total += get_cap(id) / base
	return int(round(total * POWER_PER_RATIO + float(Cultivation.tier) * POWER_PER_STAGE))


## The power level as it is shown: 12345 -> "12,345".
##
## Ungrouped digits above four figures are a string nobody can size at a glance, and being
## sized at a glance is the entire job of this number. It lives here rather than in the
## plate that draws it because the settings panel shows it too, and two formatters for one
## score is how the two come to disagree.
func power_text() -> String:
	return group_int(power_level())


## 12345 -> "12,345". Shared by the settings panel and the plate over your head, so the
## two can never render the same score differently.
func group_int(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out


# ------------------------------------------------------------------ accessors

func get_cap(stat_id: String) -> float:
	if not stats.has(stat_id):
		return 0.0
	return float(stats[stat_id]["cap"])


## The number that actually applies right now: live HP/QI, the allocated value
## for SPEED/JUMP, and the earned cap for passive stats.
func get_value(stat_id: String) -> float:
	if not stats.has(stat_id):
		return 0.0
	match kind(stat_id):
		KIND_RESOURCE:
			return float(stats[stat_id]["current"])
		KIND_TRAINABLE:
			return float(allocated.get(stat_id, stats[stat_id]["cap"]))
		_:
			return float(stats[stat_id]["cap"])


func get_allocated(stat_id: String) -> float:
	if not stats.has(stat_id):
		return 0.0
	return float(allocated.get(stat_id, stats[stat_id]["cap"]))


## 0..1 progress toward the next cap increase.
func progress_ratio(stat_id: String) -> float:
	if not stats.has(stat_id):
		return 0.0
	var entry: Dictionary = stats[stat_id]
	var required: float = float(entry["cap"]) * float(def(stat_id)["need"])
	if required <= 0.0:
		return 0.0
	return clampf(float(entry["progress"]) / required, 0.0, 1.0)


func format_value(stat_id: String, value: float) -> String:
	var defn: Dictionary = def(stat_id)
	var text := String.num(value, int(defn.get("decimals", 1)))
	var unit := String(defn.get("unit", ""))
	return text + unit if unit != "" else text


## "12.4 / 50" style readout for the HUD.
func readout(stat_id: String) -> String:
	var defn: Dictionary = def(stat_id)
	match String(defn.get("kind", KIND_PASSIVE)):
		KIND_RESOURCE:
			return "%s / %s" % [
				format_value(stat_id, get_value(stat_id)),
				format_value(stat_id, get_cap(stat_id)),
			]
		KIND_TRAINABLE:
			return "%s / %s" % [
				format_value(stat_id, get_allocated(stat_id)),
				format_value(stat_id, get_cap(stat_id)),
			]
		_:
			return format_value(stat_id, get_cap(stat_id))


# ----------------------------------------------------------------- earning xp

## The one funnel for stat income. `amount` is raw xp; the cultivation
## coefficient is applied here so every action gets faster as you cultivate.
func gain(stat_id: String, amount: float) -> void:
	if amount <= 0.0 or not stats.has(stat_id):
		return
	# At the ceiling there is nothing left to buy, so the xp is not banked either. A
	# stat that keeps eating progress it can never spend would be a silent xp sink: the
	# player would see the number stop moving and have no way to tell that the reason is
	# a limit rather than a bug.
	if float(stats[stat_id]["cap"]) >= cap_ceiling(stat_id):
		return
	var scaled: float = amount * gain_coefficient
	var entry: Dictionary = stats[stat_id]
	var defn: Dictionary = def(stat_id)
	entry["progress"] = float(entry["progress"]) + scaled
	_dirty = true

	var ceiling: float = cap_ceiling(stat_id)
	var required: float = float(entry["cap"]) * float(defn["need"])
	while float(entry["progress"]) >= required and required > 0.0:
		if float(entry["cap"]) >= ceiling:
			# The rank that would have cost this progress would have passed the
			# ceiling, so neither the rank nor the spend happens.
			break
		entry["progress"] = float(entry["progress"]) - required
		var old_cap: float = entry["cap"]
		var step: float = maxf(0.01, old_cap * float(defn["cap_step"]))
		var gained: float = minf(step, ceiling - old_cap)
		entry["cap"] = old_cap + gained
		_on_cap_grew(stat_id, gained, old_cap)
		required = float(entry["cap"]) * float(defn["need"])
		stat_cap_gained.emit(stat_id, old_cap, float(entry["cap"]))

	stats_changed.emit()


func _on_cap_grew(stat_id: String, gained: float, old_cap: float) -> void:
	var entry: Dictionary = stats[stat_id]
	# A bigger vessel holds more: resources stay topped up to the new ceiling.
	if is_resource(stat_id):
		entry["current"] = minf(float(entry["cap"]), float(entry["current"]) + gained)
	# If the player was running at their maximum, let the setting follow the gain
	# instead of silently falling behind.
	elif is_trainable(stat_id):
		if is_equal_approx(get_allocated(stat_id), old_cap):
			_allocated_set(stat_id, float(entry["cap"]))
	# Constitution is the one stat that feeds another: every rank of BODY widens
	# the HP cap, so physical training shows up as a longer health bar.
	elif stat_id == "body":
		_grow_cap("hp", maxf(0.01, get_cap("hp") * BODY_HP_BONUS))


## Raises one stat's earned cap directly. Used for cross-stat effects, where the
## gain belongs to a stat that was not itself trained.
func _grow_cap(stat_id: String, amount: float) -> void:
	if amount <= 0.0 or not stats.has(stat_id):
		return
	var entry: Dictionary = stats[stat_id]
	var old_cap: float = float(entry["cap"])
	var ceiling: float = cap_ceiling(stat_id)
	entry["cap"] = minf(old_cap + amount, ceiling)
	# The *actual* gain, not the asked-for one: the caller's bookkeeping has to add up to
	# what the cap really did, or a capped stat reports inches it never grew.
	var gained: float = float(entry["cap"]) - old_cap
	if gained <= 0.0:
		return
	_on_cap_grew(stat_id, gained, old_cap)
	stat_cap_gained.emit(stat_id, old_cap, float(entry["cap"]))


## The highest a stat's cap may ever reach. `INF` for everything with no ceiling, which
## is everything except the entries in HARD_CAP.
func cap_ceiling(stat_id: String) -> float:
	return float(HARD_CAP.get(stat_id, INF))


## True when a stat has been trained as far as it goes. Public so the HUD can say the
## reason a number has stopped moving instead of leaving it to be guessed at.
func at_ceiling(stat_id: String) -> bool:
	return get_cap(stat_id) >= cap_ceiling(stat_id)


func _allocated_set(stat_id: String, value: float) -> void:
	var clamped: float = clampf(value, 0.0, get_cap(stat_id))
	allocated[stat_id] = clamped
	allocation_changed.emit(stat_id, clamped)


# --------------------------------------------------------------- spend / heal

## Spends up to `amount` of a resource and returns how much was actually
## available. Meditation uses the return value so a half-empty dantian gives
## half-speed progress instead of silently eating the cost.
func spend(stat_id: String, amount: float) -> float:
	if not is_resource(stat_id) or amount <= 0.0:
		return 0.0
	var entry: Dictionary = stats[stat_id]
	var available: float = float(entry["current"])
	var spent: float = minf(available, amount)
	entry["current"] = available - spent
	if spent > 0.0:
		_dirty = true
	stats_changed.emit()
	return spent


func restore(stat_id: String, amount: float) -> void:
	if not is_resource(stat_id) or amount <= 0.0:
		return
	var entry: Dictionary = stats[stat_id]
	entry["current"] = minf(float(entry["cap"]), float(entry["current"]) + amount)
	_dirty = true
	stats_changed.emit()


func restore_all() -> void:
	for id: String in STAT_ORDER:
		if is_resource(id):
			stats[id]["current"] = stats[id]["cap"]
	stats_changed.emit()
	log_message.emit("Vitality and qi fully restored.", "gain")


## DEFENSE softens incoming damage on a curve that never reaches immunity.
func damage_multiplier() -> float:
	return 100.0 / (100.0 + get_cap("defense"))


## Damage a strike lands. ATTACK is the cap you earned; `gain_coefficient` is
## already the game's single "how far along are you" number, so scaling damage
## by it means a breakthrough makes your fists heavier rather than merely making
## practice more efficient. `skill` is the per-strike variation (a lucky angle).
func strike_damage(skill: float = 1.0) -> float:
	return get_cap("attack") * skill * gain_coefficient


## Applies raw damage, grants the HP/DEFENSE training xp that comes from getting
## hit, and returns the damage that actually landed.
func apply_damage(raw: float) -> float:
	if raw <= 0.0:
		return 0.0
	var dealt: float = raw * damage_multiplier()
	var entry: Dictionary = stats["hp"]
	entry["current"] = maxf(0.0, float(entry["current"]) - dealt)
	var lethal: bool = float(entry["current"]) <= 0.0
	gain("hp", dealt * 2.0)
	gain("defense", dealt * 0.5)
	# Training your endurance must not undo the very blow that trained it. A big
	# hit can push the HP cap over a threshold, and a growing resource cap tops
	# `current` up — which would otherwise revive a body this same call emptied.
	if lethal:
		stats["hp"]["current"] = 0.0
	stats_changed.emit()
	log_message.emit("Took %s damage." % String.num(dealt, 1), "damage")
	return dealt


# --------------------------------------------------------------- allocation

## The HUD sliders call this. Always clamped to what the player has earned.
func set_allocation(stat_id: String, value: float) -> void:
	if not is_trainable(stat_id):
		return
	_allocated_set(stat_id, value)
	stats_changed.emit()


## Equips an aura. Cultivation decides what is allowed to be equipped; this just
## records it and tells the world, so the aura can change the moment you pick it.
func set_chosen_aura(element: String) -> void:
	if element == chosen_aura:
		return
	chosen_aura = element
	_dirty = true
	aura_changed.emit(element)


func max_speed() -> float:
	return get_allocated("speed")


func max_jump_height() -> float:
	return get_allocated("jump")


# ------------------------------------------------------------------- modifiers

## Breakthroughs widen the foundation: every stat's earned cap grows.
func grow_all_caps(fraction: float) -> void:
	for id: String in STAT_ORDER:
		var entry: Dictionary = stats[id]
		var old_cap: float = entry["cap"]
		var ceiling: float = cap_ceiling(id)
		if old_cap >= ceiling:
			# A breakthrough widens the foundation of every stat, but it cannot widen a
			# stat past what the technique can use. Skipped rather than clamped to a
			# zero gain, so the caller's events do not fire with nothing to report.
			continue
		var gained: float = minf(maxf(0.01, old_cap * fraction), ceiling - old_cap)
		entry["cap"] = old_cap + gained
		_on_cap_grew(id, gained, old_cap)
	_dirty = true
	stats_changed.emit()


# ---------------------------------------------------------------- persistence

# ------------------------------------------------------------------ crystals

func add_crystals(amount: int) -> void:
	if amount <= 0:
		return
	crystals += amount
	_dirty = true
	crystals_changed.emit(crystals)


## Spends crystals if there are enough of them, and reports whether the purchase
## went through, so a caller cannot half-buy something.
func spend_crystals(amount: int) -> bool:
	if amount <= 0 or crystals < amount:
		return false
	crystals -= amount
	_dirty = true
	crystals_changed.emit(crystals)
	return true


# ------------------------------------------------------------------ abilities

func has_ability(id: String) -> bool:
	var value: Variant = abilities.get(id, false)
	if typeof(value) == TYPE_BOOL:
		return value
	return float(value) != 0.0


## Grants a named ability. `value` false and true cover the toggles; a number
## covers the counting ones, such as an extra air jump.
func unlock_ability(id: String, value: Variant = true) -> void:
	if abilities.get(id, null) == value:
		return
	abilities[id] = value
	_dirty = true
	ability_unlocked.emit(id)


func air_jumps() -> int:
	return int(abilities.get("air_jumps", 0))


func dash_cooldown() -> float:
	return maxf(0.2, float(abilities.get("dash_cooldown", DEFAULT_ABILITIES["dash_cooldown"])))


func set_ui_scale(value: float) -> void:
	var clamped: float = clampf(value, UI_SCALE_MIN, UI_SCALE_MAX)
	if is_equal_approx(clamped, ui_scale):
		return
	ui_scale = clamped
	_dirty = true
	stats_changed.emit()


## Marks the save as worth writing. Anything that changes state outside `stats`
## (crystals, ability unlocks, task progress) calls this so autosave notices.
func mark_dirty() -> void:
	_dirty = true


func world_position() -> Vector3:
	return saved_position if has_saved_position else Vector3.ZERO


func remember_position(pos: Vector3) -> void:
	saved_position = pos
	has_saved_position = true
	_dirty = true


func save_game() -> bool:
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"gain_coefficient": gain_coefficient,
		"stats": stats,
		"allocated": allocated,
		"position": [saved_position.x, saved_position.y, saved_position.z],
		"has_position": has_saved_position,
		"aura": chosen_aura,
		"crystals": crystals,
		"abilities": abilities,
		"ui_scale": ui_scale,
		"cultivation": {},
	}
	var cultivation: Node = get_node_or_null("/root/Cultivation")
	if cultivation != null and cultivation.has_method("get_save_data"):
		payload["cultivation"] = cultivation.call("get_save_data")
	var quests: Node = get_node_or_null("/root/Quests")
	if quests != null and quests.has_method("save_data"):
		payload["quests"] = quests.call("save_data")

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	_dirty = false
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var raw: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file is not valid JSON; starting fresh.")
		return false
	var data: Dictionary = parsed

	var saved_stats: Variant = data.get("stats", {})
	if typeof(saved_stats) == TYPE_DICTIONARY:
		for id: String in STAT_ORDER:
			if not (saved_stats as Dictionary).has(id):
				continue
			var src: Dictionary = (saved_stats as Dictionary)[id]
			var entry: Dictionary = stats[id]
			# Clamped to the ceiling on the way in as well as on the way up: a save
			# written before a ceiling existed, or edited by hand, would otherwise walk
			# straight past it and the limit would depend on when you last played.
			entry["cap"] = minf(
				maxf(0.01, float(src.get("cap", entry["cap"]))), cap_ceiling(id)
			)
			entry["progress"] = maxf(0.0, float(src.get("progress", 0.0)))
			entry["current"] = clampf(float(src.get("current", entry["cap"])), 0.0, float(entry["cap"]))

	var saved_alloc: Variant = data.get("allocated", {})
	if typeof(saved_alloc) == TYPE_DICTIONARY:
		for id: String in STAT_ORDER:
			if is_trainable(id) and (saved_alloc as Dictionary).has(id):
				allocated[id] = clampf(float((saved_alloc as Dictionary)[id]), 0.0, get_cap(id))
	# Trainables that predate the slider being touched default to the earned cap.
	for id: String in STAT_ORDER:
		if is_trainable(id) and not allocated.has(id):
			allocated[id] = get_cap(id)

	has_saved_position = bool(data.get("has_position", false))
	var saved_pos: Variant = data.get("position", null)
	if typeof(saved_pos) == TYPE_ARRAY and (saved_pos as Array).size() == 3:
		saved_position = Vector3(
			float((saved_pos as Array)[0]),
			float((saved_pos as Array)[1]),
			float((saved_pos as Array)[2])
		)

	chosen_aura = String(data.get("aura", ""))
	crystals = maxi(0, int(data.get("crystals", 0)))

	# Merged over the defaults rather than replaced: a save written before a new
	# unlock existed simply does not mention it, and a missing key has to keep its
	# default instead of becoming an empty ability.
	var saved_abilities: Variant = data.get("abilities", {})
	if typeof(saved_abilities) == TYPE_DICTIONARY:
		for key: String in (saved_abilities as Dictionary):
			abilities[key] = (saved_abilities as Dictionary)[key]
	ui_scale = clampf(float(data.get("ui_scale", ui_scale)), UI_SCALE_MIN, UI_SCALE_MAX)

	var saved_cult: Variant = data.get("cultivation", {})
	if typeof(saved_cult) == TYPE_DICTIONARY:
		_loaded_cultivation = saved_cult
	_cultivation_consumed = false

	var saved_quests: Variant = data.get("quests", {})
	if typeof(saved_quests) == TYPE_DICTIONARY:
		_loaded_quests = saved_quests
	_quests_consumed = false
	stats_changed.emit()
	return true


## Called by Cultivation once, during its own _ready. Returning the payload
## rather than reading the node keeps the load order between the two autoloads
## irrelevant.
func take_loaded_cultivation() -> Dictionary:
	if _cultivation_consumed:
		return {}
	_cultivation_consumed = true
	return _loaded_cultivation


## The same hand-off as `take_loaded_cultivation`, for the task chain. Which of the
## two autoloads readies first is not something either should have to care about.
func take_loaded_quests() -> Dictionary:
	if _quests_consumed:
		return {}
	_quests_consumed = true
	return _loaded_quests


## Wipes progression and deletes the save. Bound to a button in the HUD so the
## loop can be replayed from scratch.
func reset_progress() -> void:
	_build_defaults()
	gain_coefficient = 1.0
	chosen_aura = ""
	crystals = 0
	abilities = DEFAULT_ABILITIES.duplicate(true)
	ui_scale = 0.85
	_loaded_quests = {}
	_quests_consumed = true
	_loaded_cultivation = {}
	_cultivation_consumed = true
	has_saved_position = false
	saved_position = Vector3.ZERO
	_dirty = false
	if FileAccess.file_exists(SAVE_PATH):
		# Remove through the DirAccess handle so this also works in the browser,
		# where user:// is a virtual filesystem backed by IndexedDB.
		var dir: DirAccess = DirAccess.open("user://")
		if dir != null:
			dir.remove(SAVE_PATH.get_file())
	var cultivation: Node = get_node_or_null("/root/Cultivation")
	if cultivation != null and cultivation.has_method("reset"):
		cultivation.call("reset")
	var quests: Node = get_node_or_null("/root/Quests")
	if quests != null and quests.has_method("reset"):
		quests.call("reset")
	crystals_changed.emit(0)
	stats_changed.emit()
	log_message.emit("Progression wiped. A new cultivator awakens.", "info")
