"""Sound effects and music, synthesised from nothing: python tools/audio/gen_audio.py

Writes 16-bit mono WAVs to elementalist/assets/audio/sfx/ and /music/. Standard library only (wave,
math, random), seeded so every run makes identical files. The sounds are chip-tune flavoured on
purpose: short envelopes, square/triangle/saw voices, filtered noise for impacts.

SFX names match what the game asks Sfx for (Sfx.play("hit") loads hit.wav, hit_2.wav, hit_3.wav ...
as random variations). Music tracks are exact bar counts so they loop without a click.
"""
import math
import os
import random
import struct
import wave

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'elementalist', 'assets', 'audio')
SFX_DIR = os.path.join(ROOT, 'sfx')
MUSIC_DIR = os.path.join(ROOT, 'music')
os.makedirs(SFX_DIR, exist_ok=True)
os.makedirs(MUSIC_DIR, exist_ok=True)

SR = 22050
MUSIC_SR = 16000
TAU = math.tau


# ------------------------------------------------------------------------------------------ DSP
def osc(kind, phase):
    p = phase % 1.0
    if kind == 'sine':
        return math.sin(TAU * p)
    if kind == 'square':
        return 1.0 if p < 0.5 else -1.0
    if kind == 'pulse':
        return 1.0 if p < 0.25 else -1.0
    if kind == 'saw':
        return 2.0 * p - 1.0
    if kind == 'tri':
        return 4.0 * abs(p - 0.5) - 1.0
    return 0.0


def adsr(i, n, a, d, s, r):
    """Envelope value at sample i of n (times in samples; s is the sustain level 0..1)."""
    if i < a:
        return i / max(a, 1)
    if i < a + d:
        return 1.0 - (1.0 - s) * (i - a) / max(d, 1)
    if i > n - r:
        return s * max(0.0, (n - i) / max(r, 1))
    return s


def tone(freq, dur, kind='square', vol=0.5, a=0.004, d=0.05, s=0.6, r=0.05, slide=0.0, vib=0.0, sr=SR):
    """One note. `slide` is the total pitch change in octaves over the note; `vib` a vibrato depth in Hz."""
    n = int(dur * sr)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / sr
        f = freq * (2.0 ** (slide * i / max(n, 1))) + (vib * math.sin(TAU * 6.0 * t) if vib else 0.0)
        phase += f / sr
        out.append(osc(kind, phase) * vol * adsr(i, n, int(a * sr), int(d * sr), s, int(r * sr)))
    return out


def noise(dur, vol=0.5, a=0.002, d=0.05, s=0.3, r=0.05, lp=1.0, seed=1, sr=SR, slide_lp=0.0):
    """White noise through a one-pole low-pass (lp 0..1, higher = brighter), optionally sweeping."""
    rnd = random.Random(seed)
    n = int(dur * sr)
    out = []
    y = 0.0
    for i in range(n):
        cutoff = min(1.0, max(0.01, lp + slide_lp * i / max(n, 1)))
        y += cutoff * (rnd.uniform(-1, 1) - y)
        out.append(y * vol * adsr(i, n, int(a * sr), int(d * sr), s, int(r * sr)))
    return out


def mix(*tracks, length=None):
    n = length or max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t[:n]):
            out[i] += v
    return out


def place(buf, samples, start, gain=1.0):
    """Add `samples` into `buf` at sample offset `start`."""
    for i, v in enumerate(samples):
        j = start + i
        if 0 <= j < len(buf):
            buf[j] += v * gain


def fade(samples, ms=4, sr=SR):
    n = min(len(samples) // 2, int(ms / 1000 * sr))
    for i in range(n):
        samples[i] *= i / n
        samples[-1 - i] *= i / n
    return samples


def write(path, samples, sr=SR, peak=0.9):
    top = max(1e-6, max(abs(v) for v in samples))
    scale = min(1.0, peak / top) if top > peak else 1.0
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1.0, min(1.0, v * scale)) * 32767)) for v in samples))


def note(name):
    """'A4' -> Hz."""
    names = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
    base = names[name[0]]
    idx = 1
    if name[1] == '#':
        base += 1
        idx = 2
    elif name[1] == 'b':
        base -= 1
        idx = 2
    octave = int(name[idx:])
    return 440.0 * 2.0 ** ((base + 12 * (octave + 1) - 69) / 12.0)


def sfx(name, samples):
    write(os.path.join(SFX_DIR, name + '.wav'), fade(samples))


