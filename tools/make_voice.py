#!/usr/bin/env python3
"""Bakes the spoken lines of Disantia into audio, and writes the table that plays them.

The lines are not typed out here. They are *read out of the tables the game already prints from*
— `story.gd`, `villages.gd`, `quests.gd` — which is the only way this file can stay honest: a
list of sentences kept by hand beside the sentences themselves is a list that is wrong the first
time somebody rewrites a greeting, and the failure is silent (a line with no audio).

What it does, in order:

  1. Extracts every quoted prose literal from those files, keeping the ones a voice can read
     (a sentence rather than a key, a label or a format string).
  2. For each, asks OpenRouter's speech endpoint for the line in English, and again in French
     when `loc_fr.gd` has a row for it. French is a separate file, not a translation at runtime,
     because a voice pretending to be French is worse than a voice that stays quiet.
  3. Writes `assets/voice/<lang>/<hash>.mp3` and `scripts/autoload/voice_table.gd`.

Usage:

    python tools/make_voice.py --key sk-or-... --voice Eve --limit 40

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

# The files whose prose the player hears. Deliberately not every file in the project: the log,
# the HUD and the tips are read, not spoken, and a game where every string is voiced is a game
# with a narrator standing over your shoulder.
SOURCES = [
    "scripts/autoload/story.gd",
    "scripts/autoload/villages.gd",
    "scripts/autoload/quests.gd",
    "scripts/autoload/tower.gd",
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


def extract() -> list[str]:
    """Every prose literal in the sources, in the order they appear, once each."""
    seen: dict[str, None] = {}
    for rel in SOURCES:
        path = os.path.join(ROOT, rel)
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        source = JOINED.sub("", source)
        for raw in LITERAL.findall(source):
            for escaped, plain in ESCAPES:
                raw = raw.replace(escaped, plain)
            if readable(raw):
                seen.setdefault(raw.strip(), None)
    return list(seen)


def readable(line: str) -> bool:
    """Whether a voice should say this out loud.

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
    # Every one of these is printed somewhere and none of them is *said* by anybody.
    if "+" in line or "{" in line or "cap permanently" in line:
        return False
    if line.startswith(("Press ", "Tap ", "Click ", "Esc ")):
        return False
    # Identifiers and paths read as one long token; a sentence has several short ones.
    words = line.split()
    if len(words) < 5:
        return False
    if sum(1 for word in words if len(word) > 22) > 0:
        return False
    return True


def french_rows() -> dict[str, str]:
    """The French table, read as text so this tool needs no Godot to run."""
    path = os.path.join(ROOT, "scripts", "autoload", "loc_fr.gd")
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    rows: dict[str, str] = {}
    pattern = re.compile(r'^\t"((?:[^"\\]|\\.)*)":\s*"((?:[^"\\]|\\.)*)",?$', re.MULTILINE)
    for english, french in pattern.findall(source):
        rows[english.replace('\\"', '"')] = french.replace('\\"', '"')
    return rows


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
    """Writes what is missing, returns `{english line: relative path}` for what is on disk."""
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


## `{ English line: { "en": "res://...", "fr": "res://..." } }`
const TABLE: Dictionary = {
'''


def write_table(rows: dict[str, dict[str, str]]) -> None:
    with open(TABLE_PATH, "w", encoding="utf-8") as handle:
        handle.write(HEADER)
        for line in sorted(rows):
            takes = rows[line]
            inner = ", ".join(f'"{lang}": "{takes[lang]}"' for lang in ("en", "fr") if lang in takes)
            handle.write(f'\t{json.dumps(line)}: {{{inner}}},\n')
        handle.write("}\n")
    print(f"  wrote {TABLE_PATH} with {len(rows)} lines")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--key", default=os.environ.get("OPENROUTER_API_KEY", ""))
    parser.add_argument("--voice", default="Eve")
    parser.add_argument("--limit", type=int, default=0, help="bake only the first N lines")
    parser.add_argument("--spend-cap", type=float, default=0.45)
    parser.add_argument("--list", action="store_true", help="print the lines and stop")
    args = parser.parse_args()

    lines = extract()
    if args.limit:
        lines = lines[: args.limit]
    if args.list:
        for line in lines:
            print(line)
        print(f"--- {len(lines)} lines")
        return 0
    if not args.key:
        print("no API key: pass --key or set OPENROUTER_API_KEY", file=sys.stderr)
        return 2

    french = french_rows()
    print(f"{len(lines)} lines; {sum(1 for line in lines if line in french)} have a French row")

    # English first, then French only for the rows that exist: a French take of an English
    # sentence would be the model reading English with a French accent, which is not a dub.
    english = bake(lines, "en", args.voice, args.key, args.spend_cap)
    francais = bake([line for line in lines if line in french], "fr", args.voice, args.key,
                    args.spend_cap)

    rows: dict[str, dict[str, str]] = {}
    for line, path in english.items():
        if os.path.exists(os.path.join(ROOT, path.replace("res://", ""))):
            rows.setdefault(line, {})["en"] = path
    for line, path in francais.items():
        if os.path.exists(os.path.join(ROOT, path.replace("res://", ""))):
            rows.setdefault(line, {})["fr"] = path
    write_table(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
