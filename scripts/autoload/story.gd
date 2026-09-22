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

	# ------------------------------------------------------------- the first hour
	#
	# The six events of `EVENTS`, in the order `Prologue` tells them. Each one is a *moment* with a
	# price, and the price is nearly always reputation — because reputation is the only number in
	# this game that is paid back later, in a cheaper shelf, a watch that looks the other way, or a
	# gate that will not open. That delay is the whole design: nothing here is a "buff" and a
	# player who picks the greedy option six times will not find out for another hour, in a village
	# where the merchant has stopped smiling and the price has quietly gone up.
	"gate": {
		# The caption over each scene. Not a name, because there is nobody speaking — the line is
		# the *place*, and "The gate · " over it is how the player is told that what is talking is
		# the world rather than a person, without a second widget to say so.
		"speaker": "The gate",
		"open": "The gate is a wall with a man in front of it. \"You are not from here. State "
			+ "your business, or walk the road round.\"",
		"options": [
			{
				"key": "trade", "label": "I am a cultivator, and I am here to trade",
				"blurb": "They mark you down as a guest. Hollowmere is better disposed to you.",
				"effect": {"kind": "rep", "amount": 4, "reason": "you announced yourself"},
			},
			{
				"key": "nothing", "label": "I am nobody, and I am passing through",
				"blurb": "A gate is happier with a nobody, and nobody is glad to see you.",
				"effect": {"kind": "rep", "amount": -2, "reason": "you would not say"},
			},
		],
		"after": "He steps aside, and writes something in the book by the gate.",
	},
	"caravan": {
		"speaker": "The bend in the road",
		"open": "A cart sits on its side where the road bends, one wheel still turning. The driver "
			+ "is under it, and the crates are spilled where they fell.",
		"options": [
			{
				"key": "help", "label": "Get the cart off him",
				"blurb": "He will remember the face. The villages hear about it first.",
				"effect": {"kind": "rep", "amount": 6, "reason": "you pulled a driver out"},
			},
			{
				"key": "loot", "label": "Take the crates and go",
				"blurb": "+40 crystals, and the road learns what your hands are for.",
				"effect": {"kind": "crystals", "amount": 40},
			},
		],
		"after": "The road is quiet again, and the wheel stops turning.",
	},
	"notice": {
		"speaker": "The crossroads",
		"open": "There is a paper nailed to the post at the crossroads, and it is *you*: a face "
			+ "badly drawn, a name you have never used, and a price under it.",
		"options": [
			{
				"key": "tear", "label": "Tear it down",
				"blurb": "Nobody sees it happen. Somebody always does.",
				"effect": {"kind": "crime", "crime": "arrogance", "detail": "A notice taken off its post"},
			},
			{
				"key": "leave", "label": "Leave it hanging",
				"blurb": "Let them read a description that is not you. The village notices you did not.",
				"effect": {"kind": "rep", "amount": 3, "reason": "the notice was left alone"},
			},
		],
		"after": "Somewhere behind the wall a bell rings twice, which is nothing at all.",
	},
	"mark": {
		"speaker": "The stone you passed",
		"open": "Scratched into the stone you walked past earlier, low down where a hand would "
			+ "reach: nine strokes, and one of them crossed out. It was not there this morning.",
		"options": [
			{
				"key": "touch", "label": "Put your hand on it",
				"blurb": "QI cap permanently +24. Whatever it is, it knows your hand now.",
				"effect": {"kind": "cap", "stat": "qi", "amount": 24.0},
			},
			{
				"key": "turn", "label": "Walk on and do not look back",
				"blurb": "DEFENSE cap permanently +8. Some invitations are answered by declining.",
				"effect": {"kind": "cap", "stat": "defense", "amount": 8.0},
			},
		],
		"after": "The stone is cold, and the cold does not leave your hand.",
	},
	"tally": {
		"speaker": "The cart of pots",
		"open": "A woman with a cart of pots takes one look at your shoes, your hands and your "
			+ "belt, and names a price before you have asked for anything. \"Or you can owe me.\"",
		"options": [
			{
				"key": "pay", "label": "Pay what she asks, and walk on",
				"blurb": "She marks you down as a customer who pays. That is worth more than it sounds.",
				"effect": {"kind": "rep", "amount": 4, "reason": "you paid the asking price"},
			},
			{
				"key": "owe", "label": "Take the credit",
				"blurb": "+55 crystals now. The debt is the villages' business, not hers.",
				"effect": {"kind": "rep", "amount": -5, "reason": "you took credit and walked"},
			},
		],
		"after": "She writes it down either way. Everyone here writes everything down.",
	},
	"oath": {
		"speaker": "The road, at the end of the first day",
		"open": "Three villages, one road, and a tower at the end of it that has been standing "
			+ "there longer than any of them. They will ask you, sooner or later, what you came for.",
		"options": [
			{
				"key": "villages", "label": "The people on the road",
				"blurb": "Every village takes you more seriously. The tower will not care.",
				"effect": {"kind": "rep", "amount": 6, "village": "all",
					"reason": "word of what you came for"},
			},
			{
				"key": "tower", "label": "The top of the tower",
				"blurb": "ATTACK cap permanently +10, and no village will thank you for it.",
				"effect": {"kind": "cap", "stat": "attack", "amount": 10.0},
			},
		],
		"after": "The road does not answer. It has heard it before.",
	},
}

