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

## What the *log* is said at: a sentence the game prints rather than one somebody says to your
## face. Four decibels under a conversation, because the world is already saying other things.
const LOG_DB := -7.0
## The shortest gap between two spoken log lines. Half of what the log prints is a consequence of
## the other half — a blow lands, the blood it cost trains a stat, the crystal it paid moves the
## purse — and a corpus that reads all of them out turns a fight into a monologue. Long enough
## that the ear can tell two sentences apart, short enough that a fight still sounds like one.
const LOG_GAP_SECONDS := 1.6

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
## The meaning of the last thing said, and when: `0` for a spoken conversation, `1` for a line off
## the log, and the clock reading it finished at.
var _saying_kind: int = 0
var _last_log_ms: int = 0
## The recorded sentences that fragments of a dynamic line are looked up in, longest first. Sorted
## once, because the search is "the longest one that appears in this line" and sorting it here is
## the difference between a lookup and a sort per line.
var _phrases: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_table = preload(TABLE_PATH).TABLE
	_phrases = preload(TABLE_PATH).PHRASES.keys()
	_phrases.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	_player = AudioStreamPlayer.new()
	_player.name = "Line"
	add_child(_player)
	var saved: Dictionary = PlayerData.take_loaded_module("voice")
	enabled = bool(saved.get("enabled", true))
	volume = clampf(float(saved.get("volume", 1.0)), 0.0, 1.0)
	Story.conversation_changed.connect(_on_conversation)
	# The log, which is where the *dynamic* half of the game's prose lives: a sentence with a
	# number in it is a different sentence every time it is printed, so no recording can ever
	# match one. Listening here is what lets the fixed half of those sentences be heard — see
	# `speak_phrase`. Connected once, so nothing in the game has to remember to say anything.
	PlayerData.log_message.connect(_on_log)


func save_data() -> Dictionary:
	return {"enabled": enabled, "volume": volume}


func reset() -> void:
	enabled = true
	volume = 1.0
	_saying_kind = 0
	_last_log_ms = 0
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


## The recordings that exist for a *fragment* of a line, on the same terms as `takes`.
func phrase_takes(phrase: String) -> Dictionary:
	return ((preload(TABLE_PATH).PHRASES as Dictionary).get(phrase, {}) as Dictionary).duplicate()


## The recording for a fragment, or "" when that fragment was never recorded.
func phrase_take_for(phrase: String) -> String:
	var rows: Dictionary = phrase_takes(phrase)
	if rows.is_empty():
		return ""
	if Loc.is_french() and rows.has("fr"):
		return String(rows["fr"])
	return String(rows.get("en", ""))


## The longest recorded sentence inside a line, or "" when the line holds none.
##
## This is what makes a dynamic line audible at all. `Took 12.4 damage.` can never be recorded —
## it is a different sentence every time — but `Took .` nothing and `damage.` are fixed, so the
## fixed part is recorded on its own and the line is spoken with the number left to the eye. The
## longest match wins rather than the first, because the shortest match in a table is a word and
## a word is not a sentence.
func phrase_in(line: String) -> String:
	for phrase: String in _phrases:
		if line.contains(phrase):
			return phrase
	return ""


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
	return _play(line, path, LINE_DB, 0)


## Says the fixed half of a line that has a number in it, and returns whether anything was said.
##
## Deliberately *not* a fallback inside `speak`: a conversation's line is the thing being listened
## to and a fragment of it would be the wrong half of the sentence, so the two doors are separate
## and each caller knows which one it wants.
func speak_phrase(line: String) -> bool:
	var phrase: String = phrase_in(line)
	if phrase == "":
		return false
	var path: String = phrase_take_for(phrase)
	if path == "":
		return false
	return _play(phrase, path, LOG_DB, 1)


## A cry: a short line said out loud rather than printed, by a guard or a raider.
##
## Shouts are their own table because they are not prose the game *writes* anywhere — nobody is
## reading them off the band — so no amount of reading the story's tables would find them. What
## they are worth is the thing a village square otherwise cannot give: somebody on the other side
## of it being glad, or frightened, that you are there.
func shout(line: String) -> bool:
	if line == "":
		return false
	var rows: Dictionary = ((preload(TABLE_PATH).SHOUTS as Dictionary).get(line, {}) as Dictionary)
	if rows.is_empty():
		return false
	var path: String = String(rows["fr"]) if Loc.is_french() and rows.has("fr") else String(rows.get("en", ""))
	if path == "":
		return false
	# A shout interrupts a conversation line, unlike a log line: it is something happening *to*
	# you, and the sentence the band was reading has already been read.
	return _play(line, path, LINE_DB, 2)


## The one place a stream is handed to the player, so the volume and the bookkeeping cannot
## drift between the three doors above.
func _play(what: String, path: String, level: float, kind: int) -> bool:
	_saying = what
	_saying_kind = kind
	if kind == 1:
		_last_log_ms = Time.get_ticks_msec()
	if not enabled:
		return true
	var stream: AudioStream = _stream(path)
	if stream == null:
		return false
	_player.stream = stream
	_player.volume_db = level + linear_to_db(maxf(0.0001, volume))
	_player.play()
	return true


## Stops whatever is being said, without forgetting which line it was.
func stop() -> void:
	_saying = ""
	if _player != null and _player.playing:
		_player.stop()


## True while a conversation's line is playing. A log line never talks over one.
func is_saying_a_line() -> bool:
	return _player != null and _player.playing and _saying_kind == 0


## How long since the log last said anything, in seconds.
##
## Public because the gap is a rule about behaviour rather than a private detail of the mixer, and
## a timer only the tick can see is a rule nobody — the panel, the suite — can reason about.
func seconds_since_log() -> float:
	return float(Time.get_ticks_msec() - _last_log_ms) / 1000.0


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
	# The fragments and the cries are counted too, and *separately*: a corpus that doubles its
	# line count while every dynamic sentence in the game stays silent is a corpus that grew
	# without getting any better, and this is the number that says so.
	var phrases: Dictionary = preload(TABLE_PATH).PHRASES
	var shouts: Dictionary = preload(TABLE_PATH).SHOUTS
	var phrase_french: int = 0
	for phrase: String in phrases:
		if (phrases[phrase] as Dictionary).has("fr"):
			phrase_french += 1
	var shout_french: int = 0
	var shout_english: int = 0
	for cry: String in shouts:
		if (shouts[cry] as Dictionary).has("fr"):
			shout_french += 1
		if (shouts[cry] as Dictionary).has("en"):
			shout_english += 1
	return {
		"lines": _table.size(),
		"english": english,
		"french": french,
		"phrases": phrases.size(),
		"phrase_french": phrase_french,
		"shouts": shouts.size(),
		"shout_english": shout_english,
		"shout_french": shout_french,
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


## Everything the log prints, said as far as it is recorded.
##
## Three ways to be quiet, and each of them is a different reason: the voices are off, the line is
## inside the gap left by the last one, or a conversation is in progress and the sentence you are
## being told matters more than the one your fight just produced. None of them is an error, and
## none of them is silence the player was not meant to hear — the band still has the words.
func _on_log(text: String, _kind: String) -> void:
	if not enabled or text == "":
		return
	if is_saying_a_line():
		return
	if Time.get_ticks_msec() - _last_log_ms < int(LOG_GAP_SECONDS * 1000.0):
		return
	speak_phrase(text)
