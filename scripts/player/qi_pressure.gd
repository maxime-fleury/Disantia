extends Node3D
## Qi Pressure: your aura pushed out of the body and held there.
##
## A cultivator past a certain depth does not need to reach out and strike — the field
## around them is already a threat. This is that field: a bubble centred on the body,
## fed by the dantian, that hurts whatever stands inside it.
##
## Three numbers define it, and all three come from one place.
##
##   * **Unlock** — the pool has to hold `UNLOCK_QI` before the technique exists at all.
##     Below that there is not enough refined breath in the body to keep a shell of it
##     out of the skin.
##   * **Sustain** — at `SUSTAIN_QI` the pool refills exactly as fast as the pressure
##     spends it, so it can be held indefinitely. This is not a tuned coincidence: the
##     drain *is* the regeneration rate evaluated at that capacity, so the two cannot
##     drift apart when either is retuned.
##   * **Size** — the bubble's radius grows with how much the body can hold, up to a
##     hard ceiling. The ceiling is the whole point: an unbounded radius would be damage
##     to everything on the map from a standing start, which is not a technique, it is a
##     delete key.
##
## The bubble shrinks as the pool empties — down to a floor, never to nothing — because
## the alternative is a technique with only two observable states. Watching the field
## tighten as you spend it is how you know the dantian is running dry *before* it does.
##
## Everything is built in code and driven by the active aura element, so the field you
## push out is the element you are wearing: qi is a soft blue shell, fire burns hotter
## and brighter, electric snaps. The element decides the colour and the tempo; the
## capacity decides the size.

## Capacity of the qi pool, in points, before the technique exists.
const UNLOCK_QI := 500.0
## Capacity at which the drain is exactly covered by regeneration: forever sustainable.
const SUSTAIN_QI := 1000.0

## Radius at the moment of unlocking, and the hard ceiling it grows to. The ceiling is
## what keeps this a technique rather than a screen-clearing button: at 12 m the field
## reaches as far as a good leap and no further, whatever the dantian grows to.
const MIN_RADIUS := 4.0
const MAX_RADIUS := 12.0
## How much of the radius survives an empty pool. Zero would make the bubble vanish
## and then reappear, which reads as a bug rather than as an emptying tank.
const EMPTY_RADIUS_FACTOR := 0.55

## Damage a second to a body inside the field, before the aura element's own bonus.
##
## Deliberately a *pressure* rather than a blow: a near-camp raider has 55 health, so
## this is about nine seconds of standing in it. Short enough to be worth using, long
## enough that it cannot replace the strike — the field is what you hold while you
## close the distance, not what kills for you.
const DAMAGE_PER_SECOND := 6.0
## How often the damage is applied. Finite and small: a once-a-second tick makes a
## health bar jump in steps, and the raider's flinch animation restart on each one.
const TICK_SECONDS := 0.25

## Where the ring sits above the ground, so it is not z-fighting with the terrain.
const RING_HEIGHT := 0.16

var _sphere: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _active: bool = false
var _tick_accum: float = 0.0
var _phase: float = 0.0
var _built: bool = false
## The element's look, cached. Walking the aura catalogue for a colour every frame is the
## sort of cost that never shows up in a profile and never stops either; the element only
## changes when the player equips one or reaches a stage that unlocks a new one.
var _tint: Color = Color("6ec8ff")
var _tempo: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()
	_cache_element()
	PlayerData.aura_changed.connect(_on_element_changed)
	Cultivation.cultivation_changed.connect(_on_element_changed)
	_refresh_visual()


func _on_element_changed(_a: Variant = null) -> void:
	_cache_element()


# ------------------------------------------------------------------- the numbers

## True once the body can hold enough breath to keep a shell of it outside the skin.
func unlocked() -> bool:
	return PlayerData.get_cap("qi") >= UNLOCK_QI


## Qi spent per second while the pressure is held.
##
## Defined as the passive regeneration rate at `SUSTAIN_QI` rather than picked, which is
## what makes "sustainable at a thousand" a fact about the code instead of a claim about
## the balance. Retune the regen constant and this follows it.
func drain_per_second() -> float:
	var share: float = float(PlayerData.RESOURCE_REGEN["qi"])
	return share * SUSTAIN_QI


## The radius the current capacity allows, before the pool level is taken into account.
func base_radius() -> float:
	var span: float = maxf(0.001, SUSTAIN_QI - UNLOCK_QI)
	var grown: float = clampf((PlayerData.get_cap("qi") - UNLOCK_QI) / span, 0.0, 1.0)
	return lerpf(MIN_RADIUS, MAX_RADIUS, grown)


