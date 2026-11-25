#!/usr/bin/env python3
"""Run unchanged GLM001, GLM002 and COMMON006 cases, retaining all evidence."""
from pathlib import Path
import subprocess, re, json, hashlib, difflib, math, xml.etree.ElementTree as ET
import argparse

CASES = [('STAT-GLM-001','documented_feature',3),('STAT-GLM-002','documented_default',3),('STAT-COMMON-006','class_order',0)]

def verify(binary, output):
    output.mkdir(parents=True, exist_ok=True)
    records=[]
    for ticket,stem,graph_count in CASES:
        root=Path(__file__).resolve().parent.parent/ticket
        expected=(root/(stem+'.expected.txt')).read_bytes()
        r=subprocess.run([binary,str(root/(stem+'.sas'))],capture_output=True,text=True)
        (output/(ticket+'.actual.txt')).write_text(r.stdout)
        (output/(ticket+'.actual.log')).write_text(r.stderr)
        (output/(ticket+'.diff')).write_text('\n'.join(difflib.unified_diff(expected.decode().split(),r.stdout.split(),fromfile='SAS expected',tofile='OpenSAS actual',lineterm='')))
        wanted=int((root/(stem+'.expected.rc')).read_text().strip())
        assert r.returncode==wanted==0,(ticket,r.returncode,r.stderr)
        assert expected.decode().split()==r.stdout.split(),ticket
        paths=re.findall(r'^NOTE: SVG graphic written to (.+\.svg)\.$',r.stderr,re.M)
        assert len(paths)==graph_count,(ticket,r.stderr)
        assert len(r.stderr.splitlines())==graph_count,(ticket,'unexpected diagnostic',r.stderr)
        graphs=[]
        for path in paths:
            svg=ET.parse(path).getroot()
            name='IntPlot' if 'glm-interaction' in path else 'FitPlot' if 'glm-fit' in path else 'ScatterPlot'
            points=[e for e in svg.iter() if e.attrib.get('data-kind')=='observed' or e.attrib.get('class')=='point']
            assert len(points)==(7 if name=='IntPlot' else 13),(name,len(points))
            assert all(math.isfinite(float(e.attrib['data-x'])) and math.isfinite(float(e.attrib['data-y'])) for e in points)
            if name=='IntPlot':
                predicted=[float(e.attrib['data-predicted']) for e in points]
                for actual,reference in zip(predicted,[13,13,10,10,19,19,17]):
                    assert abs(actual-reference)<=128*2**-52*max(1,abs(reference))
                assert sum(e.attrib.get('data-kind')=='group-fit' for e in svg.iter())==2
            if name=='FitPlot':
                curve=[e for e in svg.iter() if 'data-lclm' in e.attrib]
                assert len(curve)==101
                for e in curve:
                    values=[float(e.attrib[k]) for k in ['data-lcli','data-lclm','data-predicted','data-uclm','data-ucli']]
                    assert all(math.isfinite(v) for v in values) and values==sorted(values)
            graphs.append(dict(name=name,path=path,observations=len(points),sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest()))
            if ticket=='STAT-GLM-001': (output/(name+'.svg')).write_bytes(Path(path).read_bytes())
        records.append(dict(ticket=ticket,expected_status=wanted,actual_status=r.returncode,expected_tokens=len(expected.decode().split()),actual_tokens=len(r.stdout.split()),exact_whitespace_match=True,expected_sha256=hashlib.sha256(expected).hexdigest(),stderr=r.stderr,graphics=graphs))
    result=dict(sha=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),version=subprocess.check_output([binary,'--version'],text=True).strip(),normalization='whitespace tokenization only; no numeric substitutions or tolerances for listings',cases=records)
    (output/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(sha=result['sha'],cases=[dict(ticket=r['ticket'],status=r['actual_status'],tokens=r['actual_tokens'],graphs=len(r['graphics'])) for r in records]),indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--binary',default='zig-out/bin/opensas');parser.add_argument('--output-dir',default='.zig-cache/stat-glm-001-evidence/verified');args=parser.parse_args();verify(args.binary,Path(args.output_dir))
