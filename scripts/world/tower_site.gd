extends Node3D
## The tower, standing in the world.
##
## Two halves that solve two different problems.
##
## **The outside** is one cylinder, ten rings and a column of light at the top. It has to be
## *one* thing because it is the only landmark on a 448-metre map: a spire four hundred metres
## tall with a beacon on it is visible from the spawn fire, which is what turns "somewhere out
## there is a tower" from a line of dialogue into a fact you can see over your own shoulder —
## and it is the reason a player walks south at all.
##
## **The inside** is a single stage that reconfigures. A hundred built arenas is a hundred
## arenas' worth of collision shapes in the broadphase for one floor's worth of play, so there
## is exactly one plate, one ring of walls, one way down, one way up — and entering a floor
## moves the set to that floor's height and repaints it in the band's colour. A band that has
## just changed colour on the walls and gone dark is legible without a single word of text.
##
## Floors already cleared are *empty* on the way back up. That is what makes a run a matter of
## reaching the frontier instead of re-earning it, and it costs one `if`.

const PROPS := "res://assets/props/"
const STRUCTURES := "res://assets/structures/"
const EnemyFactory := preload("res://scripts/enemy/enemy_factory.gd")

## Where it stands: the fraction of the half-extent, and which of the terrain's roads to walk to
## get there. The last ring before the outer ward, so the tower is reachable the moment the
## second wall is open and stands with its back against the third.
@export var reach: float = 0.775
@export var road: int = 9
@export var radius: float = 15.0
## The arena, inside the shell. A little smaller than the outside, so a body never stands in the
## wall it can see through.
@export var arena: float = 13.6
## How far above the ground the first floor sits, so the arena is never buried in a hillside.
@export var interior_offset: float = 7.0
@export var tower_seed: int = 5150

var _terrain: Node
var _base: Vector3 = Vector3.ZERO
## Where the door is in the world, and which way it faces outward. Kept as the plaza is built
## rather than re-derived by every caller: the door's transform is what the player sees, and a
## second computation of it is a second answer waiting to disagree with the first.
var _door_world: Vector3 = Vector3.ZERO
var _door_out: Vector3 = Vector3.FORWARD
var _stage: Node3D
var _floor_root: Node3D
var _plate: MeshInstance3D
var _ceil: MeshInstance3D
var _walls: Array = []
var _ring: MeshInstance3D
var _entry_pad: MeshInstance3D
var _gate_pad: MeshInstance3D
var _floor_light: OmniLight3D
var _gate_light: OmniLight3D
var _shell_material: StandardMaterial3D
var _enemies: Array = []
var _shown_floor: int = -1
var _cleared_here: bool = false
var _second_wave: bool = false
var _interact_cooldown: float = 0.0


func _ready() -> void:
	_terrain = get_parent().get_node_or_null("Terrain")
	if _terrain == null:
		push_warning("[tower] no terrain to stand on")
		return
	_base = _pick_ground()
	# The tower is built in its *own* frame — the plaza, the shell, the door and the arena all
	# grow upward from (0, 0, 0) — so the node carries the base and nothing else does. Left at
	# the origin, a four-hundred-metre tower, its worked plaza and its arena all stand on the
	# middle of the map: the spawn camp gets a stage a player cannot jump out of, and every
	# probe that casts a ray near the fire finds the tower's floor.
	position = _base
	_build_exterior()
	_build_stage()
	add_to_group("tower_site")
	add_to_group("interactable")
	# Registered as a place to keep clear of, the same way the villages are: nothing else in the
	# world may be placed on the tower's plain.
	Villages.register_site("tower", "The Tower", Vector2(_base.x, _base.z), radius + 12.0)
	Haven.register({
		"id": "tower_step",
		"name": "the tower's step",
		"kind": "camp",
		"centre": _base + Vector3(0.0, 0.4, 0.0),
		"radius": 16.0,
		"wake": _base + Vector3(0.0, 1.2, -radius - 3.0),
		"enter": "The tower's step. Nothing comes up to the door after you.",
		"exit": "You step away from the tower's step.",
	})
	tree_exiting.connect(func() -> void: Haven.unregister("tower_step"))
	print("[tower] at %.0f m on road %d, %d floors, %d bands, deepest %d" % [
		Vector2(_base.x, _base.z).length(), road, Tower.FLOORS, Tower.BANDS.size(), Tower.deepest,
	])


