"""Export oracle-backed fixed-theta regressions; include the known unresolved row."""
from pathlib import Path
import json,re,struct
root=Path(__file__).parent
out=['# case|theta|fixed_alpha|oracle_sigma|oracle_alpha|sample values']
for name,metadata in [('scale-grid','scale-grid-inputs'),('controlled-grid','controlled-grid-inputs'),('prospective-power','prospective-power-inputs'),('initialization-edges','initialization-edges-inputs')]:
    inputs={};params={}
    for line in (root/(name+'.log')).read_text().splitlines():
        if line.startswith('DEV3_SAMPLE_CASE '):sc=line.split()[1];inputs[sc]=[]
        m=re.fullmatch(r'DEV3_SAMPLE\s+([0-9A-F]{16})',line)
        if m:inputs[sc].append(struct.unpack('>d',bytes.fromhex(m[1]))[0])
        if line.startswith('DEV3_CASE '):case=line.split()[1];params[case]={}
        m=re.fullmatch(r'DEV3_PARAMETER (Theta|Sigma|Alpha)\s+([0-9A-F]{16})',line)
        if m:params[case][m[1].lower()]=struct.unpack('>d',bytes.fromhex(m[2]))[0]
    for c in json.loads((root/(metadata+'.json')).read_text()):
        if c.get('family','power')!='power' or ('theta' in c and c['theta'] is None):continue
        p=params[c['id']];x=inputs[c['id']]
        fmt=lambda v:format(v,'.17g') if v is not None else 'est'
        out.append('|'.join([c['id'],fmt(c.get('theta',0)),fmt(c.get('alpha')),fmt(p.get('sigma')),fmt(p.get('alpha')),','.join(fmt(v) for v in x)]))
target=root.parents[2]/'src/stat/testdata/univ_endpoint_power_dev3_cases.txt'
target.parent.mkdir(exist_ok=True)
target.write_text('\n'.join(out)+'\n')
print('Oracle cases:',len(out)-1)
