"""Generates the UI sound sets: soft, low tones with nothing harsh on top.
Sets: standard (felt mallet), nature (airy whooshes), soft (round tones), keys (haptic taps).
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
    env = np.minimum(t / 0.02, 1) * np.exp(-t * decay)
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
    return s * np.minimum(t / 0.14, 1) * np.exp(-t * decay)


def tap(pitch=90, dur=0.09, decay=55.0):
    """Haptic tap: a low sine that drops in pitch, with a barely audible soft touch at the start."""
    t = np.arange(int(dur * SR)) / SR
    f = pitch * (1 + 0.8 * np.exp(-t * 60))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * decay)
    touch = lp(rng.standard_normal(len(t)), 900) * np.exp(-t * 150) * 0.25
    return (body + touch) * np.minimum(t / 0.002, 1)


def whoosh(f0, f1, dur=0.5, peak_at=0.4, width=0.35):
    """Breath of wind: noise through a band-pass whose centre glides from f0 to f1, swelling and fading."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    fc = f0 * (f1 / f0) ** (t / dur)
    g = 2 * np.sin(np.pi * np.minimum(fc, 8000) / SR)
    q = 0.55
    low = band = 0.0
    out = np.empty(n)
    for i in range(n):
        low += g[i] * band
        high = x[i] - low - q * band
        band += g[i] * high
        out[i] = band
    u = t / dur
    env = np.exp(-((u - peak_at) ** 2) / (2 * width ** 2 * 0.35))
    return out * env * np.minimum(t / 0.03, 1)


os.makedirs(OUT, exist_ok=True)
sets = {}

# Standard: felt-mallet tones (the original set).
sets["standard"] = dict(
    cutoff=1700,
    start=mix([(0, felt(62, 0.4, 9), 0.8), (0.07, felt(69, 0.5, 7), 1.0)], 0.6),
    stop=mix([(0, felt(69, 0.4, 9), 0.8), (0.07, felt(62, 0.5, 7), 1.0)], 0.6),
    paste=mix([(0, felt(62, 0.7, 5), 0.8), (0.03, felt(66, 0.7, 5), 0.6), (0.06, felt(69, 0.7, 5), 0.7)], 0.8),
    error=mix([(0, felt(50, 0.35, 11), 1.0), (0.17, felt(50, 0.45, 9), 0.9)], 0.7),
)

# Nature: soft wind whooshes, rising on start and falling on stop.
sets["nature"] = dict(
    cutoff=3500,
    start=mix([(0, whoosh(500, 2200, 0.55, 0.65), 1.0)], 0.55),
    stop=mix([(0, whoosh(2000, 450, 0.5, 0.35), 1.0)], 0.5),
    paste=mix([(0, whoosh(900, 3000, 0.3, 0.55), 1.0)], 0.3),
    error=mix([(0, whoosh(260, 150, 0.28, 0.4, ), 1.0), (0.2, whoosh(240, 130, 0.32, 0.4), 0.9)], 0.55),
)

# Soft: round sine tones with a slow attack, nothing airy or bright.
sets["soft"] = dict(
    cutoff=1000,
    start=mix([(0, soft_tone(62, 0.5), 1.0)], 0.5),
    stop=mix([(0, soft_tone(62, 0.4), 1.0)], 0.4),
    paste=mix([(0, soft_tone(55, 0.8, 4), 0.8), (0.04, soft_tone(62, 0.8, 4), 0.7), (0.08, soft_tone(66, 0.8, 4), 0.6)], 0.9),
    error=mix([(0, soft_tone(41, 0.35, 7), 1.0), (0.18, soft_tone(41, 0.4, 7), 0.9)], 0.6),
)

# Keys: soft haptic-like taps.
sets["keys"] = dict(
    cutoff=1800,
    start=mix([(0, tap(95), 0.8), (0.07, tap(120), 1.0)], 0.2),
    stop=mix([(0, tap(120), 0.8), (0.07, tap(95), 1.0)], 0.2),
    paste=mix([(0, tap(105), 0.7), (0.06, tap(115), 0.9)], 0.2),
    error=mix([(0, tap(65, 0.12, 35), 1.0), (0.15, tap(60, 0.14, 32), 0.9)], 0.3),
)

QUIET = {"keys": 0.3, "nature": 0.36}
for name, parts in sets.items():
    cutoff = parts.pop("cutoff")
    for kind, signal in parts.items():
        peak = QUIET.get(name, 0.42 if kind == "error" else 0.36)
        write(f"{name}-{kind}.wav", signal, peak=peak, cutoff=cutoff)
print("wrote", OUT)
