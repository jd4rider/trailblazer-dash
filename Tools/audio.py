#!/usr/bin/env python3
"""Synthesise every sound in Trailblazer Dash.

No sample libraries: everything is generated from oscillators and shaped noise,
so the whole soundtrack is original and reproducible from this file.

    python3 Tools/audio.py
"""

from __future__ import annotations

import array
import math
import os
import random
import struct
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "Assets", "Audio")
SFX = os.path.join(AUDIO, "SFX")
MUSIC = os.path.join(AUDIO, "Music")
AMB = os.path.join(AUDIO, "Ambience")
SR = 22050

for folder in (SFX, MUSIC, AMB):
    os.makedirs(folder, exist_ok=True)


# --------------------------------------------------------------------------
# tiny DSP kit
# --------------------------------------------------------------------------

def write(path: str, samples: list[float], rate: int = SR) -> None:
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = min(1.0, 0.92 / peak)
    data = array.array("h", (int(max(-1.0, min(1.0, s * scale)) * 32767) for s in samples))
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(data.tobytes())


def silence(seconds: float) -> list[float]:
    return [0.0] * int(seconds * SR)


def env(n: int, attack: float, decay: float, curve: float = 2.0) -> list[float]:
    a = max(1, int(attack * SR))
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        else:
            t = (i - a) / max(1, n - a)
            out.append(max(0.0, (1.0 - t) ** curve if decay <= 0 else math.exp(-t * decay)))
    return out


def tone(freq: float, seconds: float, amp: float = 0.5, shape: str = "sine", detune: float = 0.0) -> list[float]:
    n = int(seconds * SR)
    out = []
    for i in range(n):
        t = i / SR
        phase = 2 * math.pi * freq * t
        if shape == "sine":
            v = math.sin(phase)
        elif shape == "tri":
            v = 2 / math.pi * math.asin(math.sin(phase))
        elif shape == "saw":
            v = 2 * ((freq * t) % 1.0) - 1
        elif shape == "square":
            v = 1.0 if math.sin(phase) >= 0 else -1.0
        else:
            v = math.sin(phase)
        if detune:
            v = 0.6 * v + 0.4 * math.sin(phase * (1 + detune))
        out.append(v * amp)
    return out


