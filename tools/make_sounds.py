"""Generates the game sound effects as small 16-bit mono WAV files.
Run:  python3 tools/make_sounds.py   (needs numpy)
Everything is synthesized, so there are no licensing issues.

Version 2: bell and marimba voices (FM + harmonics), soft attacks, filtered noise for clicks and swishes,
and a light room reverb so effects feel like part of one space instead of raw beeps."""
import numpy as np, wave, os

SR = 32000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'sounds')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)


def t(d): return np.arange(int(SR * d)) / SR


def adsr(n, a=0.004, r=0.05, k=0.0):
    e = np.ones(n)
    na, nr = max(1, int(SR * a)), max(1, min(n, int(SR * r)))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    if k:
        e *= np.exp(-k * np.linspace(0, 1, n))
    return e


def fft_filter(x, lo=None, hi=None):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    m = np.ones_like(f)
    if lo: m *= 1 / (1 + (lo / np.maximum(f, 1)) ** 4)
    if hi: m *= 1 / (1 + (f / hi) ** 4)
    return np.fft.irfft(X * m, len(x))


def noise(d, lo=None, hi=None): return fft_filter(rng.uniform(-1, 1, int(SR * d)), lo, hi)


def bell(f, d, k=5.0, bright=1.0, vol=1.0):
    """FM bell: a sine whose pitch is wobbled by a faster sine that fades quickly."""
    tt = t(d)
    mod = np.sin(2 * np.pi * f * 3.5 * tt) * bright * 2.2 * np.exp(-9 * tt / d)
    x = np.sin(2 * np.pi * f * tt + mod) + 0.25 * np.sin(2 * np.pi * f * 2.01 * tt) * np.exp(-6 * tt / d)
    return vol * x * adsr(len(x), 0.002, 0.03, k)


def marimba(f, d, k=7.0, vol=1.0):
    tt = t(d)
    x = np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 4 * tt) * np.exp(-14 * tt / d) + 0.2 * np.sin(2 * np.pi * f * 9.2 * tt) * np.exp(-30 * tt / d)
    return vol * x * adsr(len(x), 0.002, 0.04, k)


def pluck(f, d, k=6.0, vol=1.0):
    tt = t(d)
    x = sum(np.sin(2 * np.pi * f * h * tt) / h for h in (1, 2, 3, 4)) * np.exp(-k * tt / d)
    return vol * x * adsr(len(x), 0.003, 0.03)


def sweep(f0, f1, d, vol=1.0, curve=1.0):
    tt = np.linspace(0, 1, int(SR * d)) ** curve
    f = f0 + (f1 - f0) * tt
    return vol * np.sin(2 * np.pi * np.cumsum(f) / SR)


def click(d=0.03, lo=800, hi=6000, vol=1.0, k=9.0):
    x = noise(d, lo, hi)
    return vol * x * adsr(len(x), 0.0005, d * 0.5, k)


def thud(f=90, d=0.18, vol=1.0):
    x = sweep(f * 1.8, f, d, 1.0, 0.4)
    return vol * x * adsr(len(x), 0.002, 0.05, 7)


def mix(*parts, length=None):
    n = length or max(len(p) + int(o * SR) for p, o in parts)
    out = np.zeros(n)
    for p, o in parts:
        o = int(o * SR)
        out[o:o + len(p)] += p[:max(0, n - o)]
    return out


def reverb(x, amount=0.18, size=0.25):
    n = int(SR * size)
    ir = rng.uniform(-1, 1, n) * np.exp(-6 * np.linspace(0, 1, n))
    ir = fft_filter(ir, 300, 5000)
    ir[0] = 0
    wet = np.convolve(np.pad(x, (0, n)), ir / (np.abs(ir).sum() ** 0.5 + 1e-9))[: len(x) + n]
    out = np.pad(x, (0, n)) + amount * wet / (np.max(np.abs(wet)) or 1) * (np.max(np.abs(x)) or 1)
    return out


def save(name, x, vol=0.8, verb=0.0):
    if verb: x = reverb(x, verb)
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) or 1) * vol
    fi, fo = int(SR * 0.0006), int(SR * 0.006)
    x[:fi] *= np.linspace(0, 1, fi); x[-fo:] *= np.linspace(1, 0, fo)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())


C5, D5, E5, G5, A5, C6, E6, G6, C7 = 523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1318.5, 1568.0, 2093.0

# ---- UI
save('tap', mix((click(0.035, 1500, 7000, 0.6, 10), 0), (marimba(1200, 0.06, 12, 0.5), 0)), 0.5)
save('chip', mix((click(0.03, 1800, 8000, 0.9, 8), 0), (click(0.03, 1200, 6000, 0.7, 8), 0.045), (marimba(2100, 0.08, 14, 0.25), 0.01)), 0.65, 0.08)
save('error', mix((pluck(196, 0.16, 6, 0.9), 0), (pluck(155, 0.26, 5, 0.9), 0.1)), 0.55, 0.1)
save('coin', mix((bell(1568, 0.1, 6, 0.8, 0.9), 0), (bell(2093, 0.5, 4, 1.0), 0.07)), 0.7, 0.15)

