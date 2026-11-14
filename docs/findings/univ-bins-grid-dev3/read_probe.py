from pathlib import Path
import struct

def read(path):
    tables={};schemas={}
    records=[]; pending=None
    for line in Path(path).read_text().splitlines():
        if line.startswith('DEV3_'):
            if pending is not None:records.append(pending)
            pending=line
        elif pending is not None:
            if line.startswith('NOTE:') or line.startswith('WARNING:') or line.startswith('ERROR:'):
                records.append(pending);pending=None
            elif line.strip() and 'The SAS System' not in line:
                pending+=line.strip()
    if pending is not None:records.append(pending)
    for line in records:
        p=[x.strip() for x in line.split('|')]
        if p[0]=='DEV3_META':schemas.setdefault(p[1],[]).append(p[2:])
        elif p[0] in ['DEV3_N','DEV3_C']:
            value=(None if p[4]=='.' else struct.unpack('>d',bytes.fromhex(p[4]))[0]) if p[0]=='DEV3_N' else p[4]
            tables.setdefault(p[1],{}).setdefault(int(p[2]),{})[p[3]]=value
    return {k:list(v.values()) for k,v in tables.items()},schemas
if __name__=='__main__':
    t,s=read(Path(__file__).parent/'constants-grid.log')
    for name,rows in t.items():
        if name.startswith('h'):print(name,rows)
        elif name.startswith('k'):print(name,len(rows),'range',rows[0].get('_VALUE_'),rows[-1].get('_VALUE_'),'first',rows[:2])
    for name in ['h0_mid','h0_end','hgrid0','hgrid7','kgrid0','kgrid8']:
        print('SCHEMA',name,s.get(name))
