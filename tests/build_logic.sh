#!/bin/sh
# builds build/logic_test.bin for tests/logic_test.py
cd "$(dirname "$0")" && B=../tools/cc65/bin && mkdir -p ../build &&
$B/ca65 -g -I ../gen logic_test.s -o ../build/logic_test.o &&
$B/ld65 -C logic_test.cfg -o ../build/logic_test.bin -Ln ../build/logic_test.lbl ../build/logic_test.o
