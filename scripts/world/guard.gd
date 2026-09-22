extends "res://scripts/world/quest_npc.gd"
## A village watchman.
##
## The point of a guard is not that it stands in a square looking official. It is the only
## **actor** in the world that is neither the player nor a threat: it has a beat, it decides
## things about you, and it does something the world would not otherwise do — it makes the
## roads between the villages *somebody's* roads, and it makes a village a place with a side.
##
## Two jobs, and the second is the one that changed the game:
##
##   * **It fights raiders.** A raid on a village is not a cutscene and not a scripted wave: it
##     is the same enemies the camps spawn, walking at the same gate, with the watch standing in
##     front of it. Whatever the guard kills stays killed, and whatever gets past it is the
##     player's problem.
##   * **It enforces the law.** A body that has been wanted twice in a village is a body these
##     men come at, and a body that loses that fight is put behind the watch house's door. That
##     is the whole risk system: it exists so that "what happens if I hit somebody" has an
##     answer that is not "nothing, ever".
##
## Walking is deliberately crude — the same trick the road walkers use: walk towards a point,
## snap to the ground under you. What the player reads from across a square is that a figure is
## *moving with a purpose*, and that costs four lines rather than a navmesh.

enum State { PATROL, CHASE, STRIKE, DOWN }

@export var village_id: String = ""
@export var guard_name: String = "The Watch"
## The beat, in world XZ. Walked in order and looped.
@export var route: PackedVector2Array = PackedVector2Array()
@export var walk_speed: float = 1.55
@export var chase_speed: float = 4.5
@export var attack_range: float = 2.5
@export var attack_damage: float = 17.0
@export var attack_interval: float = 1.45
@export var windup: float = 0.4
@export var max_hp: float = 260.0
## How far a watchman notices anything. Shorter than a raider's aggro, because a guard that
## spots you across a valley is a guard that never lets you get anywhere.
@export var sight: float = 19.0
@export var post_height: float = 2.7
## Beaten watchmen are carried back to the watch house and are on their feet again in this long.
@export var recover_seconds: float = 55.0
@export var plate_height: float = 2.66

var hp: float = 260.0
var state: int = State.PATROL

var _leg: int = 1
var _state_timer: float = 0.0
var _down_timer: float = 0.0
var _swing_at: float = -1.0
var _attack_timer: float = 0.0
var _scan_at: float = 0.0
var _target: Node3D
var _target_position: Vector2 = Vector2.ZERO
var _warned_at: float = -99.0
var _name_plate: Label3D
var _terrain: Node


func _ready() -> void:
	super()
	remove_from_group("quest_npc")
	add_to_group("guard")
	add_to_group("npc")
	# A swing can land on a watchman, and when it does it is a crime — the same group the
	# villagers are in, for the same reason.
	add_to_group("bystander")
	hp = max_hp
	_terrain = get_tree().root.get_node_or_null("Main/Terrain")
	_build_plate()
	if route.size() >= 2:
		_target_position = route[0]


## A watchman has nothing to say, so it must not wear the elder's marker.
func marker_state() -> String:
	return ""


func wanted_clips() -> Array:
	return ["Idle", "Walk"]


func _build_plate() -> void:
	_name_plate = Label3D.new()
	_name_plate.name = "NamePlate"
	_name_plate.text = guard_name
	_name_plate.font_size = 96
	_name_plate.pixel_size = 0.0045
	_name_plate.outline_size = 18
	_name_plate.outline_modulate = Color(0.05, 0.05, 0.08)
	_name_plate.modulate = Color(0.86, 0.9, 0.96)
	_name_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_plate.no_depth_test = true
	_name_plate.render_priority = 3
	_name_plate.position = Vector3(0.0, plate_height, 0.0)
	add_child(_name_plate)


# ------------------------------------------------------------------- the beat

func _process(delta: float) -> void:
	super(delta)
	_scan_at -= delta
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if state == State.DOWN:
		_down_timer -= delta
		if _down_timer <= 0.0:
			_stand_up()
		return
	if _swing_at >= 0.0:
		_swing_at -= delta
		if _swing_at <= 0.0:
			_swing_at = -1.0
			_land()
		return
	if _scan_at <= 0.0:
		_scan_at = 0.4
		_choose_target()
	var enemy: Node3D = _target if _target != null and is_instance_valid(_target) else null
	if enemy != null and state != State.PATROL:
		_hunt(enemy, delta)
		return
	# No one to fight: the beat, in daylight, and the post after dusk. A village whose guards
	# walked all night would have made the dark pointless, and the dark is the one thing on the
	# clock the player can plan around.
	if Clock.gates_open():
		_walk_beat(delta)
	else:
		_hold_post(delta)


## Something worth walking at: a raider that has wandered into the village's business, or the
## player, who has to have *earned* it. Order matters — a watchman with a raider in front of him
## and a wanted player behind him deals with the raider, which is also how the world is supposed
## to read: the monsters come first.
func _choose_target() -> void:
	var player: Node3D = _player_node()
	if Law.guards_hostile(village_id) and player != null \
			and _flat(player.global_position) <= sight:
		_target = player
		state = State.CHASE
		return
	var best: Node3D
	var best_distance: float = sight
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and bool(enemy.call("is_dead")):
			continue
		if enemy.has_method("is_pacified") and bool(enemy.call("is_pacified")):
			continue
		var d: float = _flat(enemy.global_position)
		if d <= best_distance:
			best_distance = d
			best = enemy
	if best != null:
		_target = best
		state = State.CHASE
		return
	_target = null
	state = State.PATROL
	# Watched, not hunted: the rung below a fight gets a line rather than a swing, so a player
	# who did something small can walk in and be *told* about it.
	if Law.wanted_at(village_id) == 1 and player != null and _flat(player.global_position) <= 8.0:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _warned_at > 24.0:
			_warned_at = now
			PlayerData.log_message.emit(
				"%s: \\\"We know your face. Walk quietly.\\\"" % guard_name, "damage"
			)


