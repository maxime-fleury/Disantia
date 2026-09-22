extends Node
## Autoload. The spine: three wards laid across the road out of camp, and the champions
## who hold the ground behind them.
##
## The problem this file exists to solve is that a sandbox has no *next*. Everything in
## the world was reachable in the first minute and nothing was reachable *later*: any of
## the nine sites, any camp, any spirit zone, in any order, on the day you arrived. The
## map was a minute and a half wide in every direction, and the tenth hour of play looked
## exactly like the first one.
##
## So the road out is now a sequence. A ward is a wall of qi standing across the map at a
## fixed radius: invisible while it is open, and staked in front of you while it is not.
## The only thing that opens one is a realm you have not reached yet, and since the
## fastest way to a realm is a spirit zone, and since each zone sits *inside* the ring it
## powers, the route writes itself:
##
##   break through  →  walk the road out  →  a champion holds the zone in the next ring
##                  →  fight it            →  the zone wakes  →  cultivate
##                  →  break through again …
##
## Four rings, three gates, four champions — and the last of them is the Ninth.
##
## What lives here is only the *rule*: the radii, the requirements, who holds what, and
## what has been crossed. The walls you can see are built by the world
## (`scripts/world/ward_walls.gd`), the champions are spawned by the camps, and the
## dormant zones are read by `qi_zones.gd` — so this file has no 3D in it at all and the
## whole progression can be reasoned about, tested and saved without a scene.

signal ward_passed(index: int, gate: Dictionary)
signal warden_felled(id: String, label: String)
## Any change to the progress the HUD draws. One signal rather than one per field, for the
## same reason `stats_changed` is one: a panel that has to remember which of four things to
## listen to is a panel that stops updating the day a fifth is added.
signal changed

## The rings, counted outward from the fire. Ring 0 is the home plateau; each gate opens
## the ring beyond it, and a ring is named after the ward that guards its entrance.
const RING_NAMES: Array = [
	"The Home Ward",
	"The Second Ward",
	"The Third Ward",
	"The Outer Reach",
]

## Which spirit zone powers which ring, by the zone ids in `qi_zones.gd`. Zone `r` sits in
## ring `r`, which is the whole trick: the boost that makes a realm quick is always on the
## far side of the wall that realm opens.
const RING_ZONES: Array = ["spring", "grove", "vein", "peak"]

