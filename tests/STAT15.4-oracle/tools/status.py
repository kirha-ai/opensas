#!/usr/bin/env python3
"""Summarize the reference archive and refresh its human-readable case index."""
from collections import Counter
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def refresh():
 d=json.loads((ROOT/'oracle-manifest.json').read_text());counts=Counter();tc=Counter()
 for t in d['tickets']:
  cases=t['cases'];tc['total']+=1;tc['authored']+=bool(cases);tc['captured']+=bool(cases) and all(c.get('status')=='captured' for c in cases)
  for c in cases:counts[c.get('status','draft')]+=1
  rows=[f"# {t['ticket']} — {t['title']}",'','## Source','',t['source'],'','## Scope','',t['scope'],'','## Acceptance criteria','',t['acceptance_criteria'],'','## Cases','']
  if cases:
   rows+=['| Program | Status | SAS status | Expected listing | Discriminates |','|---|---|---:|---|---|']
   for c in cases:
    expected=f"[listing]({c['expected_listing']}) / [log]({c['expected_log']})" if c.get('status')=='captured' else 'Pending capture'
    rows.append(f"| [{c['source']}]({c['source']}) | {c['status']} | {c.get('last_observed_sas_status','—')} | {expected} | {c['covers'].replace('|','/')} |")
   for c in cases:
    if c.get('coverage_note'):rows+=['',f"**{c['case']}:** {c['coverage_note']}"]
  else:rows+=['Pending case authoring and real SAS capture. No expected output has been fabricated.']
  rows+=['','A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.','']
  (ROOT/t['ticket']/'README.md').write_text('\n'.join(rows))
 rcs=Counter(c.get('last_observed_sas_status') for t in d['tickets'] for c in t['cases'] if c.get('status')=='captured')
 text=f'''# SAS/STAT 15.4 ticket oracle cases

Reference: SAS/STAT 15.4 User’s Guide. Runtime verified as SAS {d['sas_version']}, SAS/STAT {d['sas_stat_version']}.

Current progress: {tc['authored']}/{tc['total']} tickets have authored cases; {tc['captured']} tickets have all authored cases captured. Case statuses: {dict(counts)}. Native SAS results: {rcs.get(0,0)} clean, {rcs.get(1,0)} with preserved warnings, and {rcs.get(2,0)} intentional negative cases. These are reference captures, not OpenSAS implementation test results.

Each directory is named after its ticket in [stat-jira.md](../../stat-jira.md). Its README records source PDF pages, scope, and the precise behavior each program discriminates.

## Artifacts

- `case.sas`: a standalone program, normally with input in DATALINES or a documented SASHELP data set. [inputs.md](inputs.md) indexes the public data dependencies. Each case resets WORK, ODS, variable naming, and locale. Batch capture shares a SAS session; each source can also run on its own.
- `case.expected.txt`: the actual text listing returned by real SAS. An empty listing is allowed only where the case explicitly expects no listing.
- `case.oracle.log`: the actual SAS log, including ODS TRACE paths and diagnostics where requested.
- `case.expected.rc`: sasrun status: 0 clean, 1 warning, 2 SAS error. These are SAS runner statuses, not OpenSAS exit-code meanings.
- `case.expected.diagnostics.txt`: ERROR/WARNING lines, when present.
- `oracle-manifest.json`: source references, case intent, capture status, source hashes, versions, and provenance. A capture does not imply exhaustive ticket coverage.

Expected results are never manufactured from the manual or OpenSAS. Unexpected program errors and connection failures go under `_attempts/` for repair and are not accepted as expected outputs. Negative cases explicitly declare their allowed SAS error status.

## Capture or resume

```sh
python3 tests/STAT15.4-oracle/tools/capture.py --ticket 'STAT-TTEST-*'
python3 tests/STAT15.4-oracle/tools/capture.py
python3 tests/STAT15.4-oracle/tools/status.py
```

The capture tool calls `/Users/argos/saspy/bin/sasrun CASE.sas -f text --json` in a shared session, preserving each returned listing and log separately. This is equivalent to capturing stdout from the user-supplied `-f text -o -` invocation; no mock mode is used. Fixed-width listings retain their original whitespace. Source hashes make capture resumable after program edits.

## Archive verification

[SHA256SUMS](SHA256SUMS) seals the captured SAS sources, listings, logs, return codes, and diagnostic files. [replay-audit.json](replay-audit.json) records eight sampled cases replayed in three fresh SAS sessions, including standalone Bayesian and traditional graphics programs. All sampled listings, SAS statuses, and diagnostics matched exactly. The audit is a sample, not an independent-session replay of every case.

## Scope and coverage

These are draft fixtures, not a declaration that every acceptance criterion is tested. Some tickets currently have a baseline procedure example; statement variants and edge cases remain to be expanded. [coverage.md](coverage.md) lists these limitations explicitly. Numerical examples can include real SAS warnings about convergence or nonidentifiability; read their logs before treating estimates as a valid fitted model.

Sources use one-based physical PDF pages, matching the backlog. Program comments identify the ticket sources; the manifest additionally records the example pages used for each adaptation. Inputs are inline public/manual data, seeded synthetic data, or installed public SASHELP data. The large PDF itself and extracted chapter text are not copied into this archive.

Validate the archive without connecting to SAS:

```sh
python3 tests/STAT15.4-oracle/tools/validate.py
```

Listings and logs are preserved as returned. Dates, WORK paths, log line/page counters, timing tables, and platform-dependent floating-point details can vary on replay. Compare the relevant tables and diagnostics with justified numerical tolerances; raw log byte equality is not an acceptance rule.

## Remaining verification

Text references cover numerical listings, data set dumps, and diagnostics. Graphics tickets also need image artifacts for full visual verification; a text listing or ODS TRACE alone is not a visual oracle. Design-only and external UI tickets require explicit observable case scope rather than artificial expected files.
'''
 (ROOT/'README.md').write_text(text)
 gaps=['# Draft coverage notes','','Captured means the program ran on real SAS and its artifacts were stored. It does not mean the ticket is fully tested. This index is based on the authored case notes; statement-token checks are only an aid to review, not a semantic coverage proof.','','| Ticket | Draft limitations |','|---|---|']
 for t in d['tickets']:
  first=t['cases'][0] if t['cases'] else {}
  req=set(first.get('requested_statements',[]));ex=set(first.get('exercised_statement_tokens',[]))
  for c in t['cases']:ex.update(c.get('targeted_statements',[]))
  missing=sorted(req-ex);notes=[]
  if first.get('covers','').startswith('Verified default'):notes.append('Includes a baseline procedure context; expand ticket-specific variants.')
  if missing:notes.append('Statements still needing a dedicated case: '+', '.join(missing)+'.')
  if t['ticket'].startswith(('STAT-GRAPHICS-','STAT-KM-','STAT-TEMPLATE-')):notes.append('Full visual/template behavior requires image or template comparisons beyond text capture.')
  if t['ticket'].startswith('STAT-APP-'):notes.append('CLI/backend scope only; interactive application behavior requires a UI test.')
  if notes:gaps.append(f"| [{t['ticket']}]({t['ticket']}/README.md) | {' '.join(notes)} |")
 gaps+=['','All other tickets also retain the scope limits stated in their case READMEs. An example is not exhaustive coverage of options, missing data, invalid requests, numerical boundaries, or graphical output.','']
 (ROOT/'coverage.md').write_text('\n'.join(gaps))
 print(json.dumps({'tickets':dict(tc),'cases':dict(counts)},ensure_ascii=False))
if __name__=='__main__':refresh()
