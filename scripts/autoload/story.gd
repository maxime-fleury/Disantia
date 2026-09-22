extends Node
## The people, and the two or three things they will let you decide.
##
## The world had one character in it. Elder Shufen stood by the fire and asked for
## quantities — kill this many, find this many — and every other metre of a hundred and sixty
## was scenery with nobody standing in it. A game can have all the systems it likes and still
## not read as one to play, because what makes a world feel inhabited is not the number of
## trees: it is that somebody *notices you*, and that something you did is still true later.
##
## So this file holds two things, and they are the same idea from both ends.
##
## **Greetings that change.** Nobody in this world reads your stat sheet, and nobody should —
## they read your *shape*: a fresh face, somebody who has grown, somebody whose name has
## reached the next valley. Power level is the number every other system already rolls into
## one, so it is the number the people react to. The line changes at four thresholds, and the
## top one is written to sound like a warning rather than a reward.
##
## **Decisions that stay decided.** Two conversations end in a choice, the choice is written
## into the save, and it does something concrete and visible — a cap that is permanently
## higher, a raider camp that is no longer standing, a camp whose raiders will look through
## you for the rest of the run. The option you did not take is closed, which is the part that
## makes it a decision rather than a menu: an RPG's choices are interesting exactly to the
## extent that they are irreversible.
##
## Everything here is data. The panel in the HUD reads `conversation()`, the tests drive
## `choose()` directly, and neither of them knows what a decision *is*.

signal conversation_changed
## Emitted when a conversation opens or closes, because the controller roots the body while
## one is open — a person who carries on running mid-sentence is not a person being spoken to.
signal talking_changed

## How far a person lets you get before they will talk to you.
const TALK_RANGE := 4.5

## The people, in the order they are placed. `line` is what they say when there is nothing to
## decide; `decision` names the conversation that opens if one is still open to them.
##
## `at` is an offset from the spawn fire rather than a world position, so a change to the camp
## — a bigger plateau, a moved fire — moves the people with it instead of leaving them
## standing in the grass. `road` stands a wanderer on the road it walks, at that distance out.
const CAST: Array = [
	{
		"id": "ren", "name": "Master Ren", "role": "the hand",
		"colour": Color("8c5a3c"), "at": Vector2(4.5, -2.0), "wanders": false,
		"line": "Stand there a moment. Feet apart. Yes — you have been running, not standing.",
		"decision": "path",
		"hint": "He is the one who asks what your hands are for.",
	},
	{
		"id": "xia", "name": "Xia the Firekeeper", "role": "the fire",
		"colour": Color("7a4a6f"), "at": Vector2(-3.5, 3.0), "wanders": true,
		"line": "The fire is for whoever comes back. It does not ask what you did out there.",
		"decision": "camp",
		"hint": "She has watched every camp smoke from up here.",
	},
	{
		"id": "bo", "name": "Old Bo", "role": "the road",
		"colour": Color("4f6b52"), "road": 0, "wanders": true,
		"line": "Mm. Walk with me a little. I have the legs for it and nothing else.",
		"decision": "ledger",
		"hint": "He carries other people's accounts.",
	},
]

## What the people call you, by power level. Four steps rather than a curve: the point is a
## moment the player can hear, and a line that changes by a per cent would never be heard at
## all. The last one is deliberately not flattering.
## The first threshold sits just above what a body at its starting caps is worth, so the
## opening line is the one a new player actually hears — a scale whose first step is already
## behind you at character creation is a scale with one fewer line than it looks.
const RENOWN: Array = [
	{
		"at": 1800, "label": "a stranger",
		"greeting": "You are new here. It is in the shoulders.",
	},
	{
		"at": 4200, "label": "known by sight",
		"greeting": "You have grown since last I looked. It shows in how you stand.",
	},
	{
		"at": 10000, "label": "talked about",
		"greeting": "They say your name now, further down the road. They say it carefully.",
	},
	{
		"at": 1.0e300, "label": "a thing the road warns about",
		"greeting": "I have heard what you did. I would rather not be the one who repeats it.",
	},
]

