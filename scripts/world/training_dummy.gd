extends StaticBody3D
## A stuffed post to hit.
##
## It carries the collision that makes it solid and the swing that sells the
## impact, and it owns its own stuffing: a post that runs out doubles the reward
## for the blow that emptied it, then spends a few seconds being restuffed — which
## is what stops a single post from being an infinite damage sink and gives the
## row of them something to do.
##
## The reward itself is paid by whoever struck, not here: this knows how much
## damage it took, and `take_hit` reports that back.

@export var max_stuffing: float = 60.0
## Stuffing regained per second, so a post is never permanently dead.
@export var restuff_per_second: float = 12.0
## Seconds a knocked-out post stays down before it starts refilling.
@export var restuff_delay: float = 2.5
## Radius the striker is told about, so the reach check and the post agree.
@export var hit_radius: float = 0.55

signal struck(post: Node3D, damage: float, knocked_out: bool)
signal recovered(post: Node3D)

var stuffing: float = 60.0

var _pivot: Node3D
var _tilt: float = 0.0
var _tilt_velocity: float = 0.0
var _tilt_axis: Vector3 = Vector3.RIGHT
var _down_timer: float = 0.0
var _knocked_out: bool = false
var _restuff_timer: float = 0.0


func _ready() -> void:
	add_to_group("training_post")
	stuffing = max_stuffing
	_pivot = get_node_or_null("Pivot") as Node3D
	set_process(true)


func _process(delta: float) -> void:
	# The swing is a damped spring rather than a tween: a post that was already
	# leaning when the next blow lands should add to the motion, not fight it.
	if absf(_tilt) > 0.0005 or absf(_tilt_velocity) > 0.0005:
		_tilt_velocity += (-26.0 * _tilt - 5.0 * _tilt_velocity) * delta
		_tilt += _tilt_velocity * delta
		_pivot.basis = Basis(_tilt_axis, _tilt)

	if _knocked_out:
		_down_timer -= delta
		if _down_timer <= 0.0:
			_knocked_out = false
			stuffing = 0.0
			recovered.emit(self)
		return

	if stuffing < max_stuffing:
		_restuff_timer += delta
		if _restuff_timer >= restuff_delay:
			stuffing = minf(max_stuffing, stuffing + restuff_per_second * delta)


## Applies damage from a blow that came from `from`, and leans the post away from
## the striker. Returns the damage actually taken.
func take_hit(damage: float, from: Vector3 = Vector3.ZERO) -> float:
	if _knocked_out:
		# Already down: the swing passes through it rather than beating a corpse.
		return 0.0
	var dealt: float = maxf(0.0, damage)
	stuffing = maxf(0.0, stuffing - dealt)

	var away := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if away.length_squared() > 0.0001:
		away = away.normalized()
		# Lean about the axis perpendicular to the blow, in the horizontal plane.
		_tilt_axis = Vector3(away.z, 0.0, -away.x).normalized()
	_tilt_velocity += clampf(dealt * 0.06, 0.35, 2.6)

	var emptied: bool = stuffing <= 0.0
	if emptied:
		_knocked_out = true
		_down_timer = restuff_delay
		_tilt_velocity = 3.2
	struck.emit(self, dealt, emptied)
	return dealt


func is_knocked_out() -> bool:
	return _knocked_out


func health_ratio() -> float:
	return clampf(stuffing / maxf(1.0, max_stuffing), 0.0, 1.0)


func placement() -> Vector3:
	return global_position
