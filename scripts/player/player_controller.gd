extends CharacterBody3D
## Third-person cultivator controller.
##
## Every movement number is read live from PlayerData, so raising SPEED or JUMP
## with the HUD sliders takes effect immediately and a breakthrough is felt in
## the very next step.
##
## The controller is also where the body earns its stats:
##   * running          -> SPEED xp, one point per metre, scaled by how close to
##                         your chosen top speed you actually ran
##   * jumping          -> JUMP xp, scaled by how close to your cap you jumped
##   * landing hard     -> HP + DEFENSE xp, via fall damage
##   * pressing C       -> hands control to Cultivation, which drains QI

## Raised when a blow actually lands on the body, so the model can flinch. It is
## deliberately separate from HP changing: the HP cap growing and healing both
## raise HP without anything having hit anyone.
signal struck(amount: float)

@export_group("Movement feel")
## Multiplier on the project gravity. Jump height is derived from the *effective*
## gravity, so raising this makes the character snappier without changing how
## high the slider says you jump.
@export var gravity_scale: float = 2.4
## Fraction of top speed used when not holding Shift.
@export var walk_factor: float = 0.45
@export var ground_accel: float = 28.0
@export var air_accel: float = 10.0
@export var ground_friction: float = 32.0
@export var air_friction: float = 2.0
@export var turn_speed: float = 14.0
@export var jump_buffer_time: float = 0.12
@export var coyote_time: float = 0.12
## Applied to CharacterBody3D.floor_snap_length. Enough to stay glued to noise
## terrain without making jumps feel sticky.
@export var ground_snap_length: float = 0.55

@export_group("Slopes and steps")
## Steepest ground the body will treat as floor. Godot's default of 45 degrees turns a
## rolling hillside into a set of walls to slide off; 55 degrees is a hill you can
## walk up and, more to the point, walk *down* without launching off every shoulder.
@export var climbable_degrees: float = 55.0
## Tallest ledge the body steps over instead of stopping against. CharacterBody3D has
## no step-up of its own, so without this a 30 cm rock in the grass is a wall.
@export var step_height: float = 0.42
## How far ahead of the body the step probe looks.
@export var step_probe: float = 0.55

@export_group("Dash")
## Speed held through a dash, and how long it lasts. Only available once a task has
## taught it.
@export var dash_speed: float = 15.0
@export var dash_seconds: float = 0.18
## Fraction of the jump height an air jump carries you.
@export var air_jump_factor: float = 0.92

@export_group("Collision feel")
## Godot's default is the single biggest reason a grounded body stops dead against
## anything it brushes. With `floor_block_on_wall` left on, touching a wall while on
## the floor blocks the whole move, so a run dies at a fence post instead of sliding
## past it. Turning it off makes the wall just another surface to slide along.
@export var slide_along_walls: bool = true
## Keeps speed constant on slopes. Without it a hill silently slows the body until
## it drops under the animation's run threshold and the run looks like it gave up
## halfway up.
@export var constant_speed_on_slopes: bool = true
## The default collision margin is a hair, which judders against the terrain's own
## triangles once the body is moving at speed.
@export var collision_margin: float = 0.01

@export_group("Fall damage")
@export var fall_damage_enabled: bool = true
## Falls shorter than this are free; below the threshold you take HP damage.
@export var safe_fall_height: float = 4.0
@export var fall_damage_per_meter: float = 6.0

@export_group("Feedback")
## Metres travelled between footstep sounds. Cadence then follows speed for free:
## the same stride at a run is twice as many steps a second as at a walk.
@export var step_stride: float = 1.75
@export var footsteps_enabled: bool = true

@export_group("Collapse")
## Seconds spent down after HP runs out, before getting back up.
@export var downed_seconds: float = 4.0

@export_group("Stat income")
@export var speed_xp_per_meter: float = 1.0
@export var jump_xp_per_jump: float = 1.0
## How often the player's position is written into PlayerData for autosave.
@export var position_save_seconds: float = 3.0

