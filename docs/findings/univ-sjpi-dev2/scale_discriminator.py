#!/usr/bin/env python3
"""Rejected coordinate-preconditioning hypotheses; fixed SJPI math is unchanged.

Uses exact SAS statistic bits. No predictor here is used by the Zig helper.
--require-parity fails unless one candidate matches every retained decision.
"""
from pathlib import Path
import json, math, re, struct, sys
from compare import _fma as fma
HERE = Path(__file__).resolve().parent
metas=json.load((HERE/'dev2-sjpi-halfgrid-stathex-inputs.json').open());raw=(HERE/'dev2-sjpi-halfgrid-scalehex.txt').read_text()
stat={}
for line in raw.splitlines():
 mm=re.search(r'id=(\d+) n=(\d+)',line)
 if not mm:
  mid=re.search(r'id=(\d+)',line)
  if mid:stat[int(mid[1])].update({k:struct.unpack('>d',bytes.fromhex(h))[0] for k,h in re.findall(r'\b(s1|s2|s3)=([A-F0-9]{16})',line)})
  continue
 stat[int(mm[1])]=dict(n=int(mm[2]),**{k:struct.unpack('>d',bytes.fromhex(h))[0] for k,h in re.findall(r'\b(m|sd|v|q|r)=([A-F0-9]{16})',line)})
rows={};truth={}
for stem in {m['stem'] for m in metas}:
 rows[stem]=json.load((HERE/(stem+'-inputs.json')).open());truth[stem]=json.load((HERE/(stem+'-inferred.json')).open())
scores={};miss={}
for meta in metas:
 r=rows[meta['stem']][meta['id']];s=stat[meta['gid']];want=truth[meta['stem']][meta['id']]['assignment'][0]
 n=s['n'];sig=s['sd'];q=s['q'];span=s['r'];scales={'sd':sig,'pop_var':math.sqrt(s['v']*(n-1)/n),'pop_sd':sig*math.sqrt((n-1)/n),'iqr':q,'normal_iqr':q/1.34898,'normalized_bandwidth':q*n**(-.2),'normal_bw':(q/1.34898)*(4/(3*n))**.2,'os':3*sig*(1/(70*math.sqrt(math.pi)*n))**.2,'range':span,'native_s1':s['s1'],'native_s2':s['s2'],'native_s3':s['s3']}
 for name,scale in scales.items():
  for origin in ['zero','min','mean','naive_mean','centered_mean','midrange']:
   a=0 if origin=='zero' else r['lo'] if origin=='min' else s['m'] if origin=='mean' else sum(r['values'])/n if origin=='naive_mean' else r['lo']+sum(v-r['lo'] for v in r['values'])/n if origin=='centered_mean' else (r['hi']+r['lo'])/2
   for form in ['divide','inverse','separate','fused']:
    def trans(x):
     if form=='divide':return (x-a)/scale
     if form=='inverse':return (x-a)*(1/scale)
     if form=='separate':return x/scale-a/scale
     return fma(x,1/scale,-a/scale)
    l,h,v,k=trans(r['lo']),trans(r['hi']),trans(r['target']),r['k'];d=(h-l)/200;z=(v-l)/d
    pred={'div_up':int(z+.5)>k,'inverse_up':int((v-l)*(1/d)+.5)>k,'div_even':round(z)>k,'one_even':round(z+1)-1>k,'fma_mid_up':v>=fma(k+.5,d,l),'fma_mid_down':v>fma(k+.5,d,l),'fma_nearest_up':v-fma(k,d,l)>=fma(k+1,d,l)-v,'fma_nearest_down':v-fma(k,d,l)>fma(k+1,d,l)-v,'prod_nearest_up':v-(l+k*d)>=(l+(k+1)*d)-v}
    for mode,val in pred.items():
     key=name+'/'+origin+'/'+form+'/'+mode;scores[key]=scores.get(key,0)+(val==want);miss.setdefault(key,[])
     if val!=want:miss[key].append(meta['gid'])
for name,n in sorted(scores.items(),key=lambda r:-r[1])[:12]:print(n,'/',len(metas),name,miss[name][:15])

if '--require-parity' in sys.argv and max(scores.values()) < len(metas):
    sys.exit(1)
