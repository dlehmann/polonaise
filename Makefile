# Polonaise C64 - builds build/polonaise.prg and build/polonaise.d64
CC65 = tools/cc65/bin
EXO = tools/exomizer/src/exomizer
PY = tools/venv/bin/python
SRC = ../polonaise-c64

GEN = gen/gfx.inc gen/text.inc gen/music.inc
ASM = $(wildcard src/*.s src/*.inc)

all: build/polonaise.d64

gen/gfx.inc: tools/gfx.py
	$(PY) tools/gfx.py $(SRC) gen

gen/text.inc: tools/text.py gen/gfx.inc
	$(PY) tools/text.py gen

gen/music.inc: tools/music.py
	$(PY) tools/music.py gen

# make test: the same with the autopilot (src/autopilot.s)
test: build/test.prg

build/test.prg: FORCE $(ASM) $(GEN) src/polonaise.cfg
	mkdir -p build
	$(CC65)/ca65 -g -D TEST=1 $(if $(SONG),-D TEST_SONG=$(SONG)) $(if $(SCRIPT),-D TEST_SCRIPT=$(SCRIPT)) $(if $(LANG1),-D TEST_LANG=$(LANG1)) -I gen -I src --bin-include-dir gen src/main.s -o build/test.o
	$(CC65)/ld65 -C src/polonaise.cfg -o build/test.prg -Ln build/test.lbl build/test.o

build/polonaise.prg: $(ASM) $(GEN) src/polonaise.cfg
	mkdir -p build
	$(CC65)/ca65 -g -I gen -I src --bin-include-dir gen src/main.s -o build/main.o
	$(CC65)/ld65 -C src/polonaise.cfg -o build/polonaise.prg -Ln build/polonaise.lbl -m build/polonaise.map build/main.o

build/polonaise-exo.prg: build/polonaise.prg
	$(EXO) sfx 2061 -n -q -o build/polonaise-exo.prg build/polonaise.prg

build/polonaise.d64: build/polonaise-exo.prg tools/mkd64.py
	$(PY) tools/mkd64.py build/polonaise.d64 "POLONAISE" "PL" build/polonaise-exo.prg:POLONAISE
	cp build/polonaise.d64 polonaise.d64
	cp build/polonaise.d64 docs/polonaise.d64

clean:
	rm -rf build gen

.PHONY: all clean test FORCE
FORCE:
