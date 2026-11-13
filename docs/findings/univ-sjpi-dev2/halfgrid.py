#!/usr/bin/env python3
"""Bounded single-half-grid discriminator; not a production SJPI API.

Reuses the unchanged formula/pilot/root solver from the prior investigation.
Reads actual SAS hex inputs and determines each point's bin by forcing BOTH
assignments and comparing the resulting bandwidth with SAS. Neither decisions
nor oracle bandwidths are hardcoded into the arithmetic predictors.

Default exit 0 means the discriminator completed, not that SJPI is accepted.
--require-parity exits 1 while all arithmetic candidates have counterexamples.
"""
import json,math,re,struct,sys
import compare as reference
from pathlib import Path
fma=reference._fma
HERE=Path(__file__).resolve().parent
def forced(x,k,point,right):
 lo,hi=min(x),max(x);d=(hi-lo)/200;grid=[fma(i,d,lo) for i in range(201)]
 indices=[int((v-lo)/d+.5) for v in x];indices[point]=k+right
 f=reference.residual([grid[i] for i in indices]);n=len(x);mean=sum(x)/n;sd=math.sqrt(sum((v-mean)**2 for v in x)/(n-1))
 upper=6*sd*(1/(70*math.sqrt(math.pi)*n))**.2
 search=[upper/18*18**(j/20) for j in range(21)]
 for j in range(19,-1,-1):
  a,b=search[j:j+2]
  if f(a)*f(b)<=0:break
 else:raise ValueError('no bracket')
 for _ in range(200):
  h=(a+b)/2
  if f(a)*f(h)>0:a=h
  else:b=h
  if b-a<.001:return h
 raise ValueError('nonconvergence')

def predict(x,k,point):
 v=x[point];lo,hi=min(x),max(x);d=(hi-lo)/200;inv=1/d
 expr={'center_div':(v-lo)/d,'center_inverse':(v-lo)*inv,'absolute_div':v/d-lo/d,'absolute_inverse':v*inv-lo*inv,'normalized':(v-lo)/(hi-lo)*200,'normalized_abs':(v/(hi-lo)-lo/(hi-lo))*200}
 out={}
 for name,z in expr.items():
  out[name+'_half_up']=int(z+.5)>k
  out[name+'_ties_even']=round(z)>k
 out['center_inverse_fma']=int(fma(v-lo,inv,.5))>k
 out['absolute_inverse_fma']=int(fma(v,inv,.5-lo*inv))>k
 boundaries={'index_product':lo+(k+.5)*d,'index_fma':fma(k+.5,d,lo),'center_plus_half':lo+k*d+d/2,'fma_center_plus_half':fma(k,d,lo)+d/2,'shifted_origin':lo+d/2+k*d,'shifted_origin_fma':fma(k,d,lo+d/2),'normalized_index':lo+(k+.5)/200*(hi-lo),'normalized_fma':fma((k+.5)/200,hi-lo,lo)}
 a=lo+d/2
 for _ in range(k):a+=d
 boundaries['repeated_edges']=a
 grid=[lo]
 for _ in range(200):grid.append(grid[-1]+d)
 boundaries['repeated_centers']=(grid[k]+grid[k+1])/2
 boundaries['index_centers']=(lo+k*d+lo+(k+1)*d)/2
 boundaries['fma_centers']=(fma(k,d,lo)+fma(k+1,d,lo))/2
 for name,b in boundaries.items():
  out[name+'_up']=v>=b;out[name+'_down']=v>b
 out['repeated_nearest_up']=abs(v-grid[k])>=abs(grid[k+1]-v)
 out['repeated_nearest_down']=abs(v-grid[k])>abs(grid[k+1]-v)
 return out

def batches():
    for stem in ['dev2-sjpi-halfgrid','dev2-sjpi-halfgrid-heldout','dev2-sjpi-halfgrid-background','dev2-sjpi-halfgrid-background-left','dev2-sjpi-halfgrid-profile','dev2-sjpi-halfgrid-zero']:
        cases=json.loads((HERE/(stem+'-inputs.json')).read_text())
        text=(HERE/(stem+'.txt')).read_text()
        actual={}
        for i,p,h in re.findall(r'INPUT id=(\d+) point=(\d+) x=([A-F0-9]+)',text):
            actual.setdefault(int(i),[]).append(struct.unpack('>d',bytes.fromhex(h))[0])
        stats={int(i):(int(n),float(q),float(sd)) for i,n,q,sd in re.findall(r'STATS id=(\d+) n=([0-9.]+) q=([0-9.E+-]+) sd=([0-9.E+-]+)',text)}
        cs={int(i):float(c) for i,c in re.findall(r'RESULT id=(\d+) _C_=([0-9.E+-]+)',text)}
        yield stem,cases,actual,stats,cs


def main():
    scores={}; totals={}; errors=[]; decisions=[]
    for stem,cases,actual,stats,cs in batches():
        for row in cases:
            i=row['id']; x=actual[i]
            assert x==row['values'], 'SAS hex input differs from supplied bits'
            point=x.index(row['target']); k=row['k']; n,q,sd=stats[i]
            target=cs[i]*q*n**(-.2)
            hs=[forced(x,k,point,b) for b in [0,1]]
            matched=[b for b,h in enumerate(hs) if abs(h-target)<1e-10]
            assert len(matched)==1, (stem,i,'assignment is not uniquely identifiable',hs,target)
            answer=matched[0]; errors.append(abs(hs[answer]-target))
            category={'dev2-sjpi-halfgrid':'discovery','dev2-sjpi-halfgrid-background':'background','dev2-sjpi-halfgrid-background-left':'background_left','dev2-sjpi-halfgrid-profile':'profile','dev2-sjpi-halfgrid-zero':'zero'}.get(stem, 'heldout' if i<12 else 'transition')
            totals[category]=totals.get(category,0)+1
            out=predict(x,k,point)
            lo=min(x); step=(max(x)-lo)/200
            # Frozen after discovery: best candidate among the tested
            # centering/reconstruction arithmetic orders. It is NOT accepted.
            out['center_recombine_fma_up']=((x[point]-lo)+lo)>=fma(k+.5,step,lo)
            for name,val in out.items():
                scores.setdefault(name,{})
                scores[name].setdefault(category,0)
                scores[name][category]+=val==answer
            decisions.append((category,i,k,row['direction'],answer))
            print(f'{category:10} id={i:2} k={k:3} ULP={row["direction"]:3} bin={k+answer:3} '
                  f'left_h={hs[0]:.15g} right_h={hs[1]:.15g} oracle_h={target:.15g} '
                  f'target_hex={struct.pack(">d",x[point]).hex().upper()}')
    assert len(decisions)==136
    print(f'\nUnique forced-bin matches: 136/136; max |h-oracle|={max(errors):.6g}; tolerance=1e-10')
    print('\nArithmetic candidate           discovery heldout transition background background_left profile zero total')
    for name,ss in sorted(scores.items(),key=lambda r:(-sum(r[1].values()),r[0])):
        print(f'{name:33} '+' '.join(f'{ss[c]:2}/{totals[c]}' for c in totals)+f' {sum(ss.values()):3}/136')
    print('\nSUPPORT NOT ACCEPTED: none of these fixed arithmetic candidates explains all bin decisions.')
    if '--require-parity' in sys.argv and max(sum(ss.values()) for ss in scores.values())<136:
        return 1
    return 0


if __name__=='__main__':
    sys.exit(main())