## Places that speak. A door is not a person and does not pretend to be one — but the tower's
## door has a question to ask (the stairhead or the frontier) and the landing has three ways
## out of it, and the dialogue panel is already the interface the player has learned for
## "something is asking me a question". The alternative was three new keybinds.
const PLACES: Array = ["tower_door", "tower_landing"]

## What the door says when it is locked, so a refusal names the thing that would open it.
const DOOR_REFUSED := "The door does not move. It is waiting for a body with more behind it than it has in front of it."

## The conversation on screen: empty when nobody is being spoken to.
##
## `speaker`, `role`, `line`, `options` (each with `key`, `label`, `blurb`, and optionally a
## `panel` to open or an `effect` to apply), `decision` when the options belong to one of the
## table's closed choices, and `kind` — "decision" or "menu" — which is what tells `choose`
## which of the two flows it is answering.
var _conversation: Dictionary = {}

## The scripted events of the first hour, in the order they are told.
##
## These are the same machinery as a conversation — the same panel, the same two options, the same
## record of what was chosen — with one thing missing: a *speaker*. The first hour of this game is
## not six people talking, it is six things happening to a body that has just arrived: a watchman
## who will not let it in, a caravan on its side on the road, a notice with its own description on
## it, a mark on a wall it has already walked past. Nobody's name is over any of them, which is
## exactly what makes them read as a world rather than as a cast.
##
## `Prologue` decides *when* each one happens; this file only knows what they say.
const EVENTS: Array = ["gate", "caravan", "notice", "mark", "tally", "oath"]


## Opens a scripted event by id, if it has not already happened and its gate is open. The same
## door as `begin`, so the panel, the record and the effects cannot tell the difference.
func begin_event(id: String) -> Dictionary:
	if not EVENTS.has(id) or decided(id) or not gate_open(id):
		return {}
	var spec: Dictionary = DECISIONS.get(id, {})
	if spec.is_empty():
		return {}
	var options: Array = []
	for option: Dictionary in (spec["options"] as Array):
		options.append({
			"key": String(option["key"]),
			"label": String(option["label"]),
			"blurb": String(option["blurb"]),
		})
	if options.is_empty():
		return {}
	var line: String = String(spec["open"])
	var voice: String = String(spec.get("voice", ""))
	if voice != "":
		Voice.speak(voice)
	_conversation = {
		"speaker": String(spec.get("speaker", "")),
		"role": "",
		"line": line,
		"options": options,
		"decision": id,
	}
	talking_changed.emit()
	conversation_changed.emit()
	return _conversation


