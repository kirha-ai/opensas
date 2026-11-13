"""Padded-grid hypothesis, not a production selector.

Every prediction uses only x, low and high; never a measured index/threshold.
All operations store binary64 except the explicitly fused center operation.
"""
from functools import lru_cache
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent/'absolute-grid'))
from grids import fma
sys.path.insert(0, str(Path(__file__).resolve().parent.parent/'extended-precision'))
from binary_model import Arithmetic, nearest_integer

ORIGINS = ('fingerprint', 'direct_half_range')
SPACINGS = ('original_range', 'padded_endpoints')
DECISIONS = ('q_div_up', 'q_div_even', 'q_inverse_up', 'q_inverse_even',
             'ratio_one_even_binary64', 'ratio_one_even_extended64') + tuple(
    center+'_'+decision for center in ('relative', 'absolute', 'absolute_fma', 'relative_fraction')
    for decision in ('distance_left', 'distance_right', 'midpoint_left', 'midpoint_right'))


def parameters(low, high, origin_method, spacing_method):
    r = high-low
    if origin_method == 'fingerprint':
        lower_padding = low-r
        upper_padding = high+r
        origin = (lower_padding+low)/2
        upper = (upper_padding+high)/2
    else:
        origin = low-r/2
        upper = high+r/2
    step = r/200 if spacing_method == 'original_range' else (upper-origin)/400
    return dict(low=low, high=high, range=r, origin=origin, upper=upper, step=step)


@lru_cache(maxsize=None)
def grid(low, high, origin_method, spacing_method, representation):
    p = parameters(low, high, origin_method, spacing_method)
    o, d = p['origin'], p['step']
    if representation == 'relative_fraction':
        values = tuple((j/400)*(p['upper']-o) for j in range(401))
    elif representation == 'relative':
        values = tuple(j*d for j in range(401))
    elif representation == 'absolute':
        values = tuple((o+j*d)-o for j in range(401))
    else:
        assert representation == 'absolute_fma'
        values = tuple(fma(j, d, o)-o for j in range(401))
    assert all(math.isfinite(v) for v in values)
    assert all(a < b for a, b in zip(values, values[1:]))
    return values


def padded_index(x, low, high, origin_method, spacing_method, decision):
    p = parameters(low, high, origin_method, spacing_method)
    z = x-p['origin']
    d = p['step']
    if decision.startswith('ratio_one_even_'):
        # The offset itself is stored binary64; only this complete normalized
        # one-based index expression varies in retained precision.
        arithmetic = Arithmetic('extended64' if decision.endswith('extended64') else 'binary64')
        span = p['upper']-p['origin']
        fraction = arithmetic.op('/', z, span)
        one_based = arithmetic.op('+', arithmetic.op('*', fraction, 400), 1)
        return nearest_integer(one_based)-1
    if decision.startswith('q_'):
        q = z/d if decision.startswith('q_div') else z*(1/d)
        return int(q+.5) if decision.endswith('_up') else round(q)
    if decision.startswith('relative_fraction_'):
        representation, rule = 'relative_fraction', decision[len('relative_fraction_'):]
    elif decision.startswith('absolute_fma_'):
        representation, rule = 'absolute_fma', decision[len('absolute_fma_'):]
    elif decision.startswith('absolute_'):
        representation, rule = 'absolute', decision[len('absolute_'):]
    else:
        representation, rule = 'relative', decision[len('relative_'):]
    values = grid(low, high, origin_method, spacing_method, representation)
    if rule.startswith('distance'):
        # Full 401-center search; the target's observed k is not available.
        if rule.endswith('right'):
            return min(range(401), key=lambda j:(abs(z-values[j]), -j))
        return min(range(401), key=lambda j:(abs(z-values[j]), j))
    edges = tuple((a+b)/2 for a, b in zip(values, values[1:]))
    if rule.endswith('right'):
        return sum(z >= edge for edge in edges)
    return sum(z > edge for edge in edges)


def counts(values, origin_method, spacing_method, decision):
    low, high = min(values), max(values)
    p = parameters(low, high, origin_method, spacing_method)
    indices = [padded_index(v, low, high, origin_method, spacing_method, decision) for v in values]
    bins = [0]*201
    for j in indices:
        if not 100 <= j <= 300:
            raise ValueError(f'Nonempty padding cannot be dropped: padded index {j}')
        bins[j-100] += 1
    assert sum(bins) == len(values)
    return p, indices, bins
