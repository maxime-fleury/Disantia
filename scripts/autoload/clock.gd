extends Node
## The clock, and what the valley looks like at any hour of it.
##
## The world had a sun and the sun never moved. That is the single cheapest way for a place to
## read as a *set* rather than as a country: nothing ever happens without the player, every
## camp looks the same on the tenth visit as on the first, and the only thing that changes
## between two screenshots an hour apart is how much health is in the bar.
##
## So time moves, and — this is the part that matters — **the systems read it**. A clock that
## only turned the sky would be a filter over the same game. Instead:
##
##   * the spirit zones breathe harder at night (×1.35 throughput), so the *fast* way to
##     cultivate is a decision about when rather than only where;
##   * raiders see further in the dark and give up later, so the night is when the road costs
##     something;
##   * the guards walk their beat in daylight and shut the gates at dusk, which is what makes
##     a village a place with hours instead of a bubble with people in it;
##   * a raid only ever lands at night, and it is the one thing in the game that happens
##     whether or not anybody is looking.
##
## And sitting down hurries it. Meditation runs the clock at `MEDITATION_TIME_SCALE`, so
## "cultivate until dawn" is a real move a player can make — the night stops being something
## you wait out and becomes a thing you can *spend*.

signal phase_changed(phase: String)
signal hour_changed(hour: int)
signal day_passed(day: int)

## A whole day is twenty-four real minutes, so an hour is a minute of play and the night lasts
## eight of them. Long enough that the light means something, short enough that a session sees
## a sunset without waiting for one.
const SECONDS_PER_DAY := 1440.0
const MINUTES_PER_SECOND := 24.0 * 60.0 / SECONDS_PER_DAY
## While meditating. Nothing about cultivation is faster — the *clock* is, which is the whole
## point: the trance is how you wait for a light you want.
const MEDITATION_TIME_SCALE := 14.0

## Where the sun is at each phase, as (elevation°, azimuth°) and the light it throws. Lerped
## between the keys rather than computed from an orbit, so the look of the valley at each hour
## is a thing that was chosen rather than a side effect of trigonometry.
const LIGHT_KEYS: Array = [
	# hour, sun elevation, sun azimuth, colour, energy, ambient, fog colour, sky top, sky horizon
	{"at": 0.0, "elev": -64.0, "az": -38.0, "sun": Color("54608f"), "energy": 0.10,
		"ambient": 0.30, "fog": Color("101526"), "top": Color("0a0f22"), "horizon": Color("1b2440")},
	{"at": 5.0, "elev": -14.0, "az": -38.0, "sun": Color("6f6a9a"), "energy": 0.22,
		"ambient": 0.45, "fog": Color("20263c"), "top": Color("14203f"), "horizon": Color("3b3f63")},
	{"at": 6.6, "elev": 12.0, "az": -30.0, "sun": Color("ffb27a"), "energy": 1.00,
		"ambient": 0.80, "fog": Color("c9a08a"), "top": Color("3a5a8f"), "horizon": Color("ffc79a")},
	{"at": 9.0, "elev": 44.0, "az": -20.0, "sun": Color("fff0d8"), "energy": 1.35,
		"ambient": 1.05, "fog": Color("b9c8d8"), "top": Color("3f6bb8"), "horizon": Color("c3d2df")},
	{"at": 13.0, "elev": 68.0, "az": -12.0, "sun": Color("fffaf0"), "energy": 1.50,
		"ambient": 1.10, "fog": Color("c3d0dd"), "top": Color("2f5fb0"), "horizon": Color("cdd8e2")},
	{"at": 17.4, "elev": 22.0, "az": 8.0, "sun": Color("ffcf94"), "energy": 1.10,
		"ambient": 0.88, "fog": Color("d3b393"), "top": Color("3a5c9c"), "horizon": Color("ffd0a0")},
	{"at": 19.2, "elev": -6.0, "az": 16.0, "sun": Color("c9806a"), "energy": 0.40,
		"ambient": 0.60, "fog": Color("6a4f56"), "top": Color("213153"), "horizon": Color("c47a6a")},
	{"at": 21.0, "elev": -40.0, "az": 20.0, "sun": Color("5a6494"), "energy": 0.16,
		"ambient": 0.36, "fog": Color("181d2f"), "top": Color("0d1428"), "horizon": Color("26304c")},
	{"at": 24.0, "elev": -64.0, "az": -38.0, "sun": Color("54608f"), "energy": 0.10,
		"ambient": 0.30, "fog": Color("101526"), "top": Color("0a0f22"), "horizon": Color("1b2440")},
]

