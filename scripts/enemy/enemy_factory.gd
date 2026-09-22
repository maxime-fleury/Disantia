extends RefCounted
## Builds an enemy body outside a raider camp.
##
## The camps had the only spawner in the project, and it is six lines of real work wrapped in
## twenty of placement: a capsule, the script, and the two properties that have to be set
## *before* the node enters the tree because `_ready` fills the health from them. That last part
## is the trap — a caller that sets `max_hp` after `add_child` gets a body with the default
## health and no error at all. So the rule lives here, once, and the tower, the guard patrols
## and the raids all come through the same door.

const EnemyScript := preload("res://scripts/enemy/enemy.gd")

## A capsule and the raider script, sized and ready to be configured. The caller sets its
## properties and then adds it to the tree.
static func make(scale_factor: float = 1.0, display_name: String = "") -> CharacterBody3D:
	var enemy := CharacterBody3D.new()
	enemy.name = display_name.replace(" ", "") if display_name != "" else "Enemy"
	enemy.set_script(EnemyScript)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36 * scale_factor
	capsule.height = 1.7 * scale_factor
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.86 * scale_factor, 0.0)
	enemy.add_child(shape)
	enemy.set("scale_factor", scale_factor)
	enemy.set("target_height", 1.78 * scale_factor)
	return enemy


## The property block that every off-camp enemy shares: what it hits for, what it pays, how far
## it sees and how long it keeps coming. Set here rather than in three callers so the tower's
## floor 3 and a raid's raider cannot quietly disagree about what a raider is.
static func configure(enemy: CharacterBody3D, hp: float, damage: float, crystals: int,
		home: Vector3, colour: Color, aggro: float = 16.0, leash: float = 30.0,
		bolts: float = 0.0) -> void:
	enemy.set("max_hp", hp)
	enemy.set("attack_damage", damage)
	enemy.set("crystals", crystals)
	enemy.set("attack_xp", 26.0)
	enemy.set("home", home)
	enemy.set("rune_color", colour)
	enemy.set("aggro_radius", aggro)
	enemy.set("leash_radius", leash)
	enemy.set("give_up_radius", leash + 4.0)
	enemy.set("bolt_damage", bolts)