var _gravity: float = 9.8
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _peak_y: float = 0.0
var _airborne: bool = false
var _position_accum: float = 0.0
var _running: bool = false
var _downed: bool = false
var _downed_timer: float = 0.0
var _glow_materials: Array[StandardMaterial3D] = []
var _step_accum: float = 0.0
var _dash_timer: float = 0.0
var _dash_cooldown: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _air_jumps_used: int = 0

## Each physical drill, with the key that holds it. Shared with the HUD so the
## panel and the input cannot drift apart.
const DRILLS: Array = [
	["train_pushups", "pushups"],
	["train_squats", "squats"],
	["train_stance", "stance"],
]

@onready var _model: Node3D = get_node_or_null("Model")
@onready var _camera_rig: Node3D = get_node_or_null("CameraRig")
@onready var _aura: Node3D = get_node_or_null("Aura")
@onready var _pressure: Node3D = get_node_or_null("QiPressure")


## The Qi Pressure field, for the HUD and the self-test. Asked for rather than reached
## for: the skill owns what it is doing, and neither of them should be reading its
## radius or its drain out of the constants.
func qi_pressure() -> Node3D:
	return _pressure


func _ready() -> void:
	add_to_group("player")
	var project_gravity: float = float(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	)
	_gravity = project_gravity * gravity_scale
	floor_snap_length = maxf(0.0, ground_snap_length)
	floor_block_on_wall = not slide_along_walls
	floor_constant_speed = constant_speed_on_slopes
	floor_max_angle = deg_to_rad(clampf(climbable_degrees, 5.0, 85.0))
	safe_margin = maxf(0.001, collision_margin)
	_prepare_glow()
	_restore_position()
	PlayerData.log_message.emit("Press C to sit and cultivate, B to break through.", "info")


## Places the player on the saved spot, or on the terrain's home plateau.
func _restore_position() -> void:
	if PlayerData.has_saved_position:
		global_position = PlayerData.world_position()
		_peak_y = global_position.y
		return
	var terrain: Node = get_parent().get_node_or_null("Terrain")
	if terrain != null and terrain.has_method("spawn_point"):
		global_position = terrain.call("spawn_point", 2.0)
	_peak_y = global_position.y


## Copies every material on the body so the meditation glow can be animated
## without touching the shared material resources the model was imported with.
##
## This walks the whole subtree and overrides each *surface*: the visible body is
## now an instanced glTF scene whose meshes sit several nodes deep, and a skinned
## character carries more than one surface. A per-surface override is also the
## only way to tint a multi-material model without flattening it to one material.
func _prepare_glow() -> void:
	if _model != null:
		_collect_glow_materials(_model)