# ---- slots / wheel
whirr = noise(0.6, 400, 3500) * adsr(int(SR * 0.6), 0.04, 0.2) * (0.6 + 0.4 * np.sin(2 * np.pi * 22 * t(0.6)))
save('spin', mix((whirr, 0), (sweep(200, 520, 0.6, 0.18, 1.5), 0)), 0.6, 0.06)
save('reel_stop', mix((thud(130, 0.14, 1.0), 0), (click(0.04, 600, 4000, 0.7, 9), 0)), 0.8, 0.05)
save('win', mix(*[(marimba(f, 0.34, 5.5, 0.9), i * 0.085) for i, f in enumerate([C5, E5, G5, C6])],
                *[(bell(f, 0.6, 4.5, 0.7, 0.45), 0.34 + i * 0.03) for i, f in enumerate([C6, E6])]), 0.8, 0.2)
fan = [(bell(f, 0.9, 3.0, 0.8, 0.8), i * 0.075) for i, f in enumerate([C5, E5, G5, C6, E6, G6, C7])]
chord = [(bell(f, 1.3, 2.5, 0.5, 0.55), 0.55) for f in (C6, E6, G6)]
shower = [(bell(2400 + 600 * ((i * 7) % 5), 0.12, 8, 0.8, 0.35), 0.5 + i * 0.065) for i in range(12)]
save('big_win', mix(*fan, *chord, *shower), 0.88, 0.25)
save('lose', mix((pluck(262, 0.24, 6, 0.8), 0), (pluck(220, 0.32, 6, 0.8), 0.14), (pluck(175, 0.5, 5, 0.8), 0.3)), 0.5, 0.18)

# ---- cards
swish = noise(0.11, 1500, 9000) * np.linspace(0.2, 1, int(SR * 0.11)) ** 0.5 * adsr(int(SR * 0.11), 0.01, 0.05)
save('card', mix((swish, 0), (click(0.02, 900, 5000, 0.5, 9), 0.095)), 0.65, 0.05)
save('card_flip', mix((noise(0.07, 2500, 9000) * adsr(int(SR * 0.07), 0.004, 0.04), 0), (click(0.02, 1200, 6000, 0.6, 9), 0.06)), 0.65, 0.05)
save('blackjack', mix(*[(bell(f, 0.7, 3.5, 0.8, 0.8), i * 0.065) for i, f in enumerate([E5, A5, 1108.7, E6])], (bell(E6, 1.0, 3, 0.6, 0.5), 0.3)), 0.85, 0.22)

# ---- dice
hits = []
for i in range(11):
    gap = 0.045 + 0.017 * i
    hits.append((mix((click(0.03, 300, 3500, 0.95 - i * 0.07, 7), 0), (thud(160 - i * 6, 0.05, 0.4), 0)), sum(0.045 + 0.017 * j for j in range(i))))
save('dice_roll', mix(*hits, length=int(SR * 1.2)), 0.8, 0.07)

# ---- roulette
ticks = [(mix((click(0.02, 2200, 9000, 0.8, 9), 0), (marimba(2300, 0.03, 18, 0.35), 0)), 0.055 * i + 0.0025 * i * i) for i in range(20)]
save('roulette_spin', mix(*ticks, (noise(1.6, 200, 2200) * adsr(int(SR * 1.6), 0.15, 0.6) * 0.25, 0), length=int(SR * 1.9)), 0.7, 0.1)
save('ball_drop', mix((marimba(1500, 0.1, 10, 0.9), 0), (marimba(1100, 0.1, 10, 0.8), 0.075), (marimba(1800, 0.08, 12, 0.7), 0.14)), 0.7, 0.12)

# ---- crash / climb
save('crash_start', mix((noise(0.6, 300, 4500) * adsr(int(SR * 0.6), 0.25, 0.2) * 0.6, 0), (sweep(180, 720, 0.6, 0.5, 2.0), 0)), 0.6, 0.08)
save('crash_tick', mix((marimba(1500, 0.05, 14, 0.8), 0), (click(0.01, 3000, 9000, 0.3, 8), 0)), 0.4)
save('cash_out', mix((bell(988, 0.2, 5, 0.9, 0.9), 0), (bell(1319, 0.2, 5, 0.9, 0.9), 0.08), (bell(1760, 0.8, 3.5, 1.0, 1.0), 0.16),
                     *[(click(0.02, 3000, 9000, 0.4, 8), 0.3 + i * 0.05) for i in range(4)]), 0.85, 0.22)
save('bust', mix((thud(70, 0.5, 1.0), 0), (noise(0.55, 60, 900) * adsr(int(SR * 0.55), 0.005, 0.4, 5) * 0.8, 0), (sweep(420, 55, 0.5, 0.5, 0.5), 0)), 0.9, 0.12)
print('ok', sorted(f for f in os.listdir(OUT) if not f.startswith('music')))
