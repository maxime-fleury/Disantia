extends Node3D
## Root of the playable world.
##
## Holds the handful of things that belong to the world rather than to the player:
## the sun's angle, the global keys, and the bootstrap messages. The sun is posed
## here in code instead of in main.tscn so the scene file stays free of
## hand-written basis matrices.

@export var sun_rotation_degrees: Vector3 = Vector3(-52.0, -38.0, 0.0)

@onready var _sun: DirectionalLight3D = get_node_or_null("Sun")
@onready var _terrain: Node = get_node_or_null("Terrain")
@onready var _player: Node = get_node_or_null("Player")


func _ready() -> void:
	if _sun != null:
		_sun.rotation_degrees = sun_rotation_degrees
	PlayerData.log_message.emit("Disantia. The path begins at the foot of the mountain.", "info")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("breakthrough"):
		Cultivation.break_through()
	elif event.is_action_pressed("quick_save"):
		if PlayerData.save_game():
			PlayerData.log_message.emit("Progress recorded.", "info")


func terrain() -> Node:
	return _terrain


func player() -> Node:
	return _player
