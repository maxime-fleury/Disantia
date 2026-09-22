extends Node
## Physical training: the qi-free half of the cultivation loop.
##
## The drills cost HP rather than QI, and that choice is the whole system. It means
## you can drill until you are exhausted with an empty dantian, that a body at
## zero is the natural end of a session, and that the only way to drill *longer*
## is to earn a bigger constitution — which is precisely what you are training.
## BODY widens the HP cap, so the loop closes on itself.
##
## **One drill at a time, and which one it is depends on your cultivation.** Three
## physical exercises (pushups, squats, a horse stance) were three ways of paying the same
## blood for the same attribute: a panel of rows where one row was the whole decision. Past
## `QiPressure.UNLOCK_QI` the work changes character — the body stops being drilled from the
## outside and starts being pushed from the inside — so the same single key now runs the qi
## cripple, and the detail that used to be spread across a menu lives in the two numbers that
## actually differ between the two drills: what they cost and what they train.
##
## A rep is a fixed slice of time, so training is something you hold down, the
## same way meditating is. The controller decides when a drill may run (feet on the
## ground, not moving, not meditating); this owns the reps and the pay-out.

signal exercise_started(id: String)
signal exercise_stopped(id: String)
signal rep_completed(id: String, reps: int)
signal log_message(text: String, kind: String)
## The catalogue changed — the qi cripple has become available. The interface listens so a
## row can appear without the player having to find the panel again after a breakthrough.
signal catalogue_changed

## Qi Pressure's script, read for its own unlock constant rather than keeping a copy of the
## number here. Two files that both decide "how much qi is enough" is two files that
## disagree the next time either is retuned.
const PRESSURE := preload("res://scripts/player/qi_pressure.gd")

## `clip` is the posture to hold and `clip_speed` how fast to run it: the pack has
## no pushup animation, and a crouch-and-rise read at the right tempo is honest
## enough, while the cripple is deliberately a slowed idle — a body standing still
## with its breath turning over.
##
## `hp_cost` is a *fraction of the health cap*, not a flat number of points. It has to
## be: health regenerates as a share of the cap, so a flat cost is a real price at 100
## HP and free at 300, where the regen refills it between reps. The rate is
## deliberately above `RESOURCE_REGEN["hp"]` of 1.2% a second, so a drill always costs
## blood and never becomes a way to stand still while the bar fills itself.
##
## `qi_cost` is a share of the *pool*, the same rule every qi technique follows, and it is
## what makes the cripple a deeper body's drill: the price rises with the pool that pays it.
const EXERCISES: Array = [
	{
		"id": "pushups", "label": "Pushups", "key": "1",
		"clip": "PickUp", "clip_speed": 1.0, "seconds_per_rep": 1.15,
		"hp_cost": 0.018, "qi_cost": 0.0, "body_xp": 1.0, "secondary": "",
		"secondary_xp": 0.0, "qi_xp": 0.0,
		"blurb": "Pure constitution. Costs the most blood and trains the most body.",
	},
	{
		"id": "qi_cripple", "label": "Qi Cripple", "key": "1",
		"clip": "Idle", "clip_speed": 0.40, "seconds_per_rep": 1.30,
		"hp_cost": 0.016, "qi_cost": 0.07, "body_xp": 0.60, "secondary": "",
		"secondary_xp": 0.0, "qi_xp": 1.0,
		"blurb": "Breath driven through the meridians until they give. "
			+ "Costs blood and qi, and the deeper the dantian the faster it goes.",
	},
]

## The drill whose place the cripple takes, by id.
const FIRST_DRILL := "pushups"

## Seconds per rep of the cripple at a calm breath. The real figure is this divided by the tempo
## below, and the share of the pool it costs does *not* move with the tempo — which is what makes
## a deeper dantian spend more per second for the same work. It has to be: with both the tempo
## and the share fixed, the drill would pay for itself exactly at the unlock and the whole
## "it costs more qi" clause would be a comment rather than a rule.
const QI_REP_SECONDS := 1.30
## Points of breath the body takes back per second at which the tempo has doubled. Measured in
## *points*, not in a share of the cap, on purpose: passive qi regeneration is five per cent of
## the pool, so a share would be the same number at every depth and the whole "deeper dantian,
## faster work" clause would be a comment rather than a rule.
const QI_TEMPO_REFERENCE := 150.0
## How much faster than a calm rate the drill is ever allowed to be. A ceiling rather than pure
## scaling because the tempo is what the player *watches*: past three times the calm pace the
## reps stop reading as a body doing something and start reading as a stutter.
const QI_TEMPO_CEILING := 3.0

