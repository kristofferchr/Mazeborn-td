#!/usr/bin/env python3
"""Synthesizes all of Mazeborn TD's sound effects and the two music layers.

Usage: scripts/make_sfx.py [out-dir]        (default: game/assets/audio)
       scripts/make_sfx.py --only fire_ice  (one sound, for tweaking)

Everything is made here from sine waves and noise (sfxr-style), so the audio is
our own work and CC0 like the rest of the assets. Deterministic: every sound has
a fixed seed. Mono, 22.05 kHz. Encodes to OGG Vorbis with ffmpeg (libvorbis)
when it is installed, otherwise writes 16-bit WAV. Needs numpy.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import wave
import zlib

import numpy as np

SR = 22050
SOUNDS = {}  # name -> function returning a float array
MUSIC_BPM = 84
MUSIC_BARS = 16


def sound(fn):
    SOUNDS[fn.__name__] = fn
    return fn


# --- Building blocks -----------------------------------------------------------


def rng_for(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


def times(dur):
    return np.arange(int(dur * SR)) / SR


def silence(dur):
    return np.zeros(int(dur * SR))


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def phase_of(freq):
    """Phase of a signal whose frequency changes per sample (array or scalar)."""
    return 2.0 * np.pi * np.cumsum(freq) / SR


def sweep(f0, f1, dur, curve=1.0):
    """Exponential frequency sweep from f0 to f1 (Hz) over dur seconds."""
    x = np.linspace(0.0, 1.0, int(dur * SR)) ** curve
    return f0 * (f1 / f0) ** x


def decay(dur, tau, attack=0.002):
    t = times(dur)
    env = np.exp(-t / tau)
    if attack > 0:
        env *= np.minimum(t / attack, 1.0)
    return env


def swell(dur, power=1.5):
    t = np.linspace(0.0, 1.0, int(dur * SR))
    return np.sin(np.pi * t) ** power


def noise(rng, dur):
    return rng.uniform(-1.0, 1.0, int(dur * SR))


def spectral(x, gain_fn):
    """Filters x by a magnitude response gain_fn(freqs) in the frequency domain."""
    n = len(x)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(spec * gain_fn(freqs), n)


def lowpass(x, cutoff, order=2):
    return spectral(x, lambda f: 1.0 / np.sqrt(1.0 + (f / cutoff) ** (2 * order)))


def highpass(x, cutoff, order=2):
    return spectral(x, lambda f: 1.0 / np.sqrt(1.0 + (cutoff / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=2):
    return highpass(lowpass(x, hi, order), lo, order)


def sweep_lowpass(x, cutoffs):
    """One-pole low-pass whose cutoff (Hz) changes per sample (short sounds only)."""
    a = 1.0 - np.exp(-2.0 * np.pi * np.asarray(cutoffs) / SR)
    a = np.broadcast_to(a, x.shape)
    out = np.empty_like(x)
    y = 0.0
    for i in range(len(x)):
        y += a[i] * (x[i] - y)
        out[i] = y
    return out


def tone(freq, dur, partials=((1.0, 1.0),), tau=None):
    """Sum of sine partials (ratio, amplitude) on a (possibly sweeping) frequency."""
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = phase_of(f)
    out = np.zeros(n)
    for ratio, amp in partials:
        out += amp * np.sin(ph * ratio)
    if tau is not None:
        out *= decay(dur, tau)
    return out


def bell(freq, dur, tau=0.4, bright=1.0):
    """Struck metal: inharmonic partials, the high ones die first."""
    out = np.zeros(int(dur * SR))
    for ratio, amp in ((1.0, 1.0), (2.0, 0.5 * bright), (2.76, 0.35 * bright), (5.4, 0.2 * bright)):
        out += amp * tone(freq * ratio, dur, tau=tau / (1.0 + 0.6 * (ratio - 1.0)))
    return out


def pluck(freq, dur, tau=0.6, harmonics=8, bright=0.7):
    """Harp or string pluck: harmonics with faster decay the higher they are."""
    t = times(dur)
    out = np.zeros(len(t))
    for k in range(1, harmonics + 1):
        if freq * k > SR / 2.2:
            break
        amp = (1.0 / k ** 1.3) * (bright ** (k - 1))
        out += amp * np.sin(2.0 * np.pi * freq * k * t) * np.exp(-t * k * 1.4 / tau)
    return out * np.minimum(t / 0.003, 1.0)


def brass(freq, dur, attack=0.12, release=0.25, bright=6.0, vibrato=0.006, scoop=0.03):
    """Horn: harmonic series whose brightness follows the envelope, with a scoop up
    into the note and a delayed vibrato."""
    t = times(dur)
    n = len(t)
    env = np.minimum(t / attack, 1.0) * np.clip((dur - t) / release, 0.0, 1.0)
    vib = 1.0 + vibrato * np.sin(2.0 * np.pi * 5.2 * t) * np.clip((t - 0.3) / 0.3, 0.0, 1.0)
    bend = 1.0 - scoop * np.exp(-t / 0.05)
    ph = phase_of(freq * vib * bend)
    b = 0.6 + bright * env
    out = np.zeros(n)
    for k in range(1, 24):
        if freq * k > SR / 2.2:
            break
        out += (1.0 / k) * np.exp(-(k - 1) / b) * np.sin(ph * k)
    return out * env


def drum(freq0, freq1, dur, tau, rng, noise_amt=0.3, noise_cut=900.0):
    """Skin drum: a falling sine body and a short filtered noise slap."""
    body = tone(sweep(freq0, freq1, dur, 0.4), dur, ((1.0, 1.0), (1.5, 0.2)), tau=tau)
    slap = lowpass(noise(rng, dur), noise_cut) * decay(dur, tau * 0.25)
    return body + noise_amt * slap / max(np.max(np.abs(slap)), 1e-9)


def place(buf, x, at, gain=1.0, wrap=False):
    """Mixes x into buf starting at `at` seconds; wrap=True folds the overflow to
    the start (seamless loops)."""
    i = int(round(at * SR))
    n = len(buf)
    if wrap:
        idx = (np.arange(len(x)) + i) % n
        np.add.at(buf, idx, x * gain)
    else:
        end = min(i + len(x), n)
        if end > i:
            buf[i:end] += x[: end - i] * gain
    return buf


def mix(dur, *parts):
    """Mixes (at, signal, gain) parts into a buffer of dur seconds."""
    buf = silence(dur)
    for at, x, gain in parts:
        place(buf, x, at, gain)
    return buf


def reverb(x, rng, seconds=1.2, wet=0.25, circular=False, damp=3000.0):
    """Convolution with a decaying noise tail (a cheap hall)."""
    ir = noise(rng, seconds) * np.exp(-times(seconds) / (seconds / 5.0))
    ir = lowpass(ir, damp)
    ir /= np.sqrt(np.sum(ir ** 2))
    if circular:
        n = len(x)
        tail = np.zeros(n)
        tail[: len(ir)] = ir
        wet_sig = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(tail), n)
    else:
        n = len(x) + len(ir)
        wet_sig = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
        x = np.concatenate([x, np.zeros(len(ir))])
    return x + wet * wet_sig


def finish(x, peak_db=-1.0, fade=0.01, trim=True):
    """Normalizes to a peak level, trims trailing silence and fades in (2 ms,
    no click) and out. Loops (trim=False) are left whole."""
    if trim:
        quiet = np.where(np.abs(x) > np.max(np.abs(x)) * 0.002)[0]
        if len(quiet):
            x = x[: quiet[-1] + 1]
    x = x - np.mean(x)
    x = x / max(np.max(np.abs(x)), 1e-9) * 10.0 ** (peak_db / 20.0)
    n = min(int(fade * SR), len(x))
    if n > 0:
        x[-n:] *= np.linspace(1.0, 0.0, n)
    if trim:
        m = min(int(0.002 * SR), len(x))
        x[:m] *= np.linspace(0.0, 1.0, m)
    return x


# --- Building and the UI ------------------------------------------------------


@sound
def build():
    """Hammer knocks on wood and a settling thud."""
    rng = rng_for("build")
    parts = []
    for at, f in ((0.0, 230.0), (0.1, 250.0), (0.2, 190.0)):
        knock = tone(sweep(f * 1.7, f, 0.12, 0.3), 0.12, ((1.0, 1.0), (2.3, 0.3)), tau=0.03)
        click = bandpass(noise(rng, 0.05), 900, 3500) * decay(0.05, 0.008)
        parts += [(at, knock, 0.8), (at, click, 0.6)]
    thud = tone(sweep(120, 60, 0.3), 0.3, tau=0.09) + 0.5 * lowpass(noise(rng, 0.3), 500) * decay(0.3, 0.1)
    parts.append((0.2, thud, 0.9))
    for _ in range(6):
        grain = bandpass(noise(rng, 0.02), 1500, 5000) * decay(0.02, 0.004)
        parts.append((0.24 + rng.uniform(0, 0.25), grain, rng.uniform(0.1, 0.25)))
    return finish(mix(0.6, *parts), -2.0)


@sound
def upgrade():
    """Rising bright arpeggio with a shimmer on top."""
    rng = rng_for("upgrade")
    parts = []
    for i, n in enumerate((72, 76, 79, 84)):
        parts.append((i * 0.07, bell(midi(n), 0.7, tau=0.35 if i < 3 else 0.6), 0.6 if i < 3 else 0.8))
    shimmer = np.zeros(int(0.8 * SR))
    for _ in range(14):
        f = rng.uniform(2500, 5000)
        place(shimmer, tone(f, 0.15, tau=0.05), rng.uniform(0.15, 0.6), rng.uniform(0.05, 0.15))
    parts.append((0.0, shimmer, 1.0))
    return finish(reverb(mix(0.9, *parts), rng, 0.6, 0.2), -2.0)


@sound
def sell():
    """Coins tumbling into a purse, over a soft downward whoosh."""
    rng = rng_for("sell")
    parts = []
    for i, at in enumerate((0.05, 0.13, 0.18, 0.26)):
        f = (2637.0, 1976.0, 2349.0, 1760.0)[i]
        parts.append((at, tone(f, 0.25, ((1.0, 1.0), (2.4, 0.3)), tau=0.06), 0.7 - i * 0.12))
    whoosh = sweep_lowpass(noise(rng, 0.35), sweep(3000, 400, 0.35)) * swell(0.35)
    parts.append((0.0, whoosh, 0.5))
    return finish(mix(0.6, *parts), -3.0)


@sound
def coin():
    """Two quick pings, high and higher."""
    a = tone(midi(83), 0.07, ((1.0, 1.0), (3.0, 0.25)))
    b = tone(midi(88), 0.3, ((1.0, 1.0), (3.0, 0.25)), tau=0.08)
    return finish(mix(0.36, (0.0, a, 0.8), (0.06, b, 1.0)), -3.0)


@sound
def click():
    """Short wooden tick for buttons."""
    rng = rng_for("click")
    tick = tone(sweep(2200, 1500, 0.04), 0.04, tau=0.006)
    snap = bandpass(noise(rng, 0.01), 2000, 8000) * decay(0.01, 0.002)
    return finish(mix(0.05, (0.0, tick, 1.0), (0.0, snap, 0.4)), -4.0)


# --- Towers firing ------------------------------------------------------------


@sound
def fire_arrow():
    """Bowstring twang and the hiss of the arrow."""
    rng = rng_for("fire_arrow")
    string = tone(sweep(520, 300, 0.2, 0.3), 0.2, ((1.0, 1.0), (2.0, 0.5), (3.0, 0.25)), tau=0.05)
    hiss = highpass(noise(rng, 0.2), 2500) * swell(0.2, 2.0)
    return finish(mix(0.25, (0.0, string, 1.0), (0.02, hiss, 0.25)), -2.0)


@sound
def fire_earth():
    """Catapult thump: a creak and a heavy launch."""
    rng = rng_for("fire_earth")
    creak = tone(sweep(150, 110, 0.06), 0.06, ((1.0, 1.0), (2.0, 0.6), (3.0, 0.4))) * decay(0.06, 0.03)
    thump = drum(110, 42, 0.4, 0.12, rng, 0.5, 450)
    return finish(mix(0.45, (0.0, creak, 0.3), (0.04, thump, 1.0)), -1.5)


@sound
def fire_wind():
    """Gust: band of noise that swells and sweeps up and back down."""
    rng = rng_for("fire_wind")
    dur = 0.42
    x = noise(rng, dur)
    cut = 400 + 2200 * swell(dur, 1.0)
    band = sweep_lowpass(x, cut) - sweep_lowpass(x, cut * 0.35)
    return finish(band * swell(dur, 1.4), -3.0)


@sound
def fire_arcane():
    """Magic bolt: a falling, wobbling tone."""
    dur = 0.28
    t = times(dur)
    f = sweep(1300, 380, dur, 0.6) * (1.0 + 0.03 * np.sin(2 * np.pi * 32 * t))
    return finish(tone(f, dur, ((1.0, 1.0), (2.0, 0.3), (3.0, 0.1)), tau=0.1), -3.0)


@sound
def fire_fire():
    """Fwoosh of flame with crackles and a low rumble."""
    rng = rng_for("fire_fire")
    dur = 0.5
    t = times(dur)
    body = sweep_lowpass(noise(rng, dur), 300 + 2600 * np.minimum(t / 0.08, 1.0) * np.exp(-t / 0.3))
    body *= np.minimum(t / 0.04, 1.0) * np.exp(-t / 0.18)
    rumble = tone(sweep(90, 50, dur), dur, tau=0.15)
    crackle = np.zeros(len(t))
    for _ in range(10):
        pop = highpass(noise(rng, 0.006), 3000) * decay(0.006, 0.0015)
        place(crackle, pop, rng.uniform(0.02, 0.35), rng.uniform(0.3, 0.8))
    return finish(body * 1.6 + 0.4 * rumble + 0.5 * crackle, -2.0)


@sound
def fire_ice():
    """Ice crack: a sharp snap and ringing crystal partials."""
    rng = rng_for("fire_ice")
    snap = highpass(noise(rng, 0.03), 3000) * decay(0.03, 0.006)
    ring = np.zeros(int(0.4 * SR))
    for f, tau in ((2300, 0.12), (3170, 0.09), (4410, 0.07), (5900, 0.05), (1580, 0.1)):
        ring += tone(f * rng.uniform(0.98, 1.02), 0.4, tau=tau) * rng.uniform(0.4, 0.8)
    return finish(mix(0.4, (0.0, snap, 1.0), (0.004, ring, 0.6)), -2.5)


@sound
def fire_lightning():
    """Electric zap: a buzzing sawtooth that jumps in pitch, and a crack."""
    rng = rng_for("fire_lightning")
    dur = 0.35
    n = int(dur * SR)
    steps = rng.uniform(70, 220, n // 160 + 1)
    f = np.repeat(steps, 160)[:n]
    ph = phase_of(f)
    saw = ((ph / (2 * np.pi)) % 1.0) * 2.0 - 1.0
    buzz = saw * (0.6 + 0.4 * noise(rng, dur))
    flicker = np.repeat(rng.uniform(0.3, 1.0, n // 300 + 1), 300)[:n]
    buzz = lowpass(buzz * flicker, 4500) * decay(dur, 0.1)
    crack = highpass(noise(rng, 0.03), 1500) * decay(0.03, 0.008)
    return finish(mix(dur, (0.0, buzz, 1.0), (0.0, crack, 0.8)), -3.0)


@sound
def fire_nature():
    """Thwip: a quick rising chirp like a seed flicked off a branch."""
    rng = rng_for("fire_nature")
    up = tone(sweep(320, 1400, 0.05), 0.05)
    down = tone(sweep(1400, 900, 0.12), 0.12, tau=0.04)
    breath = bandpass(noise(rng, 0.08), 1500, 5000) * swell(0.08)
    return finish(mix(0.2, (0.0, up, 0.8), (0.05, down, 1.0), (0.0, breath, 0.2)), -3.0)


# --- Impacts ------------------------------------------------------------------


@sound
def impact_arrow():
    """Arrow thunk into a creep."""
    rng = rng_for("impact_arrow")
    body = tone(sweep(280, 140, 0.12), 0.12, tau=0.03)
    tap = bandpass(noise(rng, 0.03), 1000, 4000) * decay(0.03, 0.006)
    return finish(mix(0.14, (0.0, body, 1.0), (0.0, tap, 0.5)), -3.0)


@sound
def impact_earth():
    """Boulder landing: a boom and scattered gravel."""
    rng = rng_for("impact_earth")
    boom = drum(80, 34, 0.7, 0.22, rng, 0.8, 300)
    gravel = np.zeros(int(0.7 * SR))
    for _ in range(18):
        grain = bandpass(noise(rng, 0.02), 800, 4000) * decay(0.02, 0.005)
        place(gravel, grain, rng.uniform(0.04, 0.45), rng.uniform(0.1, 0.35))
    return finish(boom + gravel, -1.5)


@sound
def impact_wind():
    """Soft puff of air."""
    rng = rng_for("impact_wind")
    return finish(lowpass(noise(rng, 0.2), 1400) * decay(0.2, 0.05, 0.01), -5.0)


@sound
def impact_magic():
    """Arcane pop with a small ring."""
    pop = tone(sweep(500, 900, 0.04), 0.04, tau=0.02)
    ring = bell(1760, 0.25, tau=0.12, bright=0.6)
    return finish(mix(0.25, (0.0, pop, 1.0), (0.01, ring, 0.5)), -4.0)


@sound
def impact_fire():
    """Small fiery burst."""
    rng = rng_for("impact_fire")
    burst = lowpass(noise(rng, 0.45), 1300) * decay(0.45, 0.12, 0.005)
    thump = tone(sweep(90, 45, 0.45), 0.45, tau=0.08)
    crackle = np.zeros(int(0.45 * SR))
    for _ in range(8):
        pop = highpass(noise(rng, 0.006), 3000) * decay(0.006, 0.0015)
        place(crackle, pop, rng.uniform(0.03, 0.3), rng.uniform(0.2, 0.6))
    return finish(burst * 1.5 + 0.6 * thump + 0.4 * crackle, -2.0)


@sound
def impact_ice():
    """Shatter: a spray of tiny crystal pings."""
    rng = rng_for("impact_ice")
    out = highpass(noise(rng, 0.35), 4000) * decay(0.35, 0.02) * 0.5
    for _ in range(26):
        ping = tone(rng.uniform(2800, 7500), 0.05, tau=0.015)
        place(out, ping, rng.exponential(0.05), rng.uniform(0.2, 0.6))
    return finish(out, -3.0)


@sound
def impact_nature():
    """Wet squelch of a poison seed."""
    rng = rng_for("impact_nature")
    dur = 0.22
    t = times(dur)
    goo = sweep_lowpass(noise(rng, dur), 500 + 900 * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * t)))
    goo *= decay(dur, 0.06, 0.005)
    blob = tone(sweep(200, 90, dur), dur, tau=0.05)
    return finish(goo * 2.0 + 0.6 * blob, -4.0)


@sound
def zap_small():
    """Short zap for a lightning hop."""
    return finish(fire_lightning()[: int(0.12 * SR)] * decay(0.12, 0.04), -4.0)


# --- Creeps and waves ---------------------------------------------------------


@sound
def creep_death():
    """Grunt and poof: a growling falling tone and a burst of air."""
    rng = rng_for("creep_death")
    dur = 0.45
    t = times(dur)
    growl = tone(sweep(260, 70, dur, 0.7), dur, ((1.0, 1.0), (2.0, 0.5), (3.0, 0.25)), tau=0.12)
    growl *= 0.6 + 0.4 * np.sin(2 * np.pi * 38 * t)
    poof = lowpass(noise(rng, dur), 900) * decay(dur, 0.1, 0.01)
    return finish(growl + 1.2 * poof, -2.5)


@sound
def leak():
    """Warning: two low bell strikes a semitone apart over a drum."""
    rng = rng_for("leak")
    a = bell(midi(57), 1.0, tau=0.5)
    b = bell(midi(56), 1.0, tau=0.6)
    hit = drum(70, 40, 0.5, 0.18, rng, 0.4, 400)
    x = mix(1.2, (0.0, a, 0.7), (0.0, hit, 0.8), (0.26, b, 0.8), (0.26, hit, 0.6))
    return finish(reverb(x, rng, 0.8, 0.25), -1.5)


@sound
def wave_start():
    """War horn call, a fifth up, over a big drum."""
    rng = rng_for("wave_start")
    low = brass(midi(50), 0.45, attack=0.08, release=0.1, bright=4.0)
    high = brass(midi(57), 1.5, attack=0.15, release=0.5, bright=6.0)
    under = brass(midi(38), 1.9, attack=0.2, release=0.6, bright=2.0)
    hit = drum(65, 38, 1.0, 0.35, rng, 0.5, 300)
    x = mix(2.0, (0.0, low, 0.8), (0.42, high, 0.9), (0.0, under, 0.35), (0.0, hit, 0.9))
    return finish(reverb(lowpass(x, 5000), rng, 1.4, 0.3), -1.0)


@sound
def wave_cleared():
    """Bright chime arpeggio."""
    rng = rng_for("wave_cleared")
    parts = []
    for i, n in enumerate((67, 71, 74, 79)):
        parts.append((i * 0.11, bell(midi(n), 1.2, tau=0.5, bright=0.7), 0.7))
    parts.append((0.33, pluck(midi(55), 1.0, 0.8), 0.4))
    return finish(reverb(mix(1.4, *parts), rng, 1.0, 0.3), -2.0)


@sound
def victory():
    """Fanfare: a triplet call and a held major chord, with timpani."""
    rng = rng_for("victory")
    parts = []
    for i in range(3):
        parts.append((i * 0.16, brass(midi(62), 0.15, attack=0.02, release=0.05), 0.8))
    for n, gain in ((62, 0.6), (66, 0.5), (69, 0.6), (74, 0.7)):
        parts.append((0.5, brass(midi(n), 2.0, attack=0.06, release=0.8, bright=7.0), gain))
    for i, at in enumerate((0.0, 0.16, 0.32, 0.5)):
        parts.append((at, drum(90, 60, 0.8, 0.3, rng, 0.3), 0.5 if i < 3 else 0.9))
    return finish(reverb(lowpass(mix(3.2, *parts), 6000), rng, 1.6, 0.35), -1.0)


@sound
def defeat():
    """Falling minor horn line and a low gong."""
    rng = rng_for("defeat")
    parts = [
        (0.0, brass(midi(57), 0.5, attack=0.08, release=0.15, bright=4.0), 0.8),
        (0.5, brass(midi(53), 0.5, attack=0.08, release=0.15, bright=3.5), 0.8),
        (1.0, brass(midi(50), 1.8, attack=0.1, release=0.9, bright=3.0, vibrato=0.01), 0.9),
        (1.0, brass(midi(38), 1.8, attack=0.2, release=0.9, bright=1.5), 0.4),
        (1.0, bell(midi(38), 2.0, tau=1.2, bright=0.8), 0.6),
        (1.0, drum(60, 32, 1.0, 0.4, rng, 0.4, 250), 0.9),
    ]
    return finish(reverb(lowpass(mix(3.2, *parts), 4000), rng, 1.8, 0.4), -1.0)


# --- Music ----------------------------------------------------------------------

# Two bars per chord: (root midi note, chord intervals).
PROGRESSION = [
    (50, (0, 3, 7)),  # Dm
    (46, (0, 4, 7)),  # Bb
    (53, (0, 4, 7)),  # F
    (48, (0, 4, 7)),  # C
    (50, (0, 3, 7)),  # Dm
    (46, (0, 4, 7)),  # Bb
    (43, (0, 3, 7)),  # Gm
    (45, (0, 4, 7)),  # A
]
# Flute melody over the second half: (beat from the start, beats, midi note).
MELODY = [
    (32, 2, 69), (34, 1, 74), (35, 1, 76), (36, 3, 77), (39, 1, 76),
    (40, 2, 74), (42, 1, 72), (43, 1, 70), (44, 4, 69),
    (48, 2, 67), (50, 1, 69), (51, 1, 70), (52, 3, 74), (55, 1, 72),
    (56, 2, 73), (58, 2, 76), (60, 4, 69),
]


def music_length():
    return int(round(MUSIC_BARS * 4 * 60.0 / MUSIC_BPM * SR))


def flute(freq, dur, rng):
    t = times(dur)
    env = np.minimum(t / 0.08, 1.0) * np.clip((dur - t) / 0.2, 0.0, 1.0)
    vib = 1.0 + 0.005 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.25) / 0.3, 0.0, 1.0)
    body = tone(freq * vib, dur, ((1.0, 1.0), (2.0, 0.18), (3.0, 0.06)))
    breath = bandpass(noise(rng, dur), freq, freq * 4) * 0.08
    return (body + breath) * env


def pad(freqs, dur):
    t = times(dur)
    env = np.minimum(t / 0.8, 1.0) * np.clip((dur - t) / 0.9, 0.0, 1.0)
    out = np.zeros(len(t))
    for f in freqs:
        for detune in (0.997, 1.003):
            for k in range(1, 7):
                out += (0.5 / k ** 1.6) * np.sin(2 * np.pi * f * detune * k * t + k)
    return out * env


@sound
def music_calm():
    """Build-phase layer: a string pad, harp arpeggios, soft bass and a flute."""
    rng = rng_for("music_calm")
    beat = 60.0 / MUSIC_BPM
    buf = np.zeros(music_length())
    arp = (0, 7, 12, 15, 19, 15, 12, 7)  # semitones over the root; third fixed below
    for i, (root, chord) in enumerate(PROGRESSION):
        start = i * 8 * beat
        notes = [midi(root + 12 + iv) for iv in chord]
        place(buf, pad(notes, 8 * beat + 0.6), start, 0.12, wrap=True)
        place(buf, pluck(midi(root - 12), 2.4, 1.2, 6, 0.5), start, 0.35, wrap=True)
        place(buf, pluck(midi(root - 12), 2.4, 1.2, 6, 0.5), start + 4 * beat, 0.25, wrap=True)
        for j in range(16):
            step = arp[j % 8]
            if step in (15, 3):
                step = 12 + chord[1]
            elif step == 19:
                step = 12 + chord[2]
            gain = 0.22 if j % 2 == 0 else 0.15
            place(buf, pluck(midi(root + 12 + step), 1.6, 0.9), start + j * beat / 2, gain, wrap=True)
    for at, beats, n in MELODY:
        place(buf, flute(midi(n), beats * beat * 0.95, rng), at * beat, 0.2, wrap=True)
    buf = reverb(buf, rng, 2.2, 0.45, circular=True, damp=2500)
    return finish(buf, -3.0, fade=0.0, trim=False)


@sound
def music_battle():
    """Wave layer on top of the calm one: war drums, a driving bass and a shaker."""
    rng = rng_for("music_battle")
    beat = 60.0 / MUSIC_BPM
    buf = np.zeros(music_length())
    big = drum(85, 48, 0.8, 0.28, rng, 0.5, 350)
    small = drum(170, 120, 0.3, 0.09, rng, 0.6, 1500)
    pattern = ((0.0, big, 1.0), (1.5, big, 0.7), (2.0, big, 0.9), (3.0, small, 0.6), (3.5, small, 0.5))
    for bar in range(MUSIC_BARS):
        t0 = bar * 4 * beat
        for b, x, g in pattern:
            place(buf, x, t0 + b * beat, g, wrap=True)
        if bar % 4 == 3:
            for k in range(8):
                place(buf, small, t0 + (2.0 + k * 0.25) * beat, 0.3 + 0.07 * k, wrap=True)
        for k in range(16):
            sh = highpass(noise(rng, 0.05), 6000) * decay(0.05, 0.012)
            place(buf, sh, t0 + k * beat / 4, 0.12 if k % 2 else 0.05, wrap=True)
    for i, (root, chord) in enumerate(PROGRESSION):
        start = i * 8 * beat
        line = (0, 0, 12, 0, chord[2], 0, 12, chord[1])
        for j in range(16):
            f = midi(root - 12 + line[j % 8])
            note = brass(f, beat * 0.45, attack=0.01, release=0.08, bright=2.5, vibrato=0.0, scoop=0.0)
            place(buf, note, start + j * beat / 2, 0.35, wrap=True)
        if i % 2 == 0:
            stab = brass(midi(root), beat * 1.5, attack=0.03, release=0.4, bright=4.0, scoop=0.02)
            place(buf, stab, start, 0.25, wrap=True)
    buf = reverb(lowpass(buf, 5000), rng, 1.4, 0.3, circular=True, damp=2500)
    return finish(buf, -3.0, fade=0.0, trim=False)


# --- Output -------------------------------------------------------------------


def write_wav(path, x):
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def write(out_dir, name, x, use_ogg):
    if not use_ogg:
        path = os.path.join(out_dir, name + ".wav")
        write_wav(path, x)
        return path
    path = os.path.join(out_dir, name + ".ogg")
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, name + ".wav")
        write_wav(src, x)
        quality = "2" if name.startswith("music") else "3"
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-c:a", "libvorbis",
             "-q:a", quality, "-map_metadata", "-1", "-fflags", "+bitexact",
             "-flags:a", "+bitexact", path],
            check=True,
        )
    return path


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("out_dir", nargs="?", default=os.path.join(root, "game", "assets", "audio"))
    parser.add_argument("--only", help="make just this sound")
    parser.add_argument("--wav", action="store_true", help="write WAV even if ffmpeg exists")
    args = parser.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    if not args.wav and shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg is needed to write the .ogg files the game loads (or pass --wav)")
    use_ogg = not args.wav
    names = [args.only] if args.only else list(SOUNDS)
    total = 0
    for name in names:
        if name not in SOUNDS:
            sys.exit(f"unknown sound {name}; known: {', '.join(SOUNDS)}")
        x = SOUNDS[name]()
        path = write(args.out_dir, name, x, use_ogg)
        size = os.path.getsize(path)
        total += size
        print(f"{os.path.basename(path):24s} {len(x) / SR:6.2f} s {size / 1024:8.1f} KiB")
    print(f"total {total / 1024:.1f} KiB")


if __name__ == "__main__":
    main()
