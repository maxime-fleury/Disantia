extends "res://scripts/world/quest_npc.gd"
## Somebody standing in the world who is not the elder.
##
## The elder's script already does the expensive part of being a person in this project: it
## finds the shared monk rig, measures it, scales it to a height, tints it, plays its idle and
## hangs a billboarded glyph over its head. So a villager *is* one of those with three
## differences — a name over the head instead of a task marker, a conversation instead of a
## task board, and, for the two on the road, legs that go somewhere.
##
## Walking is deliberately crude: a point on a road, walk to the next one, snap to the ground
## under you. The alternative — a navmesh, an agent, path following — would be three systems
## to make one person stroll. What the player reads from across a valley is that a figure is
## *moving along the road*, and that costs the four lines below.

@export var person_id: String = ""
## The road this one walks, or -1 to stand where they were placed.
@export var road_index: int = -1
@export var walk_speed: float = 1.15
## Seconds spent standing still between legs, so a walker reads as somebody going somewhere
## rather than as a train on a track.
@export var pause_seconds: float = 2.5
@export var name_height: float = 2.72

var _name_plate: Label3D
var _road: PackedVector2Array = PackedVector2Array()
var _leg: int = 1
var _rest: float = 0.0
var _on_road: bool = false


func _ready() -> void:
	super()
	# The elder is the one who hands out tasks; this is somebody else standing in the same
	# world, and a group that counted them both would make "talk to the elder" ambiguous.
	remove_from_group("quest_npc")
	add_to_group("villager")
	add_to_group("npc")
	_build_name_plate()


## The clips a person needs. The base resolves the idle; a walker needs its walk as well.
func wanted_clips() -> Array:
	return ["Idle", "Walk"]


## Only the people with something they have not said yet wear a glyph, and it comes down the
## moment they have said it — the same contract the elder's "!" keeps, for the same reason:
## a world where everybody is permanently shouting is a world with no signal in it.
func marker_state() -> String:
	if person_id == "":
		return ""
	var entry: Dictionary = Story.person(person_id)
	var decision: String = String(entry.get("decision", ""))
	if decision == "" or Story.decided(decision) or not Story.gate_open(decision):
		return ""
	return "!"


func _build_name_plate() -> void:
	_name_plate = Label3D.new()
	_name_plate.name = "NamePlate"
	_name_plate.text = Story.display_name(person_id)
	_name_plate.font_size = 110
	_name_plate.pixel_size = 0.005
	_name_plate.outline_size = 20
	_name_plate.outline_modulate = Color(0.05, 0.05, 0.08)
	_name_plate.modulate = Color(0.92, 0.96, 1.0)
	_name_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_plate.no_depth_test = true
	_name_plate.render_priority = 3
	_name_plate.position = Vector3(0.0, name_height, 0.0)
	add_child(_name_plate)


## Loads the road this one walks and drops onto the first point. Called by `place` rather than
## from `_ready`, because where a road *is* is not known until the terrain has built itself.
func take_to_road(road: PackedVector2Array) -> void:
	_road = road
	_on_road = _road.size() >= 2
	if not _on_road:
		return
	_snap_to_ground(_road[0])
	_leg = 1


func _process(delta: float) -> void:
	super(delta)
	if not _on_road:
		return
	if _rest > 0.0:
		_rest -= delta
		if _rest <= 0.0:
			_play("Walk")
		return
	var target: Vector2 = _road[_leg]
	var here := Vector2(global_position.x, global_position.z)
	var step: Vector2 = target - here
	if step.length() <= 0.5:
		_leg = (_leg + 1) % _road.size()
		_rest = pause_seconds
		_play("Idle")
		return
	var motion: Vector2 = step.normalized() * walk_speed * delta
	global_position.x += motion.x
	global_position.z += motion.y
	_snap_to_ground(Vector2(global_position.x, global_position.z))
	# Facing is the whole grammar of a crowd: a figure that slides sideways along a road reads
	# as a prop on a rail, and the rig's own +Z is its front.
	if _rig != null:
		_rig.rotation.y = atan2(motion.x, motion.y)


## Drops the body onto the terrain under it, keeping whatever x and z it has.
func _snap_to_ground(flat: Vector2) -> void:
	var terrain: Node = get_tree().root.get_node_or_null("Main/Terrain")
	if terrain == null or not terrain.has_method("surface_height_at"):
		return
	global_position = Vector3(
		flat.x, float(terrain.call("surface_height_at", flat.x, flat.y)), flat.y
	)


## What this person says, through the story file. Overrides the elder's task hand-in, so the
## interact key does the same thing at every person in the world.
func interact() -> Dictionary:
	return Story.begin(person_id)


func is_on_road() -> bool:
	return _on_road