func _collect_glow_materials(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			_glow_surfaces(child as MeshInstance3D)
		_collect_glow_materials(child)


func _glow_surfaces(mesh_node: MeshInstance3D) -> void:
	if mesh_node.mesh == null:
		return
	for surface in mesh_node.mesh.get_surface_count():
		var base: Material = mesh_node.get_active_material(surface)
		var material: StandardMaterial3D
		if base is StandardMaterial3D:
			material = (base as StandardMaterial3D).duplicate()
		else:
			material = StandardMaterial3D.new()
			material.albedo_color = Color("dbe7f5")
		material.emission_enabled = true
		material.emission = Color("6ec8ff")
		material.emission_energy_multiplier = 0.0
		mesh_node.set_surface_override_material(surface, material)
		_glow_materials.append(material)


func _physics_process(delta: float) -> void:
	_update_downed(delta)
	_update_meditation(delta)
	_update_training()
	_update_qi_pressure()

	# A trance, a drill and a collapse all root the character in place and refuse
	# to read movement input: in each of them the body is busy being something
	# other than a pair of legs. The trance is released with C, a drill with its
	# own key, and a collapse on its own timer.
	var rooted: bool = Cultivation.meditating or _downed or Training.is_training()
	var want_dir := Vector3.ZERO
	if not rooted:
		want_dir = _wish_direction()

	_running = Input.is_action_pressed("sprint") and not rooted

	if rooted:
		# Rooted in place: keep a little downward push so floor snapping holds on
		# uneven ground, but kill all horizontal motion.
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = minf(velocity.y, -1.0)
	else:
		_apply_horizontal(delta, want_dir)
		if not is_on_floor():
			velocity.y -= _gravity * delta

	_update_coyote(delta)
	_handle_jump(delta, rooted)
	_update_dash(delta, want_dir, rooted)

	if is_on_floor() and not rooted and velocity.y <= 0.0:
		# Project movement onto the slope so climbing hills needs no special case.
		#
		# Only while descending, though. This projection removes the velocity
		# component along the floor normal, and on any slope that includes most of an
		# *upward* one — so it was cancelling the leap outright. A floor normal of
		# 1.0 skips the branch below, which is exactly why flat ground looked fine and
		# why jumping over real terrain failed.
		var normal: Vector3 = get_floor_normal()
		if normal.y > 0.2 and normal.y < 0.999:
			var vertical: float = velocity.dot(normal)
			velocity -= normal * vertical
			# Walking up a slope must not *add* upward speed. Projecting onto an
			# uphill normal turns part of the horizontal run into positive Y, and
			# Godot declines to floor-snap a body whose velocity points up — so
			# sprinting uphill left the ground every few frames and came down again,
			# which reads as the body bouncing its way up a hill. The climb is not
			# lost by removing it: the slide along the floor is what carries the body
			# up the slope, and `floor_constant_speed` keeps the pace. The guard above
			# still skips this whole block for a leap, because a leap's velocity is
			# already positive by the time it runs.
			velocity.y = minf(velocity.y, 0.0)

	move_and_slide()
	_try_step_up(want_dir, rooted)

	_track_fall()
	_earn_running_xp(delta, rooted)
	_track_footsteps(delta, rooted)
	_track_facing(delta, want_dir)
	_track_position(delta)


# ------------------------------------------------------------------- movement

func _wish_direction() -> Vector3:
	var input: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)
	if input.length_squared() < 0.0001:
		return Vector3.ZERO
	if _camera_rig == null:
		return Vector3(input.x, 0.0, input.y).normalized()
	# Camera space keeps -Z as forward, which is exactly what get_vector gives us
	# ("move_forward" arrives as y = -1).
	var basis: Basis = _camera_rig.global_transform.basis
	var dir: Vector3 = basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	return dir.normalized()


## Walks the body up a low ledge instead of letting it stop dead against one.
##
## The ledge's *top face* is what gets measured: a ray is dropped a little ahead of the
## body from above step height, and if it lands on walkable ground no higher than the
## step, the body is stood on it. Measuring the foothold rather than probing for a free
## space is what makes this reliable — a body pressed against a wall is in contact with
## it, so any shape probe from there reports a collision for *every* attempted lift, up
## included, and the step never happens. The height limit is what stops it becoming a
## wall-climb: a face with no foothold within the step is a cliff, not a kerb.
func _try_step_up(dir: Vector3, rooted: bool) -> void:
	if rooted or step_height <= 0.0 or not is_on_floor() or not is_on_wall():
		return
	var heading: Vector3 = dir
	if heading.length_squared() < 0.0001:
		heading = Vector3(velocity.x, 0.0, velocity.z)
	if heading.length_squared() < 0.01:
		return
	heading = Vector3(heading.x, 0.0, heading.z).normalized()
	var feet: float = global_position.y
	# Three samples, because a ledge can be anything from a lip to a wide platform and one
	# distance would step onto a narrow kerb and miss a broad one.
	for reach: float in [step_probe * 0.7, step_probe * 1.3, step_probe * 2.0]:
		var probe: Vector3 = global_position + heading * reach + Vector3.UP * (step_height + 0.4)
		var query := PhysicsRayQueryParameters3D.create(
			probe, probe + Vector3.DOWN * (step_height + 0.55)
		)
		query.collide_with_bodies = true
		query.exclude = [get_rid()]
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		# A face is not a foothold, however close to step height its top edge is.
		if normal.y < 0.7:
			continue
		var top: float = (hit["position"] as Vector3).y
		var rise: float = top - feet
		if rise <= 0.03 or rise > step_height + 0.06:
			continue
		global_position.y = top + 0.02
		velocity.y = maxf(velocity.y, 0.0)
		return


