extends Node3D
## The lamp on the belt.
##
## A night in this valley is a real night: the light goes, the raiders see further, the raids
## only ever land in the dark, and until now the only answers to it were a campfire and waiting
## for dawn. This is the third answer — a hooded lamp, bought from the traders at the home
## village and taken to the smith when its light stops being enough.
##
## **The radius is a function of the forge tier and nothing else.** That is the whole design:
## "upgrade the lamp" has to be a change you can *see* in the world rather than a number that
## moves in a panel, so each tier takes the lit circle out a few more metres and the player
## watches the road appear. It burns only when the sky is dark enough to need it, which keeps it
## a tool rather than a permanent glow — a lamp that is always on is a lamp nobody notices.
##
## It hangs on the *body* rather than on the character model. The model is scaled to a height by
## the animator, and a light under a scaled parent has its range scaled with it, which would make
## how far the lamp reaches depend on how tall the character happens to be.

## The piece in the forge's catalogue this is the worn form of. One string, so the shop shelf and
## the smith's anvil and this light cannot come to disagree about what the lamp is called.
const PIECE_ID := "traveller_lamp"

## Lit radius in metres, by forge tier. Index 0 is "not owned" and is deliberately dark: the lamp
## is bought, never found, and a lamp that lights before it is paid for is a lamp nobody buys.
const RADIUS: Array = [0.0, 7.0, 10.5, 14.0, 17.0, 20.5]

## How dark it has to be before the wick is lit, 0 (noon) to 1 (deep night), from the clock.
## A quarter is dusk: the hour after the sun has gone and before anything can see in the dark.
const DARK_ENOUGH := 0.25

## Where the lamp sits, in body space: the left hip, at about a belt's height.
const HANG := Vector3(-0.30, 1.00, 0.10)

## The colour of the light. Deliberately yellow rather than white, because the whole point of
## carrying a lamp is that it is *warm* in a valley that gets cold and dark at the same hour.
const FLAME := Color("ffce8a")

var _light: OmniLight3D
var _flame: MeshInstance3D
## What was lit last frame, so the log only carries a change and not a state.
var _was_lit: bool = false


func _ready() -> void:
	name = "Lantern"
	_build()
	Forge.changed.connect(_refresh)
	_refresh()


## The light and the little flame it comes out of. A light with nothing behind it reads as a
## bug in the renderer; a lamp you can see on the body reads as something the character is
## carrying, which is most of why anybody wants it.
func _build() -> void:
	_light = OmniLight3D.new()
	_light.name = "Lamp"
	_light.position = HANG
	_light.light_color = FLAME
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)

	_flame = MeshInstance3D.new()
	_flame.name = "Wick"
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	mesh.radial_segments = 10
	mesh.rings = 6
	_flame.mesh = mesh
	_flame.position = HANG
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = FLAME
	material.emission_enabled = true
	material.emission = FLAME
	material.emission_energy_multiplier = 2.2
	_flame.material_override = material
	add_child(_flame)


func _process(_delta: float) -> void:
	_refresh()


## How far the lamp reaches right now, in metres. Zero when it is not owned or not lit, which is
## the number anything else in the game should ask rather than reading the table.
func reach() -> float:
	return radius_for_tier(Forge.tier_of(PIECE_ID))


## What a tier would reach, whether or not it is owned — the figure the shop and the anvil
## advertise, so a shelf cannot promise a light the lamp will not give.
func radius_for_tier(tier: int) -> float:
	return RADIUS[clampi(tier, 0, RADIUS.size() - 1)]


func is_owned() -> bool:
	return Forge.tier_of(PIECE_ID) > 0


func is_lit() -> bool:
	return _light != null and _light.visible


## What the lamp is doing, for the HUD and the suite: the tier, the metres it throws, and whether
## the hour has lit it.
func summary() -> Dictionary:
	return {
		"owned": is_owned(),
		"tier": Forge.tier_of(PIECE_ID),
		"radius": reach(),
		"lit": is_lit(),
		"darkness": Clock.darkness(),
	}


func _refresh() -> void:
	if _light == null:
		return
	var radius: float = reach()
	# Lit only when it is dark enough to matter. Two thresholds rather than one — on at a quarter
	# of darkness, off below a fifth — because a lamp flickering on and off around a single
	# number would read as a broken shader at exactly the hour the player is watching it.
	var want: bool = radius > 0.0 and Clock.darkness() >= (0.18 if is_lit() else DARK_ENOUGH)
	if want:
		_light.omni_range = radius
		# Energy falls as the circle widens, so a rank five lamp lights a *street* and a rank one
		# lights a *room* rather than a small sun.
		_light.light_energy = 2.4 - 0.14 * float(Forge.tier_of(PIECE_ID))
	_light.visible = want
	_flame.visible = want
	if want and not _was_lit:
		PlayerData.log_message.emit(Loc.fill("The lamp takes. %d metres of road.", [int(radius)]),
			"info")
	elif not want and _was_lit:
		PlayerData.log_message.emit("The lamp goes out.", "info")
	_was_lit = want


## The socket the worn piece sits in, so anything reading the body's gear can find the lamp
## without knowing what it is called.
func slot() -> String:
	return "lamp"