# ------------------------------------------------------------------------------------------ SFX
def make_sfx():
    # interface
    sfx('ui_tick', tone(1400, 0.035, 'square', 0.22, d=0.02, s=0.2, r=0.01))
    sfx('ui_click', mix(tone(660, 0.05, 'square', 0.25, s=0.3, r=0.02),
                        [0.0] * int(0.04 * SR) + tone(990, 0.07, 'square', 0.25, s=0.3, r=0.03)))
    sfx('ui_back', mix(tone(660, 0.05, 'square', 0.22, s=0.3, r=0.02), [0.0] * int(0.04 * SR) + tone(440, 0.07, 'square', 0.22, s=0.3, r=0.03)))
    sfx('error', tone(130, 0.18, 'saw', 0.3, s=0.7, r=0.06, slide=-0.3))

    # combat
    for k in range(3):
        sfx('hit' if k == 0 else 'hit_%d' % (k + 1),
            mix(noise(0.09, 0.7, a=0.001, d=0.04, s=0.1, r=0.04, lp=0.5 + 0.1 * k, seed=10 + k),
                tone(140 - 12 * k, 0.1, 'tri', 0.6, a=0.001, d=0.06, s=0.1, r=0.04, slide=-0.6)))
    for k in range(2):
        sfx('slash' if k == 0 else 'slash_2', noise(0.16, 0.5, a=0.01, d=0.06, s=0.4, r=0.08, lp=0.12, seed=30 + k, slide_lp=0.5))
    sfx('dodge', noise(0.2, 0.4, a=0.02, d=0.08, s=0.3, r=0.1, lp=0.08, seed=40, slide_lp=0.3))
    sfx('spin', noise(0.3, 0.45, a=0.03, d=0.1, s=0.5, r=0.12, lp=0.15, seed=41, slide_lp=0.4))
    sfx('enemy_hurt', tone(520, 0.1, 'square', 0.3, d=0.04, s=0.3, r=0.04, slide=-0.5))
    sfx('enemy_die', mix(tone(420, 0.28, 'square', 0.35, d=0.1, s=0.4, r=0.1, slide=-1.4),
                         noise(0.2, 0.35, d=0.1, s=0.2, r=0.08, lp=0.4, seed=50)))
    sfx('player_hurt', mix(tone(180, 0.2, 'saw', 0.5, d=0.08, s=0.4, r=0.08, slide=-0.6), noise(0.12, 0.5, d=0.05, s=0.2, lp=0.35, seed=51)))
    sfx('player_die', mix(tone(300, 0.9, 'saw', 0.4, a=0.01, d=0.3, s=0.5, r=0.4, slide=-2.2, vib=4.0),
                          noise(0.5, 0.25, d=0.2, s=0.3, r=0.2, lp=0.2, seed=52)))
    sfx('slam', mix(tone(70, 0.45, 'tri', 0.8, a=0.002, d=0.2, s=0.3, r=0.2, slide=-0.8), noise(0.35, 0.6, a=0.001, d=0.15, s=0.2, r=0.15, lp=0.25, seed=53)))
    sfx('boss_roar', mix(tone(95, 0.9, 'saw', 0.5, a=0.08, d=0.3, s=0.6, r=0.3, slide=-0.4, vib=14.0), noise(0.9, 0.3, a=0.1, d=0.3, s=0.5, r=0.3, lp=0.12, seed=54)))
    sfx('enrage', mix(tone(110, 0.7, 'saw', 0.5, a=0.05, d=0.2, s=0.7, r=0.25, slide=0.6, vib=20.0), noise(0.5, 0.3, lp=0.3, seed=55)))
    sfx('telegraph', tone(300, 0.25, 'tri', 0.25, a=0.02, d=0.05, s=0.6, r=0.1, slide=0.8))

    # elements: one cast sound each
    sfx('cast_fire', mix(noise(0.3, 0.45, a=0.01, d=0.1, s=0.5, r=0.15, lp=0.35, seed=60, slide_lp=0.3), tone(200, 0.28, 'saw', 0.25, s=0.5, slide=0.5)))
    bubbles = [0.0] * int(0.4 * SR)
    for i, f in enumerate((500, 700, 620, 880)):
        place(bubbles, tone(f, 0.08, 'sine', 0.4, d=0.04, s=0.3, r=0.03, slide=0.4), int(i * 0.07 * SR))
    sfx('cast_water', bubbles)
    sfx('cast_earth', mix(tone(80, 0.3, 'tri', 0.7, a=0.003, d=0.12, s=0.4, r=0.1, slide=-0.3), noise(0.25, 0.4, d=0.1, s=0.3, lp=0.2, seed=62)))
    sfx('cast_air', noise(0.28, 0.5, a=0.04, d=0.08, s=0.5, r=0.12, lp=0.1, seed=63, slide_lp=0.35))
    sfx('cast_mineral', mix(tone(1320, 0.3, 'sine', 0.4, d=0.1, s=0.4, r=0.15), tone(1980, 0.22, 'sine', 0.25, d=0.08, s=0.3, r=0.12), noise(0.05, 0.4, lp=0.8, seed=64)))
    chime = [0.0] * int(0.6 * SR)
    for i, f in enumerate((880, 1318, 1760)):
        place(chime, tone(f, 0.4, 'sine', 0.3, a=0.002, d=0.15, s=0.3, r=0.2), int(i * 0.06 * SR))
    sfx('cast_light', chime)
    sfx('cast_dark', mix(tone(70, 0.55, 'saw', 0.4, a=0.12, d=0.2, s=0.5, r=0.2, slide=0.3, vib=3.0), tone(73, 0.55, 'saw', 0.3, a=0.12, d=0.2, s=0.5, r=0.2, slide=0.3)))
    sfx('cast_martial', mix(noise(0.1, 0.5, a=0.001, d=0.04, s=0.2, lp=0.7, seed=66), tone(900, 0.08, 'square', 0.2, d=0.03, s=0.2, slide=-0.5)))
    sfx('explode', mix(noise(0.5, 0.7, a=0.002, d=0.2, s=0.3, r=0.2, lp=0.3, seed=67), tone(60, 0.5, 'tri', 0.7, d=0.2, s=0.3, r=0.2, slide=-0.6)))
    spark = [0.0] * int(0.5 * SR)
    for i, f in enumerate((1200, 1600, 2000, 2600)):
        place(spark, tone(f, 0.12, 'sine', 0.25, d=0.05, s=0.3, r=0.05), int(i * 0.05 * SR))
    sfx('combo', spark)
    buff = [0.0] * int(0.55 * SR)
    for i, f in enumerate((392, 494, 587, 784)):
        place(buff, tone(f, 0.2, 'tri', 0.3, d=0.08, s=0.5, r=0.1), int(i * 0.07 * SR))
    sfx('buff', buff)

    # world
    sfx('pickup_gold', mix(tone(1568, 0.07, 'square', 0.25, s=0.4, r=0.03), [0.0] * int(0.06 * SR) + tone(2093, 0.14, 'square', 0.25, s=0.4, r=0.08)))
    sfx('pickup_item', mix(tone(660, 0.1, 'tri', 0.35, s=0.5, r=0.05), [0.0] * int(0.08 * SR) + tone(880, 0.16, 'tri', 0.35, s=0.5, r=0.09)))
    sfx('pickup_gem', mix(tone(1047, 0.35, 'sine', 0.35, d=0.12, s=0.4, r=0.18), tone(1568, 0.3, 'sine', 0.25, d=0.1, s=0.3, r=0.15)))
    arp = [0.0] * int(0.8 * SR)
    for i, f in enumerate((523, 659, 784, 1047)):
        place(arp, tone(f, 0.22, 'square', 0.28, d=0.08, s=0.5, r=0.12), int(i * 0.1 * SR))
    sfx('level_up', arp)
    fan = [0.0] * int(1.2 * SR)
    for i, f in enumerate((392, 523, 659, 784, 1047)):
        place(fan, tone(f, 0.4, 'tri', 0.3, d=0.1, s=0.6, r=0.2), int(i * 0.12 * SR))
        place(fan, tone(f * 2, 0.3, 'sine', 0.12, d=0.1, s=0.5, r=0.15), int(i * 0.12 * SR))
    sfx('reward', fan)
    sfx('door_open', mix(tone(60, 0.5, 'saw', 0.45, a=0.05, d=0.2, s=0.6, r=0.2, slide=0.3), noise(0.5, 0.4, a=0.05, d=0.2, s=0.5, r=0.2, lp=0.1, seed=70)))
    sfx('door_locked', mix(tone(110, 0.2, 'square', 0.4, d=0.06, s=0.3, r=0.08, slide=-0.4), noise(0.08, 0.5, lp=0.5, seed=71)))
    sfx('chest_open', mix(tone(180, 0.3, 'saw', 0.3, a=0.03, d=0.1, s=0.5, r=0.1, slide=0.5, vib=8.0), [0.0] * int(0.18 * SR) + tone(1320, 0.35, 'sine', 0.3, d=0.1, s=0.4, r=0.2)))
    sfx('forge', mix(noise(0.08, 0.7, a=0.001, d=0.03, s=0.1, lp=0.8, seed=72), tone(1200, 0.5, 'sine', 0.4, a=0.001, d=0.2, s=0.3, r=0.25), tone(1810, 0.4, 'sine', 0.2, a=0.001, d=0.15, s=0.2, r=0.2)))
    sfx('equip', mix(noise(0.07, 0.5, a=0.001, d=0.03, s=0.1, lp=0.6, seed=73), tone(500, 0.08, 'tri', 0.3, s=0.3)))
    sfx('save', mix(tone(784, 0.12, 'tri', 0.28, s=0.5, r=0.06), [0.0] * int(0.1 * SR) + tone(1047, 0.22, 'tri', 0.28, s=0.5, r=0.12)))