## Rejection-samples level ground on the chosen road, for the same reason the camps do: the
## terrain is procedural, and a tower half-buried in a hillside reads as a bug rather than as a
## feat of somebody's engineering.
func _pick_ground() -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = tower_seed
	var extent: float = float(_terrain.call("extent"))
	var target: float = extent * reach
	var roads: Array = _terrain.call("roads")
	var best := Vector3(0.0, 0.0, target)
	var best_slope: float = INF
	for attempt in 240:
		var angle: float = TAU * rng.randf()
		var use_road: bool = attempt % 3 == 0
		var x: float = 0.0
		var z: float = 0.0
		if use_road and road >= 0 and road < roads.size():
			# On the road, at the distance asked for: a tower you reach by walking a road.
			var points: PackedVector2Array = roads[road]["points"]
			var travelled: float = 0.0
			var at := Vector2(points[0])
			for i in range(1, points.size()):
				var step: float = points[i - 1].distance_to(points[i])
				if travelled + step >= target:
					at = points[i - 1].lerp(points[i], (target - travelled) / maxf(0.1, step))
					break
				travelled += step
				at = points[i]
			var out := Vector2(at.y, -at.x).normalized() * rng.randf_range(0.0, 10.0)
			x = at.x + out.x
			z = at.y + out.y
		else:
			var d: float = target + rng.randf_range(-10.0, 14.0)
			x = cos(angle) * d
			z = sin(angle) * d
		var slope: float = float(_terrain.call("slope_at", x, z))
		if slope < best_slope:
			best_slope = slope
			best = Vector3(x, float(_terrain.call("surface_height_at", x, z)), z)
		if slope <= 0.10 and attempt > 8:
			break
	return best


# ------------------------------------------------------------------- the outside

