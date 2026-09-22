extends Node
## Which language the valley speaks.
##
## The whole of Disantia's prose is English, written in the source, in the voice of the thing that
## says it — and that is fine for the interface and useless for a player who does not read English.
## So there is one door between the two.
##
## **The English sentence is the key.** This is the decision the rest of the file hangs off. A
## symbolic key (`QUEST_FIRST_STEPS_TITLE`) needs a second file mapping keys to English before a
## single word is translated, which means every sentence exists twice before it exists in French
## once — and a sentence typed in the code and never listed in the table is *invisible*, because
## nothing can find it. With the English as the key, a missing row simply is the English, the game
## is never broken or blank by an untranslated line, and the table can be filled in a hundred rows
## at a time, in any order, without touching the code that prints them.
##
## Two mechanisms, and the split matters:
##
##   * Godot translates a `Control`'s own text on the way to the screen, which is every label,
##     button, heading and panel row in the game — and `Label3D` too, which is every name plate
##     over every head. Static text needs **no wiring at all**: it is in the table or it is
##     English, and switching language re-translates every screen that is already open.
##   * `say()` and `fill()` are for the text the engine cannot see: a line built in code, a log
##     message, anything with numbers substituted into it. A formatted string has to be
##     translated *before* the numbers go in, because `"Floor %d"` and `"Étage %d"` are the same
##     three words in a different order and looking up the finished sentence would find nothing.
##
## A language is a *save* — not a per-session preference — because a French player does not want
## to be asked again every time they open the game.

signal changed

## Locale codes, in the order the settings panel shows them.
const LANGUAGES: Array = ["en", "fr"]
const LANGUAGE_NAMES: Array = ["English", "Français"]
const FRENCH_PATH := "res://scripts/autoload/loc_fr.gd"

var language: int = 0
var _translation: Translation


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_module("loc")
	language = clampi(int(saved.get("language", 0)), 0, LANGUAGES.size() - 1)
	_install()


func save_data() -> Dictionary:
	return {"language": language}


func reset() -> void:
	language = 0
	_install()


# ------------------------------------------------------------------- the door

## Translates a string that the engine will not translate on its own. Returns the string
## unchanged when there is no row for it, which is the whole reason a half-finished table is
## still a working game.
func say(text: String) -> String:
	return TranslationServer.translate(text)


## A template with values in it: `fill("Floor %d of %d — %s", [3, 100, band])`.
##
## The template is translated and *then* the values are substituted, so a translation is free to
## move them around — which French needs more often than English does, because the adjective
## agrees with the noun and the noun is sometimes the number.
func fill(template: String, args: Array) -> String:
	var translated: String = say(template)
	if args.is_empty():
		return translated
	return translated % args


# ------------------------------------------------------------------ choosing

func code() -> String:
	return String(LANGUAGES[clampi(language, 0, LANGUAGES.size() - 1)])


func language_name() -> String:
	return String(LANGUAGE_NAMES[clampi(language, 0, LANGUAGES.size() - 1)])


func is_french() -> bool:
	return code() == "fr"


## Switches language and re-installs the table. Everything on screen is re-translated by the
## engine itself the moment the locale changes; only the text this file built by hand needs a
## nudge, which is what `changed` is for.
func set_language(index: int) -> void:
	var want: int = clampi(index, 0, LANGUAGES.size() - 1)
	if want == language:
		return
	language = want
	PlayerData.mark_dirty()
	_install()
	changed.emit()


func next() -> void:
	set_language((language + 1) % LANGUAGES.size())


## How many rows this language actually has, for the self-test and for anybody wondering how far
## the translation has got. `rows` is 0 for English, which needs none.
func summary() -> Dictionary:
	return {
		"language": code(),
		"name": language_name(),
		"rows": (preload(FRENCH_PATH).TABLE as Dictionary).size() if is_french() else 0,
	}


# ----------------------------------------------------------------- installing

## Hands the table to Godot. Ordered so there is never a moment with two French translations
## installed: the old one comes out before the new one goes in, because two of them would make
## the lookup depend on which was added last.
func _install() -> void:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	if not is_french():
		TranslationServer.set_locale("en")
		return
	var table: Dictionary = preload(FRENCH_PATH).TABLE
	var french := Translation.new()
	french.locale = "fr"
	for key: String in table:
		french.add_message(StringName(key), StringName(String(table[key])))
	_translation = french
	TranslationServer.add_translation(french)
	TranslationServer.set_locale("fr")
