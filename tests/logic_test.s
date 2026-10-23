; logic_test.s - the game logic alone, for tests/logic_test.py (py65)
.include "../src/defs.inc"
.segment "ZEROPAGE"
ptr:    .res 2
ptr2:   .res 2
.include "../src/game.s"
