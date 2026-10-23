// js_game.mjs - runs game.ts of the browser version tick by tick for logic_test.py.
// stdin: "new <seed>" or "<dir> <a>" per line; stdout: the state as JSON per line.
import { Game } from '../../polonaise-c64/src/game.ts';
import * as readline from 'node:readline';

let g = null;
const rl = readline.createInterface({ input: process.stdin });
const state = () => ({
    phase: g.phase, timer: g.timer, song: g.song, score: g.score / 100, lives: g.lives, done: g.done,
    length: g.length, body: Array.from(g.body.slice(0, g.length)), look: Array.from(g.look.slice(0, g.length)),
    dir: g.dir, moving: g.moving, combo: g.combo, comboTimer: g.comboTimer, steps: g.steps & 255,
    stepTimer: g.stepTimer, dropped: g.dropped,
    guests: g.guests.map((x, i) => x.active ? [i, x.type, x.cell, x.look, Math.min(x.moved, 255), x.age] : null)
        .filter(x => x),
    events: g.events.map(e => [e.type, e.cell, e.count, e.index, e.points / 100]),
    tile: Array.from(g.tile),
});
rl.on('line', line => {
    const p = line.trim().split(' ');
    if (p[0] === 'new') {
        g = new Game(Number(p[1]) >>> 0);
        if (p[2]) g.startAt(Number(p[2]));
    } else {
        g.tick(Number(p[0]), p[1] === '1');
    }
    process.stdout.write(JSON.stringify(state()) + '\n');
});
