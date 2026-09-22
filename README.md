# Disantia

A cultivation game. You are a body at the foot of a long road: you run, you jump, you
carry stones and you sit and breathe, and every one of those makes the body slightly
more capable than it was. Training widens what you can hold, sitting refines what you
hold into breath, and breath is what a technique is made of.

Built in **Godot 4.7** (GDScript), 3D, with the compatibility renderer so it runs in a
browser as well as on Windows. Full controller support is not there yet; keyboard and
mouse only.

Around the body there is now a **valley**: three walled villages with a watch that walks
beats and arrests people, a hundred-floor tower with a boss every ten floors, a bounty board
in every village, a forge that works a champion's material into a named weapon, a day and a
night, and the wound you carry home from dying.

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
| `Space` | Jump — and, once a deep enough dantian has bought Cloud Step, **hold** it in the air to walk on it |
| `R` | Throw a ball of your own aura (once QI has bought Qi Bolt) |
| Left click / `F` | Strike |
| Right click / `Q` | Dash (unlocked by a task) |
| `X` | Qi Pressure — the aura pushed out of the body |
| `T` (hold) | Attune and return to the fire. A blow breaks it |
| `C` | Cultivate (sit and refine) — a toggle |
| `B` | Break through, when insight is full |
| `1` `2` `3` | Drill the body — pushups, squats, iron stance. Toggles |
| `E` | Talk, or take a stair — whatever the line above the hint strip says is within reach |
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

### Every stat *becomes* something

A cap is a slope, and a slope has no events on it: nobody could say what the difference
between ATTACK 22 and 23 was. So each stat has thresholds, and crossing one gives the body a
**capability** rather than a number — something that changes what you can do rather than what
you are worth. The name appears at the end of that stat's own row (and the whole table is in
the `TECHNIQUES` block of the action panel), because a capability nobody can see is one nobody
will ever use.

Thresholds are multiples of that stat's *starting* cap, so "four times your starting strength"
means the same thing for a fist and for a dantian. They are derived from the caps every time a
cap moves, never granted — a save cannot be wrong about them, and there is nothing to migrate.

| Stat | ×2 | ×4 | ×5 | ×6 | ×8 | ×10 |
|---|---|---|---|---|---|---|
| **ATTACK** | | **Cleave** — a second body within 2.2 m takes 40% of every blow | | | | **Crushing** — one blow in five lands for double |
| **HP** | | **Mending** — out of a fight five seconds, wounds close three times as fast | | | **Second Wind** — once every 90 s a killing blow leaves you standing at a quarter | |
| **DEFENSE** | | **Unshaken** — blows no longer move you | | | **Warded** — 15% of every blow you take is given back | |
| **SPEED** | **Surefoot** — steeper ground stays runnable, and you are an eighth quicker | | | **Burst** — the first three quarters of a second of a sprint leaves the line a third quicker | | |
| **JUMP** | | **Softfoot** — falls hurt half as much and the safe drop is two metres deeper | | | | **Meteor** — a landing from six metres staggers everything within three and a half |
| **QI** | *fractional thresholds — listed below the table* | | | | | |
| **BODY** | **Thick Skin** — blows land eight per cent softer | | **Iron Bones** — you get up twice as fast and slide half as far | | | |

QI is the one stat whose entries are not whole multiples, because it is the one stat that buys
*range* and *altitude* rather than more of the same: **Qi Bolt** at ×2.5 — `R` throws a ball of
your equipped aura at what you are looking at, for a twentieth of the pool, at 55% of a blow;
**Deep Well** at ×3; **Cloud Step** at ×4 — hold jump off the ground and the qi holds the body
up, nine metres over the ground under your feet and well under the seventeen-metre ward fences,
paid for at 9% of the pool a second (against 5% coming back, so it is about twenty-five seconds
aloft from a full dantian *whatever its depth*); and **Jade Skin** at ×8.

And four **disciplines**, which need two stats and are the only entries that ask you to have
trained in a *direction*: Iron Skin (DEFENSE + BODY — another 12% off), Sky Step (JUMP + SPEED
— one more jump in the air), Blood Boil (HP + ATTACK — below a third of your health, blows land
a quarter harder), Dantian Bell (QI + DEFENSE — the jade shell comes back twice as fast).

