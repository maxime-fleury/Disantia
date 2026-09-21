extends CharacterBody3D
## A raider: one enemy, guarding one camp.
##
## The design is about being *escapable*. It notices you at `aggro_radius`, chases, and
## strikes when it is close enough — and the moment it is `leash_radius` from its own
## fire it gives up and walks home, however close you still are. That leash is what
## makes a camp a place you can lose a fight and leave, rather than a place that
## follows you across the map, and it is also what makes the roads matter: flee down
## one and you are out of the fight.
##
## Two more rules keep the camp fair. Raiders will not enter the safe zone, and will
## not strike through its boundary, so retreating home always works. And they keep
## attacking until *they* are dead, which is what the player's own HP pool is for.
##
## Everything the player earns from a kill goes through the same doors as everything
## else: `PlayerData.gain` for the ATTACK training and crystals for the purse, so the
## cultivation coefficient applies to a fight exactly as it does to a run.

signal died(enemy: Node3D)
signal respawned(enemy: Node3D)

enum State {
	GUARD,   ## Standing at the fire, watching.
	CHASE,   ## Moving to strike range.
	STRIKE,  ## In reach, swinging on a timer.
	RETURN,  ## Leashed: walking home with no interest in the player.
	DOWN,    ## Dead, waiting to be restocked.
}

@export_group("Body")
@export var max_hp: float = 55.0
@export var target_height: float = 1.78
## Tint that separates a raider from the player at a glance. The character kit has one
## model, so the difference has to be made out of material and colour.
@export var robe_color: Color = Color("8f2f3a")
@export var trim_color: Color = Color("2a1216")

@export_group("Fight")
@export var aggro_radius: float = 16.0
## How far the player has to get before a raider that has already noticed them gives up.
## Deliberately larger than `aggro_radius`: pursuit that ended the instant you stepped
## outside the notice range would make a chase feel like a light switch, and one that
## never ended would make a camp unescapable. Between the two the raider is committed,
## and past it you are gone.
@export var give_up_radius: float = 27.0
@export var leash_radius: float = 26.0
@export var chase_speed: float = 4.2
@export var walk_speed: float = 1.7
@export var attack_range: float = 2.3
@export var attack_damage: float = 9.0
## Seconds between the start of one swing and the next.
@export var attack_interval: float = 1.7
## Seconds into a swing that the blow actually lands.
@export var attack_windup: float = 0.45
@export var turn_speed: float = 7.0

@export_group("Rewards")
## Crystals dropped. Two of these plus the ATTACK training is the whole payout.
@export var crystals: int = 3
@export var attack_xp: float = 26.0

@export_group("Reset")
## Seconds after a kill before this raider is back at its fire, so a camp is a place
## you can return to rather than a place you clear once.
@export var respawn_seconds: float = 45.0

var home: Vector3 = Vector3.ZERO
var hp: float = 55.0
var state: int = State.GUARD

var _player: CharacterBody3D
var _rig: Node3D
var _anim: AnimationPlayer
var _clips: Dictionary = {}
var _current: String = ""
var _aggro: bool = false
var _attack_timer: float = 0.0
var _swing_at: float = -1.0
var _down_timer: float = 0.0
var _flinch: float = 0.0
var _health_bar: Node3D
var _health_fill: MeshInstance3D
var _bar_full_width: float = 0.9
var _gravity: float = 9.8
var _died_announced: bool = false


func _ready() -> void:
	add_to_group("enemy")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	hp = max_hp
	_build_body()
	_build_health_bar()


## The raider is the player's own character model with a different robe. The kit ships
## one rig: reusing it means an enemy arrives with a full set of clips — walk, run,
## swing, flinch, death — instead of standing still, and the silhouette stays coherent.
func _build_body() -> void:
	var scene: PackedScene = load("res://assets/characters/Monk.gltf")
	if scene == null:
		push_warning("[enemy] character model missing")
		return
	_rig = scene.instantiate() as Node3D
	if _rig == null:
		return
	_rig.name = "Model"
	add_child(_rig)
	_fit_rig()
	_anim = _find_animation_player(_rig) as AnimationPlayer
	if _anim == null:
		return
	_resolve_clips()
	_tint()
	_play("Idle")


func _fit_rig() -> void:
	var bounds: AABB = _bounds(_rig)
	if bounds.size.y <= 0.001:
		return
	var factor: float = target_height / bounds.size.y
	_rig.scale = Vector3.ONE * factor
	_rig.position = Vector3(
		-(bounds.position.x + bounds.size.x * 0.5) * factor,
		-bounds.position.y * factor,
		-(bounds.position.z + bounds.size.z * 0.5) * factor
	)
	# The shipped rig faces +Z; the controller turns a model with -Z as its face.
	_rig.rotation.y = PI


