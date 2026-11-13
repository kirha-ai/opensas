#!/usr/bin/env python3
"""Compare ordinary binary64 arithmetic with retained actual SAS HEX16 values."""
import json
import re
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
meta = json.loads((HERE/'dev2-sjpi-halfgrid-arithmetic-inputs.json').read_text())
raw = (HERE/'dev2-sjpi-halfgrid-arithmetic.txt').read_text()
entries = {}
for chunk in re.split(r'\bid=', raw)[1:]:
    cid = int(chunk.split()[0])
    entries.setdefault(cid, {}).update(re.findall(r'(step|inv|centered|z|z2|bound|l|r|ld|rd)=([0-9A-F]{16})', chunk))
checked = 0
for m in meta:
    low, high, x, k = m['lo'], m['hi'], m['target'], m['k']
    step = (high-low)/200
    left = low+k*step
    right = low+(k+1)*step
    values = dict(step=step, inv=1/step, centered=x-low,
                  z=(x-low)/step, z2=(x-low)*(1/step),
                  bound=low+(k+.5)*step, l=left, r=right,
                  ld=x-left, rd=right-x)
    for name, value in values.items():
        bits = struct.pack('>d', value).hex().upper()
        assert bits == entries[m['global_id']][name], (m['global_id'], name, bits)
        checked += 1
print(f'{len(meta)} input cases; {checked}/{checked} SAS intermediate HEX16 values match exactly.')
