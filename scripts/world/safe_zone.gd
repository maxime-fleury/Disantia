extends Node3D
## The safe zone: the bubble over the home camp, where nothing hunts you.
##
## It is the answer to "where do I go when this goes badly". Raiders will not cross the
## edge, will not strike through it, and a beaten body wakes up inside it — so the camp
## is somewhere you can always retreat to and regroup, and it is where a player first
## learns that the world has places that behave differently.
##
## It is a *volume*, not a wall: the boundary is a sphere, so it also covers the air
## above the camp and a jump cannot be used to escape a raider mid-pounce. The
## membership test is a plain distance on all three axes for that reason — unlike a
## spirit zone, which is a region of ground and is deliberately flat.
##
## Enemies ask this node rather than keeping their own copy of the rule, so there is
## one definition of "safe" in the game.

## Big enough to hold the hut, the yard, the fence ring and both gateways.
@export var radius: float = 15.0
## The bubble is deliberately faint: it is a boundary marker, not weather.
@export var shell_alpha: float = 0.055
@export var pulse_seconds: float = 6.0
## Hollow: the dome is drawn, the inside is not.
@export var shell_thickness: float = 0.995

var _shell: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _phase: float = 0.0
var _inside: bool = false


func _ready() -> void:
	add_to_group("safe_zone")
	_build()


func _build() -> void:
	var tint: Color = Color("8fe3ff")

	# A sphere seen from outside is a dome and from inside is a sky; both readings are
	# right, and backface culling off means the shell is visible from either side.
	_shell = MeshInstance3D.new()
	_shell.name = "Shell"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 40
	sphere.rings = 20
	_shell.mesh = sphere
	_shell.material_override = _glow(tint, shell_alpha)
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.position = Vector3(0.0, radius * (1.0 - shell_thickness) + 0.2, 0.0)
	add_child(_shell)

	# A ring on the ground, at the height a fence would be, because the boundary is
	# what a player needs to see while running towards it — not the dome overhead.
	_ring = MeshInstance3D.new()
	_ring.name = "Boundary"
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.28
	torus.outer_radius = radius
	_ring.mesh = torus
	_ring.material_override = _glow(tint, 0.75)
	_ring.position = Vector3(0.0, 0.16, 0.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = tint
	_light.light_energy = 0.8
	_light.omni_range = radius * 1.4
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 2.4, 0.0)
	add_child(_light)


## One soft glowing surface, with emission as a share of the tint rather than a bonus
## on top of it, so the shell cannot sum past white and lose its colour.
func _glow(tint: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	const EMISSION_SHARE := 0.3
	material.albedo_color = Color(
		tint.r * (1.0 - EMISSION_SHARE), tint.g * (1.0 - EMISSION_SHARE),
		tint.b * (1.0 - EMISSION_SHARE), alpha)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = EMISSION_SHARE
	return material


var _player: Node3D


func _process(delta: float) -> void:
	# A slow breath, so a boundary that never moves still reads as alive rather than
	# as a hologram someone forgot to switch off.
	_phase = fmod(_phase + delta, maxf(0.5, pulse_seconds))
	var pulse: float = 0.5 + 0.5 * sin(_phase / maxf(0.5, pulse_seconds) * TAU)
	if _light != null:
		_light.light_energy = 0.65 + 0.35 * pulse
	if _ring != null:
		(_ring.material_override as StandardMaterial3D).albedo_color.a = 0.6 + 0.2 * pulse

	if _player == null or not is_instance_valid(_player):
		_player = get_parent().get_node_or_null("Player") as Node3D
		if _player == null:
			return
	var was_inside: bool = _inside
	_inside = contains(_player.global_position)
	if _inside == was_inside:
		return
	# Said once per crossing: the difference between a rule the player knows and one
	# they only ever feel as "the raiders stopped following me".
	PlayerData.log_message.emit(
		"The camp wards hold. Nothing here will follow you in." if _inside
		else "You step beyond the camp wards.",
		"info" if _inside else "damage"
	)


## True when a world position is inside the bubble. Spherical on purpose: the zone has
## to hold the air over the camp too, or a raider could be jumped over it.
func contains(point: Vector3) -> bool:
	var centre: Vector3 = _centre()
	var d: Vector3 = point - centre
	return d.length_squared() <= radius * radius


## Where a beaten body wakes up: on the ground at the middle of the camp, which is the
## levelled plateau.
func spawn_point() -> Vector3:
	var terrain: Node = get_parent().get_node_or_null("Terrain")
	if terrain != null and terrain.has_method("surface_height_at"):
		return Vector3(0.0, float(terrain.call("surface_height_at", 0.0, 0.0)) + 1.2, 0.0)
	return Vector3(0.0, 1.2, 0.0)


func _centre() -> Vector3:
	# The shell sits a little above the ground so the dome clears the hut; membership is
	# measured from the ground the camp actually stands on.
	return Vector3(global_position.x, global_position.y + 0.2, global_position.z)


## True while the player is standing inside it. Cached on the node so the HUD can ask
## without re-testing the distance every frame.
func player_inside() -> bool:
	return _inside
