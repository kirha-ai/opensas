from pathlib import Path
from fractions import Fraction
import json,struct
cases=[];lines=[]
for k,lo,hi in [(87,-8.,8.),(6,0.,16.)]:
 for variant in range(6):
  indices=[0,13,34,55,106,152,200]
  if variant==1:indices[1]=Fraction(66,5)
  if variant==2:indices[-2]=Fraction(759,5)
  if variant==3:indices.insert(0,0)
  if variant==4:indices=[0,5,30,73,100,172,200]
  vals=[float(Fraction(lo)+(Fraction(hi)-Fraction(lo))*Fraction(i)/200) for i in indices]
  target=float(Fraction(lo)+(Fraction(hi)-Fraction(lo))*Fraction(2*k+1,400));vals.append(target)
  vals=sorted(vals,reverse=variant==5)
  cid=len(cases);cases.append(dict(id=cid,k=k,shift=lo+8,direction=0,variant=variant,lo=lo,hi=hi,target=target,values=vals))
  for j,v in enumerate(vals):lines.append(f'{cid} {j} {struct.pack(">d",v).hex().upper()}')
s='ods graphics off;\ndata all;input id point x :hex16.;datalines;\n'+'\n'.join(lines)+'''\n;
data _null_;set all;file print;put 'INPUT ' id= point= x=hex16.;run;
proc univariate data=all noprint;by id;var x;output out=stats n=n qrange=q std=sd;
histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set stats;file print;put 'STATS ' id= n=best32. q=best32. sd=best32.;run;
data _null_;set k;by id;file print;if first.id then put 'RESULT ' id= _c_=best32.;run;
'''
Path('/private/tmp/dev2-sjpi-halfgrid-background-left.sas').write_text(s)
Path('/private/tmp/dev2-sjpi-halfgrid-background-left-inputs.json').write_text(json.dumps(cases,indent=2)+'\n')