## The hours the phases turn over at. Dawn and dusk are named because they are the two moments
## the world changes its mind, and both of them are visible from the road.
const DAWN_HOUR := 5.0
const DAY_HOUR := 7.0
const DUSK_HOUR := 17.5
const NIGHT_HOUR := 19.5

## 0..1440, in in-game minutes. Starts at half past eight in the morning: a player who has
## never seen the night should get a day's worth of play before it arrives.
var minutes: float = 8.5 * 60.0
var day: int = 1
## Set while the player is sitting. **Read** from the trance rather than pushed by it, for the
## same reason `suppress_qi_regen` is: a flag with two writers can be left on by a trance that
## ended some other way — a death, a reset, a path added later by somebody who never saw this
## variable — and the clock would then run at fourteen times speed for the rest of the session,
## which is a bug whose only symptom is that the days go by too fast.
var hurried: bool:
	get:
		return Cultivation.meditating

var _phase: String = ""
var _sun: DirectionalLight3D
var _environment: Environment


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved: Dictionary = PlayerData.take_loaded_module("sky")
	minutes = fmod(maxf(0.0, float(saved.get("minutes", minutes))), 1440.0)
	day = maxi(1, int(saved.get("day", 1)))
	_phase = phase()


func save_data() -> Dictionary:
	return {"minutes": minutes, "day": day}


func reset() -> void:
	minutes = 8.5 * 60.0
	day = 1
	_phase = phase()


func _process(delta: float) -> void:
	var scale: float = MEDITATION_TIME_SCALE if hurried else 1.0
	var before: int = int(minutes) / 60
	minutes += delta * MINUTES_PER_SECOND * scale
	while minutes >= 1440.0:
		minutes -= 1440.0
		day += 1
		day_passed.emit(day)
	var after: int = int(minutes) / 60
	if after != before:
		hour_changed.emit(after)
	var now: String = phase()
	if now != _phase:
		_phase = now
		phase_changed.emit(now)
		_announce(now)
	_apply_light()


# ------------------------------------------------------------------- reading it

func hour() -> int:
	return int(minutes) / 60


func hour_float() -> float:
	return minutes / 60.0


func clock_text() -> String:
	var total: int = int(minutes)
	return "%02d:%02d" % [total / 60, total % 60]


func phase() -> String:
	var h: float = hour_float()
	if h >= DAWN_HOUR and h < DAY_HOUR:
		return "dawn"
	if h >= DAY_HOUR and h < DUSK_HOUR:
		return "day"
	if h >= DUSK_HOUR and h < NIGHT_HOUR:
		return "dusk"
	return "night"


func is_night() -> bool:
	return phase() == "night"


## How dark it is, 0 (noon) to 1 (deep night). Used by the HUD's palette and by anything that
## wants to darken with the world without re-deriving the clock.
func darkness() -> float:
	var lit: float = float(_light_key()["energy"])
	return clampf(1.0 - lit / 1.5, 0.0, 1.0)


# --------------------------------------------------------------- what it changes

## The spirit zones' share of the night. A zone is faster in the dark, so the best hour to
## cultivate is a decision the player can make rather than a place they walk to.
func zone_share() -> float:
	return 1.35 if is_night() else 1.0


## How much further a raider sees in the dark. Applied to the aggro radius where it is read,
## so a raider that was already awake stays awake — a body being chased does not lose interest
## because the sun came up.
func aggro_share() -> float:
	return 1.30 if is_night() else 1.0


## How far a raider will follow before it gives up. Night is when the road costs something:
## the same camp that lets you walk past at noon will come after you at midnight.
func leash_share() -> float:
	return 1.20 if is_night() else 1.0


