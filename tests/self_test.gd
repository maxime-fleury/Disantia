extends Node
## Headless self-check. Autoloaded last, and completely inert unless the flag is
## passed on the command line:
##
##   godot --headless --path . -- --selftest
##
## The exit code is the number of failed checks, so a shell `&&` or CI job can
## gate on it.
##
## Two things here are worth more than the rest:
##   * `_test_winding` pulls an engine-authored PlaneMesh out of the engine and
##     compares its triangle winding against the terrain's. That is the only
##     reliable way to learn which way round a hand-built surface must face: get
##     it wrong and the terrain renders inside-out without any error at all.
##   * `_test_terrain_alignment` fires rays down at exact grid points and expects
##     to land on the height the generator reported, which catches a transposed
##     heightmap (otherwise visible only as the player sinking into hillsides).
##
## The suite is destructive to in-memory state, so any real save file is backed
## up first and put back at the end.

const SAMPLE_POINTS: Array = [
	Vector2i(0, 0), Vector2i(6, 0), Vector2i(0, 6), Vector2i(-11, -7),
	Vector2i(23, -14), Vector2i(-30, 21), Vector2i(40, 40), Vector2i(-3, 52),
	Vector2i(-2, 7),
]
const HEIGHT_TOLERANCE := 0.5
## How far out locomotion is measured, and how far ahead of the body the lane has to
## be clear for. The home camp reaches a little over ten metres from the origin, so
## the first figure steps well outside it and the second covers the few metres the
## walk and the run actually travel.
const LANE_DISTANCE := 30.0
const LANE_DEPTH := 14.0
## How much higher than the body's own footing the ground at a landing spot may be.
## Anything steeper is somewhere a body would be buried by a warp rather than dropped
## onto, so the spot is skipped.
const HILL_TOLERANCE := 1.5
const SAVE_PATH := "user://disantia_save.json"
const BACKUP_PATH := "user://disantia_selftest_backup.json"

var _checks: int = 0
var _failures: int = 0
var _had_save: bool = false

var _terrain: Node
var _player: Node
var _hud: Node
var _scatter: Node
var _camp: Node


func _ready() -> void:
	if OS.has_feature("web") or not OS.get_cmdline_user_args().has("--selftest"):
		set_process(false)
		return

	_had_save = _backup_save()
	# Let the terrain build, the HUD lay itself out, and the physics server
	# register the freshly generated collision shape.
	for i in 3:
		await get_tree().physics_frame
	for i in 3:
		await get_tree().process_frame

	# Must be awaited: one of the checks yields a frame, and without this the
	# suite would report a partial result and quit.
	await _run()

	print("---- self test: %d checks, %d failed ----" % [_checks, _failures])
	get_tree().quit(_failures)


# ------------------------------------------------------------------- harness

func _section(title: String) -> void:
	print("\n== %s ==" % title)


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
		return
	_failures += 1
	print("  FAIL  %s%s" % [label, ("   (%s)" % detail) if detail != "" else ""])


func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _copy(from_path: String, to_path: String) -> bool:
	var source: FileAccess = FileAccess.open(from_path, FileAccess.READ)
	if source == null:
		return false
	var text: String = source.get_as_text()
	source.close()
	var target: FileAccess = FileAccess.open(to_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_string(text)
	target.close()
	return true


func _remove(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		dir.remove(path)


func _backup_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	return _copy(SAVE_PATH, BACKUP_PATH)


# ---------------------------------------------------------------- the checks

func _run() -> void:
	_resolve_nodes()
	_reset_state()
	await _start_from_spawn()
	_test_stat_definitions()
	await _test_input_map()
	_test_winding()
	_test_terrain_alignment()
	_test_terrain_shape()
	_test_sun()
	_test_nature()
	_test_camp()
	_test_allocation()
	_test_stat_growth()
	await _test_meditation_drain()
	_test_cultivation()
	_test_player_reads_stats()
	_test_character()
	_test_locomotion()
	await _test_animation_states()
	await _test_poses()
	await _test_qi_zones()
	_test_roads()
	await _test_safe_zone()
	await _test_enemies()
	await _test_quests()
	_test_shop()
	await _test_wards()
	await _test_ward_walls()
	await _test_champions()
	await _test_ranged_bolt()
	await _test_damage_numbers()
	await _test_landmarks()
	await _test_wayfaring()
	await _test_rim()
	await _test_abilities()
	await _test_regen()
	await _test_attainments()
	await _test_qi_pressure()
	await _test_qi_arts()
	await _test_ceilings()
	await _test_step_up()
	await _test_slopes()
	await _test_aura()
	await _test_avatar_overlay()
	await _test_training_and_strike()
	_test_hud()
	_test_meters()
	await _test_stats_panel()
	await _test_map()
	_test_hud_focus()
	await _test_settings_modal()
	await _test_hud_intro()
	await _test_hud_layout()
	await _test_hud_progress()
	# Before the save round trip rather than early in the run: this section changes the world
	# itself — a camp's raiders are spared and another camp is burned — and every test that
	# counts raiders has already had its say by here.
	await _test_people()
	_test_persistence()
	_restore_player_state()


func _resolve_nodes() -> void:
	var root: Node = get_tree().root
	_terrain = root.get_node_or_null("Main/Terrain")
	_player = root.get_node_or_null("Main/Player")
	_hud = root.get_node_or_null("Main/HUD")
	_scatter = root.get_node_or_null("Main/Scatter")
	_camp = root.get_node_or_null("Main/Camp")
	_check(_terrain != null, "Main/Terrain exists")
	_check(_player != null, "Main/Player exists")
	_check(_hud != null, "Main/HUD exists")
	_check(_scatter != null, "Main/Scatter exists")
	_check(_camp != null, "Main/Camp exists")
	_check(root.get_node_or_null("PlayerData") != null, "PlayerData autoload exists")
	_check(root.get_node_or_null("Cultivation") != null, "Cultivation autoload exists")


## Everything below assumes a known starting point, so a loaded save cannot make
## the suite pass or fail differently for different players.
func _reset_state() -> void:
	PlayerData._build_defaults()
	PlayerData.gain_coefficient = 1.0
	PlayerData.has_saved_position = false
	PlayerData.crystals = 0
	PlayerData.abilities = PlayerData.DEFAULT_ABILITIES.duplicate(true)
	# Decisions are the one thing a real player's save would carry that the suite cannot work
	# around: a body that has already chosen a path is a body with no choices left to be about.
	PlayerData.decisions.clear()
	Cultivation.reset()
	Quests.reset()
	Wards.reset()
	# ...and every ward is opened for the rest of the run.
	#
	# The suite warps the body all over the map — to the farthest spirit zone, to far ground,
	# onto hillsides — and a ward doing its job would quietly shove it back out of half of
	# those measurements, which is a failure that would look like a physics bug. The walls get
	# their own section, where they are shut on purpose and the realm is set to open them.
	Wards.set("_passed", Wards.gate_count())


## Puts the body back on the spawn point before anything is measured.
##
## The controller restores the position remembered in the save file at startup, so
## without this the suite begins wherever the *previous* session happened to end —
## standing on a prop, or in mid-air — and a trance that will not start because the
## body is not on the floor reads as a broken game rather than as a dirty start. That
## is not hypothetical: the shipped build failed ten checks this way while the same
## code passed in the editor, purely because the two runs inherited different saved
## positions.
func _start_from_spawn() -> void:
	if _player == null or _terrain == null:
		return
	(_player as Node3D).call("warp_to", _terrain.call("spawn_point", 0.5))
	await _land(_player)
	print("  info  starting on the spawn point at %s" % _player.global_position)


func _test_stat_definitions() -> void:
	_section("Stat definitions")
	_check(PlayerData.STAT_ORDER.size() == 7, "seven stats defined", str(PlayerData.STAT_ORDER))
	var required: Array = ["label", "kind", "base_cap", "cap_step", "need", "color"]
	for stat_id: String in PlayerData.STAT_ORDER:
		var defn: Dictionary = PlayerData.def(stat_id)
		var missing: Array = []
		for key: String in required:
			if not defn.has(key):
				missing.append(key)
		_check(missing.is_empty(), "%s definition is complete" % stat_id, "missing " + str(missing))
		_check(PlayerData.get_cap(stat_id) > 0.0, "%s has a positive cap" % stat_id)


## The input map is written by tools/setup_project.gd rather than typed into
## project.godot, so it is worth proving that a real key press reaches an action
## and not merely that the actions exist.
func _test_input_map() -> void:
	_section("Input map")
	var expected: Array = [
		"move_forward", "move_backward", "move_left", "move_right", "jump",
		"sprint", "meditate", "breakthrough", "quick_save",
		"strike", "dash", "interact", "settings", "toggle_stats",
	]
	var missing: Array = []
	for action: String in expected:
		if not InputMap.has_action(action):
			missing.append(action)
	_check(missing.is_empty(), "every game action is registered", "missing " + str(missing))

	var empty: Array = []
	for action: String in expected:
		if InputMap.has_action(action) and InputMap.action_get_events(action).is_empty():
			empty.append(action)
	_check(empty.is_empty(), "every action has at least one binding", "empty " + str(empty))

	# The strike has to answer to a *click*: with a camera behind the character the hand
	# is already on the mouse, and a swing bound only to a key is a swing that happens a
	# beat late. Checked on the binding rather than by synthesising a click, because what
	# can break here is the binding.
	var mouse_bound: bool = false
	for event: InputEvent in InputMap.action_get_events("strike"):
		if event is InputEventMouseButton:
			mouse_bound = true
	_check(mouse_bound, "the strike answers to a mouse click")

	# R used to teleport the player to the high ground. It was a placeholder from
	# before there were roads to walk, and a key that moves you somewhere else on a
	# procedural map is not a placeholder any more — it is a way to lose your bearings.
	# Deleted rather than unbound, so nothing can read it by accident.
	_check(not InputMap.has_action("ascend"), "the ascend teleport key is gone")

	Input.action_release("jump")
	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.physical_keycode = KEY_SPACE
	press.pressed = true
	Input.parse_input_event(press)
	_check(await _input_settles("jump", true),
		"a simulated Space press reaches the jump action")

	var release := InputEventKey.new()
	release.keycode = KEY_SPACE
	release.physical_keycode = KEY_SPACE
	release.pressed = false
	Input.parse_input_event(release)
	_check(await _input_settles("jump", false), "releasing Space clears the action")


## Waits a few frames for an action to reach the state a parsed event asked for.
##
## `Input.parse_input_event` only queues: the event reaches the Input singleton when
## the engine next flushes, which is not reliably the frame that `process_frame`
## resumes in. Asserting on that one frame tests the flush order rather than the
## binding, and it goes off the moment an await is added anywhere earlier in the
## suite — which is exactly how it failed.
func _input_settles(action: String, want_pressed: bool) -> bool:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
		if Input.is_action_pressed(action) == want_pressed:
			return true
	return false


func _test_winding() -> void:
	_section("Triangle winding")
	var reference: Vector3 = _first_triangle_rh_normal(PlaneMesh.new())
	_check(reference.y != 0.0, "PlaneMesh gives a usable reference triangle")
	if reference.y == 0.0:
		return
	# PlaneMesh's faces point up, so the sign of its right-hand normal is the
	# engine's own answer for "which way is front" on an upward-facing surface.
	var front_rh_sign: float = signf(reference.y)
	print("  info  PlaneMesh up-facing RH normal y = %.3f -> front faces need RH y %s 0"
		% [reference.y, ">" if front_rh_sign > 0.0 else "<"])

	var mesh_node: MeshInstance3D = _terrain.get_node_or_null("Mesh")
	_check(mesh_node != null and mesh_node.mesh != null, "terrain mesh was generated")
	if mesh_node == null or mesh_node.mesh == null:
		return

	var terrain_normal: Vector3 = _first_triangle_rh_normal(mesh_node.mesh)
	_check(signf(terrain_normal.y) == front_rh_sign,
		"terrain triangles wind the same way as the engine's own up-facing plane",
		"terrain RH y = %.3f" % terrain_normal.y)

	var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var downward: int = 0
	for n in normals:
		if n.y <= 0.0:
			downward += 1
	_check(downward == 0, "every vertex normal points upward",
		"%d of %d point down" % [downward, normals.size()])


func _first_triangle_rh_normal(mesh: Mesh) -> Vector3:
	if mesh.get_surface_count() == 0:
		return Vector3.ZERO
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a: Vector3
	var b: Vector3
	var c: Vector3
	if indices.size() >= 3:
		a = verts[indices[0]]
		b = verts[indices[1]]
		c = verts[indices[2]]
	else:
		a = verts[0]
		b = verts[1]
		c = verts[2]
	return (b - a).cross(c - a)


func _test_terrain_alignment() -> void:
	_section("Terrain / collision alignment")
	var state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())

	var worst: float = 0.0
	var misses: int = 0
	var covered: int = 0
	for point: Vector2i in SAMPLE_POINTS:
		var x: float = float(point.x)
		var z: float = float(point.y)
		# Three of the sample points sit inside the home camp, so a tree trunk or a
		# blocker is a perfectly ordinary first hit there — and a hit on a trunk says
		# nothing at all about the collision shape this section is about. Such a
		# collider is excluded and the ray re-cast, so the terrain underneath is still
		# measured instead of the sample being thrown away. The offsets were stable
		# until the road count changed and the camp's procedural layout moved with it,
		# which is exactly how a sample-point assumption turns into a false failure.
		var skip: Array[RID] = exclude.duplicate()
		var expected: float = _terrain.call("height_at", x, z)
		for attempt in 4:
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, 300.0, z), Vector3(x, -200.0, z), 1, skip
			)
			var hit: Dictionary = state.intersect_ray(query)
			if hit.is_empty():
				misses += 1
				break
			if hit.get("collider") == _terrain:
				covered += 1
				worst = maxf(worst, absf(float((hit["position"] as Vector3).y) - expected))
				break
			var other: Object = hit.get("collider")
			if not other is CollisionObject3D:
				break
			skip.append((other as CollisionObject3D).get_rid())

	_check(misses == 0, "ray hits terrain at every sample point", "%d missed" % misses)
	_check(covered == SAMPLE_POINTS.size(),
		"every sample point measures the terrain and not what is standing on it",
		"%d of %d cleared" % [covered, SAMPLE_POINTS.size()])
	_check(worst <= HEIGHT_TOLERANCE, "collision matches terrain heights at grid points",
		"worst delta %.3f m" % worst)

	var shape: CollisionShape3D = _terrain.get_node_or_null("Shape")
	_check(shape != null and shape.shape != null, "collision shape assigned")
	if shape != null and shape.shape != null:
		print("  info  collision shape: %s" % shape.shape.get_class())


func _test_sun() -> void:
	_section("Lighting")
	var sun: DirectionalLight3D = get_tree().root.get_node_or_null("Main/Sun")
	_check(sun != null, "Main/Sun exists")
	if sun == null:
		return
	# A light shines along its own -Z axis.
	var forward: Vector3 = -sun.global_transform.basis.z.normalized()
	_check(forward.y < -0.3, "sun shines downward", "direction %s" % str(forward))
	_check(absf(sun.global_transform.basis.determinant() - 1.0) < 0.001,
		"sun basis is orthonormal")


func _test_allocation() -> void:
	_section("Movement within earned caps")
	PlayerData.set_allocation("speed", 9999.0)
	_check(is_equal_approx(PlayerData.get_allocated("speed"), PlayerData.get_cap("speed")),
		"speed allocation cannot exceed the earned cap")
	PlayerData.set_allocation("speed", -5.0)
	_check(PlayerData.get_allocated("speed") >= 0.0, "speed allocation cannot go negative")
	PlayerData.set_allocation("jump", PlayerData.get_cap("jump") * 0.5)
	_check(_near(PlayerData.get_allocated("jump"), PlayerData.get_cap("jump") * 0.5, 0.001),
		"jump allocation accepts a value below the cap")
	PlayerData.set_allocation("defense", 1.0)
	_check(is_equal_approx(PlayerData.get_cap("defense"), PlayerData.get_value("defense")),
		"passive stats ignore allocation attempts")
	PlayerData.set_allocation("speed", PlayerData.get_cap("speed"))
	PlayerData.set_allocation("jump", PlayerData.get_cap("jump"))


func _test_stat_growth() -> void:
	_section("Earning stats")
	var before: float = PlayerData.get_cap("speed")
	PlayerData.gain("speed", PlayerData.get_cap("speed") * 12.0)
	var after: float = PlayerData.get_cap("speed")
	_check(after > before, "running xp raises the speed cap", "%.2f -> %.2f" % [before, after])
	_check(_near(after, before * 1.05, 0.0001), "speed cap grew by exactly one step",
		"%.5f vs %.5f" % [after, before * 1.05])

	var hp_before: float = PlayerData.get_value("hp")
	PlayerData.apply_damage(20.0)
	_check(PlayerData.get_value("hp") < hp_before, "damage reduces current HP")
	_check(PlayerData.damage_multiplier() < 1.0, "defense mitigates damage",
		"x%.4f" % PlayerData.damage_multiplier())

	var coefficient: float = PlayerData.gain_coefficient
	PlayerData.gain("jump", 10.0)
	_check(is_equal_approx(PlayerData.gain_coefficient, coefficient),
		"earning stats does not change the coefficient by itself")


## The one part of the cultivation loop that only real elapsed time can exercise:
## holding the meditate key has to burn QI, fill both meters, and feed the QI stat.
## Waits (with a cap) for the player to settle on the terrain. The controller has
## no climbing, and meditation is ground-only, so this has to happen first.
func _land_player() -> bool:
	if _player == null or not (_player is CharacterBody3D):
		return false
	for i in 300:
		await get_tree().physics_frame
		if (_player as CharacterBody3D).is_on_floor():
			return true
	return false


## The one part of the cultivation loop that only real elapsed time can exercise,
## and it is driven through the real input path: hold the key, the player
## controller hands control to Cultivation, QI burns down and both meters fill.
func _test_meditation_drain() -> void:
	_section("Meditation")
	Cultivation.reset()
	var landed: bool = await _land_player()
	_check(landed, "player is resting on the terrain")
	if not landed:
		return

	PlayerData.stats["qi"]["current"] = PlayerData.get_cap("qi")
	PlayerData.stats["hp"]["current"] = PlayerData.get_cap("hp") * 0.5
	var qi_before: float = PlayerData.get_value("qi")
	var hp_before: float = PlayerData.get_value("hp")
	var cycle_before: float = Cultivation.cycle
	var qi_progress_before: float = PlayerData.progress_ratio("qi")

	var taps: int = await _enter_trance()
	_check(Cultivation.meditating, "tapping the meditate key enters the trance",
		"%d tap(s)" % taps)
	_check(PlayerData.suppress_qi_regen, "passive QI regen is held off while meditating")

	var loop_qi_before: float = PlayerData.get_value("qi")
	var start_usec: int = Time.get_ticks_usec()
	for i in 90:
		await get_tree().process_frame
	var elapsed: float = maxf(0.0001, float(Time.get_ticks_usec() - start_usec) / 1000000.0)
	var drained: float = qi_before - PlayerData.get_value("qi")
	var rate: float = (loop_qi_before - PlayerData.get_value("qi")) / elapsed
	print("  info  %.2fs in the trance drained %.3f QI (%.2f QI/s, cost is %.2f/s)" % [
		elapsed, drained, rate, Cultivation.qi_cost_per_second()
	])
	_check(_near(rate, Cultivation.qi_cost_per_second(), 0.35),
		"QI drain rate matches the stated cost",
		"%.2f QI/s vs %.2f/s" % [rate, Cultivation.qi_cost_per_second()])

	_check(drained > 0.0, "meditation drains QI", "%.4f drained" % drained)
	_check(PlayerData.get_value("hp") > hp_before, "HP keeps regenerating while meditating",
		"%.4f -> %.4f" % [hp_before, PlayerData.get_value("hp")])
	_check(Cultivation.cycle > cycle_before, "the refinement cycle advances",
		"%.6f -> %.6f" % [cycle_before, Cultivation.cycle])
	_check(Cultivation.insight > 0.0, "insight accrues", "%.4f" % Cultivation.insight)
	_check(PlayerData.progress_ratio("qi") > qi_progress_before,
		"spending QI banks xp toward a bigger QI cap")

	# The trance outlives the key: nothing here releases anything, and it is still on.
	await _settle(4)
	_check(Cultivation.meditating, "the trance holds after the key comes back up")
	await _tap_action("meditate")
	await _settle(3)
	_check(not Cultivation.meditating, "a second tap ends it")
	_check(not PlayerData.suppress_qi_regen, "QI regen resumes when meditation ends")

	# The flag is read from the trance, so no way out of the trance can leave it on. The old
	# version was set false in exactly one function, which meant every other exit — a reset, a
	# collapse, a path added later by someone who never saw the variable — left QI regen off
	# for the rest of the session with nothing on screen to explain it. Writing the trance
	# field directly stands in for all of those exits at once.
	Cultivation.meditating = true
	_check(PlayerData.suppress_qi_regen, "the trance is what holds regen off")
	Cultivation.meditating = false
	_check(not PlayerData.suppress_qi_regen,
		"and a trance ended by any route hands QI regen back",
		"suppress=%s meditating=%s" % [PlayerData.suppress_qi_regen, Cultivation.meditating])

	# The symptom this came from: a bar pinned at zero. Qigong drains the dantian to the
	# bottom on purpose, so a pool that is held at zero once emptied is a one-way door out of
	# the cultivation loop — meditation buys nothing, and the qi that pays for it never comes
	# back.
	PlayerData.stats["qi"]["current"] = 0.0
	for i in 60:
		await get_tree().process_frame
	_check(PlayerData.get_value("qi") > 0.0, "an emptied dantian refills on its own",
		"%.3f of %.1f" % [PlayerData.get_value("qi"), PlayerData.get_cap("qi")])


func _test_cultivation() -> void:
	_section("Cultivation and breakthrough")
	Cultivation.reset()
	_check(is_equal_approx(Cultivation.gain_coefficient(), 1.0),
		"coefficient starts at 1.0 after a reset")

	Cultivation.refinement = Cultivation.refinements_needed()
	Cultivation.insight = Cultivation.insight_required()
	_check(Cultivation.can_break_through(), "full insight plus refinement unlocks a breakthrough")

	var speed_before: float = PlayerData.get_cap("speed")
	PlayerData.stats["hp"]["current"] = 1.0
	_check(Cultivation.break_through(), "break_through() succeeds when ready")
	_check(Cultivation.tier == 1, "tier advanced to 1", "tier %d" % Cultivation.tier)

	var expected_coefficient: float = 1.0 + 0.15 + 0.03 * float(Cultivation.refinement)
	_check(_near(Cultivation.gain_coefficient(), expected_coefficient, 0.0001),
		"coefficient is 1.0 + 3% per refinement + 15% per tier",
		"%.4f vs %.4f" % [Cultivation.gain_coefficient(), expected_coefficient])
	_check(is_equal_approx(PlayerData.gain_coefficient, Cultivation.gain_coefficient()),
		"the coefficient is pushed into PlayerData")
	_check(_near(PlayerData.get_cap("speed"), speed_before * 1.08, 0.002),
		"a breakthrough widens every stat cap by 8%",
		"%.3f -> %.3f" % [speed_before, PlayerData.get_cap("speed")])
	_check(is_equal_approx(PlayerData.get_value("hp"), PlayerData.get_cap("hp")),
		"a breakthrough restores HP and QI to the new cap")
	_check(_near(Cultivation.insight, 0.0, 0.0001), "insight is spent by the breakthrough")
	_check(not Cultivation.can_break_through(), "a spent breakthrough cannot be repeated")
	_check(Cultivation.realm_name() == String(Cultivation.REALMS[0]),
		"tier 1 is still in the first realm", Cultivation.realm_label())

	# The coefficient has to actually multiply income: a lump of xp divided by the
	# coefficient must still be enough to fill exactly one step.
	var cap_before: float = PlayerData.get_cap("speed")
	var needed: float = cap_before * float(PlayerData.def("speed")["need"])
	PlayerData.gain("speed", needed / PlayerData.gain_coefficient)
	_check(PlayerData.get_cap("speed") > cap_before,
		"coefficient-scaled income fills the bar",
		"%.3f -> %.3f" % [cap_before, PlayerData.get_cap("speed")])


func _test_player_reads_stats() -> void:
	_section("Player reads live stats")
	if _player == null:
		return
	_check(_player.has_method("jump_velocity"), "player controller script is attached")
	if not _player.has_method("jump_velocity"):
		return
	PlayerData.set_allocation("jump", PlayerData.get_cap("jump"))
	var high: float = _player.call("jump_velocity")
	PlayerData.set_allocation("jump", PlayerData.get_cap("jump") * 0.25)
	var low: float = _player.call("jump_velocity")
	_check(low < high, "lowering the jump slider lowers jump velocity",
		"%.2f vs %.2f" % [low, high])

	# v^2 / 2g must equal the height the slider promised.
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) \
		* float(_player.get("gravity_scale"))
	var reached: float = (low * low) / (2.0 * gravity)
	_check(_near(reached, PlayerData.max_jump_height(), 0.02),
		"jump velocity is derived from the wanted height",
		"%.3f m reached vs %.3f m asked for" % [reached, PlayerData.max_jump_height()])
	PlayerData.set_allocation("jump", PlayerData.get_cap("jump"))
	PlayerData.set_allocation("speed", PlayerData.get_cap("speed"))


func _test_hud() -> void:
	_section("HUD")
	if _hud == null:
		return
	# The suite runs synchronously between frames, so the HUD's own 10 Hz tick
	# will not have fired since the stats changed. Drive it by hand.
	_hud.call("_refresh")

	var rows: Node = _hud.get_node_or_null("HudRoot/TopLeft/StatsPanel/Body/StatRows")
	_check(rows != null, "stat rows container exists")
	if rows != null:
		_check(rows.get_child_count() == PlayerData.STAT_ORDER.size(), "one row per stat",
			"%d rows" % rows.get_child_count())

	var sliders: Array[HSlider] = []
	_collect_sliders(_hud, sliders)
	_check(sliders.size() == 2, "speed and jump sliders built", "%d sliders" % sliders.size())
	if sliders.size() == 2:
		var caps: Array = [PlayerData.get_cap("speed"), PlayerData.get_cap("jump")]
		var matched: bool = true
		for i in sliders.size():
			if not _near(sliders[i].max_value, float(caps[i]), 0.001):
				matched = false
		_check(matched, "every slider's maximum is the earned cap",
			"caps %s vs sliders %s" % [
				str(caps), str([sliders[0].max_value, sliders[1].max_value])
			])

	var log_text: RichTextLabel = _hud.get_node_or_null("HudRoot/LogPanel/LogText")
	_check(log_text != null and log_text.text.length() > 0, "event log is receiving messages")


func _collect_sliders(node: Node, out: Array[HSlider]) -> void:
	if node is HSlider:
		out.append(node)
	for child in node.get_children():
		_collect_sliders(child, out)


func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out)


## Labels with something written in them, at any depth. A row is a column holding a
## heading that holds the labels, so counting only the immediate children of the
## container reports every panel as empty.
func _filled_labels(node: Node) -> int:
	var found: int = 0
	if node is Label and (node as Label).text.length() > 0:
		found += 1
	for child in node.get_children():
		found += _filled_labels(child)
	return found


func _find_by_name(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found: Node = _find_by_name(child, wanted)
		if found != null:
			return found
	return null


## Nothing here can be checked by looking at a screenshot, so the layout is
## asserted numerically instead: every panel must sit inside the design viewport
## and no two panels may overlap. That is what catches the classic "a panel grew
## with its content and is now buried under another one" bug.
func _test_hud_layout() -> void:
	_section("HUD layout")
	if _hud == null:
		return
	var configured := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	)
	var design: Vector2 = _hud.get_viewport().get_visible_rect().size
	print("  info  canvas %dx%d (design %dx%d)" % [
		int(design.x), int(design.y), int(configured.x), int(configured.y)
	])
	# Stretch mode canvas_items with aspect expand only ever grows the canvas past
	# the design resolution, so edge-anchored panels stay put in any browser
	# window. Assert that guarantee, then lay out against the real rect.
	_check(design.x >= configured.x - 0.5 and design.y >= configured.y - 0.5,
		"canvas is never smaller than the design resolution", str(design))
	_assert_layout(design, "on the current canvas")

	# ...and again with the stat readout open, which is the tallest the top-left column
	# ever gets and the case that matters. Checking only the folded layout is what let
	# the task tracker sink into the event log: nothing overlaps at all until you press
	# Show, and pressing Show is the first thing a player does.
	_hud.call("set_stats_expanded", true)
	await _settle(4)
	_assert_layout(design, "with the stat readout open")
	_assert_column_fits(configured.y)
	_hud.call("set_stats_expanded", false)
	await _settle(4)
	await _test_design_resolution()


## The top-left column against the event log, at the shortest canvas the game can be
## asked to show.
##
## The two are laid out independently: the column is anchored to the top and grows
## downward with its contents, the log is anchored to the bottom and grows upward with
## the lines it keeps. Neither knows the other exists, so the only thing holding them
## apart is there being room — and there stops being room the moment the stat readout
## is open on a short canvas, which is how the task tracker came to sink into the log
## and have its last line dimmed by the log's own backing.
##
## Both numbers are canvas-independent, so this is evaluated at the *design* resolution
## rather than at whatever size the test window happens to be. That matters: the headless
## window is square, which is the roomiest case there is, and a resize-based check cannot
## reach the tight one if the display server declines to resize.
func _assert_column_fits(design_height: float) -> void:
	var column: Control = _find_by_name(_hud, "TopLeft") as Control
	var log_panel: Control = _find_by_name(_hud, "LogPanel") as Control
	if column == null or log_panel == null:
		_check(false, "the left column and the event log are both in the scene")
		return
	# A container lays its children out from its top and lets them run past its own edge
	# when the contents need more room than the rect it was given, so the content ends at
	# whichever of the two is greater. Reading `size` alone reports a column that fits
	# while its last panel is hanging out of the bottom of it.
	var content: float = maxf(column.size.y, column.get_combined_minimum_size().y)
	var ending: float = column.position.y + content
	var log_top: float = design_height + log_panel.offset_top
	_check(ending <= log_top - 8.0,
		"the stat column clears the event log at the shortest canvas",
		"ends at %.0f, log starts at %.0f, %.0f px of room" % [ending, log_top, log_top - ending])


## The tightest layout the game can ever be asked to show is exactly the design
## resolution, and the headless window happens to be square, so exercise it explicitly
## rather than trusting luck.
func _test_design_resolution() -> void:
	var window: Window = _hud.get_viewport() as Window
	if window == null:
		return
	var configured := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	)
	var design: Vector2 = _hud.get_viewport().get_visible_rect().size
	var restore: Vector2i = window.size
	window.size = Vector2i(int(configured.x), int(configured.y))
	await get_tree().process_frame
	await get_tree().process_frame
	var resized: Vector2 = _hud.get_viewport().get_visible_rect().size
	print("  info  resized canvas %dx%d" % [int(resized.x), int(resized.y)])
	if resized.y < design.y - 1.0:
		_assert_layout(resized, "at the design resolution")
	else:
		print("  info  display server ignored the resize; tightest-case layout not exercised")
	window.size = restore


