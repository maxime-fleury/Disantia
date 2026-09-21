extends Node3D
## Turns the Monk (Quaternius RPG Characters, CC0) into the visible cultivator,
## and drives its eleven built-in clips from what the body is actually doing.
##
## This node *is* the controller's `Model` pivot: the controller yaws it to face
## the direction of travel, and this script owns everything inside it — the rig's
## scale, its orientation, and which clip is playing.
##
## Sizing is measured, not assumed. The kit ships a 2.95-unit-tall monk whose
## origin convention is nobody's business but the exporter's, so the rig is
## scaled to `target_height` from its own bounding box and then dropped until its
## lowest point sits on the pivot's origin, which is the CharacterBody3D's feet.
##
## There is no jump, sit or attack clip in the pack, so the state machine maps
## onto what exists: running legs for a leap, a slowed idle for a trance, the roll
## as a landing recovery. What the pack *does* have — attack, pick-up, second hit
## reaction — is left for combat to claim later.

## The visual height of the body in metres. The collision capsule is 1.7, so this
## is deliberately a head taller: a humanoid's skull should clear its capsule.
@export var target_height: float = 1.80
## The kit's characters face +Z. The controller drives its `Model` pivot so that
## its local -Z points along the direction of travel, so the rig needs half a turn.
## Flip this if a future model arrives facing the other way.
@export var model_faces_plus_z: bool = true
## How long a crossfade to use between clips.
@export var blend_seconds: float = 0.18
## Speed multiplier on the idle while meditating; the trance is a slowed breath.
@export var trance_speed: float = 0.32
## Fraction of top speed above which the run clip takes over from the walk.
@export var run_threshold: float = 0.62
## Airborne for longer than this and the landing plays the roll as a recovery.
@export var roll_after_air_seconds: float = 0.45
@export var roll_seconds: float = 0.70
@export var hit_seconds: float = 0.55
## How long a strike animation runs before locomotion takes the body back.
@export var attack_seconds: float = 0.55
## Airborne longer than this and the body holds a tuck instead of the run cycle.
## The pack has no jump clip, so without it a leap is genuinely invisible from a
## third-person camera: the legs keep cycling exactly as they did on the ground.
@export var tuck_after_air_seconds: float = 0.10
## How much the seated body rises and falls as it breathes, in metres.
@export var breath_amount: float = 0.012

## Clips that are a continuous state rather than a one-shot.
##
## The importer leaves every clip at LOOP_NONE, which is invisible on a standing
## idle — a stuck frame of a still pose is still a still pose — but freezes the run
## on the frame it ends, which is exactly the "running gets stuck after a while"
## that a player notices and a screenshot does not show.
const LOOPING_CLIPS: Array = ["Idle", "Walk", "Run"]

var _rig: Node3D
var _anim: AnimationPlayer
var _player: CharacterBody3D
var _clips: Dictionary = {}
var _current: String = ""
var _hit_timer: float = 0.0
var _roll_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_clip: String = ""
var _alternate_attack: bool = false
var _air_time: float = 0.0
var _was_on_floor: bool = true
var _measured_height: float = 0.0
var _skeleton: Skeleton3D
var _pose_name: String = ""
var _breath: float = 0.0
var _rig_base_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if get_child_count() == 0:
		push_warning("[animator] no rig instance under %s" % name)
		return
	_rig = get_child(0) as Node3D
	if _rig == null:
		push_warning("[animator] first child of %s is not a Node3D" % name)
		return

	_fit_rig()
	_anim = _find_animation_player(_rig) as AnimationPlayer
	if _anim == null:
		push_warning("[animator] no AnimationPlayer inside the rig")
		return
	_resolve_clips()
	_loop_clips()
	_skeleton = _find_skeleton(_rig) as Skeleton3D
	if _player != null and _player.has_signal("struck"):
		_player.struck.connect(_on_struck)
	print("[animator] rig %.2f m as shipped, scaled by %.3f to %.2f m, facing +Z=%s, clips %s" % [
		_measured_height, model_scale(), target_height, model_faces_plus_z, str(_clips.keys()),
	])