## The conversations that end in a decision. Each option's effect is applied once and the
## decision is closed for good; the option not taken is recorded as explicitly *not* taken, so
## that a person can be sorry about it in a later line rather than forgetting it happened.
##
## Gates are on things the player can see they have done — a technique attained, a camp seen —
## rather than on a level, because a gate nobody can read is a door with no handle.
const DECISIONS: Dictionary = {
	"path": {
		"speaker": "ren",
		"open": "You can be taught one thing today, and only one, because the two of them are "
			+ "opposite answers. A heavier hand, or a deeper breath. Which is it?",
		"options": [
			{
				"key": "fist", "label": "Teach me the heavier hand",
				"blurb": "ATTACK cap permanently +8. The breath is closed to you.",
				"effect": {"kind": "cap", "stat": "attack", "amount": 8.0},
			},
			{
				"key": "breath", "label": "Teach me the deeper breath",
				"blurb": "QI cap permanently +60. The hand is closed to you.",
				"effect": {"kind": "cap", "stat": "qi", "amount": 60.0},
			},
		],
		"after": "\"Then that is what you are. Come back when you have used it.\"",
	},
	"camp": {
		"speaker": "xia",
		"gate": "attained",
		"open": "You have been out there, so you know. The raiders burn the road for whoever "
			+ "walks it — and they were somebody's sons before they were anybody's problem. "
			+ "Burn their camp with them in it, or take the road past it and let them live?",
		"options": [
			{
				"key": "burn", "label": "The road is worth more than they are",
				"blurb": "The nearest raider camp is cleared for good. +45 crystals.",
				"effect": {"kind": "camp", "choice": "burn"},
			},
			{
				"key": "spare", "label": "Let them keep their fire",
				"blurb": "Those raiders will never raise a hand to you again. DEFENSE cap +6.",
				"effect": {"kind": "camp", "choice": "spare"},
			},
		],
		"after": "\"I will remember you said it, whatever comes of it.\"",
	},
	"ledger": {
		"speaker": "bo",
		"open": "Found this on the road. The elder's own ledger, with his prices in it. I could "
			+ "walk it back to him, or we could both just... not notice.",
		"options": [
			{
				"key": "return", "label": "He should have his book",
				"blurb": "The elder's shelf gets 12% cheaper, permanently.",
				"effect": {"kind": "discount", "amount": 0.88},
			},
			{
				"key": "keep", "label": "Then let it stay lost",
				"blurb": "+60 crystals in his pocket and yours, once.",
				"effect": {"kind": "crystals", "amount": 60},
			},
		],
		"after": "\"Road's long. I will be seeing you on it.\"",
	},
}

## The conversation on screen: empty when nobody is being spoken to.
## `speaker`, `line`, `options` (each with `key`, `label`, `blurb`), and `decision`.
var _conversation: Dictionary = {}


## True while somebody is being spoken to. The controller reads this to root the body.
func talking() -> bool:
	return not _conversation.is_empty()


func cast() -> Array:
	return CAST.duplicate(true)


func person(id: String) -> Dictionary:
	for entry: Dictionary in CAST:
		if String(entry["id"]) == id:
			return entry
	return {}


func display_name(id: String) -> String:
	var entry: Dictionary = person(id)
	return String(entry.get("name", "Somebody"))


# ------------------------------------------------------------------- renown

## The step of renown the body has reached, as an index into RENOWN.
func renown_tier() -> int:
	var power: float = float(PlayerData.power_level())
	for i in RENOWN.size():
		if power < float(RENOWN[i]["at"]):
			return i
	return RENOWN.size() - 1


func renown_label() -> String:
	return String(RENOWN[renown_tier()]["label"])


## How this person sees you, which is a line that changes as you grow. Kept apart from the
## decision lines on purpose: a person's opinion of you should not be the same thing as a
## transaction, or the world reads as vending machines with faces.
func greeting_for(id: String) -> String:
	var entry: Dictionary = person(id)
	if entry.is_empty():
		return ""
	return "%s: \"%s\"" % [String(entry["name"]), String(RENOWN[renown_tier()]["greeting"])]


# ------------------------------------------------------------------- talking

## Opens a conversation with `id`. Public and free of the input layer, so a test drives
## exactly what the interact key drives.
func begin(id: String) -> Dictionary:
	var entry: Dictionary = person(id)
	if entry.is_empty():
		return {}
	var decision: String = String(entry.get("decision", ""))
	var line: String = String(entry["line"])
	var options: Array = []
	if decision != "" and not decided(decision) and gate_open(decision):
		var spec: Dictionary = DECISIONS[decision]
		line = String(spec["open"])
		for option: Dictionary in (spec["options"] as Array):
			options.append({
				"key": String(option["key"]),
				"label": String(option["label"]),
				"blurb": String(option["blurb"]),
			})
	if options.is_empty():
		# The door they closed, said out loud. A person who has nothing left to ask is still a
		# person, and the thing they remember about you is the thing you decided.
		var memory: String = _old_decision_line(decision)
		if memory != "":
			line = "%s %s" % [line, memory]
	_conversation = {
		"speaker": String(entry["name"]),
		"role": String(entry.get("role", "")),
		"line": line,
		"options": options,
		"decision": decision if not options.is_empty() else "",
	}
	talking_changed.emit()
	conversation_changed.emit()
	return _conversation


