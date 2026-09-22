extends Node
## Tells the music where the player is.
##
## The whole point of this node is that nothing else has to. A village does not start its own
## theme, a tower floor does not stop one, and a scripted moment does not have to remember to
## put the soundtrack back afterwards -- because there is no state to forget. Once a second
## this asks one question ("where is the body standing") and the answer *is* the theme. Miss a
## transition and the next poll catches it.
##
## The order of the checks is the policy, and it is not arbitrary:
##
##   1. **The tower.** Interiors win. A tower floor is nowhere near a village site, but the
##      rule is stated rather than implied so that moving the tower later does not turn its
##      music into village music.
##   2. **The cave.** Same reason, and the cave is inside a landmark's footprint.
##   3. **A village.** Standing inside the walls is the clearest signal the game has.
##   4. **The valley.** Everything else, which is most of the map.
##
## Everything below the first line is a fallback, so a body in an unregistered place still
## hears the valley rather than nothing.

## Once a second. Faster would be a poll per frame for a value that changes when you walk
## through a gate; slower would leave you inside the walls of a town listening to the road.
const POLL := 1.0

## How far outside a village's radius the town theme starts, so the music is already changing
## when you walk in rather than arriving with you.
const APPROACH := 12.0

const DUCK_QUIET := 0.4

var _player: Node3D
var _timer: float = 0.0
var _region: String = ""
## The count of times this actually handed the music a new region, so a test can tell a
## working poll from a poll that never fires.
var transitions: int = 0


func _ready() -> void:
	_player = get_parent().get_node_or_null("Player") as Node3D


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = POLL
	_poll()
	_duck()


## One poll. Public and free of the node tree, so the suite can walk a position through every
## kind of place the map has without moving a body through it.
func region_at(position: Vector3) -> String:
	if Tower.inside():
		return "tower"
	if _in_cave(position):
		return "cave"
	if Villages.near_site(position.x, position.z, APPROACH):
		return "village"
	return "valley"


func _poll() -> void:
	if _player == null:
		return
	var region: String = region_at(_player.global_position)
	if region == _region:
		return
	_region = region
	transitions += 1
	Music.set_region(region)


## A bed under a voice line is the difference between a conversation and a sound check, and
## meditation is the one moment where the player is meant to hear their own breath. Both are
## read off the systems that already know, rather than signalled into existence.
func _duck() -> void:
	var quiet: bool = Story.talking()
	var cultivation: Node = get_node_or_null("/root/Cultivation")
	if cultivation != null and bool(cultivation.get("meditating")):
		quiet = true
	Music.set_duck(DUCK_QUIET if quiet else 1.0)


## Where the body is, in one word, for a test or a debug line.
func current_region() -> String:
	return _region


## The caves in the scene. Caves register themselves in the `cave` group and answer
## `contains`, the same contract the safe zone and the qi zones already use -- so a second
## cave is a scene change rather than a code change.
func _in_cave(position: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("cave"):
		if node.has_method("contains") and bool(node.call("contains", position)):
			return true
	return false