## Scales and seats the rig from its own measured bounds.
func _fit_rig() -> void:
	var bounds: AABB = _bounds(_rig)
	_measured_height = bounds.size.y
	if _measured_height <= 0.001:
		push_warning("[animator] rig has no measurable height")
		return
	var factor: float = target_height / _measured_height
	_rig.scale = Vector3.ONE * factor
	# Centre the footprint on the pivot and stand the lowest point on the feet.
	# Doing it from the bounding box means the exporter's origin is irrelevant.
	_rig.position = Vector3(
		-(bounds.position.x + bounds.size.x * 0.5) * factor,
		-bounds.position.y * factor,
		-(bounds.position.z + bounds.size.z * 0.5) * factor
	)
	_rig.rotation.y = PI if model_faces_plus_z else 0.0
	_rig_base_position = _rig.position


## Every clip the visible body should keep cycling. The locomotion pair is the one
## that matters: it arrives from the exporter as a one-shot.
func _loop_clips() -> void:
	for wanted: String in LOOPING_CLIPS:
		if _clips.has(wanted):
			_loop_clip(_clips[wanted])


func _find_skeleton(node: Node) -> Node:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found: Node = _find_skeleton(child)
		if found != null:
			return found
	return null


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


func _find_animation_player(node: Node) -> Node:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found: Node = _find_animation_player(child)
		if found != null:
			return found
	return null


# --------------------------------------------------------------- clip plumbing

## Logical name -> the name the imported AnimationPlayer actually uses. Importers
## disagree about prefixes ("Monk|Idle"), so each name is matched exactly first,
## then by suffix, then by substring.
func _resolve_clips() -> void:
	for wanted: String in [
		"Idle", "Walk", "Run", "Roll", "RecieveHit", "Death", "Attack", "Attack2", "PickUp",
	]:
		var found: String = _match_clip(wanted)
		if found != "":
			_clips[wanted] = found
	if not _clips.has("Idle"):
		push_warning("[animator] no idle clip found; list was %s" % str(_anim.get_animation_list()))


func _match_clip(wanted: String) -> String:
	var names: PackedStringArray = _anim.get_animation_list()
	for name in names:
		if String(name) == wanted:
			return String(name)
	for name in names:
		var text: String = String(name)
		if text.get_basename() == wanted or text.ends_with("|" + wanted):
			return text
	for name in names:
		if String(name).findn(wanted) >= 0:
			return String(name)
	return ""


func _clip(wanted: String) -> String:
	if _clips.has(wanted):
		return _clips[wanted]
	return _clips.get("Idle", "")


# ------------------------------------------------------------------ the state

func _process(delta: float) -> void:
	if _anim == null:
		return
	_hit_timer = maxf(0.0, _hit_timer - delta)
	_roll_timer = maxf(0.0, _roll_timer - delta)
	_attack_timer = maxf(0.0, _attack_timer - delta)

	var on_floor: bool = _player != null and _player.is_on_floor()
	# Landing after real airtime plays the roll, which is the closest thing the
	# pack has to a landing animation.
	if on_floor and not _was_on_floor and _air_time > roll_after_air_seconds:
		_roll_timer = roll_seconds
	_air_time = 0.0 if on_floor else _air_time + delta
	_was_on_floor = on_floor

	# The two states the pack ships no clip for take the skeleton over outright.
	var pose: String = _wanted_pose(on_floor)
	if pose != _pose_name:
		_enter_pose(pose)
	if _pose_name != "":
		_hold_pose(delta)
		return

	var wanted: String = _desired_clip(on_floor)
	if wanted != "" and wanted != _current:
		_current = wanted
		if Training.is_training():
			# A drill is a rep *repeated*, and the crouch clip is authored as a
			# one-shot, so it would otherwise freeze on the last frame.
			_loop_clip(wanted)
		_anim.play(wanted, blend_seconds)

	var want_speed: float = 1.0
	if Training.is_training():
		want_speed = Training.clip_speed()
	elif Cultivation.meditating:
		want_speed = trance_speed
	_anim.speed_scale = lerpf(_anim.speed_scale, want_speed, clampf(6.0 * delta, 0.0, 1.0))


func _desired_clip(on_floor: bool) -> String:
	if _player != null and _player.has_method("is_downed") and _player.is_downed():
		return _clip("Death")
	if _hit_timer > 0.0:
		return _clip("RecieveHit")
	if _attack_timer > 0.0 and _attack_clip != "":
		return _attack_clip
	# A drill owns the body while it runs, and its posture says which drill.
	if Training.is_training():
		var posture: String = Training.active_clip()
		if posture != "":
			return _clip(posture)
	if _roll_timer > 0.0:
		return _clip("Roll")
	if Cultivation.meditating:
		return _clip("Idle")
	var speed: float = _flat_speed()
	if not on_floor:
		# A leap has no clip of its own; running legs read as a jump from any
		# distance, where a frozen standing pose reads as a bug.
		return _clip("Run") if speed > 1.0 else _clip("Idle")
	if speed > PlayerData.max_speed() * run_threshold:
		return _clip("Run")
	if speed > 0.35:
		return _clip("Walk")
	return _clip("Idle")