func _build_exterior() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("3a3d47")
	stone.roughness = 0.86
	stone.metallic = 0.08
	_shell_material = stone

	var height: float = float(Tower.FLOORS) * Tower.FLOOR_HEIGHT + 12.0

	# The plain: a disc of worked ground the tower stands on, so the door does not open straight
	# into grass.
	var plaza := MeshInstance3D.new()
	plaza.name = "Plaza"
	var plaza_mesh := CylinderMesh.new()
	plaza_mesh.top_radius = radius + 5.0
	plaza_mesh.bottom_radius = radius + 6.0
	plaza_mesh.height = 1.2
	plaza_mesh.radial_segments = 40
	plaza.mesh = plaza_mesh
	plaza.material_override = _stone(Color("4a4d55"), 0.0)
	plaza.position = Vector3(0.0, -0.5, 0.0)
	add_child(plaza)

	# The shell: one cylinder, open at both ends, so the light of the sky reaches the floors.
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var shell_mesh := CylinderMesh.new()
	shell_mesh.top_radius = radius
	shell_mesh.bottom_radius = radius + 1.4
	shell_mesh.height = height
	shell_mesh.radial_segments = 48
	shell_mesh.cap_top = false
	shell_mesh.cap_bottom = false
	shell.mesh = shell_mesh
	shell.material_override = _shell_material
	shell.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shell)

	var body := StaticBody3D.new()
	body.name = "ShellBody"
	add_child(body)
	var shell_shape := CollisionShape3D.new()
	var shell_cyl := CylinderShape3D.new()
	shell_cyl.radius = radius + 0.7
	shell_cyl.height = height
	shell_shape.shape = shell_cyl
	shell_shape.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shell_shape)

	# Ten rings, one per band, so the *height* of the climb is readable from the ground: a
	# player standing at the door can count what they have not done yet.
	for band in Tower.BANDS.size():
		var spec: Dictionary = Tower.BANDS[band]
		var ring := MeshInstance3D.new()
		ring.name = "Band%d" % band
		var torus := TorusMesh.new()
		torus.inner_radius = radius + 0.2
		torus.outer_radius = radius + 1.1
		ring.mesh = torus
		ring.material_override = _glow(spec["colour"], 0.85)
		ring.position = Vector3(0.0, float(band + 1) * 10.0 * Tower.FLOOR_HEIGHT - 1.4, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

	# The crown and the beacon. Four hundred metres up, and it is the highest thing on the map
	# by an order of magnitude: this is the signpost for the whole southern half of the valley.
	var crown := MeshInstance3D.new()
	crown.name = "Crown"
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = radius * 0.35
	crown_mesh.bottom_radius = radius + 1.4
	crown_mesh.height = 14.0
	crown_mesh.radial_segments = 48
	crown.mesh = crown_mesh
	crown.material_override = _stone(Color("4e525c"), 0.0)
	crown.position = Vector3(0.0, height + 7.0, 0.0)
	add_child(crown)

	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	var beacon_mesh := CylinderMesh.new()
	beacon_mesh.top_radius = 1.2
	beacon_mesh.bottom_radius = 3.4
	beacon_mesh.height = 90.0
	beacon_mesh.radial_segments = 20
	beacon.mesh = beacon_mesh
	beacon.material_override = _glow(Color("cfe4ff"), 0.20)
	beacon.position = Vector3(0.0, height + 56.0, 0.0)
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beacon)

	var beacon_light := OmniLight3D.new()
	beacon_light.name = "BeaconLight"
	beacon_light.light_color = Color("dcebff")
	beacon_light.light_energy = 2.2
	beacon_light.omni_range = 60.0
	beacon_light.shadow_enabled = false
	beacon_light.position = Vector3(0.0, height + 16.0, 0.0)
	add_child(beacon_light)

	_build_door(height)