### The path: four rings, three wards, four champions

This is the spine. The map is concentric, and each ring out from the fire is closed by a
**ward** — a fence of qi standing across the map at a fixed radius.

* A ward is **invisible while it is open and standing while it is not**. Walk at a shut
  one and it turns you back, and says which realm it wants.
* The only thing that opens a ward is a **realm**, not a key.
* Ring *r* holds the **spirit zone** that makes the next realm cheap, and a **champion**
  stands on that zone. The zone is asleep until the champion is down.
* A champion has a name, a plate over its head, a rune light, about ten blows' worth of
  health whatever your ATTACK happens to be, and it does not come back. Killing one pays
  crystals and widens a cap permanently — the ground behind you stays yours.

The loop, therefore, is one sentence long:

> break through → walk the road out → fight the champion holding the next zone →
> cultivate there → break through again

| Ring | Ward that opens it | Realm it wants | Champion | Zone it holds |
|---|---|---|---|---|
| The Home Ward | — | — | — | Spirit Spring |
| The Second Ward | 66 m | Qi Condensation | The Ash Champion | Whispering Grove |
| The Third Ward | 104 m | Foundation Establishment | The Iron Champion | Earth Vein |
| The Outer Reach | 140 m | Core Formation | **The Ninth** | Storm Peak |

The last one is the fight the rest is for. Unlike everything else in the game it throws
something: a **qi bolt** at anything between 6 and 26 m, aimed six tenths of a second after
a tell. Every other enemy in Disantia can be beaten by stepping back; the Ninth is where
that stops being true.

The line at the top of the HUD is the path: it names exactly one next thing, with a meter
toward the next ward underneath it. A list of open objectives would be the flat world again,
drawn instead of walked.

### Cultivation

Meditating drains QI and turns it into **refinement** cycles and **insight**. Enough
insight and you break through into the next stage of the realm, which raises a
coefficient applied to everything you earn from then on — the same run pays more than
it did at the stage before. Nine stages make a realm.

### The qi arts

Three things the dantian does beyond replenishing itself, and the only three in the game that
act at a distance rather than at arm's length.

* **Qi Bolt** (QI ×2.5, `R`) — the aura, thrown. It wears the colour of whatever element you
  have equipped, it reaches about thirty metres, and it costs a twentieth of the pool per
  throw, so how many you can put in the air in one breath is a statement about the pool. A
  cooldown stops it being a gun.
* **Cloud Step** (QI ×4, hold `Space` airborne) — a floor made of qi, nine metres up. It is a
  hold rather than a press because a flight made of taps is a double jump with better manners,
  and it is paid for the whole time it is on. The ceiling is measured from the ground under the
  body, so it follows the country rather than a plane in the sky, and it is deliberately below
  the ward fences: a power that let a body step over one would sell the path of rings, the three
  champions and the four spirit zones for the price of a held key.

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

* **Spirit zones** — one per ring, each multiplying the qi you get per second from
  meditating inside it (×1.5 to ×3.5), and each held by the champion of its ring until
  you take it. The furthest is also gated on a cultivation stage.
* **The home camp** — a fenced camp with a hut, a training yard and a **safe zone**:
  a marked bubble of radius 15 m that nothing will follow you into.
* **Raider camps** — seven of them spread across the rings, plus the three champion
  camps standing on the spirit zones. Raiders in a deeper ring hit harder and drop more;
  they aggro at range, strike you, and leash to their own fire, so a camp is a fight you
  can leave rather than one that follows you home. Ordinary camps keep 26 m clear of a
  spirit zone, because a trance broken every few seconds is not a zone you can use.
* **The elder** — by the campfire, wearing a `!`. Its tasks are a chain, and finishing
  them is what unlocks your air jumps and your dash.
* **Nine sites to find** — one beside each of nine roads, each a small arrangement of
  kit under a tall pillar of light. Walk into one and it is yours: crystals, and a
  permanent raise to one stat's cap. Finding it puts the light out. Nothing signposts
  them; the roads are the signpost, and the number in the map's legend is the only hint
  of how many are left.
