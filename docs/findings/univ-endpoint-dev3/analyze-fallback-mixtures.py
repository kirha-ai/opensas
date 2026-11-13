"""Evaluate frozen predictions against exact M9 observations/estimates."""
from pathlib import Path
import json,re,struct,importlib.util
root=Path(__file__).parent
spec=importlib.util.spec_from_file_location('model',root/'power-fallback-model.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
inputs={};params={}
for line in (root/'fallback-mixtures.log').read_text().splitlines():
    if line.startswith('DEV3_SAMPLE_CASE '):sc=line.split()[1];inputs[sc]=[]
    found=re.fullmatch(r'DEV3_SAMPLE\s+([0-9A-F]{16})',line)
    if found:inputs[sc].append(struct.unpack('>d',bytes.fromhex(found[1]))[0])
    if line.startswith('DEV3_CASE '):case=line.split()[1];params[case]={}
    found=re.fullmatch(r'DEV3_PARAMETER (Theta|Sigma|Alpha)\s+([0-9A-F]{16})',line)
    if found:params[case][found[1].lower()]=struct.unpack('>d',bytes.fromhex(found[2]))[0]
rows=[]
for c in json.loads((root/'fallback-mixtures-inputs.json').read_text()):
    actual=m.model(inputs[c['id']],c['theta'],c['alpha']);p=params[c['id']]
    r={**c,'exact_samples':inputs[c['id']],'actual_input_prediction':actual,'oracle_curve':bool(p),'parameters':p}
    r['current_helper_curve']=actual.get('feasible',False) and (c['alpha'] is not None or (actual.get('four_moment_valid',False) and actual.get('positive_start',False)))
    if p:
        r['sigma_residual']=p['sigma']-actual['sigma']
        r['alpha_residual']=p['alpha']-(c['alpha'] if c['alpha'] is not None else actual['conditional_alpha'])
    rows.append(r)
for policy in ['positive_start','two_moment_newton','default_one_newton','capped_start_newton']:
    errors=[r['id'] for r in rows if (r['actual_input_prediction'].get('feasible',False) and r['actual_input_prediction'].get(policy,False))!=r['oracle_curve']]
    print(policy,len(errors),errors)
for r in rows:print(r['id'],r['group'],'4mom',r['actual_input_prediction'].get('four_moment_valid'),'a0',r['actual_input_prediction'].get('two_moment_alpha'),'MLE',r['actual_input_prediction'].get('conditional_alpha'),'oracle',r['parameters'])
(root/'fallback-mixtures-audit.json').write_text(json.dumps(rows,indent=2,allow_nan=False)+'\n')

print('Current helper schematic mismatches',sum(r['current_helper_curve']!=r['oracle_curve'] for r in rows))
print('Four-moment-valid cases',sum(r['actual_input_prediction'].get('four_moment_valid',False) for r in rows))