## The door, on the side facing the camp. Two light strips rather than a mesh, because the only
## thing the door has to communicate is *which* door, and the band-1 colour is the answer.
func _build_door(height: float) -> void:
	var gap: float = 4.0
	var heading: Vector2 = Vector2(_base.x, _base.z)
	if heading.length() > 0.1:
		heading = -heading.normalized()
	else:
		heading = Vector2(0.0, -1.0)
	var door_pos := Vector3(heading.x * (radius + 0.9), 0.0, heading.y * (radius + 0.9))
	_door_world = _base + door_pos
	_door_out = Vector3(heading.x, 0.0, heading.y)

	var dark := MeshInstance3D.new()
	dark.name = "Doorway"
	var dark_mesh := BoxMesh.new()
	dark_mesh.size = Vector3(gap * 1.5, 7.0, 0.7)
	dark.mesh = dark_mesh
	dark.material_override = _stone(Color("14161c"), 0.0)
	dark.position = door_pos + Vector3(0.0, 3.5, 0.0)
	# The slab's thin axis (local +Z) has to face *outward*, so the doorway reads as a hole in the
	# ring rather than a fin nailed to it. A box's local +Z lands on the radial direction at
	# `atan2(heading.x, heading.y)`; the old figure was the complement of that, which laid the
	# six-metre face along the radius — the door stood at a right angle to the wall it is set in,
	# which is exactly how it looked from the road.
	dark.rotation.y = atan2(heading.x, heading.y)
	add_child(dark)

	for side: float in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(0.34, 6.0, 0.34)
		strip.mesh = strip_mesh
		strip.material_override = _glow(Tower.BANDS[0]["colour"], 0.9)
		var lateral := Vector3(-heading.y, 0.0, heading.x) * side * gap
		strip.position = door_pos + lateral + Vector3(0.0, 3.2, 0.0)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)

	var glow := OmniLight3D.new()
	glow.name = "DoorGlow"
	glow.light_color = Tower.BANDS[0]["colour"]
	glow.light_energy = 1.6
	glow.omni_range = 14.0
	glow.shadow_enabled = false
	glow.position = door_pos + Vector3(0.0, 2.6, 0.0)
	add_child(glow)

	# The name, over the door, in the game's own voice: the second thing the player reads about
	# this place and the first thing the tower says for itself.
	var label := Label3D.new()
	label.name = "Nameplate"
	label.text = "THE TOWER OF THE TENTH SEAT"
	label.font_size = 120
	label.pixel_size = 0.008
	label.outline_size = 22
	label.outline_modulate = Color(0.04, 0.04, 0.06)
	label.modulate = Color("dce4f2")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = door_pos + Vector3(0.0, 6.6, 0.0)
	add_child(label)

	# A staging camp at the door, because a hundred-floor climb needs an antechamber: a fire,
	# two banners, a chest somebody left, and the crates a party would leave behind.
	var door_flat := Vector2(door_pos.x, door_pos.z)
	for offset: Vector2 in [
		Vector2(3.6, 2.4), Vector2(-3.5, 2.6), Vector2(2.2, -2.6), Vector2(-2.4, -2.8),
	]:
		_place_prop(PROPS + "Torch_Metal.gltf", door_flat + offset, 0.0)
	_place_prop(PROPS + "Banner_1.gltf", door_flat + Vector2(5.4, 1.2), 0.0)
	_place_prop(PROPS + "Banner_1.gltf", door_flat + Vector2(-5.4, 1.4), 0.0)
	_place_prop(PROPS + "Chest_Wood.gltf", door_flat + Vector2(-1.6, 3.4), 0.0)
	_place_prop(PROPS + "Crate_Wooden.gltf", door_flat + Vector2(1.8, 3.8), 12.0)
	_place_prop(PROPS + "Crate_Wooden.gltf", door_flat + Vector2(1.0, 4.9), -18.0)
	var fire: Node3D = _place_prop(PROPS + "Cauldron.gltf", door_flat + Vector2(0.4, 6.2), 0.0)
	if fire != null:
		var fire_light := OmniLight3D.new()
		fire_light.light_color = Color("ff9a4d")
		fire_light.light_energy = 1.8
		fire_light.omni_range = 13.0
		fire_light.shadow_enabled = false
		fire_light.position = Vector3(0.0, 1.3, 0.0)
		fire.add_child(fire_light)


# -------------------------------------------------------------------- the inside

