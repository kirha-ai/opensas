#!/usr/bin/env python3
"""Capture real SAS listings through sasrun; resume without replacing verified files."""
import argparse
from datetime import datetime,timezone
import fnmatch
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
MANIFEST=ROOT/'oracle-manifest.json'
DIAG=re.compile(r'^[\x0c\x14]?(?:ERROR|WARNING)(?: \d+-\d+)?:.*$',re.M)

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
UPDATED=set()
def save(data):
 latest=json.loads(MANIFEST.read_text()) if MANIFEST.exists() else data
 lookup={t['ticket']:t for t in latest['tickets']}
 for ticket in data['tickets']:
  target=lookup[ticket['ticket']]
  for case in ticket['cases']:
   if (ticket['ticket'],case['case']) not in UPDATED:continue
   old=next((c for c in target['cases'] if c['case']==case['case']),None)
   if old:target['cases'][target['cases'].index(old)]=case
   else:target['cases'].append(case)
  target['status']='captured' if target['cases'] and all(c.get('status')=='captured' for c in target['cases']) else ('pending_capture' if target['cases'] else 'pending_authoring')
 data=latest
 tmp=MANIFEST.with_suffix('.json.tmp');tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');tmp.replace(MANIFEST)
 UPDATED.clear()
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--ticket',action='append',help='ticket ID or glob; repeatable')
 p.add_argument('--limit',type=int)
 p.add_argument('--force',action='store_true')
 p.add_argument('--status',action='append',choices=['draft','needs_repair','capture_failed','captured'],help='capture only these case states')
 p.add_argument('--sasrun',default='/Users/argos/saspy/bin/sasrun')
 p.add_argument('--timeout',type=int,default=90)
 args=p.parse_args();data=json.loads(MANIFEST.read_text());pending=[]
 for t in data['tickets']:
  if args.ticket and not any(fnmatch.fnmatchcase(t['ticket'],pat) for pat in args.ticket):continue
  for case in t['cases']:
   if args.status and case.get('status','draft') not in args.status:continue
   src=ROOT/t['ticket']/case['source']
   if not args.force and case.get('status')=='captured' and case.get('source_sha256')==digest(src):continue
   pending.append((t,case,src))
 if args.limit:pending=pending[:args.limit]
 if not pending:print('No pending authored cases.');return 0
 print(f'Capturing {len(pending)} cases in one real SAS session.',flush=True)
 index={str(src):(t,c,src) for t,c,src in pending}
 submitted_hashes={str(src):digest(src) for t,c,src in pending}
 cmd=[args.sasrun,*index,'-f','text','--json','--timeout',str(args.timeout)]
 failures=0;seen=set()
 proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
 try:
  for line in proc.stdout:
   try:rec=json.loads(line)
   except json.JSONDecodeError:continue
   key=rec.get('file')
   if key not in index:continue
   t,case,src=index[key];seen.add(key);rc=rec.get('exit_code',3)
   diagnostics=DIAG.findall(rec.get('log',''))
   source_unchanged=digest(src)==submitted_hashes[key]
   acceptable=source_unchanged and not rec.get('error') and not rec.get('log_truncated') and not rec.get('lst_truncated') and rc in case.get('allowed_sas_status',[0])
   if re.search(r'(?im)^NOTE: (?:Invalid data|LOST CARD|Variable .+ is uninitialized)',rec.get('log','')) and not case.get('allows_invalid_data',False):acceptable=False
   if any(not re.search(pattern,rec.get('log',''),re.I) for pattern in case.get('required_diagnostics',[])):acceptable=False
   if case.get('listing_required',True) and not rec.get('lst','').strip():acceptable=False
   case['last_observed_sas_status']=rc
   case['diagnostics']=diagnostics
   if acceptable:
    stem=src.with_suffix('')
    stem.with_suffix('.expected.txt').write_text(rec.get('lst') or '')
    stem.with_suffix('.oracle.log').write_text(rec.get('log') or '')
    stem.with_suffix('.expected.rc').write_text(str(rc)+'\n')
    if diagnostics:stem.with_suffix('.expected.diagnostics.txt').write_text('\n'.join(diagnostics)+'\n')
    elif stem.with_suffix('.expected.diagnostics.txt').exists():stem.with_suffix('.expected.diagnostics.txt').unlink()
    case.pop('failure',None)
    prior_attempt=ROOT/'_attempts'/t['ticket']/(src.stem+'.json')
    if prior_attempt.exists():prior_attempt.unlink()
    case.update(status='captured',source_sha256=digest(src),captured_at=datetime.now(timezone.utc).isoformat(),elapsed_seconds=rec.get('elapsed'),expected_listing=stem.name+'.expected.txt',expected_log=stem.name+'.oracle.log',expected_rc=stem.name+'.expected.rc')
   else:
    attempt=ROOT/'_attempts'/t['ticket'];attempt.mkdir(parents=True,exist_ok=True)
    (attempt/(src.stem+'.json')).write_text(json.dumps(rec,ensure_ascii=False,indent=2))
    case['status']='needs_repair' if not rec.get('error') else 'capture_failed'
    case['failure']=rec.get('error') or {'diagnostics':diagnostics,'listing_empty':not bool(rec.get('lst','').strip())}
    for suffix in ['.expected.txt','.expected.rc','.expected.diagnostics.txt']:
     stale=src.with_suffix(suffix)
     if stale.exists():stale.unlink()
    failures+=1
   t['status']='captured' if t['cases'] and all(c.get('status')=='captured' for c in t['cases']) else 'pending_capture'
   UPDATED.add((t['ticket'],case['case']))
   save(data)
   print(f"{len(seen)}/{len(pending)} {t['ticket']}/{src.name}: {case['status']} (SAS status {rc})",flush=True)
  proc.wait()
 finally:
  if proc.poll() is None:proc.terminate();proc.wait(timeout=20)
  stderr=proc.stderr.read()
  if stderr:(ROOT/'capture.stderr.log').write_text(stderr)
  save(data)
 print(f'Captured {len(seen)-failures}; failed {failures}; not run {len(pending)-len(seen)}.',flush=True)
 return int(failures or len(seen)!=len(pending))
if __name__=='__main__':sys.exit(main())
