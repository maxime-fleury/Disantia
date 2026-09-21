extends CanvasLayer
## The cultivator's interface.
##
## The chrome (panels, cultivation meter, log) lives in hud.tscn; everything that
## depends on a stat table is built here, so adding a stat to STAT_DEFS grows the
## HUD automatically and adding a drill to Training.EXERCISES grows the training
## list the same way.
##
## The SPEED and JUMP sliders are hard-clamped to what the player has actually
## earned: `max_value` is the earned cap and PlayerData clamps again on write, so
## there is no way to dial in a number you have not trained for. They live in the
## settings panel now rather than on top of the game: reading an untrained slider
## is not what the screen is for while you are running.

const LOG_LINES := 9
const REFRESH_INTERVAL := 0.1
const RESET_CONFIRM_WINDOW_MS := 4000

## The Kenney panel art: a 48x48 frame whose centre fills the whole panel, so one
## texture is both the border and the backing. 23 px is the measured thickness of
## that border — the smallest margin that never slices the corner ornament.
const PANEL_TEXTURE := "res://assets/ui/panel_solid.png"
const PANEL_BORDER: int = 23
const PANEL_PADDING: int = 6

const LOG_COLORS := {
	"gain": "7dff9b",
	"cultivate": "6ec8ff",
	"breakthrough": "ffd76e",
	"damage": "ff7b7b",
	"info": "b9c2cc",
}

const TRAINABLE_ROWS: Array = ["speed", "jump"]

@onready var _realm_label: Label = %RealmLabel
@onready var _coeff_label: Label = %CoeffLabel
@onready var _crystals_label: Label = %CrystalsLabel
@onready var _quest_name: Label = %QuestName
@onready var _quest_bar: ProgressBar = %QuestBar
@onready var _quest_progress: Label = %QuestProgress
@onready var _refinement_label: Label = %RefinementLabel
@onready var _refinement_bar: ProgressBar = %RefinementBar
@onready var _insight_label: Label = %InsightLabel
@onready var _insight_bar: ProgressBar = %InsightBar
@onready var _stat_rows: VBoxContainer = %StatRows
@onready var _drill_rows: VBoxContainer = %DrillRows
@onready var _aura_label: Label = %AuraLabel
@onready var _pressure_label: Label = %PressureLabel
@onready var _hint: Label = %Hint
@onready var _settings_button: Button = %SettingsButton
@onready var _log_text: RichTextLabel = %LogText
@onready var _status_label: Label = %StatusLabel
@onready var _stats_toggle: Button = %StatsToggle
@onready var _stats_title: Label = %StatsTitle
@onready var _quest_panel: PanelContainer = %QuestPanel
@onready var _cultivation_panel: PanelContainer = %CultivationPanel
@onready var _stats_panel: PanelContainer = %StatsPanel
@onready var _action_panel: PanelContainer = %ActionPanel
@onready var _log_panel: PanelContainer = %LogPanel
@onready var _help_panel: PanelContainer = %HelpPanel
@onready var _root: Control = %HudRoot

var _value_labels: Dictionary = {}
var _fill_bars: Dictionary = {}
var _xp_bars: Dictionary = {}
var _sliders: Dictionary = {}
var _slider_readouts: Dictionary = {}
var _drill_readouts: Dictionary = {}
var _drill_bars: Dictionary = {}
var _aura_buttons: Dictionary = {}
var _log_lines: Array[String] = []
var _refresh_accum: float = 0.0

## Whether the panels fade in at boot. Off under `--selftest`, because the suite reads
## panel geometry and alpha and an entrance animating underneath those reads is a race
## dressed up as a flaky check. It is a field rather than a check inside the function so
## the entrance can be exercised on purpose from there.
var intro_enabled: bool = true
var _syncing_sliders: bool = false
var _reset_armed_until: int = 0
var _stats_expanded: bool = false

var _modal: Control
var _modal_panel: PanelContainer
var _modal_dim: ColorRect
var _modal_band: TextureRect
var _modal_summary: Label
## Kept so the open/close fade is a single tween rather than a new one per toggle.
var _modal_tween: Tween
var _aura_blurb: Label
var _tasks_modal: Control
var _tasks_panel: PanelContainer
var _tasks_dim: ColorRect
var _tasks_tween: Tween
var _tasks_body: VBoxContainer
var _tasks_headline: Label
var _tasks_bar: ProgressBar
var _tasks_detail: Label
var _tasks_claim: Button
var _scale_readout: Label
var _map_panel: PanelContainer
var _map_view: Control
var _map_toggle: Button
var _map_legend: VBoxContainer
var _map_expanded: bool = true
## Bars mid-flight, and where each one is heading. Kept apart from the bars themselves
## so `_set_bar` can be called as often as the refresh runs without restarting an
## animation: the target moves, the displayed value chases it.
var _bar_target: Dictionary = {}
var _bar_easing: Dictionary = {}


func _ready() -> void:
	add_to_group("hud")
	# The world stops while a panel is open (see `_sync_pause`), and this layer has to
	# keep going while it does: the panel is drawn from here, the pointer is freed from
	# here, and — the part that is easy to miss — the tweens that fade a panel in are
	# bound to this node by default, so a paused HUD freezes its own menu half-faded and
	# invisible. That is not hypothetical: it is what the opacity check caught the first
	# time the pause was added.
	process_mode = Node.PROCESS_MODE_ALWAYS
	intro_enabled = not OS.get_cmdline_user_args().has("--selftest")
	_dress_panels()
	_build_stat_rows()
	_build_drill_rows()
	# Before the panel-scaling pass at the bottom of this method, which walks the root's
	# children: a panel built after it would never be scaled or pinned.
	_build_minimap()
	_build_settings_modal()
	_build_tasks_modal()
	# Deferred, and again on every resize: each panel is scaled about its own anchored
	# corner, which needs its laid-out size. At _ready the layout has not run yet.
	_settings_button.icon = _gear_texture()
	_settings_button.pressed.connect(_toggle_settings)
	_stats_toggle.pressed.connect(_toggle_stats)
	# Folded by default: it is the tallest panel on screen and the least urgent one.
	set_stats_expanded(false)
	_connect_signals()
	# The four edge panels are re-pinned whenever one of them resizes, which is the
	# point at which its real height is finally known. Deferred once at startup for the
	# first layout.
	for node in _root.get_children():
		var panel := node as Control
		if panel == null or panel == _modal or panel == _tasks_modal:
			continue
		panel.resized.connect(_apply_ui_scale)
	_apply_ui_scale.call_deferred()
	_play_intro.call_deferred()

	# The two meters in the scene are dressed here rather than in the scene file, so the
	# fill and the track are built by the same helpers as every other bar in the HUD —
	# which is what stops these two drifting away from the rest on the next pass over
	# the palette.
	var meter_height: int = int(_refinement_bar.custom_minimum_size.y) if \
		_refinement_bar.custom_minimum_size.y > 0.0 else 10
	_refinement_bar.add_theme_stylebox_override("fill", _bar_fill(Color("9fd4ff"), meter_height))
	_insight_bar.add_theme_stylebox_override("fill", _bar_fill(Color("ffd76e"), meter_height))
	for bar: ProgressBar in [_refinement_bar, _insight_bar]:
		bar.add_theme_stylebox_override("background", _bar_track(meter_height))
		bar.show_percentage = false
		# Forced here as well as in the scene. Every meter in this HUD is fed a 0..1
		# ratio, and a ProgressBar left at its default 0..100 range draws a bar at 90%
		# as one at 0.9% — with the correct number printed beside it, which is what
		# makes it read as a broken display rather than a full one.
		bar.max_value = 1.0
		bar.step = 0.001

	_refresh()