## One arena, reused. Its origin is the floor surface, so moving the stage to a height *is*
## walking onto that floor.
func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	_stage.visible = false
	add_child(_stage)

	_plate = MeshInstance3D.new()
	_plate.name = "Plate"
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(arena * 2.0 + 2.0, 0.8, arena * 2.0 + 2.0)
	_plate.mesh = plate_mesh
	_plate.material_override = _stone(Color("33363f"), 0.0)
	_plate.position = Vector3(0.0, -0.4, 0.0)
	_stage.add_child(_plate)

	var body := StaticBody3D.new()
	body.name = "StageBody"
	_stage.add_child(body)
	var plate_shape := CollisionShape3D.new()
	var plate_box := BoxShape3D.new()
	plate_box.size = Vector3(arena * 2.0 + 2.0, 0.8, arena * 2.0 + 2.0)
	plate_shape.shape = plate_box
	plate_shape.position = Vector3(0.0, -0.4, 0.0)
	body.add_child(plate_shape)

	# Twelve walls rather than four: a square room with a circular tower around it reads as
	# wrong from the first step.
	_walls = []
	for i in 12:
		var angle: float = TAU * float(i) / 12.0
		var wall := MeshInstance3D.new()
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = Vector3(arena * 0.62, Tower.FLOOR_HEIGHT, 1.0)
		wall.mesh = wall_mesh
		wall.material_override = _stone(Color("3f434d"), 0.0)
		wall.position = Vector3(cos(angle) * (arena + 0.4), Tower.FLOOR_HEIGHT * 0.5 - 0.2,
			sin(angle) * (arena + 0.4))
		wall.rotation.y = -angle
		_stage.add_child(wall)
		_walls.append(wall)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall_mesh.size
		shape.shape = box
		shape.position = wall.position
		shape.rotation.y = -angle
		body.add_child(shape)

	_ceil = MeshInstance3D.new()
	_ceil.name = "Ceiling"
	var ceil_mesh := CylinderMesh.new()
	ceil_mesh.top_radius = arena + 1.4
	ceil_mesh.bottom_radius = arena + 1.4
	ceil_mesh.height = 0.6
	ceil_mesh.radial_segments = 48
	_ceil.mesh = ceil_mesh
	_ceil.material_override = _stone(Color("2b2e36"), 0.0)
	_ceil.position = Vector3(0.0, Tower.FLOOR_HEIGHT - 0.3, 0.0)
	_stage.add_child(_ceil)
	var ceil_shape := CollisionShape3D.new()
	var ceil_cyl := CylinderShape3D.new()
	ceil_cyl.radius = arena + 1.4
	ceil_cyl.height = 0.6
	ceil_shape.shape = ceil_cyl
	ceil_shape.position = _ceil.position
	body.add_child(ceil_shape)

	_ring = MeshInstance3D.new()
	_ring.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = arena - 0.4
	torus.outer_radius = arena + 0.1
	_ring.mesh = torus
	_ring.material_override = _glow(Tower.BANDS[0]["colour"], 0.7)
	_ring.position = Vector3(0.0, 0.12, 0.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_ring)

	_entry_pad = _build_pad("EntryPad", arena - 3.0, 0.0, Color("8fe3ff"))
	_gate_pad = _build_pad("GatePad", -(arena - 3.0), 0.0, Color("ffd76e"))

	_floor_light = OmniLight3D.new()
	_floor_light.name = "FloorLight"
	_floor_light.light_color = Color("cfe0ff")
	_floor_light.light_energy = 1.2
	_floor_light.omni_range = arena * 2.2
	_floor_light.shadow_enabled = false
	_floor_light.position = Vector3(0.0, Tower.FLOOR_HEIGHT - 1.2, 0.0)
	_stage.add_child(_floor_light)

	_gate_light = OmniLight3D.new()
	_gate_light.name = "GateLight"
	_gate_light.light_color = Color("ffd76e")
	_gate_light.light_energy = 0.0
	_gate_light.omni_range = 10.0
	_gate_light.shadow_enabled = false
	_gate_light.position = _gate_pad.position + Vector3(0.0, 1.4, 0.0)
	_stage.add_child(_gate_light)

	_floor_root = Node3D.new()
	_floor_root.name = "Floor"
	_stage.add_child(_floor_root)


func _build_pad(pad_name: String, x: float, z: float, tint: Color) -> MeshInstance3D:
	var pad := MeshInstance3D.new()
	pad.name = pad_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.6
	mesh.bottom_radius = 2.6
	mesh.height = 0.16
	mesh.radial_segments = 28
	pad.mesh = mesh
	pad.material_override = _glow(tint, 0.55)
	pad.position = Vector3(x, 0.1, z)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(pad)
	return pad


# ------------------------------------------------------------------ running it

