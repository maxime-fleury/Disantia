extends Node
## The first hour, told in six scenes.
##
## A body appears in a valley with an elder, a help strip and a task, and the one thing a game of
## this kind is supposed to have and this one did not is an *incident*: something that happens to
## you in the first ten minutes that you did not arrange and cannot undo, whose consequence you
## meet three hours later. Everything needed to build one was already here — decisions, the
## dialogue panel, reputation, the law, the sites, the clock — and nothing was arranging it.
##
## So: six scenes, in a fixed order, each of which fires the first time the world offers the right
## moment. Four rules, and they are the whole design:
##
##   * **In order, and one at a time.** Only the first scene that has not happened is ever
##     eligible, so the hour reads as a story rather than as a pile of triggers, and a player who
##     sprints to a village and then to a camp does not get four panels in four seconds.
##   * **A pause between them.** Fifteen seconds of walking. Without it two scenes land on top of
##     each other the moment a body crosses two boundaries, and the panel becomes a queue.
##   * **Never during a conversation, the tower, or the dark.** A scene is a moment, and a moment
##     cannot be had while somebody else is talking or while the body is climbing a staircase.
##   * **Every scene is a choice with a *price that arrives later*.** Not a buff: a debt. The
##     currency is reputation, which is the only number in this game that is paid back hours after
##     it moves — in a cheaper shelf, a watch that looks away, or a gate that suddenly will not
##     open. That delay is exactly what a scripted hour is for.
##
## The scenes themselves live in `Story.DECISIONS`, beside the conversations they share a panel
## and a record with. This file only decides *when*.

## Once a second. The conditions are all "the body is somewhere", and somewhere changes at the
## speed of walking.
const POLL := 1.0
## Seconds of walking between two scenes. Long enough that each one is its own moment.
const GAP := 15.0
## How near a village's walls the gate scene fires, and how near a raider camp the caravan does.
const APPROACH := 18.0
const CAMP_REACH := 44.0
## A road under the body, for the two scenes that happen on one.
const ROAD_WEIGHT := 0.35

## Whether the hour is being told. On in the game; the self-test switches it off, because a
## director that opens a panel when a body reaches a village will open one in the middle of a
## measurement as happily as in the middle of a walk — and a conversation roots the body, so
## every check after it fails for a reason that has nothing to do with what it was checking.
var enabled: bool = true

var _player: Node3D
var _terrain: Node
var _timer: float = 0.0
var _gap_left: float = GAP
## The scenes that have fired this session, in order. The save's own record is
## `PlayerData.decisions`, which is what the events are gated on; this is the same list, readable
## by a check without it having to know how a decision is stored.
var fired: Array = []
## How many times a village has come into reach. The notice scene waits for the *second* time:
## the first is the gate, and a warning about a paper on a post means nothing to somebody who has
## not yet been inside a wall.
var approaches: int = 0
var _was_near: bool = false


func _ready() -> void:
	var world: Node = get_tree().root.get_node_or_null("Main")
	if world != null:
		_player = world.get_node_or_null("Player") as Node3D
		_terrain = world.get_node_or_null("Terrain")
	# A save that has already been through the hour does not go through it again. The scenes are
	# gated on their own decisions anyway; this is so a loaded game does not spend its first
	# fifteen seconds waiting for a scene that has already been told.
	for id: String in Story.EVENTS:
		if PlayerData.decisions.has(id):
			fired.append(id)


func _process(delta: float) -> void:
	if not enabled:
		return
	poll(delta)


## One tick of the hour, stepped by hand. Separated from `_process` for the same reason the
## Hollow's is: the pause between scenes is fifteen seconds, and a check that has to wait fifteen
## real seconds for each of six scenes is a check nobody runs.
func poll(delta: float) -> void:
	if _player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = POLL
	_gap_left = maxf(0.0, _gap_left - POLL)
	_track_approach()
	var id: String = next_scene()
	if id == "":
		return
	fire(id)


