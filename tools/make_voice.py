#!/usr/bin/env python3
"""Bakes the spoken lines of Disantia into audio, and writes the tables that play them.

The lines are not typed out here. They are *read out of the tables the game already prints from*
— `story.gd`, `villages.gd`, `quests.gd` — which is the only way this file can stay honest: a
list of sentences kept by hand beside the sentences themselves is a list that is wrong the first
time somebody rewrites a greeting, and the failure is silent (a line with no audio).

Three kinds of thing get recorded, and the split is the whole design:

  1. **Lines** — the prose the story tables hold, recorded whole. This is what somebody says to
     your face, and it is a sentence in the transcript and a file on disk.
  2. **Phrases** — the *fixed halves* of a sentence with a number in it. `Took 12.4 damage.` is a
     different sentence every time the game prints it, so no recording can ever match one — but
     `damage.` is fixed, and so is `The lamp takes.`. These are read out of the game's own format
     strings: every quoted literal with a `%` specifier in it is cut at the specifiers, and the
     pieces that read as language are recorded. That is what makes the *dynamic* half of the
     game's prose audible at all, and it is the only mechanism here that could not have been done
     by hand — there are hundreds of them and they change every time a message is reworded.
  3. **Shouts** — what the watch and the raiders say out loud. They are constants in
     `guard.gd`/`enemy.gd` named `SHOUT_*`, which is where this file reads them from: a cry that
     is written there is a cry that gets recorded, and one that is renamed stops being recorded
     rather than silently going on being played from a stale file.

French is a separate take of each, never a runtime translation of the English file: a voice reading
French words with an English mouth is worse than no voice at all. A phrase's French take is found
by cutting the *French* row of the same template at the same specifiers and pairing the pieces up,
which works whenever the translation kept the specifiers — and that is already checked by the
suite, because a translation that loses one is a crash rather than a bad accent.

Usage:

    python tools/make_voice.py --key sk-or-... --voice Eve
    python tools/make_voice.py --key sk-or-... --list-phrases

Re-running is free for anything already generated: a file that exists is left alone, so the tool
is a top-up rather than a rebuild.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VOICE_DIR = os.path.join(ROOT, "assets", "voice")
TABLE_PATH = os.path.join(ROOT, "scripts", "autoload", "voice_table.gd")
ENDPOINT = "https://openrouter.ai/api/v1/audio/speech"
MODEL = "x-ai/grok-voice-tts-1.0"

# The files whose prose is said *whole*. Deliberately not every file in the project: the log, the
# HUD and the tips are read, not spoken, and a game where every string is voiced is a game with a
# narrator standing over your shoulder. What the rest of the project contributes is *phrases* —
# see `extract_phrases`.
SOURCES = [
    "scripts/autoload/story.gd",
    "scripts/autoload/villages.gd",
    "scripts/autoload/quests.gd",
    "scripts/autoload/tower.gd",
]

# Where the format strings live: everywhere. A message with a number in it can be printed from any
# file in the project, and a tool that only looked at the four above would miss most of them.
PHRASE_ROOT = os.path.join(ROOT, "scripts")

# Where the cries live, and the only two files that have any. Named rather than swept for,
# because a shout is a line nobody reads — it exists to be *said* — and the naming convention is
# what keeps this list from becoming a guess.
SHOUT_SOURCES = [
    "scripts/world/guard.gd",
    "scripts/enemy/enemy.gd",
]

# One string literal, in the game's own style: double-quoted, no line breaks.
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
# A long line of prose in this project is written as literals joined with `+`, one per source
# line, because the source is wrapped at a hundred columns. The *line* is the join of them, and a
# fragment on its own is a fragment: `"walked it — and they were somebody's sons..."` is not a
# sentence anybody hears, and baking it would spend a request on audio that never plays.
JOINED = re.compile(r'"\s*\+\s*\n?\s*"')
# The escapes GDScript string literals actually use. Not `unicode_escape`: that decodes the whole
# literal as latin-1 and turns every `—` in the prose into mojibake, which then hashes to a
# filename that no printed line can ever look up.
ESCAPES = (("\\n", "\n"), ("\\t", "\t"), ('\\"', '"'), ("\\\\", "\\"))

# A `%s`, a `%d`, a `%.1f`, a `%02d`. What a template is cut at — and the same shape the suite
# checks French rows against (`_placeholders` in `tests/self_test.gd`), deliberately: a tool that
# used a looser pattern would cut at things the game never substitutes, and `45% of the pool` is
# the one that matters, because `% o` looks exactly like a specifier to a careless pattern.
SPECIFIER = re.compile(r"%[-+0#]*[0-9]*(?:\.[0-9]+)?[sdfxX]")
# A shout, as it is written at the top of the file that says it.
SHOUT = re.compile(r'^const (SHOUT_[A-Z_]+)\s*:=\s*"((?:[^"\\]|\\.)*)"', re.MULTILINE)

# The punctuation a cut piece has to end on to be language rather than a fragment of one. A piece
# that stops in the middle of a clause ("and the pool is") is a piece nobody can say.
ENDS = (".", "!", "?", "…", ",")


def unescape(raw: str) -> str:
    for escaped, plain in ESCAPES:
        raw = raw.replace(escaped, plain)
    return raw


def extract() -> list[str]:
    """Every whole-line prose literal in the sources, in the order they appear, once each."""
    seen: dict[str, None] = {}
    for rel in SOURCES:
        path = os.path.join(ROOT, rel)
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        source = JOINED.sub("", source)
        for raw in LITERAL.findall(source):
            line = unescape(raw)
            if readable(line):
                seen.setdefault(line.strip(), None)
    return list(seen)


def readable(line: str) -> bool:
    """Whether a voice should say this out loud whole.

    The rules are the difference between prose and plumbing: a sentence has length, spaces and
    ends in punctuation; a key (`hollowmere_keeper`), a path (`res://audio/plop.ogg`), a label
    (`Hand it in`) and a format string (`%s — dormant, needs stage %d`) do not.
    """
    if len(line) < 28 or "%" in line:
        return False
    if line.startswith(("res://", "user://", "uid://")):
        return False
    if not re.search(r"[.!?…]$", line.strip()):
        return False
    if " " not in line:
        return False
    # Plumbing that happens to be a sentence: a cap grant ("ATTACK cap permanently +8"), a
    # reward ("+45 crystals"), a task line with a `{target}` in it, and the two control hints.
    if "+" in line or "{" in line or "cap permanently" in line:
        return False
    if line.startswith(("Press ", "Tap ", "Click ", "Esc ")):
        return False
    words = line.split()
    if len(words) < 5:
        return False
    if sum(1 for word in words if len(word) > 22) > 0:
        return False
    return True


def phrase_sources() -> list[str]:
    """Every GDScript file under `scripts/`, so a message printed from anywhere is covered."""
    out: list[str] = []
    for base, _dirs, files in os.walk(PHRASE_ROOT):
        for name in sorted(files):
            if name.endswith(".gd"):
                out.append(os.path.relpath(os.path.join(base, name), ROOT).replace(os.sep, "/"))
    return sorted(out)


## Separators a cut piece inherits from the text around the number it was cut at. Escaped
## `${}`-style, and the em dash and middle dot the game writes its bands with.
EDGES = " \t.,;:—–·-|"


def cut(template: str) -> list[str]:
    """A template split at its specifiers: the pieces a voice could actually say.

    Leading separators are trimmed, trailing ones are not: `%d %s. Body remembers.` cuts to
    `. Body remembers.` — which is a whole sentence wearing the full stop that belonged to the
    number before it — and `%d on every blow` cuts to a tail that has to stay recognisable as one
    so it can be thrown away.
    """
    return [piece.lstrip(EDGES).rstrip() for piece in SPECIFIER.split(template)]


def phrase_like(piece: str) -> bool:
    """Whether a cut piece is a sentence rather than the debris between two numbers.

    **It has to start at a word.** Cutting a template at its specifiers leaves the pieces that
    *follow* a number as well as the ones that precede it, and a sentence's tail is not a
    sentence: `...%d%% on every blow for 45 seconds.` cuts to `n every blow for 45 seconds.`,
    which is four fifths of a cue and would be recorded as if it were language. A capital is the
    cheapest honest way to ask "did this piece begin where a sentence can begin" — every cue in
    the table is a sentence the game *starts*, never one it joins halfway.

    Two words is the floor, not three: `Body remembers.` is a whole sentence and `damage.` is not
    — and the difference between them is the full stop, which is what the ending rule reads.
    """
    if not 2 <= len(piece.split()) <= 12:
        return False
    if not piece[0].isupper():
        return False
    if "%" in piece or "{" in piece or "}" in piece or "res://" in piece:
        return False
    if not any(character.islower() for character in piece):
        return False
    # Plumbing that happens to have two words in it: `Crystals (you have`, `×3`. A piece that is
    # mostly digits or symbols is a value, not a phrase.
    if sum(1 for character in piece if character.isalpha()) < len(piece) * 0.5:
        return False
    return piece.endswith(ENDS)


def french_piece_ok(piece: str) -> bool:
    """Whether a French piece is worth recording. Looser than the English rule on purpose.

    The capital-letter rule above exists to throw away the *tails* of cut templates, and the
    French side is cut the same way from the same shape of sentence — so a French piece that is a
    tail has already been thrown away with its English twin, and asking for a capital here would
    only lose the French sentences that begin with a lower-case article.
    """
    if not 2 <= len(piece.split()) <= 12:
        return False
    if "%" in piece or "{" in piece or "}" in piece:
        return False
    if sum(1 for character in piece if character.isalpha()) < len(piece) * 0.5:
        return False
    return piece.endswith(ENDS)


## A line that goes to the console rather than to the player.
CONSOLE = re.compile(r"^\s*(print|print_rich|push_warning|push_error)\s*\(", re.MULTILINE)


def extract_phrases() -> list[str]:
    """The fixed halves of every dynamic sentence the *player* can read, once each.

    Console output is dropped first. It is a template like any other, it is written in the same
    style, and nobody will ever hear a word of it — `[terrain] %d chunk meshes, %d for slope` is
    exactly the shape of a phrase this would otherwise pay to record.
    """
    seen: dict[str, None] = {}
    for rel in phrase_sources():
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            source = JOINED.sub("", handle.read())
        source = CONSOLE.sub("", source)
        for raw in LITERAL.findall(source):
            text = unescape(raw)
            if "%" not in text or len(text) < 12:
                continue
            for piece in cut(text):
                if phrase_like(piece):
                    seen.setdefault(piece, None)
    return list(seen)


def extract_shouts() -> list[str]:
    """The cries, in the order the files that say them declare them."""
    seen: dict[str, None] = {}
    for rel in SHOUT_SOURCES:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            source = handle.read()
        for _name, raw in SHOUT.findall(source):
            seen.setdefault(unescape(raw), None)
    return list(seen)


def french_rows() -> dict[str, str]:
    """The French table, read as text so this tool needs no Godot to run."""
    path = os.path.join(ROOT, "scripts", "autoload", "loc_fr.gd")
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    return read_rows(source)


## One row of the French table, in either of the two shapes the file uses: key and value on one
## line, or the value carried onto the next with a colon and a newline between them. Both are in
## the file, and reading only the first shape was a real bug rather than a style question — every
## long row went unseen, so every long row was silently never dubbed.
ROWS = re.compile(r'^\t"((?:[^"\\]|\\.)*)":\s*(?:\n\t\t)?"((?:[^"\\]|\\.)*)",?[ \t]*$',
                  re.MULTILINE)


def read_rows(source: str) -> dict[str, str]:
    rows: dict[str, str] = {}
    for english, french in ROWS.findall(source):
        rows[unescape(english)] = unescape(french)
    return rows


def french_phrases(french: dict[str, str]) -> dict[str, str]:
    """English piece -> French piece, for every template whose translation kept its specifiers.

    Paired by *position* after cutting both sides at their specifiers, which is the one thing that
    can be relied on: `Loc.fill` translates the template and then substitutes, so the pieces are
    in the order the sentence puts them, and a French row that moved one is a row that would have
    been caught by the suite long before it got here.
    """
    out: dict[str, str] = {}
    for rel in phrase_sources():
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            source = CONSOLE.sub("", JOINED.sub("", handle.read()))
        for raw in LITERAL.findall(source):
            english = unescape(raw)
            if "%" not in english or english not in french:
                continue
            left = cut(english)
            right = cut(french[english])
            if len(left) != len(right):
                continue
            for i, piece in enumerate(left):
                if phrase_like(piece) and french_piece_ok(right[i]):
                    out[piece] = right[i]
    return out


def slug(line: str) -> str:
    return hashlib.md5(line.encode("utf-8")).hexdigest()[:12]


def speak(text: str, voice: str, key: str) -> bytes:
    body = json.dumps(
        {"model": MODEL, "input": text, "voice": voice, "response_format": "mp3"}
    ).encode("utf-8")
    request = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def usage(key: str) -> float:
    request = urllib.request.Request(
        "https://openrouter.ai/api/v1/key", headers={"Authorization": f"Bearer {key}"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return float(json.load(response)["data"]["usage"])


def bake(lines: list[str], language: str, voice: str, key: str, spend_cap: float) -> dict:
    """Writes what is missing, returns `{text: relative path}` for what is on disk."""
    out: dict[str, str] = {}
    started = usage(key)
    made = 0
    for index, line in enumerate(lines):
        name = f"{slug(line)}.mp3"
        path = os.path.join(VOICE_DIR, language, name)
        out[line] = f"res://assets/voice/{language}/{name}"
        if os.path.exists(path):
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        try:
            audio = speak(line, voice, key)
        except urllib.error.HTTPError as error:
            print(f"  ! {error.code} on {line[:48]!r}: {error.read()[:160]!r}")
            break
        with open(path, "wb") as handle:
            handle.write(audio)
        made += 1
        if made % 5 == 0:
            spent = usage(key) - started
            print(f"  {index + 1}/{len(lines)} — ${spent:.4f} spent")
            if spent > spend_cap:
                print(f"  stopped: ${spent:.4f} is over the ${spend_cap:.2f} cap")
                break
        time.sleep(0.2)
    if made:
        print(f"  {language}: {made} new, ${usage(key) - started:.4f}")
    else:
        print(f"  {language}: nothing missing")
    return out


HEADER = '''extends RefCounted
## The spoken lines, and which file holds each one.
##
## Generated by `tools/make_voice.py` from the prose in the game's own tables — **do not edit by
## hand**. The English sentence is the key, the same way it is everywhere else in the interface
## (see `loc.gd`): a line with no row here is simply a line nobody has recorded yet, and the game
## says it in silence rather than breaking.
##
## A language is a *set of files*, not a translation of a file. A voice reading French words with
## an English mouth is worse than no voice at all, so `fr` is its own recording and a line that
## has no French take is played in English.
##
## Three tables, and the reason for each is in the tool that writes them:
##
##   * `TABLE` — whole lines, the prose somebody says to your face.
##   * `PHRASES` — the fixed half of a sentence with a number in it, which is the only way a line
##     like `Took 12.4 damage.` can ever be heard.
##   * `SHOUTS` — the cries, which are said rather than printed and so live here alone.
'''


def line_rows(rows: dict[str, dict[str, str]]) -> list[str]:
    out: list[str] = []
    for text in rows:
        takes = rows[text]
        inner = ", ".join(f'"{lang}": "{takes[lang]}"' for lang in ("en", "fr") if lang in takes)
        out.append(f"\t{json.dumps(text)}: {{{inner}}},")
    return out


def table(name: str, rows: dict[str, dict[str, str]], note: str) -> str:
    out = [f"\n## {note}", f"const {name}: Dictionary = {{"]
    out.extend(f"{line}" for line in line_rows(rows))
    out.append("}")
    return "\n".join(out)


def write_table(
    lines: dict[str, dict[str, str]],
    phrases: dict[str, dict[str, str]],
    shouts: dict[str, dict[str, str]],
) -> None:
    parts = [HEADER]
    parts.append(table("TABLE", dict(sorted(lines.items())),
                       '`{ English line: { "en": "res://...", "fr": "res://..." } }`'))
    parts.append(table("PHRASES", dict(sorted(phrases.items())),
                       "The fixed halves of the game's dynamic sentences, longest match wins."))
    parts.append(table("SHOUTS", dict(sorted(shouts.items())),
                       "What the watch and the raiders say out loud."))
    with open(TABLE_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(parts) + "\n")
    print(f"  wrote {TABLE_PATH}: {len(lines)} lines, {len(phrases)} phrases, {len(shouts)} cries")


def collects(paths: dict[str, str]) -> dict[str, dict[str, str]]:
    """`{text: {"en": ..., "fr": ...}}` from two `{text: res:// path}` maps, on-disk only."""
    rows: dict[str, dict[str, str]] = {}
    for language, mapping in paths.items():
        for text, path in mapping.items():
            if os.path.exists(os.path.join(ROOT, path.replace("res://", ""))):
                rows.setdefault(text, {})[language] = path
    return rows


def merged(existing: dict, fresh: dict) -> dict:
    """Old takes kept, new ones added. A run that only looked at lines would otherwise *delete*
    the phrase table it wrote last time, which is the failure mode of every generated file that
    is written from a partial scan."""
    out = {text: dict(takes) for text, takes in existing.items()}
    for text, takes in fresh.items():
        out.setdefault(text, {}).update(takes)
    return {text: takes for text, takes in out.items() if takes}


def existing_table() -> dict:
    """The tables already on disk, read as text: this tool must not need Godot to run."""
    if not os.path.exists(TABLE_PATH):
        return {}
    with open(TABLE_PATH, encoding="utf-8") as handle:
        source = handle.read()
    out: dict[str, dict] = {}
    for name in ("TABLE", "PHRASES", "SHOUTS"):
        block = re.search(rf"const {name}: Dictionary = \{{(.*?)^\}}", source, re.S | re.M)
        rows: dict[str, dict] = {}
        if block:
            for english, body in re.findall(
                r'^\t("(?:[^"\\]|\\.)*"): \{(.*?)\},$', block.group(1), re.MULTILINE
            ):
                takes = dict(re.findall(r'"(en|fr)": "(res://[^"]+)"', body))
                rows[json.loads(english)] = takes
        out[name] = rows
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--key", default=os.environ.get("OPENROUTER_API_KEY", ""))
    parser.add_argument("--voice", default="Eve")
    parser.add_argument("--limit", type=int, default=0, help="bake only the first N of each kind")
    parser.add_argument("--spend-cap", type=float, default=1.20)
    parser.add_argument("--list", action="store_true", help="print the lines and stop")
    parser.add_argument("--list-phrases", action="store_true", help="print the phrases and stop")
    parser.add_argument("--list-shouts", action="store_true", help="print the cries and stop")
    parser.add_argument("--prune", action="store_true",
                        help="delete recordings no row in the table points at")
    args = parser.parse_args()

    lines = extract()
    phrases = extract_phrases()
    shouts = extract_shouts()
    if args.limit:
        lines = lines[: args.limit]
    if args.list:
        for line in lines:
            print(line)
        print(f"--- {len(lines)} lines")
        return 0
    if args.list_phrases:
        for phrase in phrases:
            print(phrase)
        print(f"--- {len(phrases)} phrases")
        return 0
    if args.list_shouts:
        for cry in shouts:
            print(cry)
        print(f"--- {len(shouts)} cries")
        return 0
    if args.prune and not args.key:
        # Pruning is a local job — it needs the table, not the model — so it must not be gated on a
        # key. Tying a cleanup to a paid service is how a cleanup stops being run.
        old = existing_table()
        prune({**old.get("TABLE", {}), **old.get("PHRASES", {}), **old.get("SHOUTS", {})})
        return 0
    if not args.key:
        print("no API key: pass --key or set OPENROUTER_API_KEY", file=sys.stderr)
        return 2

    french = french_rows()
    sayable = french_phrases(french)
    print(f"{len(lines)} lines ({sum(1 for line in lines if line in french)} with French), "
          f"{len(phrases)} phrases ({len(sayable)} with French), {len(shouts)} cries")

    english = bake(lines, "en", args.voice, args.key, args.spend_cap)
    francais = bake([line for line in lines if line in french], "fr", args.voice, args.key,
                    args.spend_cap)
    english_phrases = bake(phrases, "en", args.voice, args.key, args.spend_cap)
    french_phrases_baked = bake([sayable[phrase] for phrase in phrases if phrase in sayable],
                                "fr", args.voice, args.key, args.spend_cap)
    english_shouts = bake(shouts, "en", args.voice, args.key, args.spend_cap)
    french_shouts = bake(shouts, "fr", args.voice, args.key, args.spend_cap)

    # The French phrase takes are keyed by the *English* piece and point at the French recording of
    # the French piece, which is the same arrangement the whole-line table uses.
    francais_phrases: dict[str, str] = {}
    for phrase in phrases:
        if phrase in sayable and sayable[phrase] in french_phrases_baked:
            francais_phrases[phrase] = french_phrases_baked[sayable[phrase]]

    old = existing_table()
    lines_rows = merged(old.get("TABLE", {}), collects({"en": english, "fr": francais}))
    phrases_rows = merged(old.get("PHRASES", {}),
                          collects({"en": english_phrases, "fr": francais_phrases}))
    shouts_rows = merged(old.get("SHOUTS", {}), collects({"en": english_shouts, "fr": french_shouts}))
    write_table(lines_rows, phrases_rows, shouts_rows)
    if args.prune:
        prune({**lines_rows, **phrases_rows, **shouts_rows})
    return 0


def prune(rows: dict[str, dict[str, str]]) -> None:
    """Deletes audio nothing points at.

    A recording is only reachable through the table, and the table is regenerated — so a line that
    is reworded, or a phrase that stops being cut out of a template, leaves its file behind
    forever. Nine megabytes of the repository, in the state that made this worth writing: every
    one of them a file that no code path could ever open.
    """
    wanted: set[str] = set()
    for takes in rows.values():
        for path in takes.values():
            wanted.add(os.path.basename(path))
    removed = 0
    kept = 0
    for language in os.listdir(VOICE_DIR):
        folder = os.path.join(VOICE_DIR, language)
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            # The `.import` sidecar belongs to its recording and is deleted with it. It is *not* a
            # recording with no row: skipping it here was a real bug rather than tidiness — the
            # prune took every sidecar it passed, and a Godot resource with no `.import` is a file
            # the engine cannot see at all, so all 184 takes went missing at once.
            if name.endswith(".import"):
                continue
            if name in wanted:
                kept += 1
                continue
            os.remove(os.path.join(folder, name))
            sidecar: str = os.path.join(folder, name + ".import")
            if os.path.exists(sidecar):
                os.remove(sidecar)
            removed += 1
    print(f"  pruned {removed} unreferenced recordings, {kept} kept")


if __name__ == "__main__":
    raise SystemExit(main())