## The gates, in order. `reach` is a fraction of the map's half-extent rather than a number
## of metres: the terrain is procedural and its size is a setting, so a wall written down in
## metres is a wall that ends up inside a mountain the day the map grows.
##
## `required_realm` is an index into Cultivation's REALMS. A realm is nine stages of
## cultivation, which is several minutes of real work even on a zone, so each ward is a
## session rather than a key.
##
## `hp_blows` is how the champion's health is set: the placer multiplies the player's own
## strike damage by it, so a champion is always about that many blows from dead whatever
## the player's ATTACK happens to be. That is deliberate and it is the opposite of what the
## raiders do. A raider's health is a fixed number, so growing ATTACK turns a fight into a
## formality — which is the reward for growing. A champion is a *fight*, and a fight that
## ends in four swings because you trained is not one. The floors and ceilings are what keep
## that honest at both ends of a save: the floor so a champion is never trivial at the
## start, the ceiling so it is never an hour at the end.
const GATES: Array = [
	{
		"id": "second",
		"name": "The Second Ward",
		"reach": 0.4125,
		"required_realm": 1,
		"color": Color("6ec8ff"),
		"warden": {
			"id": "ash_champion",
			"label": "The Ash Champion",
			"ring": 1,
			"hp_blows": 9.0, "hp_floor": 280.0, "hp_ceil": 4000.0,
			"damage": 15.0, "scale": 1.18, "crystals": 18,
			"reward": {"attack": 5.0, "hp": 120.0},
			"line": "It drinks from the grove and calls the grove its own.",
		},
	},
	{
		"id": "third",
		"name": "The Third Ward",
		"reach": 0.65,
		"required_realm": 2,
		"color": Color("c9a6ff"),
		"warden": {
			"id": "iron_champion",
			"label": "The Iron Champion",
			"ring": 2,
			"hp_blows": 11.0, "hp_floor": 900.0, "hp_ceil": 12000.0,
			"damage": 22.0, "scale": 1.3, "crystals": 45,
			"reward": {"attack": 12.0, "hp": 320.0, "defense": 4.0},
			"line": "It has been standing on the vein since before you arrived.",
		},
	},
	{
		"id": "outer",
		"name": "The Outer Ward",
		# 0.80 rather than 0.875. The last ring is the only place the Ninth and the Storm Peak
		# can stand, and at the old radius it was a fourteen-metre annulus pressed against the
		# rim of the map — too thin to hold a boss fight, a spirit zone and a place to find,
		# which is what put every candidate site for it on the wrong side of the wall.
		"reach": 0.80,
		"required_realm": 3,
		"color": Color("ffd76e"),
		"warden": {
			"id": "the_ninth",
			"label": "The Ninth",
			"ring": 3,
			"hp_blows": 20.0, "hp_floor": 2600.0, "hp_ceil": 40000.0,
			"damage": 30.0, "scale": 1.45, "crystals": 140,
			## The one enemy in the game with a ranged attack. Everything else in Disantia
			## has to close the distance, which is what makes stepping back a defence; the
			## Ninth is where that stops being true, because a final fight that is the
			## previous fight with a bigger number on it is not a final fight.
			"bolt_damage": 20.0,
			"reward": {"attack": 34.0, "hp": 900.0, "qi": 500.0},
			"line": "The ninth disciple never left. It has been waiting at the top of the road.",
		},
	},
]

## Gates crossed, and champions felled. Both are a count and a list rather than booleans
## per gate, so a gate added later cannot be silently treated as already open.
var _passed: int = 0
var _wardens_down: Array = []

## The map's half-extent, filled by the world once the terrain exists. Kept here rather
## than asked for at each use so the HUD, the map and the walls all divide by the same
## number — three copies of "how big the world is" is how they come to disagree.
var extent: float = 160.0


func _ready() -> void:
	var saved: Dictionary = PlayerData.take_loaded_wards()
	_passed = clampi(int(saved.get("passed", 0)), 0, GATES.size())
	_wardens_down = []
	var saved_wardens: Variant = saved.get("wardens", [])
	if typeof(saved_wardens) == TYPE_ARRAY:
		for entry: Variant in saved_wardens:
			_wardens_down.append(String(entry))


func save_data() -> Dictionary:
	return {"passed": _passed, "wardens": _wardens_down.duplicate()}


func reset() -> void:
	_passed = 0
	_wardens_down.clear()
	changed.emit()


# ---------------------------------------------------------------------- the rule

func gate_count() -> int:
	return GATES.size()


func passed() -> int:
	return _passed


## Radius of a gate in metres. Resolved late: the terrain is not built when the autoload
## readies, and a wall at zero metres would be a wall around the player's feet.
func radius_of(index: int) -> float:
	if index < 0 or index >= GATES.size():
		return INF
	return extent * float(GATES[index]["reach"])


## True when the gate at this index is passable: open if it was already crossed, otherwise
## if the realm behind it has been reached.
func is_open(index: int) -> bool:
	if index < _passed:
		return true
	if index < 0 or index >= GATES.size():
		return true
	return Cultivation.realm_index() >= int(GATES[index]["required_realm"])


## The realm needed to open a gate, as a name rather than an index, so a message about a
## wall can name something the player has seen on the HUD.
func realm_label_of(index: int) -> String:
	if index < 0 or index >= GATES.size():
		return ""
	var required: int = int(GATES[index]["required_realm"])
	if required >= Cultivation.REALMS.size():
		return String(Cultivation.REALMS[Cultivation.REALMS.size() - 1])
	return String(Cultivation.REALMS[required])


