extends Node3D
## The plate over the cultivator's head: the stage you have reached, and your power
## level underneath it.
##
## There were bars here, and they were the wrong thing to hang over a character. A bar
## is a *local* reading — how full a pool is right now — and the pools are already on the
## HUD where they can be read without looking away from the fight; the plate's job is the
## one thing the HUD cannot say at a glance, which is *how strong this body has become*.
## Health and qi also spend their whole time near full, so two bars over a head are two
## bars that mostly say nothing.
##
## So the plate carries one number, and the number is styled by its own size: a quiet
## white figure when you are nobody, embers when you have started, fire when the training
## shows, then lightning, then a colour that will not settle. The styling is driven by the
## power level itself rather than by cultivation tier, because the number on screen is
## what the player is watching and the reward for it climbing should be visible in it.
##
## Kept as world geometry rather than drawn onto the HUD on purpose: a doorframe, a tree
## and a hut all occlude it correctly without any projection maths here, and it follows
## the body for free.
##
## Everything is billboarded, so the number stays legible from any camera angle.

const STAGE_Y := 2.34
const POWER_Y := 2.02
const STAGE_FONT_SIZE := 30
const POWER_FONT_SIZE := 54
## Pixel size of the labels. Text is `font_size * pixel_size` metres tall.
@export var label_pixel_size: float = 0.0042

## The glow behind the number is a second label wearing a wide outline rather than a
## real light: an OmniLight3D here would light the ground and the character's own face,
## and a bloom pass is not available on the compatibility renderer the web build needs.
## Two coplanar labels need an explicit draw order for the same reason the old bars did —
## two transparent quads at one depth leave the renderer free to pick, and the halo
## losing that coin toss would take the number with it.
const HALO_PRIORITY := 1
const TEXT_PRIORITY := 2

@export var show_stage: bool = true

## The tiers, in ascending order of power. `style` names the animation; everything else
## is the look. Kept as a table rather than as a match statement in `_process` because
## the interesting part of a tier — its colour and its behaviour — should be readable in
## one place, and because the self-test walks this to prove the tiers actually escalate.
const POWER_TIERS: Array = [
	{
		"at": 0, "name": "still", "style": "calm",
		"tint": "e8eef6", "glow": "9fc0d8",
		"halo_outline": 22.0, "text_outline": 8.0, "scale": 1.00,
	},
	{
		"at": 2000, "name": "kindled", "style": "ember",
		"tint": "ffe9a8", "glow": "ffb347",
		"halo_outline": 26.0, "text_outline": 9.0, "scale": 1.06,
	},
	{
		"at": 5200, "name": "burning", "style": "fire",
		"tint": "ffcf7a", "glow": "ff5f1f",
		"halo_outline": 32.0, "text_outline": 10.0, "scale": 1.13,
	},
	{
		"at": 12000, "name": "storming", "style": "storm",
		"tint": "dff6ff", "glow": "4fc3ff",
		"halo_outline": 36.0, "text_outline": 11.0, "scale": 1.19,
	},
	{
		"at": 28000, "name": "ascendant", "style": "rainbow",
		"tint": "ffffff", "glow": "ff8fe0",
		"halo_outline": 42.0, "text_outline": 12.0, "scale": 1.28,
	},
]

var _power_text: Label3D
var _power_halo: Label3D
var _stage_text: Label3D
var _tier: Dictionary = {}
var _phase: float = 0.0
## Set when the power level goes up, then decays. The one moment in this plate that is
## worth a flourish: it is the only feedback the player gets for every rank they earned.
var _flash: float = 0.0
var _shown_power: int = -1


func _ready() -> void:
	build()
	PlayerData.stats_changed.connect(_refresh)
	Cultivation.cultivation_changed.connect(_refresh)
	# Kept ticking while a panel is open so a stylised number does not freeze mid-flicker
	# behind the settings screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh()
	set_process(true)


func build() -> void:
	if show_stage:
		_stage_text = _add_label("StageText", STAGE_Y, STAGE_FONT_SIZE, Color("ffe9b0"))
	# The halo is added first so the text draws over it, and carries the wide outline.
	_power_halo = _add_label("PowerHalo", POWER_Y, POWER_FONT_SIZE, Color(1, 1, 1, 0.5))
	_power_halo.outline_size = 26
	_power_halo.render_priority = HALO_PRIORITY
	_power_text = _add_label("PowerText", POWER_Y, POWER_FONT_SIZE, Color.WHITE)
	_power_text.render_priority = TEXT_PRIORITY


func _refresh(_a: Variant = null, _b: Variant = null) -> void:
	var power: int = PlayerData.power_level()
	if _shown_power >= 0 and power > _shown_power:
		# Any gain flashes, however small, so a rank earned mid-run is never silent.
		_flash = 1.0
	_shown_power = power
	_tier = tier_for(power)
	if _power_text != null:
		_power_text.text = group(power)
	if _stage_text != null:
		_stage_text.text = "%s · %s" % [Cultivation.realm_name(), _numeral(Cultivation.stage())]


## The tier a power level falls in. Public because the HUD and the self-test both ask
## what the plate is currently wearing, and neither should be re-deriving the thresholds.
func tier_for(power: int) -> Dictionary:
	var chosen: Dictionary = POWER_TIERS[0]
	for entry: Dictionary in POWER_TIERS:
		if power >= int(entry["at"]):
			chosen = entry
	return chosen


func tier() -> Dictionary:
	return _tier


func power_label() -> String:
	return _power_text.text if _power_text != null else ""


func _process(delta: float) -> void:
	if _power_text == null or _tier.is_empty():
		return
	_phase += delta
	_flash = maxf(0.0, _flash - delta * 1.6)

	var style: String = String(_tier["style"])
	var tint := Color(String(_tier["tint"]))
	var glow := Color(String(_tier["glow"]))
	# Everything below writes these four: the number's colour, its brightness, the halo's
	# brightness and where the pair sits. Each style is a different way of moving them.
	var heat: float = 0.0
	var punch: float = 0.0
	var bob: float = 0.0
	var slide: float = 0.0

	match style:
		"calm":
			# A slow breath, so a still number still reads as alive. Nothing more: this
			# is the tier a player sits in for their first hour and it must not shout.
			heat = 0.35 + 0.12 * sin(_phase * 1.1)
		"ember":
			heat = 0.5 + 0.22 * sin(_phase * 2.4) + 0.08 * sin(_phase * 6.1)
		"fire":
			# Two frequencies that do not divide into each other, so the flicker never
			# settles into a rhythm the eye can predict. A single sine reads as a pulse,
			# which is a lamp; the point here is a flame.
			heat = 0.62 + 0.3 * sin(_phase * 7.3) * sin(_phase * 11.7 + 1.0)
			heat += 0.1 * sin(_phase * 23.0)
			# Fire leans hot as it brightens: the tint itself moves, rather than only
			# its brightness.
			tint = tint.lerp(Color("ff7a2f"), 0.22 * (0.5 + 0.5 * sin(_phase * 4.1)))
			glow = glow.lerp(Color("ffd06a"), 0.18 * (0.5 + 0.5 * sin(_phase * 5.3)))
			bob = 0.012 * sin(_phase * 3.7)
			punch = 0.05
		"storm":
			# Spikes rather than waves: a high power of a sine spends nearly all its time
			# near zero and then stabs, which is what makes it read as a discharge instead
			# of a glow that got brighter.
			var spike: float = pow(absf(sin(_phase * 9.1)), 9.0)
			var spike2: float = pow(absf(sin(_phase * 15.7 + 0.7)), 13.0)
			heat = 0.55 + 0.75 * maxf(spike, spike2)
			# White-hot at the peak, so the brightest moments bleach the colour out.
			tint = tint.lerp(Color.WHITE, minf(1.0, 0.9 * maxf(spike, spike2)))
			slide = 0.02 * sin(_phase * 31.0) * (0.4 + spike)
			punch = 0.07
		"rainbow":
			# The hue walks the wheel rather than cycling per frame: a colour that changes
			# at a readable speed is a colour you can name, and one that spins is just noise.
			var hue: float = fmod(_phase * 0.09, 1.0)
			tint = Color.from_hsv(hue, 0.55, 1.0)
			glow = Color.from_hsv(fmod(hue + 0.32, 1.0), 0.85, 1.0)
			heat = 0.7 + 0.15 * sin(_phase * 2.2)
			bob = 0.02 * sin(_phase * 1.7)
			punch = 0.09

	# The flash rides on top of whatever the tier is doing.
	var flash: float = _flash * _flash
	heat = minf(1.6, heat + flash * 0.9)
	punch += flash * 0.22

	_power_text.modulate = Color(tint, minf(1.0, 0.82 + 0.18 * heat))
	_power_halo.modulate = Color(glow, minf(0.85, 0.16 + 0.5 * heat))
	_power_halo.outline_modulate = Color(glow, minf(0.95, 0.3 + 0.6 * heat))

	var scale_factor: float = float(_tier["scale"]) * (1.0 + punch)
	_power_text.pixel_size = label_pixel_size * scale_factor
	_power_halo.pixel_size = label_pixel_size * scale_factor * 1.04
	_power_text.outline_size = float(_tier["text_outline"])
	_power_halo.outline_size = float(_tier["halo_outline"]) * (1.0 + 0.15 * heat)

	var at := Vector3(slide, POWER_Y + bob, 0.0)
	_power_text.position = at
	_power_halo.position = at


## 12345 -> "12,345". A four or five digit score with no grouping is a string of digits
## nobody can size at a glance, and sizing it at a glance is the entire job of this
## number.
func group(value: int) -> String:
	return PlayerData.group_int(value)


func _add_label(node_name: String, y: float, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = ""
	label.font_size = font_size
	label.pixel_size = label_pixel_size
	label.modulate = color
	label.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector3(0.0, y, 0.0)
	label.render_priority = TEXT_PRIORITY
	add_child(label)
	return label


## Roman numerals for the stage, because a cultivation rank as "VII" reads as a
## rank where "7" reads as a number.
func _numeral(value: int) -> String:
	if value <= 0:
		return "-"
	var digits: Array = [
		[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"],
	]
	var out: String = ""
	var left: int = value
	for pair: Array in digits:
		while left >= int(pair[0]):
			out += String(pair[1])
			left -= int(pair[0])
	return out


func summary() -> Dictionary:
	return {
		"power": _shown_power,
		"power_text": power_label(),
		"tier": String(_tier.get("name", "")),
		"style": String(_tier.get("style", "")),
		"stage_text": _stage_text.text if _stage_text != null else "",
		"pixel_size": _power_text.pixel_size if _power_text != null else 0.0,
		"halo_outline": _power_halo.outline_size if _power_halo != null else 0.0,
		"flash": _flash,
	}
