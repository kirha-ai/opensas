#!/usr/bin/env python3
"""Independently run the unchanged GLM003 case using the shared strict validator."""
import argparse
import importlib.util
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--binary', default='zig-out/bin/opensas')
parser.add_argument('--output-dir', default='.zig-cache/stat-glm-003-evidence/verified')
args = parser.parse_args()
sys.dont_write_bytecode = True
contract = Path(__file__).resolve().parent.parent / 'STAT-GLM-001' / 'verify.py'
spec = importlib.util.spec_from_file_location('glm_original_contract', contract)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.CASES = [('STAT-GLM-003', 'documented_feature', 3)]
module.verify(args.binary, Path(args.output_dir))