## Why a wall is where it is, in the player's own units: the realm required and the realm
## they are standing in.
func blocker(index: int) -> String:
	if is_open(index):
		return ""
	return "%s opens this ward — you are %s." % [
		realm_label_of(index), Cultivation.realm_label()
	]


## The ring a position falls in, counted outward. Used by the world, the map and by the
## champions' camps to know which ring they are putting something in.
func ring_at(position: Vector3) -> int:
	var distance: float = sqrt(position.x * position.x + position.z * position.z)
	var ring: int = 0
	for i in GATES.size():
		if distance >= radius_of(i):
			ring = i + 1
	return ring


## Gates a position has left behind. A position past two walls counts two however it got
## there — a save, a jump, a bug — which is what makes crossing un-forgeable.
func crossed_at(position: Vector3) -> int:
	var out: int = 0
	for i in GATES.size():
		if sqrt(position.x * position.x + position.z * position.z) >= radius_of(i):
			out = i + 1
	return out


## Records that the player has walked out past a gate. Returns false when there was nothing
## to record, so a caller can announce only the crossings that happened.
func pass_ward(index: int) -> bool:
	if index != _passed or index >= GATES.size() or not is_open(index):
		return false
	_passed = index + 1
	PlayerData.mark_dirty()
	var gate: Dictionary = GATES[index]
	PlayerData.log_message.emit(
		"%s crossed. %s opens out in front of you." % [String(gate["name"]), RING_NAMES[_passed]],
		"breakthrough"
	)
	Audio.play("confirm", -2.0)
	ward_passed.emit(index, gate)
	changed.emit()
	return true


func warden_down(id: String) -> bool:
	return _wardens_down.has(id)


func mark_warden_down(id: String) -> bool:
	if id == "" or warden_down(id):
		return false
	_wardens_down.append(id)
	PlayerData.mark_dirty()
	changed.emit()
	for i in GATES.size():
		var warden: Dictionary = GATES[i]["warden"]
		if String(warden["id"]) == id:
			warden_felled.emit(id, String(warden["label"]))
	# The last one gets a line of its own. Everything else in this file is a step on the way
	# somewhere; this is the only place the game has anything to say about arriving.
	if felled_count() >= warden_count() and _passed >= GATES.size():
		PlayerData.log_message.emit(
			"Every ward is open and every champion is down. The road ends here — the world is "
			+ "yours to walk, and nothing on it is holding you back.",
			"breakthrough"
		)
		Audio.play("breakthrough", 0.0)
	return true


func warden_of_ring(ring: int) -> Dictionary:
	for gate: Dictionary in GATES:
		var warden: Dictionary = gate["warden"]
		if int(warden["ring"]) == ring:
			return warden
	return {}


func warden_count() -> int:
	return GATES.size()


func felled_count() -> int:
	var total: int = 0
	for gate: Dictionary in GATES:
		if warden_down(String((gate["warden"] as Dictionary)["id"])):
			total += 1
	return total


# -------------------------------------------------------------------- the goal