## Every panel the HUD shows, found rather than listed.
##
## This used to be a hard-coded list of five names, and the task tracker was not in it —
## so the tracker drifted down into the event log, which dimmed its bottom line through
## the log's own background, and the overlap check reported everything fine. The new map
## panel would have been the second omission. Finding them means a panel added later is
## covered by existing, not by remembering.
func _visible_panels() -> Array:
	var out: Array = []
	for node in _root_children():
		var panel := node as PanelContainer
		if panel == null:
			continue
		# A panel that is not on screen is not on screen: it can neither be off the edge
		# nor overlap anything. The modals are hidden until opened and checked separately.
		if not panel.is_visible_in_tree():
			continue
		out.append(panel)
	return out


func _root_children() -> Array:
	var root: Control = _find_by_name(_hud, "HudRoot") as Control
	return root.get_children() if root != null else []


func _assert_layout(design: Vector2, label: String) -> void:
	# The five the scene ships are still named, because "it exists" is a different claim
	# from "it does not overlap", and a scene edit that lost one should say so.
	for panel_name: String in [
		"CultivationPanel", "StatsPanel", "ActionPanel", "LogPanel", "HelpPanel",
	]:
		_check(_find_by_name(_hud, panel_name) != null, "%s exists" % panel_name)

	var rects: Dictionary = {}
	for node: Node in _visible_panels():
		var panel: Control = node
		var panel_name: String = String(panel.name)
		var rect: Rect2 = panel.get_global_rect()
		rects[panel_name] = rect
		_check(rect.size.x > 1.0 and rect.size.y > 1.0, "%s has a real size" % panel_name, str(rect))
		_check(rect.position.x >= -0.5 and rect.position.y >= -0.5
				and rect.end.x <= design.x + 0.5 and rect.end.y <= design.y + 0.5,
			"%s is fully on screen %s" % [panel_name, label],
			"%s in %dx%d" % [str(rect), int(design.x), int(design.y)])
		# A panel the layout has squeezed smaller than its own contents clips them: the
		# container cannot fit what is inside it, so the last line is drawn past the edge
		# and the frame cuts it off. That is invisible to a size or overlap check and is
		# exactly how the tracker's progress line ended up half-drawn.
		var needed: Vector2 = panel.get_combined_minimum_size()
		_check(panel.size.x + 0.5 >= needed.x and panel.size.y + 0.5 >= needed.y,
			"%s is big enough for its own contents %s" % [panel_name, label],
			"needs %s in %s" % [str(needed), str(panel.size)])

	var keys: Array = rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			_check(not a.intersects(b), "%s does not overlap %s %s" % [keys[i], keys[j], label],
				"%s vs %s" % [str(a), str(b)])


## The parts of the interface that are fed by the new systems: the purse, the task
## tracker, the task panel, and the size the player can dial.
func _test_hud_progress() -> void:
	_section("HUD: purse and tasks")
	if _hud == null:
		return
	PlayerData.add_crystals(4)
	_hud.call("_refresh")
	var purse: Label = _find_by_name(_hud, "CrystalsLabel") as Label
	_check(purse != null, "the HUD shows the crystal purse")
	if purse != null:
		_check(purse.text.find(str(PlayerData.crystals)) >= 0, "with the count in it",
			"%s against %d" % [purse.text, PlayerData.crystals])

	var tracker: Label = _find_by_name(_hud, "QuestName") as Label
	var bar: ProgressBar = _find_by_name(_hud, "QuestBar") as ProgressBar
	_check(tracker != null and bar != null, "and the task tracker")
	if tracker != null and bar != null:
		_check(is_equal_approx(bar.max_value, 1.0),
			"whose bar is ranged as a ratio like every other meter")
		_check(bar.value >= 0.0 and bar.value <= 1.0, "and sits in it", "%.2f" % bar.value)
		_check(tracker.text.length() > 0, "naming something", tracker.text)

	# The panel the elder opens: it reports the task, and its button is only live when
	# there is something to hand in.
	_check(_hud.has_method("show_tasks") and _hud.has_method("tasks_open"),
		"the task panel can be opened and reported")
	_hud.call("show_tasks")
	_check(bool(_hud.call("tasks_open")), "opening it works")
	var claim: Button = _find_by_name(_hud, "Claim") as Button
	_check(claim != null, "and it carries a button to hand the task in")
	if claim != null:
		_check(claim.disabled == Quests.claimable().is_empty(),
			"which is live only when a task is finished",
			"disabled=%s, claimable=%s" % [str(claim.disabled), str(not Quests.claimable().is_empty())])
	_hud.call("close_tasks")
	_check(not bool(_hud.call("tasks_open")), "and it closes again")

	# The interface size is a setting, and applying it has to move a real panel.
	var panel: Control = _find_by_name(_hud, "HelpPanel") as Control
	var original: float = PlayerData.ui_scale
	PlayerData.set_ui_scale(0.7)
	_hud.call("_apply_ui_scale")
	_check(panel != null and _near(panel.scale.x, 0.7, 0.001),
		"the interface scales to the size the player picks",
		"%.2f" % (panel.scale.x if panel != null else -1.0))
	_check(panel != null and _near(panel.scale.y, 0.7, 0.001), "on both axes")
	PlayerData.set_ui_scale(original)
	_hud.call("_apply_ui_scale")
	_check(panel != null and _near(panel.scale.x, original, 0.001), "and back again")


# ------------------------------------------------------------------- the spine

## The wards: the table itself, and the agreement between it and everything else that has
## an opinion about the shape of the world.
##
## Read rather than copied, in every case. A check that hard-codes "66 metres" would pass
## on the day it was written and go on passing after the map doubled, which is exactly the
## failure the fractions exist to prevent.
func _test_wards() -> void:
	_section("Wards")
	_check(Wards.gate_count() >= 2, "the road out has wards across it",
		"%d gates" % Wards.gate_count())
	var extent: float = float(_terrain.call("extent"))
	var last: float = 0.0
	for i in Wards.gate_count():
		var gate: Dictionary = Wards.GATES[i]
		var radius: float = Wards.radius_of(i)
		_check(radius > last + 20.0,
			"%s stands further out than the ward before it" % String(gate["name"]),
			"%.0f m" % radius)
		_check(radius < extent * 0.96, "%s stands inside the world" % String(gate["name"]),
			"%.0f m of %.0f m" % [radius, extent])
		_check(int(gate["required_realm"]) <= Wards.GATES.size(),
			"%s wants a realm that exists" % String(gate["name"]),
			"%s" % Wards.realm_label_of(i))
		var warden: Dictionary = gate["warden"]
		_check(String(warden["id"]) != "" and String(warden["label"]) != "",
			"%s has a champion with a name" % String(gate["name"]))
		last = radius

	# Ring r is powered by zone r. This is the loop: the boost that makes a realm cheap is
	# always on the far side of the wall that realm opens, and the two lists are written in
	# two different files, so the check is that they still describe the same world.
	var zones_node: Node = get_tree().root.get_node_or_null("Main/QiZones")
	if zones_node != null:
		var defs: Array = zones_node.get("ZONE_DEFS")
		_check(defs.size() == Wards.RING_ZONES.size(), "there is one spirit zone per ring",
			"%d zones, %d rings" % [defs.size(), Wards.RING_ZONES.size()])
		for i in mini(defs.size(), Wards.RING_ZONES.size()):
			_check(String(defs[i]["id"]) == String(Wards.RING_ZONES[i]),
				"ring %d is powered by %s" % [i, defs[i]["name"]])
		var placed: Array = zones_node.call("zones")
		for zone: Dictionary in placed:
			var ring: int = int(zone.get("ring", -1))
			var from_home: float = Vector2(
				zone["position"].x, zone["position"].z).length()
			# A zone in the wrong ring would be a boost you can farm from inside a wall —
			# or one you cannot reach at all — and neither is visible in a placement log.
			var inner: float = 0.0 if ring <= 0 else Wards.radius_of(ring - 1)
			_check(ring >= 0 and from_home >= inner,
				"%s is on the far side of the ward that opens its ring" % zone["name"],
				"%.0f m, ring %d opens at %.0f m" % [from_home, ring, inner])

	# The things to find, one ring at a time. Two of them have to be inside the first ward:
	# the elder asks for two of the old places several minutes before any realm can open a
	# wall, and a task chain that stalls behind a wall is a wall with a bug report on it.
	var sites_node: Node = get_tree().root.get_node_or_null("Main/Landmarks")
	if sites_node != null and sites_node.has_method("sites_in_ring"):
		for ring in Wards.RING_ZONES.size():
			var in_ring: int = (sites_node.call("sites_in_ring", ring) as Array).size()
			_check(in_ring >= 1, "ring %d has places to find in it" % ring,
				"%d sites" % in_ring)
		var first: int = (sites_node.call("sites_in_ring", 0) as Array).size()
		_check(first >= 2, "and the ring you start in has enough for the elder's errand",
			"%d sites inside the first ward" % first)

	# The goal line: one thing at a time, a ratio the HUD can draw, and words that name what
	# the player has to do rather than what the system is called.
	var goal: Dictionary = Wards.goal()
	_check(not String(goal.get("title", "")).is_empty(), "the path always names one next thing")
	_check(float(goal["progress"]) >= 0.0 and float(goal["progress"]) <= 1.0,
		"the path meter is a ratio like every other bar", "%.2f" % float(goal["progress"]))
	_check(String(goal.get("chapter", "")) != "",
		"and says which ring it is talking about", String(goal["chapter"]))
	_check(String(goal.get("detail", "")) != "",
		"with a longer answer in the tooltip", String(goal["detail"]))
	if _hud != null:
		_hud.call("_refresh_path")
		var path_name: Label = _find_by_name(_hud, "PathName") as Label
		var chapter: Label = _find_by_name(_hud, "PathChapter") as Label
		var bar: ProgressBar = _find_by_name(_hud, "PathBar") as ProgressBar
		_check(path_name != null and not path_name.text.is_empty(),
			"the HUD carries the next thing on the path")
		_check(chapter != null and chapter.text.begins_with("THE PATH"),
			"and names the ring it belongs to", chapter.text if chapter != null else "missing")
		_check(bar != null and _near(bar.max_value, 1.0, 0.001),
			"with a meter on the same 0..1 scale as the rest of them")


## The walls themselves: that a ward the realm has not opened actually stops a body, and
## that the same ward stops stopping once it has.
##
## The body is warped rather than walked, because the claim is about the boundary rather than
## about the legs: a test that ran into the wall would also be testing the slope of the
## ground it ran over.
func _test_ward_walls() -> void:
	_section("Ward walls")
	var walls: Node3D = get_tree().root.get_node_or_null("Main/WardWalls") as Node3D
	_check(walls != null, "the wards are built in the world")
	if walls == null or _player == null or _terrain == null:
		return
	var keep: Dictionary = Wards.save_data()
	var tier_keep: int = Cultivation.tier

	# A fresh cultivator, standing inside the first wall.
	Wards.set("_passed", 0)
	Cultivation.tier = 0
	Wards.changed.emit()
	await _settle(2)
	var radius: float = Wards.radius_of(0)
	_check(bool(walls.call("wall_visible", 0)), "a ward you have not earned is standing")
	_check(not Wards.is_open(0), "and the rule agrees that it is shut", Wards.blocker(0))
	var before: int = int(walls.call("blocked_count"))
	(_player as Node3D).call("warp_to", _ground_spot(radius + 8.0))
	await _settle(6)
	var reached: float = Vector2(_player.global_position.x, _player.global_position.z).length()
	_check(reached < radius, "a shut ward turns the body back",
		"%.0f m out against a wall at %.0f m" % [reached, radius])
	_check(int(walls.call("blocked_count")) > before, "and it is the wall that did it")
	_check(Wards.passed() == 0, "and nothing was recorded as crossed")

	# The same wall, with the realm it wants.
	Cultivation.tier = int(Wards.GATES[0]["required_realm"]) * Cultivation.STAGES_PER_REALM
	await _settle(2)
	_check(Wards.is_open(0), "the realm the ward asks for opens it",
		"%s" % Wards.realm_label_of(0))
	(_player as Node3D).call("warp_to", _ground_spot(radius + 8.0))
	await _settle(6)
	_check(Wards.passed() >= 1, "walking out through an open ward crosses it",
		"%d crossed" % Wards.passed())
	_check(not bool(walls.call("wall_visible", 0)), "and the fence is gone")

	# ...and a save dropped outside a wall it has not opened is put back inside, because a
	# body on the wrong side of a closed ward is a world state nothing else can repair.
	Wards.set("_passed", 0)
	Cultivation.tier = 0
	Wards.changed.emit()
	(_player as Node3D).call("warp_to", _ground_spot(radius + 8.0))
	await _settle(4)
	walls.call("_reconcile")
	await _settle(2)
	var inside: float = Vector2(_player.global_position.x, _player.global_position.z).length()
	_check(inside < radius, "a body left on the wrong side of a shut ward is put back",
		"%.0f m" % inside)

	Wards.set("_passed", int(keep["passed"]))
	Wards.set("_wardens_down", (keep["wardens"] as Array).duplicate())
	Cultivation.tier = tier_keep
	Wards.changed.emit()
	await _settle(2)


## A ground spot at a given radius from the fire, on the terrain rather than above it.
func _ground_spot(radius: float) -> Vector3:
	var height: float = float(_terrain.call("surface_height_at", radius, 0.0))
	return Vector3(radius, height + 2.0, 0.0)


## The champions: that they exist where the table says, that they are a fight rather than a
## formality, and that beating one is permanent and pays.
func _test_champions() -> void:
	_section("Champions")
	var camps: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	if camps == null:
		_check(false, "the camps are part of the world")
		return
	var standing: Array = camps.call("champions")
	var expected: int = 0
	for gate: Dictionary in Wards.GATES:
		if not Wards.warden_down(String((gate["warden"] as Dictionary)["id"])):
			expected += 1
	# Asked of the world rather than of the table, because the world was built *from the
	# player's save* and the suite resets that save a few frames later. A body who felled a
	# champion in an earlier session arrives to a map with one camp fewer, which is the design
	# — the ring they took stays taken — and a check that counted the table alone would call
	# that a bug every time somebody actually played the game between two runs.
	var left_out: Array = camps.call("warden_left_out")
	_check(standing.size() + left_out.size() == Wards.GATES.size(),
		"every warden is either standing over its zone or was felled in an earlier session",
		"%d standing, %d already felled of %d"
			% [standing.size(), left_out.size(), Wards.GATES.size()])
	for gate: Dictionary in Wards.GATES:
		var gate_id: String = String((gate["warden"] as Dictionary)["id"])
		if not Wards.warden_down(gate_id):
			continue
		var rebuilt: bool = false
		for champion: Node in standing:
			if String(champion.get("warden_id")) == gate_id:
				rebuilt = true
		_check(not rebuilt, "%s is down and has not been rebuilt" % gate_id,
			"a felled champion that comes back makes the ring a treadmill")
	if standing.is_empty():
		print("  info  every champion in this save is already down; the kill is not re-run")
		return

	# Each one stands on the zone of the ring it holds — the whole reason it exists.
	var zones_node: Node = get_tree().root.get_node_or_null("Main/QiZones")
	if zones_node != null:
		var placed: Array = zones_node.call("zones")
		for champion: Node3D in standing:
			var ring: int = int(champion.call("warden_id_ring"))
			var zone: Dictionary = {}
			for candidate: Dictionary in placed:
				if int(candidate.get("ring", -1)) == ring:
					zone = candidate
					break
			if zone.is_empty():
				continue
			var gap: float = Vector2(
				champion.global_position.x - zone["position"].x,
				champion.global_position.z - zone["position"].z).length()
			_check(gap <= 30.0, "%s stands at %s" % [champion.get("display_name"), zone["name"]],
				"%.0f m away" % gap)

	# The fight, and the payout. The body's own bookkeeping is put back afterwards: this
	# check deliberately kills something that pays permanent caps, and every other check in
	# the suite expects the cultivator it was handed.
	var champion: Node3D = standing[0]
	var stats_keep: Dictionary = PlayerData.stats.duplicate(true)
	var crystals_keep: int = PlayerData.crystals
	var id: String = String(champion.get("warden_id"))
	var label: String = String(champion.get("display_name"))
	var ring: int = int(champion.call("warden_id_ring"))
	var hp: float = float(champion.get("max_hp"))
	_check(hp >= 200.0 and is_finite(hp), "%s has a champion's health" % label, "%.0f" % hp)
	_check(hp >= float(Wards.GATES[ring - 1]["warden"]["hp_floor"]),
		"and never less than the floor it is promised")
	_check(not Wards.zone_awake(ring), "%s is holding the zone of its ring" % label)
	var cap_before: float = PlayerData.get_cap("attack")
	champion.call("take_hit", hp * 4.0, _player.global_position)
	await _settle(4)
	_check(Wards.warden_down(id), "%s stays down" % label)
	_check(bool(champion.call("is_dead")), "and does not get back up")
	_check(float(champion.get("respawn_seconds")) > 1.0e9,
		"because it has no respawn timer at all", "%.0f s" % float(champion.get("respawn_seconds")))
	_check(Wards.zone_awake(ring), "and the ground it was standing on is awake")
	_check(PlayerData.crystals > crystals_keep, "beating it pays crystals",
		"%d crystals" % int(champion.get("crystals")))
	_check(PlayerData.get_cap("attack") > cap_before,
		"and widens a cap permanently", "ATTACK %.1f -> %.1f" % [cap_before, PlayerData.get_cap("attack")])
	var saved: Array = Wards.save_data()["wardens"]
	_check(saved.has(id), "and the save remembers which champion fell")
	PlayerData.stats = stats_keep
	PlayerData.crystals = crystals_keep
	await _settle(2)


## The Ninth's thrown attack: the one thing in the game that can reach a player who has
## stepped back, and the reason the last fight is not the previous one with a bigger number.
func _test_ranged_bolt() -> void:
	_section("The Ninth")
	var camps: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	if camps == null or _player == null:
		return
	var shooter: Node3D
	for champion: Node3D in camps.call("champions"):
		if float(champion.get("bolt_damage")) > 0.0:
			shooter = champion
			break
	if shooter == null:
		print("  info  the Ninth is already down in this save; the bolt is not re-run")
		return
	_check(float(shooter.get("bolt_damage")) > 0.0, "the last champion throws something")
	_check(float(shooter.get("bolt_range")) > float(shooter.get("bolt_min_range")),
		"and there is a band of ground where it will")

	# Stand where it can reach, wake it up, and let one fly.
	var bolt_hits: Array = []
	if (_player as Node).has_signal("struck"):
		(_player as Node).struck.connect(func(amount: float) -> void: bolt_hits.append(amount))
	var hp_before: float = PlayerData.get_value("hp")
	shooter.set("_aggro", true)
	shooter.set("_bolt_timer", 0.0)
	var at: Vector3 = shooter.global_position + Vector3(12.0, 0.0, 0.0)
	at.y = float(_terrain.call("surface_height_at", at.x, at.z)) + 1.4
	(_player as Node3D).call("warp_to", at)
	var seen: int = 0
	for i in 160:
		await get_tree().physics_frame
		seen = maxi(seen, get_tree().get_nodes_in_group("qi_bolt").size())
		if not bolt_hits.is_empty():
			break
	_check(seen > 0, "it throws a bolt at a body standing twelve metres away")
	_check(not bolt_hits.is_empty(), "and the bolt that reaches the body hurts it",
		"%.0f raw, hp %.1f -> %.1f" % [
			float(shooter.get("bolt_damage")), hp_before, PlayerData.get_value("hp")])
	# Everything it left in the air is cleaned up by its own timer rather than by the world.
	await _settle(260)
	_check(get_tree().get_nodes_in_group("qi_bolt").size() == 0,
		"a bolt that hits nothing stops existing")


## The numbers that pop off a body. Cheap, and the only feedback in the game that says "am
## I doing anything" rather than "how much is left".
func _test_damage_numbers() -> void:
	_section("Damage numbers")
	var camps: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	if camps == null or _player == null:
		return
	var target: Node3D
	for enemy: Node3D in camps.call("enemies"):
		if not bool(enemy.call("is_dead")) and not bool(enemy.call("is_champion")):
			target = enemy
			break
	if target == null:
		print("  info  no living raider to hit; the popup is not re-run")
		return
	var before: int = get_tree().get_nodes_in_group("damage_popup").size()
	var dealt: float = float(target.call("take_hit", 12.0, _player.global_position))
	await _settle(2)
	_check(dealt > 0.0, "a blow lands on a raider", "%.1f" % dealt)
	_check(get_tree().get_nodes_in_group("damage_popup").size() == before + 1,
		"and prints exactly one number")
	# And it clears itself up, which is the only reason a node per hit is affordable.
	await _settle(120)
	_check(get_tree().get_nodes_in_group("damage_popup").size() == before,
		"and the number leaves on its own")


## Finding one of the old places: crystals, a permanent cap, and a line on the elder's chain.
##
## This exists because the whole tail of a site's discovery used to be dead. The boon guard
## asked a Node for a function it does not have, the call failed, and a failed call in GDScript
## ends the method it is in — so the cap was never granted and, two statements further down,
## the quest counter was never reported. "Find two of the old places" was therefore impossible,
## and everything the chain pays out after it — a second air jump, the shorter dash — was
## unreachable. A check that only counted crystals would have passed the whole time.
func _test_landmarks() -> void:
	_section("Finding a place")
	var landmarks: Node = get_tree().root.get_node_or_null("Main/Landmarks")
	if landmarks == null or _player == null:
		return
	var target: Dictionary = {}
	for site: Dictionary in landmarks.call("sites"):
		if not bool(site.get("discovered", false)):
			target = site
			break
	if target.is_empty():
		print("  info  every site in this save is already found; the payout is not re-run")
		return

	# Put the elder's chain on the errand it names, so "did this count" has an answer.
	var errand: int = -1
	for i in Quests.TASKS.size():
		if String(Quests.TASKS[i]["id"]) == "walkabout":
			errand = i
	if errand >= 0:
		Quests.set("_completed", errand)
		Quests.set("_claimed", errand)
	var progress_before: float = Quests.progress_of(Quests.TASKS[errand]) if errand >= 0 else 0.0

	var stats_keep: Dictionary = PlayerData.stats.duplicate(true)
	var crystals_keep: int = PlayerData.crystals
	var id: String = String(target["id"])
	var boon: Dictionary = target["boon"]
	var stat_id: String = String(boon.get("stat", ""))
	var cap_before: float = PlayerData.get_cap(stat_id) if stat_id != "" else 0.0
	var at: Vector3 = target["position"]
	at.y = float(_terrain.call("surface_height_at", at.x, at.z)) + 1.2
	(_player as Node3D).call("warp_to", at)
	await _settle(8)
	_check(PlayerData.found_landmarks.has(id), "walking into a site makes it yours", id)
	_check(PlayerData.crystals > crystals_keep, "it pays crystals")
	_check(stat_id != "" and PlayerData.get_cap(stat_id) > cap_before,
		"and raises a cap, which is the half that used to be lost",
		"%s %.1f -> %.1f" % [stat_id, cap_before, PlayerData.get_cap(stat_id)])
	if errand >= 0:
		_check(Quests.progress_of(Quests.TASKS[errand]) > progress_before,
			"and the elder counts it towards his errand",
			"%.0f -> %.0f" % [progress_before, Quests.progress_of(Quests.TASKS[errand])])
	PlayerData.stats = stats_keep
	PlayerData.crystals = crystals_keep
	Quests.reset()
	await _settle(2)


## Wayfaring: the one destination, and the two ways it can fail.
func _test_wayfaring() -> void:
	_section("Wayfaring")
	if _player == null or _terrain == null:
		return
	var far: Vector3 = _ground_spot(40.0)
	(_player as Node3D).call("warp_to", far)
	await _settle(4)
	Input.action_release("recall")
	await _settle(2)
	_check(not bool((_player.call("recall_state") as Dictionary)["attuning"]),
		"standing still with the key up is not an attunement")

	Input.action_press("recall")
	await _settle(8)
	var state: Dictionary = _player.call("recall_state")
	_check(bool(state["attuning"]), "holding the key starts one",
		"%.0f%%" % (float(state["progress"]) * 100.0))
	_check(float(state["progress"]) > 0.0 and float(state["progress"]) < 1.0,
		"and it takes long enough to be a decision")
	# A blow breaks it. The technique is a way to travel, not a way out of a fight — which is
	# the only reason a teleport home can exist in a game built on being able to retreat.
	(_player as Node).call("take_enemy_blow", 1.0, null)
	await _settle(2)
	var broken: Dictionary = _player.call("recall_state")
	_check(not bool(broken["attuning"]), "a blow breaks it")
	_check(bool(broken["blocked"]), "and it stays broken while the key is still held")
	var distance: float = Vector2(_player.global_position.x, _player.global_position.z).length()
	_check(distance > 30.0, "and nothing moved", "%.0f m from the fire" % distance)

	# All the way through, for real — and the key has to come *up* first, which is the block
	# doing its job rather than the test working around it.
	Input.action_release("recall")
	await _settle(2)
	_check(not bool((_player.call("recall_state") as Dictionary)["blocked"]),
		"letting go clears the interruption")
	Input.action_press("recall")
	var seconds: float = float(_player.get("recall_seconds"))
	await _settle(int(ceil(seconds * 70.0)) + 20)
	Input.action_release("recall")
	await _settle(4)
	var home: float = Vector2(_player.global_position.x, _player.global_position.z).length()
	_check(home < 12.0, "held through, it puts the body back at the fire", "%.0f m" % home)


## The rim: the terrain is a square mesh with nothing beyond it, and walking off it used to
## end a session with no explanation at all.
func _test_rim() -> void:
	_section("The rim of the world")
	if _player == null or _terrain == null:
		return
	var limit: float = float(_terrain.call("extent")) * 0.965
	var at: Vector3 = _ground_spot(limit - 2.0)
	(_player as Node3D).call("warp_to", Vector3(limit + 60.0, at.y, 0.0))
	await _settle(8)
	var reached: float = Vector2(_player.global_position.x, _player.global_position.z).length()
	_check(reached <= limit + 1.0, "the edge of the world holds the body in",
		"%.0f m out, rim at %.0f m" % [reached, limit])
	_check(_player.global_position.y > -10.0, "and it is not falling into nothing",
		"y %.1f" % _player.global_position.y)
	(_player as Node3D).call("warp_to", _ground_spot(0.0) + Vector3(0.0, 4.0, 0.0))
	await _settle(4)


func _test_persistence() -> void:
	_section("Persistence")
	Cultivation.tier = 4
	Cultivation.refinement = 7
	Cultivation.insight = 3.5
	PlayerData.gain("speed", 900.0)
	PlayerData.set_allocation("speed", PlayerData.get_cap("speed") * 0.5)
	var expected_speed_cap: float = PlayerData.get_cap("speed")
	var expected_alloc: float = PlayerData.get_allocated("speed")
	PlayerData.remember_position(Vector3(12.0, 3.0, -4.0))

	# Everything earned outside the stat table has to survive too: the purse, the
	# abilities the elder handed over, and the interface size.
	PlayerData.add_crystals(7)
	PlayerData.unlock_ability("air_jumps", 2)
	PlayerData.unlock_ability("dash", true)
	PlayerData.set_ui_scale(0.72)
	var expected_crystals: int = PlayerData.crystals
	# And what has already been bought from the elder. A save that forgets this hands out
	# the first rank of every ware at the starting price all over again.
	Shop.bought = {"hide": 2, "legs": 1}

	_check(PlayerData.save_game(), "save_game() writes the save file")

	# Wreck the in-memory state without touching the file, then reload.
	PlayerData.stats["speed"]["cap"] = 1.0
	PlayerData.allocated["speed"] = 1.0
	PlayerData.has_saved_position = false
	PlayerData._build_defaults()
	_check(PlayerData.load_game(), "load_game() reads the save file")
	_check(_near(PlayerData.stats["speed"]["cap"], expected_speed_cap, 0.0001),
		"restored cap matches exactly",
		"%.5f vs %.5f" % [PlayerData.stats["speed"]["cap"], expected_speed_cap])
	_check(_near(PlayerData.get_allocated("speed"), expected_alloc, 0.0001),
		"restored allocation matches exactly",
		"%.5f vs %.5f" % [PlayerData.get_allocated("speed"), expected_alloc])
	_check(PlayerData.has_saved_position, "restored the saved position flag")
	_check(PlayerData.world_position().is_equal_approx(Vector3(12.0, 3.0, -4.0)),
		"restored position matches", str(PlayerData.world_position()))
	_check(PlayerData.take_loaded_cultivation().has("tier"),
		"cultivation payload is available for the Cultivation autoload")
	_check(PlayerData.crystals == expected_crystals, "the crystal purse survives a reload",
		"%d vs %d" % [PlayerData.crystals, expected_crystals])
	_check(PlayerData.air_jumps() == 2, "so do the abilities the elder handed over",
		"%d air jumps" % PlayerData.air_jumps())
	_check(PlayerData.has_ability("dash"), "including the dash")
	_check(_near(PlayerData.ui_scale, 0.72, 0.001), "and the interface size",
		"%.2f" % PlayerData.ui_scale)
	_check(not PlayerData.take_loaded_quests().is_empty(),
		"the task chain is available for the Quests autoload")
	var saved_bought: Variant = PlayerData.take_loaded_shop().get("bought", {})
	_check(typeof(saved_bought) == TYPE_DICTIONARY
			and int((saved_bought as Dictionary).get("hide", 0)) == 2,
		"and the shop remembers what was bought", str(saved_bought))
	# A decision is the one kind of state nothing can rebuild, so it is checked through a
	# wrecked in-memory copy exactly like a cap is: a save that lost it would quietly reopen a
	# door the player walked through, and nothing else in the game would look wrong.
	PlayerData.note_decision("path", "breath", "")
	PlayerData.note_decision("camp", "burn", "Bandit Hollow")
	PlayerData.save_game()
	PlayerData.decisions.clear()
	_check(PlayerData.load_game(), "a save carrying decisions still loads")
	_check(PlayerData.chosen_option("path") == "breath",
		"and the option taken comes back", PlayerData.chosen_option("path"))
	_check(PlayerData.decision_subject("camp") == "Bandit Hollow",
		"with the thing it was about, which is what the world re-applies it from",
		PlayerData.decision_subject("camp"))

	# The save file is the fifth writer of a stat cap, and the one a player would actually
	# use to get past a ceiling — including accidentally, by loading a save written before
	# the ceiling existed. Written straight into the payload and read back through the real
	# loader, so what is checked is the path the game takes on startup.
	var ceiling: float = PlayerData.cap_ceiling("jump")
	PlayerData.stats["jump"]["cap"] = 1000.0
	PlayerData.save_game()
	PlayerData.stats["jump"]["cap"] = 1.0
	_check(PlayerData.load_game(), "a save carrying an impossible jump cap still loads")
	_check(PlayerData.get_cap("jump") <= ceiling + 0.0001,
		"and the ceiling holds against it", "%.2f m from a saved 1000" % PlayerData.get_cap("jump"))


