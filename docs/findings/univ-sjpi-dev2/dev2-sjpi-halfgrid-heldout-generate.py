from pathlib import Path
from fractions import Fraction
import math,struct,json
cases=[];rows=[]
def add(k,lo,hi,directions,label):
 mid=float(Fraction(lo)+(Fraction(hi)-Fraction(lo))*Fraction(2*k+1,400))
 for direction in directions:
  target=mid
  for _ in range(abs(direction)):target=math.nextafter(target,-math.inf if direction<0 else math.inf)
  vals=sorted([float(Fraction(lo)+(Fraction(hi)-Fraction(lo))*Fraction(i,200)) for i in [0,13,34,55,106,152,200]]+[target])
  cid=len(cases);cases.append(dict(id=cid,k=k,shift=lo+8,direction=direction,label=label,lo=lo,hi=hi,target=target,values=vals))
  for j,v in enumerate(vals):rows.append(f'{cid} {j} {struct.pack(">d",v).hex().upper()}')
for k in [47,123]:
 for lo,hi,label in [(-100.125,-94.205,'heldout negative scaled .37'),(2.75,130.75,'heldout positive scaled 8')]:add(k,lo,hi,[-1,0,1],label)
add(87,-7.99,8.01,[-16,-8,-4,-2,2,4,8,16],'transition k87 shift .01')
add(62,-8.,8.,[-16,-8,-4,-2,2,4,8,16],'transition k62 shift zero')
s='''ods graphics off;
data all; input id point x :hex16.; datalines;
'''+ '\n'.join(rows)+'''
;
data _null_;set all;file print;put 'INPUT ' id= point= x=hex16.;run;
proc univariate data=all noprint;by id;var x;output out=stats n=n qrange=q std=sd;
histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set stats;file print;put 'STATS ' id= n=best32. q=best32. sd=best32.;run;
data _null_;set k;by id;file print;if first.id then put 'RESULT ' id= _c_=best32.;run;
'''
Path('/private/tmp/dev2-sjpi-halfgrid-heldout.sas').write_text(s)
Path('/private/tmp/dev2-sjpi-halfgrid-heldout-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
