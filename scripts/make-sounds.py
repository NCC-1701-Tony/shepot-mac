"""Generates the UI sound sets: soft, low tones with nothing harsh on top.
Sets: standard (felt mallet), pixel (futuristic FM chimes), soft (round tones), keys (quiet key taps).
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


def fm(note, dur=0.3, index=2.0, ratio=2.0, decay=9.0, bright=14.0):
    """Glassy digital tone: a sine whose phase is modulated by a faster, quickly fading sine."""
    t = np.arange(int(dur * SR)) / SR
    f = hz(note)
    mod = index * np.exp(-t * bright) * np.sin(2 * np.pi * f * ratio * t)
    return np.sin(2 * np.pi * f * t + mod) * np.minimum(t / 0.003, 1) * np.exp(-t * decay)


def sweep(f0, f1, dur=0.2):
    """Short rising or falling glide with a soft bell-shaped envelope, like a system powering up."""
    t = np.arange(int(dur * SR)) / SR
    f = f0 + (f1 - f0) * (t / dur) ** 1.5
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    return s * np.sin(np.pi * t / dur) ** 2


def echo(x, taps=((0.09, 0.38), (0.18, 0.2), (0.27, 0.1))):
    """Short digital echo tail: delayed, quieter copies."""
    out = np.zeros(len(x) + int(0.3 * SR))
    out[:len(x)] += x
    for delay, gain in taps:
        i = int(delay * SR)
        out[i:i + len(x)] += x * gain
    return out


def soft_tone(note, dur=0.6, decay=5.0):
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

# Tech: clean FM chimes and glides, dry, like a futuristic assistant waking up.
sets["pixel"] = dict(
    cutoff=5200,
    start=mix([(0, sweep(300, 900, 0.18), 0.5), (0.12, fm(69, 0.3), 0.8), (0.19, fm(76, 0.3), 0.9),
                    (0.26, fm(81, 0.45, 1.6, 2.0, 7), 1.0)], 0.75),
    stop=mix([(0, fm(81, 0.3), 0.8), (0.07, fm(76, 0.3), 0.9), (0.14, fm(69, 0.4, 1.6, 2.0, 8), 1.0),
                   (0.16, sweep(900, 300, 0.2), 0.45)], 0.6),
    paste=mix([(0, fm(76, 0.25), 0.8), (0.07, fm(83, 0.4, 1.5, 2.0, 8), 1.0)], 0.5),
    error=mix([(0, fm(45, 0.25, 3.0, 1.41, 12, 22), 1.0), (0.17, fm(45, 0.3, 3.0, 1.41, 11, 22), 0.9)], 0.55),
)

# Soft: round sine tones with a slow attack, nothing airy or bright.
sets["soft"] = dict(
    cutoff=1300,
    start=mix([(0, soft_tone(62, 0.5), 1.0)], 0.5),
    stop=mix([(0, soft_tone(62, 0.4), 1.0)], 0.4),
    paste=mix([(0, soft_tone(55, 0.8, 4), 0.8), (0.04, soft_tone(62, 0.8, 4), 0.7), (0.08, soft_tone(66, 0.8, 4), 0.6)], 0.9),
    error=mix([(0, soft_tone(41, 0.35, 7), 1.0), (0.18, soft_tone(41, 0.4, 7), 0.9)], 0.6),
)

# Keys: short quiet keyboard-like taps.
sets["keys"] = dict(
    cutoff=4800,
    start=mix([(0, key(150), 0.8), (0.07, key(210), 1.0)], 0.2),
    stop=mix([(0, key(210), 0.8), (0.07, key(150), 1.0)], 0.2),
    paste=mix([(0, key(170), 0.7), (0.06, key(190), 0.8), (0.11, key(160), 0.7), (0.19, key(240, 0.1), 1.0)], 0.35),
    error=mix([(0, key(90, 0.12), 1.0), (0.16, key(80, 0.14), 0.9)], 0.35),
)

QUIET = {"keys": 0.34, "pixel": 0.45}
for name, parts in sets.items():
    cutoff = parts.pop("cutoff")
    for kind, signal in parts.items():
        peak = QUIET.get(name, 0.55 if kind == "error" else 0.5)
        write(f"{name}-{kind}.wav", signal, peak=peak, cutoff=cutoff)
print("wrote", OUT)
