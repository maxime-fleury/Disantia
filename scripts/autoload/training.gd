extends Node
## Physical training: the qi-free half of the cultivation loop.
##
## Exercises cost HP rather than QI, and that choice is the whole system. It means
## you can drill until you are exhausted with an empty dantian, that a body at
## zero is the natural end of a session, and that the only way to drill *longer*
## is to earn a bigger constitution — which is precisely what you are training.
## BODY widens the HP cap, so the loop closes on itself.
##
## A rep is a fixed slice of time, so training is something you hold down, the
## same way meditating is. The controller decides when a drill may run (feet on
## the ground, not moving, not meditating); this owns the reps and the pay-out.

signal exercise_started(id: String)
signal exercise_stopped(id: String)
signal rep_completed(id: String, reps: int)
signal log_message(text: String, kind: String)

## `clip` is the posture to hold and `clip_speed` how fast to run it: the pack has
## no pushup animation, and a crouch-and-rise read at the right tempo is honest
## enough, while a stance is deliberately a slowed idle.
##
## `hp_cost` is a *fraction of the health cap*, not a flat number of points. It has to
## be: health regenerates as a share of the cap, so a flat cost is a real price at 100
## HP and free at 300, where the regen refills it between reps. Each of these rates is
## deliberately above `RESOURCE_REGEN["hp"]` of 1.2% a second, so a drill always costs
## blood and never becomes a way to stand still while the bar fills itself.
const EXERCISES: Array = [
	{
		"id": "pushups", "label": "Pushups", "key": "1",
		"clip": "PickUp", "clip_speed": 1.0, "seconds_per_rep": 1.15,
		"hp_cost": 0.018, "body_xp": 1.0, "secondary": "", "secondary_xp": 0.0,
		"blurb": "Pure constitution. Costs the most blood and trains the most body.",
	},
	{
		"id": "squats", "label": "Squats", "key": "2",
		"clip": "PickUp", "clip_speed": 1.3, "seconds_per_rep": 0.95,
		"hp_cost": 0.013, "body_xp": 0.75, "secondary": "jump", "secondary_xp": 0.30,
		"blurb": "Cheaper per rep, and the legs earn a little of the jump with them.",
	},
	{
		"id": "stance", "label": "Iron Stance", "key": "3",
		"clip": "Idle", "clip_speed": 0.35, "seconds_per_rep": 1.6,
		"hp_cost": 0.022, "body_xp": 0.55, "secondary": "defense", "secondary_xp": 0.45,
		"blurb": "Horse stance. Slow and stubborn, and it thickens the skin you hide behind.",
	},
]

## The drill in progress, or "" for none.
var active: String = ""
## Reps banked in the drill currently running. Resets whenever a drill stops, so
## this is "the set you are in" rather than lifetime volume.
var reps: int = 0

var _rep_timer: float = 0.0
var _totals: Dictionary = {}


func _process(delta: float) -> void:
	if active == "":
		return
	var defn: Dictionary = def(active)
	_rep_timer += delta
	if _rep_timer < float(defn["seconds_per_rep"]):
		return
	# A rep is paid for up front. Running dry mid-rep ends the set instead of
	# letting the body grind against a floor it cannot pass.
	var spent: float = PlayerData.spend("hp", blood_cost(active))
	if spent <= 0.0:
		stop()
		log_message.emit("Nothing left in the tank. The set ends.", "damage")
		return

	_rep_timer = 0.0
	reps += 1
	_totals[active] = int(_totals.get(active, 0)) + 1
	PlayerData.gain("body", float(defn["body_xp"]))
	var secondary: String = String(defn["secondary"])
	if secondary != "":
		PlayerData.gain(secondary, float(defn["secondary_xp"]))
	rep_completed.emit(active, reps)


func start(id: String) -> bool:
	if id == "" or def(id).is_empty() or id == active:
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


## Blood a drill drains per second, as a share of the health cap. The HUD prints it
## so the price of a drill is visible before it is paid.
func blood_per_second(id: String) -> float:
	var defn: Dictionary = def(id)
	if defn.is_empty():
		return 0.0
	return float(defn["hp_cost"]) / maxf(0.05, float(defn["seconds_per_rep"]))


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
	return clampf(_rep_timer / float(def(active)["seconds_per_rep"]), 0.0, 1.0)


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
	return blood_cost(active) / maxf(0.05, float(def(active)["seconds_per_rep"]))


func get_save_data() -> Dictionary:
	return {"totals": _totals}


func apply_save_data(data: Dictionary) -> void:
	_totals = data.get("totals", {})


func reset() -> void:
	active = ""
	reps = 0
	_rep_timer = 0.0
	_totals.clear()