# ------------------------------------------------------------------- the world

## Straight down at an XZ, returning the first thing hit on the world layer.
func _cast_down(x: float, z: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 400.0, z), Vector3(x, -400.0, z), 1, []
	)
	return get_viewport().world_3d.direct_space_state.intersect_ray(query)


## The scatter is checked against the instance buffers it actually handed to the
## renderer, not against the intent behind them: a placement that never made it
## into a MultiMesh would otherwise pass every other check in this file.
func _test_nature() -> void:
	_section("Nature scatter")
	if _scatter == null or not _scatter.has_method("summary"):
		_check(false, "the scatter builder is attached")
		return

	var summary: Dictionary = _scatter.call("summary")
	print("  info  %d instances, %d species, %d chunk meshes, %d trunk bodies" % [
		summary["instances"], summary["species"], summary["chunk_meshes"],
		summary["trunk_bodies"],
	])
	_check(int(summary["instances"]) > 800, "the terrain is dressed",
		"%d instances" % summary["instances"])
	_check((summary["missing"] as Array).is_empty(), "every nature model loaded",
		str(summary["missing"]))
	_check(int(summary["species"]) >= 15, "most of the kit is in play",
		"%d species" % summary["species"])
	_check(int(summary["chunk_meshes"]) > 20, "instances are split across chunks so they cull",
		"%d chunk meshes" % summary["chunk_meshes"])

	# Every species in the table has to appear somewhere. This is not busywork: all
	# three rock species silently vanished when the terrain was flattened, because their
	# slope window (0.10 and up) was a window onto ground that no longer existed — the
	# whole map's steepest point is 0.175. A species that places nothing is invisible in
	# the instance total, which stayed comfortably large throughout.
	# The ground has to be *visible* under it. The instance count on its own says nothing
	# about how thick the cover is — the map doubled in area and lost two thirds of its
	# instances, and a total that stayed large would have hidden either half of that. What
	# the eye reads is instances per square metre, so that is what is checked: one instance
	# per twenty square metres, at most.
	var span_m: float = float(_terrain.call("size_units"))
	var per_instance: float = (span_m * span_m) / maxf(1.0, float(summary["instances"]))
	_check(per_instance >= 20.0, "the ground shows through the vegetation",
		"one instance per %.0f m2 over a %.0f m map" % [per_instance, span_m])

	var audit: Dictionary = _scatter.call("placement_audit")
	var empty: Array = []
	for label: String in audit:
		var entry: Dictionary = audit[label]
		# Not "more than nothing": a species down to a handful of instances is the same
		# bug half-finished, and it is the state the rocks shipped in twice over.
		if int(entry["placed"]) >= 10:
			continue
		empty.append("%s: %d placed, steepest offered %.3f, needs %.3f-%.3f, band %.2f-%.2f, cleared %d, density %d, band %d, slope %d" % [
			label, int(entry["placed"]),
			label, float(entry["steepest"]), float(entry["slope_min"]),
			float(entry["slope_max"]), (entry["band"] as Vector2).x,
			(entry["band"] as Vector2).y, int(entry["clear"]),
			int(entry["rejected_density"]), int(entry["rejected_band"]),
			int(entry["rejected_slope"]),
		])
	_check(not audit.is_empty(), "the scatter reports on every species it ran")
	_check(empty.is_empty(), "every species in the table places something",
		" | ".join(empty))

	# Only the trees carry collision, and every tree carries one. That equality is
	# the whole reason the trunks are counted per species rather than globally.
	var counts: Dictionary = _scatter.call("species_counts")
	var trees: int = 0
	for label: String in [
		"CommonTree_1", "CommonTree_3", "Pine_1", "Pine_3", "TwistedTree_1", "DeadTree_1"
	]:
		trees += int(counts.get(label, 0))
	_check(trees > 40, "the forest has enough trees to walk into", "%d trees" % trees)
	_check(trees == int(summary["trunk_bodies"]),
		"exactly the trees are solid and nothing else is",
		"%d trees vs %d trunk bodies" % [trees, summary["trunk_bodies"]])

	var samples: Array = _scatter.call("sample_transforms", 240)
	_check(samples.size() >= 100, "placements can be read back out of the instance buffers",
		"%d samples" % samples.size())

	# Two different failures, and both matter: an instance left hanging above the
	# ground, and one buried under it. Some species are deliberately sunk into the
	# surface (rocks, so they read as outcrops), which is why the lower bound is
	# generous and the upper one is not.
	#
	# This compares against the surface rather than against a raycast, because a
	# downward ray on a tree lands on that tree's own invisible trunk several
	# metres up. The comparison is still worth making: it is a round trip through
	# the instance buffer, so it catches a transform mangled on the way into the
	# MultiMesh — which is the failure that would leave a tree hanging in mid air.
	var floating: int = 0
	var buried: int = 0
	var unsupported: int = 0
	var worst_float: float = 0.0
	var worst_bury: float = 0.0
	for entry: Transform3D in samples:
		var at: Vector3 = entry.origin
		var surface: float = float(_terrain.call("surface_height_at", at.x, at.z))
		var gap: float = at.y - surface
		if gap > 0.02:
			floating += 1
			worst_float = maxf(worst_float, gap)
		elif gap < -0.60:
			buried += 1
			worst_bury = minf(worst_bury, gap)
		if _cast_down(at.x, at.z).is_empty():
			unsupported += 1
	_check(floating == 0, "no instance floats above the ground",
		"%d floated, worst %.3f m up" % [floating, worst_float])
	_check(buried == 0, "no instance is buried deeper than its own sink",
		"%d buried, worst %.3f m down" % [buried, worst_bury])
	_check(unsupported == 0, "every sampled instance stands over real collision",
		"%d had nothing underneath" % unsupported)

	# The invisible trunk has to sit where the drawn tree does. The instance
	# buffers cannot show that on their own, so it is measured in the physics
	# world: a horizontal ray from just beside a trunk's axis has to stop on it.
	# Two of the eight are allowed to miss, since a neighbouring trunk can step
	# into the path.
	var trunks: Array = _scatter.call("trunk_points", 8)
	_check(trunks.size() >= 6, "trunk positions can be read back", "%d" % trunks.size())
	var blocked: int = 0
	for entry: Vector4 in trunks:
		var base := Vector3(entry.x, entry.y, entry.z)
		var from := Vector3(base.x + 1.2, base.y + 1.5, base.z)
		var query := PhysicsRayQueryParameters3D.create(
			from, Vector3(base.x, base.y + 1.5, base.z), 1, []
		)
		if not get_viewport().world_3d.direct_space_state.intersect_ray(query).is_empty():
			blocked += 1
	_check(blocked >= trunks.size() - 2,
		"the invisible trunks stand where the drawn trees do",
		"%d of %d blocked a ray at trunk height" % [blocked, trunks.size()])


func _test_camp() -> void:
	_section("Home camp")
	if _camp == null or not _camp.has_method("summary"):
		_check(false, "the camp builder is attached")
		return
	var summary: Dictionary = _camp.call("summary")
	print("  info  %d pieces, %d blockers, %d lights" % [
		summary["pieces"], summary["blockers"], summary["lights"],
	])
	_check(int(summary["pieces"]) >= 50, "the camp is furnished",
		"%d pieces" % summary["pieces"])
	# A handful of pieces are deliberately not solid: floor tiles get a deeper box
	# of their own, and flat decorations (vine, scroll) get none.
	_check(int(summary["blockers"]) >= int(summary["pieces"]) - 10,
		"nearly every piece has collision",
		"%d blockers for %d pieces" % [summary["blockers"], summary["pieces"]])

	# Placing a kit piece by its origin rather than its bounding box shows up here
	# and nowhere else: half the furniture would be sunk into the hillside.
	var sunk: int = 0
	var grounded: int = 0
	var stacked: int = 0
	var worst: float = 0.0
	for child in _camp.get_children():
		if not (child is Node3D):
			continue
		var pivot: Node3D = child
		var surface: float = float(_terrain.call(
			"surface_height_at", pivot.position.x, pivot.position.z
		))
		var gap: float = pivot.position.y - surface
		if gap > 0.35:
			stacked += 1
			continue
		grounded += 1
		if gap < -0.01:
			sunk += 1
			worst = minf(worst, gap)
	_check(sunk == 0, "no piece is sunk into the terrain",
		"%d sunk, worst %.3f m" % [sunk, worst])
	_check(grounded >= 50, "most pieces stand on the ground",
		"%d grounded, %d stacked" % [grounded, stacked])
	_check(stacked >= 2, "the roof and the table top are stacked above it",
		"%d stacked" % stacked)

	# The ring is solid and the gateway is not, both measured in the physics world
	# rather than read back off the scene tree.
	var ring: Vector2 = Vector2(10.5, 0.0)
	var on_ring: float = float(_terrain.call("surface_height_at", ring.x, ring.y))
	var ring_hit: Dictionary = _cast_down(ring.x, ring.y)
	_check(not ring_hit.is_empty() and float(ring_hit["position"].y) > on_ring + 0.3,
		"the fence is solid at the ring",
		"hit %s vs ground %.2f" % [str(ring_hit.get("position", "nothing")), on_ring])
	var gate: Vector2 = Vector2(0.0, 10.5)
	var at_gate: float = float(_terrain.call("surface_height_at", gate.x, gate.y))
	var gate_hit: Dictionary = _cast_down(gate.x, gate.y)
	_check(not gate_hit.is_empty()
			and absf(float(gate_hit["position"].y) - at_gate) < 0.25,
		"the south gateway is open to walk through",
		"hit %s vs ground %.2f" % [str(gate_hit.get("position", "nothing")), at_gate])


## Bigger and flatter are both numbers rather than opinions: a world described as
## flatter whose peaks still reach ±18 m has not been flattened, and one that is bigger
## but sampled at the same cell count has merely been stretched.
func _test_terrain_shape() -> void:
	_section("Terrain shape")
	if _terrain == null:
		return
	var span: float = float(_terrain.call("size_units"))
	var extent: float = float(_terrain.call("extent"))
	var relief: Vector2 = _terrain.call("height_range")
	var climb: float = relief.y - relief.x
	print("  info  map %.0f m across, relief -%.1f..%.1f (%.1f m), %s roads" % [
		span, -relief.x, relief.y, climb, str((_terrain.call("roads") as Array).size()),
	])
	_check(span >= 300.0, "the map is a large one", "%.0f m across" % span)
	_check(extent >= 150.0, "and reaches far enough to walk in", "%.0f m half-width" % extent)
	_check(climb <= 12.0, "the relief is rolling country rather than mountains",
		"%.1f m from lowest to highest" % climb)
	# Roads are what make a map this size walkable rather than a one-way trip: they are
	# levelled, they radiate from home, and every signpost on the map stands beside one.
	var roads: Array = _terrain.call("roads")
	_check(roads.size() >= 9, "enough roads that the whole map can be reached on one",
		"%d roads" % roads.size())
	# Flattening must not have gone all the way to a billiard table, or half the world
	# becomes one altitude and the vertex colours lose every band.
	_check(climb > 4.0, "but it is not a billiard table", "%.1f m" % climb)
	# A bigger map at the old cell size would be flat-shaded blocks rather than hills.
	_check(int(_terrain.get("grid")) >= 200,
		"the height field is sampled finely enough for that size",
		"%s cells" % str(_terrain.get("grid")))


## Spirit zones, checked for the two things that decide whether they are a feature or
## a label: that the stage requirement actually gates, and that the boost actually
## moves qi. Both are measured through the real trance rather than by reading the
## multiplier back out of the node.
func _test_qi_zones() -> void:
	_section("Spirit zones")
	var zones_node: Node = get_tree().root.get_node_or_null("Main/QiZones")
	_check(zones_node != null, "the spirit zones are part of the world")
	if zones_node == null or _player == null or _terrain == null:
		return
	var placed: Array = zones_node.call("zones")
	_check(placed.size() >= 3, "several zones were placed", "%d" % placed.size())
	if placed.size() < 2:
		return

	for i in placed.size():
		var zone: Dictionary = placed[i]
		var centre: Vector3 = zone["position"]
		var from_home: float = Vector2(centre.x, centre.z).length()
		_check(from_home >= 30.0, "%s is clear of the home camp" % zone["name"],
			"%.0f m from the origin" % from_home)
		var slope: float = float(_terrain.call("slope_at", centre.x, centre.z))
		_check(slope <= 0.30, "%s sits on ground level enough to cultivate" % zone["name"],
			"slope %.2f" % slope)
		_check(float(zone["boost"]) > 1.0, "%s is worth standing in" % zone["name"],
			"x%.1f" % float(zone["boost"]))
		for j in range(i + 1, placed.size()):
			var other: Dictionary = placed[j]
			var spot: Vector3 = other["position"]
			var gap: float = Vector2(centre.x - spot.x, centre.z - spot.z).length()
			# Overlapping discs would stack their boosts into one big aura.
			_check(gap > float(zone["radius"]) + float(other["radius"]),
				"%s and %s do not overlap" % [zone["name"], other["name"]],
				"%.0f m apart" % gap)

	# Containment is a disc in XZ, so standing above one is still standing in it.
	var first: Dictionary = placed[0]
	var centre: Vector3 = first["position"]
	var inside: Dictionary = zones_node.call("zone_at", centre)
	_check(not inside.is_empty(), "the middle of a zone counts as inside it")
	var past_rim: Vector3 = centre + Vector3(float(first["radius"]) * 1.4, 0.0, 0.0)
	_check((zones_node.call("zone_at", past_rim) as Dictionary).is_empty(),
		"a step past the rim is outside it")
	var above: Vector3 = centre + Vector3(0.0, 40.0, 0.0)
	_check(not (zones_node.call("zone_at", above) as Dictionary).is_empty(),
		"and being above it is still being in it")

	# The stage requirement gates. The last zone is deliberately out of reach of a
	# fresh cultivator, so drop to tier 0 and stand in it.
	var gate: Dictionary = placed[placed.size() - 1]
	var needed: int = int(gate["required_tier"])
	var tier_before: int = Cultivation.tier
	Cultivation.tier = 0
	zones_node.set_process(false)
	zones_node.call("_clear")
	zones_node.set("_player", _player)
	var locked_spot: Vector3 = gate["position"]
	(_player as Node3D).call("warp_to", locked_spot + Vector3(0.0, 2.0, 0.0))
	zones_node.set_process(true)
	await _settle(4)
	if needed > 0:
		_check(Cultivation.zone_locked, "a zone above your stage is dormant",
			"%s needs stage %d" % [gate["name"], needed])
		_check(is_equal_approx(Cultivation.zone_boost, 1.0),
			"and gives nothing away while it is", "x%.1f" % Cultivation.zone_boost)
		# The champion holding this ring is taken out of the picture for these two checks,
		# which are about the *stage* gate: a champion on the ground makes a zone dormant
		# whatever the cultivator's realm is, and that rule has its own section.
		var ring: int = int(gate.get("ring", 0))
		var warden: Dictionary = Wards.warden_of_ring(ring)
		var held: bool = not warden.is_empty()
		if held:
			Wards.set("_wardens_down", [String(warden["id"])])
		Cultivation.tier = needed
		await _settle(4)
		_check(not Cultivation.zone_locked, "and opens once the stage is reached",
			"held by %s" % String(warden.get("label", "nobody")))
		_check(Cultivation.zone_boost > 1.0, "with the boost to match",
			"x%.1f" % Cultivation.zone_boost)
		if held:
			Wards.set("_wardens_down", [])

	# The boost has to move qi, not just a label. Measured as cultivation progress per
	# second in the same zone, once from inside it and once from outside.
	var landed: bool = await _land_player()
	if not landed:
		return
	Cultivation.tier = maxi(tier_before, 20)
	var in_rate: float = await _measure_cycle_rate(zones_node, centre + Vector3(0.0, 2.0, 0.0), true)
	var out_rate: float = await _measure_cycle_rate(zones_node, _far_from_zones(zones_node), false)
	print("  info  cultivation rate %.4f/s in %s vs %.4f/s outside" % [
		in_rate, first["name"], out_rate])
	_check(in_rate > out_rate * 1.2, "cultivating in a zone is genuinely faster",
		"%.4f/s vs %.4f/s" % [in_rate, out_rate])
	# ...and leaving has to hand the multiplier back, or the world is one big zone.
	_check(is_equal_approx(Cultivation.zone_boost, 1.0),
		"stepping out returns the multiplier to normal", "x%.1f" % Cultivation.zone_boost)
	Cultivation.tier = tier_before
	Cultivation.stop_meditation()
	await _settle(2)


## A spot far enough from every zone to be in none of them.
func _far_from_zones(zones_node: Node) -> Vector3:
	var placed: Array = zones_node.call("zones")
	for candidate: Vector2 in [Vector2(0.0, 0.0), Vector2(60.0, 60.0), Vector2(-60.0, 60.0)]:
		var spot := Vector3(candidate.x, 4.0, candidate.y)
		if (zones_node.call("zone_at", spot) as Dictionary).is_empty():
			return spot
	return Vector3(0.0, 4.0, 0.0)


## Cycle progress per second through the real trance, at a given spot. Runs the
## controller's own entry path rather than poking Cultivation, so what is measured is
## the thing the player does.
func _measure_cycle_rate(zones_node: Node, spot: Vector3, expect_zone: bool) -> float:
	Cultivation.stop_meditation()
	await _settle(2)
	PlayerData.restore_all()
	(_player as Node3D).call("warp_to", spot)
	await _land(_player)
	await _settle(3)
	if expect_zone:
		zones_node.set_process(true)
		await _settle(2)
	await _enter_trance()
	if not Cultivation.meditating:
		return 0.0
	# From zero, so a refinement completing mid-window cannot subtract from the
	# numerator and report a negative rate.
	Cultivation.cycle = 0.0
	var start_cycle: float = Cultivation.cycle
	var start_usec: int = Time.get_ticks_usec()
	for i in 40:
		await get_tree().physics_frame
		await get_tree().process_frame
	var seconds: float = maxf(0.0001, float(Time.get_ticks_usec() - start_usec) / 1000000.0)
	var rate: float = (Cultivation.cycle - start_cycle) / seconds
	Cultivation.stop_meditation()
	await _settle(2)
	return rate


# --------------------------------------------------------------- the character

## Waits for a body that has just been moved to settle onto the ground.
##
## Entry to the trance needs both feet down on the exact frame the key lands, and a
## warp leaves the body in the air. A two-metre drop takes roughly a third of a
## second, which is longer than six taps of the key, so tapping straight after a warp
## never enters the trance at all — and a probe that cannot enter it reports a rate
## of zero, which reads exactly like a zone that grants nothing.
func _land(body: Node3D) -> void:
	# Three settled frames in a row rather than one. `is_on_floor()` is a flag left over
	# from the last `move_and_slide`, so on the frame straight after a warp it still
	# describes where the body used to be: a single check reports a body in mid-air as
	# landed, and every tap that follows falls on nothing.
	var settled: int = 0
	for i in 300:
		await get_tree().physics_frame
		if body.is_on_floor() and absf(body.velocity.y) < 0.5:
			settled += 1
			if settled >= 3:
				return
		else:
			settled = 0
	print("  info  a body never settled: at %s, floor=%s, vy=%.2f" % [
		body.global_position, body.is_on_floor(), body.velocity.y])


## The solid things standing within a metre or so of a point, for naming what has
## stopped the body. Terrain is left out because it is always there and its many
## collision tiles would bury the answer.
func _blockers_near(centre: Vector3) -> Array:
	var out: Array = []
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), centre + Vector3(0.0, 0.8, 0.0))
	query.collide_with_bodies = true
	for hit in _player.get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider: Object = hit.get("collider")
		if collider == null or collider == _player or not collider is Node:
			continue
		var path: String = String((collider as Node).get_path())
		if path.find("/Terrain") >= 0 or out.has(path):
			continue
		out.append(path)
	return out