## The drill in progress, or "" for none.
var active: String = ""
## Reps banked in the drill currently running. Resets whenever a drill stops, so
## this is "the set you are in" rather than lifetime volume.
var reps: int = 0

var _rep_timer: float = 0.0
var _totals: Dictionary = {}
## Whether the catalogue held the cripple last time it was asked, so the signal is emitted on
## the *edge* rather than every frame a deep body stands still.
var _cripple_was_available: bool = false


func _ready() -> void:
	_cripple_was_available = cripple_unlocked()


func _process(delta: float) -> void:
	_watch_catalogue()
	if active == "":
		return
	var defn: Dictionary = def(active)
	_rep_timer += delta
	if _rep_timer < seconds_per_rep(active):
		return
	# A rep is paid for up front, and in two currencies for the cripple. Running dry in
	# either ends the set instead of letting the body grind against a floor it cannot pass.
	var blood: float = PlayerData.spend("hp", blood_cost(active))
	if blood <= 0.0:
		stop()
		log_message.emit("Nothing left in the tank. The set ends.", "damage")
		return
	var breath_owed: float = qi_cost(active)
	if breath_owed > 0.0 and PlayerData.spend("qi", breath_owed) < breath_owed:
		# The blood is already gone — the rep was begun — so this is a rep that hurts and
		# pays nothing, which is exactly what running out mid-drill should feel like.
		PlayerData.restore("hp", blood)
		stop()
		log_message.emit("The breath runs out. The set ends.", "damage")
		return

	_rep_timer = 0.0
	reps += 1
	_totals[active] = int(_totals.get(active, 0)) + 1
	PlayerData.gain("body", float(defn["body_xp"]))
	var secondary: String = String(defn["secondary"])
	if secondary != "":
		PlayerData.gain(secondary, float(defn["secondary_xp"]))
	# The blood a drill costs is *damage*, and damage is what thickens the skin. Paid through
	# the same door a raider's fist uses, so the two can never drift apart.
	PlayerData.gain_defense_from(blood)
	var breath: float = float(defn["qi_xp"])
	if breath > 0.0:
		PlayerData.gain("qi", breath * qi_xp_scale())
	rep_completed.emit(active, reps)


## The drills available right now. One, always — see the note at the top of the file.
func catalogue() -> Array:
	if cripple_unlocked():
		return [def("qi_cripple")]
	return [def(FIRST_DRILL)]


## True once the pool is deep enough to push a shell of breath out of the skin. Asked of the
## pressure field's own constant, so unlocking the technique and unlocking the drill are the
## same event rather than two numbers that happen to match today.
func cripple_unlocked() -> bool:
	return PlayerData.get_cap("qi") >= PRESSURE.UNLOCK_QI


func available(id: String) -> bool:
	for entry: Dictionary in catalogue():
		if String(entry["id"]) == id:
			return true
	return false


## The ids in the catalogue, for anything that has to notice a change without comparing
## dictionaries.
func catalogue_ids() -> Array:
	var out: Array = []
	for entry: Dictionary in catalogue():
		out.append(String(entry["id"]))
	return out


func start(id: String) -> bool:
	if id == "" or def(id).is_empty() or id == active or not available(id):
		return false
	if active != "":
		stop()
	active = id
	reps = 0
	_rep_timer = 0.0
	exercise_started.emit(id)
	return true


func stop() -> void:
	if active == "":
		return
	var finished: String = active
	var done: int = reps
	active = ""
	reps = 0
	_rep_timer = 0.0
	exercise_stopped.emit(finished)
	if done > 0:
		var defn: Dictionary = def(finished)
		log_message.emit("%d %s. Body remembers." % [done, String(defn["label"]).to_lower()],
			"cultivate")


func is_training() -> bool:
	return active != ""


func active_id() -> String:
	return active