* **The elder's shelf** — crystals buy permanent things: cap raises for HP, QI, ATTACK,
  DEFENSE, SPEED and JUMP, a shorter dash cooldown, and extra air jumps. Every ware is
  repeatable with a rising price, and the two abilities stop at a ceiling.
* **A minimap** — the terrain's own baked picture, with the spirit zones, the camps,
  the wards, the sites you have found, the elder and you on it. North is up and the map
  does not spin with the camera.
* **A compass** — a mark at the edge of the screen naming the nearest site you have not
  found yet and how far the walk is. It stops pointing once every one of them is yours.
* **The rim** — the terrain is a square mesh and there is nothing beyond it. An invisible
  boundary holds you on the ground there is, because walking off the edge of the world
  used to end a session with no explanation and no way back.

### The people

Three of them besides the elder, built from a table rather than placed by hand, each with a
name over their head and something to say. Walking up and pressing `E` opens a conversation
across the foot of the screen — the world keeps running behind it, and you cannot walk out of
the middle of a sentence.

* **Master Ren**, at the training yard, asks what your hands are for. One answer only, and it
  is final: **the heavier hand** (ATTACK cap permanently +8) or **the deeper breath** (QI cap
  permanently +60). Whoever you did not choose never offers again.
* **Xia the Firekeeper**, who has watched every camp smoke from the hill, asks what to do
  about the raiders once your hands have learned something. **Burn their camp** and its
  raiders are gone from the world for good, plus 45 crystals; **let them keep their fire** and
  they will never raise a hand to you again, plus a permanent 6 to your DEFENSE cap. The camp
  is chosen for you — the nearest to the home fire — and the world remembers which one.
* **Old Bo**, who walks the road with other people's accounts — the elder's own ledger among
  them. Walk it back and the shelf is **12% cheaper for the rest of the run**; say nothing and
  it is **60 crystals now**.
* **Renown** — nobody reads your stat sheet; they read how *much* of you there is. The greeting
  changes at four rungs of the power level, from *you are new here* to a line that is not
  meant as flattery. A body that has grown is spoken to differently, and it is the same four
  lines for everyone, because a world where the crowd agrees about you is the point.

A decision is written into the save, so it survives the session — including the *world's* side
of it: the camps are told what you decided as they are built, because a map that regenerates
with a burned camp standing again would make the choice a session-long trinket.

### Combat and dying

Striking a raider pays ATTACK, prints the number that just came off it, and lights the body
up for a tenth of a second; being hit pays HP; killing one pays crystals, which the
elder's tasks and the sites out in the world also hand out. Crystals are spent at the
elder's shelf, so the fight, the walk and the training all feed the same purse.

Dying respawns you at the spawn point and costs you nothing you cannot work off: a **wound**.
Wounds stack, make you take more damage and breathe back less qi, and close on their own out of
a fight — or at a village healer, or in a spirit zone, fast. It is deliberately *not* a timer:
the punishment for dying is a walk and a decision, not three minutes of watching a number go
down while you are not allowed to play.

### The three villages

Hollowmere, Stonewatch and Towerfall — one beside the road of each ring, each a levelled square
with a palisade, a gate, a well, huts, its own **specialty** (the herbalist, the smith, the
scholar) and **five people** with names over their heads. They are **sanctuaries**: nothing
follows you inside a palisade, and the watch walks *outside* it, which is where the fighting is
meant to happen.

* **A road rather than a checklist** — finishing a village's business hands you something to
  carry to the next one, so the map is walked in an order instead of picked over.
* **Reputation, village by village** — serving one is noticed by the others, and what a
  villager says to you depends on how much of you there is and what you have done elsewhere.
* **The bounty board** — each village posts named marks: an ordinary raider with a *name*, a
  modifier and a price. The fight is one you already know; the name is what makes it an event,
  and the price is paid at the board, which is why the mark is worth walking back for.
* **The forge** — the smith takes a **signed material** (a champion's, or a mark's) and works it
  into a named weapon whose look changes at the tiers. Gear *multiplies* what you trained and
  never replaces it: an arm that hits for a flat +20 would make the training pointless.
