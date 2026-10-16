"""Generates the game sound effects as small 16-bit mono WAV files.
Run:  python3 tools/make_sounds.py   (needs numpy)
Everything is synthesized, so there are no licensing issues."""
import numpy as np, wave, os, math

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

def t(d): return np.linspace(0, d, int(SR * d), endpoint=False)

def env(x, a=0.005, r=0.08):
    n = len(x); e = np.ones(n)
    na, nr = max(1, int(SR * a)), max(1, int(SR * r))
    e[:na] = np.linspace(0, 1, na); e[-nr:] = np.minimum(e[-nr:], np.linspace(1, 0, nr))
    return x * e

def decay(x, k=6.0):
    return x * np.exp(-k * np.linspace(0, 1, len(x)))

def sine(f, d, vol=1.0): return vol * np.sin(2 * np.pi * f * t(d))
def noise(d, vol=1.0): return vol * rng.uniform(-1, 1, int(SR * d))
def sweep(f0, f1, d, vol=1.0):
    tt = t(d); f = f0 + (f1 - f0) * tt / d
    return vol * np.sin(2 * np.pi * np.cumsum(f) / SR)

def lowpass(x, a=0.2):
    y = np.zeros_like(x); s = 0.0
    for i, v in enumerate(x): s += a * (v - s); y[i] = s
    return y

def mix(*parts, length=None):
    n = length or max(len(p) + int(o * SR) for p, o in parts)
    out = np.zeros(n)
    for p, o in parts:
        o = int(o * SR); out[o:o + len(p)] += p[:max(0, n - o)]
    return out

def save(name, x, vol=0.8):
    x = x / (np.max(np.abs(x)) or 1) * vol
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())

def note(f, d, vol=1.0, k=5.0):
    return decay(env(sine(f, d, vol) + 0.3 * sine(2 * f, d, vol), 0.004, 0.03), k)

# ---- UI
save('tap', decay(env(sine(900, 0.05), 0.002, 0.02), 7), 0.5)
save('chip', mix((decay(sine(2400, 0.06), 9), 0), (decay(sine(3600, 0.05), 10), 0.025)), 0.6)
save('error', mix((note(220, 0.14), 0), (note(165, 0.2), 0.12)), 0.6)
save('coin', mix((note(1318, 0.1), 0), (note(1760, 0.3, k=4), 0.09)), 0.7)

# ---- slots
save('spin', env(lowpass(noise(0.5, 0.6), 0.08) + sweep(180, 420, 0.5, 0.25), 0.02, 0.15), 0.6)
save('reel_stop', mix((decay(sine(140, 0.12), 9), 0), (decay(lowpass(noise(0.05), 0.3), 10), 0)), 0.8)
save('win', mix(*[(note(f, 0.28, k=4), i * 0.09) for i, f in enumerate([523, 659, 784, 1047])]), 0.75)
save('big_win', mix(*[(note(f, 0.4, k=3), i * 0.08) for i, f in enumerate([523, 659, 784, 1047, 1319, 1568])],
                    *[(decay(env(noise(0.05), 0.001, 0.03), 6) * 0.3, 0.5 + i * 0.07) for i in range(8)]), 0.85)
save('lose', mix((note(294, 0.22, k=4), 0), (note(233, 0.35, k=4), 0.16)), 0.55)

# ---- cards
save('card', mix((lowpass(noise(0.08), 0.35) * np.linspace(1, 0, int(SR * 0.08)), 0), (decay(sine(500, 0.04), 8) * 0.4, 0)), 0.7)
save('card_flip', mix((lowpass(noise(0.06), 0.4), 0), (decay(sine(700, 0.05), 9) * 0.3, 0.03)), 0.7)
save('blackjack', mix(*[(note(f, 0.25, k=3.5), i * 0.07) for i, f in enumerate([659, 880, 1109, 1319])]), 0.8)

# ---- dice
clicks = [(decay(env(noise(0.025), 0.0005, 0.01), 5) * (0.9 - i * 0.07), i * (0.05 + 0.012 * i)) for i in range(9)]
save('dice_roll', mix(*clicks, length=int(SR * 0.75)), 0.8)

# ---- roulette
ticks = [(decay(sine(1800, 0.03), 9) * 0.7, 0.06 * i + 0.0015 * i * i) for i in range(18)]
save('roulette_spin', mix(*ticks, (env(lowpass(noise(1.3, 0.22), 0.05), 0.1, 0.5), 0), length=int(SR * 1.5)), 0.7)
save('ball_drop', mix((decay(sine(1200, 0.05), 10), 0), (decay(sine(900, 0.05), 10), 0.07), (decay(sine(1500, 0.04), 12), 0.13)), 0.7)

# ---- crash
save('crash_start', env(sweep(220, 660, 0.45, 0.8), 0.01, 0.1), 0.6)
save('crash_tick', decay(env(sine(1100, 0.04), 0.002, 0.015), 8), 0.35)
save('cash_out', mix((note(988, 0.12), 0), (note(1319, 0.12), 0.09), (note(1760, 0.35, k=4), 0.18)), 0.8)
save('bust', mix((env(lowpass(noise(0.5, 0.9), 0.12), 0.003, 0.4) * np.exp(-4 * np.linspace(0, 1, int(SR * 0.5))), 0),
                 (sweep(300, 60, 0.45, 0.8) * np.exp(-3 * np.linspace(0, 1, int(SR * 0.45))), 0)), 0.9)

# ---- background loop (soft pad, loops cleanly: whole cycles of every partial)
d = 8.0; tt = t(d)
pad = sum(np.sin(2 * np.pi * f * tt) * v for f, v in [(110, .5), (165, .3), (220, .25), (275, .18), (330, .12)])
pad *= 0.6 + 0.4 * np.sin(2 * np.pi * tt / d)
save('music', pad, 0.25)
print('ok', sorted(os.listdir(OUT)))
