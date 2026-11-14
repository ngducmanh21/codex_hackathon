#!/usr/bin/env python3
"""Turns a dialogue script into one audio file for rehearsing the demo.

Play the file from a laptop next to the phone: it stands in for the person
across the table, says the same words every time, and can carry the numbers
and terms that make the glossary, "Giải thích" and the summary worth
watching.

Each line of the script is "voice: what is said". Blank lines and lines
starting with # are ignored. Lines are spoken one at a time and joined with
a short pause, so the app sees separate sentences.

    export OPENAI_API_KEY=sk-...
    python3 tool/make_demo_audio.py tool/demo_zh.txt demo-zh.wav

The key is read from the environment only: never pass it on the command
line, where it would land in the shell history.
"""

import json
import os
import struct
import sys
import urllib.error
import urllib.request

MODEL = "gpt-4o-mini-tts"
URL = "https://api.openai.com/v1/audio/speech"
SAMPLE_RATE = 24000  # what the API returns for wav
PAUSE_SECONDS = 0.9

INSTRUCTIONS = (
    "Speak as someone in a business meeting about a parts order: calm, "
    "unhurried, clear. Say numbers distinctly."
)


def speak(text: str, voice: str, key: str) -> bytes:
    """One line as a wav, as the speech endpoint returns it."""
    body = json.dumps(
        {
            "model": MODEL,
            "voice": voice,
            "input": text,
            "instructions": INSTRUCTIONS,
            "response_format": "wav",
        }
    ).encode()
    request = urllib.request.Request(
        URL,
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:400]
        raise SystemExit(f"OpenAI trả lỗi {error.code}: {detail}") from None


def pcm_of(wav: bytes) -> bytes:
    """The samples inside a wav, skipping its chunks."""
    if wav[:4] != b"RIFF" or wav[8:12] != b"WAVE":
        raise SystemExit("Phản hồi không phải wav.")
    at = 12
    while at + 8 <= len(wav):
        name = wav[at : at + 4]
        size = struct.unpack("<I", wav[at + 4 : at + 8])[0]
        if name == b"data":
            return wav[at + 8 : at + 8 + size]
        at += 8 + size + (size % 2)
    raise SystemExit("Không thấy phần data trong wav.")


def wav_of(pcm: bytes) -> bytes:
    """A 16-bit mono wav around [pcm]."""
    header = b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt "
    header += struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16)
    return header + b"data" + struct.pack("<I", len(pcm)) + pcm


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Dùng: make_demo_audio.py <kịch bản.txt> <đầu ra.wav>")
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        raise SystemExit("Chưa đặt OPENAI_API_KEY.")

    script, out = sys.argv[1], sys.argv[2]
    silence = b"\0" * (int(SAMPLE_RATE * PAUSE_SECONDS) * 2)
    pieces = []
    with open(script, encoding="utf-8") as f:
        for number, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                raise SystemExit(f"Dòng {number} thiếu dấu hai chấm: {line}")
            voice, text = line.split(":", 1)
            text = text.strip()
            if not text:
                continue
            print(f"  {number:>2}. [{voice.strip()}] {text[:48]}…")
            pieces.append(pcm_of(speak(text, voice.strip(), key)))
            pieces.append(silence)

    if not pieces:
        raise SystemExit("Kịch bản rỗng.")
    audio = b"".join(pieces)
    with open(out, "wb") as f:
        f.write(wav_of(audio))
    seconds = len(audio) / (SAMPLE_RATE * 2)
    print(f"Đã ghi {out} · {seconds:.1f} giây")


if __name__ == "__main__":
    main()