# ---------------------------------------------------------------------------------------- music
def render_track(sr, bpm, bars, parts):
    """parts: list of (voice-kind, gain, [(beat, 'A4' or None, beats_long), ...]) over `bars` 4/4 bars.
    Drums: a 'kick'/'hat'/'snare' part lists (beat, None, 0) hits."""
    beat = 60.0 / bpm
    total = int(bars * 4 * beat * sr)
    buf = [0.0] * total
    for kind, gain, events in parts:
        for b, name, length in events:
            start = int(b * beat * sr)
            if kind == 'kick':
                place(buf, tone(110, 0.16, 'sine', 0.9, a=0.001, d=0.08, s=0.2, r=0.06, slide=-1.8, sr=sr), start, gain)
            elif kind == 'snare':
                place(buf, noise(0.14, 0.7, a=0.001, d=0.06, s=0.2, r=0.06, lp=0.6, seed=start & 0xff, sr=sr), start, gain)
            elif kind == 'hat':
                place(buf, noise(0.04, 0.5, a=0.001, d=0.02, s=0.1, r=0.015, lp=0.95, seed=(start * 7) & 0xff, sr=sr), start, gain)
            elif name is not None:
                voice, a_, d_, s_, r_ = {
                    'bass': ('tri', 0.005, 0.1, 0.7, 0.08), 'pad': ('saw', 0.25, 0.3, 0.7, 0.4),
                    'lead': ('square', 0.01, 0.1, 0.5, 0.12), 'pluck': ('pulse', 0.003, 0.18, 0.15, 0.1),
                    'bell': ('sine', 0.002, 0.3, 0.2, 0.4), 'arp': ('square', 0.002, 0.07, 0.3, 0.05),
                }[kind]
                dur = max(0.05, length * beat)
                place(buf, tone(note(name), dur, voice, 0.5, a=a_, d=d_, s=s_, r=min(r_, dur * 0.6), vib=2.0 if kind == 'lead' else 0.0, sr=sr), start, gain)
    # a soft one-pole low-pass on the whole mix to take the edge off the square waves
    y = 0.0
    for i in range(total):
        y += 0.55 * (buf[i] - y)
        buf[i] = y
    return buf


