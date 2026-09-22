extends Node
## Autoload. The path of cultivation: meditation, refinement, and breakthroughs.
##
## The loop
## --------
##   MEDITATE (hold C) drains QI and fills two meters at once:
##     * the REFINEMENT cycle, which on each completion grants +1 refinement.
##       Every refinement adds COEFF_PER_REFINEMENT to the global gain
##       coefficient, so simply sitting down and cultivating makes *every*
##       action in the world pay out more. This is the "a little more stats per
##       action" knob the whole progression is built around.
##     * the INSIGHT meter, which fills more slowly and, once full, stays full.
##       Holding a full insight meter is what lets you break through.
##
##   BREAKTHROUGH (press B) consumes the insight meter and +1 tier: a large
##   coefficient jump, a permanent widening of every stat cap, and a full
##   restore. Nine tiers make a realm; crossing a realm boundary widens the
##   foundation much further.
##
##   gain_coefficient = 1.0 + 0.03 * refinement + 0.15 * tier
##
## Because PlayerData.gain() multiplies by that coefficient, the same amount of
## running, jumping and getting hit yields more stats the further you walk the
## path. Every timing constant below is exported as a plain const so the pacing
## can be tuned in one place.

signal cultivation_changed
signal breakthrough_performed(tier: int, realm: String)
signal realm_advanced(realm_index: int, realm: String)
signal meditation_started
signal meditation_stopped
signal log_message(text: String, kind: String)

const REALMS: Array = [
	"Body Tempering",
	"Qi Condensation",
	"Foundation Establishment",
	"Core Formation",
	"Nascent Soul",
	"Soul Transformation",
	"Void Refinement",
	"Body Integration",
	"Great Ascension",
	"Immortal Ascension",
]
const STAGES_PER_REALM := 9

## The elemental auras. Each one is a colour, a shape of motion, and the tier at
## which it becomes available, so a new element is the visible reward for pushing
## the realm forward and the settings panel can only ever offer what was earned.
##
## The numbers here describe how the effect *moves*: `emission` is particles per
## second at full power, `speed` how fast they travel, `orbit` how hard they
## circle the body instead of falling, `spread` how wide the ring sits, and
## `light` how much of a lamp the aura is. How *big* the aura is comes from the
## stage, not from here.
const AURAS: Array = [
	{
		"id": "none", "label": "None", "unlock_tier": 0,
		"color": Color("ffffff"), "accent": Color("ffffff"),
		"emission": 0, "speed": 0.0, "orbit": 0.0, "spread": 0.0, "light": 0.0,
		"blurb": "No aura. Only your own skin between you and the world.",
	},
	{
		"id": "qi", "label": "Qi", "unlock_tier": 0,
		"color": Color("6ec8ff"), "accent": Color("cdeaff"),
		"emission": 40, "speed": 1.1, "orbit": 0.9, "spread": 0.75, "light": 0.5,
		"blurb": "Raw refined qi drawn off the dantian. Soft, steady, always awake.",
	},
	{
		"id": "wind", "label": "Wind", "unlock_tier": 2,
		"color": Color("cfeee0"), "accent": Color("8fd9b4"),
		"emission": 70, "speed": 2.8, "orbit": 1.7, "spread": 1.30, "light": 0.22,
		"blurb": "A wide, fast spiral. Thin as breath and impossible to grasp.",
	},
	{
		"id": "water", "label": "Water", "unlock_tier": 5,
		"color": Color("4fa3e3"), "accent": Color("a8dcff"),
		"emission": 90, "speed": 1.5, "orbit": 0.6, "spread": 0.95, "light": 0.6,
		"blurb": "Heavy droplets that rise and fall in a tide of their own.",
	},
	{
		"id": "electric", "label": "Electric", "unlock_tier": 9,
		"color": Color("ffe86e"), "accent": Color("ffffff"),
		"emission": 130, "speed": 5.4, "orbit": 2.5, "spread": 1.10, "light": 0.9,
		"blurb": "Arcs that snap around the body. Hard to hold, harder to watch.",
	},
	{
		"id": "fire", "label": "Fire", "unlock_tier": 14,
		"color": Color("ff7a3d"), "accent": Color("ffd08a"),
		"emission": 170, "speed": 3.6, "orbit": 0.4, "spread": 1.40, "light": 1.5,
		"blurb": "A pillar fed by your own qi. Bright, hungry, and impossible to hide.",
	},
]

const COEFF_PER_REFINEMENT := 0.03
const COEFF_PER_TIER := 0.15

## Seconds of full-flow meditation to complete one refinement cycle. Grows with
## every refinement so later ranks take real dedication.
const CYCLE_BASE_SECONDS := 12.0
const CYCLE_GROWTH := 1.10

## Insight accrues at this fraction of the refinement rate, so a full meter can
## only exist once you have spent real time at the meditation mat.
const INSIGHT_RATE := 0.5
const INSIGHT_BASE := 15.0
const INSIGHT_GROWTH := 1.30

