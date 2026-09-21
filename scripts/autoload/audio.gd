extends Node
## One-shot sound, pooled.
##
## Every sound is a logical name mapped to a list of files, so callers never hold
## a path and a bank with several takes (footsteps, impacts) varies on its own.
## Two-dimensional sounds come from a fixed round-robin pool, which is what keeps
## a footstep from cutting off the strike that landed on the same frame; world
## sounds get a player built for them and freed when they finish, because a 3D
## one needs a position and those are one-offs.
##
## Audio in the browser cannot start until the user interacts with the page, but
## Godot resumes the context on the first input, so nothing here has to know.

## Baseline trim. Every file in these packs is mastered loud, and a browser tab
## that shouts is worse than one that is quiet.
const MIX_DB := -8.0
const POOL_SIZE := 12

const CLIPS: Dictionary = {
	"footstep": [
		"res://assets/audio/footstep_00.ogg", "res://assets/audio/footstep_01.ogg",
		"res://assets/audio/footstep_02.ogg", "res://assets/audio/footstep_03.ogg",
		"res://assets/audio/footstep_04.ogg", "res://assets/audio/footstep_05.ogg",
		"res://assets/audio/footstep_06.ogg", "res://assets/audio/footstep_07.ogg",
		"res://assets/audio/footstep_08.ogg", "res://assets/audio/footstep_09.ogg",
	],
	"impact": ["res://assets/audio/impact_1.ogg", "res://assets/audio/impact_2.ogg"],
	"whoosh": [
		"res://assets/audio/whoosh_1.ogg", "res://assets/audio/whoosh_2.ogg",
		"res://assets/audio/whoosh_3.ogg", "res://assets/audio/whoosh_4.ogg",
	],
	"ui_click": [
		"res://assets/audio/ui_click_1.ogg", "res://assets/audio/ui_click_2.ogg",
		"res://assets/audio/ui_click_3.ogg",
	],
	"ui_open": ["res://assets/audio/ui_open.ogg"],
	"ui_close": ["res://assets/audio/ui_close.ogg"],
	"ui_toggle": ["res://assets/audio/ui_toggle.ogg"],
	"ui_select": ["res://assets/audio/ui_select.ogg"],
	"confirm": ["res://assets/audio/confirm.ogg"],
	"breakthrough": ["res://assets/audio/breakthrough.ogg"],
	"error": ["res://assets/audio/error.ogg"],
	"drop": ["res://assets/audio/drop.ogg"],
	"rep": ["res://assets/audio/rep.ogg"],
	"scroll": ["res://assets/audio/scroll.ogg"],
	"pluck": ["res://assets/audio/pluck.ogg"],
	"coin": ["res://assets/audio/coin.ogg"],
	"book": ["res://assets/audio/book.ogg"],
}

## Linear 0..1. Applied to the master bus, so everything follows it at once.
var volume: float = 1.0

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _streams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Streams are loaded once up front: these are tiny files, and a hitch on the
	# first footstep would be worse than the memory.
	for bank: String in CLIPS:
		var paths: Array = []
		for path: String in CLIPS[bank]:
			var stream: Resource = load(path)
			if stream != null:
				paths.append(stream)
		_streams[bank] = paths
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "OneShot%d" % i
		add_child(player)
		_pool.append(player)
	set_volume(volume)


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, volume)))


func has_bank(bank: String) -> bool:
	return not (bank_for(bank) as Array).is_empty()


func bank_for(bank: String) -> Array:
	return _streams.get(bank, [])


## Plays a bank from the pool. `pitch` jitter is what stops ten identical
## footstep files from sounding like ten identical footsteps.
func play(bank: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _pick(bank)
	if stream == null:
		return
	var player: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = MIX_DB + volume_db
	player.pitch_scale = pitch
	player.play()


## Plays a bank at a point in the world, with distance falloff. The player is
## built for the call and frees itself, because a one-off needs a position and a
## pool of positioned players would be a lot of machinery for a footstep.
func play_at(bank: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0,
		max_distance: float = 30.0) -> void:
	var stream: AudioStream = _pick(bank)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = MIX_DB + volume_db
	player.pitch_scale = pitch
	player.unit_size = 6.0
	player.max_distance = max_distance
	add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


## A random take from a bank. Pitches are jittered by the caller, which is what
## keeps ten identical footstep files from sounding like ten identical steps.
func _pick(bank: String) -> AudioStream:
	var bank_streams: Array = bank_for(bank)
	if bank_streams.is_empty():
		return null
	return bank_streams[randi() % bank_streams.size()]


## A sound for a positive stat event, so gains are audible without every caller
## having to decide what "a gain" sounds like.
func play_gain(stat_id: String) -> void:
	match stat_id:
		"body", "attack":
			play("rep", -4.0, randf_range(0.95, 1.1))
		"hp", "defense":
			play("impact", -8.0, 0.7)
		_:
			play("coin", -6.0, randf_range(0.95, 1.15))
