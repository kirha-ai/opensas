exec(open('/private/tmp/dev5-hoeffding-boundaries-gen.py').read().split('cases=[]')[0])
# Start from the previous independently generated boundary permutations.
lines=Path('/private/tmp/dev5-hoeffding-boundaries.sas').read_text().split('datalines;\n')[1].split(';')[0].splitlines();initial={}
for line in lines:
 g,nn,x,y=map(int,line.split());initial.setdefault(g,[]).append(y)
cases=[]
for j,boundary in enumerate([.3,.55,1.1,2.95,10.3]):
 y=np.array(initial[2*j+1],dtype=float);z=stat(y);found={}
 for k in range(90000):
  target=boundary+[-.000015,0,.000002,.000005,.00001,.00002,.00004][(k//3000)%7]
  a,b=rng.choice(n,2,replace=False);y[a],y[b]=y[b],y[a];v=stat(y)
  if boundary-.00003<v<boundary+.00006:found[round(v,12)]=y.copy()
  if abs(v-target)<=abs(z-target):z=v
  else:y[a],y[b]=y[b],y[a]
 vals=sorted(found);print(boundary,len(vals),flush=True)
 if len(vals)>80:vals=[vals[i] for i in np.linspace(0,len(vals)-1,80,dtype=int)]
 for v in vals:cases.append((boundary,v,found[v]))
s='options linesize=240 pagesize=10000; data d; input g n x y; datalines;\n'
for g,(_,_,y) in enumerate(cases,1):
 for x,v in enumerate(y,1):s+=f'{g} {n} {x} {int(v)}\n'
s+=';\nods exclude all;ods output HoeffdingCorr=h;proc corr data=d hoeffding;by g n;var x;with y;run;\nods exclude none;data _null_;set h;file print;put "ROW " g best12. n best12. x e25.17 Px e25.17;run;\n'
Path('/private/tmp/dev5-hoeffding-switch.sas').write_text(s)
