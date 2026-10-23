; sound_test.s - the SID player alone, for tests/sound_test.py (py65)
.include "../src/defs.inc"
.segment "ZEROPAGE"
ptr:    .res 2
ptr2:   .res 2
.segment "BSS"
pal:        .res 1
sound_on:   .res 1
ev_type:    .res 16
ev_index:   .res 16
ev_count:   .res 16
.segment "CODE"
.include "../src/sound.s"