## The events still ahead of this body, so the prologue's director can be told what to wait for.
func events_done() -> int:
	var done: int = 0
	for id: String in EVENTS:
		if decided(id):
			done += 1
	return done


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
	# Villages and places first: the camp's three have ids that `person` knows, and everything
	# else that can be spoken to lives in one of the two tables below.
	var village_person: Dictionary = Villages.person(id)
	if not village_person.is_empty():
		return _speak_village(village_person)
	if PLACES.has(id):
		return _speak_place(id)
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
	# A menu is not a decision and must not be recorded as one: the shop is answered as often as
	# the player likes, and writing it into `decisions` would have made "what did you buy at
	# Hollowmere" a permanent fact of the save.
	if String(_conversation.get("kind", "")) == "menu":
		return _choose_menu(key)
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
	match String(effect.get("kind", "")):
		"camp":
			return _nearest_camp_name()
		"rep", "crime":
			# Which village the choice was about, if the effect did not name one. Recorded with the
			# decision for the same reason the camp's name is: the place it happened is the half of
			# the choice the player can walk back to and look at.
			if String(effect.get("village", "nearest")) != "nearest":
				return String(effect.get("village", ""))
			return _nearest_village_id()
	return ""


## The village the body is standing in the reach of, for a decision whose subject is "this place".
func _nearest_village_id() -> String:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return ""
	var entry: Dictionary = Villages.nearest_to(player.global_position)
	return String(entry.get("id", ""))


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
		"rep":
			# Reputation, as an *effect* rather than as a reward: which is the whole point of the
			# first hour. A village that trusts you charges you less, a village that hates you puts
			# its watch on you — so a line of dialogue that moves this number is a line of dialogue
			# with a price on it, however long it takes to be paid.
			var amount: int = int(effect.get("amount", 0))
			var reason: String = String(effect.get("reason", "something you said"))
			if String(effect.get("village", "nearest")) == "all":
				for entry: Dictionary in Villages.all():
					Villages.adjust_rep(String(entry["id"]), amount, reason)
			elif subject != "":
				Villages.adjust_rep(subject, amount, reason)
		"crime":
			# The other half of the same idea: a choice can also be *against the law*, and the law
			# is per village and remembered for days.
			if subject != "":
				Law.add_crime(String(effect.get("crime", "trouble")), subject,
					String(effect.get("detail", "")))


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


# ----------------------------------------------------------- the village people

## One of a village's own. The *role* is the whole behaviour, exactly as it is in the world:
## a keeper has the village's business, a merchant has its share of the valley's shelves, and
## the folk have nothing but a line that changes with how well the place knows you.
func _speak_village(who: Dictionary) -> Dictionary:
	var speech: Dictionary = _village_speech(
		String(who["role"]), String(who["village"]), String(who["name"])
	)
	_conversation = {
		"speaker": String(who["name"]),
		"role": String(who["role"]),
		"line": speech["line"],
		"options": speech["options"],
		"decision": "",
		"kind": "menu",
		"village": String(who["village"]),
		"person": String(who["id"]),
	}
	talking_changed.emit()
	conversation_changed.emit()
	return _conversation


## What each role says and which doors they hold.
##
## The greeting is the same renown line the camp's three use, because a pedlar in a village you
## have never visited should still have *heard* of you if you are the reason the road is quiet.
## A village with its gate in the ground says so before it says anything else.
##
## Every role, deliberately, rather than only the keeper: the stalls are ash, so the merchant has
## nothing to sell and the healer has nowhere to work, and a player who had to find the *right*
## person to hand over the crystals would be doing paperwork. The role's own conversation is kept
## underneath — the shelf is shut, but the chain, the board and the wound are still there to be
## asked about — so the village is damaged rather than replaced.
func _village_speech(role: String, village_id: String, speaker: String) -> Dictionary:
	var speech: Dictionary = _village_role_speech(role, village_id, speaker)
	if Raids.is_sacked(village_id):
		return _sacked_speech(village_id, speech)
	return speech


func _sacked_speech(village_id: String, speech: Dictionary) -> Dictionary:
	var cost: int = Raids.repair_cost(village_id)
	var name_of: String = String(Villages.def(village_id).get("name", village_id))
	var short: int = cost - PlayerData.crystals
	var options: Array = [{
		"key": "mend",
		"label": "Mend the gate — %d crystals" % cost,
		"blurb": ("They will not start it without the price in hand." if short <= 0
			else "You are %d crystals short of it." % short),
		"effect": {"kind": "mend"},
	}]
	for option: Dictionary in (speech.get("options", []) as Array):
		options.append(option)
	return {
		"line": "%s is a gap in a fence, and it can be seen from the road."
			% name_of + " Nobody has anything for sale until it is standing again.",
		"options": options,
	}


