extends StaticBody3D
## The elder: the cultivator standing by the camp fire who hands out tasks.
##
## The marker over the head is the entire interface for finding him — "!" while there
## is something to do, "?" once a task is finished and wants collecting, and nothing
## once the chain is done — so the player never has to remember to go and check. The
## tasks themselves live in the Quests autoload; this only reports them and takes the
## credit for handing them in.

const MARKER_HEIGHT := 2.35

@export var npc_name: String = "Elder Shufen"
@export var target_height: float = 1.76
@export var robe_color: Color = Color("3f6f8f")
@export var interact_radius: float = 4.5
@export var facing_degrees: float = 200.0

var _rig: Node3D
var _anim: AnimationPlayer
var _clips: Dictionary = {}
var _current: String = ""
var _marker: Label3D
var _player: Node3D
var _marker_state: String = ""
var _bob: float = 0.0


func _ready() -> void:
	add_to_group("quest_npc")
	_sit_on_ground()
	_build_body()
	_build_marker()


## Dropped onto the terrain rather than placed at a height in the scene: the camp sits
## on a levelled plateau today, and a figure floating a metre over it after any change
## to the terrain would be the first thing anyone noticed.
func _sit_on_ground() -> void:
	var terrain: Node = get_parent().get_node_or_null("Terrain")
	if terrain == null or not terrain.has_method("surface_height_at"):
		return
	global_position.y = float(
		terrain.call("surface_height_at", global_position.x, global_position.z)
	)


func _build_body() -> void:
	var scene: PackedScene = load("res://assets/characters/Monk.gltf")
	if scene == null:
		return
	_rig = scene.instantiate() as Node3D
	if _rig == null:
		return
	_rig.name = "Model"
	add_child(_rig)
	_fit_rig()
	_anim = _find_animation_player(_rig) as AnimationPlayer
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
	_rig.rotation.y = deg_to_rad(facing_degrees)


func _tint() -> void:
	for mesh in _meshes(_rig):
		for surface in mesh.mesh.get_surface_count():
			var material := StandardMaterial3D.new()
			material.albedo_color = robe_color
			material.roughness = 0.8
			material.vertex_color_use_as_albedo = true
			mesh.set_surface_override_material(surface, material)


func _meshes(node: Node, into: Array = []) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append(node)
	for child in node.get_children():
		_meshes(child, into)
	return into


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


## The clips this person needs. A villager that walks asks for its walk as well; the elder
## stands by his fire and needs nothing else.
func wanted_clips() -> Array:
	return ["Idle"]


func _resolve_clips() -> void:
	for wanted: String in wanted_clips():
		var found: String = ""
		for name in _anim.get_animation_list():
			if String(name) == wanted or String(name).get_basename() == wanted:
				found = String(name)
				break
		if found != "":
			_clips[wanted] = found
			var animation: Animation = _anim.get_animation(found)
			if animation != null:
				animation.loop_mode = Animation.LOOP_LINEAR


func _play(clip: String) -> void:
	if _anim == null or not _clips.has(clip):
		return
	var actual: String = String(_clips[clip])
	if _current == actual:
		return
	_current = actual
	_anim.play(actual)


## The marker is a Label3D rather than geometry: it always faces the camera, and a
## single character is all it has to say.
func _build_marker() -> void:
	_marker = Label3D.new()
	_marker.name = "Marker"
	_marker.text = "!"
	_marker.font_size = 220
	_marker.pixel_size = 0.006
	_marker.outline_size = 24
	_marker.outline_modulate = Color(0.05, 0.05, 0.08)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.render_priority = 4
	_marker.position = Vector3(0.0, MARKER_HEIGHT, 0.0)
	_marker.visible = false
	add_child(_marker)


func _process(delta: float) -> void:
	# The marker bobs because a still character with a still glyph over its head is
	# easy to walk straight past.
	_bob = fmod(_bob + delta, 2.2)
	if _marker != null:
		_marker.position.y = MARKER_HEIGHT + 0.12 * sin(_bob / 2.2 * TAU)
	var wanted: String = marker_state()
	if wanted == _marker_state:
		return
	_marker_state = wanted
	_marker.visible = wanted != ""
	if wanted == "?":
		_marker.text = "?"
		_marker.modulate = Color("ffd76e")
	else:
		_marker.text = "!"
		_marker.modulate = Color("cfe9ff")


## "?" when a finished task is waiting to be handed in, "!" while one is under way,
## and nothing at all once the chain is done.
func marker_state() -> String:
	if not Quests.claimable().is_empty():
		return "?"
	if not Quests.current().is_empty():
		return "!"
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not in_range():
		return
	get_viewport().set_input_as_handled()
	interact()


func _player_node() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func in_range() -> bool:
	var player: Node3D = _player_node()
	if player == null:
		return false
	var d: Vector3 = player.global_position - global_position
	d.y = 0.0
	return d.length() <= interact_radius


## Hands in a finished task, or explains the current one. Public so the tests and the
## HUD can drive exactly what the key does.
func interact() -> Dictionary:
	var handed: Dictionary = Quests.claim()
	if not handed.is_empty():
		PlayerData.log_message.emit(
			"%s: \"Well done. Take these.\"" % npc_name, "gain"
		)
		return handed
	var task: Dictionary = Quests.current()
	if task.is_empty():
		PlayerData.log_message.emit(
			"%s: \"You have done everything I know how to teach. The shelf is yours.\""
				% npc_name, "info"
		)
		# The panel opens whether or not there is a task left, because the shelf below
		# it is the other half of the conversation and it outlives the chain.
		_open_task_panel()
		return {}
	PlayerData.log_message.emit(
		"%s: \"%s\"" % [npc_name, Quests.describe(task)], "info"
	)
	_open_task_panel()
	return {}


func _open_task_panel() -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_tasks"):
		hud.call("show_tasks")


func display_name() -> String:
	return npc_name