func _tint() -> void:
	for mesh in _meshes(_rig):
		for surface in mesh.mesh.get_surface_count():
			var material := StandardMaterial3D.new()
			material.albedo_color = robe_color
			material.roughness = 0.85
			# Trim, not a full repaint: the imported texture keeps the folds, and the
			# multiply is what makes it read as cloth rather than as paint.
			material.vertex_color_use_as_albedo = true
			material.emission_enabled = true
			material.emission = trim_color
			material.emission_energy_multiplier = 0.0
			mesh.set_surface_override_material(surface, material)


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


func _meshes(node: Node, into: Array = []) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append(node)
	for child in node.get_children():
		_meshes(child, into)
	return into


func _find_animation_player(node: Node) -> Node:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found: Node = _find_animation_player(child)
		if found != null:
			return found
	return null


func _resolve_clips() -> void:
	for wanted: String in ["Idle", "Walk", "Run", "Attack", "RecieveHit", "Death"]:
		var found: String = _match_clip(wanted)
		if found != "":
			_clips[wanted] = found
	# Every clip arrives as a one-shot from the importer, which freezes a walk mid-step.
	for wanted: String in ["Idle", "Walk", "Run"]:
		if not _clips.has(wanted):
			continue
		var animation: Animation = _anim.get_animation(_clips[wanted])
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR


func _match_clip(wanted: String) -> String:
	var names: PackedStringArray = _anim.get_animation_list()
	for name in names:
		if String(name) == wanted:
			return String(name)
	for name in names:
		if String(name).get_basename() == wanted or String(name).ends_with("|" + wanted):
			return String(name)
	for name in names:
		if String(name).findn(wanted) >= 0:
			return String(name)
	return ""


func _play(clip: String) -> void:
	if _anim == null or not _clips.has(clip):
		return
	var actual: String = String(_clips[clip])
	if _current == actual:
		return
	_current = actual
	_anim.play(actual)


## A short billboarded bar over the head. Out of sight until the first blow lands: a
## full bar over every idle guard would turn a quiet camp into a wall of meters.
func _build_health_bar() -> void:
	_health_bar = Node3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.position = Vector3(0.0, target_height + 0.55, 0.0)
	_health_bar.visible = false
	add_child(_health_bar)

	var plate := MeshInstance3D.new()
	var plate_mesh := QuadMesh.new()
	plate_mesh.size = Vector2(_bar_full_width + 0.06, 0.16)
	plate.mesh = plate_mesh
	plate.material_override = _bar_material(Color(0.05, 0.04, 0.05, 0.85), 1)
	_health_bar.add_child(plate)

	_health_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(_bar_full_width, 0.1)
	_health_fill.mesh = fill_mesh
	# Drawn after the plate and without depth testing, because two billboards at the
	# same depth are a coin flip: the plate was winning and the bar read as empty.
	_health_fill.material_override = _bar_material(Color("ff6b6b"), 2)
	_health_fill.position = Vector3(0.0, 0.0, 0.002)
	_health_bar.add_child(_health_fill)


func _bar_material(tint: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = priority
	return material


# ------------------------------------------------------------------- the fight

func is_dead() -> bool:
	return state == State.DOWN


func is_knocked_out() -> bool:
	return is_dead()


func health_ratio() -> float:
	return clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)


## Applies a blow from the player. Returns the damage actually taken, which is what
## the striker pays ATTACK training for.
func take_hit(damage: float, from: Vector3 = Vector3.ZERO) -> float:
	if is_dead():
		return 0.0
	var dealt: float = maxf(0.0, damage)
	hp = maxf(0.0, hp - dealt)
	_health_bar.visible = true
	_update_health_bar()
	_flinch = 0.35
	_play("RecieveHit")
	# Being hit from outside your notice is the one thing that should look up. A raider
	# will not chase you to the ends of the map, but it will not stand there either.
	if not _aggro:
		_aggro = true
		state = State.CHASE
	if hp <= 0.0:
		_die(from)
	return dealt


func _die(from: Vector3) -> void:
	state = State.DOWN
	_down_timer = respawn_seconds
	velocity = Vector3.ZERO
	_play("Death")
	_health_bar.visible = false
	_aggro = false
	PlayerData.add_crystals(crystals)
	PlayerData.gain("attack", attack_xp)
	Quests.report("kill", 1.0)
	Quests.report("crystals", float(crystals))
	PlayerData.log_message.emit(
		"Raider down. +%d crystals." % crystals, "gain"
	)
	Audio.play_at("drop", global_position, -2.0, 0.85)
	died.emit(self)


