#!/usr/bin/env python3
"""game_sound.py - plays a game (logic + SID player in py65, the player of logic_test.py),
logs the SID registers per tick and renders them with reSID to build/game_sound.wav.
Reports how loud the music (voices 1 and 2) is with and without effects."""
import os, sys, random, wave, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory
from logic_test import choose, EV

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
lbl = {}
for line in open(os.path.join(ROOT, 'build/game_sound.lbl')):
    p = line.split(); lbl[p[2][1:]] = int(p[1], 16)
mem = ObservableMemory()
writes = []
tick = [0]
mem.subscribe_to_write(range(0xd400, 0xd420), lambda a, v: writes.append((tick[0], a - 0xd400, v)))
mpu = MPU(memory=mem)
data = open(os.path.join(ROOT, 'build/game_sound.bin'), 'rb').read()
for i, b in enumerate(data):
    mem[0x1000 + i] = b

def call(name, a=0, x=0):
    mpu.sp = 0xfd; ret = 0xfff0
    mem[0x1ff] = (ret - 1) >> 8; mem[0x1fe] = (ret - 1) & 255
    mpu.a, mpu.x, mpu.pc = a, x, lbl[name]
    while mpu.pc != ret:
        mpu.step()

def b(n, i=0): return mem[lbl[n] + i]

def state():
    n = b('length')
    return dict(body=[b('body', i) for i in range(n)], dir=b('dir'), moving=bool(b('moving')),
                tile=[b('tile', i) for i in range(228)],
                guests=[[i, b('g_type', i), b('g_cell', i)] for i in range(32) if b('g_active', i)])

mem[lbl['pal']] = 1
seed = 99
for i, v in enumerate((seed & 255, 0, 0, 0)):
    mem[lbl['rng'] + i] = v
call('sound_init'); call('music_start'); call('game_new')
rnd = random.Random(1)
TICKS = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
fx_ticks = []
for t in range(TICKS):
    tick[0] = t
    d, a = choose(state(), rnd)
    call('game_tick', d, 1 if a else 0)
    for i in range(b('ev_n')):
        call('sound_event', 0, i)
    call('sound_tick')
    if b('sfx_on'):
        fx_ticks.append(t)
    if b('done'):
        call('game_new')
print('effect ticks: %d of %d' % (len(fx_ticks), TICKS))

# render with reSID: all voices to the WAV, voice 3 alone for the check
from datetime import timedelta
from pyresidfp import SoundInterfaceDevice, Voice
full = SoundInterfaceDevice(sampling_frequency=22050.0)
alone = SoundInterfaceDevice(sampling_frequency=22050.0)
alone.mute(Voice.THREE)                 # the music alone (voices 1 and 2)
per = {}
for tk, reg, v in writes:
    per.setdefault(tk, []).append((reg, v))
out, rms3 = [], []
for t in range(TICKS):
    for reg, v in per.get(t, []):
        full._sid.write(reg, v)
        alone._sid.write(reg, v)
    out.extend(full.clock(timedelta(seconds=1 / 60)))
    a3 = alone.clock(timedelta(seconds=1 / 60))
    rms3.append((sum(x * x for x in a3) / max(1, len(a3))) ** 0.5)
w = wave.open(os.path.join(ROOT, 'build/game_sound.wav'), 'wb')
w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050)
w.writeframes(b''.join(struct.pack('<h', max(-32768, min(32767, int(x)))) for x in out))
w.close()
# voice 3 in the melody part (bars 9..16: ticks 960..1919 of each 1920) with and without an effect
fx = set(fx_ticks)
def mean(l): return sum(l) / max(1, len(l))
print('music (voices 1, 2) loudness: without effect %.0f, during effects %.0f' % (
    mean([rms3[t] for t in range(TICKS) if t not in fx]), mean([rms3[t] for t in fx])))
print('rendered', len(out) / 22050, 's')
