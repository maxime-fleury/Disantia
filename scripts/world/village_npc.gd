extends "res://scripts/world/quest_npc.gd"
## Somebody who lives in a village.
##
## The elder's script already does the expensive part of being a person in this project: it
## finds the shared monk rig, measures it, scales it to a height, tints it, plays its idle and
## hangs a marker over its head. So a villager *is* one of those with three differences — a name
## plate that says what they do, a marker only when they actually have business with you, and a
## conversation that comes from the village table rather than from the elder's task chain.
##
## The role tag is the part worth the extra label. Fifteen people across three villages with no
## tags is a crowd you have to interview to use; with tags it is a *place*, and a player who has
## never been to Stonewatch still knows which door to walk to when their coat needs mending.

@export var person_id: String = ""
@export var village_id: String = ""
@export var role: String = "folk"
## The name plate sits where the elder's marker does, so a village's heads are all at one height.
@export var plate_height: float = 2.62

var _name_plate: Label3D
var _role_plate: Label3D


func _ready() -> void:
	super()
	# The elder is the one who hands out tasks. A village with six more people in the same group
	# would make "talk to the elder" ambiguous for anything that asks by group.
	remove_from_group("quest_npc")
	add_to_group("village_npc")
	add_to_group("npc")
	# Everything a swing can land on that is not a raider. The striker searches this group as
	# well as `enemy`, which is what makes striking somebody who lives here possible at all —
	# and what makes it a crime rather than a typo.
	add_to_group("bystander")
	_build_plates()


## The clips a person needs. Everybody here stands and breathes; nobody walks a road.
func wanted_clips() -> Array:
	return ["Idle"]


## The marker means *business*, not presence. Only the keeper ever has any: "?" once a step is
## finished and wants collecting, "!" while one is under way, and nothing once the chain is
## theirs. A village where all five people wear a glyph is a village with no signal in it.
func marker_state() -> String:
	if role != "keeper" or village_id == "":
		return ""
	if Villages.step_ready(village_id):
		return "?"
	if not Villages.current_step(village_id).is_empty():
		return "!"
	return ""


func _build_plates() -> void:
	_name_plate = Label3D.new()
	_name_plate.name = "NamePlate"
	_name_plate.text = npc_name
	_name_plate.font_size = 110
	_name_plate.pixel_size = 0.005
	_name_plate.outline_size = 20
	_name_plate.outline_modulate = Color(0.05, 0.05, 0.08)
	_name_plate.modulate = Color(0.92, 0.96, 1.0)
	_name_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_plate.no_depth_test = true
	_name_plate.render_priority = 3
	_name_plate.position = Vector3(0.0, plate_height, 0.0)
	add_child(_name_plate)

	_role_plate = Label3D.new()
	_role_plate.name = "RolePlate"
	_role_plate.text = role_label()
	_role_plate.font_size = 74
	_role_plate.pixel_size = 0.005
	_role_plate.outline_size = 14
	_role_plate.outline_modulate = Color(0.05, 0.05, 0.08)
	_role_plate.modulate = Color(0.72, 0.78, 0.86)
	_role_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_role_plate.no_depth_test = true
	_role_plate.render_priority = 3
	_role_plate.position = Vector3(0.0, plate_height - 0.30, 0.0)
	add_child(_role_plate)


## What this person is, in three words or fewer. The whole reason a player can use a village
## they have never visited.
func role_label() -> String:
	match role:
		"keeper":
			return "keeper of the village"
		"merchant":
			return "trader"
		"smith":
			return "the forge"
		"healer":
			return "physician"
		"clerk":
			return "the board"
		_:
			return ""


func _process(delta: float) -> void:
	super(delta)
	if _name_plate == null:
		return
	# Slight lift on whoever has something to say, so a marker is attached to a *body* rather
	# than floating over a square.
	var lift: float = 0.06 if marker_state() != "" else 0.0
	_name_plate.position.y = plate_height + lift


## Everything a villager does with the interact key goes through the story table, which is what
## keeps one key doing one thing at every person in the world.
func interact() -> Dictionary:
	return Story.begin(person_id)


func is_bystander() -> bool:
	return true


## Struck by the player. The crime is reported by the *victim*, which is the only place that
## knows who was hit, where, and whether they mattered — a striker that had to work out whose
## village it was standing in would have been the same logic in a worse place.
func take_hit(damage: float, _from: Vector3 = Vector3.ZERO) -> float:
	if village_id == "":
		return 0.0
	var dealt: float = maxf(1.0, damage * 0.15)
	Law.add_crime("assault", village_id, "%s was struck" % npc_name)
	_flinch()
	return dealt


## A body that has been hit at least looks like it. Cheap, and the difference between a person
## and a post.
func _flinch() -> void:
	if _rig == null:
		return
	var tween := create_tween()
	tween.tween_property(_rig, "rotation:z", deg_to_rad(11.0), 0.08)
	tween.tween_property(_rig, "rotation:z", 0.0, 0.35)