func _update_health_bar() -> void:
	var ratio: float = health_ratio()
	_health_fill.scale.x = maxf(0.001, ratio)
	# The fill scales about its centre, so it has to slide left as it shrinks or it
	# drains towards the middle instead of towards the end.
	_health_fill.position.x = -_bar_full_width * 0.5 * (1.0 - ratio)


## True when this raider has any business moving: leashed to its camp, off its back
## foot, and outside the camp wards.
func _may_pursue() -> bool:
	if is_dead() or _player == null or not is_instance_valid(_player):
		return false
	var zone: Node = get_tree().get_first_node_in_group("safe_zone")
	if zone != null and zone.has_method("contains"):
		if bool(zone.call("contains", _player.global_position)):
			return false
		if bool(zone.call("contains", global_position)):
			return false
	var home_distance: float = Vector2(
		global_position.x - home.x, global_position.z - home.z
	).length()
	if home_distance > leash_radius:
		return false
	if _player.has_method("is_downed") and bool(_player.call("is_downed")):
		return false
	return true


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _flinch > 0.0:
		_flinch = maxf(0.0, _flinch - delta)

	if state == State.DOWN:
		_down_timer -= delta
		if _down_timer <= 0.0:
			_restock()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	_attack_timer = maxf(0.0, _attack_timer - delta)
	_tick_swing(delta)

	var to_player: Vector3 = Vector3.ZERO
	var player_distance: float = INF
	if _player != null and is_instance_valid(_player):
		to_player = _player.global_position - global_position
		player_distance = Vector2(to_player.x, to_player.z).length()

	var can_pursue: bool = _may_pursue()
	if can_pursue and player_distance <= aggro_radius:
		_aggro = true
	elif not can_pursue or player_distance > give_up_radius:
		# Without the second half of this, aggro is sticky: a raider that noticed you once
		# keeps running at full chase speed until its leash runs out, however far ahead you
		# are — which is a camp that follows you across the map in everything but name.
		_aggro = false

	var home_to: Vector3 = home - global_position
	var home_distance: float = Vector2(home_to.x, home_to.z).length()

	if _aggro and player_distance <= attack_range:
		state = State.STRIKE
	else:
		state = State.CHASE if _aggro else (State.RETURN if home_distance > 1.6 else State.GUARD)

	var wish := Vector3.ZERO
	match state:
		State.CHASE:
			wish = Vector3(to_player.x, 0.0, to_player.z).normalized() * chase_speed
			_face(to_player, delta)
		State.STRIKE:
			wish = Vector3.ZERO
			_face(to_player, delta)
			if _attack_timer <= 0.0:
				_begin_swing()
		State.RETURN:
			wish = Vector3(home_to.x, 0.0, home_to.z).normalized() * walk_speed
			_face(home_to, delta)
		_:
			wish = Vector3.ZERO

	velocity.x = move_toward(velocity.x, wish.x, 18.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z, 18.0 * delta)
	move_and_slide()

	if _flinch <= 0.0:
		_animate()


func _face(toward: Vector3, delta: float) -> void:
	if toward.length_squared() < 0.0001 or _rig == null:
		return
	var target: float = atan2(-toward.x, -toward.z)
	_rig.rotation.y = lerp_angle(_rig.rotation.y, target, clampf(turn_speed * delta, 0.0, 1.0))


func _animate() -> void:
	var flat: float = Vector2(velocity.x, velocity.z).length()
	if is_dead():
		return
	if flat > chase_speed * 0.6:
		_play("Run")
	elif flat > 0.25:
		_play("Walk")
	else:
		_play("Idle")


## Starts a swing. The blow lands `attack_windup` later, and only if the player is
## still in reach — which is what makes stepping out of range a defence rather than
## a coin flip.
func _begin_swing() -> void:
	_attack_timer = attack_interval
	_swing_at = attack_windup
	_play("Attack")
	Audio.play_at("whoosh", global_position, -8.0, randf_range(0.85, 1.0))


func _tick_swing(delta: float) -> void:
	if _swing_at < 0.0:
		return
	_swing_at -= delta
	if _swing_at > 0.0:
		return
	_swing_at = -1.0
	if not _aggro or _player == null or not is_instance_valid(_player):
		return
	var distance: float = Vector2(
		_player.global_position.x - global_position.x,
		_player.global_position.z - global_position.z
	).length()
	if distance > attack_range + 0.35:
		return
	if _player.has_method("take_enemy_blow"):
		_player.call("take_enemy_blow", attack_damage, self)


func _restock() -> void:
	hp = max_hp
	state = State.GUARD
	_aggro = false
	global_position = home + Vector3(0.0, 0.2, 0.0)
	velocity = Vector3.ZERO
	_health_bar.visible = false
	_update_health_bar()
	_play("Idle")
	respawned.emit(self)


func leash_origin() -> Vector3:
	return home


func placement() -> Vector3:
	return global_position
