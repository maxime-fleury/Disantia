extends SceneTree
## One-shot project bootstrap.
##
##   godot --headless --path . --script res://tools/setup_project.gd
##
## The input map is registered through the ProjectSettings API rather than typed
## into project.godot by hand, so the file that comes out is byte-for-byte the
## format the editor itself writes and Project Settings -> Input Map shows every
## action. Safe to re-run: it only sets the keys listed below.
##
## Physical keycodes are used for WASD so the layout works on AZERTY/Dvorak too;
## Shift, Space and the letter keys that are not movement use logical keycodes.


func _initialize() -> void:
	_apply("application/run/main_scene", "res://scenes/main.tscn")
	_apply("application/run/max_fps", 0)

	# ProjectSettings serialises keys in insertion order, so an autoload added here
	# later is initialised later. The order that actually matters is PlayerData
	# before Cultivation, which applies the part of the save that belongs to it.
	# Training and Audio depend on nothing at load time, and SelfTest is inert
	# unless --selftest is passed and waits frames before it touches anything.
	_apply("autoload/PlayerData", "*res://scripts/autoload/player_data.gd")
	_apply("autoload/Cultivation", "*res://scripts/autoload/cultivation.gd")
	_apply("autoload/Training", "*res://scripts/autoload/training.gd")
	_apply("autoload/Audio", "*res://scripts/autoload/audio.gd")
	_apply("autoload/Quests", "*res://scripts/autoload/quests.gd")
	_apply("autoload/SelfTest", "*res://tests/self_test.gd")

	_apply("display/window/size/viewport_width", 1280)
	_apply("display/window/size/viewport_height", 720)
	_apply("display/window/stretch/mode", "canvas_items")
	_apply("display/window/stretch/aspect", "expand")

	_apply("physics/3d/default_gravity", 9.8)

	# Imported textures, not the source PNGs, are what end up inside the exported
	# pack, so the art budget for the browser build is set here. The source art in
	# assets/ is 2K-to-4K; the stylized models read fine at a quarter of that, and
	# mipmaps matter because the terrain props are viewed at a distance.
	# 512 rather than 1024: there are forty-odd textures in play now, and at 2K
	# they would be a quarter of a gigabyte of VRAM in a browser tab.
	_apply("importer_defaults/texture", {
		"compress/mode": 0,
		"mipmaps/generate": true,
		"process/size_limit": 512,
	})

	# Web-friendly defaults: no MSAA (it is a big cost on integrated GPUs and in
	# browsers) and the compatibility renderer, which is the only one WebGL2 can
	# support.
	_apply("rendering/renderer/rendering_method", "gl_compatibility")
	_apply("rendering/renderer/rendering_method.mobile", "gl_compatibility")
	_apply("rendering/anti_aliasing/quality/msaa_3d", 0)
	_apply("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 1)

	_move_action("move_forward", [ KEY_W, KEY_UP ], true)
	_move_action("move_backward", [ KEY_S, KEY_DOWN ], true)
	_move_action("move_left", [ KEY_A, KEY_LEFT ], true)
	_move_action("move_right", [ KEY_D, KEY_RIGHT ], true)
	_move_action("jump", [ KEY_SPACE ], false)
	_move_action("sprint", [ KEY_SHIFT ], false)
	_move_action("meditate", [ KEY_C ], false)
	_move_action("breakthrough", [ KEY_B ], false)
	_move_action("quick_save", [ KEY_F5 ], false)
	# The offensive verb answers to a click as well as to F. With a camera behind the
	# character the hand is already on the mouse, and making it reach for F is the
	# difference between attacking and thinking about attacking. The key stays bound
	# for anyone who prefers it.
	_move_action("strike", [ KEY_F ], false, [ MOUSE_BUTTON_LEFT ])
	# A dash is the escape verb, so it sits on the other mouse button, with a key for
	# the same reason.
	_move_action("dash", [ KEY_Q ], false, [ MOUSE_BUTTON_RIGHT ])
	_move_action("interact", [ KEY_E ], false)
	_move_action("train_pushups", [ KEY_1 ], false)
	_move_action("train_squats", [ KEY_2 ], false)
	_move_action("train_stance", [ KEY_3 ], false)
	# Qi Pressure. A combat technique rather than a housekeeping key, but kept off the
	# movement hand for the same reason the drill keys are: it is held for seconds at a
	# time while running, so it cannot share a finger with WASD or with the dash.
	_move_action("qi_pressure", [ KEY_X ], false)
	_move_action("settings", [ KEY_TAB ], false)
	# Folds the stat readout away. Off the movement keys on purpose: it is a
	# housekeeping key, not something the hands need while running.
	_move_action("toggle_stats", [ KEY_V ], false)
	# The old R "ascend" teleport is gone. It was a placeholder for travel before
	# there were roads to walk, and a key that silently moves you somewhere else on
	# the map is not a placeholder any more — it is a way to lose your bearings. The
	# action is deleted from the map as well as unbound, so nothing can read it.
	if InputMap.has_action("ascend"):
		InputMap.erase_action("ascend")
	ProjectSettings.set_setting("input/ascend", null)

	var err: Error = ProjectSettings.save()
	if err != OK:
		printerr("Could not save project.godot: %s" % error_string(err))
	else:
		print("project.godot updated: main scene, autoloads, input map, web-friendly render settings.")
	quit(0 if err == OK else 1)


func _apply(key: String, value: Variant) -> void:
	ProjectSettings.set_setting(key, value)


## `physical` picks InputEventKey.physical_keycode instead of the logical keycode.
## `buttons` binds mouse buttons to the same action, which is why one action can be
## both a key and a click.
func _move_action(action: String, keycodes: Array, physical: bool, buttons: Array = []) -> void:
	var events: Array = []
	for code: Key in keycodes:
		var event := InputEventKey.new()
		if physical:
			event.physical_keycode = code
		else:
			event.keycode = code
		events.append(event)
	for button: MouseButton in buttons:
		var click := InputEventMouseButton.new()
		click.button_index = button
		events.append(click)
	ProjectSettings.set_setting("input/" + action, {
		"deadzone": 0.2,
		"events": events,
	})
