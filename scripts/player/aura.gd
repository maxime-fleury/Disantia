extends Node3D
## The cultivator's elemental aura.
##
## Two emitters and a lamp, reconfigured from whichever aura Cultivation says is
## active. The element decides the *character* of the motion — colour, how hard
## the motes orbit, how fast and wide they stream — while the cultivation stage
## decides the *scale*: a stage-one qi aura is a faint shimmer at the feet and a
## late-realm fire aura is a waist-high pillar you can see from across the valley.
##
## CPUParticles3D rather than its GPU twin on purpose: the GPU one needs compute
## support that the compatibility renderer and some browsers do not provide, and
## a hundred and fifty particles is not worth that risk.

@export var enabled: bool = true
## Global multiplier, for tuning the whole effect without touching an element.
@export_range(0.0, 3.0, 0.05) var intensity: float = 1.0

const RING_LIFETIME := 1.7
const RISE_LIFETIME := 1.4

## How solid a single mote is. Each one is a soft blob rather than a light source,
## so they are blended, not added: see `_make_material`.
const MOTE_ALPHA := 0.55
## The share of a mote's brightness that comes from emission rather than from its
## albedo, so it reads as lit rather than painted.
##
## A share, not a bonus: the two are summed before blending, so an emission *added*
## on top scales the mote past its own tint and clips a pale element to white. The
## albedo is dimmed by exactly this amount to keep the sum equal to the tint, which
## is why a qi-blue mote stays blue however bright it gets.
const MOTE_EMISSION := 0.35

var _ring: CPUParticles3D
var _rise: CPUParticles3D
var _light: OmniLight3D
var _ring_material: StandardMaterial3D
var _rise_material: StandardMaterial3D
var _mote_texture: ImageTexture
var _fade: Gradient
var _element: String = ""
var _power: float = -1.0


func _ready() -> void:
	if not enabled:
		return
	_fade = _make_fade()
	_mote_texture = _make_mote_texture()
	_ring_material = _make_material()
	_rise_material = _make_material()
	_ring = _make_emitter("Ring", _ring_material)
	_rise = _make_emitter("Rise", _rise_material)

	_light = OmniLight3D.new()
	_light.name = "AuraLight"
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.0, 0.0)
	add_child(_light)

	PlayerData.aura_changed.connect(_on_changed)
	Cultivation.cultivation_changed.connect(_on_changed)
	_refresh(true)


func _on_changed(_a: Variant = null, _b: Variant = null) -> void:
	_refresh(false)


func _process(_delta: float) -> void:
	# The stage can change without either signal firing (a load, a debug poke), so
	# the cheap check runs every frame: it compares two numbers and returns.
	_refresh(false)


func _refresh(force: bool) -> void:
	if not enabled:
		return
	var element: String = Cultivation.active_aura()
	var power: float = Cultivation.aura_power()
	if not force and element == _element and is_equal_approx(power, _power):
		return
	_element = element
	_power = power
	_apply(Cultivation.aura_def(element), power)


func _apply(defn: Dictionary, power: float) -> void:
	if defn.is_empty():
		return
	var emission: float = float(defn.get("emission", 0.0)) * intensity
	var spread: float = float(defn.get("spread", 0.0))
	var speed: float = float(defn.get("speed", 0.0))
	var orbit: float = float(defn.get("orbit", 0.0))
	# Everything visible ramps with the stage. `reach` is the single number that
	# makes a late-realm aura read as larger rather than just denser.
	var reach: float = 0.35 + 0.65 * power
	var busy: float = 0.30 + 0.70 * power

	var empty: bool = emission <= 0.0
	_ring.emitting = not empty
	_rise.emitting = not empty
	_ring.amount = maxi(1, int(round(emission * 0.55 * busy)))
	_rise.amount = maxi(1, int(round(emission * 0.45 * busy)))
	_light.light_energy = float(defn.get("light", 0.0)) * (0.30 + 0.70 * power) * intensity
	_light.light_color = defn.get("color", Color.WHITE) as Color
	if empty:
		return

	var tint: Color = defn.get("color", Color.WHITE) as Color
	var accent: Color = defn.get("accent", tint) as Color

	# The ring: motes circling the body, extruded into a column by the height.
	_ring.emission_ring_radius = (0.55 + 0.60 * power) * maxf(0.4, spread)
	_ring.emission_ring_height = 1.2 + 1.8 * power
	_ring.orbit_velocity_min = -0.9 * orbit * (0.6 + power)
	_ring.orbit_velocity_max = 0.9 * orbit * (0.6 + power)
	_ring.scale_amount_min = (0.045 + 0.05 * power) * reach
	_ring.scale_amount_max = (0.085 + 0.09 * power) * reach
	_ring_material.albedo_color = _mote_color(accent)
	_ring_material.emission = accent

	# The rise: a column drawn up off the ground.
	_rise.emission_sphere_radius = (0.35 + 0.45 * power) * maxf(0.4, spread)
	_rise.initial_velocity_min = (0.5 + 1.2 * power) * maxf(0.2, speed) * 0.6
	_rise.initial_velocity_max = (0.9 + 2.0 * power) * maxf(0.2, speed)
	_rise.scale_amount_min = (0.035 + 0.045 * power) * reach
	_rise.scale_amount_max = (0.075 + 0.085 * power) * reach
	_rise_material.albedo_color = _mote_color(tint)
	_rise_material.emission = tint


