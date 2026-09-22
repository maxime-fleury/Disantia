extends Area3D
## A thrown bolt of qi: the Ninth's second weapon, and the only thing in Disantia that can
## hurt you from further than a stride away.
##
## Everything else in the game is built on one promise — step back and you are safe. It is
## what makes a raider's wind-up a defence rather than a coin flip, and it is why a camp can
## be lost and left. A final fight that was the same fight with bigger numbers would break
## nothing and mean nothing, so the Ninth takes that promise away: at range it throws, and
## the way to survive a throw is to close rather than to retreat.
##
## Deliberately slow, deliberately telegraphed and deliberately visible: the bolt is a lit
## sphere crossing open ground, so the answer — move sideways, or move in — is legible on
## the first one you ever see.

const LIFETIME := 4.0
## Physics layer for the world and bodies: the same one the ground and the player are on.
const HIT_MASK := 1

var _velocity: Vector3 = Vector3.ZERO
var _damage: float = 0.0
var _age: float = 0.0
var _shooter: Node = null
var _tint: Color = Color("6ec8ff")
## Thrown by the player rather than at them. One projectile serves both, because the two
## behave identically — leave a hand, cross open ground, burst on what it touches — and a
## second copy of that would drift out of step with the first within a week.
var _from_player: bool = false


## Throws one from `at` towards `direction`. A static factory for the same reason the damage
## popup is one: three properties and a timer do not need a scene file.
static func spawn(parent: Node, at: Vector3, direction: Vector3, damage: float,
		speed: float, tint: Color, shooter: Node = null) -> Area3D:
	if parent == null or not is_instance_valid(parent) or damage <= 0.0:
		return null
	var bolt: Area3D = (preload("res://scripts/enemy/qi_bolt.gd") as GDScript).new()
	parent.add_child(bolt)
	var flat := Vector3(direction.x, 0.0, direction.z)
	bolt._velocity = (flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD) * speed
	bolt._damage = damage
	bolt._shooter = shooter
	bolt._from_player = shooter != null and is_instance_valid(shooter) \
		and shooter.is_in_group("player")
	bolt.global_position = at
	bolt._build(tint)
	bolt.add_to_group("qi_bolt")
	return bolt


func _build(tint: Color) -> void:
	_tint = tint
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	add_child(shape)
	# Only the world and bodies: a bolt that collided with another bolt would be a fight
	# between its own projectiles.
	collision_mask = HIT_MASK
	monitoring = true

	var body := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.34
	ball.height = 0.68
	ball.radial_segments = 12
	ball.rings = 6
	body.mesh = ball
	body.material_override = _glow(tint)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)

	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 2.4
	light.omni_range = 7.0
	light.shadow_enabled = false
	add_child(light)

	body_entered.connect(_on_body_entered)


func _glow(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 1.0)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 1.0
	return material


func _physics_process(delta: float) -> void:
	_age += delta
	global_position += _velocity * delta
	if _age >= LIFETIME:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == _shooter:
		return
	if _from_player:
		# The player's own ball bursts on whatever it meets, including the ground and a post:
		# a throw that sailed on through a rock would read as a hit that did not happen.
		if body.has_method("take_hit") and _shooter is Node3D:
			body.call("take_hit", _damage, (_shooter as Node3D).global_position)
		queue_free()
		return
	if body.has_method("take_enemy_blow"):
		body.call("take_enemy_blow", _damage, self)
	queue_free()


## Read by the tests: what this bolt is carrying, and where it is going.
func damage() -> float:
	return _damage


func tint() -> Color:
	return _tint


func from_player() -> bool:
	return _from_player


func speed() -> float:
	return Vector3(_velocity.x, 0.0, _velocity.z).length()