## QI burned per second while meditating, and how many refinements must be banked
## before the next breakthrough is permitted.
const QI_COST_BASE := 2.0
const QI_COST_PER_TIER := 0.5
const REFINEMENTS_BASE_REQUIRED := 3
const REFINEMENTS_PER_TIER := 1

const CAP_GROWTH_PER_TIER := 0.08
const CAP_GROWTH_PER_REALM := 0.25

const TIER_XP_SCALE := 2.0

var refinement: int = 0
var tier: int = 0
var insight: float = 0.0
var cycle: float = 0.0
var meditating: bool = false

## Written by the world's spirit zones once per frame.
##
## `zone_boost` multiplies the trance's *throughput*: qi burns faster and both meters
## fill proportionally faster, so a zone is a straight speed-up rather than a discount
## on the cost of a refinement. `zone_locked` marks a zone the body is standing in but
## is not yet advanced enough to use, which the HUD reports differently from being out
## in the open.
var zone_boost: float = 1.0
var zone_name: String = ""
var zone_locked: bool = false
var zone_required_tier: int = 0


func _ready() -> void:
	var data: Dictionary = PlayerData.take_loaded_cultivation()
	if not data.is_empty():
		refinement = int(data.get("refinement", 0))
		tier = int(data.get("tier", 0))
		insight = maxf(0.0, float(data.get("insight", 0.0)))
		cycle = maxf(0.0, float(data.get("cycle", 0.0)))
	_apply_coefficient()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not meditating:
		return

	# A stalled or zero-length frame is not a reason to drop out of the trance;
	# only a real cost that cannot be paid is. (Getting this wrong means the first
	# hitch, or the first frame after a browser tab regains focus, ends meditation
	# for no visible reason.)
	# Standing in an unlocked spirit zone raises the rate qi is drawn and the rate the
	# meters fill by the same factor, so it is genuinely "more qi per second" rather
	# than a cheaper refinement.
	#
	# And the *hour* multiplies the same number, because the zones breathe harder in the
	# dark. Read from the clock here rather than folded into `zone_boost` when the zone is
	# entered: the sun sets while a body is already sitting, and a boost captured at the
	# moment of arrival would mean the best way to use a zone at night is to stand up and
	# walk back into it.
	var boost: float = maxf(0.1, zone_boost * Clock.zone_share())
	var want: float = qi_cost_per_second() * boost * delta
	if want <= 0.0:
		return
	var spent: float = PlayerData.spend("qi", want)
	var flow: float = spent / want

	if spent <= 0.0:
		stop_meditation()
		log_message.emit("Your dantian is empty. Qi will recover on its own.", "info")
		return

	# A half-empty dantian gives half-speed progress rather than silently
	# swallowing the qi cost.
	cycle += delta * boost * flow
	insight = minf(insight_required(), insight + delta * boost * flow * INSIGHT_RATE)
	PlayerData.gain("qi", spent * TIER_XP_SCALE)
	# Seconds actually spent in the trance with qi to burn, which is what the elder's
	# patience tasks count. A trance that has run dry does not count, because it is not
	# cultivation, it is sitting down.
	Quests.report("meditate", delta * flow)

	# Refinement cycles can complete more than once per frame in theory; keep the
	# loop so banking is always exact.
	while cycle >= cycle_required():
		cycle -= cycle_required()
		refinement += 1
		_apply_coefficient()
		cultivation_changed.emit()
		log_message.emit(
			"Refinement %d reached — stat gain now ×%.2f." % [refinement, gain_coefficient()],
			"cultivate"
		)


# --------------------------------------------------------------- calculations

func cycle_required() -> float:
	return CYCLE_BASE_SECONDS * pow(CYCLE_GROWTH, refinement)


func insight_required() -> float:
	return INSIGHT_BASE * pow(INSIGHT_GROWTH, tier)


func qi_cost_per_second() -> float:
	return QI_COST_BASE + QI_COST_PER_TIER * float(tier)


func refinements_needed() -> int:
	return REFINEMENTS_BASE_REQUIRED + REFINEMENTS_PER_TIER * tier


func gain_coefficient() -> float:
	return 1.0 + COEFF_PER_REFINEMENT * float(refinement) + COEFF_PER_TIER * float(tier)


func cycle_ratio() -> float:
	return clampf(cycle / maxf(0.001, cycle_required()), 0.0, 1.0)


func insight_ratio() -> float:
	return clampf(insight / maxf(0.001, insight_required()), 0.0, 1.0)


func realm_index() -> int:
	return mini(tier / STAGES_PER_REALM, REALMS.size() - 1)


func stage() -> int:
	return (tier % STAGES_PER_REALM) + 1


# ------------------------------------------------------------------------- auras

## Every aura the current tier has earned, in catalogue order.
func unlocked_auras() -> Array:
	var out: Array = []
	for entry: Dictionary in AURAS:
		if tier >= int(entry["unlock_tier"]):
			out.append(entry)
	return out