func _village_role_speech(role: String, village_id: String, speaker: String) -> Dictionary:
	var village: Dictionary = Villages.def(village_id)
	var village_name: String = String(village.get("name", ""))
	var greeting: String = String(RENOWN[renown_tier()]["greeting"])
	# An outlaw is refused before anything else is said. The shops shut at the top rung, and a
	# merchant who sells to an outlaw is an outlaw — so the closed door has to be *said*.
	if Law.shops_closed(village_id) and role != "folk" and role != "keeper":
		return {
			"line": "\"%s\" %s will not serve you, and does not pretend otherwise."
				% [greeting, village_name],
			"options": [],
		}
	var first_time: bool = not Met.has(speaker)
	Met[speaker] = true
	match role:
		"keeper":
			return _keeper_speech(village_id, village_name, greeting)
		"merchant":
			return {
				"line": "\"%s\" %s\"%s\"" % [greeting, String(village.get("welcome", "")), ""],
				"options": [
					{"key": "shop", "label": "Show me your shelf",
						"blurb": "Wares, pieces and pills — %s's own share of the valley's." % village_name,
						"panel": "shop"},
					{"key": "later", "label": "Another time"},
				],
			}
		"smith":
			return {
				"line": "\"%s\" %s\"%s\"" % [greeting, String(village.get("welcome", "")), ""],
				"options": [
					{"key": "forge", "label": "Put something on the anvil",
						"blurb": "Bring the material and the crystals and it comes out better.",
						"panel": "forge"},
					{"key": "later", "label": "Another time"},
				],
			}
		"healer":
			if PlayerData.wounded():
				var cost: int = _heal_cost()
				return {
					"line": "\"%s\" You are carrying %d wound%s. They do not close on their own, and the "
						% [greeting, PlayerData.wounds, "" if PlayerData.wounds == 1 else "s"]
						+ "road out there is not getting shorter.",
					"options": [
						{"key": "treat", "label": "Close them — %d crystals" % cost,
							"blurb": "All of them, at once.",
							"effect": {"kind": "heal", "cost": cost}},
						{"key": "shop", "label": "What have you got?", "panel": "shop"},
						{"key": "later", "label": "I will live"},
					],
				}
			return {
				"line": "\"%s\" Nothing wrong with you that a walk would not fix. Pills, though, are "
					% greeting + "cheap today.",
				"options": [
					{"key": "shop", "label": "Then show me the pills", "panel": "shop"},
					{"key": "later", "label": "Another time"},
				],
			}
		"clerk":
			return {
				"line": "\"%s\" %s has a board, and the board has names on it." % [greeting, village_name],
				"options": [
					{"key": "bounties", "label": "What names?", "panel": "bounties"},
					{"key": "later", "label": "Not today"},
				],
			}
		_:
			return {
				"line": "\"%s\" %s" % [greeting, Villages.folk_line(village_id)],
				"options": [],
			}


## The keeper: the village's business, in order, with the parcel at the end of each chain sent
## on to the next village.
func _keeper_speech(village_id: String, village_name: String, greeting: String) -> Dictionary:
	var village: Dictionary = Villages.def(village_id)
	if not Villages.started_chain(village_id):
		return {
			"line": "\"%s\" %s The village has one thing it cannot do for itself, and you are "
				% [greeting, String(village.get("welcome", ""))]
				+ "walking out of that gate either way.",
			"options": [
				{"key": "listen", "label": "Tell me what it is",
					"blurb": "This is the village's whole story, and it is three steps long.",
					"effect": {"kind": "open_chain"}},
				{"key": "later", "label": "Not yet"},
			],
		}
	var step: Dictionary = Villages.current_step(village_id)
	if step.is_empty():
		return {
			"line": "\"%s\" %s has nothing left to ask of you. That is not the same as nothing "
				% [greeting, village_name] + "left to say, but it is what I can do.",
			"options": [
				{"key": "board", "label": "What did I do for you?", "panel": "board"},
			],
		}
	if Villages.step_ready(village_id):
		return {
			"line": "\"%s\" Then it is done. %s" % [greeting, String(step["detail"])],
			"options": [
				{"key": "claim", "label": "Hand it over",
					"blurb": "A step finished is a step paid.",
					"effect": {"kind": "claim"}},
			],
		}
	var progress: String = "%d%%" % int(round(Villages.step_progress(village_id) * 100.0))
	return {
		"line": "\"%s\" %s  (%s asked, %s done)" % [greeting, String(step["detail"]), String(step["title"]), progress],
		"options": [
			{"key": "board", "label": "Say it again", "panel": "board"},
		],
	}