## The line a person gives when their decision is already behind you — named rather than
## implied, so the player can hear that the door they closed is closed.
func _old_decision_line(decision: String) -> String:
	if decision == "" or not decided(decision):
		return ""
	var picked: String = PlayerData.chosen_option(decision)
	for option: Dictionary in (DECISIONS[decision]["options"] as Array):
		if String(option["key"]) == picked:
			return "You already chose. %s" % String(option["blurb"])
	return ""


func close() -> void:
	if _conversation.is_empty():
		return
	_conversation = {}
	talking_changed.emit()
	conversation_changed.emit()


## What the panel should be showing.
func conversation() -> Dictionary:
	return _conversation.duplicate(true)


func options() -> Array:
	return (_conversation.get("options", []) as Array).duplicate(true)


# ------------------------------------------------------------------- deciding

## True when a decision is open to this body. The gate is deliberately about something the
## player has *done*, so the offer lands at a moment they can recognise.
func gate_open(decision: String) -> bool:
	var spec: Dictionary = DECISIONS.get(decision, {})
	if spec.is_empty():
		return false
	match String(spec.get("gate", "")):
		"attained":
			return PlayerData.attained_count() >= 1
		_:
			return true


func decided(decision: String) -> bool:
	return PlayerData.decisions.has(decision)


## Answers the decision that is on screen. Returns the line that closes the conversation,
## with the effect already applied — so the caller never reports a choice the world did not
## record.
func choose(key: String) -> Dictionary:
	var decision: String = String(_conversation.get("decision", ""))
	if decision == "" or decided(decision):
		return {}
	var spec: Dictionary = DECISIONS[decision]
	for option: Dictionary in (spec["options"] as Array):
		if String(option["key"]) != key:
			continue
		# Recorded *before* the effect, so an effect that cannot be given (a camp that is
		# already gone) still leaves the conversation decided rather than repeatable.
		var subject: String = subject_for(option["effect"])
		PlayerData.note_decision(decision, key, subject)
		apply(option["effect"], subject)
		var line: String = String(spec["after"])
		_conversation["options"] = []
		_conversation["line"] = line
		_conversation["decision"] = ""
		PlayerData.log_message.emit(
			"%s: %s" % [String(_conversation["speaker"]), line], "breakthrough"
		)
		conversation_changed.emit()
		return {"decision": decision, "key": key, "line": line}
	return {}


## The name of the thing an effect is about, which is what makes the decision re-appliable to
## a world rebuilt from scratch at the next launch. Empty for effects about the body itself.
func subject_for(effect: Dictionary) -> String:
	if String(effect.get("kind", "")) != "camp":
		return ""
	return _nearest_camp_name()


## Applies one effect. Every branch here has to be visible from outside the save file, or the
## choice is a flag in a JSON blob and nothing else.
func apply(effect: Dictionary, subject: String = "") -> void:
	match String(effect.get("kind", "")):
		"cap":
			PlayerData.grant_cap(String(effect["stat"]), float(effect["amount"]))
		"crystals":
			PlayerData.add_crystals(int(effect["amount"]))
		"discount":
			var shop: Node = get_node_or_null("/root/Shop")
			if shop != null and shop.has_method("set_discount"):
				shop.call("set_discount", float(effect["amount"]))
		"camp":
			_resolve_camp(String(effect["choice"]), subject)


## The camp decision, which is the one the player can walk out and look at. The nearest camp
## to the fire is the one Xia has been watching: burning it takes its raiders out of the
## world, and sparing it leaves them standing at a fire that will not hunt you again.
func _resolve_camp(choice: String, camp_name: String = "") -> void:
	if camp_name == "":
		camp_name = _nearest_camp_name()
	if camp_name == "":
		return
	var camps: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	if camps == null or not camps.has_method("resolve_camp"):
		return
	camps.call("resolve_camp", camp_name, choice, true)
	if choice == "spare":
		PlayerData.grant_cap("defense", 6.0)


## The name of the camp the conversation is about, or "" when there is no world to ask.
func _nearest_camp_name() -> String:
	var camps: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	if camps == null or not camps.has_method("nearest_camp"):
		return ""
	var camp: Dictionary = camps.call("nearest_camp", Vector3.ZERO)
	return String(camp.get("name", ""))


## Every decision the body has made, for the tests and for anything that wants to know.
func decisions() -> Dictionary:
	return PlayerData.decisions.duplicate()