func aura_def(id: String) -> Dictionary:
	for entry: Dictionary in AURAS:
		if String(entry["id"]) == id:
			return entry
	return {}


func aura_unlocked(id: String) -> bool:
	var defn: Dictionary = aura_def(id)
	return not defn.is_empty() and tier >= int(defn["unlock_tier"])


## The aura actually in effect: the player's own choice while it is still theirs
## to wear, and otherwise the best one they have earned. Never returns an id that
## is not in the catalogue, so the effect can never be asked for something it has
## no description of.
func active_aura() -> String:
	if aura_unlocked(PlayerData.chosen_aura):
		return PlayerData.chosen_aura
	var unlocked: Array = unlocked_auras()
	if unlocked.is_empty():
		return "none"
	return String((unlocked[unlocked.size() - 1] as Dictionary)["id"])


## How far through the current nine-stage realm you are, 0..1.
func realm_progress() -> float:
	return float(stage() - 1) / float(STAGES_PER_REALM - 1)


## Aura intensity, 0..1, ramping over the first eighteen tiers and then crawling.
## A fresh realm should be visibly stronger without the effect exploding.
func aura_power() -> float:
	return clampf(float(tier) / 18.0, 0.0, 1.0)


func realm_name() -> String:
	return String(REALMS[realm_index()])


func realm_label() -> String:
	return Loc.fill("%s · Stage %d", [Loc.say(realm_name()), stage()])


func refinements_missing() -> int:
	return maxi(0, refinements_needed() - refinement)


func can_break_through() -> bool:
	return insight_ratio() >= 1.0 and refinement >= refinements_needed()


## Human-readable reason the breakthrough key will not work, for the HUD.
func breakthrough_blocker() -> String:
	if insight_ratio() < 1.0:
		return "Insight %d%%" % int(round(insight_ratio() * 100.0))
	if refinement < refinements_needed():
		return "Refine %d more" % refinements_missing()
	return ""


func _apply_coefficient() -> void:
	PlayerData.gain_coefficient = gain_coefficient()


# ------------------------------------------------------------------ meditation

func start_meditation() -> bool:
	if meditating:
		return false
	# Not inside the tower. A trance on a landing would be a rest between floors, and the entire
	# design of the climb is that there is no rest — the pills in the belt are the rest, and they
	# were paid for at a village. Refusing here rather than hiding the key means the reason is
	# said out loud the first time somebody tries it.
	if Tower.inside():
		PlayerData.log_message.emit(
			"The tower's stair answers nothing. Whatever you carried up is what you have.", "damage"
		)
		Audio.play("error", -6.0)
		return false
	meditating = true
	# The qigong cycle must be able to empty the dantian; passive regen would otherwise
	# cancel the drain out and meditation would cost nothing. Nothing to set here: the flag
	# that holds regen off is read from this one, so entering the trance is what holds it.
	meditation_started.emit()
	return true


func stop_meditation() -> void:
	if not meditating:
		return
	meditating = false
	meditation_stopped.emit()


func toggle_meditation() -> void:
	if meditating:
		stop_meditation()
	else:
		start_meditation()


# ------------------------------------------------------------------ breakthrough

func break_through() -> bool:
	if not can_break_through():
		var blocker: String = breakthrough_blocker()
		if blocker != "":
			log_message.emit("Breakthrough not ready — %s." % blocker, "info")
		return false

	stop_meditation()
	insight = 0.0
	cycle = 0.0
	tier += 1
	_apply_coefficient()

	# A tier that unlocks an elemental aura says so, since it is otherwise easy to
	# miss that the palette in the settings panel just grew.
	for entry: Dictionary in AURAS:
		if int(entry["unlock_tier"]) == tier:
			log_message.emit("New aura unlocked: %s." % entry["label"], "cultivate")

	var crossed_realm: bool = (tier % STAGES_PER_REALM) == 0
	var growth: float = CAP_GROWTH_PER_REALM if crossed_realm else CAP_GROWTH_PER_TIER
	PlayerData.grow_all_caps(growth)
	PlayerData.restore_all()

	breakthrough_performed.emit(tier, realm_name())
	cultivation_changed.emit()

	if crossed_realm:
		realm_advanced.emit(realm_index(), realm_name())
		log_message.emit(
			"REALM ADVANCE — %s. All caps +%d%%, gain ×%.2f." % [
				realm_name(), int(round(growth * 100.0)), gain_coefficient()
			],
			"breakthrough"
		)
	else:
		log_message.emit(
			"Breakthrough! %s. All caps +%d%%, gain ×%.2f." % [
				realm_label(), int(round(growth * 100.0)), gain_coefficient()
			],
			"breakthrough"
		)
	return true


func reset() -> void:
	refinement = 0
	tier = 0
	insight = 0.0
	cycle = 0.0
	meditating = false
	_apply_coefficient()
	cultivation_changed.emit()


# ---------------------------------------------------------------- persistence

func get_save_data() -> Dictionary:
	return {
		"refinement": refinement,
		"tier": tier,
		"insight": insight,
		"cycle": cycle,
	}
