"""Lossless compact serialization of discovery failures; no model logic."""
import json
import re


def compact_report(report, old_names, probe_names):
    if report.get('failure_format'):
        return report
    old_index = {name:i for i,name in enumerate(old_names)}
    probe_index = {name:i for i,name in enumerate(probe_names)}
    result = dict(report)
    result['failure_format'] = '[case index, predicted bin, observed bin]'
    result['old_case_order'] = old_names
    result['probe_case_order'] = probe_names
    result['models'] = []
    for row in report['models']:
        converted = dict(row)
        for key,index,names in [('failed_old',old_index,old_names),('failed_probes',probe_index,probe_names)]:
            original = row[key]
            converted['first_'+key] = original[0] if original else None
            converted[key] = [[index[f['name']],f['predicted'],f['observed']] for f in original]
            assert [dict(name=names[i],predicted=p,observed=o) for i,p,o in converted[key]] == original
        result['models'].append(converted)
    return result


def dumps(report):
    encoded = json.dumps(report,indent=2)
    return re.sub(r'("failed_(?:old|probes)": )(\[[-0-9,\s\[\]]*\])',
                  lambda m:m[1]+json.dumps(json.loads(m[2]),separators=(',',':')),encoded)+'\n'
