extends Node
## What happens when you hit somebody who lives here.
##
## The world had teeth in exactly one direction. Ten camps' worth of raiders would come at you
## and nothing you did to anything was ever anybody's business: you could walk into a village,
## strike the first person you met, walk out, and come back to the same square with the same
## shop at the same price. A world that only ever *suffers* the player is a diorama. The point
## of a guard is not that it stands there — it is that it makes a choice about you.
##
## The ladder, and every rung of it is visible from outside:
##
##   1  watched    the guards call out and the squares go quiet when you walk in
##   2  hunted     they come at you, and they are on the road between the villages too
##   3  outlaw     the shops shut, the healer refuses, the gates are closed to you
##
## The way down is money or time — and *time* here means the clock, not a waiting screen: a
## day passing without new trouble forgives one rung, which is the only reason a player ever
## has to care what hour it is. Getting caught with a price on your head puts you in the
## lockup, and the lockup is not a cutscene: the fine can be paid at the bars if you have it,
## and the bar can be forced if you do not — which costs you the rung you were trying to shed.
## Being caught is therefore *expensive*, not *paused*, and there is no timer anywhere in it.

signal severity_changed(village_id: String, severity: int, reason: String)
signal jailed(village_id: String)
signal released(village_id: String, how: String)

const MAX_SEVERITY := 3
const LABELS: Array = ["clear", "watched", "hunted", "outlaw"]

## How far past a village the guards' business reaches. Beyond it you are nobody's problem,
## which is what makes the far rings the place to be wanted in.
const TERRITORY := 62.0

## What a rung of the ladder costs to have taken off. Quadratic-ish on purpose: being wanted
## in three villages is a bigger bill than three times one.
const FINE_UNIT := 22

var severity: Dictionary = {}
## Every village's lockup, registered by the village that built it: where a caught body is put,
## where the bars let out, and the door that is shut while they are in there.
var _cells: Dictionary = {}
var _jailed_in: String = ""
## Named for the log, because "someone saw you" is the sentence that makes the ladder readable.
var last_crime: String = ""


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_module("law")
	severity = saved.get("severity", {})
	Clock.day_passed.connect(_on_day_passed)


## A day without trouble is worth a rung. Tied to the clock rather than to a timer so that
## "wait it out" has a *shape* — you wait for a day, and you can watch it come.
func _on_day_passed(_day: int) -> void:
	var cooled: Array = []
	for village_id: String in severity.keys():
		if int(severity[village_id]) <= 0:
			continue
		severity[village_id] = int(severity[village_id]) - 1
		cooled.append(village_id)
	if cooled.is_empty():
		return
	PlayerData.mark_dirty()
	for village_id: String in cooled:
		severity_changed.emit(village_id, int(severity[village_id]), "a day passed")
	PlayerData.log_message.emit(
		"A day has gone by. The villages have short memories: %s." % ", ".join(cooled),
		"info"
	)


func save_data() -> Dictionary:
	return {"severity": severity}


func reset() -> void:
	severity.clear()
	_jailed_in = ""
	last_crime = ""


func register_cell(village_id: String, inside: Vector3, outside: Vector3, door: Object = null) -> void:
	_cells[village_id] = {"inside": inside, "outside": outside, "door": door}


# ------------------------------------------------------------------ the ladder

func wanted_at(village_id: String) -> int:
	return clampi(int(severity.get(village_id, 0)), 0, MAX_SEVERITY)


## The worst this body is wanted *anywhere near where it is standing*. Every rule below asks
## this rather than a global flag, because a player who burned a camp in Towerfall should be
## able to walk into Hollowmere and buy a pill.
func wanted_near(position: Vector3) -> int:
	var worst: int = 0
	for entry: Dictionary in Villages.all():
		var village_id: String = String(entry["id"])
		var here: int = wanted_at(village_id)
		if here <= 0:
			continue
		var site: Dictionary = Haven.site(village_id)
		if site.is_empty():
			continue
		var centre: Vector3 = site["centre"]
		if Vector2(position.x - centre.x, position.z - centre.z).length() <= TERRITORY * 2.0:
			worst = maxi(worst, here)
	return worst


func label(value: int) -> String:
	return String(LABELS[clampi(value, 0, MAX_SEVERITY)])


func is_wanted() -> bool:
	for village_id: String in severity.keys():
		if int(severity[village_id]) > 0:
			return true
	return false


## True when the guards of that village have decided the body in front of them is a problem
## to be dealt with rather than questioned.
func guards_hostile(village_id: String) -> bool:
	return wanted_at(village_id) >= 2


## Shops shut at the top rung. A merchant who sells to an outlaw is an outlaw.
func shops_closed(village_id: String) -> bool:
	return wanted_at(village_id) >= 3


