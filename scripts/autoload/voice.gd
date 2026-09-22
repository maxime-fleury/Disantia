extends Node
## The valley, out loud.
##
## Every person in this game has been text on a band at the foot of the screen. That is the
## cheapest way to have fifteen characters and the worst way to *meet* one: a keeper who says her
## line in a voice is somebody the player can recognise across a square, and the same line in a
## paragraph is a paragraph. So the prose the game already prints is recorded, once, and played
## when it is said — see `tools/make_voice.py` for how the recordings are made and `voice_table.gd`
## for where they live.
##
## Three decisions worth writing down.
##
##   * **The line is the key**, exactly as it is everywhere else in the interface (see `loc.gd`).
##     A line with no recording is silent, which means the corpus can be partial forever without
##     anything being broken — and the lines that *are* recorded are the ones the tables say are
##     said out loud.
##   * **A language is a set of recordings, not a translation of one.** French is a separate take.
##     A line with no French recording is played in English rather than in a French accent, and if
##     neither exists it is silent.
##   * **One listener, on `conversation_changed`.** Every path that puts a line on the band — the
##     first thing somebody says, an answer, a place speaking — already announces it, so nothing in
##     the story has to remember to call this. The alternative is a `Voice.speak` at each of the
##     eight places a line is set, and the day somebody adds a ninth is the day it goes quiet.

const TABLE_PATH := "res://scripts/autoload/voice_table.gd"
## What a spoken line sits at, in the mix. Dialogue over a fire and a footstep has to be louder
## than the world and quieter than the music would be, and this is the one number that decides it.
const LINE_DB := -3.0

## Off means silent, and is a *save*: a player who turns the voices off does not want to be asked
## again on the next launch.
var enabled: bool = true
## Linear, 0..1. A trim on top of the master bus rather than a bus of its own, because the master
## is already the volume control the settings panel shows.
var volume: float = 1.0

var _table: Dictionary = {}
var _streams: Dictionary = {}
var _player: AudioStreamPlayer
## The line being said, so the same one is not restarted by a redraw of the same conversation.
var _saying: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_table = preload(TABLE_PATH).TABLE
	_player = AudioStreamPlayer.new()
	_player.name = "Line"
	add_child(_player)
	var saved: Dictionary = PlayerData.take_loaded_module("voice")
	enabled = bool(saved.get("enabled", true))
	volume = clampf(float(saved.get("volume", 1.0)), 0.0, 1.0)
	Story.conversation_changed.connect(_on_conversation)


func save_data() -> Dictionary:
	return {"enabled": enabled, "volume": volume}


func reset() -> void:
	enabled = true
	volume = 1.0
	stop()


# -------------------------------------------------------------------- the door

## The recordings that exist for a line: `{"en": "res://...", "fr": "res://..."}`, possibly empty.
func takes(line: String) -> Dictionary:
	return (_table.get(line, {}) as Dictionary).duplicate()


## Which recording a line would play right now, or "" when it would be silent.
##
## The language of the recording follows the language of the interface, and falls back to English
## when the French take does not exist.
func take_for(line: String) -> String:
	var rows: Dictionary = takes(line)
	if rows.is_empty():
		return ""
	if Loc.is_french() and rows.has("fr"):
		return String(rows["fr"])
	return String(rows.get("en", ""))


## Says a line. Returns false when there is nothing to say it with — no recording, or the voices
## are off — which is not an error and is what most lines in the game will answer.
func speak(line: String) -> bool:
	if line == "":
		return false
	if line == _saying and _player.playing:
		return true
	var path: String = take_for(line)
	if path == "":
		return false
	_saying = line
	if not enabled:
		return true
	var stream: AudioStream = _stream(path)
	if stream == null:
		return false
	_player.stream = stream
	_player.volume_db = LINE_DB + linear_to_db(maxf(0.0001, volume))
	_player.play()
	return true


## Stops whatever is being said, without forgetting which line it was.
func stop() -> void:
	_saying = ""
	if _player != null and _player.playing:
		_player.stop()


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop()
	PlayerData.mark_dirty()


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	PlayerData.mark_dirty()


# ------------------------------------------------------------------- the state

## Everything about the voices in one dictionary, for the panel and the suite, so neither has to
## re-derive what is recorded or how much of it is.
func summary() -> Dictionary:
	var english: int = 0
	var french: int = 0
	for line: String in _table:
		var rows: Dictionary = _table[line]
		if rows.has("en"):
			english += 1
		if rows.has("fr"):
			french += 1
	return {
		"lines": _table.size(),
		"english": english,
		"french": french,
		"enabled": enabled,
		"volume": volume,
		"saying": _saying,
		"playing": _player != null and _player.playing,
		"language": Loc.code(),
	}


func is_playing() -> bool:
	return _player != null and _player.playing


# ---------------------------------------------------------------- the plumbing

## Loaded once and kept: a conversation can repeat a line, and a hitch on the second time somebody
## greets you is worse than the memory.
func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		_streams[path] = null
		return null
	var stream: AudioStream = load(path) as AudioStream
	_streams[path] = stream
	return stream


func _on_conversation() -> void:
	var line: String = String(Story.conversation().get("line", ""))
	if line == "":
		stop()
		return
	speak(line)