func _flat_speed() -> float:
	if _player == null:
		return 0.0
	return Vector2(_player.velocity.x, _player.velocity.z).length()


## A strike, played through rather than blended away by the locomotion state.
## Alternates between the two attack clips the pack ships, so a flurry of blows
## does not read as one animation on repeat.
func play_attack() -> void:
	if _anim == null:
		return
	_attack_timer = attack_seconds
	_attack_clip = _clip("Attack2") if _alternate_attack else _clip("Attack")
	_alternate_attack = not _alternate_attack
	if _attack_clip == "":
		return
	_current = _attack_clip
	# A short blend so a second strike interrupts the first instead of queueing.
	_anim.play(_attack_clip, 0.06)


## Repeats a clip. Idle already loops; the crouch the drills borrow does not.
func _loop_clip(clip_name: String) -> void:
	var anim: Animation = _anim.get_animation(clip_name)
	if anim != null and anim.loop_mode == Animation.LOOP_NONE:
		anim.loop_mode = Animation.LOOP_LINEAR


# --------------------------------------------------------- posed states

## Which pose, if any, owns the body. A collapse and a flinch both have real clips,
## and a clip always beats a pose — a ragged hand-made pose is never an improvement
## on an animation the pack shipped.
func _wanted_pose(on_floor: bool) -> String:
	if _player != null and _player.has_method("is_downed") and _player.is_downed():
		return ""
	if _hit_timer > 0.0 or _attack_timer > 0.0:
		return ""
	if Training.is_training():
		return ""
	if Cultivation.meditating:
		# The sit wins outright, floor query or not. Entry already requires the floor and
		# the trance roots the body in place, so an airborne trance is not a state a player
		# can reach — and if the floor query flickers on a slope edge, sitting is the
		# honest read of what was asked for rather than a mid-air tuck.
		return "seated"
	if not on_floor and _air_time > tuck_after_air_seconds:
		return "airborne"
	return ""


## Poses the pack cannot express, written onto the skeleton directly.
##
## The AnimationPlayer is *stopped* while a pose holds rather than being overridden
## afterwards, and stopped rather than paused. A rotation written after the mixer
## only wins if this node happens to process later than the AnimationPlayer, which
## the scene tree does not promise; and a paused player does not stay out of the way
## either — it holds its position and goes on re-applying that pose every frame, so
## the bones get overwritten by the mixer and the hand-written pose quietly does
## almost nothing. Neither state is animated anyway, so there is nothing to lose.
func _enter_pose(pose: String) -> void:
	_pose_name = pose
	if pose == "":
		# Hand the skeleton back. The rotations this script wrote are still sitting on
		# the bones, and a clip only overwrites the tracks it actually carries, so
		# they are cleared rather than left to leak into whatever plays next.
		_reset_bones()
		# The rig was moved for the pose and has to go back too, or the body keeps the
		# seat's drop and spends the rest of the run sunk into the ground.
		_rig.position = _rig_base_position
		# A fresh blend, so leaving the trance does not snap.
		_current = ""
		return
	if _anim != null:
		_anim.stop()
	_breath = 0.0


## Writes the pose afresh every frame. The skeleton is reset first, so the angles
## never accumulate: the pose is a pure function of the character's state rather
## than of how many frames it has been held for.
func _hold_pose(delta: float) -> void:
	if _skeleton == null:
		return
	_breath += delta
	_reset_bones()
	var side: float = _left_side()
	var posed: Dictionary = {}
	for entry: Array in _pose_entries(_pose_name, side):
		var bone_name: String = String(entry[0])
		var index: int = _skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var parent_global: Transform3D = _parent_global(posed, index)
		var rest: Transform3D = _skeleton.get_bone_rest(index)
		# The frame the bone's pose rotation is applied in is parent pose * rest,
		# so an axis named in the character's own frame has to be pulled back into
		# it. Parenting the axes this way is what lets "swing the thigh out, then
		# fold the knee under it" be written the way it reads.
		var pre: Basis = (parent_global * rest).basis
		var rotation := Quaternion()
		for pair: Array in entry[1]:
			var axis: Vector3 = (pre.inverse() * (pair[0] as Vector3)).normalized()
			rotation = Quaternion(axis, deg_to_rad(float(pair[1]))) * rotation
		posed[bone_name] = parent_global * rest * Transform3D(Basis(rotation), Vector3.ZERO)
		_skeleton.set_bone_pose_rotation(index, rotation)

	# The seated body breathes; the tuck is a stiff, short-lived shape.
	var rise: float = 0.0
	if _pose_name == "seated":
		rise = sin(_breath * TAU * 0.28) * breath_amount
	_rig.position = _rig_base_position + Vector3(0.0, _pose_rig_drop(_pose_name) + rise, 0.0)


