"""Generates the app's three UI sounds: soft, low, felt-mallet tones with nothing harsh on top.
Run: python3 scripts/make-sounds.py  →  Shepot/Sounds/{start,stop,paste}.wav"""
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


def write(name, x, peak=0.5):
    x = lp(x, 2200)
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    x *= peak / np.max(np.abs(x))
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


os.makedirs(OUT, exist_ok=True)
# Start: two notes stepping up (D4 → A4), like "listening".
write("start.wav", mix([(0, felt(62, 0.4, 9), 0.8), (0.07, felt(69, 0.5, 7), 1.0)], 0.6))
# Stop: the same pair stepping down (A4 → D4).
write("stop.wav", mix([(0, felt(69, 0.4, 9), 0.8), (0.07, felt(62, 0.5, 7), 1.0)], 0.6))
# Pasted: a warm low chord (D4, F#4, A4) with a soft strum.
write("paste.wav", mix([(0, felt(62, 0.7, 5), 0.8), (0.03, felt(66, 0.7, 5), 0.6),
                        (0.06, felt(69, 0.7, 5), 0.7)], 0.8), peak=0.45)
# Error: two low, dull thuds ("tun-tun"), same pitch, no upper partials.
write("error.wav", mix([(0, felt(50, 0.35, 11), 1.0), (0.17, felt(50, 0.45, 9), 0.9)], 0.7), peak=0.55)
print("wrote", OUT)