## The dash: a short burst forward, on a cooldown the tasks can shorten. It is the
## one movement verb that is about escaping rather than arriving, which is why a
## raider's camp is where it first becomes worth having.
func _update_dash(delta: float, dir: Vector3, rooted: bool) -> void:
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	if _dash_timer > 0.0:
		_dash_timer = maxf(0.0, _dash_timer - delta)
		var flat := Vector3(_dash_dir.x, 0.0, _dash_dir.z) * dash_speed
		velocity.x = flat.x
		velocity.z = flat.z
		if _dash_timer <= 0.0:
			velocity.x *= 0.4
			velocity.z *= 0.4
		return
	if rooted or not PlayerData.has_ability("dash") or _dash_cooldown > 0.0:
		return
	if not Input.is_action_just_pressed("dash"):
		return
	var heading: Vector3 = dir
	if heading.length_squared() < 0.0001 and _model != null:
		# Nothing held: a dash goes where the body is looking, which is what the key
		# means when you are standing still and being hit.
		var yaw: float = _model.rotation.y
		heading = Vector3(-sin(yaw), 0.0, -cos(yaw))
	if heading.length_squared() < 0.0001:
		heading = Vector3(velocity.x, 0.0, velocity.z)
	if heading.length_squared() < 0.0001:
		return
	_dash_dir = heading.normalized()
	_dash_timer = dash_seconds
	_dash_cooldown = PlayerData.dash_cooldown()
	velocity.y = maxf(velocity.y, 0.0)
	Audio.play_at("whoosh", global_position, -5.0, 1.3)


func dash_ready() -> bool:
	return PlayerData.has_ability("dash") and _dash_cooldown <= 0.0


func dash_cooldown_left() -> float:
	return _dash_cooldown


func is_dashing() -> bool:
	return _dash_timer > 0.0


func _apply_horizontal(delta: float, dir: Vector3) -> void:
	if _dash_timer > 0.0:
		return
	var top_speed: float = PlayerData.max_speed()
	var target_speed: float = top_speed * (1.0 if _running else walk_factor)
	var target: Vector3 = dir * target_speed
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var accel: float = ground_accel if is_on_floor() else air_accel
	var friction: float = ground_friction if is_on_floor() else air_friction

	if dir.length_squared() > 0.0001:
		flat = flat.move_toward(target, accel * delta)
	else:
		flat = flat.move_toward(Vector3.ZERO, friction * delta)
		if flat.length() < 0.05:
			flat = Vector3.ZERO

	velocity.x = flat.x
	velocity.z = flat.z


