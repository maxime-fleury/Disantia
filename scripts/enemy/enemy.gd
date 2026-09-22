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

const DamagePopup := preload("res://scripts/ui/damage_popup.gd")
const QiBolt := preload("res://scripts/enemy/qi_bolt.gd")

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

@export_group("Champion")
## Set on the champions who hold the spirit zones, and empty on every raider. It is the
## whole difference between the two: a champion has a name, a plate over its head, a bigger
## body, more health, a permanent reward and no respawn. One script with a switch rather
## than a subclass, because everything else about the fight — the chase, the leash, the
## windup you can step out of — should be *identical*: the boss of a ring is the same fight
## you have already learned, and re-learning it is not what a champion is for.
@export var display_name: String = ""
@export var warden_id: String = ""
## Its size. A champion is a head taller than the raiders it stands with, which is the only
## signal of rank that works at forty metres in fog.
@export var scale_factor: float = 1.0
## Permanent cap grants on the kill, by stat id. Paid once, and only once: a champion does
## not come back.
@export var reward_caps: Dictionary = {}
## The aura it wears, so the ring's colour follows its champion around.
@export var rune_color: Color = Color("ffd76e")

@export_group("Ranged")
## Damage per qi bolt, and zero on everything but the Ninth. This is the one enemy in the
## game that can hurt you from further than a stride away, and that is the point of it: for
## twenty-five stages, stepping back has been a complete defence, and the last fight is
## where the player has to find a second answer.
@export var bolt_damage: float = 0.0
@export var bolt_interval: float = 3.6
@export var bolt_speed: float = 18.0
@export var bolt_range: float = 26.0
## It will not throw one closer than this: a bolt at arm's length is a melee hit with extra
## steps, and the wind-up is what gives the player time to close and punish.
@export var bolt_min_range: float = 6.0
@export var bolt_windup: float = 0.6

@export_group("Rewards")
## Crystals dropped. Two of these plus the ATTACK training is the whole payout.
@export var crystals: int = 3
@export var attack_xp: float = 26.0

## Seconds a body spends off its feet after a hard landing shakes the ground under it.
const STAGGER_SECONDS := 1.4

@export_group("Feedback")
## Seconds an enemy's own surfaces stay lit after a blow.
##
## A raider that does not visibly react is a raider you are not sure you hit; the flinch
## clip, the sound and the number all say it, but the *body* saying it is the one that reads
## at a glance in the middle of a fight. A tenth of a second is long enough to see and short
## enough that a fast swing does not leave the whole camp glowstick-lit.
@export var hit_flash_seconds: float = 0.12

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
## Set by a spared camp: does not hunt, still defends itself.
var _pacified: bool = false
var _provoked: bool = false
var _attack_timer: float = 0.0
var _swing_at: float = -1.0
var _down_timer: float = 0.0
var _flinch: float = 0.0
var _health_bar: Node3D
var _health_fill: MeshInstance3D
var _bar_full_width: float = 0.9
var _gravity: float = 9.8
var _died_announced: bool = false
## Seconds left of being knocked off its feet. A staggered body does not walk, chase or
## swing: it is the one state in this file that is not about the player at all.
var _stagger: float = 0.0
var _flash: float = 0.0
var _flash_materials: Array[StandardMaterial3D] = []
var _bolt_timer: float = 0.0
var _bolt_windup_at: float = -1.0
var _rune: OmniLight3D


## True for the named champions who hold the rings' spirit zones.
func is_champion() -> bool:
	return warden_id != ""


func _ready() -> void:
	add_to_group("enemy")
	if is_champion():
		add_to_group("champion")
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	hp = max_hp
	_build_body()
	_build_health_bar()
	if is_champion():
		_build_rune()
		_build_nameplate()
		_bolt_timer = bolt_interval


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
	var factor: float = target_height * scale_factor / bounds.size.y
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
			# A champion wears the colour of the ward it stands behind, which is how the map,
		# the fence and the enemy in front of you all say the same thing at once.
			material.albedo_color = rune_color * 0.65 if is_champion() else robe_color
			material.roughness = 0.85
			material.emission = Color("ffd9a0")
			# Trim, not a full repaint: the imported texture keeps the folds, and the
			# multiply is what makes it read as cloth rather than as paint.
			material.vertex_color_use_as_albedo = true
			material.emission_enabled = true
			material.emission = trim_color
			material.emission_energy_multiplier = 0.0
			mesh.set_surface_override_material(surface, material)
			_flash_materials.append(material)


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
## The champion's rune: a small light that breathes, so a named enemy is visible through the
## trees it is standing in. Faint, and short-range: it is a marker, not a torch.
func _build_rune() -> void:
	_rune = OmniLight3D.new()
	_rune.name = "Rune"
	_rune.light_color = rune_color
	_rune.light_energy = 1.6
	_rune.omni_range = 5.5 * scale_factor
	_rune.shadow_enabled = false
	_rune.position = Vector3(0.0, target_height * 0.6, 0.0)
	add_child(_rune)