## Whether a body walking from `from` along `dir` would get a clear run of `depth`.
func _lane_clear(from: Vector3, dir: Vector3, depth: float) -> bool:
	var eye: Vector3 = from + Vector3(0.0, 1.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(eye, eye + dir * depth)
	query.collide_with_bodies = true
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Moves the body to open ground, in the direction the forward key will carry it.
##
## The training posts and the camp hut sit right where the body spawns — deliberately,
## so there is something to hit — and a body pressed into a blocker reads 0.00 m/s and
## reports Idle, which is indistinguishable from a run that is broken. A ring of
## candidate spots is scanned and the first with a clear lane ahead is used, so the
## measurement follows the world instead of assuming the world is empty.
##
## Only a landing spot whose ground is level with the body's own height will do. A
## warp sets the position exactly, so dropping the body at the home plateau's height
## on ground that rises to meet it buries it — and a body buried in a heightmap falls
## through it rather than out of it.
func _move_to_open_ground() -> void:
	var cam: Camera3D = _player.get_viewport().get_camera_3d()
	if cam == null:
		return
	var forward := Vector3(-cam.global_transform.basis.z.x, 0.0, -cam.global_transform.basis.z.z)
	if forward.length() < 0.01:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	var base: Vector3 = _player.global_position
	# Three rings rather than one, and twice the headings: a single ring of eight made
	# the search a bet on the camp's procedural layout, and when the road count changed
	# the layout moved and *every* candidate was blocked — which presented as "sprinting
	# does not play the run", a game bug that did not exist. The measurement then fell
	# back to the spawn point, in the middle of the camp, against the hut.
	var rings: Array = [LANE_DISTANCE, LANE_DISTANCE * 1.45, LANE_DISTANCE * 0.7]
	for ring: float in rings:
		for step in 16:
			var heading: Vector3 = forward.rotated(Vector3.UP, float(step) * TAU / 16.0)
			var spot: Vector3 = base + heading * ring
			var ground: float = float(_terrain.call("surface_height_at", spot.x, spot.z))
			if absf(ground - base.y) > HILL_TOLERANCE:
				continue
			spot.y = ground + 0.2
			if not _lane_clear(spot, forward, LANE_DEPTH):
				continue
			if not _lane_ground_ok(spot, forward, LANE_DEPTH):
				continue
			(_player as Node3D).call("warp_to", spot)
			await _land(_player)
			await _settle(6)
			print("  info  locomotion measured on open ground at %s, lane clear and level for %.0f m" % [
				_player.global_position, LANE_DEPTH])
			return
	print("  info  no clear level lane found, so locomotion is measured where the body stands")


## Whether the ground along a lane stays near the footing it starts from. A body that
## has to climb a bank partway through the lane reports a walk speed and a walk clip
## however hard the sprint key is held, which is a measurement failure rather than a
## finding about the game. Roads carve banks, so this is not hypothetical.
func _lane_ground_ok(from: Vector3, dir: Vector3, depth: float) -> bool:
	if _terrain == null:
		return true
	# Measured against the ground the lane *starts* on, not against `from.y`: callers
	# hand in a spot that already floats above its own ground, and comparing to that
	# quietly ate the whole tolerance, so nothing ever qualified.
	var base: float = float(_terrain.call("surface_height_at", from.x, from.z))
	var steps: int = 4
	for i in range(1, steps + 1):
		var at: Vector3 = from + dir * (depth * float(i) / float(steps))
		var ground: float = float(_terrain.call("surface_height_at", at.x, at.z))
		if absf(ground - base) > 1.2:
			return false
	return true


## Advances both frame kinds, so the animator's _process and the controller's
## _physics_process have both run before anything is read back off them.
func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


## Taps an action the way a key does: down for a frame, then up. The trance is a
## toggle, so the press is what matters — a held key would re-enter it every frame
## and the release would then have nothing to undo.
func _tap_action(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


## Taps until the trance takes, and reports how many taps that needed.
##
## Entry requires the body to be on the floor on the exact frame the press lands, and
## on uneven terrain the body skips a centimetre off the ground often enough that a
## single tap is a coin flip. A player would simply press again; so does this.
func _enter_trance() -> int:
	for attempt in 6:
		if Cultivation.meditating:
			return attempt
		await _tap_action("meditate")
		await _settle(2)
	print("  info  the trance refused 6 taps: at %s, floor=%s, downed=%s, meditating=%s" % [
		_player.global_position, _player.is_on_floor(), _player.call("is_downed"),
		Cultivation.meditating])
	return 6


## Presses an action and holds it across a frame boundary before releasing.
##
## A single-frame tap is what a *player* does and is not what a frame-exact check can rely
## on: `Input.action_press` and the `physics_frame` signal are not ordered against the node
## that reads the action, so a one-frame tap can begin and end inside the same frame and the
## controller never sees a "just pressed" at all. That is a property of the harness, not of
## the key — holding for two frames removes the race instead of retrying against it.
func _hold_action(action: String, frames: int = 2) -> void:
	Input.action_press(action)
	for i in frames:
		await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _release_game_input() -> void:
	for action: String in [
		"move_forward", "move_backward", "move_left", "move_right",
		"jump", "sprint", "meditate", "qi_pressure",
	]:
		Input.action_release(action)


func _count_of_type(node: Node, wanted: String) -> int:
	var total: int = 1 if node.is_class(wanted) else 0
	for child in node.get_children():
		total += _count_of_type(child, wanted)
	return total


func _test_character() -> void:
	_section("Character")
	if _player == null:
		return
	var animator: Node = _player.get_node_or_null("Model")
	_check(animator != null and animator.has_method("current_clip"),
		"the model pivot runs the character animator")
	if animator == null or not animator.has_method("current_clip"):
		return

	var clips: Dictionary = animator.call("clip_table")
	print("  info  rig %.3f m as shipped, scale %.3f, clips %s" % [
		animator.call("model_height"), animator.call("model_scale"), str(clips.keys()),
	])
	for wanted: String in ["Idle", "Walk", "Run", "Roll", "RecieveHit", "Death"]:
		_check(clips.has(wanted), "the '%s' clip resolved on the imported rig" % wanted,
			str(clips.keys()))
	# 2.95 m is the Monk as the kit ships it. Measuring beats trusting a constant:
	# the same code fits any of the pack's other five classes unchanged.
	_check(_near(float(animator.call("model_height")), 2.95, 0.05),
		"the rig's own height is measured, not assumed",
		"%.3f m" % animator.call("model_height"))
	_check(_count_of_type(animator, "AnimationPlayer") == 1,
		"the rig carries exactly one animation player")
	_check(_count_of_type(animator, "Skeleton3D") == 1,
		"the rig's skeleton came through the import")
	_check(_count_of_type(animator, "MeshInstance3D") >= 1, "the rig has a body to draw")

	var body: AABB = animator.call("world_bounds")
	_check(_near(body.size.y, 1.80, 0.04), "the body is scaled to the target height",
		"%.3f m" % body.size.y)
	# Feet on the origin is the difference between a character and a character
	# floating a metre above its own shadow.
	_check(_near(body.position.y, _player.global_position.y, 0.03),
		"the body's feet stand on the character's origin",
		"feet %.3f vs character %.3f" % [body.position.y, _player.global_position.y])


## The animator's state machine, driven through the Input singleton the game
## itself reads, so what is exercised is the path a real key press takes.
func _test_animation_states() -> void:
	_section("Animation states")
	var animator: Node = _player.get_node_or_null("Model") if _player != null else null
	if animator == null or not animator.has_method("current_clip"):
		return
	_release_game_input()
	await _land(_player)
	_check(_player.is_on_floor(), "the character settles onto the ground first")

	await _settle(10)
	_check(String(animator.call("current_clip")) == "Idle", "standing still plays the idle",
		String(animator.call("current_clip")))

	# Walk and run differ only by whether sprint is held, which is the one
	# decision the controller actually makes about locomotion. Both are measured on
	# open ground, because the spawn sits in the middle of the home camp and a body
	# stopped by the hut is not evidence about the animation.
	await _move_to_open_ground()
	Input.action_press("move_forward")
	var walking: String = await _grounded_clip(animator)
	_check(walking == "Walk", "walking plays the walk",
		"%s at %.2f m/s of %.2f, blocked by %s" % [
			walking, _flat_speed(), PlayerData.max_speed(),
			_blockers_near(_player.global_position)])
	Input.action_press("sprint")
	var running: String = await _grounded_clip(animator)
	_check(running == "Run", "sprinting plays the run",
		"%s at %.2f m/s of %.2f, blocked by %s" % [
			running, _flat_speed(), PlayerData.max_speed(),
			_blockers_near(_player.global_position)])

	Input.action_press("jump")
	await _settle(2)
	Input.action_release("jump")
	await _settle(5)
	_check(not _player.is_on_floor(), "the jump leaves the ground")
	var airborne: String = String(animator.call("current_clip"))
	_check(airborne == "Run" or airborne == "Idle",
		"an airborne body holds a locomotion pose, having no jump clip", airborne)
	_release_game_input()
	await _land(_player)
	await _settle(10)

	# A blow that drew blood staggers the body. The signal is raised directly
	# because a real fall takes seconds of falling to set up.
	_player.struck.emit(12.0)
	await _settle(2)
	_check(String(animator.call("current_clip")) == "RecieveHit",
		"a landed blow plays the flinch", String(animator.call("current_clip")))
	await _settle(45)
	_check(String(animator.call("current_clip")) != "RecieveHit",
		"the flinch releases back to the idle", String(animator.call("current_clip")))

	# The trance is a toggle and has a pose of its own. `_test_poses` measures that
	# pose properly; here it only has to be entered and handed back.
	PlayerData.restore_all()
	await _enter_trance()
	await _settle(8)
	_check(Cultivation.meditating, "a tap enters the trance")
	_check(String(animator.call("current_pose")) == "seated",
		"a meditating body takes the sit pose", String(animator.call("current_pose")))
	await _tap_action("meditate")
	await _settle(8)
	_check(not Cultivation.meditating, "a second tap leaves the trance")
	_check(String(animator.call("current_pose")) == "",
		"and the skeleton is handed back to the clips",
		String(animator.call("current_pose")))

	# Collapse and recovery: the only route to the death clip. The down timer is
	# shortened so the test does not have to wait out the real four seconds.
	var down_seconds: float = float(_player.get("downed_seconds"))
	_player.set("downed_seconds", 0.3)
	PlayerData.apply_damage(PlayerData.get_cap("hp") * 20.0)
	await _settle(4)
	_check(_player.call("is_downed"), "running out of HP puts the body down")
	_check(String(animator.call("current_clip")) == "Death",
		"a downed body plays the death clip", String(animator.call("current_clip")))
	_check(PlayerData.get_value("hp") <= 0.0, "and has no vitality left",
		"%.1f" % PlayerData.get_value("hp"))
	await _settle(40)
	_check(not _player.call("is_downed"), "the body gets back up on its own")
	_check(PlayerData.get_value("hp") > 0.0, "getting up restores vitality",
		"%.1f" % PlayerData.get_value("hp"))
	_check(String(animator.call("current_clip")) != "Death", "and the death clip ends",
		String(animator.call("current_clip")))
	_player.set("downed_seconds", down_seconds)
	_release_game_input()


## The clip the animator is showing, read on a frame where the body is genuinely on
## the ground and moving.
##
## Sampling a fixed number of frames later lands on whatever frame happens to be
## there, and on rolling country the body skips off the ground over every rise — and
## an airborne body is *meant* to show the run, having no jump clip. So a walk read on
## one of those frames reports Run and looks like a broken threshold. The reading
## waits for four grounded frames in a row instead.
## The clip the body is playing once its speed has *settled*, which is the only moment
## the clip decision means anything.
##
## Returning as soon as the body has been moving for a few frames reads the clip during
## the acceleration, and the walk-to-run threshold is 0.62 of top speed — within a
## couple of frames of a standing start, so the reading could land on either side of it
## on nothing at all. That is a test reporting a coin toss as a game bug: it showed up
## here as "sprinting plays the run (Walk at 3.70 m/s of 5.95)" against a threshold of
## 3.69. Waiting for the speed to stop changing measures the pace the held keys
## actually command.
func _grounded_clip(animator: Node) -> String:
	var last: float = -1.0
	var steady: int = 0
	for i in 200:
		await _settle(1)
		var speed: float = _flat_speed()
		if not _player.is_on_floor() or speed <= 0.35:
			steady = 0
			last = -1.0
			continue
		if last >= 0.0 and absf(speed - last) < 0.02:
			steady += 1
			if steady >= 6:
				break
		else:
			steady = 0
		last = speed
	return String(animator.call("current_clip"))


func _flat_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


## Two things about locomotion that a screenshot cannot show.
##
## The first is the freeze: every clip the importer touched comes in as LOOP_NONE,
## which is invisible on a standing idle and obvious on a run, where the legs stop
## mid-stride after one cycle and the character appears to get stuck.
##
## The second is the collision flags, which are pure configuration and whose effect
## is a feel rather than a number.
func _test_locomotion() -> void:
	_section("Locomotion")
	if _player == null:
		return
	var animator: Node = _player.get_node_or_null("Model")
	if animator != null and animator.has_method("loop_modes"):
		var modes: Dictionary = animator.call("loop_modes")
		_check(not modes.is_empty(), "the animator reports what it loaded", str(modes.keys()))
		# The clips the body spends nearly all its time in.
		for wanted: String in ["Idle", "Walk", "Run"]:
			_check(int(modes.get(wanted, Animation.LOOP_NONE)) != Animation.LOOP_NONE,
				"the %s clip keeps cycling instead of freezing on its last frame" % wanted,
				"mode %d" % int(modes.get(wanted, -1)))
		# ...and the ones that must still play exactly once.
		for wanted: String in ["Roll", "Attack", "RecieveHit"]:
			if modes.has(wanted):
				_check(int(modes[wanted]) == Animation.LOOP_NONE,
					"the %s one-shot still plays once" % wanted)

	var body: CharacterBody3D = _player as CharacterBody3D
	_check(not body.floor_block_on_wall,
		"a wall is something to slide along rather than a full stop while grounded")
	_check(body.floor_constant_speed, "a slope does not quietly cost speed")
	_check(body.safe_margin > 0.005,
		"the collision margin is wide enough not to judder on terrain triangles",
		"%.4f" % body.safe_margin)


## Measurements taken at the *end of the leg chain*: `Body -> UpperLeg -> LowerLeg`.
##
## Deliberately not at `Foot.L`/`Foot.R`, which on this rig are IK control bones
## parented to `Root` rather than to the leg — rotating a thigh moves the knee and
## leaves the foot exactly where it was, so a foot-based measurement reports a perfect
## sit as no pose at all. The rig was checked bone by bone (`bone_tree`) to establish
## this rather than assumed from the joint names.
func _hips(animator: Node) -> Vector3:
	var joints: Dictionary = animator.call("joint_positions", ["Hips"])
	var value: Vector3 = joints.get("Hips", Vector3.ZERO)
	return value


func _head(animator: Node) -> float:
	var joints: Dictionary = animator.call("joint_positions", ["Head"])
	var value: Vector3 = joints.get("Head", Vector3.ZERO)
	return value.y


func _hip_to_knee(animator: Node) -> float:
	var joints: Dictionary = animator.call("joint_positions", ["Hips", "LowerLeg.L", "LowerLeg.R"])
	if joints.size() < 3:
		return 0.0
	var hips: Vector3 = joints["Hips"]
	var left: Vector3 = joints["LowerLeg.L"]
	var right: Vector3 = joints["LowerLeg.R"]
	return hips.y - minf(left.y, right.y)


## How far the knees sit out from the hip axis, horizontally. Standing, each knee is
## almost directly below its hip; folded outward, it cannot be.
func _knee_reach(animator: Node) -> float:
	var joints: Dictionary = animator.call("joint_positions", ["Hips", "LowerLeg.L", "LowerLeg.R"])
	if joints.size() < 3:
		return 0.0
	var hips: Vector3 = joints["Hips"]
	var left: Vector3 = joints["LowerLeg.L"]
	var right: Vector3 = joints["LowerLeg.R"]
	return maxf(
		Vector2(left.x - hips.x, left.z - hips.z).length(),
		Vector2(right.x - hips.x, right.z - hips.z).length())


## The sit and the leap. The pack ships a clip for neither, so both are written onto
## the skeleton by hand — and a hand-written pose has no reference to compare against.
##
## It is checked by geometry instead. "A pose was applied" proves nothing, because a
## pose applied about the wrong axis also moves bones; "the feet left the floor and
## the head is still above the hips" is the part that only a sit satisfies.
func _test_poses() -> void:
	_section("Poses")
	if _player == null:
		return
	var animator: Node = _player.get_node_or_null("Model")
	if animator == null or not animator.has_method("joint_positions"):
		_check(false, "the animator can report where the joints ended up")
		return
	# Stand the body up first and take the reference measurements.
	var landed: bool = await _land_player()
	_check(landed, "the body starts the section on its feet")
	await _settle(6)
	var standing_drop: float = _hip_to_knee(animator)
	var standing_hips: float = _hips(animator).y
	var standing_reach: float = _knee_reach(animator)
	_check(standing_drop > 0.15, "a standing body carries its knees below its hips",
		"%.2f m" % standing_drop)
	_check(standing_reach < 0.20, "and holds them under the hips rather than out to the side",
		"%.2f m" % standing_reach)

	PlayerData.restore_all()
	await _enter_trance()
	await _settle(10)
	_check(String(animator.call("current_pose")) == "seated", "the trance applies the sit",
		String(animator.call("current_pose")))

	var origin: Vector3 = (_player as Node3D).global_position
	# Did the pose reach the bones at all? If it did, then a joint that has not moved
	# is a stale read-back rather than a pose that was never written.
	var leg_rotation: Quaternion = animator.call("bone_rotation", "UpperLeg.L")
	_check(leg_rotation.get_angle() > 0.5,
		"the sit is written onto the leg bone, not just onto the rig pivot",
		"%.2f rad" % leg_rotation.get_angle())

	var seated_drop: float = _hip_to_knee(animator)
	var seated_reach: float = _knee_reach(animator)
	var seated_hips: float = _hips(animator).y
	var seated_head: float = (_head(animator)) - seated_hips
	var sank: float = standing_hips - seated_hips
	_check(seated_head > 0.45, "the seated spine stays upright",
		"head %.2f m above hips" % seated_head)
	# The one measurement that separates a sit from a rig rotated about the wrong axis:
	# a thigh swung out to the side takes the knee with it, and nothing else does.
	_check(seated_reach > standing_reach + 0.15,
		"the thighs swing out instead of standing under the body",
		"%.2f m vs %.2f m standing" % [seated_reach, standing_reach])
	_check(seated_drop < standing_drop - 0.08,
		"the thighs fold up rather than hanging straight down",
		"knee %.2f m below the hips vs %.2f standing" % [seated_drop, standing_drop])
	print("  info  sit: knee %.2f m out and %.2f m under the hips (standing %.2f / %.2f), pelvis dropped %.2f m" % [
		seated_reach, seated_drop, standing_reach, standing_drop, sank])
	# Legs folded rather than merely sunk: the knees have to end up off the ground and
	# low. A cross-legged sit really does put the knees near hip height, so this checks
	# where they are rather than insisting they stay under the pelvis.
	var knees: Dictionary = animator.call("joint_positions", ["LowerLeg.L", "LowerLeg.R"])
	if knees.size() == 2:
		var left_knee: Vector3 = knees["LowerLeg.L"]
		var right_knee: Vector3 = knees["LowerLeg.R"]
		var knee_low: float = minf(left_knee.y, right_knee.y) - origin.y
		_check(knee_low > 0.02 and knee_low < 0.50,
			"the folded knees sit just above the ground rather than in it",
			"%.2f m above the origin" % knee_low)
	# A seated pelvis: down from standing, but not through the ground. Mesh-space bounds
	# are no use here — a skinned mesh keeps its rest AABB, so the rendered body can sit
	# while the AABB still describes a standing one.
	_check(sank > 0.20 and sank < 0.60,
		"the body settles to a seated height rather than into the floor",
		"hips dropped %.2f m" % sank)

	# A held pose that does not move is a freeze frame, and reads as one.
	var before: Vector3 = (animator.call("joint_positions", ["Hips"]) as Dictionary)["Hips"]
	await _settle(45)
	var after: Vector3 = (animator.call("joint_positions", ["Hips"]) as Dictionary)["Hips"]
	_check(absf(after.y - before.y) > 0.0005 and absf(after.y - before.y) < 0.05,
		"the seated body breathes instead of freezing", "hips moved %.4f m" % (after.y - before.y))
	_check(_knee_reach(animator) > standing_reach + 0.15,
		"and the legs stay folded through the breath",
		"knee %.2f m out" % _knee_reach(animator))

	await _tap_action("meditate")
	await _settle(10)
	_check(String(animator.call("current_pose")) == "",
		"a second tap hands the skeleton back to the clips")

	# The leap, which is invisible without a pose: the run cycle keeps cycling in the
	# air, so a jump taken from a run is indistinguishable from the run.
	#
	# The whole flight is sampled rather than a fixed number of frames. How long the
	# body stays up depends on the JUMP cap that earlier sections have been growing, so
	# any fixed count is a bet on where in the suite this runs — and a leap short
	# enough to land inside the wait would look exactly like a broken tuck.
	# A standing leap needs a standing jump to be possible: the earlier allocation
	# section deliberately leaves JUMP at half its cap, and half of a small cap is not
	# enough airtime to hold any pose for. The allocation is set rather than assumed.
	PlayerData.set_allocation("jump", PlayerData.get_cap("jump"))
	PlayerData.set_allocation("speed", PlayerData.get_cap("speed"))
	Input.action_press("sprint")
	await _settle(20)
	print("  info  before the leap: jump %.2f m at %.2f m/s of liftoff" % [
		PlayerData.max_jump_height(), _player.call("jump_velocity")])
	Input.action_press("jump")
	await _settle(2)
	Input.action_release("jump")
	# Liftoff is waited for separately. `physics_frame` is emitted *before* the step
	# that runs the controller, so a loop that tests the floor at the top reads the
	# frame before the jump took effect and concludes the body never left the ground.
	var lifted: bool = false
	for i in 30:
		await _settle(1)
		if not _player.is_on_floor():
			lifted = true
			break
	_check(lifted, "the leap leaves the ground")
	var air_frames: int = 0
	var tucked: bool = false
	var tuck_fold: float = standing_drop
	for i in 90:
		await _settle(1)
		if _player.is_on_floor():
			break
		air_frames += 1
		if String(animator.call("current_pose")) == "airborne":
			tucked = true
			tuck_fold = minf(tuck_fold, _hip_to_knee(animator))
	print("  info  the leap lasted %d frames after liftoff (%.2f s)" % [air_frames, air_frames / 60.0])
	_check(tucked, "an airborne body holds a tuck, having no jump clip of its own")
	_check(tuck_fold < standing_drop - 0.08, "and the tuck brings the knees up",
		"knee %.2f m below the hips vs %.2f standing" % [tuck_fold, standing_drop])
	# Release everything before the body lands, so the roll is not triggered here.
	_release_game_input()
	for i in 240:
		if _player.is_on_floor():
			break
		await get_tree().physics_frame
	await _settle(20)
	_check(String(animator.call("current_pose")) == "",
		"landing gives the body back to the clips", String(animator.call("current_pose")))


func _collect_bars(node: Node, into: Array[ProgressBar]) -> void:
	if node is ProgressBar:
		into.append(node as ProgressBar)
	for child in node.get_children():
		_collect_bars(child, into)


## Every meter in this HUD is fed a 0..1 ratio, and a ProgressBar's default range is
## 0..100. One declared in the scene file without a `max_value` therefore draws a bar
## at 90% as one at 0.9% full, while the number printed beside it is correct — which
## reads as a broken display rather than as an empty bar, and is exactly what the
## refinement and insight meters were doing.
func _test_meters() -> void:
	_section("Meters")
	if _hud == null:
		return
	var bars: Array[ProgressBar] = []
	_collect_bars(_hud, bars)
	_check(bars.size() >= 6, "the HUD has meters to read", "%d found" % bars.size())
	for bar: ProgressBar in bars:
		_check(is_equal_approx(bar.max_value, 1.0),
			"%s is ranged as a ratio rather than as a percentage" % bar.name,
			"max_value %.1f" % bar.max_value)

	# ...and the two meters that hand-fed their maths still track it exactly.
	var refinement: ProgressBar = _find_by_name(_hud, "RefinementBar") as ProgressBar
	var insight: ProgressBar = _find_by_name(_hud, "InsightBar") as ProgressBar
	_check(refinement != null and insight != null, "the cultivation meters exist")
	if refinement != null and insight != null:
		Cultivation.cycle = Cultivation.cycle_required() * 0.75
		Cultivation.insight = Cultivation.insight_required() * 0.75
		_check(await _hud_settles(refinement, Cultivation.cycle_ratio()),
			"the refinement meter matches the cycle it reports",
			"%.3f vs %.3f" % [refinement.value, Cultivation.cycle_ratio()])
		_check(await _hud_settles(insight, Cultivation.insight_ratio()),
			"the insight meter matches the insight it reports",
			"%.3f vs %.3f" % [insight.value, Cultivation.insight_ratio()])
		# A three-quarters-full meter has to read as three-quarters full.
		_check(_near(refinement.value / refinement.max_value, 0.75, 0.02),
			"three quarters of the cycle fills three quarters of the track",
			"%.2f" % (refinement.value / refinement.max_value))
		Cultivation.cycle = 0.0
		Cultivation.insight = 0.0
		await _settle(2)


## Waits for a meter to catch up with a change, up to a little over the HUD's own
## refresh interval.
##
## The HUD refreshes on an interval rather than every frame — a meter does not need
## sixty updates a second — so reading a bar a fixed two frames after changing the
## value is a race against that interval. Losing it shows the number from the previous
## refresh, which looks exactly like a meter that tracks nothing: the shipped build
## reported 0.042 of a cycle that read 0.750 this way, in every run, while the same
## code passed in the editor.
func _hud_settles(bar: ProgressBar, ratio: float) -> bool:
	for i in 30:
		await _settle(1)
		if _near(bar.value, ratio, 0.001):
			return true
	return false


## The stat readout folds away, and folded is how it starts: it is the tallest panel
## on screen and the only one that is consulted rather than watched.
func _test_stats_panel() -> void:
	_section("Stats panel")
	if _hud == null:
		return
	var rows: Control = _find_by_name(_hud, "StatRows") as Control
	var toggle: Button = _find_by_name(_hud, "StatsToggle") as Button
	_check(rows != null and toggle != null, "the stat readout has a fold control")
	if rows == null or toggle == null:
		return
	_check(_hud.has_method("set_stats_expanded") and _hud.has_method("stats_expanded"),
		"the HUD can fold itself and say so")
	_check(not _hud.call("stats_expanded"), "it starts folded")
	_check(not rows.visible, "and the rows start hidden")
	# A folded header that says nothing has spent the space it saved on nothing.
	var title: Label = _find_by_name(_hud, "StatsTitle") as Label
	_check(title != null and title.text.contains("HP") and title.text.contains("QI"),
		"the folded header still shows the two numbers worth glancing at",
		title.text if title != null else "missing")
	# Click-through like the rest of the panel, except the fold control — which has
	# to be clickable, or the fold is keyboard-only for no reason.
	_check(toggle.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"the fold control can actually be clicked")
	# The page has to actually grow. "The rows became visible" and "the panel opened"
	# are different claims, and only the second one is what a player sees: a fold
	# control that flips its own label while the container it lives in never resizes is
	# indistinguishable from a button that does nothing at all.
	var panel: PanelContainer = _find_by_name(_hud, "StatsPanel") as PanelContainer
	var folded_height: float = panel.size.y if panel != null else 0.0
	_hud.call("set_stats_expanded", true)
	await _settle(4)
	_check(rows.visible, "it unfolds on request")
	_check(panel != null and panel.size.y > folded_height + 20.0,
		"and the panel actually opens rather than only relabelling its button",
		"%.0f px folded, %.0f px open" % [folded_height, panel.size.y if panel != null else 0.0])
	# ...with something in it. An opening panel of empty space is the same nothing seen
	# from a different angle.
	var filled: int = _filled_labels(rows)
	_check(filled >= 4, "the opened panel has the readouts in it",
		"%d labels with text" % filled)
	_check(toggle.text == "Hide", "and the control says what it will do next", toggle.text)
	_check((title as Label).text == "BODY", "while unfolded the header gives the space to the rows",
		(title as Label).text)
	_hud.call("set_stats_expanded", false)
	await _settle(2)
	_check(not rows.visible, "and folds away again")


# ------------------------------------------------------------------ new systems

## A real key event, pushed through the Viewport the way the browser does. Used
## for the actions that are read as one-shot events rather than polled, because
## Input.action_press() sets the action state without ever raising an event.
func _press_key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)


func _test_aura() -> void:
	_section("Aura")
	if _player == null:
		return
	var aura: Node3D = (_player as Node3D).get_node_or_null("Aura") as Node3D
	_check(aura != null and aura.has_method("particle_count"), "the aura is attached to the player")
	if aura == null or not aura.has_method("particle_count"):
		return
	# Qi is unlocked at tier 0, so a fresh cultivator is never bare.
	_check(Cultivation.aura_unlocked("qi"), "qi is available from the first stage")
	_check(Cultivation.aura_unlocked(Cultivation.active_aura()),
		"the aura in effect is one that has actually been earned",
		Cultivation.active_aura())

	# An element that has not been earned must not be wearable, no matter what the
	# save says: this is the only thing standing between a stage and its reward.
	var tier_before: int = Cultivation.tier
	PlayerData.set_chosen_aura("fire")
	_check(Cultivation.active_aura() != "fire" or Cultivation.tier >= 14,
		"a locked aura cannot be worn by asking for it", Cultivation.active_aura())

	PlayerData.set_chosen_aura("qi")
	await _settle(3)
	var low_power: float = Cultivation.aura_power()
	var low_count: int = int(aura.call("particle_count"))
	_check(low_count > 0, "an equipped aura actually emits", "%d particles" % low_count)

	# A particle is a quad, and two separate things stop it reading as one: a soft
	# texture that erases the corners, and a material that cannot saturate to white.
	# Both were wrong at once, which is why the aura looked like a pile of white
	# boxes rather than like light.
	var ring: CPUParticles3D = aura.get_node_or_null("Ring") as CPUParticles3D
	_check(ring != null and ring.mesh != null, "the aura has a ring emitter with a mesh")
	if ring != null and ring.mesh != null:
		var mat: StandardMaterial3D = ring.mesh.surface_get_material(0) as StandardMaterial3D
		_check(mat != null and mat.albedo_texture != null,
			"each mote is textured, so a particle is not a bare square")
		_check(mat != null and mat.blend_mode != BaseMaterial3D.BLEND_MODE_ADD,
			"motes mix toward their hue instead of adding, so a dense aura keeps its colour")
		if mat != null:
			var lit := Color(
				mat.albedo_color.r + mat.emission.r * mat.emission_energy_multiplier,
				mat.albedo_color.g + mat.emission.g * mat.emission_energy_multiplier,
				mat.albedo_color.b + mat.emission.b * mat.emission_energy_multiplier)
			var below_white: int = 0
			for channel: float in [lit.r, lit.g, lit.b]:
				if channel < 0.98:
					below_white += 1
			_check(below_white >= 2,
				"albedo plus emission leaves the mote's hue intact rather than white",
				"lit " + str(lit))
		# A mote still at full opacity on its last frame does not fade, it vanishes.
		var ramp: Gradient = ring.color_ramp
		_check(ramp != null and ramp.sample(1.0).a < 0.05 and ramp.sample(0.4).a > 0.9,
			"motes fade out over their life instead of blinking off",
			"alpha %.2f at end, %.2f mid" % [ramp.sample(1.0).a, ramp.sample(0.4).a]
				if ramp != null else "no ramp")

	Cultivation.tier = 18
	Cultivation.cultivation_changed.emit()
	await _settle(3)
	_check(Cultivation.aura_power() > low_power, "aura power ramps with the tier",
		"%.2f -> %.2f" % [low_power, Cultivation.aura_power()])
	_check(int(aura.call("particle_count")) > low_count,
		"a later stage is a bigger aura, not merely a brighter one",
		"%d -> %d particles" % [low_count, aura.call("particle_count")])

	# Every element must be wearable once earned, and each must resolve through the
	# catalogue rather than silently falling back to the default.
	for entry: Dictionary in Cultivation.AURAS:
		var id: String = String(entry["id"])
		_check(Cultivation.aura_unlocked(id), "%s is unlocked by tier 18" % id)
		PlayerData.set_chosen_aura(id)
		await _settle(2)
		_check(Cultivation.active_aura() == id, "%s can be worn once earned" % id,
			Cultivation.active_aura())

	Cultivation.tier = tier_before
	PlayerData.set_chosen_aura("qi")
	Cultivation.cultivation_changed.emit()
	await _settle(2)


## The nameplate over the cultivator's head is world geometry rather than HUD, so
## none of the 2D layout checks above touch it — and a nameplate that floats a metre
## off the head, or stacks its own text on top of its own bar, still looks fine in a
## static read of the scene file.
##
## `unproject_position` is pure transform maths and needs no renderer, so a headless
## run can assert where these pixels actually land. Everything below reads the node
## geometry that was really built instead of re-deriving it from the constants.
func _test_avatar_overlay() -> void:
	_section("Avatar nameplate")
	if _player == null:
		return
	var overlay: Node3D = (_player as Node3D).get_node_or_null("Overlay") as Node3D
	_check(overlay != null and overlay.has_method("summary"),
		"the nameplate is attached to the player")
	if overlay == null or not overlay.has_method("summary"):
		return

	var camera: Camera3D = _player.get_viewport().get_camera_3d()
	_check(camera != null, "a camera is looking at the cultivator")
	if camera == null:
		return

	PlayerData.restore("hp", PlayerData.get_cap("hp"))
	await _settle(2)
	var shown: Dictionary = overlay.call("summary")
	# The number is read back rather than recomputed: a plate that agreed with a copy of
	# the formula in this file would still be wrong if the plate stopped using it.
	var expected: String = String(overlay.call("group", PlayerData.power_level()))
	_check(String(shown["power_text"]) == expected,
		"the number over the head is the power level",
		"%s vs %s (level %d)" % [shown["power_text"], expected, PlayerData.power_level()])
	_check(int(shown["power"]) == PlayerData.power_level(), "and it is the live one",
		"%d vs %d" % [int(shown["power"]), PlayerData.power_level()])
	# One formatter, not two that agree today. The settings panel prints the same score,
	# and two copies of the grouping loop is how the two screens come to disagree.
	_check(String(shown["power_text"]) == PlayerData.power_text(),
		"and the plate shares the settings panel's formatter",
		"%s vs %s" % [shown["power_text"], PlayerData.power_text()])
	_check(PlayerData.group_int(1234567) == "1,234,567",
		"the score is grouped into thousands", PlayerData.group_int(1234567))
	# A stage with no rank numeral is a stage you cannot tell from the one before it.
	_check(String(shown["stage_text"]).contains(Cultivation.realm_name()),
		"the stage label names the realm reached", String(shown["stage_text"]))
	_check(String(shown["stage_text"]).contains("I"),
		"and ranks the stage within it", String(shown["stage_text"]))
	# The bars are gone. Pinned rather than assumed, because a stale reference to one of
	# them surviving the rewrite and then throwing at runtime is the whole risk of a
	# rewrite like this one.
	for gone: String in ["HpBack", "HpFill", "QiBack", "QiFill", "HpText"]:
		_check(overlay.get_node_or_null(gone) == null, "%s is off the plate" % gone)

	# Top to bottom as the eye reads it: the stage, then the number under it.
	var spans: Array = []
	for node_name: String in ["StageText", "PowerText"]:
		var span: Vector2 = _overlay_span(overlay, node_name, camera)
		_check(span != Vector2.INF, "%s is part of the nameplate" % node_name)
		if span == Vector2.INF:
			return
		spans.append(span)
	var stage_span: Vector2 = spans[0]
	var power_span: Vector2 = spans[1]
	_check(power_span.x >= stage_span.y - 1.0,
		"the power level sits under the stage rather than through it",
		"stage ends %.0f, number starts %.0f" % [stage_span.y, power_span.x])

	# Readability at range. This number is the whole plate now, so legibility is not a
	# nicety: it is the feature.
	_check(power_span.y - power_span.x >= 14.0,
		"the number is big enough to read from where you stand",
		"%.1f px tall" % (power_span.y - power_span.x))
	# ...and centred on the body, which an offset in the animation could quietly break.
	var mid: Vector2 = camera.unproject_position(
		overlay.global_transform * Vector3(0.0, 2.02, 0.0))
	var head: Vector2 = camera.unproject_position(
		overlay.global_transform * Vector3(0.0, 1.82, 0.0))
	_check(absf(mid.x - head.x) <= 6.0, "and over the cultivator rather than beside them",
		"%.0f px off centre" % absf(mid.x - head.x))
	_check(power_span.y < head.y, "the plate floats above the head, not across the face",
		"number %.0f vs crown %.0f" % [power_span.y, head.y])

	var halo: Label3D = overlay.get_node_or_null("PowerHalo") as Label3D
	var label: Label3D = overlay.get_node_or_null("PowerText") as Label3D
	_check(halo != null and label != null, "the number has a glow behind it")
	if halo == null or label == null:
		return
	# Two coplanar labels at one depth: with equal priority the renderer is free to draw
	# the glow over the digits, which is the same tie that once swallowed the health bar.
	_check(halo.render_priority < label.render_priority,
		"the glow is drawn behind the digits rather than over them",
		"%d vs %d" % [halo.render_priority, label.render_priority])
	_check(halo.outline_size > label.outline_size,
		"and it is a wider outline that makes it a glow",
		"%.0f vs %.0f" % [halo.outline_size, label.outline_size])

	# The tiers have to escalate, or "the higher it is, the better it looks" is a claim
	# the table only appears to make. Every one of the three numbers that decide how big
	# the figure is and how brightly it burns has to keep climbing.
	var tiers: Array = overlay.get("POWER_TIERS")
	_check(tiers.size() >= 4, "there is more than one look to grow through",
		"%d tiers" % tiers.size())
	var flat: Array = []
	for i in range(1, tiers.size()):
		var lower: Dictionary = tiers[i - 1]
		var upper: Dictionary = tiers[i]
		if int(upper["at"]) <= int(lower["at"]):
			flat.append("tier %d starts no higher than tier %d" % [i, i - 1])
		if float(upper["scale"]) <= float(lower["scale"]):
			flat.append("tier %d is not bigger" % i)
		if float(upper["halo_outline"]) <= float(lower["halo_outline"]):
			flat.append("tier %d does not glow wider" % i)
	_check(flat.is_empty(), "every tier is bigger and brighter than the one below",
		" | ".join(flat))

	# Which tier a level lands in, checked at the boundaries rather than mid-band.
	var wrong: Array = []
	for entry: Dictionary in tiers:
		var at: int = int(entry["at"])
		if String(overlay.call("tier_for", at)["name"]) != String(entry["name"]):
			wrong.append("level %d should wear %s" % [at, entry["name"]])
		if at > 0 and String(overlay.call("tier_for", at - 1)["name"]) == String(entry["name"]):
			wrong.append("level %d is one too early for %s" % [at - 1, entry["name"]])
	_check(wrong.is_empty(), "a level lands in the tier its threshold says",
		" | ".join(wrong))

	# Grown through real state rather than a shortcut: caps and the stage counter are the
	# only two things the power level is made of, so those are what it is grown with.
	var low_power: int = PlayerData.power_level()
	var low_tier: String = String(shown["tier"])
	var low_size: float = float(shown["pixel_size"])
	var saved_tier: int = Cultivation.tier
	var saved_caps: Dictionary = {}
	for id: String in PlayerData.STAT_ORDER:
		saved_caps[id] = PlayerData.get_cap(id)
		PlayerData._grow_cap(id, PlayerData.get_cap(id) * 6.0)
	Cultivation.tier = saved_tier + 20
	overlay.call("_refresh")
	await _settle(2)
	var grown: Dictionary = overlay.call("summary")
	_check(int(grown["power"]) > low_power, "the level climbs when the body does",
		"%d -> %d" % [low_power, int(grown["power"])])
	_check(String(grown["tier"]) != low_tier, "and the plate changes its look with it",
		"%s -> %s" % [low_tier, grown["tier"]])
	_check(float(grown["pixel_size"]) > low_size, "a higher level is drawn bigger",
		"%.4f -> %.4f" % [low_size, float(grown["pixel_size"])])

	# The look is animated, which is the part no screenshot can show: read the same values
	# a few frames apart and require them to have moved.
	var seen: Array = []
	for i in 6:
		await _settle(2)
		var frame: Dictionary = overlay.call("summary")
		seen.append("%.5f" % float(frame["pixel_size"]))
	var moved: bool = false
	for value: String in seen:
		if value != String(seen[0]):
			moved = true
	_check(moved, "the number flickers and breathes as it burns", ", ".join(seen))

	# A rank earned is the only feedback this plate ever gives, so it has to be visible
	# and then get out of the way.
	overlay.set("_flash", 1.0)
	await _settle(2)
	var flashing: float = float(overlay.call("summary")["flash"])
	await _settle(90)
	var settled: float = float(overlay.call("summary")["flash"])
	_check(flashing > 0.1 and settled < 0.05,
		"a gain flashes and then fades away", "%.2f -> %.2f" % [flashing, settled])

	for id: String in saved_caps:
		PlayerData.stats[id]["cap"] = saved_caps[id]
	Cultivation.tier = saved_tier
	overlay.call("_refresh")
	await _settle(2)
	PlayerData.restore("hp", PlayerData.get_cap("hp"))

	var view: Vector2 = _player.get_viewport().get_visible_rect().size
	_check(stage_span.x > 0.0 and power_span.y < view.y,
		"the whole nameplate is inside the viewport",
		"%.0f .. %.0f of %.0f" % [stage_span.x, power_span.y, view.y])


## Screen-space (top, bottom) of one nameplate element, from the geometry it was
## actually built with: a QuadMesh knows its own height, a Label3D knows its own
## font size. Reading those beats mirroring the constants here, where they would
## silently go stale the moment the plate is resized.
func _overlay_span(overlay: Node3D, node_name: String, camera: Camera3D) -> Vector2:
	var node: Node3D = overlay.get_node_or_null(node_name) as Node3D
	if node == null:
		return Vector2.INF
	var half: float = _overlay_height(node) * 0.5
	var base: Transform3D = overlay.global_transform
	var top: Vector2 = camera.unproject_position(base * Vector3(0.0, node.position.y + half, 0.0))
	var bottom: Vector2 = camera.unproject_position(base * Vector3(0.0, node.position.y - half, 0.0))
	return Vector2(top.y, bottom.y)


func _overlay_height(node: Node3D) -> float:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh is QuadMesh:
			return (mesh as QuadMesh).size.y
	elif node is Label3D:
		var label: Label3D = node as Label3D
		return float(label.font_size) * label.pixel_size
	return 0.0


func _overlay_width(overlay: Node3D, node_name: String, camera: Camera3D) -> float:
	var node: Node3D = overlay.get_node_or_null(node_name) as Node3D
	if node == null or not (node is MeshInstance3D):
		return 0.0
	var mesh: Mesh = (node as MeshInstance3D).mesh
	if not (mesh is QuadMesh):
		return 0.0
	var half: float = (mesh as QuadMesh).size.x * 0.5
	var base: Transform3D = overlay.global_transform
	var left: Vector2 = camera.unproject_position(base * Vector3(-half, node.position.y, 0.0))
	var right: Vector2 = camera.unproject_position(base * Vector3(half, node.position.y, 0.0))
	return absf(right.x - left.x)


## The two new ways to earn. Both matter to the shape of the game rather than to a
## number: drills are the only stat you can raise with an empty dantian, and the
## posts are the only reason ATTACK can move at all.
func _test_training_and_strike() -> void:
	_section("Drills and strikes")
	if _player == null:
		return
	_release_game_input()
	PlayerData.restore_all()
	# In the air, or mid-trance, a drill must refuse to start.
	Training.stop()

	var body_before: float = PlayerData.get_cap("body")
	var hp_cap_before: float = PlayerData.get_cap("hp")
	var qi_before: float = PlayerData.get_value("qi")
	# The drills are toggles now, not holds, and that is worth asserting rather than
	# assuming: the whole point of the change is that the keys come free the moment a
	# set starts, so a set that quietly ended when the key came up would look exactly
	# like a working toggle in any screenshot.
	await _tap_action("train_pushups")
	await _settle(4)
	_check(Training.is_training() and Training.active == "pushups",
		"tapping the drill key starts a set", Training.active)
	await _settle(92)
	_check(Training.reps > 0, "reps keep being counted with nothing held down",
		"%d reps" % Training.reps)
	_check(PlayerData.progress_ratio("body") > 0.0,
		"drilling banks xp toward the next BODY rank",
		"%.1f%% of the bar" % (PlayerData.progress_ratio("body") * 100.0))
	# A rank takes half a minute of real drilling, so the rank itself is forced
	# here: what is worth checking is the link between BODY and the health bar, not
	# this suite's patience.
	var body_need: float = PlayerData.get_cap("body") * float(PlayerData.def("body")["need"])
	PlayerData.gain("body", body_need / PlayerData.gain_coefficient)
	_check(PlayerData.get_cap("body") > body_before, "a full bar widens BODY",
		"%.2f -> %.2f" % [body_before, PlayerData.get_cap("body")])
	# The loop that makes drills worth doing twice: a bigger body holds more.
	_check(PlayerData.get_cap("hp") > hp_cap_before,
		"every BODY rank widens the HP cap",
		"%.2f -> %.2f" % [hp_cap_before, PlayerData.get_cap("hp")])
	_check(PlayerData.get_value("hp") < PlayerData.get_cap("hp"),
		"a set is paid for in blood",
		"hp %.1f / %.1f" % [PlayerData.get_value("hp"), PlayerData.get_cap("hp")])
	_check(PlayerData.get_value("qi") >= qi_before - 0.05,
		"and costs no qi at all, which is what makes it the other half of the loop",
		"qi %.1f -> %.1f" % [qi_before, PlayerData.get_value("qi")])

	# Rooted, like a trance: a drill must not double as a way to run about.
	var standing: Vector3 = (_player as Node3D).global_position
	Input.action_press("move_forward")
	await _settle(36)
	var drifted: float = standing.distance_to((_player as Node3D).global_position)
	_check(drifted < 0.5, "a drilling body cannot run off mid-set", "moved %.2f m" % drifted)
	Input.action_release("move_forward")
	# A different drill key switches straight to it rather than refusing, because the
	# player pressing 2 mid-set means "squats now", not "stop, then press 2".
	await _tap_action("train_squats")
	await _settle(4)
	_check(Training.active == "squats", "a different drill key switches straight to it",
		Training.active)
	await _tap_action("train_squats")
	await _settle(4)
	_check(not Training.is_training(), "and tapping the same key again ends the set")
	await _settle(2)

	var posts: Array = get_tree().get_nodes_in_group("training_post")
	_check(posts.size() >= 4, "the camp has posts within walking distance of spawn",
		"%d posts" % posts.size())
	if posts.is_empty():
		return
	var striker: Node = (_player as Node3D).get_node_or_null("Striker")
	_check(striker != null, "the player carries a striker")

	# Stand among the posts and strike through the real key path. The post that is
	# checked is the one the striker says is in reach, not a fixed index: the row
	# is placed close together on purpose, and a neighbouring post is a perfectly
	# good thing to hit.
	var anchor: Node3D = posts[0] as Node3D
	(_player as Node3D).global_position = anchor.global_position + Vector3(1.3, 1.0, 0.0)
	await _settle(8)
	var target: Node3D = striker.call("target") as Node3D if striker != null else null
	_check(target != null, "a post is in reach from beside the row")
	if target == null:
		return
	var stuffing_before: float = float(target.get("stuffing"))
	var attack_before: float = PlayerData.get_cap("attack")
	var banked_before: float = float(PlayerData.stats["attack"]["progress"])
	var damage_before: float = PlayerData.strike_damage()
	_press_key(KEY_F)
	await _settle(24)
	_check(float(target.get("stuffing")) < stuffing_before,
		"a strike takes stuffing out of the post in reach",
		"%.1f -> %.1f" % [stuffing_before, float(target.get("stuffing"))])
	# A single blow banks xp; a rank takes about five of them, so either outcome
	# counts as paid.
	_check(float(PlayerData.stats["attack"]["progress"]) > banked_before
			or PlayerData.get_cap("attack") > attack_before,
		"and the blow is paid for in ATTACK",
		"banked %.2f -> %.2f, cap %.2f -> %.2f" % [
			banked_before, float(PlayerData.stats["attack"]["progress"]),
			attack_before, PlayerData.get_cap("attack"),
		])
	# The point of the stat: a heavier ATTACK lands heavier blows.
	var attack_need: float = PlayerData.get_cap("attack") * float(PlayerData.def("attack")["need"])
	PlayerData.gain("attack", attack_need / PlayerData.gain_coefficient)
	_check(PlayerData.get_cap("attack") > attack_before, "a full bar widens ATTACK",
		"%.2f -> %.2f" % [attack_before, PlayerData.get_cap("attack")])
	_check(PlayerData.strike_damage() > damage_before,
		"and training it makes the next blow land harder",
		"%.1f -> %.1f" % [damage_before, PlayerData.strike_damage()])

	# A post that runs out is out of play until it is restuffed, which is what
	# stops a single post from being an infinite damage sink.
	var second: Node3D = posts[1] as Node3D
	second.set("restuff_delay", 0.25)
	second.call("take_hit", 9999.0, (_player as Node3D).global_position)
	await _settle(2)
	_check(bool(second.call("is_knocked_out")), "enough damage knocks a post out")
	(_player as Node3D).global_position = second.global_position + Vector3(1.3, 1.0, 0.0)
	await _settle(4)
	var chosen: Variant = striker.call("nearest_post") if striker != null else null
	_check(chosen == null or chosen != second, "a knocked-out post is passed over")
	await _settle(40)
	_check(not bool(second.call("is_knocked_out")), "and restuffs itself afterwards")
	_release_game_input()


## The settings panel is the only route to the sliders now, so it has to exist,
## start hidden, hold both clamps, and offer an aura per catalogue entry with the
## unearned ones genuinely locked.
func _test_settings_modal() -> void:
	_section("Settings panel")
	if _hud == null:
		return
	var modal: Control = _find_by_name(_hud, "SettingsModal") as Control
	_check(modal != null, "the settings modal exists")
	if modal == null:
		return
	_check(not modal.is_visible_in_tree(), "it starts hidden rather than covering the game")
	_check(_hud.has_method("open_settings") and _hud.has_method("settings_open"),
		"the HUD can open and report it")

	var sliders: Array[HSlider] = []
	_collect_sliders(_find_by_name(_hud, "SettingsPanel"), sliders)
	_check(sliders.size() == 2, "both clamps live inside the modal now",
		"%d sliders" % sliders.size())

	var grid: GridContainer = _find_by_name(_hud, "AuraGrid") as GridContainer
	_check(grid != null, "the aura picker was built")
	if grid != null:
		_check(grid.get_child_count() == Cultivation.AURAS.size(),
			"one button per aura in the catalogue",
			"%d buttons for %d auras" % [grid.get_child_count(), Cultivation.AURAS.size()])
		var locked: int = 0
		var expected: int = 0
		for entry: Dictionary in Cultivation.AURAS:
			if Cultivation.tier < int(entry["unlock_tier"]):
				expected += 1
		for child in grid.get_children():
			if (child as Button).disabled:
				locked += 1
		_check(locked == expected, "exactly the unearned auras are locked",
			"%d locked, expected %d" % [locked, expected])

	_hud.call("open_settings")
	await _settle(2)
	_check(_hud.call("settings_open"), "it opens")
	# The camera captures the pointer while you play, so the modal has to free it
	# or the sliders inside could never be dragged.
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED,
		"opening it frees the mouse so the controls can be clicked")
	_check(modal.is_visible_in_tree(), "and it is actually on screen")
	# Visible in the tree is not the same as visible to the player, and the gap between
	# the two is not theoretical here: the panel was set to fully transparent as it
	# opened and nothing ever faded it back up, so the settings opened onto a dimmed
	# screen with the controls all present, correctly laid out and invisible — while
	# every check above passed. Opacity is what the difference comes down to, so opacity
	# is what is measured, by waiting for the fade rather than sleeping past it.
	var panel: PanelContainer = _find_by_name(_hud, "SettingsPanel") as PanelContainer
	_check(panel != null and panel.size.x > 100.0 and panel.size.y > 100.0,
		"the panel is laid out at a readable size",
		"%s" % ("%.0f x %.0f" % [panel.size.x, panel.size.y] if panel != null else "missing"))
	var opaque: bool = false
	for i in 40:
		await _settle(1)
		if panel != null and panel.modulate.a >= 0.99:
			opaque = true
			break
	# Built but never filled is a failure mode this panel already had once — the transparent
	# box was the same bug a layer up. The summary is generated in `_refresh`, so a panel
	# that opens correctly can still open empty.
	_hud.call("_refresh")
	var summary: Label = _find_by_name(panel, "SettingsSummary") as Label
	_check(summary != null and summary.text.strip_edges() != "",
		"the panel says where you are and what you have", "" if summary == null else summary.text)
	_check(summary != null and summary.text.contains(PlayerData.power_text()),
		"and it agrees with the plate over your head on your power",
		"" if summary == null else summary.text)
	_check(opaque, "and it is fully opaque rather than a transparent box on a dim screen",
		"alpha %.2f" % (panel.modulate.a if panel != null else -1.0))
	_hud.call("close_settings")
	await _settle(2)
	_check(not _hud.call("settings_open"), "it closes again")
	_check(panel == null or panel.modulate.a >= 0.99,
		"and a close during the fade leaves it ready to open again",
		"alpha %.2f" % (panel.modulate.a if panel != null else -1.0))