func _hunt(target: Node3D, delta: float) -> void:
	var to_target: Vector2 = Vector2(
		target.global_position.x - global_position.x,
		target.global_position.z - global_position.z
	)
	var distance: float = to_target.length()
	if distance > attack_range:
		var step: Vector2 = to_target.normalized() * chase_speed * delta
		_move_by(step)
		_face(step)
		return
	_play("Idle")
	if _attack_timer > 0.0 or _swing_at >= 0.0:
		return
	_attack_timer = attack_interval
	_swing_at = windup
	_play("Walk")


func _land() -> void:
	var target: Node3D = _target
	if target == null or not is_instance_valid(target):
		return
	if _flat(target.global_position) > attack_range + 0.5:
		return
	if not target.has_method("take_hit"):
		return
	var dealt: float = float(target.call("take_hit", attack_damage, global_position))
	Audio.play_at("impact", global_position, -4.0, 0.95)
	# The player is not a raider and is not killed by the watch: a body that has been beaten down
	# in a village square is a body that gets *arrested*, which is the whole design of the ladder.
	if target == _player_node():
		if PlayerData.get_value("hp") <= PlayerData.get_cap("hp") * 0.25:
			Law.arrest(target.global_position, village_id)
			_target = null
			state = State.PATROL
			return
		if dealt > 0.0:
			PlayerData.log_message.emit(
				"%s: \\\"Enough. Put it down.\\\"" % guard_name, "damage"
			)


func _walk_beat(delta: float) -> void:
	if route.size() < 2:
		return
	var here := Vector2(global_position.x, global_position.z)
	var step: Vector2 = _target_position - here
	if step.length() <= 0.6:
		_leg = (_leg + 1) % route.size()
		_target_position = route[_leg]
		_play("Idle")
		_state_timer = 1.6
		return
	if _state_timer > 0.0:
		_state_timer -= delta
		return
	var motion: Vector2 = step.normalized() * walk_speed * delta
	_move_by(motion)
	_face(motion)
	_play("Walk")


## After dusk: stand at the post by the gate, facing out. Somebody has to be awake.
func _hold_post(delta: float) -> void:
	if route.is_empty():
		_play("Idle")
		return
	var post: Vector2 = route[0]
	var step: Vector2 = post - Vector2(global_position.x, global_position.z)
	if step.length() > 0.8:
		_move_by(step.normalized() * walk_speed * delta)
		_face(step)
		_play("Walk")
		return
	_play("Idle")
	_face(Vector2(post.x - _centre_flat().x, post.y - _centre_flat().y))


func _centre_flat() -> Vector2:
	var site: Dictionary = Haven.site(village_id)
	if site.is_empty():
		return Vector2.ZERO
	var centre: Vector3 = site["centre"]
	return Vector2(centre.x, centre.z)


func _move_by(motion: Vector2) -> void:
	if motion.length_squared() <= 0.000001:
		return
	global_position = Vector3(
		global_position.x + motion.x,
		global_position.y,
		global_position.z + motion.y
	)
	if _terrain != null and _terrain.has_method("surface_height_at"):
		global_position.y = float(_terrain.call(
			"surface_height_at", global_position.x, global_position.z
		))


func _face(direction: Vector2) -> void:
	if _rig == null or direction.length_squared() <= 0.000001:
		return
	_rig.rotation.y = atan2(direction.x, direction.y)


func _flat(at: Vector3) -> float:
	return Vector2(at.x - global_position.x, at.z - global_position.z).length()


func _player_node() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


# ------------------------------------------------------------------- the fight

## A blow from the player. A watchman is a body, not a wall: it can be beaten, and beating it is
## the worst thing a player can do short of murdering a village — which is why it is the crime
## that puts them on the third rung immediately.
func take_hit(damage: float, from: Vector3 = Vector3.ZERO) -> float:
	if state == State.DOWN:
		return 0.0
	var dealt: float = maxf(0.0, damage)
	hp = maxf(0.0, hp - dealt)
	Law.add_crime("assault", village_id, "%s was struck" % guard_name)
	_target = _player_node()
	state = State.CHASE
	_swing_at = -1.0
	_attack_timer = 0.6
	_flinch()
	if hp <= 0.0:
		_fall()
	return dealt


func _flinch() -> void:
	if _rig == null:
		return
	var tween := create_tween()
	tween.tween_property(_rig, "rotation:x", deg_to_rad(-14.0), 0.08)
	tween.tween_property(_rig, "rotation:x", 0.0, 0.4)


func _fall() -> void:
	state = State.DOWN
	_down_timer = recover_seconds
	_target = null
	Law.add_crime("murder", village_id, "%s was killed in the open" % guard_name)
	if _rig != null:
		_rig.rotation.x = deg_to_rad(-80.0)
		_rig.position.y = 0.2
	Audio.play_at("drop", global_position, -2.0, 0.8)


func _stand_up() -> void:
	hp = max_hp
	state = State.PATROL
	if _rig != null:
		_rig.rotation.x = 0.0
		_rig.position.y = 0.0
	_play("Idle")


## The watch's own read on things, for the boot log and the tests.
func status() -> Dictionary:
	return {"village": village_id, "hp": hp, "state": State.keys()[state], "route": route.size()}
