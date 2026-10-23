#!/usr/bin/env python3
"""fixbranch.py - turns the branches that ca65 reports as out of range into an
inverted branch over a jmp. Reads the assembler messages on stdin."""
import re
import sys

INV = {'beq': 'bne', 'bne': 'beq', 'bcc': 'bcs', 'bcs': 'bcc', 'bmi': 'bpl', 'bpl': 'bmi', 'bvc': 'bvs',
       'bvs': 'bvc'}
fixes = {}
for line in sys.stdin:
    m = re.match(r'(\S+):(\d+): Error: Range error', line)
    if m:
        fixes.setdefault(m.group(1), set()).add(int(m.group(2)))
for path, nums in fixes.items():
    lines = open(path).read().split('\n')
    for n in sorted(nums, reverse=True):
        l = lines[n - 1]
        m = re.match(r'^(\S*:)?(\s+)(b\w\w)\s+(\S+)(.*)$', l)
        if not m or m.group(3) not in INV:
            print('cannot fix %s:%d: %s' % (path, n, l))
            continue
        label = (m.group(1) or '')
        ind = m.group(2)
        lines[n - 1] = '%s%s%s *+5\n        jmp %s%s' % (label, ind, INV[m.group(3)], m.group(4), m.group(5))
    open(path, 'w').write('\n'.join(lines))
    print('fixed %d in %s' % (len(nums), path))