* **The watch** — guards walk beats outside every gate, hunt raiders, and keep the peace.
* **Getting wanted** — strike a villager and you are **hunted**: the watch comes for you, the
  shops shut and the prices rise. Being caught is a **cell** — a door in the world with a fine
  on it — not a menu and not a timer.

### The Tower of the Tenth Seat

A hundred floors of composed arena on the far road: **ten bands** of ten, each band with its own
theme, colour and rule (a band that is dark, a band that burns), and a **boss every ten**. The
arena is one set that moves and repaints, so a hundred floors is a hundred *fights* rather than a
hundred rooms.

What makes it a climb rather than a corridor is that **nothing resets between floors**: no
trance to sit in, no shelf, and the only healing is what you carried in. The way down is always
open, your best depth is kept, and the crown is the highest thing on the map by an order of
magnitude — you can see what you have not done yet from thirty metres away.

The way in is a conversation at the door rather than a key: the stairhead and the frontier are two
different runs, and the door is where the choice belongs. For a long time that conversation was
the *only* way in and nothing said so — the climb was reachable and unreachable at once. The hint
strip now answers for the whole world: anything in the `interactable` group says what the key
would do and how far away it counts, and the nearest one wins.

### One line that says what is happening

Four systems have nothing to do with each other and share a single line at the foot of the
screen — the sanctuaries, the law, the tower and the clock. Standing in a village names it,
being on a floor names the floor and its band, being wanted names the rung *and* the sum that
settles it, and a wound from dying is counted there rather than buried in a panel. Each part
appears only when it has something true to say: a strip with four permanent segments is a strip
nobody reads.

### Day and night

The clock runs at a pace you can watch: the sun's colour and angle, the sky and the fog move
with it, meditating hurries time along, and the night changes what the world is like to be out
in — the wards read differently, aggression and leashes shift, and the gates of a village are
the only thing worth standing behind.

Night is also a *sky*. Godot's procedural sky is a gradient with a sun in it, which does daylight
beautifully and night not at all; a dome carrying stars and a moon is drawn over the top of it and
faded out by the clock, so midday is untouched. The moon takes the sun's own direction and turns
it around — there is already one light in this world and a second would have to be reconciled with
its shadows — and the stars are the shader's own hash rather than a texture, so the web build
carries none of them.

### Two languages

English and French, switched in the settings panel, remembered in the save.

**The English sentence is the key.** A symbolic key (`QUEST_FIRST_STEPS`) needs a second file
mapping keys to English before a single word is translated, and a sentence typed in the code and
never listed in the table is then *invisible* — nothing can find it. With the English as the key, a
missing row simply *is* the English: the game is never broken or blank by an untranslated line, and
the table can be filled in a hundred rows at a time, in any order, without touching the code that
prints them.

Two mechanisms, and the split matters:

* Godot re-translates a `Control`'s own text on the way to the screen — every label, button,
  heading and `Label3D` name plate in the game. Static text needs **no wiring at all**, and
  switching language re-translates every screen that is already open.
* `Loc.say` and `Loc.fill` are for what the engine cannot see: a line built in code, a log message,
  anything with numbers in it. A template is translated *before* the values go in, because
  `"Floor %d"` and `"Étage %d"` are the same three words in a different order.

The suite checks the one mistake a translated format string can make — a placeholder that went
missing or changed kind, which is a crash in the middle of a conversation rather than a typo — by
comparing the placeholders of every row in the table.

### Voices

Around ninety of the lines the game prints are **recorded**, and a conversation says its line
through the same signal that puts it on the band. Fifteen characters with fifteen voices is the
difference between a crowd you interview and a place you walk into.

* The lines are not listed by hand. `tools/make_voice.py` reads them out of the prose tables the
game already prints from (`story.gd`, `villages.gd`, `quests.gd`, `tower.gd`), which is the only way
the corpus stays honest: a list kept beside the sentences is wrong the first time somebody rewrites
a greeting, and the failure is silent.
* **A language is a set of recordings, not a translation of one.** French is a separate take; a
  line with no French recording is played in English rather than in an English voice reading French
  words, and a line with neither is silent. Most lines are dynamic (a floor number, a crystal
  count) and will never be recorded, which is fine and is the point.
