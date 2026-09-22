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

## How badly hurt this body came out of its last beatings, 0..WOUND_MAX. Each one makes the
## next fight worse and heals slower, and none of them goes away on its own.
##
## This is what a death costs, and the shape of the cost is the whole argument. A three-minute
## timer would have been the cheapest penalty to write and the worst to play: three minutes
## of a game like this is eight fights, so the punishment for losing a fight would have been
## to not play for a while. A wound is paid instead — in crystals at a village healer, in a
## pill you carried, or in the five minutes of being worse at the game until you deal with it,
## which is a bill with three ways to settle it rather than a wall you wait in front of.
var wounds: int = 0
## Above this a fourth death would stop being a setback and start being a spiral.
const WOUND_MAX := 3
## Damage taken per wound: a third more at three of them.
const WOUND_DAMAGE_PER_STACK := 0.11
## Regeneration taken away per wound, as a share of the plain rate.
const WOUND_REGEN_SHARE := 0.22

var abilities: Dictionary = DEFAULT_ABILITIES.duplicate(true)

## Scale applied to the whole interface, chosen in the settings panel. Fullscreen on
## a large monitor makes the default HUD look oversized, so the size is the player's
## call rather than a constant.
var ui_scale: float = 0.85
const UI_SCALE_MIN := 0.6
const UI_SCALE_MAX := 1.3

const SAVE_PATH := "user://disantia_save.json"
## Where the suite writes instead, whenever it is running.
##
## The self-test autosaves as it goes — that is exactly what makes a save round trip worth
## checking — and it does so against whatever the running game's save path is. Which meant that a
## suite killed half way through (a timeout, a Ctrl-C, a crash on floor sixty) left the *player's*
## save holding the suite's state: a clock at ten at night, a purse the tests had topped up, a
## body standing where a measurement had put it. Backing the file up and putting it back at the
## end only helps if the run reaches the end, and a run that is killed is the run that matters.
##
## One string, and the whole class of accident is gone: under `--selftest` the game simply has a
## different save file.
const SELFTEST_SAVE_PATH := "user://disantia_selftest_run.json"


## The file this process reads and writes. See `SELFTEST_SAVE_PATH`.
func save_path() -> String:
	return SELFTEST_SAVE_PATH if OS.get_cmdline_user_args().has("--selftest") else SAVE_PATH
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
var _loaded_shop: Dictionary = {}
var _shop_consumed: bool = false
var _loaded_wards: Dictionary = {}
var _wards_consumed: bool = false

## Every autoload added after the four above keeps its own progress, and this is the one list
## of them.
##
## The older four each got their own block in *three* places — written, read, and handed off
## during their own `_ready` — which is twelve lines of the save file's business per new
## system, and a thing to forget. A module that follows the contract (`save_data()`, and a
## `_ready` that opens with `PlayerData.take_loaded_module(key)`) is now saved and restored
## without this file knowing what it holds. Keyed by save key, valued by the autoload's path.
const SAVE_MODULES: Dictionary = {
	"villages": "/root/Villages",
	"law": "/root/Law",
	# `sky` is the save file's own name for the clock, kept because the key is what an existing
	# save was written under — renaming it here would silently drop the hour of every save in
	# the wild. The *path* is what has to be right, and it was not: the autoload was renamed to
	# Clock (Godot already has a `Sky` type) and this line went on pointing at a node that never
	# existed, so no save ever restored the time of day.
	"sky": "/root/Clock",
	"tower": "/root/Tower",
	"forge": "/root/Forge",
	"bounties": "/root/Bounties",
	"raids": "/root/Raids",
	"loc": "/root/Loc",
}
var _loaded_modules: Dictionary = {}
var _modules_consumed: Dictionary = {}


func _ready() -> void:
	_build_defaults()
	if not load_game():
		log_message.emit("A new cultivator awakens.", "info")
	# After the load, so a save arrives with its attainments already in force and does not
	# announce the whole table on the first frame of play.
	_recheck_attainments()
	stat_cap_gained.connect(_on_cap_moved)
	stats_changed.connect(_recheck_attainments)


## A cap moved, which is the only event an attainment cares about. Declared with the signal's
## own arguments rather than connected to the no-argument version, so the wiring says what it
## is reacting to instead of relying on Godot dropping arguments.
func _on_cap_moved(_stat_id: String, _old_cap: float, _new_cap: float) -> void:
	_recheck_attainments()
	# Keep ticking while the window is unfocused so autosave stays predictable.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Browsers give no reliable "about to close" event, so losing focus counts as
## a checkpoint too. user:// is backed by IndexedDB in the web build.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _dirty:
			save_game()