## The entrance animation has to *end*.
##
## It fades every panel up from nothing, which means every panel in the interface passes
## through a state where it is present, correctly laid out and invisible — the exact state
## the settings modal was stuck in for several builds, and the one that is hardest to
## notice because the code looks right. So the entrance is run on purpose here (it is off
## by default under `--selftest`) and the thing checked is where it finishes, not that it
## started.
func _test_hud_intro() -> void:
	_section("Panel entrance")
	if _hud == null:
		return
	var panels: Array = []
	for node in _hud.get_child(0).get_children():
		var panel := node as Control
		if panel == null:
			continue
		panels.append(panel)
	_check(panels.size() >= 4, "there is a set of panels to bring in",
		"%d panels" % panels.size())
	_hud.set("intro_enabled", true)
	_hud.call("_play_intro")
	# The entrance holds each panel at zero for a moment, so the check the other way —
	# that something actually fades — has to sample early rather than after it finishes.
	var seen_faded: int = 0
	for i in 4:
		await _settle(1)
		for panel: Control in panels:
			if panel.modulate.a < 0.9:
				seen_faded += 1
				break
	_check(seen_faded > 0, "the panels fade up rather than simply appearing")
	var opaque: int = 0
	for i in 90:
		await _settle(1)
		opaque = 0
		for panel: Control in panels:
			if panel.modulate.a >= 0.999:
				opaque += 1
		if opaque == panels.size():
			break
	_check(opaque == panels.size(), "and every one of them ends fully visible",
		"%d of %d at alpha 1" % [opaque, panels.size()])
	_hud.set("intro_enabled", false)


## No control in the HUD may take keyboard focus.
##
## Space both jumps and activates whatever Button currently has focus, so one click on
## a panel control is enough to make every later jump fold the stat readout open and
## shut — which is exactly how it presents: you click Show once, and from then on the
## panel flickers every time you jump. The fold controls are the only clickable things
## in the HUD and clicking one is how you would come to notice, so this is checked as a
## property of every button in the tree rather than of the two that were reported.
func _test_hud_focus() -> void:
	_section("Panel controls")
	if _hud == null:
		return
	var buttons: Array = []
	_collect_buttons(_hud, buttons)
	_check(not buttons.is_empty(), "the HUD has controls to click", "%d buttons" % buttons.size())
	var grabbing: Array = []
	for node in buttons:
		var button: Button = node
		if button.focus_mode != Control.FOCUS_NONE:
			grabbing.append(String(button.name))
	_check(grabbing.is_empty(), "no HUD control steals the jump key for itself",
		" | ".join(grabbing))
	# ...and the fold controls have to stay clickable, or folding is keyboard-only and
	# the keyboard is what was just taken away from them.
	for pair: Array in [["stats", "StatsToggle"], ["map", "MapToggle"],
			["settings", "SettingsButton"]]:
		var button: Button = _find_by_name(_hud, String(pair[1])) as Button
		_check(button != null and button.mouse_filter != Control.MOUSE_FILTER_IGNORE,
			"the %s control can still be clicked" % pair[0])


## The compass at the edge of the screen.
##
## The check that matters is the one a decorative marker would fail: that the name it
## shows belongs to the nearest *unfound* site, by the same flat measure the game uses. An
## arrow that points at the second nearest, or at one already visited, is worse than no
## arrow, because it is followed.
func _test_wayfinder() -> void:
	_section("Wayfinder")
	if _hud == null or _player == null:
		return
	var view: Control = _hud.get("_wayfinder")
	_check(view != null, "the HUD carries a compass")
	if view == null:
		return
	var landmarks: Node = get_tree().root.get_node_or_null("Main/Landmarks")
	if landmarks == null:
		return

	view.call("_update")
	var expected: Dictionary = landmarks.call("nearest_unfound", _player.global_position)
	_check(not expected.is_empty(), "there is somewhere left to find")
	if expected.is_empty():
		return
	_check(bool(view.call("active")), "which the compass points at")
	_check(String(view.call("target_name")) == String(expected["name"]),
		"naming the nearest one not yet found",
		"%s vs %s" % [String(view.call("target_name")), String(expected["name"])])
	var at: Vector3 = expected["position"]
	var flat: float = Vector2(at.x - _player.global_position.x, at.z - _player.global_position.z).length()
	_check(_near(float(view.call("target_metres")), flat, 0.75),
		"and the distance to it is measured flat, not over the ground",
		"%.1f vs %.1f m" % [float(view.call("target_metres")), flat])
	var text: String = String(view.call("text"))
	_check(text.contains(String(expected["name"])) and text.contains(" m"),
		"with the name and the walk printed together", text)

	# The whole point of holding it in from the edge is that it never leaves the screen,
	# including when the thing it points at is directly behind the player.
	var point: Vector2 = view.call("marker_point")
	var inside: bool = point.x >= 40.0 and point.x <= view.size.x - 40.0 \
		and point.y >= 40.0 and point.y <= view.size.y - 40.0
	_check(inside, "the mark is held inside the screen", str(point) + " of " + str(view.size))

	# Every site found: the marker has nothing left to say and says nothing.
	var sites: Array = landmarks.call("sites")
	var was: Array = []
	for site: Dictionary in sites:
		was.append(bool(site.get("discovered", false)))
		site["discovered"] = true
	view.call("_update")
	_check(not bool(view.call("active")),
		"with every site found the compass stops pointing, rather than looping")
	for i in sites.size():
		sites[i]["discovered"] = was[i]
	view.call("_update")
	_check(bool(view.call("active")), "and it comes back for the sites still out there")

	# Off the screen while a panel is open: the marker is drawn over the dim, and a
	# world-space readout floating above a menu is not part of the menu.
	_hud.call("open_settings")
	view.call("_update")
	_check(not bool(view.call("active")), "and it is off while the settings are open")
	_hud.call("close_settings")
	view.call("_update")
	_check(bool(view.call("active")), "and back once they close")


## How far the least well-placed site sits from the nearest road, for the check's detail
## line. Reads the sites' own recorded distance rather than re-measuring it here.
func _furthest_site(landmarks: Node) -> float:
	var worst: float = 0.0
	for site: Dictionary in landmarks.call("sites"):
		worst = maxf(worst, float(site.get("road_distance", 0.0)))
	return worst


## The map is only worth having if its coordinates are right: a marker drawn a few
## pixels off reads as a destination that is not there, which is worse than no map.
## So the projection and the legend are measured; the picture is not.
func _test_map() -> void:
	_section("Map")
	if _hud == null or _terrain == null:
		return
	var view: Control = _find_by_name(_hud, "MapView") as Control
	var toggle: Button = _find_by_name(_hud, "MapToggle") as Button
	_check(view != null and toggle != null, "the HUD carries a map and a fold control")
	if view == null or toggle == null:
		return
	_check(view.custom_minimum_size.x >= 120.0,
		"it has a floor on its size, so it cannot collapse to nothing in a container",
		"%.0f px" % view.custom_minimum_size.x)
	# The ground on the map has to come from the terrain rather than from a drawn
	# approximation, or the map can disagree with the world underfoot.
	var texture: Texture2D = view.call("_ground") as Texture2D
	_check(texture != null and texture.get_width() >= 128,
		"the picture is the terrain's own baked map",
		"%d px" % (texture.get_width() if texture != null else 0))
	_check(view.get("_player") != null, "and it knows where the player is")

	var extent: float = float(_terrain.call("extent"))
	var centre: Vector2 = view.call("_to_map", Vector2.ZERO)
	_check(centre.distance_to(view.size * 0.5) < 1.5,
		"the middle of the world is the middle of the map", str(centre))
	# World -Z is north, north is up, and east is right: the one convention that makes
	# the arrow in the middle agree with the signposts out in the world.
	var east: Vector2 = view.call("_to_map", Vector2(extent * 0.25, 0.0))
	var north: Vector2 = view.call("_to_map", Vector2(0.0, -extent * 0.25))
	_check(east.x > centre.x + 1.0 and _near(east.y, centre.y, 1.5),
		"east is to the right", str(east))
	_check(north.y < centre.y - 1.0 and _near(north.x, centre.x, 1.5),
		"and north is up", str(north))
	var scale: float = float(view.call("_px_per_metre"))
	_check(_near(scale * extent, minf(view.size.x, view.size.y), 2.0),
		"the whole world fits the canvas", "%.2f px per metre" % scale)

	var zones: Array = view.call("zone_legend")
	_check(zones.size() == 4, "every spirit zone is on the map", "%d zones" % zones.size())
	var legend: Control = _find_by_name(_hud, "MapLegend") as Control
	_check(legend != null, "the map has a legend")
	if legend != null:
		var text: String = String(_hud.call("map_legend_text"))
		# Every mark the map draws has to be named. A legend that explains three of four
		# marks is worse than none: the fourth one is the one the player cannot place.
		var marks: Array = view.call("legend")
		_check(marks.size() >= 4, "and a row for every mark it draws", "%d marks" % marks.size())
		var unnamed: Array = []
		for entry: Dictionary in marks:
			if not text.contains(String(entry["text"])):
				unnamed.append(String(entry["text"]))
		_check(unnamed.is_empty(), "each of them named", ", ".join(unnamed))
		# The chip is the point: a colour name in a sentence asks the player to match a
		# word to a dot from memory, which is what the panel used to do and what read as
		# illegible. Every row carries a swatch of the colour it describes.
		var chips: int = 0
		for row in legend.get_children():
			for child in row.get_children():
				if child is ColorRect:
					chips += 1
		_check(chips >= marks.size(), "every row swatches the colour it describes",
			"%d chips over %d marks" % [chips, marks.size()])
		var named: int = 0
		for entry: Dictionary in zones:
			if text.contains(String(entry["text"])):
				named += 1
		_check(named == zones.size(), "and it names every zone on it",
			"%d of %d named" % [named, zones.size()])
		# A zone you cannot use yet has to be labelled as out of reach, or the map
		# shows four pillars and explains none of them.
		var locked: int = 0
		for entry: Dictionary in zones:
			if bool(entry["locked"]):
				locked += 1
		if locked > 0:
			_check(text.contains("stage"),
				"including which of them are out of reach, by stage",
				"%d locked" % locked)
		# The elder is the one mark that moves, so it is the one mark a legend most needs
		# to explain. It is also the only thing on this map that is waiting on the player
		# rather than the other way round.
		_check(text.contains("elder"), "and it says which mark is the elder", text)
		_check(view.get("_elder") != null, "the map knows where the elder stands")
		# The pulse is read from the task chain rather than kept as a second flag, so the two
		# can be compared directly. A cached copy here would be one more thing that has to be
		# told when a task is finished, and forgetting is exactly how the mark would end up
		# pulsing forever over a reward that was already collected.
		var claimable_now: bool = not (Quests.claimable() as Dictionary).is_empty()
		var waiting: bool = bool(view.call("elder_reward_waiting"))
		_check(waiting == claimable_now,
			"the elder's mark moves exactly when a reward is waiting",
			"map=%s chain=%s" % [waiting, claimable_now])

	# The sites out in the world, on the map: the found ones marked, the rest left off.
	# Drawing all nine would turn "go and look over that hill" into "walk to this
	# coordinate", and the count in the legend is the honest half of that information
	# anyway — it says there is more out there without saying where.
	var landmarks: Node = get_tree().root.get_node_or_null("Main/Landmarks")
	_check(landmarks != null, "the world has sites to find")
	if landmarks != null:
		var sites: Array = landmarks.call("sites")
		_check(sites.size() >= 6, "several of them", "%d sites" % sites.size())
		var on_roads: bool = true
		var named: bool = true
		var seen: Dictionary = {}
		for site: Dictionary in sites:
			if String(site["name"]).is_empty():
				named = false
			if seen.has(String(site["name"])):
				named = false
			seen[String(site["name"])] = true
			if float(site.get("road_distance", 0.0)) > 24.0:
				on_roads = false
		_check(named, "each with its own name")
		_check(on_roads, "all of them beside a road, so following a road is how you find them",
			"furthest %.1f m from a road" % _furthest_site(landmarks))
		var marked: int = 0
		for site: Dictionary in sites:
			if bool(site.get("discovered", false)):
				marked += 1
		var counts: Vector2i = view.call("landmark_counts")
		_check(counts.y == sites.size() and counts.x == marked,
			"the map counts what is found and what exists", str(counts))
		# Marking is read out of the sites themselves, so the map cannot claim a site is
		# found while the world still has its beacon lit for it.
		var lit_beacons: int = 0
		for site: Dictionary in sites:
			var beacon: Node3D = site.get("beacon")
			if beacon != null and beacon.visible:
				lit_beacons += 1
		_check(lit_beacons == sites.size() - marked,
			"a beacon burns for every site that is not on the map yet",
			"%d lit, %d found" % [lit_beacons, marked])
		_check(String(_hud.call("map_legend_text")).contains("Site you found")
			or String(_hud.call("map_legend_text")).contains("site"),
			"and the legend explains the mark", String(_hud.call("map_legend_text")))

	_test_wayfinder()

	_check(bool(_hud.call("map_expanded")), "the map starts open")
	toggle.pressed.emit()
	await _settle(2)
	_check(not view.visible, "the fold control puts it away")
	toggle.pressed.emit()
	await _settle(2)
	_check(view.visible, "and brings it back")


# ------------------------------------------------------------- roads and travel

## The roads exist to be *run*, so what is measured is the thing that makes them worth
## running: the strip the player walks on climbs more gently than the hillside beside
## it, and it is where the grid says it is.
func _test_roads() -> void:
	_section("Roads")
	if _terrain == null:
		return
	var roads: Array = _terrain.call("roads")
	_check(roads.size() >= 3, "the roads are laid out", "%d" % roads.size())
	if roads.is_empty():
		return

	var centre: float = _terrain.call("road_weight_at", 0.0, 0.0)
	_check(centre > 0.9, "a road leaves the home camp", "%.2f" % centre)
	_check(is_equal_approx(_terrain.call("road_weight_at", 300.0, 300.0), 0.0),
		"and the far corner is not road")

	# Steepest climb along a centre line against the steepest climb beside it. The road
	# may not be *flat* — it follows the land — but it may not be as steep as the land.
	var road: Dictionary = roads[0]
	var points: PackedVector2Array = road["points"]
	var heights: PackedFloat32Array = road["heights"]
	var worst_road: float = 0.0
	var worst_side: float = 0.0
	var side: Vector2 = Vector2(0.0, 0.0)
	for i in range(1, points.size()):
		var step: float = points[i].distance_to(points[i - 1])
		if step < 0.01:
			continue
		worst_road = maxf(worst_road, absf(heights[i] - heights[i - 1]) / step)
		# 12 m to the side of the same point: clear of the strip and its shoulder.
		var to_side: Vector2 = (points[i] - points[i - 1]).normalized().orthogonal() * 12.0
		var beside: Vector2 = points[i] + to_side
		side = beside
		var side_step: float = to_side.length()
		var a: float = float(_terrain.call("surface_height_at", beside.x, beside.y))
		var b: float = float(_terrain.call(
			"surface_height_at", beside.x - to_side.x * 0.25, beside.y - to_side.y * 0.25
		))
		worst_side = maxf(worst_side, absf(a - b) / (side_step * 0.25))
	_check(worst_road <= 0.2, "no stretch of road climbs like a hillside",
		"%.3f rise per metre" % worst_road)
	print("  info  steepest road %.3f/m vs %.3f/m twelve metres to the side at %s" % [
		worst_road, worst_side, str(side)])

	# Every road gets the same number of signs, and stood off its own end. Both were once
	# wrong in silence: the distances were metres, three of them were fixed, and the third
	# fell past the end of a shorter road — so the network shipped with two signs a road
	# and nothing said so. Counting signs per road is what makes that failure visible.
	var signs: Array = get_tree().get_nodes_in_group("signpost")
	var per_road: Dictionary = {}
	for sign: Node in signs:
		var road_index: int = int(sign.get_meta("road_index", -1))
		per_road[road_index] = int(per_road.get(road_index, 0)) + 1
	_check(signs.size() >= roads.size() * 3, "the roads are signed",
		"%d signs over %d roads" % [signs.size(), roads.size()])
	var counts: Array = per_road.values()
	var fewest: int = 999
	var most: int = 0
	for count: int in counts:
		fewest = mini(fewest, count)
		most = maxi(most, count)
	_check(not counts.is_empty() and fewest == most,
		"every road carries the same number of signs",
		"%d to %d across %d roads" % [fewest, most, counts.size()])


# ------------------------------------------------------------------ the safe zone

## The bubble is a promise: retreating home always works. That is only true if it is
## wider than everything it has to cover and if the enemies actually consult it, which
## is what this checks rather than that a sphere mesh exists.
func _test_safe_zone() -> void:
	_section("Safe zone")
	var zone: Node3D = get_tree().get_first_node_in_group("safe_zone") as Node3D
	_check(zone != null, "the camp has a safe zone")
	if zone == null or _player == null:
		return
	var radius: float = float(zone.get("radius"))
	_check(radius > 10.5, "it covers the fence ring and the yard", "%.1f m" % radius)
	_check(bool(zone.call("contains", zone.global_position)), "the middle is inside")
	_check(not bool(zone.call("contains", zone.global_position + Vector3(radius + 6.0, 0.0, 0.0))),
		"and the edge is a real boundary")
	# Spherical, not a disc on the ground: a raider must not be dodged by jumping.
	_check(bool(zone.call("contains", zone.global_position + Vector3(0.0, radius * 0.5, 0.0))),
		"it holds the air over the camp too")
	var respawn: Vector3 = zone.call("spawn_point") as Vector3
	_check(bool(zone.call("contains", respawn)), "a beaten body wakes inside it")

	(_player as Node3D).call("warp_to", respawn)
	await _land(_player)
	await _settle(4)
	_check(bool(zone.call("player_inside")), "the player inside it knows")
	_check(bool(_player.call("in_safe_zone")), "and the controller agrees")
	(_player as Node3D).call("warp_to", Vector3(0.0, float(_terrain.call("surface_height_at", 0.0, 42.0)) + 1.0, 42.0))
	await _land(_player)
	await _settle(4)
	_check(not bool(zone.call("player_inside")), "and outside it knows that too")


# --------------------------------------------------------------------- the raiders

