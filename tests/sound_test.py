#!/usr/bin/env python3
"""sound_test.py - runs the SID player (build/sound_test.bin) in py65 and checks the notes
it writes against the music tables: the bass on voice 1, the melody on voice 3."""
import os
import sys
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
lbl = {}
for line in open(os.path.join(ROOT, 'build/sound_test.lbl')):
    p = line.split()
    lbl[p[2][1:]] = int(p[1], 16)

mem = ObservableMemory()
sid = [0] * 32
log = []
tick = [0]


def wr(addr, val):
    sid[addr - 0xd400] = val
    log.append((tick[0], addr - 0xd400, val))


mem.subscribe_to_write(range(0xd400, 0xd420), wr)
mpu = MPU(memory=mem)
data = open(os.path.join(ROOT, 'build/sound_test.bin'), 'rb').read()
for i, b in enumerate(data):
    mem[0x1000 + i] = b


def call(name, a=0):
    mpu.sp = 0xfd
    ret = 0xfff0
    mem[0x1ff] = (ret - 1) >> 8
    mem[0x1fe] = (ret - 1) & 255
    mpu.a = a
    mpu.pc = lbl[name]
    n = 0
    while mpu.pc != ret:
        mpu.step()
        n += 1
        assert n < 100000, name
    return n


mem[lbl['pal']] = 1
call('sound_init')
call('music_start')
worst = 0
for t in range(30 * 64 + 10):
    tick[0] = t
    worst = max(worst, call('sound_tick'))
    if t in (200, 1000):
        call('sfx_play', 4)         # CATCH2: on voice 2, the melody plays on


def freq_of(note):
    return mem[lbl['freq_lo'] + note] | mem[lbl['freq_hi'] + note] << 8


bass = [mem[lbl['mus_bass'] + i] for i in range(256)]
drum = [mem[lbl['mus_drum'] + i] for i in range(256)]
DRUM_LEN = [0, 3, 3, 1, 1]
ok = True
# step starts: steps alternate 7 and 8 ticks
starts, t = [], 0
for s_ in range(256):
    starts.append(t)
    t += 7 + (s_ & 1)
f1 = {}
for tk, reg, v in log:
    if reg in (0, 1):
        f1.setdefault(tk, {})[reg] = v
# voice 1: the bass note after the drum hit of its step
for st in range(64):
    if bass[st]:
        tk = starts[st] + DRUM_LEN[drum[st]]
        regs = f1.get(tk, {})
        got = regs.get(0, -1) | regs.get(1, -1) << 8
        if got != freq_of(bass[st]):
            print('bass step %d tick %d: freq %04x, expected %04x' % (st, tk, got, freq_of(bass[st])))
            ok = False
v1 = [(tk, v) for tk, reg, v in log if reg == 4 and tk < starts[4]]
print('voice 1 control in the first beat:', v1)
# the music never writes voice 3, the effects never voice 1 or 2
fx_ticks = set(range(200, 232)) | set(range(1000, 1030))
mus_v3 = [(tk, reg) for tk, reg, v in log if 14 <= reg <= 20 and tk not in fx_ticks and tk > 5]
if mus_v3:
    print('FAILED: the music writes voice 3', mus_v3[:5])
    ok = False
mel = [(tk, v) for tk, reg, v in log if reg == 11 and 955 <= tk < 1100 and v in (64, 65)]
print('melody gates (voice 2):', [m for i, m in enumerate(mel) if i == 0 or mel[i - 1][1] != m[1]][:10])
fx = [(tk, reg, v) for tk, reg, v in log if 200 <= tk < 226 and reg >= 14]
print('effect on voice 3:', fx[:8])
if not fx:
    ok = False
print('OK' if ok else 'FAILED')
