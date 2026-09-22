extends Label3D
## The damage number that pops off a body when it is hit.
##
## It exists because a health bar answers "how much is left" and never answers "am I doing
## anything", and in a game whose entire progression is *numbers going up* that second
## question is the one the player is actually asking. Watching a five become a hundred is
## the payoff; a bar draining a little faster is not.
##
## Numbers rather than hit sparks, and readable numbers rather than a burst of particles:
## the whole point is the figure itself, so it is styled by its own size — a small hit is
## white and quiet, a big one is amber, larger, and slower to leave.
##
## One script, spawned ad hoc, and it frees itself. It is the only thing in the game that
## adds a node per event, which is why it is also the only one that carries its own lifetime
## rather than being cleaned up by a parent.

## Seconds on screen, and how far it drifts up in that time.
const LIFE := 0.85
const RISE := 1.35
## How far it wanders sideways, so two blows that land on the same frame do not print on
## top of each other.
const SPREAD := 0.32
## The amount at which a hit switches to the loud style.
const BIG_HIT := 80.0

var _age: float = 0.0
var _life: float = LIFE
var _drift: Vector3 = Vector3.UP
var _albedo: Color = Color.WHITE


## Spawns one and hands it back. A static factory rather than a scene, because a popup is
## four properties and a timer and a `PackedScene` would be a file to keep in step with this
## one for no gain.
static func spawn(parent: Node, at: Vector3, amount: float, tint: Color = Color.WHITE) -> Label3D:
	if parent == null or not is_instance_valid(parent) or amount <= 0.0:
		return null
	var popup: Label3D = (preload("res://scripts/ui/damage_popup.gd") as GDScript).new()
	parent.add_child(popup)
	var big: bool = amount >= BIG_HIT
	popup.text = ("%d" % roundi(amount)) if amount >= 10.0 else String.num(amount, 1)
	popup.font_size = 128 if big else 84
	popup.pixel_size = (0.0032 if big else 0.0026)
	popup.outline_size = 26
	popup.outline_modulate = Color(0.05, 0.03, 0.06, 0.92)
	popup.shaded = false
	popup.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Drawn over the body it came off: a number hidden inside a robe is not a number.
	popup.no_depth_test = true
	popup.render_priority = 4
	popup.global_position = at + Vector3(
		randf_range(-SPREAD, SPREAD), 0.0, randf_range(-SPREAD, SPREAD)
	)
	popup._albedo = tint.lightened(0.35) if not big else Color("ffd76e")
	popup.modulate = popup._albedo
	# A bigger hit hangs a little longer. It is the same trick as the louder colour and it
	# costs one multiplication.
	popup._life = LIFE * (1.25 if big else 1.0)
	popup.add_to_group("damage_popup")
	return popup


func _ready() -> void:
	# Slight sideways drift, so a run of hits on one enemy trails rather than stacks.
	_drift = Vector3(randf_range(-0.25, 0.25), RISE, randf_range(-0.25, 0.25))
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	var t: float = clampf(_age / _life, 0.0, 1.0)
	# Fast at first and easing off, which reads as an impact rather than as a float upwards.
	global_position += _drift * delta * (1.0 - t * 0.75)
	# The last third is the fade, so the number is fully legible while it is moving.
	var fade: float = clampf((1.0 - t) / 0.35, 0.0, 1.0)
	modulate = Color(_albedo.r, _albedo.g, _albedo.b, fade)
	if _age >= _life:
		queue_free()
