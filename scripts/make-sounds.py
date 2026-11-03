"""Generates the UI sound sets: soft, low tones with nothing harsh on top.
Sets: standard (felt mallet), pixel (soft chip blips), air (breath), keys (quiet key taps).
Run: python3 scripts/make-sounds.py  →  Shepot/Sounds/<set>-{start,stop,paste,error}.wav"""
import os
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Shepot", "Sounds")


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def lp(x, cutoff):
    # Two passes of a one-pole low-pass: gentle 12 dB/oct roll-off.
    k = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - k) * v + k * acc
            y[i] = acc
        x = y
    return x


def felt(note, dur=0.5, decay=7.0):
    """Soft mallet: fundamental, a touch of octave, a quick 4th partial for the 'tap'."""
    t = np.arange(int(dur * SR)) / SR
    f = hz(note)
    s = (np.sin(2 * np.pi * f * t)
         + 0.18 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 10)
         + 0.08 * np.sin(2 * np.pi * 4 * f * t) * np.exp(-t * 30))
    env = np.minimum(t / 0.006, 1) * np.exp(-t * decay)
    return s * env


def mix(parts, dur):
    out = np.zeros(int(dur * SR))
    for start, sig, gain in parts:
        i = int(start * SR)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n] * gain
    return out


def write(name, x, peak=0.5, cutoff=2200):
    x = lp(x, cutoff)
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    x *= peak / np.max(np.abs(x))
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())



rng = np.random.default_rng(3)


def blip(note, dur=0.07, duty=0.25, bits=16):
    """Chip-style pulse blip, bit-crushed and rounded off by the low-pass in write()."""
    t = np.arange(int(dur * SR)) / SR
    f = hz(note)
    pulse = np.where((t * f) % 1.0 < duty, 1.0, -1.0)
    tri = 2 * np.abs(2 * ((t * f) % 1.0) - 1) - 1
    x = np.round((0.55 * pulse + 0.45 * tri) * bits / 2) / (bits / 2)
    return x * np.minimum(t / 0.002, 1) * np.exp(-t * 28)


def breath(dur, lo, hi, rise=0.5):
    """Airy swell: noise band-limited between lo and hi Hz, swelling in (rise>0.5) or fading out."""
    t = np.arange(int(dur * SR)) / SR
    n = rng.standard_normal(len(t))
    band = lp(n, hi) - lp(n, lo)
    u = t / t[-1]
    env = np.sin(np.pi * u ** (1.6 if rise >= 0.5 else 0.6)) ** 2
    return band * env


def air_tone(note, dur=0.6, decay=5.0):
    """Soft sine with a slow attack, like a breath on a flute."""
    t = np.arange(int(dur * SR)) / SR
    f = hz(note)
    s = np.sin(2 * np.pi * f * t) + 0.05 * np.sin(2 * np.pi * 2 * f * t)
    return s * np.minimum(t / 0.08, 1) * np.exp(-t * decay)


def key(pitch=150, dur=0.08):
    """Quiet key tap: a short low thump and a dull click on top."""
    t = np.arange(int(dur * SR)) / SR
    thump = np.sin(2 * np.pi * pitch * t) * np.exp(-t * 70)
    click = lp(rng.standard_normal(len(t)), 5000) * np.exp(-t * 200)
    return (0.7 * thump + 0.8 * click) * np.minimum(t / 0.001, 1)


os.makedirs(OUT, exist_ok=True)
sets = {}

# Standard: felt-mallet tones (the original set).
sets["standard"] = dict(
    cutoff=2200,
    start=mix([(0, felt(62, 0.4, 9), 0.8), (0.07, felt(69, 0.5, 7), 1.0)], 0.6),
    stop=mix([(0, felt(69, 0.4, 9), 0.8), (0.07, felt(62, 0.5, 7), 1.0)], 0.6),
    paste=mix([(0, felt(62, 0.7, 5), 0.8), (0.03, felt(66, 0.7, 5), 0.6), (0.06, felt(69, 0.7, 5), 0.7)], 0.8),
    error=mix([(0, felt(50, 0.35, 11), 1.0), (0.17, felt(50, 0.45, 9), 0.9)], 0.7),
)

# Pixel: tiny chip blips, rounded off so nothing bites.
sets["pixel"] = dict(
    cutoff=2800,
    start=mix([(0, blip(69), 0.8), (0.055, blip(76), 0.9), (0.11, blip(81), 1.0)], 0.3),
    stop=mix([(0, blip(81), 0.8), (0.055, blip(76), 0.9), (0.11, blip(69), 1.0)], 0.3),
    paste=mix([(0, blip(72), 0.7), (0.05, blip(79), 0.8), (0.10, blip(84, 0.12), 1.0)], 0.35),
    error=mix([(0, blip(43, 0.12, 0.5, 8), 1.0), (0.17, blip(43, 0.16, 0.5, 8), 0.9)], 0.45),
)

# Air: breath swells and soft flute-like tones.
sets["air"] = dict(
    cutoff=1300,
    start=mix([(0, breath(0.35, 250, 1000, 0.6), 0.8), (0.12, air_tone(62, 0.5), 0.7)], 0.6),
    stop=mix([(0, air_tone(62, 0.4), 0.5), (0.05, breath(0.35, 250, 1000, 0.4), 0.8)], 0.6),
    paste=mix([(0, breath(0.3, 250, 1000, 0.6), 0.6), (0.08, air_tone(55, 0.8, 4), 0.7),
               (0.12, air_tone(62, 0.8, 4), 0.6), (0.16, air_tone(66, 0.8, 4), 0.5)], 0.9),
    error=mix([(0, breath(0.2, 120, 600, 0.6), 1.0), (0.18, breath(0.25, 120, 600, 0.6), 0.9),
               (0, air_tone(41, 0.3, 9), 0.5), (0.18, air_tone(41, 0.3, 9), 0.5)], 0.5),
)

# Keys: short quiet keyboard-like taps.
sets["keys"] = dict(
    cutoff=4800,
    start=mix([(0, key(150), 0.8), (0.07, key(210), 1.0)], 0.2),
    stop=mix([(0, key(210), 0.8), (0.07, key(150), 1.0)], 0.2),
    paste=mix([(0, key(170), 0.7), (0.06, key(190), 0.8), (0.11, key(160), 0.7), (0.19, key(240, 0.1), 1.0)], 0.35),
    error=mix([(0, key(90, 0.12), 1.0), (0.16, key(80, 0.14), 0.9)], 0.35),
)

QUIET = {"keys": 0.34, "pixel": 0.4}
for name, parts in sets.items():
    cutoff = parts.pop("cutoff")
    for kind, signal in parts.items():
        peak = QUIET.get(name, 0.55 if kind == "error" else 0.5)
        write(f"{name}-{kind}.wav", signal, peak=peak, cutoff=cutoff)
print("wrote", OUT)
