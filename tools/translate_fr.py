#!/usr/bin/env python3
"""Fills the holes in the French table, from the strings the game itself prints.

The table is keyed by the English sentence (see `loc.gd`), which makes it a list that can only be
maintained by hand — and hands are exactly what a game with three villages, fifteen people, four
hundred strings and a hundred and one tower floors does not have. So this tool does the tedious
half: it reads every literal in the project that could reach the screen, drops the ones that are
already translated, and asks a model for the rest.

Three rules, and every one of them is a thing a translation can silently get wrong:

  * **The placeholders survive.** `%s`, `%d`, `%.1f` and a literal `%%` are checked against the
    English *in order* before a row is written. A French sentence that lost one is a crash in the
    middle of a conversation rather than a bad accent, so it is not written at all.
  * **Anything that is not language is not a candidate.** Keys, paths, sound names, group names
    and colour hexes are filtered out before the model ever sees them: a table row for `res://...`
    is a row that can never be looked up.
  * **Proper nouns are collected, not guessed.** The names of the places and the people are passed
    to the model explicitly, because a model left to itself will translate a village.

The lines a voice speaks are included deliberately: a line with no French row is a line that can
never be dubbed (see `tools/make_voice.py`), so a missing row here is a silence there.

Usage:

    python tools/translate_fr.py --key sk-or-... --dry-run
    python tools/translate_fr.py --key sk-or-...
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import make_voice  # noqa: E402  — the same extraction rules, not a second copy of them

ROOT = make_voice.ROOT
TABLE_PATH = os.path.join(ROOT, "scripts", "autoload", "loc_fr.gd")
ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
MODEL = "google/gemini-2.5-flash-lite"
BATCH = 24

## A line of the source that is nothing but a comment. Dropped before anything is read out of it:
## the documentation in this project is written *in the voice of the game*, so a fragment of a doc
## comment is indistinguishable from a line of dialogue by every rule below — and translating the
## comments would fill the table with rows nothing can ever look up.
COMMENT = re.compile(r"^\s*#", re.MULTILINE)

## Files whose strings are *plumbing*: the language names, the generated voice table, and the
## translation table itself. A row for "English" would make the two language buttons in the
## settings panel both say the same word.
SKIP_SOURCES = (
    "scripts/autoload/loc.gd",
    "scripts/autoload/loc_fr.gd",
    "scripts/autoload/voice_table.gd",
)


## The names that must survive translation. Read out of the game's own casts rather than listed
## here, so a person added to a village is a person the translator already knows about.
def proper_nouns() -> list[str]:
    names: list[str] = []
    for rel in ("scripts/autoload/story.gd", "scripts/autoload/villages.gd"):
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            source = handle.read()
        for match in re.findall(r'"name":\s*"([^"]+)"', source):
            names.append(match)
        for match in re.findall(r'"speaker":\s*"([^"]+)"', source):
            names.append(match)
    for word in ("Disantia", "Hollowmere", "Stonewatch", "Towerfall", "Ninth", "Qi", "Dantian"):
        names.append(word)
    return sorted(set(names))


SYSTEM = """You localise a French action-RPG called Disantia into French. It is a cultivation
fantasy game: a valley, three villages, a hundred-floor tower, qi, body training, raiders, a
watch that arrests you rather than killing you.

The register is terse, physical and slightly archaic — a villager talking to somebody who has been
walking a long road. Second person ("vous"). No exclamation where the English has none. Never
explain, never add, never soften.

Rules, in order of importance:
1. Keep every placeholder exactly: %s, %d, %.1f, %% . They may move inside the sentence, but the
   set and the order must be identical.
2. Keep proper nouns as they are: the names in the list you are given.
3. Keep the typographic characters: · (a middle dot used as a separator), — (an em dash), … .
4. Keep the same punctuation at the end of the sentence. A string that starts with spaces keeps
   those spaces.
5. A string that is an interface label stays an interface label: short, capital where the English
   is capital, no full stop added.

