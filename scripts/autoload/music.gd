extends Node
## Music, by region and hour.
##
## The game was silent except for effects, which is the single loudest signal that something
## is a technical demo rather than a place. This is the whole of the fix: a handful of looping
## beds, a theme chosen from *where the player is* rather than from what the code is doing,
## and a crossfade so the change of theme is felt rather than heard.
##
## Three decisions worth keeping:
##
## * **Region, not script.** Nothing that wants music calls it. A director in the world asks
##   "where is the body standing" once a second and this answers with a theme. That means a
##   new place only has to say where it is, and a place that forgets to say anything still
##   gets the valley rather than silence.
## * **Two players and a hand-rolled fade.** A tween would work, but a fade that is a number
##   in `_process` can be *measured* -- the suite walks the fade and checks both beds were
##   audible in the middle and only one was audible at the end. A tween would pass a test by
##   existing.
## * **The music is on its own bus.** The master slider moves everything; the music slider
##   moves the music. Turning the soundtrack off to hear the footsteps is a thing players do.

const DIR := "res://assets/music/"
const BUS := "Music"

## Long enough to read as a change of place, short enough that walking through a gate does
## not leave you in a corridor between two songs for five seconds.
const FADE := 2.6
## Where a bed sits under the effects. Every file was mastered for a listener who is doing
## nothing else.
const BASE_DB := -9.0

## Which bed answers for which place, per half of the day. The tower and the cave ignore the
## hour on purpose: a stone room does not care what the sun is doing.
const REGIONS: Dictionary = {
	"valley": {"day": "valley", "night": "valley_night"},
	"village": {"day": "village", "night": "village_night"},
	"tower": {"day": "tower", "night": "tower"},
	"cave": {"day": "cave", "night": "cave"},
}

const FALLBACK := "valley"

## 0..1, and it multiplies the bed rather than the master bus, because the effects are
## already mixed against it.
var volume: float = 0.65
## Off means nothing plays at all, which is a different statement from volume zero: the
## players stop, so a bed is not silently decoding behind the scenes.
var enabled: bool = true

var _players: Array[AudioStreamPlayer] = []
## Per-player gain 0..1, moved toward `_target` in `_process`. Index 0 is the live bed.
var _gain: Array[float] = [0.0, 0.0]
var _target: Array[float] = [0.0, 0.0]
var _active: int = 0
var _region: String = ""
var _theme: String = ""
## Set by whoever wants the music out of the way -- meditation, a death, a cutscene.
var duck: float = 1.0
## How many times a fade has actually happened. A count rather than a flag, so a test can
## tell "did not change" from "never checked".
var switches: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Read before the bus exists, so a save restores the level the player chose rather than
	# the level the default built -- and the bus is opened at that level instead of being
	# moved to it a frame later.
	var saved: Dictionary = PlayerData.take_loaded_module("music")
	volume = clampf(float(saved.get("volume", volume)), 0.0, 1.0)
	enabled = bool(saved.get("enabled", enabled))
	_ensure_bus()
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Bed%d" % i
		player.bus = BUS
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)


## The music slider needs a bus to move. The project ships no bus layout file, so the bus is
## made here -- one place, and it cannot be missing at runtime.
func _ensure_bus() -> void:
	var index: int = AudioServer.get_bus_index(BUS)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, volume)))


func _process(delta: float) -> void:
	advance(delta)


## Moves every fade on by `delta` seconds. Separated from `_process` so the fade can be walked
## in one step instead of waited out: a check that has to sleep for two and a half real seconds
## is a check that gets deleted the first time the suite runs slow.
func advance(delta: float) -> void:
	var step: float = delta / FADE if FADE > 0.0 else 1.0
	for i in _players.size():
		if is_equal_approx(_gain[i], _target[i]):
			continue
		_gain[i] = move_toward(_gain[i], _target[i], step)
		_apply(i)
		# A bed that has finished fading out is stopped rather than left at -80 dB: an idle
		# player per region is a stream being decoded for nothing.
		if _gain[i] <= 0.0 and _players[i].playing and i != _active:
			_players[i].stop()


## Where the body is, in one word. Called by the director, but public and free of the world
## so a test can set a region directly.
func set_region(region: String) -> void:
	var wanted: String = theme_for(region)
	if wanted == _theme and _players[_active].playing:
		_region = region
		return
	_region = region
	_cross_to(wanted)


## The bed for a place, resolved through the hour. Pure, so the mapping can be checked
## without a world, a clock, or a frame.
func theme_for(region: String, night: bool = false) -> String:
	var entry: Dictionary = REGIONS.get(region, REGIONS[FALLBACK])
	return String(entry.get("night" if night else "day", FALLBACK))


## The hour is read here rather than passed in, so nothing has to remember to tell the music
## that the sun went down.
func _is_night() -> bool:
	var clock: Node = get_node_or_null("/root/Clock")
	return clock != null and clock.call("is_night")


func _cross_to(theme: String) -> void:
	_theme = theme
	switch_to(theme)
	switches += 1


## Starts a bed immediately, or crossfades if another one is up. Public because a scripted
## moment (the tower's door, a death) may want a specific bed out of the ordinary rotation.
func switch_to(theme: String) -> void:
	if not enabled:
		return
	var stream: AudioStream = load_bed(theme)
	if stream == null:
		return
	var next: int = 1 - _active
	_players[next].stream = stream
	_players[next].play()
	_target[_active] = 0.0
	_target[next] = 1.0
	_active = next


## Beds loop. The importer does not set this (Godot's OGG import defaults to one-shot), and a
## theme that stops after eighty-eight seconds is worse than no theme: the silence arrives in
## the middle of a fight.
func load_bed(theme: String) -> AudioStream:
	var path: String = DIR + theme + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


## The live gain of a bed, 0..1. Read by the suite to watch a fade actually move.
func gain(index: int) -> float:
	return _gain[index]


func current_theme() -> String:
	return _theme


func current_region() -> String:
	return _region


## Silence without a region change -- a fade to nothing and back. Used by meditation and by
## the conversation panel, where a bed under a voice line is the difference between a scene
## and a sound check.
func set_duck(value: float) -> void:
	duck = clampf(value, 0.0, 1.0)
	for i in _players.size():
		_apply(i)


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	var index: int = AudioServer.get_bus_index(BUS)
	if index != -1:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, volume)))


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		for i in _players.size():
			_target[i] = 0.0
	elif _theme != "":
		switch_to(_theme)


## The one place a gain becomes decibels, so the duck and the fade cannot disagree.
func _apply(index: int) -> void:
	_players[index].volume_db = linear_to_db(maxf(0.0001, _gain[index] * duck)) + BASE_DB


func save_data() -> Dictionary:
	return {"volume": volume, "enabled": enabled}


func load_data(saved: Dictionary) -> void:
	set_volume(float(saved.get("volume", volume)))
	set_enabled(bool(saved.get("enabled", enabled)))


func reset() -> void:
	volume = 0.65
	enabled = true
	set_volume(volume)
	duck = 1.0
	for i in _players.size():
		_target[i] = 0.0
		_gain[i] = 0.0
		_players[i].stop()
	_region = ""
	_theme = ""
	switches = 0


func summary() -> String:
	return "%s%s" % [_theme, "" if enabled else " (off)"]