## The one thing to do next, as a line the HUD can print.
##
## A single next step rather than a list, and that is the point of the whole file: a list
## of open objectives is the flat world again, drawn instead of walked. The order below is
## the loop itself — the champion holding the zone you need, then the cultivation that zone
## makes cheap, then the road out.
##
## `progress` is measured at the *next gate* in both of the first two cases, so the bar
## under the line always answers the same question ("how far to the next ward") while the
## line above it answers "what am I doing right now". A bar that changed meaning between
## steps would be worse than no bar.
func goal() -> Dictionary:
	var p: int = _passed
	if p >= GATES.size():
		var last: Dictionary = warden_of_ring(GATES.size())
		if not last.is_empty() and not warden_down(String(last["id"])):
			return {
				"key": "warden",
				"chapter": RING_NAMES[RING_NAMES.size() - 1],
				"title": String(last["label"]),
				"detail": "It holds %s, and it has been waiting a long time." % zone_name(GATES.size()),
				"progress": _realm_progress(p),
				"progress_text": "the last wall is behind you",
				"ready": false,
			}
		return {
			"key": "done",
			"chapter": RING_NAMES[RING_NAMES.size() - 1],
			"title": "The road ends here",
			"detail": "Every ward is open and every champion is down. The world is yours to walk.",
			"progress": 1.0,
			"progress_text": "all wards open",
			"ready": false,
		}

	var gate: Dictionary = GATES[p]
	var zone: String = String(RING_ZONES[mini(p, RING_ZONES.size() - 1)])
	var warden: Dictionary = warden_of_ring(p)
	var zone_held: bool = not warden.is_empty() and not warden_down(String(warden["id"]))
	var realm_short: bool = Cultivation.realm_index() < int(gate["required_realm"])
	var progress: float = _realm_progress(p)
	var text: String = _progress_text(p)

	if zone_held and realm_short:
		# The champion is the block on the *fast* path rather than on the path itself:
		# the realm can always be ground out at the previous zone, slowly.
		return {
			"key": "warden",
			"chapter": RING_NAMES[p],
			"title": String(warden["label"]),
			"detail": "%s It holds %s — the fastest ground you can cultivate on." % [
				String(warden.get("line", "")), zone_name(p)
			],
			"progress": progress,
			"progress_text": text,
			"ready": false,
		}
	if realm_short:
		return {
			"key": "cultivate",
			"chapter": RING_NAMES[p],
			"title": "Break through to %s" % realm_label_of(p),
			"detail": "%s needs %s. %s%s" % [
				String(gate["name"]), realm_label_of(p),
				"" if zone_name(p) == "" else "%s is awake — cultivate there, " % zone_name(p),
				"then walk the road out."
			],
			"progress": progress,
			"progress_text": text,
			"ready": false,
		}
	return {
		"key": "cross",
		"chapter": RING_NAMES[p],
		"title": "%s is open" % String(gate["name"]),
		"detail": "The wall has fallen. Walk out to %s." % RING_NAMES[mini(p + 1, RING_NAMES.size() - 1)],
		"progress": 1.0,
		"progress_text": "walk the road out",
		"ready": true,
	}


## 0..1 of the way to the realm the next gate wants. Measured in stages, because stages are
## the unit the player watches fill: one stage is one breakthrough, however long that took.
func _realm_progress(index: int) -> float:
	if index >= GATES.size():
		return 1.0
	var required: int = int(GATES[index]["required_realm"]) * Cultivation.STAGES_PER_REALM
	if required <= 0:
		return 1.0
	return clampf(float(Cultivation.tier) / float(required), 0.0, 1.0)


func _progress_text(index: int) -> String:
	if index >= GATES.size():
		return "all wards open"
	var required: int = int(GATES[index]["required_realm"]) * Cultivation.STAGES_PER_REALM
	var missing: int = maxi(0, required - Cultivation.tier)
	if missing <= 0:
		return "realm reached"
	return "%d stage%s to %s" % [missing, "" if missing == 1 else "s", realm_label_of(index)]


## The zone catalogue, read off the world script rather than copied. A second list of zone
## names here would be a second thing to remember to rename.
const QiZonesScript := preload("res://scripts/world/qi_zones.gd")


## The name of the spirit zone that powers a ring, and nothing when there is none.
func zone_name(ring: int) -> String:
	var defs: Array = QiZonesScript.ZONE_DEFS
	if ring < 0 or ring >= defs.size():
		return ""
	return String((defs[ring] as Dictionary).get("name", ""))


## True when a ring's zone is open for business: no living champion holds it. Called by the
## zone itself every frame, which is why it is a lookup rather than a cached flag.
func zone_awake(ring: int) -> bool:
	var warden: Dictionary = warden_of_ring(ring)
	if warden.is_empty():
		return true
	return warden_down(String(warden["id"]))


func summary() -> String:
	var parts: Array = []
	for i in GATES.size():
		parts.append("%s %s" % [
			String(GATES[i]["name"]),
			"open" if is_open(i) else "locked",
		])
	return "%s · %d/%d champions down" % [
		", ".join(parts), felled_count(), warden_count()
	]
