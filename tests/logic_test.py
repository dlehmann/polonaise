#!/usr/bin/env python3
"""
logic_test.py - runs the 6502 game logic (build/logic_test.bin in py65) and game.ts of
the browser version (js_game.mjs in node) side by side with the same seed and the same
input, and compares their states after every tick.

The input comes from a simple player: it walks towards the nearest guest, turns
randomly now and then and presses A (fire) at times, so the runs see catches,
crashes, cleared songs and game overs.

Usage: tests/logic_test.py [song=N] [ticks] [seeds...]
"""
import json
import os
import random
import subprocess
import sys

from py65.devices.mpu6502 import MPU

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
EV = ['turn', 'go', 'deny', 'grace', 'catch', 'flee', 'star', 'star-gone', 'crash', 'extra-life', 'song-start',
      'play', 'cleared', 'game-over']
COLS, ROWS, CELLS = 19, 12, 228


def labels():
    out = {}
    for line in open(os.path.join(ROOT, 'build/logic_test.lbl')):
        p = line.split()
        out[p[2][1:]] = int(p[1], 16)
    return out


class Cpu:
    def __init__(self):
        self.l = labels()
        self.mpu = MPU()
        data = open(os.path.join(ROOT, 'build/logic_test.bin'), 'rb').read()
        self.mpu.memory[0x1000:0x1000 + len(data)] = list(data)

    def call(self, name, a=0, x=0):
        m = self.mpu
        m.sp = 0xff
        ret = 0xfff0
        m.memory[0x1ff] = (ret - 1) >> 8
        m.memory[0x1fe] = (ret - 1) & 255
        m.sp = 0xfd
        m.a, m.x = a, x
        m.pc = self.l[name]
        n = 0
        while m.pc != ret:
            m.step()
            n += 1
            if n > 2000000:
                raise RuntimeError('runaway in ' + name)
        return n

    def b(self, name, i=0):
        return self.mpu.memory[self.l[name] + i]

    def w(self, name):
        return self.b(name) | self.b(name, 1) << 8

    def set(self, name, values):
        for i, v in enumerate(values):
            self.mpu.memory[self.l[name] + i] = v

    def state(self):
        n = self.b('length')
        st = dict(phase=self.b('phase'), timer=self.w('timer'), song=self.b('song'),
                  score=self.b('score') | self.b('score', 1) << 8 | self.b('score', 2) << 16,
                  lives=self.b('lives'), done=bool(self.b('done')), length=n,
                  body=[self.b('body', i) for i in range(n)], look=[self.b('look', i) for i in range(n)],
                  dir=self.b('dir'), moving=bool(self.b('moving')), combo=self.b('combo'),
                  comboTimer=self.b('combo_timer'), steps=self.b('steps'), stepTimer=self.b('step_timer'),
                  dropped=self.b('dropped'))
        st['guests'] = [[i, self.b('g_type', i), self.b('g_cell', i), self.b('g_look', i), self.b('g_moved', i),
                         self.b('g_age_lo', i) | self.b('g_age_hi', i) << 8]
                        for i in range(32) if self.b('g_active', i)]
        ev = []
        for i in range(self.b('ev_n')):
            ev.append([EV[self.b('ev_type', i)], self.b('ev_cell', i), self.b('ev_count', i), self.b('ev_index', i),
                       self.b('ev_points', 2 * i) | self.b('ev_points', 2 * i + 1) << 8])
        st['events'] = ev
        st['tile'] = [self.b('tile', i) for i in range(CELLS)]
        return st


def normalize(js):
    js = dict(js)
    js['events'] = [[e[0], e[1] if e[1] >= 0 else 255, e[2], e[3], e[4]] for e in js['events']]
    return js


def choose(st, rnd):
    """A direction (4 = none) and A for the next tick."""
    a = rnd.random() < 0.02
    if rnd.random() < 0.85:
        return 4, a
    if rnd.random() < 0.15:
        return rnd.randrange(4), a
    head = st['body'][0]
    blocked = set(st['body'])
    blocked |= {i for i, t in enumerate(st['tile']) if t}
    goals = {g[2] for g in st['guests']}
    # breadth first search to the nearest guest
    prev = {head: None}
    todo = [head]
    found = None
    while todo and found is None:
        nxt = []
        for c in todo:
            x, y = c % COLS, c // COLS
            for d, (dx, dy) in enumerate(((1, 0), (0, 1), (-1, 0), (0, -1))):
                xx, yy = x + dx, y + dy
                if not (0 <= xx < COLS and 0 <= yy < ROWS):
                    continue
                n = yy * COLS + xx
                if n in prev or n in blocked:
                    continue
                prev[n] = (c, d)
                if n in goals:
                    found = n
                    break
                nxt.append(n)
            if found is not None:
                break
        todo = nxt
    if found is None:
        return rnd.randrange(4), a
    c = found
    while prev[c][0] != head:
        c = prev[c][0]
    return prev[c][1], a


START_SONG = 0


def run(seed, ticks):
    cpu = Cpu()
    js = subprocess.Popen(['node', os.path.join(HERE, 'js_game.mjs')], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          text=True, bufsize=1)

    def js_cmd(s):
        js.stdin.write(s + '\n')
        js.stdin.flush()
        return normalize(json.loads(js.stdout.readline()))

    rnd = random.Random(seed)
    total = [0, 0]
    hist = {}
    game_seed = seed
    games = 0
    maxsong = 0
    cycles = 0

    def new_game():
        nonlocal game_seed
        game_seed = (game_seed * 69069 + 1) & 0xffffffff
        cpu.set('rng', [game_seed & 255, game_seed >> 8 & 255, game_seed >> 16 & 255, game_seed >> 24])
        cpu.call('game_new')
        if START_SONG:
            cpu.call('game_start_at', START_SONG)
            return js_cmd('new %d %d' % (game_seed, START_SONG))
        return js_cmd('new %d' % game_seed)

    j = new_game()
    for t in range(ticks):
        c = cpu.state()
        if c != j:
            for k in j:
                if c.get(k) != j[k]:
                    print('seed %d tick %d game %d: %s differs\n  6502: %s\n  js:   %s' % (seed, t, games, k, c.get(k),
                                                                                         j[k]))
            js.kill()
            return False
        if j['done']:
            games += 1
            j = new_game()
            continue
        d, a = choose(j, rnd)
        n = cpu.call('game_tick', d, 1 if a else 0)
        cycles = max(cycles, n)
        total[0] += n
        total[1] += 1
        hist[min(n // 500, 20)] = hist.get(min(n // 500, 20), 0) + 1
        j = js_cmd('%d %d' % (d, 1 if a else 0))
        maxsong = max(maxsong, j['song'])
    js.kill()
    print('mean %d instructions per tick; histogram (per 500):' % (total[0] // max(1, total[1])), sorted(hist.items()))
    print('seed %d: %d ticks ok, %d games, up to song %d, longest tick %d instructions' % (seed, ticks, games, maxsong,
                                                                                         cycles))
    return True


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1].startswith('song='):
        START_SONG = int(sys.argv.pop(1)[5:])
    ticks = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
    seeds = [int(s) for s in sys.argv[2:]] or [1, 2, 3]
    ok = all([run(s, ticks) for s in seeds])
    sys.exit(0 if ok else 1)