## What a healer charges for a body full of holes. Rising with each one, so the third death
## costs more than the first — but never more than a raider's purse or two can settle.
func _heal_cost() -> int:
	return 24 + 22 * PlayerData.wounds


# ------------------------------------------------------------------ menus

## Answers one of a menu's options. A menu is a *door*: it either opens a panel or applies an
## effect, and it is never recorded in the save — which is the difference between "what have you
## got for sale" and "what did you decide about the raiders".
func _choose_menu(key: String) -> Dictionary:
	var options: Array = _conversation.get("options", [])
	var picked: Dictionary = {}
	for option: Dictionary in options:
		if String(option["key"]) == key:
			picked = option
			break
	if picked.is_empty():
		return {}
	var village_id: String = String(_conversation.get("village", ""))
	var panel: String = String(picked.get("panel", ""))
	if panel != "":
		# The panel *is* the conversation: the dialogue closes and the shelf opens, because a
		# shop drawn underneath a speech bubble is two things asking to be read at once.
		var hud: Node = get_tree().get_first_node_in_group("hud")
		close()
		if hud != null and hud.has_method("show_panel"):
			hud.call("show_panel", panel, village_id)
		return {"panel": panel, "village": village_id}
	var line: String = ""
	if picked.has("effect"):
		line = _apply_menu_effect(picked["effect"])
	if line == "":
		close()
		return {}
	# An effect with something to say about itself keeps the panel open for exactly as long as it
	# takes to read it, and closes on the next key like any other line.
	_conversation["line"] = line
	_conversation["options"] = []
	PlayerData.log_message.emit(
		"%s: %s" % [String(_conversation.get("speaker", "")), line], "info"
	)
	conversation_changed.emit()
	return {"key": key, "line": line}


## Every effect a menu can have. Returns the line to print, or "" when the thing simply
## happened and the panel should close.
func _apply_menu_effect(effect: Dictionary) -> String:
	var village_id: String = String(_conversation.get("village", ""))
	var site: Node = get_tree().get_first_node_in_group("tower_site")
	match String(effect.get("kind", "")):
		"open_chain":
			Villages.open_chain(village_id)
			var step: Dictionary = Villages.current_step(village_id)
			if step.is_empty():
				return "Then there is nothing to ask."
			return String(step["detail"])
		"claim":
			var paid: Dictionary = Villages.claim(village_id)
			if paid.is_empty():
				return "Not yet — there is more to do before that."
			var done: Dictionary = paid["step"]
			var out: String = "It is done: %s. %s" % [
				String(done["title"]),
				("" if (paid["paid"] as Array).is_empty() else ", ".join(paid["paid"]) + "."),
			]
			var next: Dictionary = Villages.current_step(village_id)
			if not next.is_empty():
				out += " Next: %s" % String(next["detail"])
			return out
		"mend":
			if not Raids.is_sacked(village_id):
				return "It is standing. Whatever you were about to pay for, it was not that."
			if not Raids.can_repair(village_id):
				return "You cannot cover the price, and nobody in the valley works on credit."
			Raids.repair(village_id)
			return "The gate goes back up, and the first stall opens before the last post is in."
		"heal":
			var cost: int = int(effect.get("cost", 0))
			if not PlayerData.spend_crystals(cost):
				return "You cannot cover the fee, and she does not work on credit."
			PlayerData.clear_wounds()
			PlayerData.restore_all()
			return "It costs %d crystals and hurts, and then you are whole again." % cost
		"tower_enter":
			if site == null or not site.has_method("walk_in"):
				return "The door does not answer."
			if not bool(site.call("walk_in", bool(effect.get("frontier", false)))):
				return "The door does not answer."
			return ""
		"tower_leave":
			if site != null and site.has_method("step_out"):
				site.call("step_out")
			return ""
		"ascend":
			if Tower.ascend():
				return ""
			return "There is nothing above this one that will let you in."
		"descend":
			if Tower.descend():
				return ""
			return "There is nothing below you but the ground."
	return ""