## True while the body is inside the tower, where nothing gives anything back.
##
## Asked by node path rather than read off the autoload identifier, so a project that ever drops
## the tower still loads its saves. The rule it carries is the whole design of the climb: no
## trance, no mending, no qi — so the only health on floor sixty is the health carried up, and
## depth becomes a resource instead of a distance.
func in_tower() -> bool:
	var tower: Node = get_node_or_null("/root/Tower")
	return tower != null and bool(tower.call("inside"))


func _process(delta: float) -> void:
	# The clock behind Mending. Nothing else in the file counts up; everything else counts
	# down from a deadline.
	_since_hurt += delta
	if in_tower():
		_autosave(delta)
		return
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
		# Mending is the one rate an attainment changes, and only while nothing has hit you.
		var rate: float = float(RESOURCE_REGEN[id])
		if id == "hp":
			rate *= regen_multiplier()
		# A charm speeds the breath, a wound slows everything. Applied here rather than
		# folded into either multiplier because this loop is the only place either rate is
		# actually used, and a modifier that lives at the point of use cannot be forgotten
		# by a caller that reads the multiplier for the panel.
		rate *= gear_regen_share(id) * wound_regen_multiplier()
		entry["current"] = minf(cap, float(entry["current"]) + cap * rate * delta)
	_autosave(delta)


## Kept separate because the tower returns before the regeneration loop and a run that skipped
## the autosave would lose an hour of climbing to a crash.
func _autosave(delta: float) -> void:
	_autosave_accum += delta
	if _autosave_accum < AUTOSAVE_SECONDS:
		return
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

## True when a stat id is one this file knows about.
##
## Public because half the world hands out cap grants by id — a site's boon, a champion's
## reward, a ware on the elder's shelf — and the guard for an id that does not exist belongs
## next to the table that defines them rather than at every call site. Every one of those call
## sites used to ask `PlayerData.has(...)`, which is not a function on a Node: the call failed
## and took the rest of the method with it, silently, on the day the site was first found.
func has_stat(stat_id: String) -> bool:
	return stats.has(stat_id)


# ---------------------------------------------------------------- attainments

## What a stat *becomes*.
##
## The problem these solve is that a stat was only ever a bigger number. ATTACK 22 was not a
## thing you had, it was a quantity you had accumulated: nobody could have said what the
## difference between 22 and 23 was, and there was no moment anywhere in the game where a
## stat turned into a capability. Training was a slope, and a slope has no events on it.
##
## So every stat has thresholds, and crossing one gives the body something *qualitative* — an
## effect that changes how it plays rather than how much it is worth. The thresholds are
## multiples of the stat's own base cap, so "four times your starting strength" means the
## same thing for a pool of qi and for a fist, and a table entry never has to be rewritten
## when a base value is retuned.
##
## They are derived rather than granted. Nothing is written down, nothing can be lost, and a
## save cannot be wrong about them: `attainment_index` is asked of the caps themselves every
## time a cap moves. A granted flag would need a save field, a migration, and a way to be
## wrong — and the one thing this file must never do is hand out a capability it cannot take
## back.
const ATTAINMENTS: Dictionary = {
	"attack": [
		{
			"cap": 4.0, "label": "Cleave", "effect": "cleave",
			"blurb": "A blow carries: a second body within 2.2 m takes 40% of it.",
		},
		{
			"cap": 10.0, "label": "Crushing", "effect": "crush",
			"blurb": "One blow in five lands crushing, for double.",
		},
	],
	"hp": [
		{
			"cap": 3.0, "label": "Mending", "effect": "mending",
			"blurb": "Out of a fight, wounds close three times as fast.",
		},
		{
			"cap": 8.0, "label": "Second Wind", "effect": "second_wind",
			"blurb": "Once every ninety seconds, a killing blow leaves you standing at a quarter.",
		},
	],
	"defense": [
		{
			"cap": 3.0, "label": "Unshaken", "effect": "unshaken",
			"blurb": "Blows no longer move you.",
		},
		{
			"cap": 8.0, "label": "Warded", "effect": "warded",
			"blurb": "Some of every blow you take is given back to the one who threw it.",
		},
	],
	"speed": [
		{
			"cap": 2.5, "label": "Surefoot", "effect": "surefoot",
			"blurb": "Steeper ground stays runnable, and you are an eighth quicker than training alone.",
		},
		{
			"cap": 6.0, "label": "Burst", "effect": "burst",
			"blurb": "The first three quarters of a second of a sprint is a third faster.",
		},
	],
	"jump": [
		{
			"cap": 4.0, "label": "Softfoot", "effect": "softfoot",
			"blurb": "Falls hurt half as much and the safe drop is two metres deeper.",
		},
		{
			"cap": 10.0, "label": "Meteor", "effect": "meteor",
			"blurb": "A landing from six metres staggers everything within three and a half.",
		},
	],
	"qi": [
		{
			"cap": 2.5, "label": "Qi Bolt", "effect": "qi_bolt",
			"blurb": "R throws a ball of your own aura at what you are looking at, for a "
				+ "twentieth of the dantian.",
		},
		{
			"cap": 3.0, "label": "Deep Well", "effect": "deep_well",
			"blurb": "Qi Pressure costs a third less to hold.",
		},
		{
			"cap": 4.0, "label": "Cloud Step", "effect": "flight",
			"blurb": "Hold jump in the air and walk on it. It is paid for the whole time.",
		},
		{
			"cap": 8.0, "label": "Jade Skin", "effect": "jade_skin",
			"blurb": "A shell of qi eats one blow every eighteen seconds, out of the dantian.",
		},
	],
	"body": [
		{
			"cap": 2.0, "label": "Thick Skin", "effect": "thick_skin",
			"blurb": "Blows land eight per cent softer on a body that has been through a few.",
		},
		{
			"cap": 5.0, "label": "Iron Bones", "effect": "iron_bones",
			"blurb": "You get up twice as fast and do not slide half as far.",
		},
	],
}