func _reset_bones() -> void:
	if _skeleton != null and _skeleton.has_method("reset_bone_poses"):
		_skeleton.reset_bone_poses()


## The parent's transform in skeleton space: either the pose already written for it
## in this pass, or its resting chain. Walking the rest chain instead of reading the
## live global pose keeps the result independent of when the engine last refreshed
## the skeleton, which is what makes the pose reproducible frame to frame.
func _parent_global(posed: Dictionary, index: int) -> Transform3D:
	var parent: int = _skeleton.get_bone_parent(index)
	if parent < 0:
		return Transform3D.IDENTITY
	var parent_name: String = _skeleton.get_bone_name(parent)
	if posed.has(parent_name):
		return posed[parent_name]
	return _rest_global(parent)


func _rest_global(index: int) -> Transform3D:
	var chain: Array = []
	var walk: int = index
	while walk >= 0:
		chain.push_front(walk)
		walk = _skeleton.get_bone_parent(walk)
	var out := Transform3D.IDENTITY
	for step: int in chain:
		out = out * _skeleton.get_bone_rest(step)
	return out


## Which way `.L` actually points, measured from the rig rather than assumed. This is
## a Blender export, and which side the left bones land on is the exporter's choice
## rather than a convention worth betting a mirrored pose on, so every lateral angle
## below is multiplied by the answer.
func _left_side() -> float:
	if _skeleton == null:
		return 1.0
	var left: int = _skeleton.find_bone("UpperLeg.L")
	var right: int = _skeleton.find_bone("UpperLeg.R")
	if left < 0 or right < 0:
		return 1.0
	var offset: float = _skeleton.get_bone_rest(left).origin.x - _skeleton.get_bone_rest(right).origin.x
	return 1.0 if offset >= 0.0 else -1.0


## How far to sink the rig for a pose. The fit stands the lowest mesh point on the
## pivot's origin, which is right for standing and wrong for everything else: a
## seated body's feet are the highest part of it, not the lowest.
func _pose_rig_drop(pose_name: String) -> float:
	match pose_name:
		"seated":
			# Enough to bring the pelvis down to a seated height, no further. The legs
			# folding is what puts the body on the ground; sinking the rig past that just
			# buries it.
			return -0.42
		"airborne":
			return 0.0
	return 0.0


## The pose itself. Axes are named in the character's own frame — +X to one side,
## +Y up, +Z the way the body faces — and are applied to each bone's *current*
## orientation, in order, so a child's entry is read after its parent has moved.
## Skeleton-space axes are used rather than per-bone ones because a Blender export
## gives every joint its own idea of which axis runs down the limb, and a rig
## rotated about the wrong one of those does not look subtly wrong, it looks broken.
func _pose_entries(pose_name: String, side: float) -> Array:
	if pose_name == "seated":
		# A cross-legged trance: thighs swung outward and hips dropped, knees folded
		# so the feet come to rest in front, spine upright, hands loose on the knees.
		return [
			["Hips", [[Vector3.RIGHT, -12.0]]],
			["UpperLeg.L", [[Vector3.BACK, 64.0 * side], [Vector3.RIGHT, -18.0]]],
			["UpperLeg.R", [[Vector3.BACK, -64.0 * side], [Vector3.RIGHT, -18.0]]],
			["LowerLeg.L", [[Vector3.UP, -104.0 * side]]],
			["LowerLeg.R", [[Vector3.UP, 104.0 * side]]],
			["Foot.L", [[Vector3.UP, 24.0 * side]]],
			["Foot.R", [[Vector3.UP, -24.0 * side]]],
			["Abdomen", [[Vector3.RIGHT, 14.0]]],
			["Torso", [[Vector3.RIGHT, 8.0]]],
			["UpperArm.L", [[Vector3.RIGHT, -38.0], [Vector3.BACK, -14.0 * side]]],
			["UpperArm.R", [[Vector3.RIGHT, -38.0], [Vector3.BACK, 14.0 * side]]],
			["LowerArm.L", [[Vector3.RIGHT, -26.0]]],
			["LowerArm.R", [[Vector3.RIGHT, -26.0]]],
		]
	if pose_name == "airborne":
		# Knees up and arms out, the shape of a leap. Held still because it lasts a
		# few tenths of a second either way.
		return [
			["UpperLeg.L", [[Vector3.RIGHT, -58.0]]],
			["UpperLeg.R", [[Vector3.RIGHT, -46.0]]],
			["LowerLeg.L", [[Vector3.RIGHT, 84.0]]],
			["LowerLeg.R", [[Vector3.RIGHT, 66.0]]],
			["Abdomen", [[Vector3.RIGHT, 10.0]]],
			["UpperArm.L", [[Vector3.BACK, -26.0 * side], [Vector3.RIGHT, 20.0]]],
			["UpperArm.R", [[Vector3.BACK, 26.0 * side], [Vector3.RIGHT, 20.0]]],
		]
	return []


