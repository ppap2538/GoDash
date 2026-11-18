"""Synthesise the soi dog's bark (our own sound: no recording, no third-party file).

  python -I tools/make_bark.py

Writes assets/sfx/dog_bark.wav: two short barks. Every bark in the Roblox Creator Store that we
found was a user upload with no licence we could check (several were lifted from other games), so
the sound is built here from a falling harmonic tone with a throat formant, a little growl and a
puff of noise. The game varies the pitch per dog.
"""
import os
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sfx")
SR = 44100
rng = np.random.default_rng(7)


def bark(dur, f_hi, f_lo, gain):
    n = int(SR * dur)
    t = np.arange(n) / SR
    k = t / dur
    f0 = f_hi * (f_lo / f_hi) ** (k ** 0.7)  # the pitch drops through the bark
    f0 *= 1 + 0.035 * np.sin(2 * np.pi * 31 * t)  # roughness
    phase = 2 * np.pi * np.cumsum(f0) / SR
    out = np.zeros(n)
    for h in range(1, 22):
        f = f0 * h
        # throat and mouth resonances: this is what makes it "woof" rather than a beep
        w = np.exp(-((f - 620) / 320) ** 2) + 0.75 * np.exp(-((f - 1350) / 480) ** 2) + 0.3 * np.exp(-((f - 2600) / 700) ** 2) + 0.05
        out += w * np.sin(h * phase + rng.uniform(0, 6.28)) / h ** 0.35
    growl = 1 + 0.45 * np.sin(2 * np.pi * 68 * t + 1.0) * np.exp(-k * 2)
    noise = rng.normal(0, 1, n)
    noise = np.convolve(noise, np.ones(9) / 9, mode="same")  # breathy, not hissy
    env = np.minimum(t / 0.012, 1.0) * np.exp(-k * 4.2) * (1 - k) ** 0.5
    sig = (out * growl + 0.9 * noise * np.exp(-k * 7)) * env
    return gain * sig / np.max(np.abs(sig))


def main():
    os.makedirs(OUT, exist_ok=True)
    gap = np.zeros(int(SR * 0.11))
    sig = np.concatenate([np.zeros(int(SR * 0.02)), bark(0.2, 520, 250, 1.0), gap, bark(0.23, 480, 220, 0.9), np.zeros(int(SR * 0.08))])
    sig = np.tanh(sig * 1.6) * 0.85  # a touch of bite, then headroom
    pcm = (sig * 32767).astype("<i2")
    path = os.path.join(OUT, "dog_bark.wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())
    print(path, "%.2f s" % (len(pcm) / SR))


if __name__ == "__main__":
    main()