## The people this body has been introduced to, so a greeting can notice a first meeting.
## Runtime only: an introduction is not progress, and a save that remembered every pedlar in
## the valley would be remembering a conversation the player has no way to look up.
var Met: Dictionary = {}


# --------------------------------------------------------------------- places

## Somewhere that asks a question. Two of them, and both belong to the tower.
func _speak_place(id: String) -> Dictionary:
	var speech: Dictionary = {}
	match id:
		"tower_door":
			speech = _tower_door_speech()
		"tower_landing":
			speech = _tower_landing_speech()
		_:
			return {}
	_conversation = {
		"speaker": String(speech.get("speaker", "The Tower")),
		"role": "place",
		"line": speech["line"],
		"options": speech["options"],
		"decision": "",
		"kind": "menu",
		"village": "towerfall",
	}
	talking_changed.emit()
	conversation_changed.emit()
	return _conversation


## The door's question: the whole climb again, or the floor where the last one ended. A player
## who has to re-fight forty floors they already know to find out whether they can beat the
## forty-first has been given content where they should have been given a *stair*.
func _tower_door_speech() -> Dictionary:
	if not Tower.unlocked():
		return {
			"speaker": "The Tower's Door",
			"line": "%s  %s" % [DOOR_REFUSED, Tower.locked_reason()],
			"options": [],
		}
	var options: Array = [
		{"key": "stairhead", "label": "Take the stair from the ground floor",
			"blurb": "Ninety-nine floors you have not seen, and the ones you have are empty.",
			"effect": {"kind": "tower_enter", "frontier": false}},
	]
	if Tower.deepest > 0:
		options.append({
			"key": "frontier", "label": "Step off at floor %d" % Tower.frontier(),
			"blurb": "The deepest anybody has taken this stair: %d of %d." % [Tower.deepest, Tower.FLOORS],
			"effect": {"kind": "tower_enter", "frontier": true},
		})
	options.append({"key": "later", "label": "Not yet"})
	return {
		"speaker": "The Tower's Door",
		"line": "Stone, four hundred metres of it, and a doorway with no gate in it. "
			+ "It has been open the whole time. Deepest so far: %d of %d." % [Tower.deepest, Tower.FLOORS],
		"options": options,
	}


## The landing's question: up, down, or out.
func _tower_landing_speech() -> Dictionary:
	var site: Node = get_tree().get_first_node_in_group("tower_site")
	var open_here: bool = false
	if site != null and site.has_method("floor_open"):
		open_here = bool(site.call("floor_open"))
	var plan_here: Dictionary = Tower.plan(Tower.current)
	var options: Array = []
	if open_here:
		options.append({
			"key": "ascend", "label": "Go up to floor %d" % mini(Tower.current + 1, Tower.FLOORS),
			"blurb": "The way up is open.", "effect": {"kind": "ascend"},
		})
	if Tower.current > 1:
		options.append({
			"key": "descend", "label": "Go down one floor",
			"blurb": "Ever downward is free, and a cleared floor stays clear.",
			"effect": {"kind": "descend"},
		})
	options.append({
		"key": "out", "label": "Leave the tower",
		"blurb": "You keep the depth you have taken. You lose nothing but the climb.",
		"effect": {"kind": "tower_leave"},
	})
	options.append({"key": "stay", "label": "Stay on this landing"})
	return {
		"speaker": "Floor %d" % Tower.current,
		"line": "%s  %s" % [String(plan_here["band_name"]), String(plan_here["line"])],
		"options": options,
	}