## The panels arrive rather than simply being there.
##
## Each fades up from nothing, staged outwards from the middle of the screen, so the
## interface assembles in the order the eye would look at it and the character in the
## middle is uncovered first.
##
## Alpha only, deliberately. The obvious extra — a few pixels of rise — means writing
## `position.y` on panels whose position is computed from their anchors, which is writing
## to a property another part of this file owns: a resize during the animation re-lays the
## panel out, and the tween then finishes by writing a height captured before that. A
## fade cannot end 10 px off. The tween also writes exactly 1.0 rather than wherever the
## easing ran out, so a panel is never left at 0.99.
##
## Skipped under `--selftest`: the suite reads panel geometry and alpha, and an entrance
## animating underneath those reads would be a race dressed up as a flaky check.
func _play_intro() -> void:
	if not intro_enabled:
		return
	var centre: Vector2 = _root.size * 0.5
	var panels: Array[Control] = []
	for node in _root.get_children():
		var panel := node as Control
		if panel == null or panel == _modal or panel == _tasks_modal:
			continue
		panels.append(panel)
	# Furthest from the middle of the screen first: the outermost furniture lands last, so
	# the first thing that appears is what is closest to the character.
	panels.sort_custom(func(a: Control, b: Control) -> bool:
		return a.position.distance_to(centre) < b.position.distance_to(centre))
	for i in panels.size():
		var panel: Control = panels[i]
		panel.modulate.a = 0.0
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(panel, "modulate:a", 1.0, 0.36).set_delay(float(i) * 0.06)
		tween.tween_callback(func() -> void: panel.modulate.a = 1.0)


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh()
	_ease_bars(delta)


## Asks a bar to show a value.
##
## The bar *eases* toward it rather than snapping, so a blow that takes a fifth of your
## health reads as a loss rather than as a new number — a bar that jumps gives the eye
## nothing to follow, and the faster the game the less visible the change is. A bar seen
## for the first time is set outright: there is no movement to show yet, and easing in
## from zero would make the whole interface climb on the first second of play.
func _set_bar(bar: ProgressBar, target: float) -> void:
	if bar == null:
		return
	var want: float = clampf(target, 0.0, bar.max_value)
	if not _bar_target.has(bar):
		bar.value = want
		_bar_target[bar] = want
		return
	_bar_target[bar] = want
	if not is_equal_approx(bar.value, want):
		_bar_easing[bar] = true


## Fraction of a full bar crossed per second. Fast enough that a hit is felt as it
## lands, slow enough that the eye can follow it — a quarter of a second from empty to
## full, which is about the limit of what reads as motion rather than as a jump.
const BAR_EASE_SPEED := 3.0


func _ease_bars(delta: float) -> void:
	if _bar_easing.is_empty():
		return
	# `.keys()` copies, so a bar that finishes this frame can be dropped from the set
	# while it is being walked.
	for bar: ProgressBar in _bar_easing.keys():
		var want: float = float(_bar_target.get(bar, bar.value))
		bar.value = move_toward(bar.value, want, maxf(0.02, bar.max_value * BAR_EASE_SPEED * delta))
		if is_equal_approx(bar.value, want):
			bar.value = want
			_bar_easing.erase(bar)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("settings"):
		_toggle_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_stats"):
		_toggle_stats()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and tasks_open():
		close_tasks()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and settings_open():
		close_settings()
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------- styling

## One 9-patch texture for every panel. The art's centre is opaque, so the border
## and the backing are the same draw call, and darkening it with a modulate turns
## one fantasy frame into a readable dark panel.
func _panel_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	var texture: Texture2D = load(PANEL_TEXTURE)
	style.texture = texture
	style.set_texture_margin_all(float(PANEL_BORDER))
	style.set_content_margin_all(float(PANEL_BORDER + PANEL_PADDING))
	style.modulate_color = Color(0.09, 0.11, 0.15, 0.94)
	return style


func _dress_panels() -> void:
	for panel: PanelContainer in [
		_cultivation_panel, _stats_panel, _action_panel, _log_panel,
	]:
		panel.add_theme_stylebox_override("panel", _panel_style())
	# The two slim strips wear a flat plate instead of the 9-patch frame. That frame
	# costs 23 px of border plus 6 px of padding on *every* side — 58 px of a panel's
	# height spent on being a frame, which is most of what a one-line task tracker is.
	# On the tracker it was the difference between a 124 px box and a 44 px strip, and
	# 80 px is exactly what it needed to stop sinking into the event log below it.
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(0.05, 0.06, 0.08, 0.66)
	strip.border_color = Color(0.36, 0.47, 0.58, 0.3)
	strip.set_border_width_all(1)
	strip.set_corner_radius_all(4)
	strip.set_content_margin_all(8)
	_help_panel.add_theme_stylebox_override("panel", strip)
	var tracker_strip := strip.duplicate() as StyleBoxFlat
	# A touch more vertical room than the hint strip: this one carries a bar.
	tracker_strip.content_margin_top = 5
	tracker_strip.content_margin_bottom = 5
	_quest_panel.add_theme_stylebox_override("panel", tracker_strip)
	# Only the action panel catches the mouse, so everything else is made
	# click-through and can never steal a mouse-look motion event.
	for panel: PanelContainer in [_cultivation_panel, _stats_panel, _log_panel, _help_panel]:
		_ignore_mouse(panel)
	# The fold control is the one thing in the stat panel that has to take a click,
	# and `_ignore_mouse` has just made it click-through along with its parent.
	_stats_toggle.mouse_filter = Control.MOUSE_FILTER_STOP