## The ones that need *two* stats, which is where a build comes from.
##
## A single stat has a rank; two stats together have a discipline. That distinction is the
## whole point of them: these are the only entries in the game that ask the player to have
## trained in a *direction* rather than to have trained a lot. A body built on constitution
## and defence is a wall, one built on health and attack is a berserker, and there is no
## reason to build either except that you want it. Requirements are again multiples of the
## base caps.
const SYNERGIES: Array = [
	{
		"id": "iron_skin", "label": "Iron Skin", "effect": "iron_skin",
		"needs": {"defense": 3.0, "body": 3.0},
		"blurb": "A trained hide over a trained frame: another twelve per cent off every blow.",
	},
	{
		"id": "sky_step", "label": "Sky Step", "effect": "sky_step",
		"needs": {"jump": 4.0, "speed": 4.0},
		"blurb": "One more jump in the air than training alone would allow.",
	},
	{
		"id": "blood_boil", "label": "Blood Boil", "effect": "blood_boil",
		"needs": {"hp": 3.0, "attack": 3.0},
		"blurb": "Below a third of your health, your blows land a quarter harder.",
	},
	{
		"id": "dantian_bell", "label": "Dantian Bell", "effect": "dantian_bell",
		"needs": {"qi": 3.0, "defense": 3.0},
		"blurb": "A deep well behind a hard wall: the jade shell comes back twice as fast.",
	},
]

## How much harder Warded gives a blow back, what a jade shell costs of the pool, and how
## long each timed attainment takes to come back.
const WARDED_REFLECT := 0.15
const JADE_COST_SHARE := 0.12
const JADE_RECHARGE := 18.0
const SECOND_WIND_RECHARGE := 90.0
## The fraction of the pool Blood Boil starts at.
const BLOOD_BOIL_SHARE := 0.35
## Seconds a blow has to be absent before wounds close at the mending rate.
const MENDING_QUIET := 5.0

## The effects in force, by key. Rebuilt when a cap moves rather than read from the tables on
## every question: the controller, the striker and the pressure field all ask "do I have
## this" every frame, and walking seven tables to answer it is the kind of cost that never
## shows up in a profile and never stops either.
var _attained: Dictionary = {}

## Seconds since the last blow or fall. Mending is the one attainment that is a *state*
## rather than a modifier: it is about what is not currently happening to you.
var _since_hurt: float = 0.0
## Engine milliseconds at which each timed attainment is available again. A deadline rather
## than a countdown, so nothing has to tick them down.
var _shield_ready_ms: int = 0
var _wind_ready_ms: int = 0


## Every attainment in the game in one flat list, for the panel that shows them: the two per
## stat in stat order, then the disciplines. Each row knows whether it is attained and what
## it is short of when it is not, so the interface never re-derives either.
func attainment_rows() -> Array:
	var rows: Array = []
	for stat_id: String in STAT_ORDER:
		for entry: Dictionary in ATTAINMENTS.get(stat_id, []):
			var want: float = threshold(stat_id, entry)
			var have: float = get_cap(stat_id)
			rows.append({
				"kind": "stat",
				"stat": stat_id,
				"label": String(entry["label"]),
				"blurb": String(entry["blurb"]),
				"color": color(stat_id),
				"attained": have >= want,
				"need": "%s %s" % [label(stat_id), format_value(stat_id, want)],
				"have": "%s %s" % [label(stat_id), format_value(stat_id, have)],
				"missing": maxf(0.0, want - have),
			})
	for entry: Dictionary in SYNERGIES:
		var met: bool = true
		var needs: Array = []
		for stat_id: String in (entry["needs"] as Dictionary):
			var want: float = threshold(stat_id, {"cap": float(entry["needs"][stat_id])})
			needs.append("%s %s" % [label(stat_id), format_value(stat_id, want)])
			if get_cap(stat_id) < want:
				met = false
		rows.append({
			"kind": "synergy",
			"stat": "",
			"label": String(entry["label"]),
			"blurb": String(entry["blurb"]),
			"color": Color("ffd76e"),
			"attained": met,
			"need": ", ".join(needs),
			"have": "",
			"missing": 0.0,
		})
	return rows