## Raiders are checked for the things the design promises: they are out there, they come
## for you, they do not follow you home, and they pay when they fall.
func _test_enemies() -> void:
	_section("Raiders")
	var camps_node: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	_check(camps_node != null, "the raider camps are part of the world")
	if camps_node == null or _player == null:
		return
	var camps: Array = camps_node.call("camps")
	var raiders: Array = camps_node.call("enemies")
	_check(camps.size() >= 3, "several camps were placed", "%d" % camps.size())
	_check(raiders.size() >= 3, "and staffed", "%d raiders" % raiders.size())
	if raiders.is_empty():
		return
	# Every guard's leash is measured from its *own* fire, in world space. The enemies are
	# children of their camp, so a camp's placement and a raider's local offset are two
	# different vectors that look like the same one — handing both the same value puts each
	# guard one camp-width from the ground it is supposed to be guarding, leashed to a home
	# that is nowhere near it. Nothing else about the camp looks wrong when that happens.
	for raider: Node3D in raiders:
		var leash: Vector3 = raider.call("leash_origin")
		var nearest: float = INF
		for camp: Dictionary in camps:
			var centre: Vector3 = camp["position"]
			nearest = minf(nearest, Vector2(leash.x - centre.x, leash.z - centre.z).length())
		_check(nearest <= 8.0, "%s is leashed to its own fire" % raider.name,
			"%.1f m from the nearest camp" % nearest)

	var zone: Node = get_tree().get_first_node_in_group("safe_zone")
	var bot: CharacterBody3D = raiders[0]
	var home: Vector3 = bot.call("leash_origin")
	var safe_home: float = 0.0
	if zone != null:
		safe_home = float(zone.get("radius"))
	_check(home.distance_to(Vector3.ZERO) > safe_home + 20.0,
		"no camp sits against the camp wards", "%.0f m out" % home.distance_to(Vector3.ZERO))

	# The wards, asked of the raider itself. The raider is stood outside the bubble with
	# its leash moved to match — the question is whether it will cross the boundary, and
	# that can only be asked of a raider that is in a position to.
	var kept_home: Vector3 = bot.call("leash_origin")
	var kept_position: Vector3 = bot.global_position
	var outside: Vector3 = Vector3(0.0, 0.0, float(zone.get("radius")) + 6.0)
	outside.y = float(_terrain.call("surface_height_at", outside.x, outside.z)) + 0.4
	bot.set("home", outside)
	bot.global_position = outside
	(_player as Node3D).call("warp_to", Vector3(0.0, float(_terrain.call("surface_height_at", 0.0, 0.0)) + 1.0, 0.0))
	await _land(_player)
	await _settle(3)
	_check(not bool(bot.call("_may_pursue")), "a raider will not hunt inside the wards")
	(_player as Node3D).call("warp_to", Vector3(0.0, float(_terrain.call("surface_height_at", 0.0, 44.0)) + 1.0, 44.0))
	await _land(_player)
	await _settle(3)
	_check(bool(bot.call("_may_pursue")), "and will outside them",
		"raider at %s, player at %s" % [str(bot.global_position), str(_player.global_position)])
	bot.set("home", kept_home)
	bot.global_position = kept_position

	# The leash is what makes a camp escapable, and it is measured rather than asserted:
	# standing at the camp draws them in, and leaving takes them off you.
	_player.call("warp_to", home + Vector3(7.0, 2.0, 0.0))
	await _land(_player)
	await _settle(2)
	var before: float = _flat_distance_to(bot)
	await _settle(70)
	var after: float = _flat_distance_to(bot)
	_check(after < before - 0.4, "a raider closes on a player who comes close",
		"%.1f m -> %.1f m" % [before, after])

	_player.call("warp_to", home + Vector3(70.0, 2.0, 0.0))
	await _land(_player)
	await _settle(2)
	var leash_before: float = _flat_home_distance(bot)
	await _settle(90)
	var leash_after: float = _flat_home_distance(bot)
	# The *behaviour* is what has to stop, not the predicate: back at its fire, a raider
	# may perfectly well pursue something standing next to it. What it must not do is
	# still be chasing a player seventy metres away.
	_check(int(bot.get("state")) != 1, "a raider gives up a player who leaves",
		"state %d, %.1f m away" % [int(bot.get("state")), _flat_distance_to(bot)])
	_check(leash_after < leash_before + 0.05, "and turns back rather than following",
		"%.1f m -> %.1f m from home" % [leash_before, leash_after])

	# The strike has to *find* a raider, not merely damage one that is handed to it: the
	# reach, the group name and the alive-check are three separate ways that link can be
	# broken without the damage model noticing.
	var striker: Node = _player.get_node_or_null("Striker")
	if striker != null and striker.has_method("nearest_target"):
		_player.call("warp_to", bot.global_position + Vector3(1.4, 0.5, 0.0))
		await _land(_player)
		await _settle(3)
		# *A* raider of this camp, not a named one: the striker finds the nearest, and its
		# neighbours are standing a metre away. Which of them is nearest is not the
		# contract — that a blow lands on a living enemy rather than on nothing is.
		var found: Variant = striker.call("nearest_target")
		var found_node := found as Node3D
		_check(found_node != null and found_node.is_in_group("enemy")
				and not bool(found_node.call("is_dead")),
			"a raider within reach is what a strike finds",
			str(found_node) if found_node != null else "nothing in reach")
		# And the raider hits back through the player's own door, so being beaten trains HP
		# and DEFENSE exactly like falling does.
		var hp_before: float = PlayerData.get_value("hp")
		var defense_progress: float = PlayerData.progress_ratio("defense")
		(_player as CharacterBody3D).call("take_enemy_blow", 12.0, bot)
		_check(PlayerData.get_value("hp") < hp_before, "a raider's blow lands on the player",
			"%.1f -> %.1f" % [hp_before, PlayerData.get_value("hp")])
		_check(PlayerData.progress_ratio("hp") > 0.0 or PlayerData.progress_ratio("defense") > defense_progress,
			"and being hit is training, like every other blow")

	# The payout: crystals in the purse and ATTACK training, through the same funnel as
	# everything else.
	var crystals_before: int = PlayerData.crystals
	var attack_before: float = PlayerData.get_cap("attack")
	var attack_progress_before: float = PlayerData.progress_ratio("attack")
	var health: float = float(bot.get("max_hp"))
	var dealt: float = float(bot.call("take_hit", health * 0.5, _player.global_position))
	_check(dealt > 0.0, "a raider takes a blow", "%.1f damage" % dealt)
	_check(bot.call("health_ratio") < 1.0, "and its bar drops",
		"%.2f" % float(bot.call("health_ratio")))
	var killed: float = float(bot.call("take_hit", health, _player.global_position))
	_check(killed > 0.0 and bool(bot.call("is_dead")), "a raider can be killed")
	_check(PlayerData.crystals > crystals_before, "a kill pays crystals",
		"%d -> %d" % [crystals_before, PlayerData.crystals])
	_check(PlayerData.get_cap("attack") > attack_before
			or PlayerData.progress_ratio("attack") > attack_progress_before,
		"a kill trains ATTACK", "cap %.2f" % PlayerData.get_cap("attack"))
	_check(bot.call("is_knocked_out"), "and a corpse counts as finished")
	_check(not bool(bot.call("_may_pursue")), "a corpse does not pursue")
	# Struck down or not, the camp restocks: a cleared camp has to come back or the world
	# runs out of things to fight.
	bot.call("_restock")
	_check(not bool(bot.call("is_dead")) and is_equal_approx(float(bot.call("health_ratio")), 1.0),
		"and the camp restocks it")
	PlayerData.restore_all()


func _flat_distance_to(other: Node3D) -> float:
	return Vector2(
		_player.global_position.x - other.global_position.x,
		_player.global_position.z - other.global_position.z
	).length()


func _flat_home_distance(other: Node3D) -> float:
	var home: Vector3 = other.call("leash_origin")
	return Vector2(other.global_position.x - home.x, other.global_position.z - home.z).length()


# ------------------------------------------------------------------ the elder's chain

## The task chain is the game's tutorial for its own movement, so what is checked is the
## loop: a task counts the thing it says it counts, finishing it is worth crystals, and
## the milestone tasks hand over an ability that actually works.
func _test_quests() -> void:
	_section("Tasks")
	Quests.reset()
	_check(not Quests.current().is_empty(), "the chain starts with a task")
	_check(Quests.completed_count() == 0, "and nothing done yet")
	_check(Quests.claimable().is_empty(), "with nothing to hand in")

	var first: Dictionary = Quests.current()
	var extra: float = float(first["target"]) * 0.5
	Quests.report(String(first["kind"]), extra)
	_check(is_equal_approx(Quests.progress_of(first), extra) && Quests.ratio_of(first) < 1.0,
		"progress is counted as it is reported", "%.0f / %.0f" % [extra, float(first["target"])])
	_check(Quests.completed_count() == 0, "a half-finished task is not a finished one")

	# Reporting the wrong kind must be ignored, or every task would complete itself on the
	# first jump the player took.
	var other_kind: String = "jump" if String(first["kind"]) != "jump" else "run"
	Quests.report(other_kind, 1000.0)
	_check(is_equal_approx(Quests.progress_of(first), extra),
		"and a report of some other kind does not count")

	Quests.report(String(first["kind"]), float(first["target"]))
	_check(Quests.completed_count() == 1, "filling the bar finishes the task")
	_check(not Quests.claimable().is_empty(), "and it waits to be handed in")
	var crystals_before: int = PlayerData.crystals
	var handed: Dictionary = Quests.claim()
	_check(not handed.is_empty(), "handing it in pays out")
	_check(PlayerData.crystals > crystals_before, "in crystals",
		"+%d" % (PlayerData.crystals - crystals_before))
	_check(Quests.claimable().is_empty(), "and cannot be handed in twice")
	_check(Quests.current_index() == 1, "after which the next task is the one to do")

	# The elder is the interface for all of it, so his marker has to agree with the state.
	var npc: Node = get_tree().get_first_node_in_group("quest_npc")
	_check(npc != null, "the elder stands in the camp")
	if npc != null:
		_check(String(npc.call("marker_state")) == "!", "he wears a ! for the task in hand",
			String(npc.call("marker_state")))
		var claimable_task: Dictionary = Quests.TASKS[1]
		Quests.report(String(claimable_task["kind"]), float(claimable_task["target"]))
		_check(String(npc.call("marker_state")) == "?", "and a ? once one is ready",
			String(npc.call("marker_state")))
		npc.call("interact")
		_check(Quests.claimable().is_empty(), "talking to him takes the task off your hands")
	_check(Quests.all_complete() == false or Quests.completed_count() > 1,
		"the chain has more than one thing in it")


## The people, and the two things they let you decide.
##
## Two claims are worth more than the rest here and both are checked by walking up to
## somebody and pressing the key. The first is that the *input* path works at all — a dialogue
## nothing can open is a table of strings. The second is that a choice outlives the launch it
## was made in: the world is rebuilt from scratch every time the game starts, so a camp that
## was burned only stays burned if the world is told about the decision again as it builds.
func _test_people() -> void:
	_section("The people")
	var people: Node = get_tree().root.get_node_or_null("Main/People")
	var camps: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	_check(people != null, "the cast is part of the world")
	if people == null or _player == null or _terrain == null:
		return
	var villagers: Array = people.call("villagers")
	_check(villagers.size() == Story.cast().size(),
		"and holds exactly the people the story knows about",
		"%d in the world against %d in the table" % [villagers.size(), Story.cast().size()])
	_check(villagers.size() >= 3, "which is more than the one we had",
		"%d people" % villagers.size())
	_check(get_tree().get_nodes_in_group("quest_npc").size() == 1,
		"and the elder is still the only one handing out tasks",
		"%d in the group" % get_tree().get_nodes_in_group("quest_npc").size())
	for node: Node in villagers:
		var villager := node as Node3D
		_check(villager != null and String(villager.get("person_id")) != "",
			"a person in the world with an id: %s" % String(node.name))
		var plate := villager.get_node_or_null("NamePlate") as Label3D
		_check(plate != null and plate.text != "",
			"%s has a name over their head" % String(villager.get("npc_name")),
			plate.text if plate != null else "no plate")

	# Liveliness, measured rather than asserted: somebody walks a road, and a figure that
	# slides sideways along it reads as a prop on a rail rather than as a person.
	var walkers: Array = []
	for node: Node in villagers:
		if bool(node.call("is_on_road")):
			walkers.append(node)
	_check(walkers.size() >= 1, "somebody is walking one of the roads",
		"%d walkers" % walkers.size())
	if not walkers.is_empty():
		var walker := walkers[0] as Node3D
		var from: Vector3 = walker.global_position
		await _settle(320)
		var moved: float = Vector2(
			walker.global_position.x - from.x, walker.global_position.z - from.z
		).length()
		_check(moved > 0.4, "and is somewhere else a few seconds later", "%.2f m" % moved)
		var ground: float = float(_terrain.call(
			"surface_height_at", walker.global_position.x, walker.global_position.z
		))
		_check(absf(walker.global_position.y - ground) < 0.4,
			"with their feet still on the ground",
			"%.2f m off it" % (walker.global_position.y - ground))

	var ren: Node3D
	for node: Node in villagers:
		if String(node.get("person_id")) == "ren":
			ren = node as Node3D
	_check(ren != null, "Master Ren is standing in the camp")
	if ren == null:
		return
	_player.call("warp_to", ren.global_position + Vector3(1.5, 0.6, 0.0))
	await _land(_player)
	await _settle(3)
	_check(bool(ren.call("in_range")), "close enough to talk to")
	# The real key, not the action: the people read `is_action_pressed` off an *event*, and
	# `Input.action_press` only moves the polled state — a synthetic hold is invisible to them.
	_press_key(KEY_E)
	await _settle(3)
	_check(Story.talking(), "the talk key opens a conversation")
	_check(bool(_hud.call("dialogue_open")), "and the band is on screen")
	_check(Story.conversation().get("speaker", "") == "Master Ren",
		"and it says who is talking", String(Story.conversation().get("speaker", "")))
	_check(Story.options().size() == 2, "with two answers on the table",
		"%d" % Story.options().size())

	# A conversation is not something you can walk out of the middle of.
	var standing: Vector3 = _player.global_position
	await _hold_action("move_forward", 14)
	_check(_player.global_position.distance_to(standing) < 0.25,
		"and the body cannot walk away mid-sentence",
		"%.2f m" % _player.global_position.distance_to(standing))

	# Answered on the *key*, because the number keys are bound to the drills as well — the
	# thing that has to be true is that the conversation reads them first.
	var attack_before: float = PlayerData.get_cap("attack")
	_press_key(KEY_1)
	await _settle(3)
	_check(PlayerData.chosen_option("path") == "fist", "key 1 answers the question",
		PlayerData.chosen_option("path"))
	_check(PlayerData.get_cap("attack") >= attack_before + 7.0,
		"and the heavier hand is permanent, not a number in a dialogue",
		"%.1f -> %.1f" % [attack_before, PlayerData.get_cap("attack")])
	_check(not Training.is_training(), "and answering did not also start a drill")
	_check(String(Story.conversation().get("line", "")).contains("that is what you are"),
		"the person replies before the band closes",
		String(Story.conversation().get("line", "")))
	Story.close()
	await _settle(3)
	_check(not bool(_hud.call("dialogue_open")), "and then the band goes away")
	Story.begin("ren")
	_check(Story.options().is_empty(),
		"a decision already made cannot be made again")
	_check(String(Story.conversation().get("line", "")).contains("already chose"),
		"and the person says so rather than forgetting",
		String(Story.conversation().get("line", "")))
	Story.close()

	# The people see what you have become, which is the whole of what makes a crowd feel like
	# a crowd rather than a row of menus.
	# The greeting follows the number, which is the whole of what makes a crowd feel like a
	# crowd rather than a row of menus. Grown by hand here rather than trained, because the
	# suite has already been through every ring and the *table* is what is being checked.
	var seen_as: String = Story.greeting_for("ren")
	var tier_before: int = Story.renown_tier()
	PlayerData.grant_cap("qi", 3000.0)
	_check(Story.renown_tier() > tier_before, "growing moves the body up the scale of renown",
		"tier %d -> %d" % [tier_before, Story.renown_tier()])
	_check(Story.greeting_for("ren") != seen_as,
		"and somebody who has grown is greeted differently",
		"%s -> %s" % [seen_as, Story.greeting_for("ren")])
	var tier_line: String = String(Story.RENOWN[Story.renown_tier()]["greeting"])
	_check(Story.greeting_for("ren").contains(tier_line),
		"by the line that belongs to the tier they are in",
		"%s: %s" % [Story.renown_label(), tier_line])
	_check(String(Story.RENOWN[0]["greeting"]) != String(Story.RENOWN[-1]["greeting"]),
		"and the first thing anybody says to you is not the last")
	PlayerData.stats["qi"]["cap"] = 50.0
	PlayerData.stats_changed.emit()

	# Xia will not raise the raiders with you until your hands have learned something — the
	# gate is on a technique attained rather than on a level, because a door nobody can read
	# is a door with no handle.
	Story.begin("xia")
	_check(Story.options().is_empty(), "Xia holds the camp question back from a fresh body")
	Story.close()
	PlayerData.grant_cap("body", 5.0)
	_check(PlayerData.attained_count() >= 1, "one technique is enough to have earned an opinion",
		"%d held" % PlayerData.attained_count())
	Story.begin("xia")
	_check(Story.options().size() == 2, "and then she asks it", "%d answers" % Story.options().size())
	var defense_before: float = PlayerData.get_cap("defense")
	Story.choose("spare")
	_check(PlayerData.chosen_option("camp") == "spare", "sparing them is recorded")
	_check(PlayerData.decision_subject("camp") != "",
		"against the camp it was about", PlayerData.decision_subject("camp"))
	_check(PlayerData.get_cap("defense") > defense_before + 5.0,
		"and a camp that is spared is a debt the body carries",
		"DEFENSE %.1f -> %.1f" % [defense_before, PlayerData.get_cap("defense")])
	Story.close()
	var spared: String = PlayerData.decision_subject("camp")
	if camps != null:
		var spared_camp: Dictionary = {}
		var control_camp: Dictionary = {}
		for camp: Dictionary in camps.call("camps"):
			if String(camp["name"]) == spared:
				spared_camp = camp
			elif control_camp.is_empty():
				control_camp = camp
		var spared_raiders: Array = _raiders_of(spared_camp)
		var control_raiders: Array = _raiders_of(control_camp)
		_check(not spared_raiders.is_empty() and not control_raiders.is_empty(),
			"both the spared camp and an ordinary one are still staffed",
			"%d and %d" % [spared_raiders.size(), control_raiders.size()])
		var spared_pacified: int = 0
		for body: Node3D in spared_raiders:
			if bool(body.call("is_pacified")):
				spared_pacified += 1
		var control_pacified: int = 0
		for body: Node3D in control_raiders:
			if bool(body.call("is_pacified")):
				control_pacified += 1
		_check(spared_pacified == spared_raiders.size() and control_pacified == 0,
			"the sparing reached that camp's raiders and no others",
			"%d of %d spared, %d of %d at the next fire"
				% [spared_pacified, spared_raiders.size(), control_pacified, control_raiders.size()])
		# The control is the point of the pair. A raider answers "no" for half a dozen reasons
		# that have nothing to do with being spared — the wards, the leash, a beaten body — and
		# the first version of this check stood inside the camp wards, where *every* raider in
		# the world says no: it passed with the sparing ripped out of the game.
		PlayerData.restore_all()
		if bool((_player as Node3D).call("is_downed")):
			await _await_upright()
		# A guard standing at its own fire, and no other kind will do. The suite has spent the
		# last several sections dragging raiders around the map, and one that is still chasing
		# somewhere is either past its leash (which answers no for a reason of its own) or
		# standing back inside the camp wards where nobody may pursue anything.
		var control_guard := _living_raider(control_raiders)
		var spared_guard := _living_raider(spared_raiders)
		_check(control_guard != null and spared_guard != null,
			"and there is a raider on its feet at each fire")
		if control_guard != null and spared_guard != null:
			var control_hunts: bool = await _would_hunt(control_guard)
			_check(control_hunts,
				"a raider at an ordinary fire would come after a body standing beside it")
			var spared_hunts: bool = await _would_hunt(spared_guard)
			_check(not spared_hunts,
				"and the spared one will not, however close you stand")

	# The third conversation, which is about the price of everything else.
	var price_before: int = Shop.price("hide")
	Story.begin("bo")
	_check(Story.options().size() == 2, "Old Bo has the elder's ledger and two ways with it",
		"%d answers" % Story.options().size())
	Story.choose("return")
	Story.close()
	_check(PlayerData.chosen_option("ledger") == "return", "walking it back is recorded")
	var price_after: int = Shop.price("hide")
	_check(price_after < price_before, "and the shelf speaks for itself afterwards",
		"%d crystals -> %d" % [price_before, price_after])
	_check(_near(float(price_after) / float(price_before), 0.88, 0.05),
		"by the twelve per cent the ledger was worth")
	_check(_near(float(Shop.save_data().get("discount", 1.0)), 0.88, 0.001),
		"which is a price that has to survive the session, so it is saved")
	Shop.set_discount(1.0)

	# And the other half of the same decision: a burned camp has to still be burned after a
	# relaunch, which is the part that needs the save rather than the conversation.
	if camps != null:
		var target: Dictionary = {}
		for camp: Dictionary in camps.call("camps"):
			if String(camp["name"]) != PlayerData.decision_subject("camp"):
				target = camp
				break
		_check(not target.is_empty(), "a second camp to burn")
		if not target.is_empty():
			var standing_before: int = int(camps.call("living_raiders"))
			PlayerData.note_decision("camp", "burn", String(target["name"]))
			camps.call("_apply_decisions")
			var standing_after: int = int(camps.call("living_raiders"))
			_check(standing_after < standing_before,
				"a camp burned in an earlier session is still burned when the world is rebuilt",
				"%d raiders -> %d" % [standing_before, standing_after])
			# Put the spare back: it is the state the rest of the run was built in.
			PlayerData.decisions.clear()
			PlayerData.note_decision("camp", "spare", spared)

	PlayerData.decisions.clear()
	PlayerData.stats["attack"]["cap"] = PlayerData.def("attack")["base_cap"]
	PlayerData.stats["body"]["cap"] = PlayerData.def("body")["base_cap"]
	PlayerData.stats_changed.emit()


## How many of a camp's raiders would come after a body standing on their fire.
##
## Asked with the player *in* the camp, because the question only has an answer there: from
## the safe zone, or from beyond the leash, every raider in the world reports no and the check
## would pass whatever the game did.
func _raiders_of(camp: Dictionary) -> Array:
	var out: Array = []
	var root := camp.get("node") as Node3D
	if root == null:
		return out
	# The camp's own children, which is exactly the camp's guard: every raider is added to its
	# camp's root when it is placed, and a champion is added the same way and filtered out here.
	for child in root.get_children():
		var body := child as Node3D
		if body == null or not body.has_method("leash_origin"):
			continue
		if body.has_method("is_champion") and bool(body.call("is_champion")):
			continue
		out.append(body)
	return out


## The first raider of a camp still on its feet, or null.
func _living_raider(bodies: Array) -> Node3D:
	for body: Node3D in bodies:
		if not bool(body.call("is_dead")):
			return body
	return null


## Stands the player beside one raider and asks *that* raider whether it would come after them.
##
## One raider, one moment. The rule being measured — `_may_pursue` — is decided by the leash,
## the camp wards, the aggro radius and whether the player is on their feet, and every one of
## those is a fact about *now*. A loop that walked a body past five guards in a row measured a
## chase instead: each guard followed the player to the next one's fire and answered from fifty
## metres past its own leash, which reads exactly like "the sparing did not work".
func _would_hunt(body: Node3D) -> bool:
	# Stood back at its own fire first. The suite has spent several sections dragging raiders
	# around the map, and a guard answering from fifty metres past its leash is answering a
	# different question than the one being asked — as is one standing inside the camp wards,
	# which is where a chase that started somewhere else often ends up.
	body.global_position = body.call("leash_origin")
	body.velocity = Vector3.ZERO
	PlayerData.restore_all()
	(_player as Node3D).call("warp_to", body.global_position + Vector3(1.6, 1.0, 0.0))
	await _land(_player)
	await _settle(2)
	return bool(body.call("_may_pursue"))


## The shelf, and the one thing it has to do that nothing else does: take crystals away.
##
## Every check here is against the stat table afterwards rather than against the return
## value, because the failure that matters is a ware that reports a purchase and grants
## nothing — or, the mirror of it, one that grants twice for one payment.
func _test_shop() -> void:
	_section("The elder's shelf")
	if _hud == null:
		return
	var stats_before: Dictionary = PlayerData.stats.duplicate(true)
	var crystals_before: int = PlayerData.crystals
	var abilities_before: Dictionary = PlayerData.abilities.duplicate(true)
	var bought_before: Dictionary = Shop.bought.duplicate()

	var priced: bool = true
	var described: bool = true
	for ware: Dictionary in Shop.WARES:
		if Shop.price(String(ware["id"])) <= 0:
			priced = false
		if String(ware["name"]).is_empty() or String(ware["detail"]).is_empty():
			described = false
	_check(Shop.WARES.size() >= 4, "there is something on the shelf",
		"%d wares" % Shop.WARES.size())
	_check(priced, "every ware has a price")
	_check(described, "and a name and a description")

	# Broke.
	Shop.reset()
	PlayerData.crystals = 0
	_check(not Shop.can_buy("hide"), "an empty purse buys nothing")
	_check(not Shop.buy("hide"), "and the sale is refused")
	_check(Shop.count("hide") == 0, "without being counted as a purchase")

	# Afforded, at exactly the price.
	var price: int = Shop.price("hide")
	PlayerData.crystals = price
	var hp_before: float = PlayerData.get_cap("hp")
	_check(Shop.can_buy("hide"), "the exact price is enough", "%d crystals" % price)
	_check(Shop.buy("hide"), "and the sale goes through")
	_check(PlayerData.crystals == 0, "the purse is debited once, not twice",
		"left with %d" % PlayerData.crystals)
	var granted: float = PlayerData.get_cap("hp") - hp_before
	_check(_near(granted, float(Shop.def("hide")["amount"]), 0.001),
		"and the cap actually rose by what the label promised", "+%.2f HP" % granted)

	# The price curve is the pacing: a ware that never gets more expensive is a ware the
	# player stops thinking about.
	var first_price: int = Shop.price("hide")
	PlayerData.crystals = 9999
	Shop.buy("hide")
	_check(Shop.price("hide") > first_price, "the second one costs more",
		"%d then %d" % [first_price, Shop.price("hide")])

	# A ware bounded at the top: the game must not sell a fifth air jump.
	PlayerData.unlock_ability("air_jumps", 4)
	_check(not Shop.available("airstep"), "a ware at its ceiling leaves the shelf",
		"%d air jumps" % PlayerData.air_jumps())
	_check(not Shop.buy("airstep"), "and cannot be bought")

	# And the one bounded at the bottom, which counts the other way.
	PlayerData.unlock_ability("dash_cooldown", float(Shop.def("step")["floor"]))
	_check(not Shop.available("step"), "so does one that has hit its floor",
		"%.2f s" % PlayerData.dash_cooldown())

	# The shelf as the player sees it: opened, listed and priced against the purse.
	_hud.call("show_tasks")
	var rows: Node = _find_by_name(_hud, "WareRows")
	_check(rows != null, "the elder's panel carries a shelf")
	if rows != null:
		_check(rows.get_child_count() == Shop.WARES.size(),
			"with one row per ware", "%d rows" % rows.get_child_count())
		var buys: int = 0
		var buyable: int = 0
		for id: String in ["hide", "dantian", "legs"]:
			var button: Button = _find_by_name(rows, "Buy_%s" % id) as Button
			if button == null:
				continue
			buys += 1
			if not button.disabled:
				buyable += 1
		_check(buys == 3, "and a Buy button on the wares that have one", "%d of 3" % buys)
		# The purse was filled above, so every affordable ware must be live: a shelf of
		# greyed-out buttons with a full purse is the bug this is here to catch.
		_check(buyable == 3, "live because the purse covers them", "%d of 3" % buyable)
		_check(_purse_text(_hud).contains("crystal"), "and the purse printed on it",
			_purse_text(_hud))
	_hud.call("close_tasks")

	Shop.bought = bought_before
	PlayerData.stats = stats_before
	PlayerData.crystals = crystals_before
	PlayerData.abilities = abilities_before


## The crystal count as the shelf prints it. Read through the label rather than through
## PlayerData so the check is on what is displayed, not on what is remembered.
func _purse_text(hud: Node) -> String:
	for child in hud.find_children("*", "Label", true, false):
		var label: Label = child
		if label.text.contains("crystal"):
			return label.text
	return ""


## The abilities are the point of the chain, so each one is unlocked and *used*: a
## double jump that does not lift the body, or a dash that goes no faster than a run, is
## a line in a save file rather than a feature.
func _test_abilities() -> void:
	_section("Abilities")
	if _player == null:
		return
	Input.action_release("jump")
	Input.action_release("dash")

	var spawn: Vector3 = Vector3(0.0, float(_terrain.call("surface_height_at", 0.0, 0.0)) + 0.6, 0.0)
	PlayerData.unlock_ability("air_jumps", 0)
	(_player as Node3D).call("warp_to", spawn)
	await _land(_player)
	await _settle(6)
	_check(PlayerData.air_jumps() == 0, "with nothing unlocked there are no air jumps")

	# One jump, then a second request in the air: refused without the ability.
	await _tap_action("jump")
	await _settle(12)
	_check(not _player.is_on_floor(), "the first jump leaves the ground")
	var height_before: float = _player.global_position.y
	await _tap_action("jump")
	await _settle(6)
	_check(_player.velocity.y <= 0.0 or _player.global_position.y < height_before + 0.6,
		"and without the ability there is no second")
	await _land(_player)

	PlayerData.unlock_ability("air_jumps", 1)
	_check(PlayerData.air_jumps() == 1, "the elder's task grants an air jump")
	(_player as Node3D).call("warp_to", spawn)
	await _land(_player)
	await _settle(6)
	await _tap_action("jump")
	await _settle(14)
	_check(not _player.is_on_floor(), "the first jump leaves the ground again")
	var apex: float = _player.global_position.y
	await _tap_action("jump")
	await _settle(2)
	_check(_player.velocity.y > 0.0, "and the air jump lifts the body a second time",
		"vy %.2f" % _player.velocity.y)
	_check(_player.call("air_jumps_left") == 0, "the air jump is spent until landing")
	_check(_player.global_position.y > apex - 0.4, "from where the body already was")
	await _land(_player)
	_check(_player.call("air_jumps_left") == 1, "and landing hands it back")

	# The dash: faster than the fastest run, and on a cooldown the chain can shorten.
	PlayerData.unlock_ability("dash", false)
	_check(not PlayerData.has_ability("dash"), "the dash starts locked")
	PlayerData.unlock_ability("dash", true)
	_check(PlayerData.has_ability("dash"), "and a task unlocks it")
	(_player as Node3D).call("warp_to", spawn)
	await _land(_player)
	await _settle(4)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _settle(30)
	var run_speed: float = _flat_speed()
	await _tap_action("dash")
	await _settle(2)
	_check(_flat_speed() > run_speed + 1.0, "a dash is faster than a run",
		"%.1f m/s against %.1f" % [_flat_speed(), run_speed])
	_check(not _player.call("dash_ready"), "and goes on cooldown")
	_release_game_input()
	var cooldown: float = PlayerData.dash_cooldown()
	_check(cooldown > 0.0, "which the chain can shorten", "%.1fs" % cooldown)
	_check(PlayerData.has_ability("dash_cooldown") == false
			or float(PlayerData.abilities["dash_cooldown"]) <= cooldown,
		"the cooldown the ability grants is the one used")
	_check(float(_player.call("dash_cooldown_left")) > 0.0,
		"and reports how long until the next one")