## A translucent panel: a thin frame, a soft dark wash, and the world still visible
## through it. Used by the map, where seeing the ground behind the panel is the point.
func _glass_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.52)
	style.border_color = Color(0.45, 0.58, 0.70, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(9)
	return style


## One row of the map legend: a colour chip and what it means, on one line.
##
## No wrapping and no second column of explanation. A wrapped label inside a row inside a
## panel 180 px wide does not get shorter when it runs out of room — it narrows to nothing
## and stacks one word per line, which is how the first version of this legend became
## 1,994 px tall and pushed the panel off the top of the screen. Trimming with an ellipsis
## is the honest failure: the row stays one row.
func _make_legend_row(tint: Color, text: String, dimmed: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(9, 9)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.color = Color(tint, 0.5 if dimmed else 1.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)
	var label := _make_label(text, 10, Color("c7cfd8", 0.55 if dimmed else 1.0))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	return row


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## A bar's fill: the tint, with a lit top edge and a slightly deepened body.
##
## A `StyleBoxFlat` carries one colour and has no gradient, so this is a bevel instead.
## On a bar six pixels tall the two are indistinguishable, and the bevel rounds
## properly — a `GradientTexture2D` inside a `StyleBoxTexture` cannot, because a 9-patch
## gradient splits into three fixed bands and stretching the whole texture turns a 3 px
## corner into a 14 px blob at panel width. That is the entire reason this is a bevel.
func _bar_fill(color: Color, height: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.14)
	style.set_corner_radius_all(maxi(2, height / 2))
	# A two-pixel bar is all border; leave the thin ones flat so they stay crisp.
	if height >= 4:
		style.border_color = color.lightened(0.45)
		style.border_width_top = 1
	return style


## The empty part of a bar: dark, rounded, with the faintest inner edge so an empty bar
## still reads as a track rather than as a gap in the panel.
func _bar_track(height: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.06, 0.75)
	style.set_corner_radius_all(maxi(2, height / 2))
	style.border_color = Color(1.0, 1.0, 1.0, 0.08)
	style.set_border_width_all(1)
	return style


func _make_bar(color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _bar_track(height))
	bar.add_theme_stylebox_override("fill", _bar_fill(color, height))
	return bar


## A horizontal gradient from the tint to nothing, for the rule under a heading.
##
## This is where a real gradient belongs rather than on a bar: a two-pixel strip has no
## corners to round, nothing to stretch, and a rule that fades out is what makes a set
## of controls read as a group instead of as a list.
func _make_rule(tint: Color, height: int = 2) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.9))
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 0.0)
	texture.width = 64
	texture.height = height
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(0, height)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A section heading with a gradient rule under it. Every group of controls in the
## settings panel gets one, so the panel reads as sections rather than as a column.
func _make_heading(text: String, tint: Color) -> VBoxContainer:
	var holder := VBoxContainer.new()
	holder.name = "Heading_" + text.replace(" ", "")
	holder.add_theme_constant_override("separation", 1)
	holder.add_child(_make_label(text, 14, tint))
	holder.add_child(_make_rule(tint))
	return holder


## A vertical gradient band, for the strip across the top of a panel. Dark at the top
## edge and fading out, which is what gives a flat panel a lit top.
func _make_band(tint: Color, height: int) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint.r, tint.g, tint.b, 0.30))
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 8
	texture.height = 64
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(0, height)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Drawn rather than typed. No font in the project is guaranteed to carry a gear
## glyph, and a missing glyph renders as a tofu box; eight teeth around a hub is a
## dozen lines and cannot go missing.
func _gear_texture(size: int = 32) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var centre := Vector2(float(size), float(size)) * 0.5
	var scale: float = float(size) / 32.0
	var teeth: int = 8
	for y in size:
		for x in size:
			var offset := Vector2(float(x) + 0.5, float(y) + 0.5) - centre
			var radius: float = offset.length()
			var angle: float = atan2(offset.y, offset.x)
			# A squared-off cosine gives teeth rather than a flower.
			var rim: float = (11.0 + 2.4 * clampf(cos(angle * float(teeth)) * 2.2, -1.0, 1.0)) * scale
			if radius <= rim and radius >= 3.7 * scale:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


# -------------------------------------------------------------------- building

func _build_stat_rows() -> void:
	for stat_id: String in PlayerData.STAT_ORDER:
		var defn: Dictionary = PlayerData.def(stat_id)
		# No gap between a stat's name and its bars: the bars belong to the label above
		# them, and seven rows of a pixel each is seven pixels of the tallest panel in the
		# HUD, which is the panel that decides whether the left column clears the log.
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)

		var heading := HBoxContainer.new()
		var name_label := _make_label(PlayerData.label(stat_id), 12, PlayerData.color(stat_id))
		name_label.custom_minimum_size = Vector2(84, 0)
		name_label.tooltip_text = "%s\nGrows by: %s" % [
			PlayerData.label(stat_id), String(defn.get("earned_by", ""))
		]
		var value_label := _make_label("", 12, Color("e6edf5"))
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(name_label)
		heading.add_child(value_label)

		var fill_bar := _make_bar(PlayerData.color(stat_id), 5)
		var xp_bar := _make_bar(PlayerData.color(stat_id).darkened(0.45), 2)

		column.add_child(heading)
		column.add_child(fill_bar)
		column.add_child(xp_bar)
		_stat_rows.add_child(column)

		_value_labels[stat_id] = value_label
		_fill_bars[stat_id] = fill_bar
		_xp_bars[stat_id] = xp_bar


## One row per drill, straight from the training catalogue, so a new exercise
## appears here without this file knowing anything about it.
func _build_drill_rows() -> void:
	for entry: Dictionary in Training.EXERCISES:
		var id: String = String(entry["id"])
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override("separation", 2)

		var heading := HBoxContainer.new()
		var name_label := _make_label(
			"%s · %s" % [entry["key"], entry["label"]], 13, Color("ffd76e")
		)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The cost is a share of the health cap, so it is shown as one: "1.8% of your
		# health per rep" is the same number at any size, where "1.3 HP" stops being
		# true the moment the cap grows.
		name_label.tooltip_text = "%s\nHold the key to drill. Costs %.1f%% of your health per rep." % [
			entry["blurb"], float(entry["hp_cost"]) * 100.0,
		]
		var readout := _make_label("", 12, Color("b9c2cc"))
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		heading.add_child(name_label)
		heading.add_child(readout)

		var rep_bar := _make_bar(Color("ffd76e"), 4)

		holder.add_child(heading)
		holder.add_child(rep_bar)
		_drill_rows.add_child(holder)
		_drill_readouts[id] = readout
		_drill_bars[id] = rep_bar


