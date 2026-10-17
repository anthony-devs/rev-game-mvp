"""Generates one background loop per game: assets/sounds/music_<game>.wav
Run:  python3 tools/make_music.py   (needs numpy)
Synthesized (no licensing). Every loop is a whole number of bars and its tail
wraps onto the start, so it repeats without a click."""
import numpy as np, wave, os

SR = 16000
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds')
rng = np.random.default_rng(11)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

class Track:
    def __init__(self, bpm, bars, beats=4):
        self.spb = 60.0 / bpm
        self.n = int(round(SR * self.spb * beats * bars))
        self.buf = np.zeros(self.n + SR * 3)   # room for tails
    def add(self, x, beat, vol=1.0):
        i = int(round(beat * self.spb * SR))
        if i >= self.n: return
        self.buf[i:i + len(x)] += x * vol
    def done(self, vol):
        out = self.buf[:self.n].copy()
        tail = self.buf[self.n:]
        out[:min(len(tail), self.n)] += tail[:self.n]   # wrap tails -> seamless loop
        out = np.tanh(out * 1.1)
        r = np.linspace(0, 1, 240); out[:240] *= r; out[-240:] *= r[::-1]   # 15 ms ramps: no click at the loop point
        out = out / (np.max(np.abs(out)) or 1) * vol
        return out

def tt(d): return np.arange(int(SR * d)) / SR
def adsr(x, a=0.005, k=4.0):
    n = len(x); e = np.exp(-k * np.arange(n) / n); na = max(1, int(SR * a)); e[:na] *= np.linspace(0, 1, na); return x * e
def ep(m, d=1.2, k=3.5):      # soft electric piano
    f = hz(m); t = tt(d)
    return adsr(np.sin(2*np.pi*f*t) + .35*np.sin(2*np.pi*2*f*t)*np.exp(-6*t) + .12*np.sin(2*np.pi*4*f*t)*np.exp(-12*t), .004, k)
def pluck(m, d=.5, k=6.0):
    f = hz(m); t = tt(d)
    return adsr(np.sin(2*np.pi*f*t) + .5*np.sin(2*np.pi*2*f*t) + .25*np.sin(2*np.pi*3*f*t), .002, k)
def bass(m, d=.6, k=3.0):
    f = hz(m); t = tt(d)
    return adsr(np.sin(2*np.pi*f*t) + .25*np.sin(2*np.pi*2*f*t), .006, k)
def pad(m, d, vol=1.0):
    f = hz(m); t = tt(d)
    x = np.sin(2*np.pi*f*t) + np.sin(2*np.pi*f*1.004*t) * .8
    n = len(x); e = np.minimum(1, np.minimum(np.arange(n) / (SR*.4), (n - np.arange(n)) / (SR*.5)))
    return x * e * vol
def hat(d=.04, vol=.5):
    x = rng.uniform(-1, 1, int(SR*d)); x = np.diff(x, prepend=0)
    return x * np.exp(-9 * np.arange(len(x)) / len(x)) * vol
def kick(d=.16):
    t = tt(d); f = 110 * np.exp(-t * 22) + 45
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-t * 18)
def brush(d=.25, vol=.25):
    x = rng.uniform(-1, 1, int(SR*d)); x = np.convolve(x, np.ones(4)/4, 'same')
    n = len(x); return x * np.minimum(1, np.arange(n)/(SR*.03)) * np.exp(-5*np.arange(n)/n) * vol

def save(name, x):
    with wave.open(os.path.join(OUT, f'music_{name}.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype('<i2').tobytes())

# chords as MIDI note lists
def slots():   # bright, playful, C major, 124 bpm, 8 bars
    T = Track(124, 8)
    prog = [([48,55,60,64],48),([45,57,60,64],45),([41,53,57,60],41),([43,55,59,62],43)]*2
    for b, (ch, root) in enumerate(prog):
        s = b * 4
        for i in range(8):                       # eighth-note arpeggio
            T.add(pluck(ch[i % 4] + 12, .45, 7), s + i * .5, .5)
        T.add(bass(root - 12, .9), s, .9); T.add(bass(root - 12, .6), s + 2, .7)
        for i in range(8): T.add(hat(), s + i * .5 + .25, .22)
    return T.done(.8)

def roulette():  # lounge, slow, Am9 Dm9 G13 Cmaj9 at 78 bpm, 8 bars
    T = Track(78, 8)
    prog = [[57,64,67,71,74],[50,57,65,69,72],[55,62,65,69,76],[48,59,64,67,71]]*2
    roots = [45,38,43,36]*2
    for b, ch in enumerate(prog):
        s = b * 4
        for m in ch: T.add(ep(m, 3.8, 1.6), s, .28)
        for i, st in enumerate([0, 1.5, 2.5, 3.5]): T.add(bass(roots[b], .7, 4), s + st, .8 if i == 0 else .5)
        for i in range(4): T.add(brush(), s + i, .5 if i % 2 else .8)
        T.add(ep(ch[-1] + 12, .9, 5), s + 2.5, .22)
    return T.done(.75)

def blackjack():  # smooth swing, 100 bpm, Cm7 F7 Bbmaj7 Ebmaj7 -> walking bass, 8 bars
    T = Track(100, 8)
    chords = [[60,63,67,70],[60,65,69,63],[58,62,65,69],[63,67,70,74]]*2
    walk = [[36,39,41,43],[41,43,44,45],[34,36,38,40],[39,41,43,44]]*2
    for b, ch in enumerate(chords):
        s = b * 4
        for i in range(4): T.add(bass(walk[b][i], .55, 4), s + i, .85)
        for st in (0.67, 2.67): 
            for m in ch: T.add(ep(m, .6, 5), s + st, .2)
        for i in range(4):                       # ride, swung
            T.add(hat(.07, .5), s + i, .22); T.add(hat(.05, .4), s + i + .67, .16)
    return T.done(.75)

def dice():  # light electronic, 112 bpm, Dm, 8 bars
    T = Track(112, 8)
    notes = [62,65,69,65,62,65,72,69]
    for b in range(8):
        s = b * 4
        for i in range(4): T.add(kick(), s + i, .55)
        for i in range(8): T.add(hat(), s + i * .5 + .25, .18)
        for i in range(8): T.add(pluck(notes[(i + b) % 8] + (12 if b % 2 else 0), .3, 8), s + i * .5, .38)
        T.add(bass([38,38,34,36][b % 4], 1.8, 2.2), s, .8)
        T.add(pad([62,62,58,60][b % 4] - 12, 3.8, .12), s, 1)
    return T.done(.75)

def crash():  # tense, 132 bpm, E minor pulse, rising arp, 8 bars
    T = Track(132, 8)
    for b in range(8):
        s = b * 4
        for i in range(8): T.add(bass([40,40,40,43,40,40,38,38][b] , .22, 7), s + i * .5, .55)
        for i in range(4): T.add(kick(), s + i, .45)
        for i in range(16): T.add(pluck(64 + [0,3,7,10,12,10,7,3][i % 8] + (b // 4) * 2, .2, 9), s + i * .25, .12 + .02 * b)
        for i in range(8): T.add(hat(.03, .4), s + i * .5 + .25, .15)
        T.add(pad(52, 3.8, .1), s, 1)
    return T.done(.75)

for name, fn in [('slots', slots), ('roulette', roulette), ('blackjack', blackjack), ('dice', dice), ('crash', crash)]:
    save(name, fn())
print('ok', sorted(f for f in os.listdir(OUT) if f.startswith('music_')))