## The radius actually on screen right now: what the capacity allows, shrunk by how full
## the pool is. Never past the ceiling, whatever the two factors multiply out to.
func radius() -> float:
	var level: float = 0.0
	var cap: float = PlayerData.get_cap("qi")
	if cap > 0.0:
		level = clampf(PlayerData.get_value("qi") / cap, 0.0, 1.0)
	var scaled: float = base_radius() * (EMPTY_RADIUS_FACTOR + (1.0 - EMPTY_RADIUS_FACTOR) * level)
	return minf(MAX_RADIUS, scaled)


## Damage a second to each body standing in the field. The element you wear is what is
## being pushed out, so it is also what makes the push hurt.
func damage_per_second() -> float:
	return DAMAGE_PER_SECOND * (1.0 + Cultivation.aura_power())


func is_active() -> bool:
	return _active


## Everything about the field in one dictionary, for the HUD and the self-test. The two
## both need to say what the pressure is doing, and neither should be re-deriving the
## radius or the drain from the constants.
func state() -> Dictionary:
	return {
		"active": _active,
		"unlocked": unlocked(),
		"radius": radius(),
		"max_radius": MAX_RADIUS,
		"drain": drain_per_second(),
		"damage": damage_per_second(),
		"unlock_qi": UNLOCK_QI,
		"sustain_qi": SUSTAIN_QI,
		"element": Cultivation.active_aura(),
		"color": _element_color(),
	}


# --------------------------------------------------------------------- the switch

## Raises the field. Returns whether it is up afterwards, so a caller cannot mistake a
## refusal for a success — the two reasons to refuse are worth telling apart, and both
## are logged rather than silently doing nothing.
func start() -> bool:
	if _active:
		return true
	if not unlocked():
		PlayerData.log_message.emit(
			"Qi Pressure needs %.0f QI held. You have %.0f." % [
				UNLOCK_QI, PlayerData.get_cap("qi")
			],
			"info"
		)
		return false
	if PlayerData.get_value("qi") <= 1.0:
		PlayerData.log_message.emit("The dantian is empty — nothing to push out.", "info")
		return false
	_active = true
	_tick_accum = 0.0
	_refresh_visual()
	PlayerData.log_message.emit(
		"Qi Pressure up — %.1f m, %.0f QI/s." % [radius(), drain_per_second()],
		"cultivation"
	)
	# Pitched down, so raising the field sounds like weight rather than like a menu.
	Audio.play("ui_open", -6.0, 0.72)
	return true


func stop(reason: String = "") -> void:
	if not _active:
		return
	_active = false
	_refresh_visual()
	Audio.play("ui_close", -8.0, 0.8)
	if reason != "":
		PlayerData.log_message.emit(reason, "info")


func toggle() -> bool:
	if _active:
		stop()
		return false
	start()
	return _active


# ------------------------------------------------------------------ the per-frame

func _process(delta: float) -> void:
	# Paying can end the field, so the tick block is guarded again rather than
	# skipped by an early return: the collapse frame still has to draw the bubble
	# going out, and returning here would leave it hanging for one frame.
	if _active:
		_feed(delta)
	if _active:
		_tick_accum += delta
		while _tick_accum >= TICK_SECONDS:
			_tick_accum -= TICK_SECONDS
			_apply_damage_tick()
			if not _active:
				break
	_phase += delta
	_refresh_visual()


## Pays for the field this frame. Returns whether it is still being fed.
##
## Charged per frame rather than per damage tick, which is what makes the balance a
## balance: the pool refills continuously, so a drain that arrives in a lump every quarter
## of a second would saw the qi bar up and down around its equilibrium instead of holding
## it flat. It also makes "sustainable at a thousand" something the self-test can measure
## as an equality rather than as a trend over noisy whole ticks.
##
## The spend is asked for an exact amount and the shortfall is *not* topped up: if the pool
## cannot pay, the field stops being fed and collapses. Anything else would be a technique
## that runs on credit.
func _feed(delta: float) -> bool:
	var cost: float = drain_per_second() * delta
	var paid: float = PlayerData.spend("qi", cost)
	if paid + 0.0001 < cost or PlayerData.get_value("qi") <= 0.0:
		stop("The pressure collapses — the dantian is dry.")
		return false
	return true


