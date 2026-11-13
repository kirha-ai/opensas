#!/usr/bin/env python3
"""Diagnostic candidate, NOT a SAS UNIVARIATE implementation.

Run with --require-parity to fail on the retained midpoint counterexamples.
Only Python's standard library is needed. No third-party code is incorporated.
"""
import ctypes
import json
import math
from pathlib import Path
import re
import struct
import sys

HERE = Path(__file__).resolve().parent
_fma = ctypes.CDLL(None).fma
_fma.argtypes = [ctypes.c_double] * 3
_fma.restype = ctypes.c_double


def residual(sample):
    n = len(sample)
    mean = sum(sample) / n
    sigma = math.sqrt(sum((v - mean) ** 2 for v in sample) / n)
    if n < 2 or not sigma > 0:
        raise ValueError('degenerate sample')

    def psi(h, order):
        total = 0.0
        for u in sample:
            for v in sample:
                z = (u - v) / h
                poly = (z**4 - 6*z*z + 3) if order == 4 else (z**6 - 15*z**4 + 45*z*z - 15)
                total += poly * math.exp(-z*z/2) / math.sqrt(2*math.pi)
        return total / (n*n*h**(order+1))

    a = (32 / (5*math.sqrt(2))) ** (1/7) * sigma * n ** (-1/7)
    b = (64 / (7*math.sqrt(2))) ** (1/9) * sigma * n ** (-1/9)
    ratio = psi(a, 4) / -psi(b, 6)
    if not ratio > 0:
        raise ValueError('invalid pilot derivative ratio')
    alpha = (6*math.sqrt(2)*ratio) ** (1/7)

    def f(h):
        roughness = psi(alpha * h ** (5/7), 4)
        if not roughness > 0:
            raise ValueError('nonpositive roughness')
        return (1 / (2*math.sqrt(math.pi)*n*roughness)) ** .2 - h
    return f


def candidate(sample):
    """Candidate's FMA midpoint assignment is DISPROVED by sign.sas."""
    n = len(sample)
    minimum, maximum = min(sample), max(sample)
    step = (maximum-minimum)/200
    if not step > 0:
        raise ValueError('degenerate sample')
    grid = [_fma(i, step, minimum) for i in range(201)]
    indices = [sum(v >= _fma(i+.5, step, minimum) for i in range(200)) for v in sample]
    f = residual([grid[i] for i in indices])
    mean = sum(sample)/n
    sd = math.sqrt(sum((v-mean)**2 for v in sample)/(n-1))
    upper = 6*sd*(1/(70*math.sqrt(math.pi)*n))**.2
    search = [upper/18*18**(j/20) for j in range(21)]
    for j in range(19, -1, -1):
        lo, hi = search[j:j+2]
        if f(lo)*f(hi) <= 0:
            break
    else:
        raise ValueError('no bracket; SAS fallback not established')
    for _ in range(200):
        mid = (lo+hi)/2
        if f(lo)*f(mid) > 0:
            lo = mid
        else:
            hi = mid
        if hi-lo < .001:
            return mid
    raise ValueError('bisection failed')


def main():
    text = (HERE/'dev2-sjpi-cases.txt').read_text()
    cases = json.loads((HERE/'dev2-sjpi-inputs.json').read_text())
    cs = {int(i): float(c) for i,c in re.findall(r'CASE (\d+) _C_=([0-9.]+)', text)}
    qs = {int(i): float(q) for i,q in re.findall(r'CASE (\d+) n=.*? q=([0-9.]+)', text)}
    # Case 6 is NOT a valid oracle result: SAS raised a floating-point exception
    # and left the preceding WORK.K/WORK.STATS in place. Cases 7/8 are degenerate.
    checked = []
    for i in sorted(cs):
        if i == 6:
            continue
        actual = candidate(cases[i])
        target = cs[i]*qs[i]*len(cases[i])**(-.2)
        checked.append(abs(actual-target))
        print(f'base {i:2}: h={actual:.15g} oracle={target:.15g} abs_error={abs(actual-target):.3g}')
    assert len(checked) == 13 and max(checked) < 1e-10
    print(f'Base comparison: {len(checked)}/13, max absolute h error {max(checked):.3g}')

    inputs = {}
    for i,h in re.findall(r'id=(\d+) x=([0-9A-F]+)', (HERE/'dev2-sjpi-hex.txt').read_text()):
        inputs.setdefault(int(i), []).append(struct.unpack('>d', bytes.fromhex(h))[0])
    # Match actual SAS binary inputs, not decimals recomputed by Python.
    want = {int(i):float(c) for i,c in re.findall(r'id=(\d+) _C_=([0-9.]+)', (HERE/'dev2-sjpi-sign.txt').read_text().split('n4 ')[0])}
    failures = []
    for i,x in sorted(inputs.items()):
        c = candidate(x)/4*len(x)**.2
        error = abs(c-want[i])
        if error >= 1e-10:
            failures.append(error)
            print(f'MISMATCH shift {i:2}: c={c:.15g} oracle={want[i]:.15g} abs_error={error:.6g}')
    print(f'Midpoint comparison: {len(inputs)-len(failures)}/{len(inputs)}; max absolute c error {max(failures, default=0):.6g}')
    print('SUPPORT NOT ACCEPTED: no validated general UNIVARIATE SJPI API.')
    return 1 if failures and '--require-parity' in sys.argv else 0


if __name__ == '__main__':
    sys.exit(main())