## The settings modal. Built here rather than in the scene file because it is the
## one part of the interface that is entirely a list of generated controls: the
## two clamps and one button per aura.
func _build_settings_modal() -> void:
	_modal = Control.new()
	_modal.name = "SettingsModal"
	_modal.visible = false
	_modal.anchor_right = 1.0
	_modal.anchor_bottom = 1.0
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_modal)

	_modal_dim = ColorRect.new()
	_modal_dim.name = "Dim"
	_modal_dim.color = Color(0.0, 0.0, 0.0, MODAL_DIM)
	_modal_dim.anchor_right = 1.0
	_modal_dim.anchor_bottom = 1.0
	_modal_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.add_child(_modal_dim)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.anchor_right = 1.0
	centre.anchor_bottom = 1.0
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(centre)

	_modal_panel = PanelContainer.new()
	_modal_panel.name = "SettingsPanel"
	_modal_panel.custom_minimum_size = Vector2(560, 0)
	_modal_panel.add_theme_stylebox_override("panel", _panel_style())
	centre.add_child(_modal_panel)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 10)
	_modal_panel.add_child(body)

	body.add_child(_make_band(Color("ffd76e"), 12))
	body.add_child(_make_label("SETTINGS", 20, Color("ffd76e")))
	body.add_child(_make_rule(Color("ffd76e")))
	# Where you actually are, in the panel you open to change things. Without it, every
	# decision in here — which cap to raise, which aura to equip — is made without the
	# stage and the purse that decide whether it is even available.
	_modal_summary = _make_label("", 12, Color("b9c2cc"))
	_modal_summary.name = "SettingsSummary"
	_modal_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_modal_summary)
	body.add_child(_make_heading("TRAINING CAPS", Color("7dff9b")))
	body.add_child(_make_label(
		"Sliders cap at what you have earned. Train to raise the cap.", 11, Color("b9c2cc")
	))

	for stat_id: String in TRAINABLE_ROWS:
		body.add_child(_build_slider_row(stat_id))

	# Interface size lives here rather than being a constant because it is the one
	# visual setting that depends on the screen it is being read on, and fullscreen on
	# a large monitor is where the default reads as oversized.
	body.add_child(_make_heading("INTERFACE SIZE", Color("9ad8ff")))
	var size_row := HBoxContainer.new()
	size_row.name = "UiScaleRow"
	size_row.add_theme_constant_override("separation", 8)
	var smaller := Button.new()
	smaller.name = "UiScaleDown"
	smaller.text = "Smaller"
	smaller.focus_mode = Control.FOCUS_NONE
	smaller.pressed.connect(_on_ui_scale_pressed.bind(-0.05))
	size_row.add_child(smaller)
	_scale_readout = _make_label("%d%%" % int(round(PlayerData.ui_scale * 100.0)), 13,
		Color("f2f6fb"))
	_scale_readout.name = "UiScaleReadout"
	_scale_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scale_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(_scale_readout)
	var bigger := Button.new()
	bigger.name = "UiScaleUp"
	bigger.text = "Bigger"
	bigger.focus_mode = Control.FOCUS_NONE
	bigger.pressed.connect(_on_ui_scale_pressed.bind(0.05))
	size_row.add_child(bigger)
	body.add_child(size_row)

	body.add_child(_make_heading("AURA", Color("9ad8ff")))
	var grid := GridContainer.new()
	grid.name = "AuraGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)

	var group := ButtonGroup.new()
	for entry: Dictionary in Cultivation.AURAS:
		var id: String = String(entry["id"])
		var unlocked: bool = Cultivation.tier >= int(entry["unlock_tier"])
		var button := Button.new()
		button.name = "Aura_" + id
		button.text = String(entry["label"])
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = not unlocked
		button.tooltip_text = (
			String(entry["blurb"]) if unlocked
			else "Locked — reach stage %d (%s)" % [
				int(entry["unlock_tier"]) + 1, _realm_for_tier(int(entry["unlock_tier"]))
			]
		)
		button.pressed.connect(_on_aura_pressed.bind(id))
		grid.add_child(button)
		_aura_buttons[id] = button

	_aura_blurb = _make_label("", 11, Color("b9c2cc"))
	_aura_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aura_blurb.custom_minimum_size = Vector2(0, 46)
	body.add_child(_aura_blurb)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(_on_save_pressed)
	var reset_button := Button.new()
	reset_button.text = "Reset progress"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_on_reset_pressed)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close_settings)
	footer.add_child(save_button)
	footer.add_child(reset_button)
	footer.add_child(close_button)
	body.add_child(footer)


func _build_slider_row(stat_id: String) -> Control:
	var holder := VBoxContainer.new()
	holder.name = stat_id.capitalize() + "Row"
	holder.add_theme_constant_override("separation", 2)

	var heading := HBoxContainer.new()
	var name_label := _make_label("SET " + PlayerData.label(stat_id), 13, PlayerData.color(stat_id))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout := _make_label("", 13, Color("e6edf5"))
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(name_label)
	heading.add_child(readout)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	var slider := HSlider.new()
	slider.name = stat_id.capitalize() + "Slider"
	slider.min_value = 0.0
	slider.max_value = PlayerData.get_cap(stat_id)
	slider.step = 0.01
	slider.value = PlayerData.get_allocated(stat_id)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.mouse_filter = Control.MOUSE_FILTER_STOP
	slider.value_changed.connect(_on_slider_changed.bind(stat_id))
	var cap_button := Button.new()
	cap_button.text = "MAX"
	cap_button.focus_mode = Control.FOCUS_NONE
	cap_button.mouse_filter = Control.MOUSE_FILTER_STOP
	cap_button.pressed.connect(_on_cap_button_pressed.bind(stat_id))
	controls.add_child(slider)
	controls.add_child(cap_button)

	holder.add_child(heading)
	holder.add_child(controls)
	_sliders[stat_id] = slider
	_slider_readouts[stat_id] = readout
	return holder


## Which realm a tier falls in, for the "locked until" tooltip. Read from the
## catalogue rather than duplicated, so the promise always matches the gate.
func _realm_for_tier(tier: int) -> String:
	var index: int = mini(tier / Cultivation.STAGES_PER_REALM, Cultivation.REALMS.size() - 1)
	return String(Cultivation.REALMS[index])


func _connect_signals() -> void:
	# Any of these means the next frame's refresh should not wait for the timer,
	# and the accumulator trick coalesces a whole frame's worth into one redraw.
	PlayerData.stats_changed.connect(_queue_refresh)
	PlayerData.allocation_changed.connect(_on_allocation_changed)
	PlayerData.stat_cap_gained.connect(_on_cap_gained)
	PlayerData.log_message.connect(_append_log)
	PlayerData.aura_changed.connect(_on_aura_changed)
	PlayerData.crystals_changed.connect(_on_crystals_changed)
	Quests.task_started.connect(_on_task_changed)
	Quests.task_completed.connect(_on_task_changed)
	Quests.task_claimed.connect(_on_task_changed)
	Quests.task_progress.connect(_on_task_progress)
	Cultivation.cultivation_changed.connect(_queue_refresh)
	Cultivation.breakthrough_performed.connect(_on_breakthrough)
	Training.rep_completed.connect(_on_rep_completed)
	Training.log_message.connect(_append_log)


func _queue_refresh() -> void:
	_refresh_accum = REFRESH_INTERVAL


# --------------------------------------------------------------------- the map