## Blood a single rep of a drill costs, in points, from the fraction of the cap the
## catalogue stores. Every caller gets the number the same way, so the cost cannot
## drift between the tick that charges it and anything that advertises it.
func blood_cost(id: String) -> float:
	var defn: Dictionary = def(id)
	if defn.is_empty():
		return 0.0
	return maxf(0.1, PlayerData.get_cap("hp") * float(defn["hp_cost"]))


## Breath a single rep costs, in points. Zero for the physical drill, which is the whole
## difference between the two of them.
func qi_cost(id: String) -> float:
	var defn: Dictionary = def(id)
	if defn.is_empty():
		return 0.0
	var share: float = float(defn.get("qi_cost", 0.0))
	if share <= 0.0:
		return 0.0
	return maxf(1.0, PlayerData.get_cap("qi") * share)


## Blood a drill drains per second, as a share of the health cap. The HUD prints it
## so the price of a drill is visible before it is paid.
func blood_per_second(id: String) -> float:
	var defn: Dictionary = def(id)
	if defn.is_empty():
		return 0.0
	return float(defn["hp_cost"]) / maxf(0.05, seconds_per_rep(id))


## Qi a drill drains per second, in points.
func qi_per_second(id: String) -> float:
	var defn: Dictionary = def(id)
	if defn.is_empty():
		return 0.0
	return qi_cost(id) / maxf(0.05, seconds_per_rep(id))


## How long a rep of this drill takes. The cripple's pace is set by what the body *takes back*
## per second, so the drill visibly speeds up when the dantian deepens — which is the reward
## for the pool the drill is spending.
func seconds_per_rep(id: String) -> float:
	var defn: Dictionary = def(id)
	if defn.is_empty():
		return 1.0
	if String(defn["id"]) != "qi_cripple":
		return maxf(0.05, float(defn["seconds_per_rep"]))
	return maxf(0.10, QI_REP_SECONDS / qi_tempo())


## Reps per second of the cripple against the calm rate. 1.0 with a pool that gives nothing
## back, `QI_TEMPO_CEILING` once the body is swimming in breath.
func qi_tempo() -> float:
	var per_second: float = PlayerData.regen_per_second("qi")
	return clampf(1.0 + per_second / QI_TEMPO_REFERENCE, 1.0, QI_TEMPO_CEILING)


## What a rep is worth in the breath, scaled by how deep the dantian is. Both halves of
## "the deeper you are, the faster the work goes" live here: the tempo above sets how *often*
## a rep lands, and this sets how much each one is worth.
func qi_xp_scale() -> float:
	return 1.0 + PlayerData.get_cap("qi") / (PRESSURE.SUSTAIN_QI * 2.0)


func def(id: String) -> Dictionary:
	for entry: Dictionary in EXERCISES:
		if String(entry["id"]) == id:
			return entry
	return {}


## The posture the animator should hold while training, or "" if not training.
func active_clip() -> String:
	if active == "":
		return ""
	return String(def(active).get("clip", ""))


func clip_speed() -> float:
	if active == "":
		return 1.0
	return float(def(active).get("clip_speed", 1.0))


## 0..1 through the current rep, for a progress bar on the HUD.
func rep_ratio() -> float:
	if active == "":
		return 0.0
	return clampf(_rep_timer / maxf(0.01, seconds_per_rep(active)), 0.0, 1.0)


func total_reps(id: String = "") -> int:
	if id != "":
		return int(_totals.get(id, 0))
	var sum: int = 0
	for key: String in _totals:
		sum += int(_totals[key])
	return sum


## How hard the current drill is draining you, HP per second — the number that
## actually decides how long a session lasts, and the one the HUD shows.
func drain_per_second() -> float:
	if active == "":
		return 0.0
	return blood_cost(active) / maxf(0.05, seconds_per_rep(active))


func get_save_data() -> Dictionary:
	return {"totals": _totals}


func apply_save_data(data: Dictionary) -> void:
	_totals = data.get("totals", {})


func reset() -> void:
	active = ""
	reps = 0
	_rep_timer = 0.0
	_totals.clear()


## Emits when the catalogue has gained or lost a drill. Called every frame it is cheap: it
## compares one boolean, and a save that reloads a deep body has to notice here rather than
## only on the frame the cap moved.
func _watch_catalogue() -> void:
	var now: bool = cripple_unlocked()
	if now == _cripple_was_available:
		return
	_cripple_was_available = now
	catalogue_changed.emit()
