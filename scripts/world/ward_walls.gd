extends Node3D
## The wards, made out of geometry: a fence of qi standing across the map at each gate's
## radius, and the hand that pushes you back off it.
##
## The rule lives in the `Wards` autoload and this is the part you can see. They are split
## because the rule has to be readable and savable without a scene, and because the wall
## has to be built once the terrain exists — which is later than any autoload readies.
##
## A wall is drawn as a ring of tall panels rather than as a solid tube, and that is a
## legibility choice rather than a saving: a translucent tube at sixty metres is a haze you
## can see through and therefore do not believe, and a fence of vertical bars is a barrier
## at a glance, which is the only thing it has to communicate. A ring on the ground marks
## the radius the rule actually uses, so what blocks you is what you can see.
##
## Only locked walls are drawn. An open ward is nothing at all — a permanent glowing hoop
## around the map would be scenery, and the one thing this system has to say is "not yet".

## How tall the fence stands. Just over the eye line: tall enough to be a wall, short enough
## that the hills and the sky are still the view.
const WALL_HEIGHT := 17.0
## Panels around the circle. Few enough that the gaps between them read as a fence rather
## than as a rendering fault.
const PANEL_COUNT := 22
## How far inside a wall the pushback leaves you. Enough that you are not standing in it,
## small enough that it does not read as being shoved.
const PUSH_BACK := 1.4
## Seconds between two "the ward holds" messages. One per frame would be a wall of text.
const MESSAGE_COOLDOWN := 3.0
## The rim of the world, as a fraction of the half-extent.
##
## The terrain is a square mesh with nothing beyond it: walk far enough and you drop out of
## the world, which is the one bug that ends a session with no explanation and no way back.
## Nothing was holding the player in. The rim does, and it is deliberately not drawn — the
## ground ending is the picture, and a fence on the horizon would be scenery.
const RIM_REACH := 0.965
## Seconds between two "the world ends here" messages.
const RIM_COOLDOWN := 6.0

## Distance over which a wall fades out as you walk away from it. All three walls are inside
## each other, so without this the far ones would stack into a haze over the horizon.
const FADE_NEAR := 30.0
const FADE_FAR := 140.0
## The floor alpha of a wall you are standing next to, and how dim a distant one goes.
const ALPHA_NEAR := 0.30
const ALPHA_BASE := 0.05

var _terrain: Node
var _player: Node3D
## One entry per gate, in gate order: the built node, its panels, and the ring.
var _walls: Array = []
var _cooldown: float = 0.0
var _rim_cooldown: float = 0.0
var _blocked_count: int = 0
var _rim_count: int = 0


func _ready() -> void:
	# Physics priority, so this runs *after* the body has moved for the frame. Pushing a
	# player back at the position they held before they moved is a wall you can walk
	# through at high speed and a stutter everywhere else.
	process_physics_priority = 20
	_terrain = get_parent().get_node_or_null("Terrain")
	if _terrain != null and _terrain.has_method("extent"):
		Wards.extent = float(_terrain.call("extent"))
	_build()
	Wards.changed.connect(_refresh)
	Wards.ward_passed.connect(_on_passed)
	_refresh()
	_reconcile.call_deferred()


## Builds every gate's fence once, at its final radius. Nothing is rebuilt later: an open
## ward is hidden, not torn down, so crossing one is a visibility change rather than a
## frame of geometry work at the exact moment the player is watching the horizon.
func _build() -> void:
	for i in Wards.gate_count():
		var gate: Dictionary = Wards.GATES[i]
		var radius: float = Wards.radius_of(i)
		var tint: Color = gate.get("color", Color("6ec8ff"))
		var root := Node3D.new()
		root.name = "Ward_%s" % String(gate["id"])
		add_child(root)

		var panels: Array = []
		for p in PANEL_COUNT:
			var angle: float = TAU * float(p) / float(PANEL_COUNT)
			var panel := MeshInstance3D.new()
			panel.mesh = _fence_mesh(Vector2(3.4, WALL_HEIGHT))
			panel.material_override = _qi(tint)
			panel.position = Vector3(cos(angle) * radius, WALL_HEIGHT * 0.5, sin(angle) * radius)
			# Facing along the circle's tangent, so from inside the fence the panels are
			# seen at an angle rather than edge-on — an edge-on quad is an invisible one.
			panel.rotation.y = -angle + PI * 0.5
			panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(panel)
			panels.append(panel)

		var mark := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = maxf(1.0, radius - 0.5)
		torus.outer_radius = radius
		mark.mesh = torus
		mark.material_override = _ring_material(tint)
		mark.position = Vector3(0.0, 0.2, 0.0)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mark)

		_walls.append({
			"index": i, "root": root, "panels": panels, "mark": mark, "tint": tint, "flash": 0.0,
		})
	print("[wards] %d gates at %s of a %.0f m half-extent" % [
		Wards.gate_count(),
		", ".join(Wards.GATES.map(func(g: Dictionary) -> String: return "%.0f m" % (Wards.extent * float(g["reach"])))),
		Wards.extent,
	])


