extends Node3D
## The character's strike — the player's only offensive verb.
##
## Finds the nearest training post within reach and lands the blow a fraction of a
## second later, so the impact, the sound and the post's lean all happen at the
## bottom of the swing rather than the instant the key went down. Swinging at
## empty air still animates and still whooshes; it just does not pay, which is
## what makes the posts worth walking to.

## Reach is measured to the target's centre, and a raider's capsule is a good deal
## wider than a post's, so the two share this one number rather than the striker
## knowing about either.
@export var reach: float = 2.7
@export var cooldown: float = 0.5
## Seconds between the key going down and the blow landing.
@export var windup: float = 0.16
## ATTACK xp per point of damage actually dealt.
@export var xp_per_damage: float = 0.8
## Multiple of the normal reward for the blow that empties a post.
@export var knockout_bonus: float = 2.0

var _player: CharacterBody3D
var _animator: Node
var _cooldown: float = 0.0
var _pending: Node3D
var _pending_timer: float = 0.0
var _swings: int = 0
var _hits: int = 0
var _knockouts: int = 0
## The blow's own dice: the angle, whether it crushes. Seeded from the clock at startup and
## kept, rather than a fresh generator per swing — a generator built once per frame in a
## tight loop is the sort of thing that quietly costs more than the thing it is measuring.
var _rng := RandomNumberGenerator.new()


func _ready_roll() -> void:
	_rng.randomize()


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player != null:
		_animator = _player.get_node_or_null("Model")
	_ready_roll()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("strike"):
		return
	# A click is both the strike and the way out of the freed pointer: with the mouse
	# loose the first click belongs to the camera, which is what re-captures it. Only a
	# captured pointer swings, or every click on the HUD would also be a swing.
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	get_viewport().set_input_as_handled()
	attempt()


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _pending == null:
		return
	_pending_timer -= delta
	if _pending_timer > 0.0:
		return
	var post: Node3D = _pending
	_pending = null
	_land(post)


func can_strike() -> bool:
	if _player == null or _cooldown > 0.0:
		return false
	if _player.has_method("is_ready_to_act") and not _player.is_ready_to_act():
		return false
	return true


## Swings at whatever is in reach. Public so the HUD and the tests can drive the
## same path a key press takes.
func attempt() -> bool:
	if not can_strike():
		if _cooldown > 0.0:
			Audio.play("ui_click", -16.0, 0.7)
		return false
	_cooldown = cooldown
	_swings += 1
	if _animator != null and _animator.has_method("play_attack"):
		_animator.play_attack()
	Audio.play_at("whoosh", global_position, -4.0, randf_range(0.9, 1.15))

	var target: Node3D = nearest_target()
	if target == null:
		return true
	_pending = target
	_pending_timer = windup
	return true


func _land(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	# The blow, with the crushing roll inside it. Asked of the body rather than worked out
	# here, because the roll belongs to the attainment that grants it — and because a mean over
	# a thousand swings is the only honest way to test a one-in-five chance.
	var damage: float = PlayerData.strike_damage_rolled(_rng)
	var dealt: float = float(target.call("take_hit", damage, global_position))
	_cleave(target, damage)
	if dealt <= 0.0:
		Audio.play_at("ui_click", target.global_position, -10.0, 0.6)
		return
	_hits += 1
	var finished: bool = _is_defeated(target)
	if finished:
		_knockouts += 1
	var reward: float = dealt * xp_per_damage * (knockout_bonus if finished else 1.0)
	PlayerData.gain("attack", reward)
	Audio.play_at("impact", target.global_position, 0.0, randf_range(0.92, 1.08))
	if finished:
		Audio.play_at("drop", target.global_position, -2.0, 0.9)
		PlayerData.log_message.emit(
			"%s. ATTACK +%s." % [
				"The raider falls" if target.is_in_group("enemy") else "The post comes apart",
				String.num(reward, 1),
			],
			"gain"
		)


## Cleave: a blow that carries into a second body.
##
## The strongest thing a fist learns, and deliberately the *first* threshold rather than the
## last, because what it changes is not a number — it is which fights are worth taking. One
## raider at a time is a duel that the retreat rule makes safe; two standing close enough is
## suddenly a reason to walk into the middle of a camp, and the player who has Cleave reads
## every camp on the map differently from the player who does not.
##
## The second body is chosen as the nearest *other* thing in reach, measured flat like every
## other distance in a fight. A post is a legitimate carrier too: whatever the first blow
## landed on, the second one is picked by distance alone.
func _cleave(first: Node3D, damage: float) -> void:
	var fraction: float = PlayerData.cleave_fraction()
	if fraction <= 0.0:
		return
	var radius: float = PlayerData.cleave_radius()
	var here: Vector2 = Vector2(first.global_position.x, first.global_position.z)
	var best: Node3D
	var best_distance: float = radius
	for group: String in ["enemy", "training_post"]:
		for node in get_tree().get_nodes_in_group(group):
			var other := node as Node3D
			if other == null or not is_instance_valid(other) or other == first:
				continue
			if _is_defeated(other):
				continue
			var flat: Vector2 = Vector2(other.global_position.x, other.global_position.z)
			var distance: float = here.distance_to(flat)
			if distance <= best_distance:
				best_distance = distance
				best = other
	if best == null:
		return
	var carried: float = float(best.call("take_hit", damage * fraction, global_position))
	if carried <= 0.0:
		return
	PlayerData.gain("attack", carried * xp_per_damage)


## A target is finished either way it can be: a post when its stuffing runs out, a
## raider when its health does. The striker asks rather than knowing which is which.
func _is_defeated(target: Node3D) -> bool:
	if target.has_method("is_knocked_out") and bool(target.call("is_knocked_out")):
		return true
	if target.has_method("is_dead") and bool(target.call("is_dead")):
		return true
	return false


## Nearest thing within reach that can be struck, measured on the ground plane so a
## target on a slope is still reachable. Posts and raiders are treated identically:
## both answer `take_hit`, so the swing does not care which it found.
func nearest_target() -> Node3D:
	var best: Node3D
	var best_distance: float = reach
	var here: Vector2 = Vector2(global_position.x, global_position.z)
	for group: String in ["training_post", "enemy"]:
		for node in get_tree().get_nodes_in_group(group):
			var target := node as Node3D
			if target == null or not is_instance_valid(target):
				continue
			if _is_defeated(target):
				continue
			var there: Vector2 = Vector2(target.global_position.x, target.global_position.z)
			var distance: float = here.distance_to(there)
			if distance <= best_distance:
				best_distance = distance
				best = target
	return best


## Kept as the old name so nothing that asked for a post breaks; it now answers with
## whatever is actually in reach.
func nearest_post() -> Node3D:
	return nearest_target()


## Target currently in reach, for the HUD to advertise.
func target() -> Node3D:
	return nearest_target()


func stats() -> Dictionary:
	return {"swings": _swings, "hits": _hits, "knockouts": _knockouts}