func attained_count() -> int:
	var total: int = 0
	for row: Dictionary in attainment_rows():
		if bool(row["attained"]):
			total += 1
	return total


func attainment_total() -> int:
	var total: int = 0
	for stat_id: String in STAT_ORDER:
		total += (ATTAINMENTS.get(stat_id, []) as Array).size()
	return total + SYNERGIES.size()


## Every effect key any table grants, in table order and once each.
##
## Walked out of the tables rather than kept as a second list beside them, because a list of
## the effects is one more thing that can disagree with the effects — and the only question
## anyone asks this is "is this key real", which is a question the tables can answer. The
## suite is the caller: it compares these keys against the ones its checks exercise, so an
## entry nothing ever fires for cannot hide behind a panel that lists it as held.
func all_effect_keys() -> Array:
	var keys: Array = []
	for stat_id: String in STAT_ORDER:
		for entry: Dictionary in ATTAINMENTS.get(stat_id, []):
			var key: String = String(entry["effect"])
			if not keys.has(key):
				keys.append(key)
	for entry: Dictionary in SYNERGIES:
		var key: String = String(entry["effect"])
		if not keys.has(key):
			keys.append(key)
	return keys


## The cap a threshold stands for, in the stat's own units.
func threshold(stat_id: String, entry: Dictionary) -> float:
	return maxf(0.001, float(def(stat_id).get("base_cap", 1.0))) * float(entry.get("cap", 0.0))


## How many of a stat's thresholds are behind it.
func attainment_index(stat_id: String) -> int:
	var count: int = 0
	for entry: Dictionary in ATTAINMENTS.get(stat_id, []):
		if get_cap(stat_id) >= threshold(stat_id, entry):
			count += 1
	return count


## The name of the last thing a stat became, or empty while it is still only a number.
func attainment_label(stat_id: String) -> String:
	var passed: int = attainment_index(stat_id)
	if passed <= 0:
		return ""
	return String((ATTAINMENTS[stat_id] as Array)[passed - 1]["label"])


## The next thing a stat would become, with the absolute threshold already resolved — so the
## HUD, the tooltip and the panel all print the same number instead of three arithmetic
## expressions that agree until one of them is edited. Empty once the table runs out.
func next_attainment(stat_id: String) -> Dictionary:
	var list: Array = ATTAINMENTS.get(stat_id, [])
	var passed: int = attainment_index(stat_id)
	if passed >= list.size():
		return {}
	var entry: Dictionary = list[passed]
	var want: float = threshold(stat_id, entry)
	var have: float = get_cap(stat_id)
	return {
		"label": String(entry["label"]),
		"blurb": String(entry["blurb"]),
		"threshold": want,
		"missing": maxf(0.0, want - have),
		"progress": clampf(have / maxf(0.001, want), 0.0, 1.0),
	}


## True when a named effect is in force. The one question the rest of the game asks.
func has_effect(key: String) -> bool:
	return _attained.has(key)


## Rebuilds the effect set out of the caps, and says so when something new turns up.
##
## Connected to the caps themselves rather than to any of the four paths that can move one —
## training, a breakthrough, a site, the elder's shelf — because a fifth path added later is
## exactly how a derived table comes to disagree with the thing it is derived from.
func _recheck_attainments() -> void:
	var before: Dictionary = _attained
	var now: Dictionary = {}
	for stat_id: String in STAT_ORDER:
		for i in attainment_index(stat_id):
			now[String((ATTAINMENTS[stat_id] as Array)[i]["effect"])] = true
	for entry: Dictionary in SYNERGIES:
		var met: bool = true
		for stat_id: String in (entry["needs"] as Dictionary):
			if get_cap(stat_id) < threshold(stat_id, {"cap": float(entry["needs"][stat_id])}):
				met = false
				break
		if met:
			now[String(entry["effect"])] = true
	_attained = now
	for key: String in now:
		if not before.has(key):
			_announce_effect(key)