## Hurts whatever is standing in the field.
func _apply_damage_tick() -> void:
	var damage: float = damage_per_second() * TICK_SECONDS
	for body: Node in get_tree().get_nodes_in_group("enemy"):
		var target := body as Node3D
		if target == null or not is_instance_valid(target):
			continue
		if target.has_method("is_dead") and bool(target.call("is_dead")):
			continue
		if target.global_position.distance_to(global_position) > radius():
			continue
		target.call("take_hit", damage, global_position)


## How many bodies the field is currently reaching. Public so the HUD can say it and
## the self-test can prove it counts what it damages.
func bodies_in_range() -> int:
	var count: int = 0
	var reach: float = radius()
	for body: Node in get_tree().get_nodes_in_group("enemy"):
		var target := body as Node3D
		if target == null or not is_instance_valid(target):
			continue
		if target.has_method("is_dead") and bool(target.call("is_dead")):
			continue
		if target.global_position.distance_to(global_position) <= reach:
			count += 1
	return count


# ------------------------------------------------------------------- the visuals

func _build() -> void:
	if _built:
		return
	_built = true
	_material = _make_material(0.14)
	_ring_material = _make_material(0.55)

	_sphere = MeshInstance3D.new()
	_sphere.name = "Shell"
	var shell := SphereMesh.new()
	shell.radius = 1.0
	shell.height = 2.0
	shell.radial_segments = 32
	shell.rings = 16
	_sphere.mesh = shell
	_sphere.material_override = _material
	# Nothing here should be in the shadow pass: a transparent shell casting one would
	# darken the character standing inside it.
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sphere)

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = TorusMesh.new()
	_ring.material_override = _ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, RING_HEIGHT, 0.0)
	add_child(_ring)

	_light = OmniLight3D.new()
	_light.name = "Pressure Light"
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.position = Vector3(0.0, 0.9, 0.0)
	add_child(_light)


## A transparent, unshaded shell. `CULL_FRONT` is the whole trick: the far wall of a
## sphere is what you see through the near one, and drawing only the far side is what
## makes a bubble read as a bubble instead of as a coloured ball around the body.
func _make_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.disable_receive_shadows = true
	material.albedo_color = Color(1, 1, 1, alpha)
	return material


## The colour and the tempo of the element being pushed out.
##
## The catalogue already carries both for the motes — a colour per element and a speed for
## how hard they orbit — and reusing them here is what keeps a wind pressure, an electric
## pressure and a fire pressure from being the same blue ball in three tints.
func _cache_element() -> void:
	var defn: Dictionary = Cultivation.aura_def(Cultivation.active_aura())
	if defn.is_empty():
		return
	if defn.has("color"):
		_tint = defn["color"]
	_tempo = maxf(0.2, float(defn.get("speed", 1.0)))


func _element_color() -> Color:
	return _tint


func _element_tempo() -> float:
	return _tempo


func _refresh_visual() -> void:
	if _sphere == null:
		return
	var tint: Color = _element_color()
	var tempo: float = _element_tempo()
	# Breathing in and out, and faster for a livelier element. A still field would read
	# as a decal painted on the world.
	var breath: float = 0.5 + 0.5 * sin(_phase * tempo * 1.8)
	var target: float = radius()
	_sphere.visible = _active
	_ring.visible = _active
	if not _active:
		_light.light_energy = 0.0
		return
	_sphere.scale = Vector3.ONE * target
	_sphere.rotate_y(0.12 * tempo * get_process_delta_time())
	var shell_alpha: float = 0.10 + 0.07 * breath
	_material.albedo_color = Color(tint, shell_alpha)
	_material.emission_enabled = true
	_material.emission = tint
	_material.emission_energy_multiplier = 0.45 + 0.25 * breath

	# The ring is re-fitted rather than scaled: a scaled torus thickens with its radius,
	# and a twelve-metre ring drawn with a metre-thick tube is a wall, not a boundary.
	var torus := _ring.mesh as TorusMesh
	if torus != null and absf(torus.outer_radius - target) > 0.05:
		torus.outer_radius = target
		torus.inner_radius = maxf(0.2, target - 0.16)
	_ring_material.albedo_color = Color(tint, 0.34 + 0.22 * breath)
	_ring_material.emission_enabled = true
	_ring_material.emission = tint
	_ring_material.emission_energy_multiplier = 0.6

	_light.light_color = tint
	_light.omni_range = target * 1.15
	_light.light_energy = 0.35 + 0.25 * breath