## The scene that would fire right now, or "" — **only the first one not yet told**, which is what
## makes the hour a sequence rather than a set. Public so the whole thing can be walked through in
## a check without a body having to walk the valley for an hour.
func next_scene() -> String:
	if _player == null or Story.talking() or Tower.inside() or _gap_left > 0.0:
		return ""
	if PlayerData.unlit:
		return ""
	for id: String in Story.EVENTS:
		if Story.decided(id):
			continue
		# The first one outstanding decides: if its moment has not come, nothing later is
		# considered, however ready it looks.
		return id if _moment_for(id) else ""
	return ""


## Whether the world is offering the moment this scene belongs to.
func _moment_for(id: String) -> bool:
	var at: Vector3 = _player.global_position
	match id:
		"gate":
			# At the walls. The first time a body that has only seen a camp and a road comes up
			# against a village, somebody is standing in front of it asking questions.
			return Villages.near_site(at.x, at.z, APPROACH)
		"caravan":
			# Within sight of a raider camp: the cart is on its side *because* of the fire behind
			# it, and the scene only makes sense where the danger is visible.
			return _near_camp(at, CAMP_REACH)
		"notice":
			return approaches >= 2
		"mark":
			# Somewhere the body has been. The mark is scratched on a thing it has already walked
			# past, which is why this waits for a discovery rather than for a place.
			return PlayerData.found_landmarks.size() >= 1 \
				or bool(_hollow_taken())
		"tally":
			# On a road, between walls: the two kinds of place the game has, and this one is
			# deliberately neither of them.
			return _on_road(at) and not Villages.near_site(at.x, at.z, APPROACH)
		"oath":
			# After the first breakthrough. Everything before this is the valley introducing
			# itself; this is the first scene that assumes the body has *decided* something.
			return Cultivation.tier >= 1 or Cultivation.refinement >= 1
	return false


## Opens the scene. The effect of the choice is applied by `Story.choose`, exactly as it is for a
## conversation with a person — so this file cannot drift away from how a decision works.
func fire(id: String) -> bool:
	var opened: Dictionary = Story.begin_event(id)
	if opened.is_empty():
		return false
	fired.append(id)
	_gap_left = GAP
	Audio.play("ui_open", -4.0, 0.9)
	return true


## Called by the HUD when a scene is answered, so the pause starts from the answer rather than from
## the question — a scene read for a minute should not be followed by another one immediately.
func scene_closed() -> void:
	_gap_left = GAP


func scenes_done() -> int:
	return fired.size()


func scenes_total() -> int:
	return Story.EVENTS.size()


func summary() -> String:
	if fired.is_empty():
		return "nothing has happened yet"
	return "%d of %d: %s" % [fired.size(), scenes_total(), ", ".join(fired)]


func save_data() -> Dictionary:
	return {"fired": fired}


## Counts the times a village has come into reach, for the notice scene. Edge-triggered rather
## than a count of seconds spent inside one: "you have come back to these walls" is the event, and
## standing at a gate for a minute is not ten of them.
func _track_approach() -> void:
	var at: Vector3 = _player.global_position
	var near: bool = Villages.near_site(at.x, at.z, APPROACH)
	if near and not _was_near:
		approaches += 1
	_was_near = near


func _near_camp(at: Vector3, reach: float) -> bool:
	var camps: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	if camps == null or not camps.has_method("camps"):
		return false
	for camp: Dictionary in camps.call("camps"):
		var where: Vector3 = camp["position"]
		if Vector2(at.x - where.x, at.z - where.z).length() <= reach:
			return true
	return false


## A road under the body. Read from the terrain's own road weights rather than from a distance to
## a centre line, so the scene fires exactly where the ground *is* a road.
func _on_road(at: Vector3) -> bool:
	if _terrain == null or not _terrain.has_method("road_weight_at"):
		return false
	return float(_terrain.call("road_weight_at", at.x, at.z)) >= ROAD_WEIGHT


func _hollow_taken() -> bool:
	var cave: Node = get_tree().get_first_node_in_group("cave")
	if cave == null or not cave.has_method("taken"):
		return false
	return bool(cave.call("taken"))


func reset() -> void:
	fired = []
	approaches = 0
	_was_near = false
	# No pause *before* the first scene: the gap is there so two scenes do not land on top of each
	# other, and a body that has just arrived is not between two scenes, it is before all of them.
	_gap_left = 0.0