func _update_coyote(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
		_air_jumps_used = 0
	else:
		_coyote = maxf(0.0, _coyote - delta)


## Jump velocity from the wanted height and the *effective* gravity, so the
## slider's number is the number of metres you actually clear.
func jump_velocity() -> float:
	return sqrt(2.0 * _gravity * maxf(0.01, PlayerData.max_jump_height()))


func _handle_jump(delta: float, rooted: bool) -> void:
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if not rooted and Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	if rooted or _jump_buffer <= 0.0:
		return
	if _coyote > 0.0:
		_launch(jump_velocity())
		return
	# A jump taken in the air. Only available once a task has taught it, and only as
	# many times as it has been taught, so the counter resets on landing.
	if _air_jumps_used < PlayerData.air_jumps():
		_air_jumps_used += 1
		_launch(jump_velocity() * air_jump_factor)


func _launch(speed: float) -> void:
	velocity.y = speed
	_jump_buffer = 0.0
	_coyote = 0.0
	_airborne = true
	_peak_y = global_position.y

	# A jump at your ceiling is worth full xp; deliberately jumping lower than you
	# could is worth proportionally less.
	var cap: float = maxf(0.01, PlayerData.get_cap("jump"))
	var weight: float = clampf(PlayerData.max_jump_height() / cap, 0.0, 1.0)
	PlayerData.gain("jump", jump_xp_per_jump * weight)
	Quests.report("jump", 1.0)


## Air jumps left before the body has to touch ground again.
func air_jumps_left() -> int:
	return maxi(0, PlayerData.air_jumps() - _air_jumps_used)


## Footsteps are driven by distance rather than by a timer, which is what makes
## the cadence speed itself: the same stride at a sprint is more steps a second
## than at a walk.
func _track_footsteps(delta: float, rooted: bool) -> void:
	if not footsteps_enabled or rooted or not is_on_floor():
		_step_accum = 0.0
		return
	var flat_speed: float = Vector2(velocity.x, velocity.z).length()
	if flat_speed < 0.4:
		_step_accum = 0.0
		return
	_step_accum += flat_speed * delta
	if _step_accum < step_stride:
		return
	_step_accum = 0.0
	Audio.play_at("footstep", global_position, -7.0, randf_range(0.92, 1.08))


func _earn_running_xp(delta: float, rooted: bool) -> void:
	if rooted or not _running or not is_on_floor():
		return
	var flat_speed: float = Vector2(velocity.x, velocity.z).length()
	if flat_speed < 0.5:
		return
	var top_speed: float = maxf(0.01, PlayerData.max_speed())
	var weight: float = clampf(flat_speed / top_speed, 0.0, 1.0)
	PlayerData.gain("speed", flat_speed * delta * speed_xp_per_meter * weight)
	# The elder's tasks count distance run, and this is the only place that knows it —
	# metres actually covered while running, not time spent holding the key.
	Quests.report("run", flat_speed * delta)


func _track_facing(delta: float, dir: Vector3) -> void:
	if _model == null or dir.length_squared() < 0.0001:
		return
	# The model's -Z axis is its face, so this yaw points -Z along `dir`.
	var target_yaw: float = atan2(-dir.x, -dir.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


# ------------------------------------------------------------------ fall damage

func _track_fall() -> void:
	if not is_on_floor():
		if not _airborne:
			_airborne = true
			_peak_y = global_position.y
		_peak_y = maxf(_peak_y, global_position.y)
		return

	if not _airborne:
		return
	_airborne = false
	var fall: float = _peak_y - global_position.y
	_peak_y = global_position.y
	if not fall_damage_enabled or fall < safe_fall_height:
		return
	var raw: float = (fall - safe_fall_height) * fall_damage_per_meter
	Cultivation.stop_meditation()
	struck.emit(PlayerData.apply_damage(raw))
	PlayerData.log_message.emit("Landed from %.1f m." % fall, "damage")


## Bodies that have run out of HP collapse. This is not a death screen: a few seconds
## later the cultivator wakes up back at the camp with everything intact, so a bad
## fight or a bad fall costs the walk back and nothing else. Nothing is taken away,
## and the walk home is the point — being beaten in a raider camp should end the
## attempt, not the character.
func _update_downed(delta: float) -> void:
	if _downed:
		_downed_timer -= delta
		if _downed_timer <= 0.0:
			_downed = false
			_respawn()
			return
		# Still down: the collapse check below must not be reached, or it re-arms the
		# timer every frame from the zero HP that put the body down in the first place,
		# and the body never gets up at all.
		return
	if PlayerData.get_value("hp") <= 0.0:
		_downed = true
		_downed_timer = downed_seconds
		velocity = Vector3.ZERO
		Cultivation.stop_meditation()
		PlayerData.log_message.emit("Your body gives out.", "damage")


func _respawn() -> void:
	Cultivation.stop_meditation()
	Training.stop()
	var target: Vector3 = _spawn_point()
	warp_to(target)
	PlayerData.restore_all()
	PlayerData.log_message.emit("You wake at the camp, whole.", "info")


## Where a beaten body wakes up: inside the safe zone, which is the one place raiders
## do not follow. Falls back to the terrain's own spawn point before the zone exists.
func _spawn_point() -> Vector3:
	var zone: Node = get_tree().get_first_node_in_group("safe_zone")
	if zone != null and zone.has_method("spawn_point"):
		return zone.call("spawn_point")
	var terrain: Node = get_parent().get_node_or_null("Terrain")
	if terrain != null and terrain.has_method("spawn_point"):
		return terrain.call("spawn_point", 1.5)
	return global_position + Vector3(0.0, 1.0, 0.0)


## A raider's blow, arriving from `source`.
##
## The knockback is what makes a fight feel like contact rather than a slow
## subtraction, and `struck` is what the animator flinches on. The damage itself goes
## through `PlayerData.apply_damage` like everything else, so being hit trains HP and
## DEFENSE whether it came from a fist or a fall.
func take_enemy_blow(raw: float, source: Node3D = null) -> void:
	if _downed:
		return
	var dealt: float = PlayerData.apply_damage(raw)
	struck.emit(dealt)
	Cultivation.stop_meditation()
	Audio.play_at("impact", global_position, -3.0, randf_range(0.9, 1.05))
	if dealt <= 0.0 or source == null or not is_instance_valid(source):
		return
	var away: Vector3 = global_position - source.global_position
	away.y = 0.0
	if away.length_squared() > 0.0001:
		velocity += away.normalized() * 4.5
		velocity.y = maxf(velocity.y, 1.5)


## True while the body is inside the camp wards, where nothing hunts it.
func in_safe_zone() -> bool:
	var zone: Node = get_tree().get_first_node_in_group("safe_zone")
	if zone == null or not zone.has_method("player_inside"):
		return false
	return bool(zone.call("player_inside"))


## True while the body is down and refusing input.
func is_downed() -> bool:
	return _downed


## True when the body is free to do something deliberate. The striker asks this
## instead of re-deriving the rules, so "can I strike" and "can I move" cannot
## disagree about what the character is currently busy with.
func is_ready_to_act() -> bool:
	return not _downed and not Cultivation.meditating and not Training.is_training()


func _aura_color() -> Color:
	if _aura != null and _aura.has_method("meditation_color"):
		return _aura.meditation_color()
	return Color("6ec8ff")


## Called by the world when the player is teleported, so the fall that just
## happened on the way to the new spot does not register as damage.
func reset_fall_tracking() -> void:
	_airborne = not is_on_floor()
	_peak_y = global_position.y


# ------------------------------------------------------------------- meditation


## The drill key pressed this frame, or "".
func _drill_key_pressed() -> String:
	for pair: Array in DRILLS:
		if Input.is_action_just_pressed(pair[0]):
			return String(pair[1])
	return ""


## Reads the three drill keys as toggles, the same way the trance works and for the
## same reason: a set is dozens of reps over the better part of a minute, and pinning
## a key down for that says "keep holding" where a single press says "I am doing this
## now". Holding a key to stay in a set also meant the only way to read the HUD mid-set
## was to let the set end.
##
## The key that started a drill ends it; a different drill key switches straight to
## that drill rather than requiring the first to be stopped. Starting is still refused
## in the air and while collapsed — a set may only begin with both feet down — but
## *stopping* is never refused, so a body that starts falling cannot be stuck in a
## drill it cannot leave.
##
## Deliberately rooted, like meditation: you cannot do pushups at a run, and letting the
## player walk about mid-set would turn the drills into a free background tap of xp.
func _update_training() -> void:
	if _downed:
		if Training.is_training():
			Training.stop()
		return
	var pressed: String = _drill_key_pressed()
	if pressed == "":
		return
	if Training.active == pressed:
		Training.stop()
		return
	if not is_on_floor():
		return
	# Reaching for a drill ends the trance. The two are mutually exclusive states, and
	# the meditation toggle refuses to start while a set is running, so this is the
	# only way either can follow the other.
	if Cultivation.meditating:
		Cultivation.stop_meditation()
	Training.start(pressed)


## Qi Pressure: a toggle, and the only technique the player can hold *while running*.
##
## That is not an accident of the design — the field is a few metres of hostile space
## around a moving body, so rooting it in place would leave the case it exists for (a
## raider camp) as the one case it cannot be used in. It is refused where the body is
## already busy being something else, which is the same rule the trance and the drills
## follow: a collapse, a trance, or a set.
##
## Ending the trance or the set when the pressure comes up is the other half of that
## rule. The pressure and the trance both spend qi, and running both at once would mean
## a player draining their own pool twice over with no way to tell which was which.
func _update_qi_pressure() -> void:
	if _pressure == null:
		return
	if Input.is_action_just_pressed("qi_pressure"):
		if _pressure.is_active():
			_pressure.stop()
		elif not _downed and not Cultivation.meditating and not Training.is_training():
			_pressure.start()

	# Anything that takes the body out of the player's hands drops the field, for the
	# same reason it drops the trance: it is a state the player has to be holding, and a
	# collapse is not holding anything.
	if _pressure.is_active() and (_downed or Cultivation.meditating or Training.is_training()):
		_pressure.stop("The pressure drops.")


## The trance is a toggle rather than a hold. It is a state you sit in for the
## better part of a minute, and asking a player to keep a key pinned down for that
## says "keep holding" with the hand where a single press says "stay here".
func _update_meditation(delta: float) -> void:
	if Input.is_action_just_pressed("meditate"):
		if Cultivation.meditating:
			Cultivation.stop_meditation()
		elif not _downed and is_on_floor() and not Training.is_training():
			# In the air the request is dropped rather than queued: a trance that
			# started on its own the moment you landed would be a surprise. A running
			# drill is refused for the same reason the drill refuses a trance: they
			# are two ways of holding still and the body can only do one of them.
			Cultivation.start_meditation()

	# Anything that takes the body out of the player's hands ends the trance, so a
	# seated player is never stuck in it: a collapse, or reaching for a drill.
	if Cultivation.meditating and (_downed or _drill_key_pressed() != ""):
		Cultivation.stop_meditation()

	var glow_target: float = 1.6 if Cultivation.meditating else 0.0
	var tint: Color = _aura_color()
	for material in _glow_materials:
		material.emission_energy_multiplier = move_toward(
			material.emission_energy_multiplier, glow_target, 4.0 * delta
		)
		# The trance burns in the colour of the equipped aura, so the glow and the
		# aura read as one phenomenon rather than two unrelated blues.
		material.emission = tint


## Remembers where to put the player back on the next load, every
## `position_save_seconds` — but only from a spot the body is actually standing on.
##
## A position captured in mid-air is one you would be dropped into on load, and one
## captured on the way off a ledge would drop you back over the same edge every time.
## Waiting for both feet to be down means the remembered place is always a place you
## can stand, and never an accident of a jump.
func _track_position(delta: float) -> void:
	_position_accum += delta
	if _position_accum < position_save_seconds:
		return
	if not is_on_floor():
		return
	_position_accum = 0.0
	PlayerData.remember_position(global_position)


## Teleports the player, used by the world's ascend key.
func warp_to(target: Vector3) -> void:
	global_position = target
	velocity = Vector3.ZERO
	reset_fall_tracking()