## Time of day the guards are on their beat. At dusk they walk back inside, and the road
## outside the fence belongs to whoever else is on it.
func gates_open() -> bool:
	var h: float = hour_float()
	return h >= DAWN_HOUR and h < DUSK_HOUR


## Jumps the clock forward, for "sleep until dawn" and for a raid that has to be able to land
## at a stated hour in a test. Returns the number of hours skipped.
func skip_to_hour(target: float) -> float:
	var want: float = fmod(target, 24.0) * 60.0
	var delta: float = want - minutes
	if delta <= 0.0:
		delta += 1440.0
	minutes = want
	if want < 8.5 * 60.0:
		day += 0
	return delta / 60.0


# -------------------------------------------------------------------- the light

func _light_key() -> Dictionary:
	var h: float = hour_float()
	var before: Dictionary = LIGHT_KEYS[0]
	var after: Dictionary = LIGHT_KEYS[LIGHT_KEYS.size() - 1]
	for i in LIGHT_KEYS.size():
		var key: Dictionary = LIGHT_KEYS[i]
		if float(key["at"]) <= h:
			before = key
		if float(key["at"]) >= h:
			after = key
			break
	var span: float = maxf(0.001, float(after["at"]) - float(before["at"]))
	var t: float = clampf((h - float(before["at"])) / span, 0.0, 1.0)
	return {
		"elev": lerpf(float(before["elev"]), float(after["elev"]), t),
		"az": lerpf(float(before["az"]), float(after["az"]), t),
		"sun": (before["sun"] as Color).lerp(after["sun"], t),
		"energy": lerpf(float(before["energy"]), float(after["energy"]), t),
		"ambient": lerpf(float(before["ambient"]), float(after["ambient"]), t),
		"fog": (before["fog"] as Color).lerp(after["fog"], t),
		"top": (before["top"] as Color).lerp(after["top"], t),
		"horizon": (before["horizon"] as Color).lerp(after["horizon"], t),
	}


## Poses the sun and paints the sky. The sun is the world's own node — `world.gd` sets its
## starting angle — and this takes it over from the first frame, because two owners of the
## same light is one owner too many.
func _apply_light() -> void:
	var key: Dictionary = _light_key()
	if _sun == null or not is_instance_valid(_sun):
		_sun = get_tree().root.get_node_or_null("Main/Sun") as DirectionalLight3D
	if _sun != null:
		_sun.rotation_degrees = Vector3(-float(key["elev"]), float(key["az"]), 0.0)
		_sun.light_color = key["sun"]
		_sun.light_energy = float(key["energy"])
		# The valley is 448 m across now, so the shadow distance has to cover a village's worth
		# of it or the far side of the map is in permanent sunlight at midnight.
		_sun.directional_shadow_max_distance = 240.0
	if _environment == null or not is_instance_valid(_environment):
		var world_env: WorldEnvironment = get_tree().root.get_node_or_null(
			"Main/WorldEnvironment") as WorldEnvironment
		if world_env != null:
			_environment = world_env.environment
	if _environment == null:
		return
	_environment.ambient_light_energy = float(key["ambient"])
	_environment.fog_light_color = key["fog"]
	_environment.fog_density = 0.0026 + 0.0034 * darkness()
	var sky: Sky = _environment.sky
	if sky == null:
		return
	var material: ProceduralSkyMaterial = sky.sky_material as ProceduralSkyMaterial
	if material == null:
		return
	material.sky_top_color = key["top"]
	material.sky_horizon_color = key["horizon"]
	material.ground_horizon_color = key["fog"]
	material.ground_bottom_color = (key["top"] as Color).darkened(0.4)


func _announce(now: String) -> void:
	match now:
		"dawn":
			PlayerData.log_message.emit("Dawn. The qi comes up with the light.", "info")
		"dusk":
			PlayerData.log_message.emit(
				"Dusk. The gates are closing in the villages.", "info"
			)
		"night":
			PlayerData.log_message.emit(
				"Night. The zones run richer and the raiders see further.", "damage"
			)
		"day":
			PlayerData.log_message.emit("Morning. The roads are busy again.", "info")


func summary() -> String:
	return "day %d, %s (%s), %.2f× zone" % [
		day, clock_text(), phase(), zone_share(),
	]
