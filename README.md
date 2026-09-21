# Disantia

A cultivation game. You are a body at the foot of a long road: you run, you jump, you
carry stones and you sit and breathe, and every one of those makes the body slightly
more capable than it was. Training widens what you can hold, sitting refines what you
hold into breath, and breath is what a technique is made of.

Built in **Godot 4.7** (GDScript), 3D, with the compatibility renderer so it runs in a
browser as well as on Windows. Full controller support is not there yet; keyboard and
mouse only.

---

## Running it

You need **Godot 4.7** — the project file is `project.godot`.

```bash
# from the project root
godot --path .                      # play it in the editor's runtime
```

### Windows build

```bash
tools/export_windows.sh             # -> build/windows/Disantia.exe + Disantia.pck
```

Keep the `.exe` and the `.pck` together; the pack holds everything but the engine.
`GODOT=/path/to/godot tools/export_windows.sh` if Godot is not on your `PATH`. A
release export has no console window, but redirection still works, which is how the
test suite is run against the shipped binary (below).

### Web build

```bash
tools/export_web.sh --serve         # -> build/web/, then serves on 127.0.0.1:8791
```

The web build needs a real HTTP server — opening `index.html` off the filesystem fails
on the cross-origin isolation headers Godot's web export wants.

---

## Controls

| Key | What it does |
|---|---|
| `W` `A` `S` `D` | Move |
| `Shift` | Run — this is what trains SPEED |
| `Space` | Jump (again in the air once a task has granted it) |
| Left click / `F` | Strike |
| Right click / `Q` | Dash (unlocked by a task) |
| `X` | Qi Pressure — the aura pushed out of the body |
| `C` | Cultivate (sit and refine) — a toggle |
| `B` | Break through, when insight is full |
| `1` `2` `3` | Drill the body — pushups, squats, iron stance. Toggles |
| `E` | Talk to the elder |
| `Tab` | Settings |
| `V` | Fold the stat readout away |
| `F5` | Save (it also autosaves, and on window close) |

---

## How it plays

### Every stat is earned by doing the thing

There are seven stats and none of them has a skill point attached to it:

| Stat | Grown by |
|---|---|
| **QI** | Refining qi while meditating — spending it is what banks the progress |
| **HP** | Taking damage |
| **SPEED** | Running with `Shift` held |
| **JUMP** | Jumping, scaled by how high |
| **DEFENSE** | Weathering damage — half an xp per point taken |
| **ATTACK** | Landing blows on posts and raiders |
| **BODY** | Physical drills — pushups, squats, iron stance |

SPEED and JUMP are *allocations*: their cap is what you have earned, and a slider in
the settings panel decides how much of that cap you are actually using. Both are
hard-clamped to the earned cap, so the slider cannot dial in a number you have not
trained for. Ranks of BODY also widen the HP cap, which is what physical training is
for: it costs blood rather than qi, and it is the only path to a bigger body. Jump height has an absolute ceiling of **20 m** —
past that the body is not jumping any more, and every hill and fence laid out to be
walked would stop meaning anything.

### Cultivation

Meditating drains QI and turns it into **refinement** cycles and **insight**. Enough
insight and you break through into the next stage of the realm, which raises a
coefficient applied to everything you earn from then on — the same run pays more than
it did at the stage before. Nine stages make a realm.

### Qi Pressure

A technique rather than a key press: the aura, pushed out of the body and held there
as a shell of hostile space.

* It unlocks once the dantian holds **500 QI**.
* It costs **50 QI/s**, which is exactly what the pool hands back at **1000 QI** — at
  that depth it can be held indefinitely, and below it the field is a burst you have to
  leave.
* Its radius grows with how much you can hold, from 4 m to a hard ceiling of **12 m**,
  and tightens as the pool empties.
* Anything standing inside takes damage continuously. It is damage over time, not a
  blow: raiders caught in it will notice, and will come for you.

### The world

A **320 metre** map of rolling country — 7.5 m from the lowest point to the highest —
with eleven levelled roads radiating from the home camp and signposts along every one
of them. Everything is generated: the height field, the roads, the trees and grass, the
spirit zones, the camps. The same seed gives the same world.

* **Spirit zones** — four pillars, each gated on a cultivation stage, each multiplying
  the qi you get per second from meditating inside it.
* **The home camp** — a fenced camp with a hut, a training yard and a **safe zone**:
  a marked bubble of radius 15 m that nothing will follow you into.
* **Raider camps** — five of them, three raiders each, further out the harder. They
  aggro at range, strike you, and leash to their own fire, so a camp is a fight you can
  leave rather than one that follows you home.
* **The elder** — by the campfire, wearing a `!`. Its tasks are a chain, and finishing
  them is what unlocks your air jumps and your dash.
* **A minimap** — the terrain's own baked picture, with the spirit zones, the camps,
  the wards, the elder and you on it. North is up and the map does not spin with the
  camera.

### Combat and dying

Striking a raider pays ATTACK; being hit pays HP; killing one pays crystals, which the
elder's tasks also hand out. Dying respawns you at the spawn point and costs you
nothing — the point of the safe zone and of the leash is that retreating is always an
option.

---

## The self-test

The project has no unit-test framework: it has a headless suite that boots the real
game and drives it, `tests/self_test.gd`, run with a flag.

```bash
godot --headless --path . -- --selftest
```

It ends with a count and exits non-zero if anything failed:

```
---- self test: 589 checks, 0 failed ----
```

It is run against the **shipped binary** as well as the editor, which has caught real
bugs that only exist in a release export:

```bash
./build/windows/Disantia.exe --headless -- --selftest > log.txt 2>&1
```

Because it drives the real game, it checks claims rather than code: that twice the
health regenerates twice as fast, that a thousand qi really does hold the pressure
indefinitely (measured as net qi per game-second over a run of frames), that no amount
of jumping passes 20 m, that a raider inside the field is hurt and one outside it is
not, and that no two HUD panels overlap at either the design resolution or the window's
own. It runs on the real clock of the engine, not the wall clock, because that is the
clock the game integrates over.

---

## Layout

```
scenes/     main, player, hud, and the character/asset scenes
scripts/
  autoload/ player_data (stats, caps, save), cultivation, training, quests, audio
  player/   controller, animator, camera rig, striker, aura, qi_pressure
  world/    terrain, roads, scatter, camps, qi zones, safe zone, signposts
  ui/       hud, minimap, avatar nameplate
  enemy/    the raider
tests/      self_test.gd — the headless suite
tools/      setup_project.gd (writes project.godot), export scripts, web server
```

`tools/setup_project.gd` is the source of truth for project settings — the input map,
the autoloads, the render settings. Edit it and run it rather than hand-editing
`project.godot`:

```bash
godot --headless --path . --script tools/setup_project.gd
```

---

## Assets

The art and audio in `assets/` come from free low-poly packs, included so the project
opens and runs as-is:

* Stylized Nature MegaKit — trees, rocks, grass, plants
* Fantasy Props MegaKit — barrels, anvils, banners, furniture
* Medieval Village MegaKit — the camp hut, fences and walls
* Universal Base Characters + Universal Animation Library — the player's body and clips
* RPG Characters / Bestiary kits — the raiders
* Audio — footsteps, impacts, UI clicks

These are distributed under their own licences (the kits above are commonly released
as CC0). They are redistributed here for convenience; check each pack's own terms
before reusing them elsewhere.

The code in `scripts/`, `scenes/` and `tools/` has no licence file yet.