## A named thing is announced, and it comes with the line that says what it does. A
## capability that arrives silently is a capability the player will never know they have —
## which is the failure mode of every "invisible stat bonus" ever shipped.
func _announce_effect(key: String) -> void:
	var stat_id: String = ""
	var blurb: String = ""
	var headline: String = ""
	for id: String in STAT_ORDER:
		for entry: Dictionary in ATTAINMENTS.get(id, []):
			if String(entry["effect"]) == key:
				stat_id = id
				blurb = String(entry["blurb"])
				headline = String(entry["label"])
	var discipline: bool = stat_id == ""
	if discipline:
		for entry: Dictionary in SYNERGIES:
			if String(entry["effect"]) == key:
				blurb = String(entry["blurb"])
				headline = String(entry["label"])
	if headline == "":
		return
	log_message.emit(
		"%s — %s%s" % [
			headline.to_upper(), blurb,
			"" if discipline else "  (%s reached it)" % label(stat_id),
		],
		"breakthrough"
	)
	Audio.play("breakthrough", -3.0)


# --------------------------------------------------- the effects, as numbers

## A blow that carries: what fraction of it lands on a second body, and how far that body
## can be. Zero when the attainment is not held, so the striker multiplies rather than
## testing tables.
func cleave_fraction() -> float:
	return 0.4 if has_effect("cleave") else 0.0


func cleave_radius() -> float:
	return 2.2


## Chance that any one blow lands crushing.
func crush_chance() -> float:
	return 0.2 if has_effect("crush") else 0.0


## The multiplier on damage taken from a body. DEFENSE's own curve is applied by the caller,
## because this is the part that changes and that one does not.
func melee_multiplier() -> float:
	var out: float = 1.0
	if has_effect("thick_skin"):
		out *= 0.92
	if has_effect("iron_skin"):
		out *= 0.88
	return out


## How far a blow throws the body. Zero once a body has stopped being moved by hands.
func knockback_multiplier() -> float:
	var out: float = 1.0
	if has_effect("unshaken"):
		out = 0.0
	if has_effect("iron_bones"):
		out *= 0.5
	return out


## Health per second as a multiple of the plain rule. Mending only applies while nothing has
## hit you for a few seconds, which is what makes it a reward for leaving a fight rather
## than a reason to stand still inside one.
func regen_multiplier() -> float:
	return 3.0 if has_effect("mending") and _since_hurt >= MENDING_QUIET else 1.0


## What the rate would be if the quiet had been earned. For the panel, which has to be able
## to say what the attainment is worth without waiting five seconds to be hit less.
func repair_multiplier() -> float:
	return 3.0 if has_effect("mending") else 1.0


func seconds_since_hurt() -> float:
	return _since_hurt


## The damage a blow is dealt as a multiple of the plain rule. Blood Boil reads the pool
## rather than a flag: it is the one attainment that is switched on by being hurt.
func damage_multiplier_now() -> float:
	if not has_effect("blood_boil"):
		return 1.0
	var cap: float = get_cap("hp")
	if cap <= 0.0:
		return 1.0
	return 1.25 if get_value("hp") / cap <= BLOOD_BOIL_SHARE else 1.0


func fall_multiplier() -> float:
	return 0.5 if has_effect("softfoot") else 1.0


func safe_fall_bonus() -> float:
	return 2.0 if has_effect("softfoot") else 0.0


## The multiplier on the run. Surefoot is why the number beside SPEED is not quite the speed
## the body moves at: the training is the training, and this is what the body does with it.
func speed_multiplier() -> float:
	return 1.08 if has_effect("surefoot") else 1.0


func climb_bonus_degrees() -> float:
	return 15.0 if has_effect("surefoot") else 0.0


func sprint_burst_multiplier() -> float:
	return 1.3 if has_effect("burst") else 1.0


func sprint_burst_seconds() -> float:
	return 0.75 if has_effect("burst") else 0.0


## What the qi pressure costs, as a multiple of the plain drain.
func pressure_multiplier() -> float:
	return 0.65 if has_effect("deep_well") else 1.0


## The jade shell: whether it is up, what raising it costs, and how long until it returns.
func shield_ready() -> bool:
	return has_effect("jade_skin") and Time.get_ticks_msec() >= _shield_ready_ms


func shield_cost() -> float:
	return get_cap("qi") * JADE_COST_SHARE


func shield_recharge_seconds() -> float:
	return JADE_RECHARGE * (0.5 if has_effect("dantian_bell") else 1.0)


func second_wind_ready() -> bool:
	return has_effect("second_wind") and Time.get_ticks_msec() >= _wind_ready_ms


## One more jump in the air than the training alone allows. Added here rather than in the
## controller so the ability ceiling and its bonus sit in the same file as the table that
## grants it — and so `air_jumps()` stays the single answer to "how many jumps do I have".
func air_jump_bonus() -> int:
	return 1 if has_effect("sky_step") else 0