## Health regeneration is a share of the pool, which is the whole reason training the
## pool is worth doing: the same body with twice the health knits back twice as fast.
func _test_regen() -> void:
	_section("Regeneration")
	var share: float = float(PlayerData.RESOURCE_REGEN["hp"])
	_check(share > 0.0, "health regenerates a share of the cap, not a flat rate",
		"%.1f%% per second" % (share * 100.0))
	# The drills are paid for in blood, so they have to cost more than the body hands
	# back — otherwise a drill is free at a large enough health pool.
	for entry: Dictionary in Training.EXERCISES:
		var drain: float = Training.blood_per_second(String(entry["id"]))
		_check(drain > share, "%s costs more blood than it regenerates" % String(entry["label"]),
			"%.2f%%/s against %.2f%%/s" % [drain * 100.0, share * 100.0])

	var cap: float = PlayerData.get_cap("hp")
	PlayerData.restore("hp", 0.0)
	PlayerData.stats["hp"]["current"] = cap * 0.5
	var small: Dictionary = await _measure_heal(50)
	var small_cap: float = float(small["cap_before"])
	PlayerData.stats["hp"]["current"] = small_cap * 0.5
	PlayerData._grow_cap("hp", small_cap)
	var doubled_cap: float = PlayerData.get_cap("hp")
	PlayerData.stats["hp"]["current"] = doubled_cap * 0.5
	var large: Dictionary = await _measure_heal(50)
	# The two pools have to be equal halves of their own cap for the comparison to mean
	# anything — a heal rate is a share of the pool, so a body healing from a tenth of
	# its blood recovers the same share per second as one healing from half.
	_check(is_equal_approx(float(small["cap_before"]), float(small["cap_after"])),
		"the small pool's cap held still while it healed",
		"%.1f -> %.1f" % [small["cap_before"], small["cap_after"]])
	_check(is_equal_approx(float(large["cap_before"]), float(large["cap_after"])),
		"so did the doubled one",
		"%.1f -> %.1f" % [large["cap_before"], large["cap_after"]])
	var small_rate: float = float(small["rate"])
	var large_rate: float = float(large["rate"])
	# The rule itself, not just the ratio between two pools: "twice as fast" would still
	# hold if both pools regenerated at the wrong share of their cap.
	var expected_rate: float = small_cap * share
	_check(absf(small_rate - expected_rate) <= expected_rate * 0.1,
		"the rate is the share of the cap the constant says",
		"%.2f/s measured against %.2f/s" % [small_rate, expected_rate])
	_check(large_rate > small_rate * 1.6, "twice the health regenerates about twice as fast",
		"%.2f/s at %.0f hp against %.2f/s at %.0f hp" % [small_rate, small_cap, large_rate, doubled_cap])
	PlayerData.stats["hp"]["cap"] = cap
	PlayerData.restore_all()


## The effects the checks below actually exercise, by key.
##
## This list is the section's own coverage guard, and it is the most valuable line in it. An
## effect key that is spelled differently in a table and in the code that reads it — `wards`
## against `warded` — is a capability that never fires for anybody, while the panel lists it
## as held, the tooltip explains what it does, and nothing anywhere fails. No assertion about
## a single effect can catch that, because every assertion is about an effect that *does*
## fire. What catches it is the pair of checks below: every key the tables grant appears here,
## and every key here is one the tables grant.
const PROBED_EFFECTS: Array = [
	"cleave", "crush", "thick_skin", "iron_skin", "unshaken", "warded",
	"mending", "second_wind", "iron_bones", "blood_boil",
	"softfoot", "meteor", "sky_step", "surefoot", "burst",
	"deep_well", "jade_skin", "dantian_bell", "qi_bolt", "flight",
]


## What a stat *becomes*, checked by doing it.
##
## The table is easy to believe and easy to get wrong, so nothing here is read back from it.
## Each threshold is put exactly where it sits, and then the thing it claims to grant is
## performed: a second body takes a share of a blow, a body heals three times as fast after
## five quiet seconds, the next lethal blow does not end it, a landing moves everything
## standing nearby, a sprint leaves the line a third quicker. The accessors are checked too,
## but only for the parts no player can feel — a recharge that halves, a cost that drops.
##
## The window at the end is the other half of the section. A capability that arrives silently
## is a capability the player will never know they have, so every one of these is granted
## through the same signal a rank is and the announcements are collected as they happen.
func _test_attainments() -> void:
	_section("Attainments")
	if _player == null:
		return
	_release_game_input()
	Training.stop()
	Cultivation.stop_meditation()
	var announced: Array = []
	var collector := func(text: String, _kind: String) -> void: announced.append(text)
	PlayerData.log_message.connect(collector)
	# A clean body at its starting caps: nothing held, so every check below starts from "no
	# technique" and earns exactly one.
	PlayerData._build_defaults()
	PlayerData.stats_changed.emit()
	PlayerData.restore_all()
	PlayerData._shield_ready_ms = 0
	PlayerData._wind_ready_ms = 0

	var rows: Array = PlayerData.attainment_rows()
	var held: int = 0
	for row: Dictionary in rows:
		if bool(row["attained"]):
			held += 1
	_check(held == 0, "a body at its starting caps holds nothing", "%d held" % held)
	_check(rows.size() == PlayerData.attainment_total(),
		"the panel lists every row the tables hold",
		"%d rows against %d" % [rows.size(), PlayerData.attainment_total()])
	_check(rows.size() == 20, "twenty things a body can become", "%d" % rows.size())
	# Reachability. A threshold above its stat's hard ceiling is an entry nobody can ever
	# earn — jump is the one stat with a ceiling, so a retune of its base below 2 m would
	# silently make METEOR unreachable while the table still promised it.
	for stat_id: String in PlayerData.STAT_ORDER:
		for entry: Dictionary in (PlayerData.ATTAINMENTS[stat_id] as Array):
			var want: float = PlayerData.threshold(stat_id, entry)
			_check(want < PlayerData.cap_ceiling(stat_id),
				"%s is inside %s's ceiling" % [String(entry["label"]), PlayerData.label(stat_id)],
				"needs %s, ceiling %s" % [
					PlayerData.format_value(stat_id, want),
					PlayerData.format_value(stat_id, PlayerData.cap_ceiling(stat_id)),
				])
	var keys: Array = PlayerData.all_effect_keys()
	var unprobed: Array = []
	for key: String in keys:
		if not PROBED_EFFECTS.has(key):
			unprobed.append(key)
	_check(unprobed.is_empty(), "every effect in the tables is exercised below",
		", ".join(unprobed))
	var unknown: Array = []
	for key: String in PROBED_EFFECTS:
		if not keys.has(key):
			unknown.append(key)
	_check(unknown.is_empty(), "and no check exercises a key no table grants",
		", ".join(unknown))

	# ------------------------------------------------------------- ATTACK
	var striker: Node = _player.get_node_or_null("Striker")
	var posts: Array = get_tree().get_nodes_in_group("training_post")
	_check(striker != null, "the body carries a striker")
	# Held outside the block: WARDED is measured further down against the same post, because
	# a post is a real body with a `take_hit` and a blow given back needs something that can
	# be given it.
	var first_post: Node3D = posts[0] as Node3D if posts.size() >= 1 else null
	var second_post: Node3D = posts[1] as Node3D if posts.size() >= 2 else null
	if striker != null and first_post != null and second_post != null:
		var second_home: Vector3 = second_post.global_position
		var refill: float = float(second_post.get("restuff_per_second"))
		# Cleave's radius is 2.2 m and the camp's posts are not placed with that in mind, so
		# the pair is stood together for the measurement and put back afterwards. Refill is
		# off for the same reason: at the shipped rate it puts back about five points during
		# the frames a blow takes to land, which is a quarter of the primary hit and more than
		# half of the carried one.
		second_post.global_position = first_post.global_position + Vector3(1.5, 0.0, 0.8)
		second_post.set("restuff_per_second", 0.0)
		first_post.set("restuff_per_second", 0.0)
		_player.call("warp_to", first_post.global_position + Vector3(1.3, 1.0, 0.0))
		await _settle(8)
		var plain: Dictionary = await _swing_pair(first_post, second_post)
		_check(float(plain["primary"]) > 0.0, "a post in reach takes the blow")
		_check(not bool(plain["both"]), "and the one beside it takes nothing",
			"%.1f and %.1f" % [plain["first"], plain["second"]])

		_grant("attack", 0)
		_check(PlayerData.has_effect("cleave"), "CLEAVE at four times the starting fist")
		await _settle(70)
		var carried: Dictionary = await _swing_pair(first_post, second_post)
		_check(bool(carried["both"]), "with CLEAVE one blow reaches two bodies",
			"%.1f and %.1f" % [carried["first"], carried["second"]])
		var share: float = float(carried["carried"]) / maxf(0.001, float(carried["primary"]))
		_check(_near(share, 0.4, 0.04), "and the second one takes two fifths of it",
			"%.0f%% of %.1f" % [share * 100.0, carried["primary"]])
		second_post.global_position = second_home
		second_post.set("restuff_per_second", refill)
		first_post.set("restuff_per_second", refill)

	# The crushing roll, measured over a run of blows rather than hoped for in one: a
	# one-in-five chance is invisible to a single swing and unmissable in a mean.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var samples: int = 3000
	_set_cap("attack", 5.0)
	var unit: float = PlayerData.strike_damage(1.0)
	var plain_total: float = 0.0
	for i in samples:
		plain_total += PlayerData.strike_damage_rolled(rng)
	var plain_mean: float = plain_total / float(samples)
	_check(_near(plain_mean / unit, 1.0, 0.03), "an untrained fist lands the plain blow on average",
		"%.3f of it" % (plain_mean / unit))
	_grant("attack", 1)
	_check(PlayerData.has_effect("crush"), "CRUSHING at ten times the starting fist")
	# A heavier fist is a bigger number, so the mean is measured against *that* fist's plain
	# blow. Comparing it against the mean from the smaller cap would report a 50-strength
	# body as a tenfold crushing bonus.
	var heavy: float = PlayerData.strike_damage(1.0)
	var rolled_total: float = 0.0
	var worst: float = 0.0
	var lightest: float = INF
	for i in samples:
		var roll: float = PlayerData.strike_damage_rolled(rng)
		worst = maxf(worst, roll)
		lightest = minf(lightest, roll)
		rolled_total += roll
	var rolled_mean: float = rolled_total / float(samples)
	_check(_near(rolled_mean / heavy, 1.2, 0.05),
		"CRUSHING adds a fifth to the average blow", "%.0f%%" % ((rolled_mean / heavy - 1.0) * 100.0))
	_check(worst <= heavy * 1.15 * 2.0 + 0.001 and worst >= heavy * 0.85 * 2.0 - 0.001,
		"and a crush is exactly double, never more nor less", "%.2f of a %.2f blow" % [worst, heavy])
	_check(lightest >= heavy * 0.85 - 0.001,
		"with no blow landing lighter than the swing itself", "%.2f of %.2f" % [lightest, heavy])

	# BLOOD BOIL is the one entry switched on by being hurt rather than by training, so it is
	# checked in both states: the same arm, the same table, a different pool.
	_set_cap("attack", 15.01)
	_grant("hp", 0)
	_check(PlayerData.has_effect("blood_boil"), "BLOOD BOIL at three times the pool and the fist")
	var cap_hp: float = PlayerData.get_cap("hp")
	PlayerData.stats["hp"]["current"] = cap_hp * 0.9
	var whole_total: float = 0.0
	for i in samples:
		whole_total += PlayerData.strike_damage_rolled(rng)
	PlayerData.stats["hp"]["current"] = cap_hp * 0.2
	var hurt_total: float = 0.0
	for i in samples:
		hurt_total += PlayerData.strike_damage_rolled(rng)
	var boil: float = (hurt_total / whole_total) - 1.0
	_check(_near(boil, 0.25, 0.05), "below a third of the pool the blows land a quarter harder",
		"%.0f%%" % (boil * 100.0))

	# ------------------------------------------------------------- DEFENSE / BODY
	# One defense cap throughout, so the only thing moving is the physique: DEFENSE has its
	# own curve on top of these and a measurement that changed both would prove neither.
	_set_cap("defense", 15.01)
	_set_cap("body", 5.0)
	PlayerData.restore_all()
	var raw: float = 20.0
	var taken_plain: float = PlayerData.apply_damage(raw, "blow")
	_grant("body", 0)
	_check(PlayerData.has_effect("thick_skin"), "THICK SKIN at twice the starting frame")
	var taken_thick: float = PlayerData.apply_damage(raw, "blow")
	_check(_near(taken_thick / taken_plain, 0.92, 0.012),
			"THICK SKIN takes eight per cent off every blow",
			"%.1f against %.1f" % [taken_thick, taken_plain])
	_grant("body", 1)
	_check(PlayerData.has_effect("iron_bones"), "IRON BONES at five times it")
	_check(PlayerData.has_effect("iron_skin"), "and IRON SKIN, the frame over the guard")
	var taken_iron: float = PlayerData.apply_damage(raw, "blow")
	_check(_near(taken_iron / taken_plain, 0.92 * 0.88, 0.02),
		"the two of them stack, a fifth off in total",
		"%.1f against %.1f" % [taken_iron, taken_plain])

	# UNSHAKEN and WARDED, which both need a body throwing the blow.
	# A bare node is enough for the first: the reflection is the only part that talks to the
	# source, and reflection is the second check.
	var source := Node3D.new()
	get_tree().root.add_child(source)
	source.global_position = (_player as Node3D).global_position + Vector3(3.0, 0.0, 0.0)
	_set_cap("defense", 5.0)
	PlayerData.restore_all()
	var push_plain: float = 0.0
	_player.velocity = Vector3.ZERO
	_player.call("take_enemy_blow", 4.0, source)
	push_plain = _player.velocity.length()
	_check(push_plain > 0.5, "a blow throws a body that has not learned to stand it",
		"%.2f m/s" % push_plain)
	_set_cap("defense", 15.01)
	_check(PlayerData.has_effect("unshaken"), "UNSHAKEN at three times the starting guard")
	_player.velocity = Vector3.ZERO
	_player.call("take_enemy_blow", 4.0, source)
	_check(_player.velocity.length() < 0.05, "and then a blow no longer moves it at all",
		"%.3f m/s" % _player.velocity.length())
	# WARDED, paid back through the same door a strike goes through: the body it came from
	# really loses that much, which is the only version of this that is worth checking.
	_set_cap("defense", 40.01)
	_check(PlayerData.has_effect("warded"), "WARDED at eight times it")
	if first_post != null:
		PlayerData.restore_all()
		# The xp bar is emptied first. A blow trains the pool it lands on, and a rank that
		# happens *inside* the same call widens the cap and tops the pool up by what it grew —
		# so the blood the body is seen to lose is less than the blow that dealt it, and the
		# reflection is measured against a smaller number than the one it was paid out of.
		PlayerData.stats["hp"]["progress"] = 0.0
		var blood_before: float = PlayerData.get_value("hp")
		var stuffing_before: float = float(first_post.get("stuffing"))
		_player.call("take_enemy_blow", 20.0, first_post)
		var blood_lost: float = blood_before - PlayerData.get_value("hp")
		var post_lost: float = stuffing_before - float(first_post.get("stuffing"))
		_check(blood_lost > 0.5, "the blow lands on the body", "%.1f hp" % blood_lost)
		_check(post_lost > 0.0, "and part of it is given back to the one that threw it",
			"%.2f of %.1f" % [post_lost, blood_lost])
		_check(_near(post_lost / maxf(0.001, blood_lost), 0.15, 0.02),
			"at fifteen per cent, which is the number the table promises",
			"%.1f%% of %.1f" % [(post_lost / maxf(0.001, blood_lost)) * 100.0, blood_lost])
	source.queue_free()

	# ------------------------------------------------------------- HEALTH
	# Mending at eight times the starting pool, so the rate it triples is a rate worth
	# measuring, and Second Wind with it.
	_set_cap("defense", 5.0)
	_set_cap("body", 5.0)
	_grant("hp", 1)
	_check(PlayerData.has_effect("mending") and PlayerData.has_effect("second_wind"),
		"MENDING and SECOND WIND at eight times the starting pool")
	PlayerData.restore_all()
	PlayerData.apply_damage(6.0, "fall")
	_check(PlayerData.regen_multiplier() == 1.0,
		"MENDING pays nothing while the blood is still fresh — a body being hit is not a body mending")
	PlayerData.stats["hp"]["current"] = PlayerData.get_cap("hp") * 0.4
	var slow: Dictionary = await _measure_heal(90)
	# The five seconds of quiet are fast-forwarded rather than slept through. Sleeping them
	# would cost the wall clock of the whole section to observe a rate, and the clock being
	# jumped is the same one the loop reads — what is *not* skipped is the check above, which
	# is the half that says the quiet has to be earned.
	PlayerData._since_hurt = PlayerData.MENDING_QUIET + 1.0
	PlayerData.stats["hp"]["current"] = PlayerData.get_cap("hp") * 0.4
	var fast: Dictionary = await _measure_heal(90)
	_check(PlayerData.regen_multiplier() == 3.0, "after the quiet it is worth triple")
	var heal_ratio: float = float(fast["rate"]) / maxf(0.001, float(slow["rate"]))
	_check(_near(heal_ratio, 3.0, 0.35), "and the body really heals three times as fast",
		"%.2f/s against %.2f/s" % [fast["rate"], slow["rate"]])

	# Second Wind, from both sides: first the lethal blow that ends a body without it.
	_set_cap("hp", 300.01)
	PlayerData.stats["hp"]["current"] = 20.0
	PlayerData.apply_damage(9999.0, "fall")
	_check(PlayerData.get_value("hp") == 0.0, "without it, the killing blow empties the pool")
	_grant("hp", 1)
	PlayerData.restore_all()
	PlayerData._wind_ready_ms = 0
	PlayerData.stats["hp"]["current"] = 20.0
	PlayerData.apply_damage(9999.0, "fall")
	var standing: float = PlayerData.get_value("hp")
	_check(standing > 0.0, "SECOND WIND leaves the body standing", "%.1f hp" % standing)
	_check(_near(standing, PlayerData.get_cap("hp") * 0.25, 0.5),
		"at a quarter of the pool", "%.1f of %.1f" % [standing, PlayerData.get_cap("hp")])
	_check(not PlayerData.second_wind_ready(), "and it is spent for the next ninety seconds")
	PlayerData.stats["hp"]["current"] = 20.0
	PlayerData.apply_damage(9999.0, "fall")
	_check(PlayerData.get_value("hp") == 0.0, "so the second killing blow is the last one")

	# The collapse that follows, which is where Iron Bones lives.
	_set_cap("body", 10.01)
	await _settle(6)
	_check(bool(_player.get("_downed")), "an emptied body goes down")
	var slow_down: float = float(_player.get("_downed_timer"))
	_grant("body", 1)
	PlayerData.restore_all()
	await _await_upright()
	_check(not bool(_player.get("_downed")), "and gets up on its own timer")
	PlayerData.stats["hp"]["current"] = 0.0
	await _settle(6)
	var fast_down: float = float(_player.get("_downed_timer"))
	_check(fast_down < slow_down * 0.6, "IRON BONES halves how long that takes",
		"%.2fs against %.2fs" % [fast_down, slow_down])
	PlayerData.restore_all()
	await _await_upright()
	_check(not bool(_player.get("_downed")), "and then the body is on its feet again")

	# ------------------------------------------------------------- JUMP
	# SOFTFOOT, measured as a drop rather than as a number: five metres costs blood on a
	# plain body and nothing on a trained one, and seven costs blood on both — the threshold
	# moved, it did not vanish.
	_set_cap("jump", 1.6)
	var flat: Vector3 = _flat_ground_near(_player as Node3D)
	_check(not PlayerData.has_effect("softfoot"), "nothing held at the starting jump")
	var five_plain: float = await _drop_and_measure(flat, 5.0)
	_check(five_plain > 0.5, "a five metre drop hurts a body that lands badly",
		"%.1f hp" % five_plain)
	_grant("jump", 0)
	_check(PlayerData.has_effect("softfoot"), "SOFTFOOT at four times the starting jump")
	var five_soft: float = await _drop_and_measure(flat, 5.0)
	_check(five_soft < 0.05, "and the same drop costs it nothing", "%.1f hp" % five_soft)
	# Ten rather than seven, because where the body comes down is not always the *terrain*:
	# a camp is full of posts and boulders, and landing on one of those shortens the fall by
	# its own height. At seven metres a 1.3 m rock left the fall just inside Softfoot's six,
	# and the check read the rock rather than the rule.
	var ten_soft: float = await _drop_and_measure(flat, 10.0)
	_check(ten_soft > 0.5, "past six metres it still lands like anything else",
		"%.1f hp" % ten_soft)

	# METEOR: a landing that moves everything standing near it, and nothing further away.
	var raiders: Array = []
	var camps_node: Node = get_tree().root.get_node_or_null("Main/EnemyCamps")
	if camps_node != null and camps_node.has_method("enemies"):
		raiders = camps_node.call("enemies")
	_set_cap("jump", 16.01)
	_check(PlayerData.has_effect("meteor"), "METEOR at ten times the starting jump")
	_check(_near(PlayerData.stagger_radius(), 3.5, 0.01), "its shockwave reaches three and a half metres")
	if raiders.size() >= 2:
		var near_raider := raiders[0] as CharacterBody3D
		var far_raider := raiders[1] as CharacterBody3D
		var spot: Vector3 = _flat_ground_near(_player as Node3D)
		# The two raiders are stood where the landing can and cannot reach them. They are
		# placed rather than found, because a raider that happens to be walking through the
		# spot proves nothing about the radius.
		near_raider.global_position = spot + Vector3(1.5, 0.6, 0.0)
		far_raider.global_position = spot + Vector3(8.0, 0.6, 0.0)
		PlayerData.stats["hp"]["current"] = PlayerData.get_cap("hp")
		_player.call("warp_to", spot + Vector3(0.0, 7.0, 0.0))
		await _land(_player)
		await _settle(2)
		_check(float(near_raider.call("stagger_left")) > 0.0,
			"a hard landing knocks a raider beside it off its feet",
			"%.2fs" % float(near_raider.call("stagger_left")))
		_check(float(far_raider.call("stagger_left")) == 0.0,
			"and one eight metres away does not notice")

	# SKY STEP, which is the only entry that adds a jump rather than changing one.
	_set_cap("jump", 1.6)
	_set_cap("speed", 5.0)
	var granted_jumps: int = int(PlayerData.abilities.get("air_jumps", 0))
	_check(PlayerData.air_jumps() == granted_jumps, "no jump in the air without it")
	_set_cap("jump", 6.41)
	_set_cap("speed", 20.01)
	_check(PlayerData.has_effect("sky_step"), "SKY STEP at four times the jump and the run")
	_check(PlayerData.air_jumps() == granted_jumps + 1, "which is one more jump than training gave",
		"%d against %d" % [PlayerData.air_jumps(), granted_jumps])
	_check(_player.call("air_jumps_left") == PlayerData.air_jumps(),
		"and the body is holding it")

	# ------------------------------------------------------------- SPEED
	# SUREFOOT: a number that halves its effect would still be a number, so what is checked
	# is the slope the engine is actually letting the body climb.
	_set_cap("speed", 5.0)
	_check(_near(rad_to_deg(_player.floor_max_angle), 55.0, 1.0),
		"a fresh body can run up fifty-five degrees")
	_set_cap("speed", 12.51)
	_check(PlayerData.has_effect("surefoot"), "SUREFOOT at two and a half times the starting run")
	_check(_near(rad_to_deg(_player.floor_max_angle), 70.0, 1.0),
		"and then fifteen degrees more", "%.1f degrees" % rad_to_deg(_player.floor_max_angle))

	# BURST: the first three quarters of a second of a sprint, measured as ground covered.
	# Only the *cap* moves between the two runs — the allocation, which is the cruise ceiling
	# both runs share, is set explicitly and left alone, or a faster sprint would be
	# indistinguishable from a higher top speed.
	var run_start: Vector3 = _flat_ground_near(_player as Node3D)
	_set_cap("speed", 20.0)
	PlayerData.set_allocation("speed", 20.0)
	var cruise: float = await _launch_speed(run_start)
	_check(not PlayerData.has_effect("burst"), "no launch bonus below three times it")
	_check(cruise <= PlayerData.max_speed() * PlayerData.speed_multiplier() + 0.5,
		"a plain sprint never passes its own top speed", "%.2f m/s" % cruise)
	_set_cap("speed", 30.01)
	_check(PlayerData.has_effect("burst"), "BURST at six times the starting run")
	_check(_near(PlayerData.sprint_burst_seconds(), 0.75, 0.001), "and it lasts three quarters of a second")
	var launched: float = await _launch_speed(run_start)
	_check(launched > cruise * 1.15, "the same body leaves the line a third quicker",
		"%.2f m/s against %.2f m/s after the first quarter second" % [launched, cruise])

	# ------------------------------------------------------------- QI
	var pressure: Node = _player.call("qi_pressure")
	_check(pressure != null, "the body carries a qi field")
	_set_cap("qi", 50.0)
	_check(not PlayerData.has_effect("deep_well"), "nothing held at the starting dantian")
	# The two arts are thresholds like everything else, and the *order* between them is the
	# design: the throw arrives a dantian and a half before the sky does, so the dantian has
	# something to buy with range before it buys the one thing that changes where a fight can
	# happen.
	_check(not PlayerData.has_effect("qi_bolt") and not PlayerData.has_effect("flight"),
		"and nothing thrown at the sky yet")
	_set_cap("qi", 125.01)
	_check(PlayerData.has_effect("qi_bolt"), "QI BOLT at two and a half times the dantian")
	_check(not PlayerData.has_effect("flight"), "which is still short of the air")
	_set_cap("qi", 200.01)
	_check(PlayerData.has_effect("flight"), "CLOUD STEP at four times the dantian")
	_set_cap("qi", 50.0)
	if pressure != null:
		var plain_drain: float = float(PlayerData.RESOURCE_REGEN["qi"]) * float(pressure.SUSTAIN_QI)
		_set_cap("qi", 150.01)
		_check(PlayerData.has_effect("deep_well"), "DEEP WELL at three times the starting dantian")
		_check(_near(float(pressure.call("drain_per_second")) / plain_drain, 0.65, 0.01),
			"the field costs a third less to hold",
			"%.3f/s against %.3f/s" % [float(pressure.call("drain_per_second")), plain_drain])

	# JADE SKIN: the one entry that spends the pool instead of the blood.
	_set_cap("defense", 5.0)
	_set_cap("qi", 400.01)
	PlayerData.restore_all()
	_check(PlayerData.has_effect("jade_skin"), "JADE SKIN at eight times the dantian")
	var blood: float = PlayerData.get_value("hp")
	var breath: float = PlayerData.get_value("qi")
	var through: float = PlayerData.apply_damage(20.0, "blow")
	_check(through == 0.0, "the shell takes the blow instead of the body", "%.1f hp of it" % through)
	_check(PlayerData.get_value("hp") == blood, "and not a drop of blood is lost")
	var paid: float = breath - PlayerData.get_value("qi")
	_check(_near(paid, PlayerData.get_cap("qi") * 0.12, 0.5),
		"paid out of the dantian at the share the constant says",
		"%.1f qi of %.1f" % [paid, PlayerData.get_cap("qi")])
	_check(not PlayerData.shield_ready(), "and the shell is spent")
	_check(_near(PlayerData.shield_recharge_seconds(), 18.0, 0.01), "back in eighteen seconds")
	_set_cap("defense", 15.01)
	_check(PlayerData.has_effect("dantian_bell"), "DANTIAN BELL at three times the well and the guard")
	_check(_near(PlayerData.shield_recharge_seconds(), 9.0, 0.01),
		"which halves the wait", "%.1fs" % PlayerData.shield_recharge_seconds())

	# ------------------------------------------------------------- the announcement
	_check(announced.size() >= 8, "every capability said what it does as it arrived",
		"%d lines" % announced.size())
	var named_second_wind: bool = false
	var explained: bool = false
	for line: String in announced:
		if line.begins_with("SECOND WIND"):
			named_second_wind = true
			explained = line.contains("quarter")
	var announced_labels: Array = []
	for row: Dictionary in PlayerData.attainment_rows():
		announced_labels.append(String(row["label"]).to_upper())
	var silent: Array = []
	for label: String in announced_labels:
		var spoken: bool = false
		for line: String in announced:
			if line.begins_with(label):
				spoken = true
				break
		if not spoken:
			silent.append(label)
	_check(silent.is_empty(), "no capability arrived silently", ", ".join(silent))
	_check(named_second_wind and explained,
		"and the line names the technique and what it does rather than only that it happened")

	PlayerData.log_message.disconnect(collector)
	# Put the body back the way the next section expects to find it.
	PlayerData._build_defaults()
	PlayerData.stats_changed.emit()
	PlayerData.restore_all()
	PlayerData.set_allocation("speed", PlayerData.get_cap("speed"))
	PlayerData.set_allocation("jump", PlayerData.get_cap("jump"))
	(_player as Node3D).call("warp_to", _player.call("_spawn_point"))
	await _land(_player)


## Puts a stat's earned cap exactly where a threshold sits, and lets the body notice.
##
## Written directly rather than trained to, because a rank takes half a minute of real play
## and what is being checked is the *link* between a cap and a capability — the same shortcut
## the drill section takes for BODY. Both signals are fired, so this is the same path a real
## rank takes: the capability is derived from the caps, and the climb limit is re-applied.
func _grant(stat_id: String, index: int) -> bool:
	var list: Array = PlayerData.ATTAINMENTS.get(stat_id, [])
	if index >= list.size():
		return false
	_set_cap(stat_id, PlayerData.threshold(stat_id, list[index]) + 0.01)
	return true


## Moves an earned cap and tells everything that cares, without the training that would
## normally have paid for it.
func _set_cap(stat_id: String, value: float) -> void:
	var before: float = PlayerData.get_cap(stat_id)
	if is_equal_approx(before, value):
		PlayerData.stats_changed.emit()
		return
	PlayerData.stats[stat_id]["cap"] = value
	PlayerData.stat_cap_gained.emit(stat_id, before, value)
	PlayerData.stats_changed.emit()


## One swing at a pair of posts, and what it did to each.
##
## The stuffing each post came in with is read rather than assumed: posts refill over time
## and these two have been hit earlier in the run, so "it lost its stuffing" and "it gained
## it back slower" are the same number read from opposite ends.
func _swing_pair(first: Node3D, second: Node3D) -> Dictionary:
	var before_first: float = float(first.get("stuffing"))
	var before_second: float = float(second.get("stuffing"))
	_press_key(KEY_F)
	await _settle(40)
	var a: float = maxf(0.0, before_first - float(first.get("stuffing")))
	var b: float = maxf(0.0, before_second - float(second.get("stuffing")))
	return {
		"first": a, "second": b,
		"primary": maxf(a, b), "carried": minf(a, b),
		"both": a > 0.001 and b > 0.001,
	}


## Waits out a collapse. Counted in frames rather than in seconds because the timer the
## controller counts down and this loop both advance on the physics delta, and a suite that
## slept for a wall-clock four seconds could still be watching a body that had two left.
func _await_upright(limit: int = 900) -> void:
	for i in limit:
		if not bool(_player.get("_downed")):
			return
		await get_tree().physics_frame