func _build_health_bar() -> void:
	_health_bar = Node3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.position = Vector3(0.0, target_height * scale_factor + 0.55, 0.0)
	# A champion's bar is up before the first blow. A raider's appears when it is hit; a boss
	# whose health you cannot see is a boss you cannot tell you are winning against.
	_health_bar.visible = is_champion()
	add_child(_health_bar)
	if is_champion():
		_bar_full_width = 1.7 * scale_factor

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


## The name over a champion's head. Built here rather than in the scene so there is exactly
## one enemy type that can have one.
func _build_nameplate() -> void:
	var plate := Label3D.new()
	plate.name = "Nameplate"
	plate.text = display_name
	plate.font_size = 96
	plate.pixel_size = 0.0034 * scale_factor
	plate.outline_size = 22
	plate.outline_modulate = Color(0.04, 0.03, 0.05, 0.9)
	plate.modulate = rune_color.lightened(0.35)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.shaded = false
	plate.render_priority = 3
	plate.position = Vector3(0.0, target_height * scale_factor + 1.0, 0.0)
	add_child(plate)


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

## Spared at a fire by the road: stands where it is, watches, and does not hunt. The one
## thing the flag does is refuse to *start* a fight — the camp still exists, its raiders are
## still bodies in the world, and the difference is entirely in who swings first.
func pacify() -> void:
	_pacified = true
	_provoked = false
	_aggro = false


func is_pacified() -> bool:
	return _pacified


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
	# A spared raider that has been struck is in a fight from that moment on, whatever it was
	# told about the road. See `_may_pursue`.
	_provoked = true
	var dealt: float = maxf(0.0, damage)
	hp = maxf(0.0, hp - dealt)
	_health_bar.visible = true
	_update_health_bar()
	_show_damage(dealt)
	_flash = hit_flash_seconds
	_apply_flash()
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
	if is_champion():
		_fell_champion()
	else:
		PlayerData.log_message.emit(
			"Raider down. +%d crystals." % crystals, "gain"
		)
	Audio.play_at("drop", global_position, -2.0, 0.85)
	died.emit(self)


## A champion does not come back, and it leaves something behind that no raider does.
##
## Both halves are the point. The permanent reward is what makes a champion a *chapter*:
## the ring it holds is one you do not have to fight through again. And the caps it pays are
## granted through the same door as everything else — `grant_cap` — so they are caps rather
## than free stats: the ATTACK still has to be trained, and the fight only widened how far.
func _fell_champion() -> void:
	respawn_seconds = INF
	Wards.mark_warden_down(warden_id)
	var paid: Array = []
	for stat_id: String in reward_caps:
		var amount: float = float(reward_caps[stat_id])
		var granted: float = PlayerData.grant_cap(stat_id, amount)
		if granted > 0.0:
			paid.append("%s +%s" % [PlayerData.label(stat_id), String.num(granted, 1)])
	PlayerData.log_message.emit(
		"%s falls. +%d crystals%s" % [
			display_name, crystals,
			"" if paid.is_empty() else " · " + ", ".join(paid),
		],
		"breakthrough"
	)
	PlayerData.log_message.emit(
		"%s is awake, and there is no one left standing on it." % Wards.zone_name(int(warden_id_ring())),
		"cultivate"
	)
	Audio.play_at("breakthrough", global_position, 0.0, 1.0)


## The ring this champion holds, found by its id rather than passed in, so the camps and
## the wards autoload cannot disagree about which zone a champion belongs to.
func warden_id_ring() -> int:
	for gate: Dictionary in Wards.GATES:
		var warden: Dictionary = gate["warden"]
		if String(warden["id"]) == warden_id:
			return int(warden["ring"])
	return 0


## The number that pops off the body. Spawned at chest height rather than at the head, so a
## number is not hidden behind the health bar of the thing that produced it.
func _show_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	var tint: Color = rune_color if is_champion() else Color("ffd9d9")
	DamagePopup.spawn(
		get_parent(),
		global_position + Vector3(0.0, target_height * scale_factor * 0.62, 0.0),
		amount, tint
	)