func _process(delta: float) -> void:
	_interact_cooldown = maxf(0.0, _interact_cooldown - delta)
	if not Tower.inside():
		if _stage.visible:
			_stage.visible = false
			_shown_floor = -1
		return
	if Tower.current != _shown_floor:
		_enter_floor(Tower.current)
	if _cleared_here:
		return
	if _second_wave and _alive_count() <= 0:
		_spawn_wave(_shown_floor, true)
		return
	if _alive_count() <= 0 and not _enemies.is_empty():
		_clear_floor()


## Moves the set to a floor, repaints it in the band's colour and fills it.
func _enter_floor(depth: int) -> void:
	_shown_floor = depth
	_stage.visible = true
	_stage.position = Vector3(0.0, interior_offset + float(depth - 1) * Tower.FLOOR_HEIGHT, 0.0)
	var plan_here: Dictionary = Tower.plan(depth)
	var tint: Color = plan_here["colour"]
	(_ring.material_override as StandardMaterial3D).albedo_color = _tinted(tint, 0.7)
	(_ring.material_override as StandardMaterial3D).emission = tint
	_gate_light.light_color = tint
	# "dark" is a rule the band plays by: the floor's own light goes out and the rim does the
	# lighting. The player reads it as a place getting worse, which is what it is.
	var dark: bool = String(plan_here["rule"]) == "dark"
	_floor_light.light_energy = 0.30 if dark else 1.25
	_floor_light.light_color = tint.lightened(0.4) if dark else Color("cfe0ff")
	_warp_player(_entry_pad.global_position + Vector3(0.0, 0.9, 0.0))
	_tint_walls(tint)
	# The floor's own notice, printed on arrival: a boss's line, or what the stair looks like.
	PlayerData.log_message.emit(
		"Floor %d · %s — %s" % [depth, String(plan_here["band_name"]), String(plan_here["line"])],
		"info"
	)
	if not bool(plan_here["boss"]):
		for twist: String in plan_here["twists"]:
			if twist == "rich":
				PlayerData.log_message.emit("Something has been left on this landing.", "gain")
			elif twist == "crowded":
				PlayerData.log_message.emit("There are more of them than usual here.", "damage")
	_cleared_here = false
	_second_wave = false
	_spawn_wave(depth, false)
	# Already beaten: empty, and the way up is open. Walking back down is free.
	if Tower.cleared.has(depth):
		_cleared_here = true
		_open_gate(true)
		PlayerData.log_message.emit("This floor is already yours. The way up is open.", "info")


func _tint_walls(tint: Color) -> void:
	for wall: MeshInstance3D in _walls:
		(wall.material_override as StandardMaterial3D).albedo_color = _tinted(tint, 0.18)


func _spawn_wave(depth: int, second: bool) -> void:
	_clear_enemies()
	var plan_here: Dictionary = Tower.plan(depth)
	var count: int = maxi(0, int(plan_here["count"]) + (2 if second else 0))
	if not second:
		count = int(plan_here["count"])
	var band: int = int(plan_here["band"])
	var scale: float = 1.0 + 0.10 * float(band)
	var hp: float = clampf(PlayerData.strike_damage() * float(plan_here["blows"]), 40.0, 120000.0)
	var tint: Color = plan_here["colour"]
	var bolts: float = float(plan_here["damage"]) * 0.8 if bool(plan_here["bolts"]) else 0.0
	# Bodies around a ring, so nothing ever starts in the player's face at the door.
	for i in count:
		var angle: float = TAU * float(i) / float(maxi(1, count)) + 0.6
		var local := Vector3(cos(angle) * arena * 0.45, 0.0, sin(angle) * arena * 0.45)
		var spot: Vector3 = _stage.position + local
		var enemy: CharacterBody3D = EnemyFactory.make(scale)
		EnemyFactory.configure(enemy, hp, float(plan_here["damage"]), int(plan_here["crystals"]),
			spot, tint, 26.0, 40.0, bolts)
		enemy.set("respawn_seconds", INF)
		if String(plan_here["rule"]) == "swift":
			enemy.set("chase_speed", 5.4 * scale)
		enemy.position = local + Vector3(0.0, 0.2, 0.0)
		_floor_root.add_child(enemy)
		_enemies.append(enemy)
		enemy.died.connect(_on_enemy_died)
	if bool(plan_here["boss"]):
		var boss: CharacterBody3D = EnemyFactory.make(1.5 + 0.05 * float(band), String(plan_here["boss_name"]))
		EnemyFactory.configure(
			boss, hp * 2.6, float(plan_here["damage"]) * 1.25,
			int(plan_here["crystals"]) * 4, _stage.position, tint, 30.0, 46.0, bolts
		)
		boss.set("display_name", String(plan_here["boss_name"]))
		boss.set("respawn_seconds", INF)
		boss.position = Vector3(0.0, 0.2, -arena * 0.4)
		_floor_root.add_child(boss)
		_enemies.append(boss)
		boss.died.connect(_on_enemy_died)
		PlayerData.log_message.emit(
			"%s is standing at the top of this landing." % String(plan_here["boss_name"]),
			"damage"
		)