## A soft landing: the fall that shakes the ground, and how far the shake reaches.
func stagger_radius() -> float:
	return 3.5 if has_effect("meteor") else 0.0


func stagger_min_fall() -> float:
	return 6.0


## How long a collapsed body stays down, as a multiple of the plain rule.
func downed_multiplier() -> float:
	return 0.5 if has_effect("iron_bones") else 1.0


func reflect_fraction() -> float:
	return WARDED_REFLECT if has_effect("warded") else 0.0


## A blow as it actually lands, the crushing roll included. The striker asks for this rather
## than for `strike_damage` so the roll lives next to the table that grants it — and so the
## suite can measure a mean over a thousand swings instead of hoping to see a crit.
func strike_damage_rolled(rng: RandomNumberGenerator) -> float:
	var base: float = strike_damage(rng.randf_range(0.85, 1.15)) * damage_multiplier_now()
	if crush_chance() > 0.0 and rng.randf() < crush_chance():
		return base * 2.0
	return base


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


## Raises a stat's earned cap from somewhere other than training — a site you found, or
## something bought with crystals. Returns what it actually granted, which is not the
## amount asked for when the stat is already at its ceiling, so a caller cannot report a
## gift that was silently refused.
func grant_cap(stat_id: String, amount: float) -> float:
	if amount <= 0.0 or not stats.has(stat_id):
		return 0.0
	var before: float = get_cap(stat_id)
	_grow_cap(stat_id, amount)
	_dirty = true
	return get_cap(stat_id) - before


## Sites already found, by id. A list rather than a counter: a counter would pay out the
## wrong sites the first time the list of sites changes, which is exactly the sort of
## thing a save file is not allowed to get wrong.
var found_landmarks: Array = []


func mark_landmark_found(id: String) -> void:
	if id == "" or found_landmarks.has(id):
		return
	found_landmarks.append(id)
	_dirty = true


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
	return get_cap("attack") * skill * gain_coefficient * strike_share()


## Applies raw damage, grants the HP/DEFENSE training xp that comes from getting
## hit, and returns the damage that actually landed.
## `kind` is "blow" for anything a body did to you and "fall" for the ground. The
## distinction is not flavour: the physical attainments are about being *struck*, and a
## trained hide does not help against a cliff.
func apply_damage(raw: float, kind: String = "blow") -> float:
	if raw <= 0.0:
		return 0.0
	_since_hurt = 0.0
	var melee: bool = kind == "blow"
	# The jade shell, before anything else: a blow it takes is a blow that did not land, so
	# it grants no HP or DEFENSE training either — the shell is what a cultivator spends qi
	# *instead* of blood.
	if melee and shield_ready():
		var price: float = shield_cost()
		if get_value("qi") >= price:
			spend("qi", price)
			_shield_ready_ms = Time.get_ticks_msec() + int(shield_recharge_seconds() * 1000.0)
			log_message.emit(
				"The jade shell takes it. Back in %.0fs." % shield_recharge_seconds(), "info"
		)
			Audio.play("ui_toggle", -6.0, 0.8)
			return 0.0
	var dealt: float = raw * damage_multiplier() * incoming_share()
	if melee:
		dealt *= melee_multiplier()
	var entry: Dictionary = stats["hp"]
	entry["current"] = maxf(0.0, float(entry["current"]) - dealt)
	var lethal: bool = float(entry["current"]) <= 0.0
	# Second Wind, on the blow that would have ended it. Checked before the training below,
	# because a body that is going to get up is a body that did not go down.
	if lethal and second_wind_ready():
		entry["current"] = float(entry["cap"]) * 0.25
		_wind_ready_ms = Time.get_ticks_msec() + int(SECOND_WIND_RECHARGE * 1000.0)
		log_message.emit(
			"SECOND WIND — you are still standing, at a quarter. Once every %.0fs."
			% SECOND_WIND_RECHARGE,
			"breakthrough"
		)
		Audio.play("breakthrough", -3.0)
		stats_changed.emit()
		return dealt
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


## Jumps allowed after leaving the ground: what the elder's chain and the shelf have granted,
## plus whatever a discipline adds on top. One answer to the question, so the controller, the
## HUD and the settings panel cannot disagree about how many jumps the body has.
func air_jumps() -> int:
	return int(abilities.get("air_jumps", 0)) + air_jump_bonus()


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


# ------------------------------------------------------------------- decisions

## What the body has decided: decision id -> `{"key": the option taken, "subject": what it
## was about, or ""}`.
##
## Kept here rather than in the file that writes the conversations, because it is the one
## kind of state that must never be recomputed: a decision is not derived from anything, so
## nothing can rebuild it, and a save that loses it silently reopens a door the player
## walked through. The story autoload reads and writes it; this file only remembers it.
##
## The subject is what lets a decision be re-applied to a world that is rebuilt from scratch
## every launch: "burn" says nothing on its own, and "burn Bandit Hollow" is a fact the
## camps can act on before the first frame.
var decisions: Dictionary = {}