## Lights every surface on the body for the remainder of the flash. Emission rather than
## albedo, because a raider in shadow has to flash too, and it decays on the clock rather
## than on a tween: an enemy can be hit three times a second and three tweens fighting over
## one material is how a body gets stuck glowing after the fight ends.
func _apply_flash() -> void:
	var amount: float = clampf(_flash / maxf(0.01, hit_flash_seconds), 0.0, 1.0)
	for material: StandardMaterial3D in _flash_materials:
		material.emission_energy_multiplier = 0.0 if amount <= 0.0 else amount * 0.9


## Knocked off its feet by a landing. `away` is the direction to be pushed in, and an empty
## vector means the shake was centred on the body itself.
##
## A stagger is deliberately not damage: what was bought by landing hard is *time* — the
## half-second of a raider getting up, and the freedom to walk past it and pick which of its
## friends to open on. A shockwave that also hurt would make the jump tree a damage tree, and
## the jump tree is supposed to be about where the body can go.
func stagger(away: Vector3) -> void:
	if is_dead():
		return
	var push: Vector3 = away
	push.y = 0.0
	if push.length_squared() < 0.0001:
		push = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	velocity = push.normalized() * 6.5
	velocity.y = 3.2
	_stagger = STAGGER_SECONDS
	# The swing in progress is dropped: a raider that was mid-axe when the ground moved should
	# not complete the blow it was aiming at the ground you used to be standing on.
	_attack_timer = maxf(_attack_timer, STAGGER_SECONDS)
	_swing_at = -1.0
	# And it notices, which is the honest thing for it to do about being thrown.
	_aggro = true
	_play("RecieveHit")
	_flash = hit_flash_seconds
	_apply_flash()
	Audio.play_at("impact", global_position, -3.0, 0.75)


## Seconds left before a staggered body is on its feet again. Zero for everything upright,
## which is what the messenger and the tests read.
func stagger_left() -> float:
	return _stagger


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
	# Spared: this one will not start anything. It will finish something, though — a raider
	# that has been hit is not standing on the road's business any more, it is in a fight,
	# and a mercy that also made a body invulnerable would not be a mercy.
	if _pacified and not _provoked:
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
	if _stagger > 0.0:
		_stagger = maxf(0.0, _stagger - delta)
		# Thrown, not walking: the push bleeds off and gravity does the rest, and nothing else in
		# this function gets a say until the body is upright again.
		velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)
		if not is_on_floor():
			velocity.y -= _gravity * delta
		else:
			velocity.y = minf(velocity.y, 0.0)
		move_and_slide()
		return
	if _flinch > 0.0:
		_flinch = maxf(0.0, _flinch - delta)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		_apply_flash()

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
	_tick_ranged(delta)

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


## The Ninth's thrown attack: wind up, then throw.
##
## The wind-up is the whole design. It fires at `bolt_interval`, it only fires when the
## player is between `bolt_min_range` and `bolt_range` — and it warns, out loud, for six
## tenths of a second before the bolt exists. A projectile with no tell is a tax on being in
## the wrong place; a projectile with a tell is a question with an answer.
func _tick_ranged(delta: float) -> void:
	if bolt_damage <= 0.0 or is_dead():
		return
	if _bolt_windup_at >= 0.0:
		_bolt_windup_at -= delta
		if _bolt_windup_at <= 0.0:
			_bolt_windup_at = -1.0
			_release_bolt()
		return
	_bolt_timer = maxf(0.0, _bolt_timer - delta)
	if _bolt_timer > 0.0 or not _aggro or not _may_pursue():
		return
	if _player == null or not is_instance_valid(_player):
		return
	var distance: float = Vector2(
		_player.global_position.x - global_position.x,
		_player.global_position.z - global_position.z
	).length()
	if distance < bolt_min_range or distance > bolt_range:
		return
	_bolt_timer = bolt_interval
	_bolt_windup_at = bolt_windup
	_play("Attack")
	Audio.play_at("ui_toggle", global_position, -6.0, 0.7)


func _release_bolt() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector3 = _player.global_position + Vector3(0.0, 0.9, 0.0) - global_position
	QiBolt.spawn(
		get_parent(),
		global_position + Vector3(0.0, target_height * scale_factor * 0.7, 0.0),
		to_player,
		bolt_damage,
		bolt_speed,
		rune_color,
		self
	)
	Audio.play_at("whoosh", global_position, -4.0, 0.7)


func _restock() -> void:
	_stagger = 0.0
	# A champion never does. `respawn_seconds` is set to infinity on the kill and read back
	# here as well, because the timer that reaches zero is the one path a boss could come
	# back through.
	if is_champion():
		return
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