func _alive_count() -> int:
	var alive: int = 0
	for enemy: Node in _enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and not bool(enemy.call("is_dead")):
			alive += 1
	return alive


func _on_enemy_died(_enemy: Node3D) -> void:
	if _cleared_here:
		return
	if _alive_count() > 0:
		return
	var plan_here: Dictionary = Tower.plan(_shown_floor)
	# "reinforce": the band's fourth trick, and the only one that happens *after* the player has
	# decided the fight is over. Floors below the fifth band do not do it — a lesson before the
	# teaching has happened is just a punishment.
	if String(plan_here["rule"]) == "reinforce" and not _second_wave and _shown_floor >= 40:
		_second_wave = true
		PlayerData.log_message.emit("More of them are coming down the stair.", "damage")
		return
	_clear_floor()


func _clear_floor() -> void:
	if _cleared_here:
		return
	_cleared_here = true
	Tower.clear_floor(_shown_floor)
	Villages.report("floor", float(_shown_floor))
	_open_gate(true)


func _open_gate(open: bool) -> void:
	var material: StandardMaterial3D = _gate_pad.material_override as StandardMaterial3D
	material.albedo_color.a = 0.85 if open else 0.22
	_gate_light.light_energy = 1.5 if open else 0.0


func _clear_enemies() -> void:
	for enemy: Node in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()


func _warp_player(target: Vector3) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("warp_to"):
		return
	player.call("warp_to", target)


# ------------------------------------------------------------------ interaction

## How far out from the door itself the key still answers.
##
## The door's own position, not the tower's middle, and this is the whole bug it fixes: measured
## from the centre, the reach covered the entire footprint of the tower, so the interact key
## threw the body through the door from *anywhere* at the base — including behind the wall it is
## set into, where a player pressing E on a locked door was teleported inside it. Standing where
## a door can be reached is now the only way to reach it.
func door_reach() -> float:
	return 3.4


## What the key does here, or "" when there is nothing to press it at.
func interact_prompt() -> String:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return ""
	if Tower.inside():
		if _flat_distance(player.global_position, _entry_pad.global_position) <= 3.2:
			return Loc.say("take the stair")
		if _flat_distance(player.global_position, _gate_pad.global_position) <= 3.4:
			return Loc.say("go up") if _cleared_here else Loc.say("the floor is not clear yet")
		return ""
	if at_door(player.global_position):
		return Loc.say("the tower's door")
	return ""