## Records a decision. Written before its effect is applied, so a decision whose effect
## cannot be given is still a decision rather than a conversation that repeats forever.
func note_decision(id: String, key: String, subject: String = "") -> void:
	if id == "" or key == "":
		return
	decisions[id] = {"key": key, "subject": subject}
	_dirty = true


## The option taken on a decision, or "" while it is still open.
func chosen_option(id: String) -> String:
	var entry: Variant = decisions.get(id, {})
	if typeof(entry) == TYPE_DICTIONARY:
		return String((entry as Dictionary).get("key", ""))
	# Written before decisions carried a subject; a plain string is a valid answer.
	return String(entry)


## What the decision was about, or "". Used by the world to re-apply it to a fresh one.
func decision_subject(id: String) -> String:
	var entry: Variant = decisions.get(id, {})
	if typeof(entry) == TYPE_DICTIONARY:
		return String((entry as Dictionary).get("subject", ""))
	return ""


func world_position() -> Vector3:
	return saved_position if has_saved_position else Vector3.ZERO


func remember_position(pos: Vector3) -> void:
	saved_position = pos
	has_saved_position = true
	_dirty = true


# ---------------------------------------------------------------- wounds and gear

## One more wound, up to the cap. Returns whether it took, so a caller can tell a death that
## cost something from one that did not.
func add_wound() -> bool:
	if wounds >= WOUND_MAX:
		return false
	wounds += 1
	_dirty = true
	log_message.emit(
		"WOUNDED ×%d — blows land %d%% harder, the body mends %d%% slower. A healer, a pill, "
			% [wounds, int((wound_damage_multiplier() - 1.0) * 100.0),
				int((1.0 - wound_regen_multiplier()) * 100.0)]
			+ "or a spell at a spirit zone closes it.",
		"damage"
	)
	stats_changed.emit()
	return true


func clear_wound() -> bool:
	if wounds <= 0:
		return false
	wounds -= 1
	_dirty = true
	log_message.emit(
		"A wound closes.%s" % ("" if wounds == 0 else " %d still open." % wounds), "gain"
	)
	stats_changed.emit()
	return true


func clear_wounds() -> void:
	if wounds <= 0:
		return
	wounds = 0
	_dirty = true
	stats_changed.emit()


func wounded() -> bool:
	return wounds > 0


func wound_damage_multiplier() -> float:
	return 1.0 + WOUND_DAMAGE_PER_STACK * float(wounds)


func wound_regen_multiplier() -> float:
	return clampf(1.0 - WOUND_REGEN_SHARE * float(wounds), 0.2, 1.0)


## The Forge, if the world has one. Gear is worn as a *share of the body's own numbers*, so
## the body is the one doing the multiplying — which is what stops a sword from ever making
## the training yard pointless. `null` before the autoload exists, and every caller below
## treats that as "nothing worn".
func _forge() -> Node:
	return get_node_or_null("/root/Forge")


## What this body's blows are multiplied by, weapons and elixirs together.
func strike_share() -> float:
	var forge: Node = _forge()
	if forge == null or not forge.has_method("strike_multiplier"):
		return 1.0
	return float(forge.call("strike_multiplier")) * float(forge.call("attack_tonic"))


## And what arriving blows are multiplied by: armour, wards and the state of the body.
func incoming_share() -> float:
	var forge: Node = _forge()
	var gear: float = 1.0
	if forge != null and forge.has_method("damage_taken_multiplier"):
		gear = float(forge.call("damage_taken_multiplier")) * float(forge.call("ward_tonic"))
	return gear * wound_damage_multiplier()


func gear_regen_share(stat_id: String) -> float:
	var forge: Node = _forge()
	if forge == null or not forge.has_method("regen_multiplier_for"):
		return 1.0
	return float(forge.call("regen_multiplier_for", stat_id))