## A panel that fades upward: brightest at the top, dissolving into the ground at the
## bottom. Built by hand because a `QuadMesh` has no vertex colours, and the fade is the
## difference between a wall of light and a coloured stamp. Four vertices and two triangles
## per panel is a vertical gradient for the price of nothing.
func _fence_mesh(size: Vector2) -> ArrayMesh:
	var hw: float = size.x * 0.5
	var hh: float = size.y * 0.5
	var vertices := PackedVector3Array([
		Vector3(-hw, -hh, 0.0), Vector3(hw, -hh, 0.0),
		Vector3(hw, hh, 0.0), Vector3(-hw, hh, 0.0),
	])
	var colors := PackedColorArray([
		Color(0.18, 0.18, 0.18, 1.0), Color(0.18, 0.18, 0.18, 1.0),
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The qi itself. Additive and unshaded, like the spirit zones' columns, so the fences and
## the zones read as the same substance — in the fiction they are the same thing.
##
## Alpha lives in the albedo rather than in the mesh so the breath and the fade can move it
## every frame without touching geometry, and the vertex colours carry only brightness.
func _qi(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(tint.r, tint.g, tint.b, ALPHA_NEAR)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.35
	return material


func _ring_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(tint.r, tint.g, tint.b, 0.7)
	return material


## Which walls are on screen this frame. A wall exists while it is locked and is hidden the
## moment it is not: the fence is the *rule*, drawn.
func _refresh() -> void:
	for wall: Dictionary in _walls:
		var index: int = int(wall["index"])
		var locked: bool = index >= Wards.passed() and not Wards.is_open(index)
		(wall["root"] as Node3D).visible = locked


func _on_passed(index: int, gate: Dictionary) -> void:
	PlayerData.log_message.emit(
		"%s thins and is gone. The way out is open." % String(gate["name"]), "breakthrough"
	)
	# The wall the player just walked through, so the crossing has a picture on the frame it
	# happens rather than only a line in the log.
	_flash(index, 3.0)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_rim_cooldown = maxf(0.0, _rim_cooldown - delta)
	_breath()
	if _hold_at_rim():
		return
	var distance: float = _flat_distance(_player.global_position)
	for i in Wards.gate_count():
		if i < Wards.passed() or not (_walls[i] as Dictionary)["root"].visible:
			continue
		var radius: float = Wards.radius_of(i)
		if distance < radius:
			continue
		if Wards.is_open(i):
			# Walked out through a gate whose realm has been reached. The autoload decides
			# whether that is a crossing it recognises; this only reports the fact.
			Wards.pass_ward(i)
			continue
		_hold_back(i, radius)
		return


## Puts the body back inside the wall and takes the outward speed out of it.
##
## Setting the position alone is not enough: the next frame would carry the same velocity
## straight back into the wall, and the player would stand in the fence jittering while
## being told about it. Killing the outward component is what makes it feel like a surface
## rather than like a trap.
func _hold_back(index: int, radius: float) -> void:
	var at: Vector3 = _player.global_position
	var flat := Vector2(at.x, at.z)
	if flat.length_squared() < 0.0001:
		flat = Vector2(1.0, 0.0)
	var outward: Vector2 = flat.normalized()
	_player.global_position = Vector3(
		outward.x * (radius - PUSH_BACK), at.y, outward.y * (radius - PUSH_BACK)
	)
	var body := _player as CharacterBody3D
	if body != null:
		var along: float = body.velocity.x * outward.x + body.velocity.z * outward.y
		if along > 0.0:
			body.velocity.x -= outward.x * along
			body.velocity.z -= outward.y * along
	_blocked_count += 1
	_flash(index, 1.0)
	if _cooldown > 0.0:
		return
	_cooldown = MESSAGE_COOLDOWN
	var reason: String = Wards.blocker(index)
	PlayerData.log_message.emit(
		"The ward holds you back. %s" % reason if reason != "" else "The ward holds you back.",
		"damage"
	)
	Audio.play("ui_click", -8.0, 0.6)


## A slow breath on every standing wall, so a barrier reads as alive rather than as a wall
## of paint, and the decay of the flash that marks a crossing or a pushback. Alpha and
## distance only: the panels are placed once and never move.
func _breath() -> void:
	var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 900.0)
	var distance: float = _flat_distance(_player.global_position)
	for wall: Dictionary in _walls:
		wall["flash"] = maxf(0.0, float(wall["flash"]) - 0.02)
		var root: Node3D = wall["root"]
		if not root.visible:
			continue
		var radius: float = Wards.radius_of(int(wall["index"]))
		# Faded by how close the wall is to the player rather than by how far the player is
		# from the middle: all three walls are inside each other, so without this the two
		# you are nowhere near would stack into a haze over the horizon.
		var near: float = clampf(1.0 - absf(distance - radius) / FADE_FAR, 0.0, 1.0)
		var alpha: float = (ALPHA_BASE + (ALPHA_NEAR - ALPHA_BASE) * near) * (0.75 + 0.25 * pulse)
		var tint: Color = wall["tint"]
		var glow: float = 0.35 + 0.55 * float(wall["flash"])
		for panel: MeshInstance3D in wall["panels"]:
			var material: StandardMaterial3D = panel.material_override
			material.albedo_color = Color(tint.r, tint.g, tint.b, alpha + 0.25 * float(wall["flash"]))
			material.emission_energy_multiplier = glow


## A brightening on the frame a wall does something: a crossing, or a pushback. Recorded
## rather than applied, so the breath decays it and nothing has to remember to put it out.
func _flash(index: int, strength: float) -> void:
	if index < 0 or index >= _walls.size():
		return
	_walls[index]["flash"] = maxf(float(_walls[index]["flash"]), strength)


## Keeps the player on the ground there is, by the same mechanism as a ward: put the body
## back inside the rim and take the outward speed out of it. Returns true when it had to.
func _hold_at_rim() -> bool:
	var limit: float = Wards.extent * RIM_REACH
	var at: Vector3 = _player.global_position
	var flat := Vector2(at.x, at.z)
	if flat.length() <= limit:
		return false
	var outward: Vector2 = flat.normalized()
	_player.global_position = Vector3(
		outward.x * (limit - 1.0), at.y, outward.y * (limit - 1.0)
	)
	var body := _player as CharacterBody3D
	if body != null:
		var along: float = body.velocity.x * outward.x + body.velocity.z * outward.y
		if along > 0.0:
			body.velocity.x -= outward.x * along
			body.velocity.z -= outward.y * along
	_rim_count += 1
	if _rim_cooldown <= 0.0:
		_rim_cooldown = RIM_COOLDOWN
		PlayerData.log_message.emit(
			"The ground ends here. Past this the world simply stops.", "info"
		)
	return true


## A save can drop the player anywhere, including outside a wall — from a build where the
## walls did not exist, from a walk added later, or from an edit. Walking forward from the
## recorded crossing is the only honest answer: everything their realm has opened is
## recorded as crossed, and anything else puts them back where the wall says they belong.
func _reconcile() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	var reached: int = Wards.crossed_at(_player.global_position)
	while Wards.passed() < reached and Wards.is_open(Wards.passed()):
		if not Wards.pass_ward(Wards.passed()):
			break
	var next: int = Wards.passed()
	if next >= Wards.gate_count() or reached <= next:
		return
	var radius: float = Wards.radius_of(next)
	var flat := Vector2(_player.global_position.x, _player.global_position.z)
	if flat.length_squared() < 0.0001:
		return
	var outward: Vector2 = flat.normalized()
	_player.global_position = Vector3(
		outward.x * (radius - PUSH_BACK * 2.0),
		_player.global_position.y,
		outward.y * (radius - PUSH_BACK * 2.0)
	)
	PlayerData.log_message.emit(
		"You are put back inside %s. %s" % [String(Wards.GATES[next]["name"]), Wards.blocker(next)],
		"damage"
	)


func _flat_distance(position: Vector3) -> float:
	return sqrt(position.x * position.x + position.z * position.z)


# ------------------------------------------------------------------- querying

## Walls standing this frame. The tests read this rather than the node tree, because the
## interesting claim is "a locked ward is visible and an open one is not".
func standing_walls() -> int:
	var total: int = 0
	for wall: Dictionary in _walls:
		if (wall["root"] as Node3D).visible:
			total += 1
	return total


func wall_visible(index: int) -> bool:
	if index < 0 or index >= _walls.size():
		return false
	return (_walls[index]["root"] as Node3D).visible


## How many times a wall has turned the player around. A count rather than a flag so a test
## can tell "held back" from "never tested".
func blocked_count() -> int:
	return _blocked_count


## And how many times the end of the world has.
func rim_count() -> int:
	return _rim_count


func radius_of(index: int) -> float:
	return Wards.radius_of(index)