## The map panel: a header with a fold control, the map, and a legend.
##
## Anchored bottom-right, which is the one corner of the screen that was empty — the
## log and the help strip own the bottom-left and the bottom-centre, and putting the
## map over either would cost more than it gave. Built in code because the body of it
## is a single custom Control, which a scene file cannot express.
func _build_minimap() -> void:
	_map_panel = PanelContainer.new()
	_map_panel.name = "MapPanel"
	# Translucent, unlike every other panel. The frame costs 23 px of border plus padding and
	# its background is opaque, which over the corner of the world hides the ground the map
	# is a picture of. A map is an overlay on the landscape, not a window in a wall.
	_map_panel.add_theme_stylebox_override("panel", _glass_style())
	_map_panel.anchor_left = 1.0
	_map_panel.anchor_right = 1.0
	_map_panel.anchor_top = 1.0
	_map_panel.anchor_bottom = 1.0
	_map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_map_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_map_panel.offset_left = -200.0
	_map_panel.offset_top = -360.0
	_map_panel.offset_right = -14.0
	_map_panel.offset_bottom = -14.0
	_root.add_child(_map_panel)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 6)
	_map_panel.add_child(body)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 6)
	body.add_child(header)
	var title := _make_label("MAP", 13, Color("ffd76e"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_map_toggle = Button.new()
	_map_toggle.name = "MapToggle"
	_map_toggle.text = "Hide"
	# Every button in this HUD that a player can click sets this, and the two that did
	# not were the two that showed the bug: a focused Button is activated by Space, and
	# Space is the jump key, so jumping folded the panel open and shut.
	_map_toggle.focus_mode = Control.FOCUS_NONE
	_map_toggle.pressed.connect(_on_map_toggle)
	header.add_child(_map_toggle)

	_map_view = Control.new()
	_map_view.name = "MapView"
	_map_view.set_script(load("res://scripts/ui/minimap.gd"))
	body.add_child(_map_view)

	# The legend is a column of coloured chips rather than a sentence. It used to be one
	# wrapped line of "gold you · cyan wards · red raiders …", which asks the player to hold
	# three colour names in their head at once and match each to a dot by memory. A chip is
	# the colour; the words beside it are only the label.
	_map_legend = VBoxContainer.new()
	_map_legend.name = "MapLegend"
	_map_legend.add_theme_constant_override("separation", 2)
	body.add_child(_map_legend)

	_ignore_mouse(_map_panel)
	# ...except the fold control, for the same reason the stat fold control is exempt.
	_map_toggle.mouse_filter = Control.MOUSE_FILTER_STOP
	set_map_expanded(true)


func _on_map_toggle() -> void:
	Audio.play("ui_toggle")
	set_map_expanded(not _map_expanded)


func set_map_expanded(expanded: bool) -> void:
	_map_expanded = expanded
	if _map_view != null:
		_map_view.visible = expanded
	if _map_legend != null:
		_map_legend.visible = expanded
	if _map_toggle != null:
		_map_toggle.text = "Hide" if expanded else "Show"
		_map_toggle.tooltip_text = ("Fold the map away" if expanded else "Show the map")
	_refresh_map_legend()


func map_expanded() -> bool:
	return _map_expanded


func map_view() -> Control:
	return _map_view


## Says what the marks mean, including which spirit zones the player cannot use yet.
## A legend that only labels the colours would leave the interesting part — that two of
## the four pillars on the map are out of reach — as an unlabelled circle.
func _refresh_map_legend() -> void:
	if _map_legend == null or not _map_expanded:
		return
	for child in _map_legend.get_children():
		child.queue_free()
	# The marks, then the places. Both lists are built by the map itself, complete with the
	# colour each one is drawn in, so a chip cannot end up explaining a dot it does not match.
	if _map_view != null and _map_view.has_method("legend"):
		for entry: Dictionary in _map_view.call("legend"):
			# The one note short enough to earn its place on the line. The rest of them are
			# said better by the help strip than by four more words in a corner.
			var note: String = String(entry.get("note", ""))
			_map_legend.add_child(_make_legend_row(
				entry["color"], String(entry["text"])
					+ (" · " + note if note.begins_with("a reward") else ""),
				false
			))
	if _map_view != null and _map_view.has_method("zone_legend"):
		for entry: Dictionary in _map_view.call("zone_legend"):
			var locked: bool = bool(entry["locked"])
			_map_legend.add_child(_make_legend_row(
				entry["color"], "%s · %s" % [String(entry["text"]), String(entry["note"])],
				locked
			))


## Every word in the map's legend, joined, for the self-test. The panel is a column of
## chips and labels rather than one string, so this is how the legend's *content* is read
## without a check having to know how it is laid out.
func map_legend_text() -> String:
	if _map_legend == null:
		return ""
	var parts: Array = []
	for row in _map_legend.get_children():
		parts.append(_collect_text(row))
	return "  ".join(parts)


func _collect_text(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out = (node as Label).text
	for child in node.get_children():
		var piece: String = _collect_text(child)
		if piece != "":
			out += (" " if out != "" else "") + piece
	return out


# ---------------------------------------------------------------- the settings

func settings_open() -> bool:
	return _modal != null and _modal.visible


## Opens the settings panel, fading it in.
##
## The panel used to be set to fully transparent here and nothing ever faded it back
## up, so opening the settings showed the dimming layer and an empty middle: the
## controls were all there, correctly laid out, and invisible. A fade is what the
## transparent start was reaching for, so it is now an actual one — and the tween is
## kept so a second toggle cannot leave two of them fighting over the same property.
func open_settings() -> void:
	if _modal == null or _modal.visible:
		return
	# Only one panel at a time. Two modals stacked is a state with no good way out:
	# the pointer is shared, Escape would close the wrong one, and closing the top one
	# would leave you looking at a panel you did not open.
	close_tasks()
	_modal.visible = true
	if _modal_tween != null and _modal_tween.is_valid():
		_modal_tween.kill()
	_modal_panel.modulate = Color(1, 1, 1, 0)
	_modal_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_modal_tween.tween_property(_modal_panel, "modulate:a", 1.0, 0.12)
	_modal_tween.parallel().tween_property(_modal_dim, "color:a", MODAL_DIM, 0.14)
	# Sliding the mouse free is what makes the modal usable at all: the camera
	# captures the pointer while you are playing.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play("ui_open")
	_sync_pause()
	_refresh()


func close_settings() -> void:
	if _modal == null or not _modal.visible:
		return
	_modal.visible = false
	if _modal_tween != null and _modal_tween.is_valid():
		_modal_tween.kill()
	# Left fully visible, so a close during the fade cannot leave the next open
	# starting from a half-faded alpha.
	_modal_panel.modulate = Color(1, 1, 1, 1)
	if _modal_dim != null:
		_modal_dim.color.a = MODAL_DIM
	if not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play("ui_close")
	_sync_pause()
	_refresh()


## How dark the layer behind a panel is.
const MODAL_DIM := 0.62


## Stops the world while a panel is open, and starts it again when the last one closes.
##
## This is the difference between a menu and a screenshot. Without it, reading the
## settings means standing in the open with your guard down: raiders keep closing, blows
## keep landing, a drill keeps draining blood and the keyboard keeps walking you around
## — all while your attention is on a slider. Every one of those is a fair fight the
## player loses by doing nothing wrong.
##
## The HUD itself is set to `PROCESS_MODE_ALWAYS`, so the panel keeps drawing, the
## pointer stays free and the open/close tweens keep running while the world is stopped.
func _sync_pause() -> void:
	var wanted: bool = settings_open() or tasks_open()
	if get_tree() != null:
		get_tree().paused = wanted
	if wanted:
		_append_log("Time holds while the panel is open.", "info")


func _toggle_settings() -> void:
	if settings_open():
		close_settings()
	else:
		open_settings()


## Pauses or resumes the world when a panel opens or closes, and reports it. Public so
## the quest NPC's panel goes through exactly the same path as the settings panel — two
## ways to open a panel must not mean two sets of rules about the world stopping.
func sync_world_pause() -> void:
	_sync_pause()


func _on_aura_pressed(element: String) -> void:
	if not Cultivation.aura_unlocked(element):
		Audio.play("error")
		return
	Audio.play("ui_toggle")
	PlayerData.set_chosen_aura(element)
	_append_log("Aura attuned: %s." % String(Cultivation.aura_def(element).get("label", element)),
		"cultivate")


func _on_aura_changed(_element: String) -> void:
	Audio.play("pluck", -4.0, randf_range(0.95, 1.1))
	_refresh()


func _on_rep_completed(_id: String, reps: int) -> void:
	# Every tenth rep is worth hearing separately from the thud of the drill.
	if reps % 10 == 0:
		Audio.play("confirm", -6.0, randf_range(0.95, 1.05))


# ------------------------------------------------------------------- refreshing

func _refresh() -> void:
	_refresh_accum = 0.0
	_refresh_map_legend()

	# The line under the settings heading, filled from the same getters the plate over your
	# head uses so the panel cannot report a stage or a score you do not have.
	if _modal_summary != null:
		_modal_summary.text = "Stage %d · %s · %d crystals · power %s" % [
			Cultivation.stage(), Cultivation.realm_name(), PlayerData.crystals,
			PlayerData.power_text(),
		]

	_realm_label.text = "%s · %s" % [Cultivation.realm_name(), Cultivation.realm_label()]
	_realm_label.add_theme_color_override("font_color", Color("ffd76e"))
	_coeff_label.text = "Stat gain ×%.2f" % PlayerData.gain_coefficient
	_coeff_label.add_theme_color_override("font_color", Color("7dff9b").lerp(
		Color("ffd76e"), clampf((PlayerData.gain_coefficient - 1.0) / 3.0, 0.0, 1.0)
	))

	_refinement_label.text = "REFINEMENT %d   ·   next in %.0fs" % [
		Cultivation.refinement, Cultivation.cycle_required() - Cultivation.cycle,
	]
	_set_bar(_refinement_bar, Cultivation.cycle_ratio())

	_crystals_label.text = "Crystals %d" % PlayerData.crystals
	_refresh_tracker()

	if Cultivation.can_break_through():
		_insight_label.text = "INSIGHT FULL — press B to break through"
		_insight_label.add_theme_color_override("font_color", Color("ffd76e"))
	else:
		var blocker: String = Cultivation.breakthrough_blocker()
		_insight_label.text = "INSIGHT %d%%" % int(round(Cultivation.insight_ratio() * 100.0))
		if blocker != "":
			_insight_label.text += "  ·  %s" % blocker
		_insight_label.add_theme_color_override("font_color", Color("b9c2cc"))
	_set_bar(_insight_bar, Cultivation.insight_ratio())

	for stat_id: String in PlayerData.STAT_ORDER:
		var cap: float = PlayerData.get_cap(stat_id)
		var is_passive: bool = PlayerData.kind(stat_id) == PlayerData.KIND_PASSIVE
		(_value_labels[stat_id] as Label).text = _stat_readout(stat_id)
		# For a passive stat the cap *is* the value, so a "how full" bar would
		# always read 100%. Show how far the next rank is instead.
		var fill: float = clampf(PlayerData.get_value(stat_id) / maxf(0.001, cap), 0.0, 1.0)
		if is_passive:
			fill = PlayerData.progress_ratio(stat_id)
		_set_bar(_fill_bars[stat_id] as ProgressBar, fill)
		(_xp_bars[stat_id] as ProgressBar).visible = not is_passive
		_set_bar(_xp_bars[stat_id] as ProgressBar, PlayerData.progress_ratio(stat_id))

	_refresh_drills()
	_refresh_auras()
	_sync_sliders()
	_refresh_stats_header()
	_update_status()


func _toggle_stats() -> void:
	set_stats_expanded(not _stats_expanded)


func set_stats_expanded(expanded: bool) -> void:
	_stats_expanded = expanded
	_stat_rows.visible = expanded
	_stats_toggle.text = "Hide" if expanded else "Show"
	_stats_toggle.tooltip_text = (
		"Fold the stat readout away (V)" if expanded else "Show every stat (V)"
	)
	_refresh_stats_header()


func stats_expanded() -> bool:
	return _stats_expanded


## A folded header still has to say something, or the space it saves is spent on
## nothing. Vitality and qi are the two numbers worth glancing at mid-run, and both
## are already drawn elsewhere — this is the reminder, not the readout.
func _refresh_stats_header() -> void:
	if _stats_expanded:
		_stats_title.text = "BODY"
		return
	_stats_title.text = "BODY  ·  HP %s  QI %s" % [
		String.num(PlayerData.get_value("hp"), 0),
		String.num(PlayerData.get_value("qi"), 0),
	]


func _stat_readout(stat_id: String) -> String:
	var text: String = PlayerData.readout(stat_id)
	if stat_id == "defense":
		text += "  (−%.1f%% dmg)" % ((1.0 - PlayerData.damage_multiplier()) * 100.0)
	elif stat_id == "attack":
		text += "  (%.1f a blow)" % PlayerData.strike_damage()
	return text


func _refresh_drills() -> void:
	for entry: Dictionary in Training.EXERCISES:
		var id: String = String(entry["id"])
		var active: bool = Training.active == id
		var readout: Label = _drill_readouts[id]
		var bar: ProgressBar = _drill_bars[id]
		var other_running: bool = Training.is_training() and not active
		if active:
			readout.text = "%d reps" % Training.reps
		elif other_running:
			readout.text = "—"
		else:
			# The drill keys are toggles, so the row says what the key will *do* rather
			# than telling the player to hold it down.
			readout.text = "tap %s to start" % entry["key"]
		_set_bar(bar, Training.rep_ratio() if active else 0.0)
		bar.modulate = Color(1, 1, 1, 1.0 if active else 0.35)
		readout.modulate = Color(1, 1, 1, 1.0 if not other_running else 0.45)


func _refresh_auras() -> void:
	var active: String = Cultivation.active_aura()
	var defn: Dictionary = Cultivation.aura_def(active)
	_aura_label.text = "Aura: %s · power %.0f%%" % [
		String(defn.get("label", "—")), Cultivation.aura_power() * 100.0
	]
	for id: String in _aura_buttons:
		var button: Button = _aura_buttons[id]
		var unlocked: bool = Cultivation.aura_unlocked(id)
		button.disabled = not unlocked
		button.button_pressed = unlocked and id == active
	if _aura_blurb != null:
		_aura_blurb.text = String(defn.get("blurb", ""))


func _sync_sliders() -> void:
	_syncing_sliders = true
	for stat_id: String in TRAINABLE_ROWS:
		var slider: HSlider = _sliders[stat_id]
		var cap: float = PlayerData.get_cap(stat_id)
		slider.max_value = cap
		var allocated: float = PlayerData.get_allocated(stat_id)
		if not is_equal_approx(slider.value, allocated):
			slider.value = allocated
		(_slider_readouts[stat_id] as Label).text = "%s / %s" % [
			PlayerData.format_value(stat_id, allocated),
			PlayerData.format_value(stat_id, cap),
		]
	_syncing_sliders = false


# ----------------------------------------------------------------- interface size

## Applies the player's interface scale.
##
## Each panel is scaled about *its own* anchored corner rather than the whole layer
## being scaled from the top-left. A right-hand panel scaled about the top-left walks
## off the edge it is anchored to, and a bottom one climbs into the middle of the
## screen; scaling about the pivot each panel is pinned by keeps every panel where it
## belongs and only changes how much room it takes.
func _apply_ui_scale() -> void:
	var scale_factor: float = clampf(
		PlayerData.ui_scale, PlayerData.UI_SCALE_MIN, PlayerData.UI_SCALE_MAX
	)
	var waiting: bool = false
	for node in _root.get_children():
		var panel := node as Control
		if panel == null or panel == _modal or panel == _tasks_modal:
			continue
		# A panel that has not been laid out yet has no size to pin to. Waiting is not
		# optional: pinning a zero-size panel scales it about its top-left corner, which
		# is right for the left column and wrong for everything else.
		if panel.size.x <= 1.0 or panel.size.y <= 1.0:
			waiting = true
			continue
		pin_panel(panel, scale_factor)
	if waiting:
		_apply_ui_scale.call_deferred()
	# The settings and task panels are centred, so they scale about their own middle
	# and stay centred instead of drifting towards a corner.
	for centre_panel: PanelContainer in [_modal_panel, _tasks_panel]:
		if centre_panel == null:
			continue
		centre_panel.pivot_offset = centre_panel.size * 0.5
		centre_panel.scale = Vector2(scale_factor, scale_factor)


## Scales one panel about the corner it is anchored to, and keeps it there.
##
## The pivot is measured against the panel's own laid-out size, so the corner it is
## pinned by does not move however the panel grows. That number is only ever read when
## it is trustworthy: each panel calls back on its own `resized` signal, which fires
## once the new size is in place, rather than on the viewport's, which fires before the
## layout has caught up. Reading it a frame early is how the help strip ended up 400 px
## below the bottom of a 1280 px canvas.
func pin_panel(panel: Control, scale_factor: float) -> void:
	var centre := Vector2(
		(panel.anchor_left + panel.anchor_right) * 0.5,
		(panel.anchor_top + panel.anchor_bottom) * 0.5
	)
	panel.pivot_offset = panel.size * centre
	panel.scale = Vector2(scale_factor, scale_factor)


func _on_ui_scale_pressed(step: float) -> void:
	PlayerData.set_ui_scale(PlayerData.ui_scale + step)
	_apply_ui_scale()
	_scale_readout.text = "%d%%" % int(round(PlayerData.ui_scale * 100.0))
	Audio.play("ui_click", -6.0)


# ------------------------------------------------------------------------ tasks

## The task panel: what the elder wants, how far along it is, and the button that
## hands it in. Built in code for the same reason the settings are: it is a list of
## generated controls rather than a fixed layout.
func _build_tasks_modal() -> void:
	_tasks_modal = Control.new()
	_tasks_modal.name = "TasksModal"
	_tasks_modal.visible = false
	_tasks_modal.anchor_right = 1.0
	_tasks_modal.anchor_bottom = 1.0
	_tasks_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_tasks_modal)

	_tasks_dim = ColorRect.new()
	_tasks_dim.name = "Dim"
	_tasks_dim.color = Color(0.0, 0.0, 0.0, MODAL_DIM)
	_tasks_dim.anchor_right = 1.0
	_tasks_dim.anchor_bottom = 1.0
	_tasks_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_tasks_modal.add_child(_tasks_dim)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.anchor_right = 1.0
	centre.anchor_bottom = 1.0
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tasks_modal.add_child(centre)

	_tasks_panel = PanelContainer.new()
	_tasks_panel.name = "TasksPanel"
	_tasks_panel.custom_minimum_size = Vector2(520, 0)
	_tasks_panel.add_theme_stylebox_override("panel", _panel_style())
	centre.add_child(_tasks_panel)

	_tasks_body = VBoxContainer.new()
	_tasks_body.name = "Body"
	_tasks_body.add_theme_constant_override("separation", 10)
	_tasks_panel.add_child(_tasks_body)

	_tasks_body.add_child(_make_band(Color("ffd76e"), 10))
	_tasks_body.add_child(_make_label("ELDER SHUFEN", 20, Color("ffd76e")))
	_tasks_body.add_child(_make_rule(Color("ffd76e")))
	_tasks_headline = _make_label("", 15, Color("f2f6fb"))
	_tasks_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tasks_body.add_child(_tasks_headline)

	_tasks_bar = ProgressBar.new()
	_tasks_bar.name = "TaskProgress"
	_tasks_bar.custom_minimum_size = Vector2(0, 12)
	_tasks_bar.max_value = 1.0
	_tasks_bar.step = 0.001
	_tasks_bar.show_percentage = false
	_tasks_bar.add_theme_stylebox_override("fill", _bar_fill(Color("ffd76e"), 12))
	_tasks_bar.add_theme_stylebox_override("background", _bar_track(12))
	_tasks_body.add_child(_tasks_bar)

	_tasks_detail = _make_label("", 12, Color("b9c2cc"))
	_tasks_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tasks_body.add_child(_tasks_detail)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	_tasks_claim = Button.new()
	_tasks_claim.name = "Claim"
	_tasks_claim.text = "Hand it in"
	_tasks_claim.focus_mode = Control.FOCUS_NONE
	_tasks_claim.pressed.connect(_on_claim_pressed)
	footer.add_child(_tasks_claim)
	var close := Button.new()
	close.name = "Close"
	close.text = "Later"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_tasks)
	footer.add_child(close)
	_tasks_body.add_child(footer)


func tasks_open() -> bool:
	return _tasks_modal != null and _tasks_modal.visible


## Opens the task panel. Called by the elder when you talk to him.
func show_tasks() -> void:
	if _tasks_modal == null:
		return
	# One panel at a time, for the same reason the settings panel does it.
	close_settings()
	_refresh_tasks()
	_tasks_modal.visible = true
	if _tasks_tween != null and _tasks_tween.is_valid():
		_tasks_tween.kill()
	_tasks_panel.modulate = Color(1, 1, 1, 0)
	_tasks_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tasks_tween.tween_property(_tasks_panel, "modulate:a", 1.0, 0.12)
	_tasks_tween.parallel().tween_property(_tasks_dim, "color:a", MODAL_DIM, 0.14)
	# The pointer has to be free to press the button, which is the one place in this
	# game the mouse is for. Re-captured when the panel closes.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play("ui_select", -6.0)
	_sync_pause()


func close_tasks() -> void:
	if _tasks_modal == null or not _tasks_modal.visible:
		return
	_tasks_modal.visible = false
	if _tasks_tween != null and _tasks_tween.is_valid():
		_tasks_tween.kill()
	if _tasks_panel != null:
		_tasks_panel.modulate = Color(1, 1, 1, 1)
	if _tasks_dim != null:
		_tasks_dim.color.a = MODAL_DIM
	if not settings_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play("ui_click", -8.0)
	_sync_pause()


func _on_claim_pressed() -> void:
	var handed: Dictionary = Quests.claim()
	if handed.is_empty():
		Audio.play("ui_click", -8.0)
		_refresh_tasks()
		return
	_refresh_tasks()
	_refresh()
	close_tasks()


func _on_task_changed(_task: Dictionary) -> void:
	_refresh()
	if tasks_open():
		_refresh_tasks()


func _on_task_progress(_task: Dictionary, _amount: float) -> void:
	_refresh_accum = REFRESH_INTERVAL


## Fills the task panel from the Quests autoload. A finished-but-unclaimed task shows
## the button; an active one shows how far along it is and what it is waiting for.
func _refresh_tasks() -> void:
	if _tasks_body == null:
		return
	var ready: Dictionary = Quests.claimable()
	var task: Dictionary = ready if not ready.is_empty() else Quests.current()
	if task.is_empty():
		_tasks_headline.text = "Nothing left to teach"
		_set_bar(_tasks_bar, 1.0)
		_tasks_detail.text = "You have finished every task he knows how to set."
		_tasks_claim.disabled = true
		_tasks_claim.text = "Nothing to hand in"
		return
	_tasks_headline.text = Quests.describe(task)
	_set_bar(_tasks_bar, Quests.ratio_of(task))
	var done: bool = not ready.is_empty()
	_tasks_claim.disabled = not done
	_tasks_claim.text = "Hand it in (+%d crystals)" % int(task.get("crystals", 0)) if done \
		else "Not finished yet"
	_tasks_detail.text = (
		"%s  ·  %s" % [String(task["title"]), String(task.get("hint", ""))]
	)


func _on_crystals_changed(_total: int) -> void:
	_refresh_accum = REFRESH_INTERVAL


## The always-on task line. It exists so the player never has to walk back to the fire
## to remember what they were doing, and it turns gold the moment a task is waiting to
## be handed in.
func _refresh_tracker() -> void:
	var ready: Dictionary = Quests.claimable()
	var task: Dictionary = ready if not ready.is_empty() else Quests.current()
	if task.is_empty():
		_quest_name.text = "All tasks complete"
		_set_bar(_quest_bar, 1.0)
		_quest_progress.text = "The elder has nothing left to set."
		return
	var target: float = maxf(1.0, float(task["target"]))
	if not ready.is_empty():
		_quest_name.text = "%s — ready to hand in" % String(task["title"])
	else:
		_quest_name.text = String(task["title"])
	_quest_name.add_theme_color_override(
		"font_color", Color("ffd76e") if not ready.is_empty() else Color("f2f6fb")
	)
	_set_bar(_quest_bar, Quests.ratio_of(task))
	_quest_progress.text = "%s / %s   ·   %d crystals" % [
		_numeral(float(Quests.progress_of(task))), _numeral(target),
		int(task.get("crystals", 0)),
	]


func _numeral(value: float) -> String:
	return str(int(round(value)))


func _update_status() -> void:
	var pointer: String = "" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		else "   ·   click to look around"
	var state: String = ""
	if _player_in_safe_zone():
		state = "   ·   CAMP WARDS — nothing here will follow you in"
	var dash: String = ""
	if PlayerData.has_ability("dash"):
		dash = "   ·   DASH ready" if _dash_ready() else "   ·   dash cooling"
	if Cultivation.meditating:
		# The trance is a toggle now, so the line has to say how to come out of it.
		state = "   ·   MEDITATING — press C to stand"
	elif Training.is_training():
		state = "   ·   %s" % String(Training.def(Training.active).get("label", "")).to_upper()
	# A spirit zone changes what the trance is doing, so it rides on the same line as
	# the trance rather than being buried in the log where it scrolls away.
	var zone: String = ""
	if Cultivation.zone_name != "":
		zone = ("   ·   %s — dormant, needs stage %d"
			% [Cultivation.zone_name, Cultivation.zone_required_tier]) \
			if Cultivation.zone_locked \
			else "   ·   %s  ×%.1f qi" % [Cultivation.zone_name, Cultivation.zone_boost]

	_status_label.text = (
		"WASD move · Shift run · Space jump · click to strike · Q dash · C cultivate · B break through\n"
		+ "E talk to the elder · 1/2/3 drill the body · X qi pressure · Tab settings · V stats · F5 save\n"
		+ "%d FPS%s%s%s%s" % [Engine.get_frames_per_second(), pointer, state, dash, zone]
	)
	_hint.text = (
		"Click (or F) to strike — posts to raise ATTACK, raiders for crystals.\n"
		+ "Tap 1, 2 or 3 to drill BODY — it costs blood, not qi, and every BODY rank\n"
		+ "widens your HP cap. Talk to the elder by the fire for tasks that unlock\n"
		+ "air jumps and a dash. Cultivate inside a spirit pillar for more qi per second."
	)
	_refresh_pressure()


## The Qi Pressure line: whether the technique exists yet, and if it does, what holding
## it is currently costing and reaching.
##
## It reads the skill's own `state()` rather than working anything out here. The radius,
## the drain and the body count are all things the field is already computing every frame,
## and a panel that re-derived them from the constants would be a second opinion that can
## disagree with the thing on screen.
func _refresh_pressure() -> void:
	if _pressure_label == null:
		return
	var skill: Node3D = _pressure_skill()
	if skill == null:
		_pressure_label.text = "Qi Pressure — unavailable"
		return
	if not skill.has_method("state"):
		_pressure_label.visible = false
		return
	var state: Dictionary = skill.call("state")
	var tint := Color("b9c2cc")
	if not bool(state["unlocked"]):
		# Locked is the one case worth stating as a goal rather than as a state: the
		# number to reach is the whole message.
		_pressure_label.text = "Qi Pressure — needs %.0f QI held (you have %.0f)" % [
			float(state["unlock_qi"]), PlayerData.get_cap("qi")
		]
	elif bool(state["active"]):
		var aura: Color = state["color"]
		tint = aura.lightened(0.25)
		var bodies: int = 0
		if skill.has_method("bodies_in_range"):
			bodies = int(skill.call("bodies_in_range"))
		_pressure_label.text = "Qi Pressure UP — %.1f m · %.0f QI/s · %d in the field" % [
			float(state["radius"]), float(state["drain"]), bodies
		]
	else:
		# The one thing worth knowing before you press the key: whether your pool can
		# pay for the field indefinitely or whether it is a burst you have to leave.
		var held: bool = PlayerData.get_cap("qi") >= float(state["sustain_qi"])
		var cost: String = "self-sustaining" if held \
			else "costs %.0f QI/s" % float(state["drain"])
		_pressure_label.text = "Qi Pressure — X to raise · %.1f m now, %.1f m max · %s" % [
			float(state["radius"]), float(state["max_radius"]), cost
		]
	_pressure_label.add_theme_color_override("font_color", tint)


func _pressure_skill() -> Node3D:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("qi_pressure"):
		return null
	return player.call("qi_pressure") as Node3D


func _player_in_safe_zone() -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("in_safe_zone"):
		return false
	return bool(player.call("in_safe_zone"))


func _dash_ready() -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("dash_ready"):
		return false
	return bool(player.call("dash_ready"))


# ---------------------------------------------------------------------- events

func _on_slider_changed(value: float, stat_id: String) -> void:
	if _syncing_sliders:
		return
	PlayerData.set_allocation(stat_id, value)


func _on_cap_button_pressed(stat_id: String) -> void:
	PlayerData.set_allocation(stat_id, PlayerData.get_cap(stat_id))
	Audio.play("ui_select", -4.0)


func _on_allocation_changed(_stat_id: String, _value: float) -> void:
	_refresh_accum = REFRESH_INTERVAL


func _on_cap_gained(stat_id: String, old_cap: float, new_cap: float) -> void:
	_append_log("%s  %s → %s" % [
		PlayerData.label(stat_id),
		PlayerData.format_value(stat_id, old_cap),
		PlayerData.format_value(stat_id, new_cap),
	], "gain")
	Audio.play_gain(stat_id)


func _on_breakthrough(_tier: int, _realm: String) -> void:
	_refresh_accum = REFRESH_INTERVAL
	Audio.play("breakthrough", -2.0)


func _on_save_pressed() -> void:
	if PlayerData.save_game():
		_append_log("Progress recorded.", "info")
		Audio.play("confirm", -4.0)


func _on_reset_pressed() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _reset_armed_until:
		_reset_armed_until = 0
		PlayerData.reset_progress()
		_refresh()
		Audio.play("error", -2.0)
		return
	_reset_armed_until = now + RESET_CONFIRM_WINDOW_MS
	_append_log("Press Reset again to erase all progression.", "damage")
	Audio.play("ui_click", -6.0)


func _append_log(text: String, kind: String) -> void:
	var color: String = LOG_COLORS.get(kind, LOG_COLORS["info"])
	_log_lines.append("[color=#%s]%s[/color]" % [color, text])
	while _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_log_text.text = "\n".join(_log_lines)
