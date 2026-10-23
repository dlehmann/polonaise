; game_sound.s - the game logic and the SID player together, for tests/game_sound.py (py65)
.include "../src/defs.inc"
.segment "ZEROPAGE"
ptr:    .res 2
ptr2:   .res 2
.segment "BSS"
pal:        .res 1
sound_on:   .res 1
.segment "CODE"
.include "../src/game.s"
.include "../src/sound.s"
