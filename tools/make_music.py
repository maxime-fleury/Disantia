#!/usr/bin/env python3
"""Generate the region music, one looping bed per theme.

Why a tool and not six hand-downloaded files: the game names a *theme* and the theme has to
exist. A missing file is a silent region, and a silent region is the bug this whole feature
exists to fix -- so the table below is the source of truth and re-running this only renders
what is missing.

The model returns MP3 at 192 kbps, which is three times what a game needs for a background
bed. Everything is transcoded with ffmpeg to Ogg Vorbis, which is what Godot plays natively
and what keeps the Windows build and the web payload honest.

    export OPENROUTER_API_KEY=sk-or-...
    python tools/make_music.py            # render whatever is missing
    python tools/make_music.py --force    # re-render everything

No key is written down here, and that is deliberate: a default in the source is a secret in the
repository, and GitHub's push protection rejects the whole branch for it. `make_voice.py` takes
its key the same way, for the same reason.
"""

import base64
import json
import os
import subprocess
import sys
import urllib.request

MODEL = "google/lyria-3-pro-preview"
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "music")
SECONDS = 88

# The shared instruction, so every bed sits in the same world. A region theme that does not
# share an instrumentation with its neighbours sounds like a different game, which is worse
# than no music at all.
STYLE = (
    "Instrumental, seamless loop, {secs} seconds, Chinese xianxia folk: guqin, dizi bamboo "
    "flute, erhu, low strings, hand percussion, temple bell. {brief} No vocals, no lyrics, "
    "no spoken word, no fade-out at the end -- it must loop."
)

THEMES = {
    "valley": (
        "A wide green valley at midday. Sparse and patient, long rests between phrases, wind "
        "and distant birds, one solo guqin and a soft flute answering it."
    ),
    "valley_night": (
        "The same valley after dark. Almost empty: a single low drone, a bowed erhu far away, "
        "crickets, a very slow bell every few bars. Quiet enough to hear footsteps over."
    ),
    "village": (
        "A living market town in daylight. Warm and human, plucked pipa, a light hand drum, an "
        "erhu melody that sounds like people talking to each other."
    ),
    "village_night": (
        "The same town at night behind closed shutters. Hushed, a slow guqin figure, a distant "
        "watchman's bell, no drum."
    ),
    "tower": (
        "Inside a hundred-storey tower that must be climbed. Tense and ceremonial, low "
        "percussion like a slow heartbeat, a repeated cello figure, faint metal resonances, "
        "never resolving."
    ),
    "cave": (
        "Deep underground, somewhere your torch only reaches a few metres. Almost no melody: "
        "sub-bass drone, water dripping, breath, a single struck stone. Dread without drama."
    ),
}


def render(key: str, theme: str, brief: str) -> bytes:
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": STYLE.format(secs=SECONDS, brief=brief)}],
        "modalities": ["text", "audio"],
        "stream": True,
    }).encode()
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=body,
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    )
    chunks = []
    with urllib.request.urlopen(req, timeout=600) as response:
        for raw in response:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                event = json.loads(payload)
            except json.JSONDecodeError:
                continue
            if "error" in event:
                raise RuntimeError(event["error"])
            audio = ((event.get("choices") or [{}])[0].get("delta") or {}).get("audio") or {}
            if audio.get("data"):
                chunks.append(audio["data"])
    if not chunks:
        raise RuntimeError("no audio returned")
    return base64.b64decode("".join(chunks))


def transcode(raw: bytes, path: str) -> None:
    """MP3 in, Ogg Vorbis out. q2 is about 96 kbps, which is where a background bed stops
    being distinguishable from the 192 kbps source and stops costing a megabyte a minute."""
    mp3 = path + ".mp3"
    with open(mp3, "wb") as handle:
        handle.write(raw)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", mp3, "-c:a", "libvorbis", "-q:a", "2", path],
        check=True,
    )
    os.remove(mp3)


def main() -> int:
    force = "--force" in sys.argv
    key = os.environ.get("OPENROUTER_API_KEY", "")
    if not key:
        print("no API key: set OPENROUTER_API_KEY", file=sys.stderr)
        return 2
    os.makedirs(OUT_DIR, exist_ok=True)
    for theme, brief in THEMES.items():
        path = os.path.join(OUT_DIR, theme + ".ogg")
        if os.path.exists(path) and not force:
            print(f"skip  {theme} (already rendered)")
            continue
        print(f"render {theme} ...", flush=True)
        transcode(render(key, theme, brief), path)
        print(f"       -> {os.path.getsize(path) // 1024} KB", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