func save_game() -> bool:
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"wounds": wounds,
		"gain_coefficient": gain_coefficient,
		"stats": stats,
		"allocated": allocated,
		"position": [saved_position.x, saved_position.y, saved_position.z],
		"has_position": has_saved_position,
		"aura": chosen_aura,
		"crystals": crystals,
		"abilities": abilities,
		"ui_scale": ui_scale,
		"landmarks": found_landmarks,
		"decisions": decisions,
		"cultivation": {},
	}
	var cultivation: Node = get_node_or_null("/root/Cultivation")
	if cultivation != null and cultivation.has_method("get_save_data"):
		payload["cultivation"] = cultivation.call("get_save_data")
	var quests: Node = get_node_or_null("/root/Quests")
	if quests != null and quests.has_method("save_data"):
		payload["quests"] = quests.call("save_data")
	var shop: Node = get_node_or_null("/root/Shop")
	if shop != null and shop.has_method("save_data"):
		payload["shop"] = shop.call("save_data")
	var wards: Node = get_node_or_null("/root/Wards")
	if wards != null and wards.has_method("save_data"):
		payload["wards"] = wards.call("save_data")
	for key: String in SAVE_MODULES:
		var module: Node = get_node_or_null(String(SAVE_MODULES[key]))
		if module != null and module.has_method("save_data"):
			payload[key] = module.call("save_data")

	var file: FileAccess = FileAccess.open(save_path(), FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	_dirty = false
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(save_path()):
		return false
	var file: FileAccess = FileAccess.open(save_path(), FileAccess.READ)
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
	decisions.clear()
	var saved_decisions: Variant = data.get("decisions", {})
	if typeof(saved_decisions) == TYPE_DICTIONARY:
		for id: String in (saved_decisions as Dictionary):
			var value: Variant = (saved_decisions as Dictionary)[id]
			if typeof(value) == TYPE_DICTIONARY:
				decisions[id] = {
					"key": String((value as Dictionary).get("key", "")),
					"subject": String((value as Dictionary).get("subject", "")),
				}
			else:
				decisions[id] = {"key": String(value), "subject": ""}
	found_landmarks.clear()
	var saved_landmarks: Variant = data.get("landmarks", [])
	if typeof(saved_landmarks) == TYPE_ARRAY:
		for entry: Variant in saved_landmarks:
			found_landmarks.append(String(entry))

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

	var saved_shop: Variant = data.get("shop", {})
	if typeof(saved_shop) == TYPE_DICTIONARY:
		_loaded_shop = saved_shop
	_shop_consumed = false

	var saved_wards: Variant = data.get("wards", {})
	if typeof(saved_wards) == TYPE_DICTIONARY:
		_loaded_wards = saved_wards
	_wards_consumed = false

	wounds = clampi(int(data.get("wounds", 0)), 0, WOUND_MAX)

	_loaded_modules.clear()
	_modules_consumed.clear()
	for key: String in SAVE_MODULES:
		var saved_module: Variant = data.get(key, {})
		if typeof(saved_module) == TYPE_DICTIONARY:
			_loaded_modules[key] = saved_module
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


## And again for the shop's purchase counts — a save that forgets them hands out the
## first rank of every ware at the starting price all over again.
func take_loaded_shop() -> Dictionary:
	if _shop_consumed:
		return {}
	_shop_consumed = true
	return _loaded_shop


## And the wards: a save that forgets which walls were crossed would put the player back
## inside a ward their realm says is open, which is the one piece of progress that costs
## real minutes to re-earn.
func take_loaded_wards() -> Dictionary:
	if _wards_consumed:
		return {}
	_wards_consumed = true
	return _loaded_wards


## The same hand-off, for anything added later. Taken once, by the module itself, during its
## own `_ready` — the order the autoloads ready in is not something either side should have to
## know about.
func take_loaded_module(key: String) -> Dictionary:
	if bool(_modules_consumed.get(key, false)):
		return {}
	_modules_consumed[key] = true
	return _loaded_modules.get(key, {})


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
	_loaded_shop = {}
	_shop_consumed = true
	_loaded_wards = {}
	_wards_consumed = true
	_loaded_cultivation = {}
	_cultivation_consumed = true
	_loaded_modules.clear()
	_modules_consumed.clear()
	wounds = 0
	has_saved_position = false
	saved_position = Vector3.ZERO
	_dirty = false
	if FileAccess.file_exists(save_path()):
		# Remove through the DirAccess handle so this also works in the browser,
		# where user:// is a virtual filesystem backed by IndexedDB.
		var dir: DirAccess = DirAccess.open("user://")
		if dir != null:
			dir.remove(save_path().get_file())
	var cultivation: Node = get_node_or_null("/root/Cultivation")
	if cultivation != null and cultivation.has_method("reset"):
		cultivation.call("reset")
	var quests: Node = get_node_or_null("/root/Quests")
	if quests != null and quests.has_method("reset"):
		quests.call("reset")
	var shop: Node = get_node_or_null("/root/Shop")
	if shop != null and shop.has_method("reset"):
		shop.call("reset")
	var wards: Node = get_node_or_null("/root/Wards")
	if wards != null and wards.has_method("reset"):
		wards.call("reset")
	crystals_changed.emit(0)
	stats_changed.emit()
	log_message.emit("Progression wiped. A new cultivator awakens.", "info")