def chord_notes(root, kind, octave):
    steps = {'min': (0, 3, 7), 'maj': (0, 4, 7), 'dim': (0, 3, 6), 'min7': (0, 3, 7, 10), 'sus': (0, 5, 7)}[kind]
    names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    base = names.index(root)
    out = []
    for s in steps:
        idx = base + s
        out.append('%s%d' % (names[idx % 12], octave + idx // 12))
    return out


def song(sr, bpm, progression, bars_per_chord=1, arp_every=0.5, lead_pattern=None, drums='none', bass_pattern='root', pad=True, bell=False, seed=1):
    """A looping song from a chord progression: bass, pad, arpeggio, optional lead and drums."""
    rnd = random.Random(seed)
    bars = len(progression) * bars_per_chord
    parts = {'bass': [], 'pad': [], 'arp': [], 'lead': [], 'kick': [], 'snare': [], 'hat': [], 'bell': []}
    for ci, (root, kind) in enumerate(progression):
        b0 = ci * bars_per_chord * 4
        length = bars_per_chord * 4
        low = chord_notes(root, kind, 2)
        mid = chord_notes(root, kind, 4)
        parts['bass'].append((b0, low[0], length if bass_pattern == 'hold' else 0.9))
        if bass_pattern == 'drive':
            for k in range(int(length * 2)):
                parts['bass'].append((b0 + k * 0.5, low[0] if k % 4 != 3 else low[2], 0.45))
        elif bass_pattern == 'root':
            for k in range(1, int(length)):
                parts['bass'].append((b0 + k, low[0] if k % 2 == 0 else low[2], 0.9))
        if pad:
            for n in chord_notes(root, kind, 3):
                parts['pad'].append((b0, n, length))
        if arp_every:
            steps = int(length / arp_every)
            for k in range(steps):
                parts['arp'].append((b0 + k * arp_every, mid[(k * 2 + (k // 4)) % len(mid)] if rnd.random() > 0.08 else mid[-1], arp_every * 0.9))
        if bell:
            parts['bell'].append((b0, mid[-1], 3.5))
        if lead_pattern:
            for off, idx, ln in lead_pattern[ci % len(lead_pattern)]:
                parts['lead'].append((b0 + off, chord_notes(root, kind, 5)[idx % len(mid)], ln))
        if drums != 'none':
            for k in range(int(length)):
                parts['kick'].append((b0 + k, None, 0)) if (k % 4 in (0, 2) if drums == 'drive' else k % 4 == 0) else None
                if k % 4 in (1, 3) and drums == 'drive':
                    parts['snare'].append((b0 + k, None, 0))
                parts['hat'].append((b0 + k + 0.5, None, 0))
    gains = {'bass': 0.5, 'pad': 0.16, 'arp': 0.17, 'lead': 0.2, 'kick': 0.55, 'snare': 0.3, 'hat': 0.16, 'bell': 0.2}
    return render_track(sr, bpm, bars, [(k, gains[k], v) for k, v in parts.items() if v])


def make_music():
    tracks = {
        # slow, wistful: the title screen
        'menu': song(MUSIC_SR, 72, [('A', 'min'), ('F', 'maj'), ('C', 'maj'), ('G', 'maj')] * 2, arp_every=1.0, bell=True,
                     lead_pattern=[[(0, 2, 2.0), (2, 1, 2.0)], [(0, 0, 2.0), (2, 2, 2.0)]], bass_pattern='hold', seed=2),
        # warm and gentle: the camp
        'camp': song(MUSIC_SR, 88, [('C', 'maj'), ('A', 'min'), ('F', 'maj'), ('G', 'maj')] * 2, arp_every=0.5,
                     lead_pattern=[[(0, 2, 1.0), (1, 1, 1.0), (2, 0, 2.0)], [(0, 1, 1.0), (1, 2, 1.0), (2, 1, 2.0)]], drums='soft', seed=3),
        # tense: the Ashen Vaults
        'vault': song(MUSIC_SR, 100, [('D', 'min'), ('D', 'min'), ('A#', 'maj'), ('A', 'sus')] * 2, arp_every=0.5,
                      lead_pattern=[[(0, 0, 1.5), (2, 2, 1.5)], [(1, 1, 1.0)], [(0, 2, 2.0)], [(2, 1, 2.0)]], drums='soft', bass_pattern='root', seed=4),
        # low and drowned: the Crypts
        'crypt': song(MUSIC_SR, 84, [('E', 'min'), ('C', 'maj'), ('B', 'sus'), ('E', 'dim')] * 2, arp_every=0.75,
                      lead_pattern=[[(0, 2, 3.0)], [(1, 0, 2.0)]], drums='soft', bass_pattern='hold', bell=True, seed=5),
        # driving: boss fights
        'boss': song(MUSIC_SR, 140, [('E', 'min'), ('E', 'min'), ('C', 'maj'), ('D', 'maj'), ('E', 'min'), ('G', 'maj'), ('A', 'min'), ('B', 'sus')], arp_every=0.25,
                     lead_pattern=[[(0, 2, 0.75), (1, 1, 0.75), (2, 0, 0.5), (3, 1, 0.5)], [(0, 1, 0.75), (1, 2, 0.75), (2, 1, 1.0)]],
                     drums='drive', bass_pattern='drive', seed=6),
    }
    for name, samples in tracks.items():
        write(os.path.join(MUSIC_DIR, name + '.wav'), samples, MUSIC_SR, peak=0.8)
        print('music', name, round(len(samples) / MUSIC_SR, 1), 's')


if __name__ == '__main__':
    make_sfx()
    print('sfx ->', len(os.listdir(SFX_DIR)), 'files')
    make_music()
