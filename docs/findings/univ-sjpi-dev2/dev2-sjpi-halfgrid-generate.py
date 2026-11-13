from pathlib import Path
from fractions import Fraction
import math,struct,json
rows=[];cases=[]
for k in [62,87]:
 for shift in [0.,.01,-.07,100.]:
  lo,hi=-8+shift,8+shift
  exact=Fraction(lo)+(Fraction(hi)-Fraction(lo))*Fraction(2*k+1,400)
  mid=float(exact)
  for direction in [-1,0,1]:
   target=math.nextafter(mid,-math.inf if direction<0 else math.inf) if direction else mid
   vals=[float(Fraction(lo)+(Fraction(hi)-Fraction(lo))*Fraction(i,200)) for i in [0,13,34,55,106,152,200]]+[target]
   cid=len(cases);cases.append(dict(id=cid,k=k,shift=shift,direction=direction,lo=lo,hi=hi,target=target,values=sorted(vals)))
   for j,v in enumerate(sorted(vals)):rows.append(f'{cid} {j} {struct.pack(">d",v).hex().upper()}')
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
Path('/private/tmp/dev2-sjpi-halfgrid.sas').write_text(s)
Path('/private/tmp/dev2-sjpi-halfgrid-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