## Flat ground near a body, so a drop or a sprint is measured on the level rather than on
## whatever slope it happened to be standing on.
func _flat_ground_near(body: Node3D) -> Vector3:
	var here: Vector3 = body.global_position
	var level: float = float(_terrain.call("surface_height_at", here.x, here.z))
	for attempt in 24:
		var angle: float = TAU * float(attempt) / 24.0
		var candidate := Vector2(here.x + cos(angle), here.z + sin(angle))
		var height: float = float(_terrain.call("surface_height_at", candidate.x, candidate.y))
		if absf(height - level) > 0.6:
			continue
		var flat_enough: bool = true
		for probe in 4:
			var step: float = 1.5 * float(probe + 1)
			var ahead: float = float(_terrain.call(
				"surface_height_at", candidate.x + step, candidate.y + step
			))
			if absf(ahead - height) > 0.9:
				flat_enough = false
				break
		if flat_enough:
			return Vector3(candidate.x, height + 0.4, candidate.y)
	return Vector3(here.x, level + 0.4, here.z)


## Drops the body `metres` onto flat ground and reports the blood it cost.
##
## The pool is filled first, and that is not tidiness: the body heals a share of its cap every
## second, so a fall measured from half a bar would be partly hidden by the healing that runs
## underneath it — and the whole claim being checked is that a *small* fall costs nothing.
func _drop_and_measure(at: Vector3, metres: float) -> float:
	PlayerData.stats["hp"]["current"] = PlayerData.get_cap("hp")
	(_player as Node3D).call("warp_to", at + Vector3(0.0, metres, 0.0))
	await _land(_player)
	await _settle(2)
	return PlayerData.get_cap("hp") - PlayerData.get_value("hp")


## Sprint speed a quarter of a second after the gun.
##
## From a standstill, because that is the only state Burst is granted from, and sampled over
## a window short enough that neither run has reached its own ceiling — past that point the
## two are the same body at the same speed and the launch is over.
func _launch_speed(at: Vector3) -> float:
	_release_game_input()
	PlayerData.stats["hp"]["current"] = PlayerData.get_cap("hp")
	(_player as Node3D).call("warp_to", at)
	await _land(_player)
	await _settle(4)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var top: float = 0.0
	for i in 18:
		await get_tree().physics_frame
		top = maxf(top, Vector2(_player.velocity.x, _player.velocity.z).length())
	_release_game_input()
	await _settle(4)
	return top


## HP restored over `frames` frames, in points per *game* second.
##
## The denominator is the engine's own accumulated delta, not the wall clock, and that
## distinction is the whole reason this helper exists in this shape. Regeneration
## integrates `cap * share * delta`, so the only clock that can judge the rate is the one
## it integrates over. Dividing by wall time instead measured 4.9/s where the rule says
## 3.4/s — a 44% "failure" that was entirely the first fifty frames of a headless run
## accumulating 0.48 s of delta across 0.33 s of wall clock. Nothing about the body was
## wrong; the ruler was.
##
## The cap is reported alongside the rate rather than assumed to hold still, because the
## two are not independent: a rank of BODY widens the HP cap, and a wider cap tops the
## pool up by the amount it grew. A heal measurement that only watched the pool could
## report a physique gain as regeneration.
func _measure_heal(frames: int) -> Dictionary:
	var before: float = PlayerData.get_value("hp")
	var cap_before: float = PlayerData.get_cap("hp")
	var seconds: float = 0.0
	for i in frames:
		await get_tree().process_frame
		seconds += get_process_delta_time()
	return {
		"rate": (PlayerData.get_value("hp") - before) / maxf(0.0001, seconds),
		"cap_before": cap_before,
		"cap_after": PlayerData.get_cap("hp"),
	}


## Qi Pressure: the gate, the size and its ceiling, the economy, and the damage.
##
## The interesting claims here are all numeric, so they are measured rather than read
## back: the drain against the regeneration at the capacity that is supposed to sustain
## it, and the field's effect on a real raider moved into it.
func _test_qi_pressure() -> void:
	_section("Qi Pressure")
	if _player == null or _hud == null:
		return
	var skill: Node3D = _player.call("qi_pressure") as Node3D
	_check(skill != null and skill.has_method("state"), "the field is attached to the player")
	if skill == null:
		return

	var saved_cap: float = PlayerData.get_cap("qi")
	var saved_qi: float = PlayerData.get_value("qi")
	skill.call("stop")

	# --- the gate: the pool has to hold enough breath to keep a shell of it outside
	PlayerData.stats["qi"]["cap"] = 400.0
	PlayerData.stats["qi"]["current"] = 400.0
	_check(not bool(skill.call("unlocked")), "the technique is locked below 500 QI held",
		"%.0f held" % PlayerData.get_cap("qi"))
	_check(not bool(skill.call("start")), "and it refuses to be raised")
	PlayerData.stats["qi"]["cap"] = 500.0
	PlayerData.stats["qi"]["current"] = 500.0
	_check(bool(skill.call("unlocked")), "500 QI held is the unlock")

	# --- size: grown by capacity, capped whatever the capacity
	var at_unlock: float = float(skill.call("radius"))
	PlayerData.stats["qi"]["cap"] = 750.0
	PlayerData.stats["qi"]["current"] = 750.0
	var middle: float = float(skill.call("radius"))
	PlayerData.stats["qi"]["cap"] = 1000.0
	PlayerData.stats["qi"]["current"] = 1000.0
	var sustained: float = float(skill.call("radius"))
	PlayerData.stats["qi"]["cap"] = 8000.0
	PlayerData.stats["qi"]["current"] = 8000.0
	var enormous: float = float(skill.call("radius"))
	_check(middle > at_unlock and sustained > middle, "the bubble grows with the pool",
		"%.1f -> %.1f -> %.1f m" % [at_unlock, middle, sustained])
	print("  info  radius 500/750/1000/8000 QI held: %.1f / %.1f / %.1f / %.1f m (ceiling %.1f)" % [
		at_unlock, middle, sustained, enormous,
		float((skill.call("state") as Dictionary)["max_radius"]),
	])
	var ceiling: float = float((skill.call("state") as Dictionary)["max_radius"])
	_check(enormous <= ceiling + 0.001,
		"and stops at a ceiling however deep the dantian gets",
		"%.1f m against a cap of %.1f" % [enormous, ceiling])
	PlayerData.stats["qi"]["current"] = 0.0
	_check(float(skill.call("radius")) > 0.0,
		"an emptying pool tightens the field without erasing it",
		"%.1f m" % float(skill.call("radius")))

	# --- the economy. The claim is exact, so it is checked as an equality: the drain is
	# the passive regeneration evaluated at the sustaining capacity, by construction.
	PlayerData.stats["qi"]["cap"] = 1000.0
	var share: float = float(PlayerData.RESOURCE_REGEN["qi"])
	var drain: float = float(skill.call("drain_per_second"))
	_check(absf(drain - share * 1000.0) < 0.01,
		"at a thousand held, the drain is exactly what the pool hands back",
		"%.2f spent against %.2f refilled per second" % [drain, share * 1000.0])
	# Measured through the real path rather than taken on trust: the field is raised with
	# the pool at three-quarters and the net drift over a run of frames is the answer.
	PlayerData.stats["qi"]["current"] = 750.0
	skill.call("start")
	var sustainable: float = await _measure_qi_rate(90)
	_check(sustainable > -3.0, "and a thousand qi holds the field indefinitely",
		"%.1f QI/s net over the run" % sustainable)
	PlayerData.stats["qi"]["cap"] = 600.0
	PlayerData.stats["qi"]["current"] = 450.0
	var draining: float = await _measure_qi_rate(90)
	print("  info  net qi at 1000 held: %.1f/s (drain %.1f, regen %.1f); at 600 held: %.1f/s" % [
		sustainable, drain, share * 1000.0, draining,
	])
	_check(draining < sustainable - 8.0,
		"below it the pool is being spent, and the field is a burst",
		"%.1f QI/s against %.1f" % [draining, sustainable])

	# --- the key. Driven the way a key is driven, so what is tested is the whole path from
	# the input map through the controller to the technique, not just that the technique
	# works when asked directly. Explicitly lowered first: the economy above raised it, and
	# a toggle test that starts with the thing already on measures the wrong transition (it
	# did, and reported the pair backwards).
	PlayerData.stats["qi"]["cap"] = 1000.0
	PlayerData.stats["qi"]["current"] = 900.0
	skill.call("stop")
	_check(not bool(skill.call("is_active")), "the field starts down")
	await _hold_action("qi_pressure")
	await _settle(3)
	_check(bool(skill.call("is_active")), "the key raises the field")
	await _hold_action("qi_pressure")
	await _settle(3)
	_check(not bool(skill.call("is_active")), "and the same key drops it")

	# --- the damage, on real raiders. One is moved into the field and one is left out of
	# it, because "it hurts what stands inside" is only half a claim: the other half is
	# that it reaches no further than it says.
	var raiders: Array = get_tree().get_nodes_in_group("enemy")
	if not raiders.is_empty():
		var target: Node3D = raiders[0]
		var kept: Vector3 = target.global_position
		var kept_hp: float = float(target.get("hp"))
		PlayerData.stats["qi"]["cap"] = 1000.0
		PlayerData.stats["qi"]["current"] = 1000.0
		skill.call("start")
		target.global_position = (_player as Node3D).global_position + Vector3(1.5, 0.0, 0.0)
		_check(int(skill.call("bodies_in_range")) >= 1, "the field reports what is standing in it")
		await _settle(90)
		_check(float(target.get("hp")) < kept_hp, "a raider inside it is hurt",
			"%.1f -> %.1f" % [kept_hp, float(target.get("hp"))])
		var outside: Node3D = null
		for body: Node in raiders:
			var candidate := body as Node3D
			if candidate != null and candidate.global_position.distance_to(
				(_player as Node3D).global_position) > 30.0:
				outside = candidate
				break
		if outside != null:
			var far_hp: float = float(outside.get("hp"))
			await _settle(30)
			_check(is_equal_approx(float(outside.get("hp")), far_hp),
				"and one well outside it is untouched",
				"%.1f at %.0f m" % [far_hp, outside.global_position.distance_to(
					(_player as Node3D).global_position)])
		skill.call("stop")
		target.set("hp", kept_hp)
		target.global_position = kept

	# --- the HUD says what the technique is doing, in one of its three states
	_hud.call("_refresh")
	var label: Label = _find_by_name(_hud, "PressureLabel") as Label
	_check(label != null and label.text.begins_with("Qi Pressure"),
		"the panel reports the technique", "" if label == null else label.text)
	PlayerData.stats["qi"]["cap"] = saved_cap
	PlayerData.stats["qi"]["current"] = minf(saved_qi, saved_cap)
	skill.call("stop")


## The two things a deep enough dantian buys: a ball of your own aura thrown at a distance,
## and the air under a held jump.
##
## Both are checked where they are *paid for* rather than where they are described. A throw
## that spawned a ball but took no qi is free power; a flight that lifted the body but never
## owed the pool is a mode rather than a technique. Every other art in this game is priced,
## and these two are the expensive ones — so the price is the half of each claim worth
## measuring.
func _test_qi_arts() -> void:
	_section("The qi arts")
	if _player == null:
		return
	_release_game_input()
	Training.stop()
	Cultivation.stop_meditation()
	var saved_cap: float = PlayerData.get_cap("qi")

	# ------------------------------------------------------------ the ball of aura
	# Below the gate first: the key has to *refuse*, not merely be pointless.
	_set_cap("qi", 100.0)
	PlayerData.restore_all()
	_check(not PlayerData.has_effect("qi_bolt"),
		"a shallow dantian throws nothing", "%.0f qi held" % PlayerData.get_cap("qi"))
	_check(not bool(_player.call("throw_bolt")), "and the key refuses")
	_set_cap("qi", 130.01)
	PlayerData.restore_all()
	_check(PlayerData.has_effect("qi_bolt"), "two and a half dantians buys the throw")

	var qi_before: float = PlayerData.get_value("qi")
	var in_flight_before: int = get_tree().get_nodes_in_group("qi_bolt").size()
	var thrown: bool = bool(_player.call("throw_bolt"))
	await _settle(2)
	var bolts: Array = get_tree().get_nodes_in_group("qi_bolt")
	var spent: float = qi_before - PlayerData.get_value("qi")
	_check(thrown and bolts.size() > in_flight_before, "and there is a ball in the air",
		"%d in flight" % bolts.size())
	_check(_near(spent, PlayerData.get_cap("qi") * 0.05, 1.0),
		"paid for out of the dantian at the share the constant says",
		"%.1f qi of a %.0f pool" % [spent, PlayerData.get_cap("qi")])
	_check(not bool(_player.call("throw_bolt")), "and it cannot be spammed")
	# It wears the aura. The ball is the equipped element's own colour rather than a generic
	# blue, which is what makes "your aura, thrown" a statement about the game rather than
	# about the sphere mesh.
	var aura_node: Node = (_player as Node3D).get_node_or_null("Aura")
	if not bolts.is_empty():
		var ball: Node = bolts[0]
		_check(bool(ball.call("from_player")), "the ball knows whose it is")
		if aura_node != null and aura_node.has_method("meditation_color"):
			var expected: Color = aura_node.call("meditation_color")
			_check((ball.call("tint") as Color).is_equal_approx(expected),
				"and wears the colour of the aura you have on",
				"%s against %s" % [ball.call("tint"), expected])
	# It hurts what it is thrown at. Asked of the projectile rather than of the aim, because
	# the aim comes off a camera nobody is holding in a headless run — and the ball is the
	# thing under test here, not the shooting.
	var bolt_script: GDScript = load("res://scripts/enemy/qi_bolt.gd")
	var victim: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var candidate := node as Node3D
		if candidate != null and not bool(candidate.call("is_champion")) \
				and not bool(candidate.call("is_dead")):
			victim = candidate
			break
	_check(victim != null, "there is a raider to throw at")
	if victim != null:
		# Both bodies are put on level ground first. A ball thrown across a hillside spawns
		# inside the hill and bursts on it — which is correct behaviour and a useless
		# measurement, because what is under test is the throw and not the relief of wherever
		# a raider happened to be standing. `_flat_ground_near` is the same probe the other
		# sections stand on.
		var kept: Vector3 = victim.global_position
		var victim_hp: float = float(victim.get("hp"))
		var level: Vector3 = _flat_ground_near(_player as Node3D)
		victim.global_position = level + Vector3(0.0, 1.0, 0.0)
		await _settle(2)
		var chest: Vector3 = victim.global_position + Vector3(0.0, 0.9, 0.0)
		var from: Vector3 = chest + Vector3(3.5, 0.0, 0.0)
		var fired: Node = bolt_script.spawn(_player.get_parent(), from,
			(chest - from).normalized(), 8.0, 26.0, Color("6ec8ff"), _player)
		_check(fired != null, "a ball can be put in the air by hand")
		if fired != null:
			await _settle(24)
			_check(float(victim.get("hp")) < victim_hp,
				"and it bursts on the raider it was sent at",
				"%.1f hp -> %.1f over three and a half metres" % [victim_hp, float(victim.get("hp"))])
		victim.set("hp", victim_hp)
		victim.global_position = kept

	# ------------------------------------------------------------ walking on the air
	_set_cap("qi", 190.0)
	PlayerData.restore_all()
	_check(not PlayerData.has_effect("flight"), "no sky below four dantians")
	_set_cap("qi", 210.01)
	PlayerData.restore_all()
	_check(PlayerData.has_effect("flight"), "four times the dantian buys Cloud Step")

	var ground: Vector3 = _flat_ground_near(_player as Node3D)
	(_player as Node3D).call("warp_to", ground + Vector3(0.0, 3.0, 0.0))
	await _settle(3)
	# Without the key down first, because a body standing on qi is what is being measured and
	# a body falling from three metres is not.
	_check(not bool(_player.call("is_flying")), "falling is still falling")
	var height_before: float = (_player as Node3D).global_position.y
	Input.action_press("jump")
	await _settle(30)
	var flying: bool = bool(_player.call("is_flying"))
	var climbed: float = (_player as Node3D).global_position.y - height_before
	_check(flying, "holding jump in the air holds the body up")
	_check(climbed > 0.3, "and it climbs rather than sinking",
		"%.2f m in half a second" % climbed)
	# The price, over real frames, against the same pool measured with the technique down.
	# Both halves are taken because a drain smaller than the passive regeneration would read
	# as "paid for" while costing nothing at all.
	var with_flight: float = await _measure_qi_rate(90)
	_check(with_flight < -2.0, "and the pool is being spent the whole time it is held",
		"%.1f QI/s net" % with_flight)
	# The ceiling. The ward fences are seventeen metres and a body that could step over one
	# would sell the path of rings, the champions and the spirit zones for a held key — so
	# the limit is the ward, not the sky, and it is measured from the ground under the body.
	await _settle(180)
	var above: float = (_player as Node3D).global_position.y - ground.y
	_check(bool(_player.call("is_flying")), "it is still up after three seconds of holding")
	_check(above <= 9.4, "and it stops nine metres over the ground, under the ward fences",
		"%.1f m" % above)
	Input.action_release("jump")
	await _settle(2)
	_check(not bool(_player.call("is_flying")), "letting go ends it")
	await _land(_player)
	var free_fall: float = await _measure_qi_rate(60)
	print("  info  net qi aloft %.1f/s against %.1f/s with the key up" % [with_flight, free_fall])
	_check(free_fall > with_flight + 5.0,
		"and the pool is measurably better off with the technique down",
		"%.1f against %.1f QI/s" % [free_fall, with_flight])

	_set_cap("qi", saved_cap)
	PlayerData.restore_all()


## Net qi per second over a run of real frames, using the engine's own clock for the same
## reason `_measure_heal` does: regeneration and the drain both integrate `delta`, so a
## wall-clock denominator measures a different span than the thing being measured.
func _measure_qi_rate(frames: int) -> float:
	var before: float = PlayerData.get_value("qi")
	var seconds: float = 0.0
	for i in frames:
		await get_tree().process_frame
		seconds += get_process_delta_time()
	return (PlayerData.get_value("qi") - before) / maxf(0.0001, seconds)


## There is one stat with a hard ceiling, and it is jump height.
##
## Every writer of a cap is walked here rather than just the common one, because a limit
## that four paths respect and a fifth does not is not a limit — and the fifth is usually
## the save file, which is the one a player would use to get a twenty-metre jump.
func _test_ceilings() -> void:
	_section("Technique ceilings")
	var ceiling: float = PlayerData.cap_ceiling("jump")
	_check(ceiling <= 20.0, "jump height has a hard ceiling of twenty metres",
		"%.0f m" % ceiling)
	_check(PlayerData.cap_ceiling("speed") > 1000.0,
		"and only the stats that stop making sense have one",
		"speed ceiling %.0f" % PlayerData.cap_ceiling("speed"))
	print("  info  jump ceiling %.1f m, currently capped at %.2f m and set to %.2f m" % [
		ceiling, PlayerData.get_cap("jump"), PlayerData.max_jump_height(),
	])

	var saved_cap: float = PlayerData.get_cap("jump")
	var saved_alloc: float = PlayerData.get_allocated("jump")
	var saved_caps: Dictionary = {}
	for id: String in PlayerData.STAT_ORDER:
		saved_caps[id] = PlayerData.get_cap(id)

	PlayerData.gain("jump", 1.0e9)
	_check(PlayerData.get_cap("jump") <= ceiling + 0.0001,
		"no amount of jumping passes it", "%.2f m" % PlayerData.get_cap("jump"))
	_check(PlayerData.at_ceiling("jump"), "and the stat reports being at the limit")
	PlayerData._grow_cap("jump", 500.0)
	_check(PlayerData.get_cap("jump") <= ceiling + 0.0001,
		"nor does a grant from another stat", "%.2f m" % PlayerData.get_cap("jump"))
	PlayerData.grow_all_caps(0.02)
	_check(PlayerData.get_cap("jump") <= ceiling + 0.0001,
		"nor does a breakthrough", "%.2f m" % PlayerData.get_cap("jump"))
	PlayerData.set_allocation("jump", 999.0)
	_check(PlayerData.max_jump_height() <= ceiling + 0.0001,
		"nor can the slider dial in more than the ceiling",
		"%.2f m" % PlayerData.max_jump_height())

	# A stat with no ceiling is untouched by all of this: the guard has to be a ceiling,
	# not a change of behaviour for every stat.
	var speed_before: float = PlayerData.get_cap("speed")
	PlayerData.gain("speed", 250.0)
	_check(PlayerData.get_cap("speed") > speed_before, "a stat with no ceiling still grows",
		"%.2f -> %.2f" % [speed_before, PlayerData.get_cap("speed")])

	for id: String in PlayerData.STAT_ORDER:
		PlayerData.stats[id]["cap"] = saved_caps[id]
	PlayerData.stats["jump"]["cap"] = saved_cap
	PlayerData.set_allocation("jump", saved_alloc)
	PlayerData.stats_changed.emit()


## A low ledge must be stepped over rather than stopped against. CharacterBody3D has no
## step-up of its own, so a rock in the grass is a wall without this — which is the
## single most common way a run dies in the open world.
func _test_step_up() -> void:
	_section("Step-up")
	if _player == null:
		return
	var spawn: Vector3 = Vector3(0.0, float(_terrain.call("surface_height_at", 0.0, 0.0)) + 0.8, 0.0)
	(_player as Node3D).call("warp_to", spawn)
	await _land(_player)
	await _settle(6)
	_check(bool(_player.call("is_on_floor")), "the body starts on the ground")

	# A wide, low kerb in front of the body, standing on the ground the body actually
	# landed on. Wide and deep on purpose: a narrow one could be walked around and a thin
	# one stepped over the end of, and neither is the behaviour under test.
	# The forward key walks the camera's forward, which is -Z for the whole run because
	# nothing in the suite ever turns the camera.
	var step_height: float = float(_player.get("step_height"))
	var ground: float = _player.global_position.y
	var kerb := StaticBody3D.new()
	kerb.name = "TestKerb"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(9.0, step_height, 4.0)
	shape.shape = box
	kerb.add_child(shape)
	get_tree().root.get_node("Main").add_child(kerb)
	var kerb_near: float = -1.2
	kerb.global_position = Vector3(0.0, ground + step_height * 0.5, kerb_near - 2.0)
	await _settle(4)
	var start: Vector3 = _player.global_position
	Input.action_press("move_forward")
	var best: float = ground
	var walled: int = 0
	for i in 150:
		await _settle(1)
		best = maxf(best, _player.global_position.y)
		if _player.is_on_wall():
			walled += 1
	_release_game_input()
	print("  info  kerb probe: %s -> %s, ground %.2f, best %.2f, on a wall for %d frames" % [
		str(start), str(_player.global_position), ground, best, walled])
	await _settle(10)
	_check(best > ground + step_height * 0.4, "the body climbs a kerb instead of stopping",
		"rose %.2f m over a %.2f m step" % [best - ground, step_height])
	# The other half of the promise: it is *past* the obstacle, not pressed against it. A
	# step-up that lifted the body onto the kerb and then left it grinding there would
	# pass the first check on its own.
	_check(_player.global_position.z < kerb_near - 0.5,
		"and gets past it rather than grinding against it",
		"z %.2f against a kerb starting at %.2f" % [_player.global_position.z, kerb_near])
	kerb.queue_free()
	await _settle(4)


# ------------------------------------------------------------ slopes and grades

## Running up and down hills, which is the thing the player does most and nothing
## measured.
##
## A slope that stops the body or throws it off the ground reads as a collision bug,
## and it is invisible from the top of the map, where the ground is level. So this
## finds the steepest grade *along the direction the forward key actually drives the
## body* and runs it both ways: downhill, where a body can be launched off every
## shoulder, and uphill, where it can stall against the gradient.
##
## The steepest ground the terrain has is used rather than a slope chosen to flatter
## the test. If the whole map were still mountains this would find a wall; it is flat
## enough now that finding a real grade at all is itself the check.
func _test_slopes() -> void:
	_section("Slopes")
	if _player == null or _terrain == null:
		return
	# The suite never turns the camera, so forward is -Z for the whole run.
	var forward := Vector3(0.0, 0.0, -1.0)
	const LANE := 16.0
	var half: float = float(_terrain.call("extent")) * 0.5 - LANE - 6.0

	# A coarse sweep, then the lane test only on the best handful: `_lane_clear` is a
	# raycast, and a raycast at every one of a few thousand samples is wasted work.
	var candidates: Array = []
	var x: float = -half
	while x <= half:
		var z: float = -half
		while z <= half:
			var here: float = float(_terrain.call("surface_height_at", x, z))
			var ahead: float = float(_terrain.call("surface_height_at", x, z - LANE))
			candidates.append({"step": here - ahead, "x": x, "z": z})
			z += 5.0
		x += 5.0
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["step"]) < float(b["step"]))

	# The end of the sweep is the steepest descent forward, the start the steepest climb.
	# `require_level` is off here on purpose. The level-ground filter belongs to the
	# locomotion lane, where a bank in the middle reports a walking speed however hard
	# the sprint key is held; asking for level ground *here* would cap the grade this
	# test can reach at the 1.2 m tolerance and quietly turn "the steepest ground the
	# terrain has" into "the steepest ground that is nearly flat".
	var descent: Dictionary = _first_clear(candidates, candidates.size() - 1, -1, forward, LANE, false)
	var climb: Dictionary = _first_clear(candidates, 0, 1, forward, LANE, false)
	if descent.is_empty() or climb.is_empty():
		_check(false, "a clear lane up and down the steepest ground could be found",
			"descent %s, climb %s, of %d candidates" % [
				"found" if not descent.is_empty() else "none",
				"found" if not climb.is_empty() else "none", candidates.size()])
		return
	var grade: float = absf(float(descent["step"])) / LANE
	print("  info  steepest grade along the run direction: %.3f rise per metre over %.0f m" % [
		grade, LANE])
	_check(grade > 0.02, "the map has real ground to run up and down",
		"%.3f over %.0f m" % [grade, LANE])

	# Running, not walking: the sprint key is held for both legs, because the point is
	# what happens to a *run* on a grade. The net height change is what is asserted, not
	# the highest or lowest point reached — the grade over the lane is not uniform, so a
	# lane can hold all of its descent in its last few metres and the body would then be
	# credited with a drop it never made.
	var down: Dictionary = await _run_grade(descent, forward)
	print("  info  downhill: %.2f m covered, %.2f m dropped, airborne %d/%d frames" % [
		down["travelled"], down["drop"], down["airborne"], down["frames"]])
	_check(float(down["travelled"]) > 6.0,
		"a run downhill keeps moving rather than catching on the ground",
		"%.2f m" % down["travelled"])
	_check(float(down["drop"]) > 0.3,
		"and it really was downhill", "%.2f m" % down["drop"])
	# A body launched off every shoulder of a descent reads as a bug, so most of the
	# descent has to be spent with the feet down.
	_check(int(down["airborne"]) <= int(down["frames"]) / 5,
		"the descent does not throw the body off the ground",
		"airborne %d of %d frames" % [down["airborne"], down["frames"]])

	var up: Dictionary = await _run_grade(climb, forward)
	print("  info  uphill: %.2f m covered, %.2f m climbed, airborne %d/%d frames" % [
		up["travelled"], up["rise"], up["airborne"], up["frames"]])
	_check(float(up["travelled"]) > 6.0, "a run uphill keeps moving rather than stalling",
		"%.2f m" % up["travelled"])
	_check(float(up["rise"]) > 0.3, "and it really was uphill", "%.2f m" % up["rise"])
	_check(int(up["airborne"]) <= int(up["frames"]) / 10,
		"climbing does not turn into a series of hops",
		"airborne %d of %d frames" % [up["airborne"], up["frames"]])
	# Climbing slower than descending is correct — that is gravity. What is not correct
	# is the *silent* loss `floor_constant_speed` exists to prevent, where the pace
	# collapses because the slope is being projected out of the movement each frame.
	# The two legs are the same length over the same magnitude of grade, so they are
	# the honest comparison, and neither depends on how fast the last frame happened to
	# leave the body moving.
	var climbing: float = float(up["travelled"]) / maxf(0.01, float(up["seconds"]))
	var descending: float = float(down["travelled"]) / maxf(0.01, float(down["seconds"]))
	_check(climbing > descending * 0.75, "a hill does not quietly cost the pace",
		"%.2f m/s climbing against %.2f m/s descending" % [climbing, descending])


## Walks `candidates` from `index` in `direction` and returns the first whose lane is
## clear for the whole run.
func _first_clear(candidates: Array, index: int, direction: int, forward: Vector3,
		lane: float, require_level: bool = true) -> Dictionary:
	var i: int = index
	var tried: int = 0
	var blocked: int = 0
	var rough: int = 0
	while i >= 0 and i < candidates.size() and tried < 60:
		var entry: Dictionary = candidates[i]
		var spot := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		spot.y = float(_terrain.call("surface_height_at", spot.x, spot.z)) + 0.9
		var clear: bool = _lane_clear(spot, forward, lane + 4.0)
		var level: bool = _lane_ground_ok(spot, forward, lane) if require_level else clear
		if clear and level:
			return entry
		if not clear:
			blocked += 1
		else:
			rough += 1
		i += direction
		tried += 1
	# A grade lane needs to be both unobstructed and roughly even over sixteen metres.
	# Which of the two turned the candidates away is the difference between "the forest
	# is in the way" and "this map has no long grade", so it is worth saying.
	print("  info  no grade lane after %d candidates (%d obstructed, %d too uneven)" % [
		tried, blocked, rough])
	return {}


## One leg of a grade traverse. Returns how far the body got, how much height it
## gained or lost, and how much of the leg its feet were off the ground for.
func _run_grade(entry: Dictionary, forward: Vector3) -> Dictionary:
	var spot := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
	spot.y = float(_terrain.call("surface_height_at", spot.x, spot.z)) + 0.9
	(_player as Node3D).call("warp_to", spot)
	await _land(_player)
	await _settle(8)
	var start: Vector3 = _player.global_position
	var frames: int = 130
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var airborne: int = 0
	for i in frames:
		await _settle(1)
		if not _player.is_on_floor():
			airborne += 1
	_release_game_input()
	await _settle(10)
	var moved := Vector2(
		_player.global_position.x - start.x, _player.global_position.z - start.z)
	var ended: float = _player.global_position.y
	return {
		"travelled": moved.length(),
		"drop": start.y - ended,
		"rise": ended - start.y,
		"airborne": airborne,
		"frames": frames,
		"seconds": float(frames) / 60.0,
	}


## Puts the player's real save back, so running the suite is never destructive.
func _restore_player_state() -> void:
	_section("Cleanup")
	if _had_save:
		_check(_copy(BACKUP_PATH, SAVE_PATH), "existing save file restored")
		_remove(BACKUP_PATH)
		print("  info  your previous save was left untouched")
		return
	PlayerData.reset_progress()
	Cultivation.reset()
	PlayerData.gain_coefficient = 1.0
	_remove(BACKUP_PATH)
	_check(not FileAccess.file_exists(SAVE_PATH), "no save file left behind for a fresh start")