func _mote_color(tint: Color) -> Color:
	var albedo: float = 1.0 - MOTE_EMISSION
	return Color(tint.r * albedo, tint.g * albedo, tint.b * albedo, MOTE_ALPHA)


## The tint the body should glow with while meditating, so the trance glow and the
## aura are the same colour rather than two unrelated blues.
func meditation_color() -> Color:
	var defn: Dictionary = Cultivation.aura_def(_element)
	if defn.is_empty():
		return Color("6ec8ff")
	return defn.get("color", Color("6ec8ff")) as Color


func element() -> String:
	return _element


func power() -> float:
	return _power


func particle_count() -> int:
	if _ring == null or _rise == null:
		return 0
	return _ring.amount + _rise.amount


func _make_emitter(node_name: String, material: StandardMaterial3D) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.mesh = _make_particle_mesh(material)
	particles.lifetime = RING_LIFETIME if node_name == "Ring" else RISE_LIFETIME
	particles.emitting = false
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.randomness = 0.6
	# The ring is a hollow column around the body; the rise is a pool at the feet.
	particles.emission_shape = (
		CPUParticles3D.EMISSION_SHAPE_RING if node_name == "Ring"
		else CPUParticles3D.EMISSION_SHAPE_SPHERE
	)
	particles.direction = Vector3.UP
	particles.spread = 30.0
	particles.gravity = Vector3(0.0, 0.4, 0.0)
	particles.damping_min = 0.15
	particles.damping_max = 0.5
	particles.color_ramp = _fade
	particles.position = Vector3(0.0, 0.05, 0.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles


## A camera-facing quad, tinted by the material's albedo.
##
## Built by hand rather than as a QuadMesh because the per-particle colour rides
## in on the vertex colour channel: a mesh without that channel is a quad that
## renders black, which is precisely the bug this avoids.
func _make_particle_mesh(material: StandardMaterial3D) -> Mesh:
	var half: float = 0.5
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-half, -half, 0.0), Vector3(half, -half, 0.0),
		Vector3(half, half, 0.0), Vector3(-half, half, 0.0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK,
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0),
	])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE,
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Blended rather than additively lit. Additive is the usual choice for a glow,
	# but the motes stack dozens deep around the body and every one of them adds its
	# full brightness again, so the pile saturates and the aura turns into a white
	# slab no matter what colour the element is. Blending instead mixes toward the
	# hue, which is what keeps a fire aura red where it is dense and not just where
	# it is thin.
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	# A soft round mote. Without it every particle is the literal square the
	# geometry says it is, which reads as confetti rather than as energy.
	material.albedo_texture = _mote_texture
	# Doubly sided: a billboard seen from behind while the camera swings through
	# it must not disappear.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission_energy_multiplier = MOTE_EMISSION
	material.emission = Color.WHITE
	return material


## A soft round mote, drawn once at startup.
##
## Generated rather than shipped as a file so the aura has no asset dependency and
## nothing to lose in an import step. `alpha_cut` is deliberately left off: a hard
## cut would put the square edge back, just at a different radius.
func _make_mote_texture() -> ImageTexture:
	const SIZE := 64
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre: float = float(SIZE - 1) * 0.5
	for y in SIZE:
		for x in SIZE:
			var offset := Vector2(float(x) - centre, float(y) - centre) / centre
			var falloff: float = clampf(1.0 - offset.length(), 0.0, 1.0)
			# Smoothstep, so the core stays opaque while the rim reaches zero
			# smoothly instead of ending on a visible circle.
			var alpha: float = falloff * falloff * (3.0 - 2.0 * falloff)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


## Motes bloom in quickly, hold, then fade out over their life. The palette itself
## comes from the material, so one ramp serves every element.
##
## The end of the ramp matters as much as the start: a mote that is still at full
## opacity on its last frame does not fade, it vanishes, and a cloud of them
## blinking out together is what makes an aura look like a sheet of squares being
## switched off rather than like something dissipating.
func _make_fade() -> Gradient:
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.22, Color(1, 1, 1, 1.0))
	fade.add_point(0.65, Color(1, 1, 1, 1.0))
	return fade