func add_crime(kind: String, village_id: String, detail: String = "") -> void:
	if village_id == "":
		return
	var before: int = wanted_at(village_id)
	var step: int = 1
	match kind:
		"assault":
			step = 2
		"murder":
			step = MAX_SEVERITY
		"robbery":
			step = 2
		"escape":
			step = 1
		_:
			step = 1
	var now: int = mini(MAX_SEVERITY, before + step)
	if now == before:
		return
	severity[village_id] = now
	last_crime = kind
	PlayerData.mark_dirty()
	var village_name: String = String(Villages.def(village_id).get("name", village_id))
	PlayerData.log_message.emit(
		"%s — %s. %s counts you %s." % [
			detail if detail != "" else "The square goes quiet",
			village_name, village_name, label(now),
		],
		"damage"
	)
	Audio.play("error", -2.0)
	severity_changed.emit(village_id, now, kind)
	if now >= 2:
		PlayerData.log_message.emit(
			"The watch is coming. Bars, or the road.", "damage"
		)


## What it costs to be let off. Priced off the rung, so the ladder is a bill rather than a
## state: an outlaw is expensive to be, not impossible to stop being.
func fine(village_id: String) -> int:
	var level: int = wanted_at(village_id)
	return FINE_UNIT * level * level


func can_pay(village_id: String) -> bool:
	return wanted_at(village_id) > 0 and PlayerData.crystals >= fine(village_id)


func pay_fine(village_id: String) -> bool:
	if not can_pay(village_id):
		Audio.play("error", -8.0)
		return false
	var cost: int = fine(village_id)
	if not PlayerData.spend_crystals(cost):
		return false
	severity[village_id] = 0
	PlayerData.mark_dirty()
	PlayerData.log_message.emit(
		"The fine is paid. %s will deal with you again." % String(
			Villages.def(village_id).get("name", village_id)),
		"gain"
	)
	Audio.play("coin", -1.0)
	if _jailed_in == village_id:
		_open_door(village_id)
		_jailed_in = ""
		released.emit(village_id, "fine")
	severity_changed.emit(village_id, 0, "paid")
	return true


# -------------------------------------------------------------- the lockup

func in_prison() -> bool:
	return _jailed_in != ""


func jailed_in() -> String:
	return _jailed_in


## Puts the body behind bars. There is no sentence length: the door is shut until the fine is
## paid or the bar is forced, which is two decisions instead of one wait.
func imprison(village_id: String) -> bool:
	if village_id == "" or not _cells.has(village_id):
		return false
	var cell: Dictionary = _cells[village_id]
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	_jailed_in = village_id
	_shut_door(village_id)
	if player.has_method("warp_to"):
		player.call("warp_to", cell["inside"])
	PlayerData.log_message.emit(
		"You are put behind the door of %s's watch house. Pay the fine at the bars, or force "
		% String(Villages.def(village_id).get("name", village_id))
		+ "them — which they will remember.", "damage"
	)
	Audio.play("ui_close", -2.0)
	jailed.emit(village_id)
	return true


## Turns the door into a suggestion. Always available, and always costs a rung: a world where
## being caught is skippable for free is a world where being caught means nothing.
func break_out() -> bool:
	if _jailed_in == "":
		return false
	var village_id: String = _jailed_in
	var cell: Dictionary = _cells.get(village_id, {})
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	_open_door(village_id)
	_jailed_in = ""
	if player != null and player.has_method("warp_to") and cell.has("outside"):
		player.call("warp_to", cell["outside"])
	PlayerData.log_message.emit("The bar gives. You are out — and they will remember.", "damage")
	Audio.play("impact", 0.0, 0.8)
	released.emit(village_id, "escape")
	add_crime("escape", village_id, "A broken bar")
	return true


func _shut_door(village_id: String) -> void:
	var cell: Dictionary = _cells.get(village_id, {})
	var door: Object = cell.get("door", null)
	if door is CollisionShape3D and is_instance_valid(door):
		(door as CollisionShape3D).set_deferred("disabled", false)


func _open_door(village_id: String) -> void:
	var cell: Dictionary = _cells.get(village_id, {})
	var door: Object = cell.get("door", null)
	if door is CollisionShape3D and is_instance_valid(door):
		(door as CollisionShape3D).set_deferred("disabled", true)


## Called by a guard that has decided its business with the player is over — a blow landed on
## somebody who was not fighting back, or a body that is already wanted and in reach.
func arrest(player_position: Vector3, village_id: String) -> void:
	if _jailed_in != "":
		return
	if not _cells.has(village_id):
		# No lockup in the world (a test scene, a village that failed to build): the arrest
		# still has to cost something, so it costs the trip home and the fine's rung.
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		if player != null and player.has_method("warp_to"):
			player.call("warp_to", Haven.wake_point_for(player_position))
		PlayerData.log_message.emit(
			"A watchman walks you to the edge of the village and lets go of your collar.",
			"damage"
		)
		return
	imprison(village_id)


func summary() -> Dictionary:
	var out: Array = []
	for village_id: String in severity.keys():
		if int(severity[village_id]) > 0:
			out.append("%s=%s" % [village_id, label(int(severity[village_id]))])
	return {"wanted": out, "jailed": _jailed_in, "cells": _cells.size()}