* The line is the key, exactly as in the interface, so a line with no recording is simply a line
  nobody has said yet.
* Regenerating is free for anything already made, so the tool is a top-up rather than a rebuild:

```bash
python tools/make_voice.py --key sk-or-... --voice Eve
```

`Voice` can be turned off in the settings panel, and the choice is saved.

---

## The self-test

The project has no unit-test framework: it has a headless suite that boots the real
game and drives it, `tests/self_test.gd`, run with a flag.

```bash
godot --headless --path . -- --selftest
```

It ends with a count and exits non-zero if anything failed:

```
---- self test: 1148 checks, 0 failed ----
```

Run it in **game mode** (`godot --headless --path . -- --selftest`), not through `-s`. In script
mode the engine registers only some of the autoloads as globals, so a suite that names the newest
one fails to compile — with the error naming the autoload rather than the flag.

It is run against the **shipped binary** as well as the editor, which has caught real
bugs that only exist in a release export:

```bash
./build/windows/Disantia.exe --headless -- --selftest > log.txt 2>&1
```

Because it drives the real game, it checks claims rather than code: that a shut ward really
does turn a body back and an open one really does not, that a champion stays down, that
twice the health regenerates twice as fast, that a thousand qi really does hold the pressure
indefinitely (measured as net qi per game-second over a run of frames), that no amount
of jumping passes 20 m, that a raider inside the field is hurt and one outside it is
not, and that no two HUD panels overlap at either the design resolution or the window's
own. It runs on the real clock of the engine, not the wall clock, because that is the
clock the game integrates over.

The sections added since are worth naming, because each of them exists to catch a failure
that had already shipped:

* **The camera.** It measures the distance from the body to the camera at rest and at the top
  of a jump, and requires the arm to collide with nothing — the spring arm against the terrain
  was shortening in the air and pulling the camera onto the character, which the player reported
  as "it zooms on me when I jump".
* **The tower's door.** It stands the body outside the door and presses `E`, because everything
  else about the tower was tested by calling `Tower.enter` directly: a hundred floors of composed,
  green-tested content was unreachable, and every check was passing.
* **The voices.** That every file the generated table names is on disk, that a line with no
  recording is silent rather than an error, and that the language of the recording follows the
  language of the interface.
* **The night sky.** That nothing shows at noon and the stars are up at midnight, and that the
  moon is opposite the sun — the sign of a basis is exactly the thing a tidy-up flips.

---

## Layout

```
scenes/     main, player, hud, and the character/asset scenes
scripts/
  autoload/ player_data (stats, caps, save, wounds, gear), cultivation, training, quests,
            shop, audio, wards (the gates and the champions), story (the cast and the
            decisions), haven (the sanctuary registry), villages (the three towns, their
            people and their reputation), law (wanted, fines, cells), bounties (the boards),
            forge (materials and named gear), tower (the hundred floors), clock (day and
            night), raids (the night a village is attacked), loc (the language) and
            voice_table (the recorded lines; generated, do not edit)
  player/   controller, animator, camera rig, striker, aura, qi_pressure
  world/    terrain, roads, scatter, camps, qi zones, safe zone, signposts,
            landmarks (the sites), quest_npc (the elder), villager, people (the crowd),
            village_site + villages_place (the towns), village_npc, guard (the watch),
            tower_site (the tower and its arena), night_sky (the stars and the moon)
  ui/       hud, minimap, wayfinder, avatar nameplate
  enemy/    the raider, the factory that composes a floor's fight
assets/
  voice/    the recorded lines, one folder per language — see tools/make_voice.py
tests/      self_test.gd — the headless suite
tools/      setup_project.gd (writes project.godot), make_voice.py (bakes the spoken
            lines), export scripts, web server
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

The spoken lines in `assets/voice/` are **not** from a pack. They are generated from this
project's own prose by `tools/make_voice.py`, through OpenRouter's speech endpoint
(`x-ai/grok-voice-tts-1.0`), and committed so the game speaks without a network call and without an
API key. The tool is the source of truth: delete a file and re-run it and the take comes back.

The code in `scripts/`, `scenes/` and `tools/` has no licence file yet.
