extends Node
## The elder's chain of tasks: the game's guided path from "you can walk" to
## "you can dash".
##
## A task is a counter with a target, so progress is reported by whatever already
## knows the fact — the controller reports metres run, the enemy reports a kill, the
## trance reports seconds sat — rather than this file polling the world. That keeps
## every task cheap and keeps the trigger next to the thing being counted.
##
## Tasks are taken in order and handed in at the elder. Turning one in pays crystals
## and, for the milestone tasks, unlocks a movement ability: an air jump, a dash, a
## second air jump, then a shorter dash cooldown. Abilities are what the chain is
## really for — the crystals are the spendable half.
##
## Progress and the completed count live in the save through PlayerData, so a task
## half-finished survives a reload.

signal task_started(task: Dictionary)
signal task_progress(task: Dictionary, amount: float)
signal task_completed(task: Dictionary)
signal task_claimed(task: Dictionary)

## The whole chain, in order. `ability` entries are granted on claim; `value` is what
## the ability is set to, which is how an extra air jump and a shorter cooldown are
## both expressed as a task reward.
const TASKS: Array = [
	{
		"id": "first_steps",
		"title": "Find your feet",
		"detail": "Run {target} m with Shift held. The road out of camp is the long one.",
		"kind": "run", "target": 250.0,
		"crystals": 5,
		"hint": "Shift to run. The metres count only while you are actually moving.",
	},
	{
		"id": "lightness",
		"title": "Lightness",
		"detail": "Leave the ground {target} times.",
		"kind": "jump", "target": 25.0,
		"crystals": 6,
		"ability": "air_jumps", "value": 1,
		"hint": "Jump again in mid-air once this is yours — and mind the landing.",
	},
	{
		"id": "sit_still",
		"title": "Sit still until it moves",
		"detail": "Cultivate for {target} seconds in total.",
		"kind": "meditate", "target": 90.0,
		"crystals": 8,
		"ability": "dash", "value": true,
		"hint": "Press C to sit. A spirit zone does the same work faster.",
	},
	{
		"id": "first_blood",
		"title": "Blood on the road",
		"detail": "Defeat {target} raiders at their camps.",
		"kind": "kill", "target": 4.0,
		"crystals": 14,
		"ability": "air_jumps", "value": 2,
		"hint": "Raiders keep to their own ground. Strike them, then step back out of reach.",
	},
	{
		"id": "crystal_debt",
		"title": "A heavier purse",
		"detail": "Gather {target} crystals from the camps.",
		"kind": "crystals", "target": 30.0,
		"crystals": 10,
		"ability": "dash_cooldown", "value": 1.3,
		"hint": "Every raider carries a shard or two.",
	},
	{
		"id": "long_road",
		"title": "The long road",
		"detail": "Run {target} m in total.",
		"kind": "run", "target": 1500.0,
		"crystals": 20,
		"ability": "dash_cooldown", "value": 0.9,
		"hint": "The roads are levelled for exactly this.",
	},
	{
		"id": "deep_water",
		"title": "Deep water",
		"detail": "Cultivate for {target} seconds in total.",
		"kind": "meditate", "target": 420.0,
		"crystals": 26,
		"ability": "air_jumps", "value": 3,
		"hint": "A realm is not rushed.",
	},
]

## Progress keyed by task id. Counters here are cumulative for the run of the task;
## the totals a task measures against are also cumulative, so a task can never be
## completed and then un-completed by walking backwards.
var _progress: Dictionary = {}
var _completed: int = 0
## Set while the elder is being talked to. A task is finished by claiming it, so a
## task can sit complete until the player walks back to camp.
var _claimed: int = 0


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_quests()
	if not saved.is_empty():
		_progress = saved.get("progress", {})
		_completed = int(saved.get("completed", 0))
		_claimed = int(saved.get("claimed", 0))
	# Tasks complete themselves the moment their counter fills, so the elder only has
	# to be visited to collect.
	PlayerData.stats_changed.connect(_check_active)


func save_data() -> Dictionary:
	return {
		"progress": _progress.duplicate(),
		"completed": _completed,
		"claimed": _claimed,
	}


# --------------------------------------------------------------------- querying

## The task being worked on: the first one that is not yet complete. Empty when the
## whole chain is done.
func current() -> Dictionary:
	if _completed >= TASKS.size():
		return {}
	return TASKS[_completed]


func current_index() -> int:
	return _completed


## The task waiting to be handed in, or an empty dictionary. The elder's marker shows
## "?" rather than "!" while one of these exists.
func claimable() -> Dictionary:
	if _completed <= _claimed:
		return {}
	return TASKS[_claimed]


func progress_of(task: Dictionary) -> float:
	return float(_progress.get(String(task["id"]), 0.0))


func ratio_of(task: Dictionary) -> float:
	var target: float = maxf(1.0, float(task["target"]))
	return clampf(progress_of(task) / target, 0.0, 1.0)


func completed_count() -> int:
	return _completed


func task_count() -> int:
	return TASKS.size()


func all_complete() -> bool:
	return _completed >= TASKS.size()


# ------------------------------------------------------------------- reporting

## Records progress toward the current task. Called by whatever already knows the
## fact; kinds that do not match the active task are ignored, so every reporter can
## fire unconditionally.
func report(kind: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var task: Dictionary = current()
	if task.is_empty() or String(task["kind"]) != kind:
		return
	# A cumulative total, never a session count: these tasks are about the distance
	# walked since the beginning, which is what the player sees in the save.
	var id: String = String(task["id"])
	_progress[id] = float(_progress.get(id, 0.0)) + amount
	PlayerData.mark_dirty()
	task_progress.emit(task, float(_progress[id]))
	_check_active()


## Completes the current task as soon as its counter fills. The reward is paid on
## claim, not here, so walking away mid-task is never punished.
func _check_active() -> void:
	var task: Dictionary = current()
	if task.is_empty():
		return
	if float(_progress.get(String(task["id"]), 0.0)) < float(task["target"]):
		return
	_completed += 1
	PlayerData.mark_dirty()
	task_completed.emit(task)
	PlayerData.log_message.emit(
		"%s — done. Return to the elder." % String(task["title"]), "gain"
	)
	var next: Dictionary = current()
	if not next.is_empty():
		task_started.emit(next)


## Hands in the completed task: pays the crystals and grants the ability. Returns the
## task that was handed in, or empty if there was nothing to hand in.
func claim() -> Dictionary:
	var task: Dictionary = claimable()
	if task.is_empty():
		return {}
	_claimed += 1
	PlayerData.mark_dirty()
	var reward: int = int(task.get("crystals", 0))
	if reward > 0:
		PlayerData.add_crystals(reward)
	if task.has("ability"):
		PlayerData.unlock_ability(String(task["ability"]), task["value"])
	PlayerData.log_message.emit(
		"%s complete — %d crystals%s" % [
			String(task["title"]), reward,
			"" if not task.has("ability") else " and a new trick",
		],
		"breakthrough"
	)
	Audio.play("confirm", -2.0)
	task_claimed.emit(task)
	return task


## Description with the target filled in, so a task reads as a sentence rather than
## as a template.
func describe(task: Dictionary) -> String:
	return String(task.get("detail", "")).replace("{target}", _number(float(task.get("target", 0.0))))


func _number(value: float) -> String:
	return str(int(round(value))) if is_equal_approx(value, round(value)) else String.num(value, 1)


func reset() -> void:
	_progress.clear()
	_completed = 0
	_claimed = 0
