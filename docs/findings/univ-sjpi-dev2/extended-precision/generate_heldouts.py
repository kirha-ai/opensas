"""Prespecified heldouts; run before obtaining any SAS outcomes."""
from fractions import Fraction as F
from pathlib import Path
import hashlib
import json
import math
import struct

HERE = Path(__file__).resolve().parent
INDICES = (19, 83, 161)
DOMAINS = ((-2.125, 9.875), (257.25, 297.25), (-33.7, -30.74))
BACKGROUND = (0, 9, 37, 68, 111, 173, 200)
rows = []
cases = []
for k in INDICES:
    for low, high in DOMAINS:
        midpoint = float(F(low) + (F(high)-F(low))*F(2*k+1, 400))
        for direction in (-1, 0, 1):
            target = midpoint if direction == 0 else math.nextafter(midpoint, -math.inf if direction < 0 else math.inf)
            values = sorted([float(F(low)+(F(high)-F(low))*F(i, 200)) for i in BACKGROUND]+[target])
            cid = len(cases)
            cases.append(dict(id=cid, k=k, lo=low, hi=high, direction=direction, target=target, values=values,
                              target_hex=struct.pack('>d', target).hex().upper()))
            for point, value in enumerate(values):
                rows.append(f'{cid} {point} {struct.pack(">d", value).hex().upper()}')
manifest = json.dumps(cases, indent=2)+'\n'
(HERE/'heldouts-inputs.json').write_text(manifest)
source = '''ods graphics off;
data _null_;file print;put "SAS_VERSION=&sysvlong4";run;
data all;input id point x :hex16.;datalines;
'''+ '\n'.join(rows)+'''
;
data _null_;set all;file print;put 'INPUT ' id= point= x=hex16.;run;
proc univariate data=all noprint;by id;var x;
output out=stats n=n qrange=q std=sd;
histogram x / noplot kernel(c=sjpi) outkernel=kernel;run;
data one;set kernel;by id;if first.id;keep id _c_;run;
data _null_;merge one stats;by id;file print;
c=_c_;h=c*q*n**(-.2);
put 'RESULT ' id= n= q=hex16. sd=hex16. c=hex16. h=hex16.;run;
'''
(HERE/'heldouts.sas').write_text(source)
print('heldouts-inputs.json sha256 '+hashlib.sha256(manifest.encode()).hexdigest())