## World positions of the joints a pose has to get right. Reading the skeleton back
## is the only way to tell a sit from a rig rotated about the wrong axis: to a test
## that only checks "a pose was applied", those two are identical.
func joint_positions(names: Array) -> Dictionary:
	var out: Dictionary = {}
	if _skeleton == null:
		return out
	# The engine refreshes its cached global bone poses lazily, around the point it
	# needs them for drawing. A pose written after the mixer has been stopped is
	# otherwise read back as wherever the bones were beforehand, which is
	# indistinguishable from a pose that never applied at all.
	_skeleton.force_update_all_bone_transforms()
	for bone_name: String in names:
		var index: int = _skeleton.find_bone(bone_name)
		if index < 0:
			continue
		out[bone_name] = _skeleton.global_transform * _skeleton.get_bone_global_pose(index).origin
	return out


## Bone name -> its parent's name, and for the root bones the empty string. Needed
## because a rig exported with IK carries its control bones as joints too, so the
## bone named after a limb is not necessarily the one the limb is parented under.
func bone_tree() -> Dictionary:
	var out: Dictionary = {}
	if _skeleton == null:
		return out
	for index in _skeleton.get_bone_count():
		var parent: int = _skeleton.get_bone_parent(index)
		out[_skeleton.get_bone_name(index)] = (
			_skeleton.get_bone_name(parent) if parent >= 0 else "<root>"
		)
	return out


## The local rotation actually written to a bone. Kept separate from the joint
## positions because a pose can be sitting correctly on the bones while a caller reads
## back a stale global transform, and those two failures look identical from outside —
## "the joints did not move" — while needing opposite fixes.
func bone_rotation(bone_name: String) -> Quaternion:
	if _skeleton == null:
		return Quaternion()
	var index: int = _skeleton.find_bone(bone_name)
	if index < 0:
		return Quaternion()
	return _skeleton.get_bone_pose_rotation(index)


## The clip loop modes, as the engine actually holds them.
func loop_modes() -> Dictionary:
	var out: Dictionary = {}
	if _anim == null:
		return out
	for wanted: String in _clips.keys():
		var anim: Animation = _anim.get_animation(String(_clips[wanted]))
		if anim != null:
			out[wanted] = anim.loop_mode
	return out


func current_pose() -> String:
	return _pose_name


## A fall that drew blood staggers the body. Driven off the controller's signal
## rather than off HP, so healing and stat gains can never fake a flinch.
func _on_struck(_amount: float) -> void:
	_hit_timer = hit_seconds


# ------------------------------------------------------------------- reporting

## The world-space box the visible body occupies. Only computable from the rig's
## own mesh bounds, which is exactly why the fit is measured rather than assumed:
## it is differentiable from a body that is buried or hovering.
func world_bounds() -> AABB:
	if _rig == null:
		return AABB()
	return global_transform * _bounds(_rig)


func current_clip() -> String:
	return _current


func clip_table() -> Dictionary:
	return _clips.duplicate()


func model_height() -> float:
	return _measured_height


func model_scale() -> float:
	return _rig.scale.y if _rig != null else 0.0


## The clip playback rate, so the trance's slow breathing can be observed.
func animation_speed() -> float:
	return _anim.speed_scale if _anim != null else 0.0