## True when a body standing at `where` is in front of the door and close enough to touch it.
##
## Two conditions rather than one, because "near the door" is not the same as "at the door":
## the outward side is asked of the door's own facing, so a body inside the wall — or around the
## curve of the ring — is near it without being at it.
func at_door(where: Vector3) -> bool:
	var away: Vector3 = where - _door_world
	away.y = 0.0
	if away.length() > door_reach():
		return false
	return away.dot(_door_out) >= -0.6


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _interact_cooldown > 0.0:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# The door, from outside: a conversation rather than a key, because the stairhead and the
	# frontier are two different runs and the door is where the choice belongs.
	if not Tower.inside():
		if at_door(player.global_position):
			get_viewport().set_input_as_handled()
			Story.begin("tower_door")
		return
	if _flat_distance(player.global_position, _entry_pad.global_position) <= 3.2:
		get_viewport().set_input_as_handled()
		_interact_cooldown = 0.4
		Story.begin("tower_landing")
		return
	if _flat_distance(player.global_position, _gate_pad.global_position) <= 3.4:
		get_viewport().set_input_as_handled()
		_interact_cooldown = 0.4
		if _cleared_here and Tower.ascend():
			Audio.play("ui_select", -2.0)
		else:
			Audio.play("error", -6.0)


## The way in, called by the door conversation. Kept public so the tests drive exactly what the
## panel drives.
func walk_in(at_frontier: bool) -> bool:
	if not Tower.enter(at_frontier):
		return false
	return true


## Called by the door conversation, and by a death inside: the body comes back out to the step.
func step_out() -> void:
	Tower.leave("walked out")
	_warp_player(_base + Vector3(0.0, 1.2, -radius - 2.6))
	_clear_enemies()
	_open_gate(false)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func base_position() -> Vector3:
	return _base


func stage_floor() -> int:
	return _shown_floor


## True when this floor's way up is open: either everything on it is down or it was cleared on
## an earlier run. The landing's conversation asks this rather than re-deriving it, so the pad
## the player can see glowing and the option the panel offers cannot disagree.
func floor_open() -> bool:
	return _cleared_here


func floor_enemies() -> Array:
	return _enemies.duplicate()


# --------------------------------------------------------------------- materials

func _stone(tint: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.9
	material.metallic = 0.05
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = emission
	return material


## A tinted, slightly dark version of a colour, for surfaces that have to read as *made of* the
## band rather than lit by it.
func _tinted(tint: Color, lift: float) -> Color:
	return Color(
		lerpf(0.12, tint.r, lift), lerpf(0.13, tint.g, lift), lerpf(0.16, tint.b, lift), 1.0
	)


func _glow(tint: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	const EMISSION_SHARE := 0.35
	material.albedo_color = Color(
		tint.r * (1.0 - EMISSION_SHARE), tint.g * (1.0 - EMISSION_SHARE),
		tint.b * (1.0 - EMISSION_SHARE), alpha)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = EMISSION_SHARE
	return material


## Drops a kit piece on the ground at a world XZ. The kits disagree about where their origin
## lives — a banner's is halfway up the pole, a cauldron's is under the rim — so the piece's own
## measured box decides: the lowest point goes on the surface. That is the same rule the home
## camp and the raider camps place their props by, and it is the reason a prop can be swapped
## for another from the same kit without a hand-tuned height.
func _place_prop(path: String, at: Vector2, yaw_degrees: float) -> Node3D:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var piece: Node3D = scene.instantiate()
	add_child(piece)
	var ground: float = float(_terrain.call("surface_height_at", at.x, at.y))
	var box: AABB = _bounds(piece)
	piece.position = Vector3(at.x, ground - box.position.y, at.y)
	piece.rotation.y = deg_to_rad(yaw_degrees)
	return piece


func _bounds(node: Node, from: Transform3D = Transform3D.IDENTITY) -> AABB:
	var here: Transform3D = from * (node as Node3D).transform if node is Node3D else from
	var box := AABB()
	var found: bool = false
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			box = here * mesh_node.mesh.get_aabb()
			found = true
	for child in node.get_children():
		var child_box: AABB = _bounds(child, here)
		if child_box.size.is_zero_approx():
			continue
		box = box.merge(child_box) if found else child_box
		found = true
	return box if found else AABB()
