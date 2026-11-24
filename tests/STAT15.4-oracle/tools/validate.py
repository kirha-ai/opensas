#!/usr/bin/env python3
"""Validate fixture inventory and real-SAS capture integrity (no SAS connection)."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allow-pending', action='store_true')
    parser.add_argument('--write-checksums', action='store_true')
    args = parser.parse_args()
    data = json.loads((ROOT / 'oracle-manifest.json').read_text())
    backlog = (ROOT.parents[1] / 'stat-jira.md').read_text()
    wanted = set(re.findall(r'^### \[[^\]]+\] (STAT-[A-Z0-9]+-\d+)\b', backlog, re.M))
    found = [t['ticket'] for t in data['tickets']]
    errors = []
    if set(found) != wanted or len(found) != len(set(found)):
        errors.append('Manifest ticket IDs do not match the backlog exactly.')
    folders = {p.name for p in ROOT.glob('STAT-*') if p.is_dir()}
    if folders != wanted:
        errors.append('Ticket directories do not match the backlog exactly.')
    counts = Counter()
    checksums = []
    expected_sources = set()
    for ticket in data['tickets']:
        directory = ROOT / ticket['ticket']
        if not ticket['cases']:
            errors.append(f"{ticket['ticket']}: no SAS cases")
        if not (directory / 'README.md').is_file():
            errors.append(f"{ticket['ticket']}: no README")
        names = set()
        for case in ticket['cases']:
            label = ticket['ticket'] + '/' + case['source']
            counts[case.get('status', 'draft')] += 1
            if case['case'] in names:
                errors.append(f'{label}: duplicate case name')
            names.add(case['case'])
            source = directory / case['source']
            expected_sources.add(source)
            if not source.is_file():
                errors.append(f'{label}: missing source')
                continue
            checksums.append(source)
            if not case.get('covers') or not case.get('source_pages'):
                errors.append(f'{label}: missing case intent or source pages')
            if case.get('status') != 'captured':
                if not args.allow_pending:
                    errors.append(f'{label}: {case.get("status", "draft")}')
                continue
            attempt = ROOT / '_attempts' / ticket['ticket'] / (source.stem + '.json')
            if attempt.exists():
                errors.append(f'{label}: stale failed-attempt artifact remains')
            if case.get('source_sha256') != sha256(source):
                errors.append(f'{label}: source changed after capture')
            files = {}
            for key in ['expected_listing', 'expected_log', 'expected_rc']:
                name = case.get(key)
                path = directory / name if name else None
                if path is None or not path.is_file():
                    errors.append(f'{label}: missing {key}')
                else:
                    files[key] = path
                    checksums.append(path)
            if len(files) != 3:
                continue
            status = int(files['expected_rc'].read_text().strip())
            if status == 3 or status not in case.get('allowed_sas_status', [0]):
                errors.append(f'{label}: unexpected SAS status {status}')
            if status != case.get('last_observed_sas_status'):
                errors.append(f'{label}: status metadata mismatch')
            listing = files['expected_listing'].read_text()
            log = files['expected_log'].read_text()
            if case.get('listing_required', True) and not listing.strip():
                errors.append(f'{label}: required listing is empty')
            if not log.strip() or not case.get('captured_at'):
                errors.append(f'{label}: missing capture provenance')
            if re.search(r'^NOTE: (?:Invalid data|LOST CARD|Variable .+ is uninitialized)', log, re.M) and not case.get('allows_invalid_data'):
                errors.append(f'{label}: unexpected input-data diagnostic')
            if status < 2 and re.search(r'^ERROR(?: \d+-\d+)?:', log, re.M):
                errors.append(f'{label}: unexpected ERROR in accepted log')
            for pattern in case.get('required_diagnostics', []):
                if not re.search(pattern, log, re.I):
                    errors.append(f'{label}: missing required diagnostic {pattern}')
            diag = source.with_suffix('.expected.diagnostics.txt')
            if diag.exists():
                checksums.append(diag)
    actual_sources = set(ROOT.glob('STAT-*/*.sas'))
    if expected_sources != actual_sources:
        errors.append('SAS source inventory differs from manifest.')
    if (ROOT / 'SHA256SUMS').exists() and not args.write_checksums:
        for line in (ROOT / 'SHA256SUMS').read_text().splitlines():
            digest, name = line.split('  ', 1)
            path = ROOT / name
            if not path.is_file() or sha256(path) != digest:
                errors.append(f'Checksum mismatch: {name}')
    if args.write_checksums:
        if errors or counts.get('captured', 0) != sum(counts.values()):
            errors.append('Refusing to seal incomplete or invalid captures.')
        else:
            text = ''.join(f'{sha256(p)}  {p.relative_to(ROOT)}\n' for p in sorted(set(checksums)))
            (ROOT / 'SHA256SUMS').write_text(text)
    print(json.dumps({'tickets':len(found), 'cases':dict(counts), 'errors':len(errors)}))
    for error in errors[:100]:
        print(error, file=sys.stderr)
    if len(errors) > 100:
        print(f'... and {len(errors)-100} more errors', file=sys.stderr)
    return bool(errors)

if __name__ == '__main__':
    sys.exit(main())
