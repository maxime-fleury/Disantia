extends MeshInstance3D
## The night, overhead.
##
## Godot's procedural sky is a gradient with a sun in it. It does daylight beautifully and night
## not at all: by 22:00 the shader has been driven to near-black, which is the correct *colour*
## and a completely different thing from a sky. The valley at night was a dark place under a
## black lid — and a player who crosses it after dark has nothing to steer by but the minimap.
##
## So: a dome, drawn inside-out around the camera, holding stars and one moon. Three decisions
## worth the ink.
##
##   * **A dome, not a sky shader.** Replacing the `ProceduralSkyMaterial` would put the day, the
##     sunset and the fog in one hand-written shader — a rewrite of the best-looking part of the
##     game to add a detail to the worst. This draws over the top of it and is set to nothing at
##     midday.
##   * **A moon opposite the sun.** There is already a sun, and a second light in the sky would
##     mean reconciling two shadows for a disc nobody stands under. It takes the sun's own
##     direction and turns it around, which is what a moon does, and costs no light at all.
##   * **No texture.** The stars are the shader's own hash, so this file is the whole feature and
##     the web build carries none of it.
##
## The dome follows the camera every frame. That is what keeps it out of the far plane and out of
## the fog, and it is why nothing has to be sized against the map: it is not a place, it is a lid.

## Where the stars come from. High enough that the valleys between the hash cells are invisible
## and low enough that two neighbouring directions land in different cells at this resolution.
const STAR_SCALE := 190.0
## How bright the darkest of the three skies gets. Stars at a fifth is a hint; this is a night
## you can navigate by.
const MAX_NIGHT := 1.0

const SHADER: String = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded, shadows_disabled, fog_disabled;

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float star_scale = 190.0;
uniform vec3 star_tint : source_color = vec3(0.86, 0.90, 1.0);
uniform vec3 moon_tint : source_color = vec3(0.93, 0.95, 1.0);
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform float star_amount = 0.055;

varying vec3 local_dir;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	vec3 dir = normalize(local_dir);
	if (night <= 0.001) {
		ALPHA = 0.0;
	} else {
		// One star per cell, placed anywhere in it, and only the cells whose own hash clears
		// the bar get one. Two hashes rather than a star field image: a texture here would be
		// a megabyte of float noise in the web build for something the GPU can derive.
		vec3 p = dir * star_scale;
		vec3 cell = floor(p);
		vec3 spot = vec3(hash13(cell), hash13(cell + 7.0), hash13(cell + 19.0));
		float wanted = hash13(cell + 41.0);
		float star = 0.0;
		if (wanted > 1.0 - star_amount) {
			float d = length(fract(p) - spot);
			star = smoothstep(0.11, 0.015, d);
			// Brighter and dimmer stars, so the field has depth instead of being a grid of
			// equal dots — which is the difference between a sky and a bug.
			star *= 0.35 + 0.65 * hash13(cell + 61.0);
		}
		// The moon: a disc a couple of degrees across with a soft rim, because a hard circle
		// over a gradient reads as a hole in the sky.
		float to_moon = dot(dir, normalize(moon_dir));
		float disc = smoothstep(0.9975, 0.9986, to_moon);
		float halo = smoothstep(0.990, 0.9980, to_moon) * 0.25;
		ALBEDO = mix(star_tint, moon_tint, disc) * (star + halo + disc);
		ALPHA = clamp(night * (star + halo + disc * 1.4), 0.0, 1.0);
	}
	// The dome is a drawing of the sky, not a thing in it: it contributes no light.
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}
"""

## How far away the lid sits. Comfortably inside the camera's far plane and far outside
## everything the player can walk to.
const RADIUS := 900.0

var _night: float = 0.0
var _sun: DirectionalLight3D
var _camera: Camera3D
var _material: ShaderMaterial


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The dome is re-centred on the camera every frame, so it never leaves the frustum; the
	# margin only covers the frame the camera moves in.
	extra_cull_margin = 120.0
	mesh = _build_dome()
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	_material.set_shader_parameter("star_scale", STAR_SCALE)
	(mesh as SphereMesh).material = _material


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position
	if _material == null:
		return
	_night = lerpf(_night, _target_night(), clampf(4.0 * _delta, 0.0, 1.0))
	_material.set_shader_parameter("night", _night)
	_material.set_shader_parameter("moon_dir", _moon_direction())


## Inverted sphere: the shader culls front faces, so the inside is what the camera sees.
func _build_dome() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	return sphere


## How much night there is, from the clock that owns the hour. `1 - darkness` would be wrong:
## the stars have to arrive *during* dusk, over about a second of real time, or the whole sky
## switches on at the moment the sun crosses the horizon.
func _target_night() -> float:
	return clampf(Clock.darkness(), 0.0, 1.0) * MAX_NIGHT


## Where the moon is: opposite the sun. Taken from the sun's *own* basis rather than from the
## clock's table, because the sun is the thing actually in the sky, and a table and a light that
## disagree put the moon next to the sun — the one way this can look broken.
func _moon_direction() -> Vector3:
	if _sun == null or not is_instance_valid(_sun):
		_sun = get_tree().root.get_node_or_null("Main/Sun") as DirectionalLight3D
	if _sun == null:
		return Vector3(0.0, 1.0, 0.0)
	return -_sun.global_transform.basis.z.normalized()


## The whole sky at a given hour, as data: how much night, where the sun is, where the moon is.
##
## The hour is a parameter rather than an argument for poking the clock, because the clock is
## real and shared: a check that moved the world to midnight to look at the stars would leave a
## night behind it for every test that came after.
func sky_at(hour: float) -> Dictionary:
	var key: Dictionary = Clock.light_at(hour)
	var sun: Vector3 = _body_direction(float(key["elev"]), float(key["az"]))
	return {
		"night": clampf(1.0 - float(key["energy"]) / 1.5, 0.0, 1.0) * MAX_NIGHT,
		"sun": sun,
		"moon": -sun,
	}


## Where a body sits in the sky at a given elevation and azimuth, in the same convention the
## clock poses the sun in: elevation above the horizon on +Y, azimuth around it.
static func _body_direction(elev: float, az: float) -> Vector3:
	var e: float = deg_to_rad(elev)
	var a: float = deg_to_rad(az)
	return Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a))