def sweep(f0: float, f1: float, seconds: float, amp: float = 0.5, shape: str = "sine") -> list[float]:
    n = int(seconds * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        f = f0 + (f1 - f0) * t
        phase += 2 * math.pi * f / SR
        v = math.sin(phase) if shape == "sine" else 2 * ((phase / (2 * math.pi)) % 1.0) - 1
        out.append(v * amp)
    return out


def noise(seconds: float, amp: float = 0.5, lowpass: float = 1.0, seed: int = 1) -> list[float]:
    rng = random.Random(seed)
    n = int(seconds * SR)
    out = []
    prev = 0.0
    for _ in range(n):
        white = rng.uniform(-1, 1)
        prev = prev + lowpass * (white - prev)
        out.append(prev * amp)
    return out


def mix(*tracks: list[float]) -> list[float]:
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for track in tracks:
        for i, v in enumerate(track):
            out[i] += v
    return out


def gain(track: list[float], amount: float) -> list[float]:
    return [v * amount for v in track]


def apply_env(track: list[float], shape: list[float]) -> list[float]:
    return [v * shape[i] if i < len(shape) else 0.0 for i, v in enumerate(track)]


def concat(*tracks: list[float]) -> list[float]:
    out = []
    for track in tracks:
        out.extend(track)
    return out


def reverb(track: list[float], taps: tuple[tuple[int, float], ...] = ((1400, 0.28), (2700, 0.18), (4300, 0.1))) -> list[float]:
    out = list(track)
    for delay, level in taps:
        for i in range(delay, len(out)):
            out[i] += track[i - delay] * level
    return out


def loop_ready(track: list[float], fade: float = 0.18) -> list[float]:
    """Crossfade the tail into the head so the file loops without a click."""
    n = int(fade * SR)
    if n * 2 >= len(track):
        return track
    head = track[:n]
    tail = track[-n:]
    body = track[n:len(track) - n]
    blended = [head[i] * (i / n) + tail[i] * (1 - i / n) for i in range(n)]
    return blended + body


# --------------------------------------------------------------------------
# footsteps, one per surface
# --------------------------------------------------------------------------

def footstep(surface: str, seed: int) -> list[float]:
    rng = random.Random(seed)
    base = {
        "grass": (0.10, 520, 0.55),
        "stone": (0.055, 1500, 0.8),
        "sand": (0.11, 900, 0.4),
        "snow": (0.12, 700, 0.5),
        "metal": (0.05, 2200, 0.9),
        "wood": (0.06, 1100, 0.85),
        "mud": (0.13, 380, 0.45),
    }[surface]
    length, cutoff, amp = base
    body = noise(length, amp, lowpass=min(0.95, cutoff / SR * 6), seed=seed)
    body = apply_env(body, env(len(body), 0.004, 5.0, 2.4))
    thump = []
    if surface in ("stone", "wood", "metal"):
        freq = {"stone": 120, "wood": 180, "metal": 320}[surface]
        thump = apply_env(tone(freq, length * 1.4, 0.35, "sine"), env(int(length * 1.4 * SR), 0.002, 8.0))
    if surface == "snow":
        crunch = apply_env(noise(length, 0.35, 0.5, seed + 7), env(int(length * SR), 0.01, 3.0))
        return reverb(mix(body, crunch))
    if surface == "grass":
        rustle = apply_env(noise(length * 1.2, 0.25, 0.25, seed + 3), env(int(length * 1.2 * SR), 0.01, 4.0))
        return mix(body, rustle)
    return reverb(mix(body, thump))


def build_sfx() -> None:
    for surface in ("grass", "stone", "sand", "snow", "metal", "wood", "mud"):
        for variant in range(3):
            write(os.path.join(SFX, f"step_{surface}_{variant}.wav"), footstep(surface, 100 + variant * 17))

    jump = mix(
        apply_env(sweep(190, 430, 0.20, 0.4), env(int(0.20 * SR), 0.01, 3.5)),
        apply_env(noise(0.16, 0.18, 0.3, 21), env(int(0.16 * SR), 0.005, 5.0)),
    )
    write(os.path.join(SFX, "jump.wav"), reverb(jump))

    land = mix(
        apply_env(tone(95, 0.20, 0.5), env(int(0.20 * SR), 0.002, 9.0)),
        apply_env(noise(0.14, 0.3, 0.25, 33), env(int(0.14 * SR), 0.003, 7.0)),
    )
    write(os.path.join(SFX, "land.wav"), reverb(land))

    slide = apply_env(noise(0.45, 0.5, 0.35, 41), env(int(0.45 * SR), 0.03, 1.4, 1.4))
    write(os.path.join(SFX, "slide.wav"), slide)

    for index, (a, b) in enumerate(((880, 1320), (990, 1480), (760, 1140))):
        pickup = concat(apply_env(tone(a, 0.07, 0.3), env(int(0.07 * SR), 0.002, 6.0)),
                        apply_env(tone(b, 0.10, 0.26), env(int(0.10 * SR), 0.002, 5.0)))
        write(os.path.join(SFX, f"pickup_{index}.wav"), reverb(pickup, ((900, 0.2),)))

    relic_notes = (660, 880, 1100, 1320)
    relic = concat(*[apply_env(tone(f, 0.10, 0.24, "tri"), env(int(0.10 * SR), 0.004, 4.0)) for f in relic_notes])
    write(os.path.join(SFX, "relic.wav"), reverb(relic, ((1200, 0.3), (2400, 0.2))))

    power = concat(*[apply_env(tone(f, 0.08, 0.26, "sine"), env(int(0.08 * SR), 0.003, 4.0))
                     for f in (523, 659, 784, 1046, 1318)])
    write(os.path.join(SFX, "powerup.wav"), reverb(power, ((1100, 0.25),)))

    hit = mix(
        apply_env(noise(0.22, 0.55, 0.5, 55), env(int(0.22 * SR), 0.002, 6.0)),
        apply_env(sweep(220, 70, 0.22, 0.35, "saw"), env(int(0.22 * SR), 0.002, 5.0)),
    )
    write(os.path.join(SFX, "hit.wav"), reverb(hit))

    shield = mix(
        apply_env(noise(0.35, 0.4, 0.7, 66), env(int(0.35 * SR), 0.002, 4.0)),
        apply_env(sweep(1200, 240, 0.35, 0.25, "sine"), env(int(0.35 * SR), 0.002, 3.0)),
    )
    write(os.path.join(SFX, "shield.wav"), reverb(shield))

    beacon = mix(
        *[apply_env(tone(f, 1.4, 0.16, "sine", 0.003), env(int(1.4 * SR), 0.12, 1.2, 1.0))
          for f in (261, 329, 392, 523, 659)],
        apply_env(noise(1.4, 0.13, 0.18, 77), env(int(1.4 * SR), 0.2, 1.1, 1.0)),
    )
    write(os.path.join(SFX, "beacon.wav"), reverb(beacon, ((2200, 0.3), (3600, 0.2))))

    write(os.path.join(SFX, "gate.wav"),
          reverb(apply_env(noise(0.5, 0.35, 0.25, 88), env(int(0.5 * SR), 0.08, 1.2, 1.2))))

    write(os.path.join(SFX, "stumble.wav"), reverb(mix(
        apply_env(noise(0.28, 0.4, 0.3, 99), env(int(0.28 * SR), 0.01, 4.0)),
        apply_env(sweep(300, 120, 0.28, 0.3, "tri"), env(int(0.28 * SR), 0.01, 4.0)))))

    write(os.path.join(SFX, "ui_click.wav"),
          apply_env(tone(920, 0.055, 0.24, "sine"), env(int(0.055 * SR), 0.001, 8.0)))
    write(os.path.join(SFX, "ui_back.wav"),
          apply_env(tone(520, 0.08, 0.22, "sine"), env(int(0.08 * SR), 0.002, 6.0)))

    star = concat(
        apply_env(tone(1046, 0.12, 0.28, "sine"), env(int(0.12 * SR), 0.002, 4.0)),
        apply_env(tone(1568, 0.25, 0.22, "sine"), env(int(0.25 * SR), 0.004, 3.0)),
    )
    write(os.path.join(SFX, "star.wav"), reverb(star, ((1400, 0.3), (2800, 0.18))))


# --------------------------------------------------------------------------
# music — six moods, three layers each
# --------------------------------------------------------------------------

SCALES = {
    "major": (0, 2, 4, 5, 7, 9, 11),
    "minor": (0, 2, 3, 5, 7, 8, 10),
    "dorian": (0, 2, 3, 5, 7, 9, 10),
    "phrygian": (0, 1, 3, 5, 7, 8, 10),
}

MOODS = {
    # name: (root_hz, tempo, scale, brightness, drive)
    "meadow": (261.63, 104, "major", 0.8, 0.35),
    "forest": (220.00, 96, "dorian", 0.6, 0.4),
    "coast": (246.94, 108, "major", 0.75, 0.45),
    "forge": (196.00, 128, "phrygian", 0.5, 0.75),
    "aether": (174.61, 84, "minor", 0.55, 0.25),
    "dune": (233.08, 112, "dorian", 0.65, 0.5),
}


def note_hz(root: float, scale: str, degree: int, octave: int = 0) -> float:
    steps = SCALES[scale]
    octave_shift, index = divmod(degree, len(steps))
    return root * (2 ** (octave + octave_shift + steps[index] / 12.0))


def pad_layer(mood: str, bars: int = 4) -> list[float]:
    root, tempo, scale, bright, drive = MOODS[mood]
    beat = 60.0 / tempo
    length = bars * 4 * beat
    out = silence(length)
    progression = (0, 5, 3, 4)
    for bar in range(bars):
        degree = progression[bar % len(progression)]
        for voice, (octave, amp) in enumerate(((0, 0.13), (1, 0.07), (-1, 0.10))):
            freq = note_hz(root, scale, degree, octave)
            pad = tone(freq, 4 * beat, amp, "sine", detune=0.004)
            shape = env(len(pad), 0.35, 0.0, 1.0)
            # hold then release inside the bar
            release = int(0.5 * SR)
            for i in range(len(shape)):
                if i > len(shape) - release:
                    shape[i] *= (len(shape) - i) / release
            pad = apply_env(pad, shape)
            start = int(bar * 4 * beat * SR)
            for i, v in enumerate(pad):
                if start + i < len(out):
                    out[start + i] += v
    # slow shimmer
    shimmer = tone(root * 4, length, 0.03 * bright, "sine", detune=0.01)
    return mix(out, shimmer)


def bass_layer(mood: str, bars: int = 4) -> list[float]:
    root, tempo, scale, bright, drive = MOODS[mood]
    beat = 60.0 / tempo
    out = silence(bars * 4 * beat)
    progression = (0, 0, 5, 3)
    for bar in range(bars):
        degree = progression[bar % len(progression)]
        freq = note_hz(root, scale, degree, -2)
        for pulse in range(4):
            if pulse == 3 and drive < 0.4:
                continue
            n = apply_env(tone(freq, beat * 0.55, 0.20 + drive * 0.10, "tri"),
                          env(int(beat * 0.55 * SR), 0.006, 5.0))
            start = int((bar * 4 + pulse) * beat * SR)
            for i, v in enumerate(n):
                if start + i < len(out):
                    out[start + i] += v
    return out


def arp_layer(mood: str, bars: int = 4) -> list[float]:
    root, tempo, scale, bright, drive = MOODS[mood]
    beat = 60.0 / tempo
    step = beat / 2
    out = silence(bars * 4 * beat)
    rng = random.Random(hash(mood) & 0xFFFF)
    pattern = (0, 2, 4, 2, 5, 4, 2, 6)
    for bar in range(bars):
        for i in range(8):
            degree = pattern[(i + bar) % len(pattern)]
            freq = note_hz(root, scale, degree, 1)
            amp = 0.075 * (0.7 + bright * 0.5)
            n = apply_env(tone(freq, step * 0.9, amp, "sine", detune=0.003),
                          env(int(step * 0.9 * SR), 0.004, 6.5))
            start = int((bar * 8 + i) * step * SR)
            for j, v in enumerate(n):
                if start + j < len(out):
                    out[start + j] += v
    return out


def lead_layer(mood: str, bars: int = 4) -> list[float]:
    root, tempo, scale, bright, drive = MOODS[mood]
    beat = 60.0 / tempo
    out = silence(bars * 4 * beat)
    phrases = (
        ((0, 2), (4, 2), (2, 2), (4, 2), (5, 4), (4, 4)),
        ((2, 2), (4, 2), (5, 2), (4, 2), (2, 4), (0, 4)),
    )
    for bar in range(bars):
        phrase = phrases[bar % len(phrases)]
        position = 0.0
        for degree, duration in phrase:
            freq = note_hz(root, scale, degree, 2)
            n = apply_env(tone(freq, duration * beat * 0.92, 0.10 * (0.6 + bright), "tri"),
                          env(int(duration * beat * 0.92 * SR), 0.02, 2.2, 1.4))
            start = int((bar * 4 * beat + position * beat) * SR)
            for i, v in enumerate(n):
                if start + i < len(out):
                    out[start + i] += v
            position += duration
            if position >= 4:
                break
    return out


def build_music() -> None:
    for mood in MOODS:
        for layer, fn in (("base", pad_layer), ("bass", bass_layer),
                          ("arp", arp_layer), ("lead", lead_layer)):
            track = fn(mood)
            write(os.path.join(MUSIC, f"{mood}_{layer}.wav"), loop_ready(track, 0.12))


# --------------------------------------------------------------------------
# ambience beds
# --------------------------------------------------------------------------

def bed(name: str, seconds: float, seed: int) -> list[float]:
    rng = random.Random(seed)
    n = int(seconds * SR)
    out = [0.0] * n

    def place(sound: list[float], at: float, level: float = 1.0) -> None:
        start = int(at * SR) % max(1, n)
        for i, v in enumerate(sound):
            index = start + i
            if index < n:
                out[index] += v * level
            else:
                out[index - n] += v * level

    if name == "birds":
        base = noise(seconds, 0.05, 0.06, seed)
        for i in range(18):
            start = rng.uniform(0, seconds)
            chirps = rng.randint(2, 4)
            sound = []
            for c in range(chirps):
                f0 = rng.uniform(1800, 3200)
                sound.extend(apply_env(tone(f0, 0.05, 0.10, "sine"),
                                       env(int(0.05 * SR), 0.004, 5.0)))
            place(concat(*[sound]), start, 0.8)
        return mix(base, out)
    if name == "forest":
        base = noise(seconds, 0.09, 0.05, seed)
        for i in range(9):
            place(apply_env(noise(0.5, 0.05, 0.12, seed + i), env(int(0.5 * SR), 0.05, 2.0)),
                  rng.uniform(0, seconds))
        return out if not base else mix(base, out)
    if name == "water":
        base = noise(seconds, 0.16, 0.08, seed)
        bubble = []
        for i in range(14):
            bubble.extend(apply_env(tone(rng.uniform(500, 1500), 0.06, 0.05, "sine"),
                                    env(int(0.06 * SR), 0.004, 6.0)))
            bubble.extend(silence(rng.uniform(0.05, 0.3)))
        return mix(base, out, concat(bubble[:n]))
    if name == "waves":
        base = noise(seconds, 0.02, 0.03, seed)
        for i in range(int(seconds / 4)):
            swell = apply_env(noise(3.2, 0.22, 0.06, seed + i), env(int(3.2 * SR), 1.2, 1.4, 1.2))
            place(swell, i * 4 + rng.uniform(0, 0.4))
        return mix(base, out)
    if name == "wind":
        base = noise(seconds, 0.12, 0.02, seed)
        return mix(base, out)
    if name == "alpine":
        base = noise(seconds, 0.09, 0.02, seed)
        for i in range(5):
            place(apply_env(tone(rng.uniform(700, 1100), 0.6, 0.05, "sine"),
                            env(int(0.6 * SR), 0.15, 1.6)), rng.uniform(0, seconds))
        return mix(base, out)
    if name == "machinery":
        hum = tone(58, seconds, 0.12, "saw")
        hum2 = tone(87, seconds, 0.07, "sine", detune=0.01)
        clanks = []
        for i in range(int(seconds / 1.4)):
            clank = mix(apply_env(noise(0.09, 0.16, 0.8, seed + i), env(int(0.09 * SR), 0.002, 7.0)),
                        apply_env(tone(rng.uniform(180, 420), 0.12, 0.10, "tri"),
                                  env(int(0.12 * SR), 0.002, 6.0)))
            clanks.extend(clank)
            clanks.extend(silence(max(0.0, 1.4 - 0.21)))
        return mix(hum, hum2, concat(clanks[:n]))
    if name == "cave":
        base = noise(seconds, 0.05, 0.02, seed)
        drips = []
        for i in range(7):
            drips.extend(apply_env(tone(rng.uniform(900, 1800), 0.18, 0.09, "sine"),
                                   env(int(0.18 * SR), 0.002, 5.0)))
            drips.extend(silence(rng.uniform(0.3, 1.2)))
        return reverb(mix(base, concat(drips[:n])), ((2600, 0.25),))
    if name == "storm":
        base = noise(seconds, 0.20, 0.02, seed)
        rain = noise(seconds, 0.14, 0.25, seed + 1)
        rumble = apply_env(tone(46, 1.6, 0.30, "sine"), env(int(1.6 * SR), 0.4, 1.0, 1.0))
        out2 = list(out)
        for i in range(len(rumble)):
            if i < len(out2):
                out2[i] += rumble[i]
        return mix(base, rain, out2)
    if name == "desert":
        base = noise(seconds, 0.13, 0.03, seed)
        for i in range(6):
            place(apply_env(noise(1.0, 0.10, 0.04, seed + i), env(int(1.0 * SR), 0.3, 1.5)),
                  rng.uniform(0, seconds))
        return mix(base, out)
    if name == "lava":
        base = tone(41, seconds, 0.12, "sine", detune=0.02)
        rumble = noise(seconds, 0.14, 0.015, seed)
        pops = []
        for i in range(10):
            pops.extend(apply_env(noise(0.08, 0.14, 0.5, seed + i), env(int(0.08 * SR), 0.002, 6.0)))
            pops.extend(silence(0.5))
        return mix(base, rumble, concat(pops[:n]))
    if name == "garden":
        base = noise(seconds, 0.06, 0.03, seed)
        chimes = []
        for i in range(10):
            freq = rng.choice((880, 1046, 1318, 1568))
            chimes.extend(apply_env(tone(freq, 0.9, 0.08, "sine"),
                                    env(int(0.9 * SR), 0.01, 2.5, 1.4)))
            chimes.extend(silence(rng.uniform(0.4, 1.1)))
        return reverb(mix(base, concat(chimes[:n])), ((2000, 0.28), (3400, 0.16)))
    return noise(seconds, 0.1, 0.05, seed)


def build_ambience() -> None:
    for name in ("birds", "forest", "water", "waves", "wind", "alpine",
                 "machinery", "cave", "storm", "desert", "lava", "garden"):
        track = bed(name, 6.0, abs(hash(name)) % 9973)
        write(os.path.join(AMB, name + ".wav"), loop_ready(track, 0.4))


if __name__ == "__main__":
    build_sfx()
    build_music()
    build_ambience()
    total = 0
    for folder in (SFX, MUSIC, AMB):
        for name in sorted(os.listdir(folder)):
            total += os.path.getsize(os.path.join(folder, name))
    print(f"audio built: {total / 1024 / 1024:.1f} MiB")