Answer with JSON only: an object whose keys are the English strings, verbatim, and whose values
are the French. No commentary, no markdown fence."""

# The same shape the suite checks rows against (`_placeholders` in `tests/self_test.gd`), and
# deliberately not a looser one: `45% of the pool` contains `% o`, which a pattern that allows a
# space among the flags reads as a specifier — and a French row that writes `45 % du pool` would
# then be rejected for "losing" a placeholder that never existed.
SPECIFIER = re.compile(r"%[-+0#]*[0-9]*(?:\.[0-9]+)?[sdfxX]")
BAD_CHARS = set("={}[]<>;()|\\")
# Keys, paths, identifiers, sound names, group names, hex colours, and the handful of words that
# are data rather than language. A row for any of these is a row nothing can ever look up.
IDENTIFIER = re.compile(r"^[a-z][a-z0-9_]*$")
SNAKE = re.compile(r"^[a-z0-9_]+$")
HEX = re.compile(r"^[0-9a-fA-F]{6,8}$")
TITLE = re.compile(r"^[A-ZÀ-Ý][a-zà-ÿ'’\-]+$")
SHOUT = re.compile(r"^[A-ZÀ-Ý][^.!?]*[.!?]$")


def looks_displayable(text: str) -> bool:
    if not 2 <= len(text) <= 220:
        return False
    if text.startswith(("res://", "user://", "uid://")):
        return False
    if any(character in BAD_CHARS for character in text):
        return False
    if IDENTIFIER.match(text) or SNAKE.match(text) or HEX.match(text):
        return False
    # A doc comment carried into a literal by the line-joining rule. It is documentation, written
    # in the voice of the game, and it is never printed.
    if "\n#" in text or "##" in text:
        return False
    if not any(character.isalpha() for character in text):
        return False
    # A sentence, a label, an all-caps stat name (HP, QI, SPEED), a shouted line, or a Title Case
    # word. Everything else in a GDScript file is plumbing that happens to be in quotes.
    if " " in text or "\n" in text:
        return True
    if text.isupper() and text.isalpha():
        return True
    if TITLE.match(text):
        return True
    return False


def candidates() -> list[str]:
    """Every English string the game can put on screen and the table does not have yet."""
    known = make_voice.french_rows()
    seen: dict[str, None] = {}
    for rel in make_voice.phrase_sources():
        if rel in SKIP_SOURCES:
            continue
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            source = make_voice.CONSOLE.sub("", COMMENT.sub("", handle.read()))
        for raw in make_voice.LITERAL.findall(source):
            text = make_voice.unescape(raw)
            if text in known or not looks_displayable(text):
                continue
            seen.setdefault(text, None)
    # The spoken lines go in whatever the filters say about them: a line with no French row is a
    # line that can never be dubbed, and "Mm." is a line.
    for line in make_voice.extract():
        if line not in known:
            seen.setdefault(line, None)
    return list(seen)


def ask(batch: list[str], key: str, nouns: list[str]) -> dict[str, str]:
    user = json.dumps({"proper_nouns": nouns, "strings": batch}, ensure_ascii=False)
    body = json.dumps({
        "model": MODEL,
        "temperature": 0.2,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user},
        ],
    }).encode("utf-8")
    request = urllib.request.Request(
        ENDPOINT, data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        payload = json.load(response)
    text = payload["choices"][0]["message"]["content"].strip()
    if text.startswith("```"):
        text = text.split("```")[1].removeprefix("json").strip()
    return json.loads(text)


def placeholders(text: str) -> list[str]:
    return SPECIFIER.findall(text)


def acceptable(english: str, french: str) -> str:
    """The French, or "" when the row must not be written. The reason is not reported twice."""
    if not french or not french.strip():
        return ""
    # `45%%` for `45%`: a model that has spent the day writing format strings escapes every per
    # cent by reflex, and where the English has no `%%` at all there is nothing for the escape to
    # mean. Doubled only where the English doubled it — that is a format template, and there the
    # escape is load-bearing.
    if "%%" not in english:
        french = french.replace("%%", "%")
    if french.strip() == english.strip():
        return ""
    if placeholders(english) != placeholders(french):
        return ""
    if english.count("%%") != french.count("%%"):
        return ""
    # A control strip and a shouted line both start where the English starts; a French sentence
    # that dropped a leading indent would silently change the layout of the band.
    if english[:2].strip() == "" and french[:1].strip() != "":
        return ""
    return french


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--key", default=os.environ.get("OPENROUTER_API_KEY", ""))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    # The Windows console is cp1252 and the prose is full of em dashes and arrows: without this,
    # listing the work to be done crashes before a single batch is sent.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    todo = candidates()
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(todo)} strings with no French row")
    if args.dry_run:
        for text in todo:
            print(repr(text))
        return 0
    if not args.key:
        print("no API key: pass --key or set OPENROUTER_API_KEY", file=sys.stderr)
        return 2

    nouns = proper_nouns()
    rows: dict[str, str] = {}
    rejected: list[str] = []
    for start in range(0, len(todo), BATCH):
        batch = todo[start : start + BATCH]
        answer = {}
        for attempt, size in enumerate((len(batch), max(1, len(batch) // 2), 1)):
            part = batch[:size] if attempt else batch
            try:
                answer = ask(part, args.key, nouns)
                if size < len(batch):
                    # A batch that failed is re-sent in halves: the usual cause is one long line
                    # that the model wrapped, and the other twenty-three were fine.
                    try:
                        answer.update(ask(batch[size:], args.key, nouns))
                    except (urllib.error.HTTPError, json.JSONDecodeError, KeyError):
                        pass
                break
            except (urllib.error.HTTPError, json.JSONDecodeError, KeyError) as error:
                body = getattr(error, "read", lambda: b"")()
                print(f"  ! batch at {start} (attempt {attempt + 1}): {error} {body[:120]!r}")
                if isinstance(error, urllib.error.HTTPError):
                    break
        for english in batch:
            french = acceptable(english, str(answer.get(english, "")))
            if french:
                rows[english] = french
            else:
                rejected.append(english)
        print(f"  {min(start + BATCH, len(todo))}/{len(todo)} — {len(rows)} rows")
        time.sleep(0.1)

    if not rows:
        print("nothing to write")
        return 0
    with open(TABLE_PATH, "rb") as handle:
        source = handle.read().decode("utf-8")
    section = ["\n\t# ------------------------------------------------- translated from the game's own",
               "\t# strings, by `tools/translate_fr.py`. Same rules as everything above: the English",
               "\t# is the key, and the placeholders are checked before a row is written.\n"]
    for english in rows:
        section.append(f"\t{json.dumps(english, ensure_ascii=False)}: "
                       f"{json.dumps(rows[english], ensure_ascii=False)},")
    closing = source.rstrip().rfind("\n}")
    source = source[:closing] + "\n".join(section) + source[closing:]
    with open(TABLE_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(source)
    print(f"wrote {len(rows)} rows into {TABLE_PATH}")
    if rejected:
        print(f"left in English ({len(rejected)}): a placeholder moved, or the model said nothing")
        for text in rejected[:10]:
            print(f"  - {text[:80]!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
