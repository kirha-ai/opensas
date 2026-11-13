"""Frozen absolute-center candidates; every center is stored as binary64.

No normalized-q decision, fitted tolerance, extended-precision schedule or
measured-threshold table is used. Exact rational arithmetic implements only
the specified correctly rounded binary64 fused multiply-add.
"""
from fractions import Fraction as F
from functools import lru_cache
from pathlib import Path
import math
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent/'extended-precision'))
from binary_model import rounded

N = 200
GENERATORS = (
    'barycentric', 'bary_fma_low', 'bary_fma_high',
    'integer_weighted', 'integer_fma_low', 'integer_fma_high',
    'two_ended_product', 'two_ended_fma', 'two_ended_accumulate',
    'midpoint_product', 'midpoint_fma', 'reflected_left',
)
DECISIONS = ('sum_mid_up', 'sum_mid_down', 'gap_mid_up', 'gap_mid_down',
             'distance_up', 'distance_down')


def fma(a, b, c):
    return float(rounded(F(a)*F(b)+F(c), 53))


@lru_cache(maxsize=None)
def centers(low, high, generator):
    assert generator in GENERATORS and low < high
    step = (high-low)/N
    midpoint = (low+high)/2
    grid = [0.0]*(N+1)
    grid[0], grid[N] = low, high
    if generator == 'two_ended_accumulate':
        for i in range(1, N//2):
            grid[i] = grid[i-1]+step
            grid[N-i] = grid[N-i+1]-step
        grid[N//2] = midpoint
    elif generator == 'reflected_left':
        total = low+high
        for i in range(1, N//2):
            grid[i] = low+i*step
            grid[N-i] = total-grid[i]
        grid[N//2] = midpoint
    else:
        for i in range(1, N):
            t = i/N
            if generator == 'barycentric':
                value = (1-t)*low+t*high
            elif generator == 'bary_fma_low':
                value = fma(1-t, low, t*high)
            elif generator == 'bary_fma_high':
                value = fma(t, high, (1-t)*low)
            elif generator == 'integer_weighted':
                value = ((N-i)*low+i*high)/N
            elif generator == 'integer_fma_low':
                value = fma(N-i, low, i*high)/N
            elif generator == 'integer_fma_high':
                value = fma(i, high, (N-i)*low)/N
            elif generator == 'two_ended_product':
                value = low+i*step if i < N//2 else high-(N-i)*step if i > N//2 else midpoint
            elif generator == 'two_ended_fma':
                value = fma(i, step, low) if i < N//2 else fma(i-N, step, high) if i > N//2 else midpoint
            elif generator == 'midpoint_product':
                value = midpoint+(i-N//2)*step
            elif generator == 'midpoint_fma':
                value = fma(i-N//2, step, midpoint)
            else:
                raise AssertionError(generator)
            # Python float, including the FMA return, is a binary64 store.
            grid[i] = float(value)
    assert all(math.isfinite(v) for v in grid)
    assert all(a < b for a, b in zip(grid, grid[1:])), (low, high, generator)
    return tuple(grid)


def select(low, high, k, x, generator, decision):
    assert decision in DECISIONS
    grid = centers(low, high, generator)
    a, b = grid[k:k+2]
    if decision.startswith('sum_mid'):
        boundary = (a+b)/2
        right = x >= boundary if decision.endswith('_up') else x > boundary
    elif decision.startswith('gap_mid'):
        boundary = a+(b-a)/2
        right = x >= boundary if decision.endswith('_up') else x > boundary
    else:
        left_distance, right_distance = abs(x-a), abs(b-x)
        right = left_distance >= right_distance if decision.endswith('_up') else left_distance > right_distance
    return k+int(right)


def bits(x):
    return struct.pack('>d', x).hex().upper()


def rank(x):
    value = struct.unpack('>Q', struct.pack('>d', x))[0]
    return (~value & ((1 << 64)-1)) if value >> 63 else value ^ (1 << 63)


def unrank(key):
    value = key ^ (1 << 63) if key >> 63 else (~key & ((1 << 64)-1))
    return struct.unpack('>d', struct.pack('>Q', value))[0]


def self_test():
    # FMA differs from a product rounded before addition, with no tolerance.
    a, b, c = 1+2**-27, 1-2**-27, -1.0
    assert a*b+c == 0.0
    assert fma(a, b, c) == -2**-54
    for x in (-33.7, -8.0, -1.08, -1.0, -0.92, 1.0, 257.25):
        assert unrank(rank(x)) == x
        assert rank(math.nextafter(x, math.inf)) == rank(x)+1
        assert rank(math.nextafter(x, -math.inf)) == rank(x)-1
    for generator in GENERATORS:
        g = centers(-8.0, 8.0, generator)
        assert g[0] == -8 and g[N] == 8
        for decision in DECISIONS:
            assert select(-8.0, 8.0, 87, g[87], generator, decision) == 87
            assert select(-8.0, 8.0, 87, g[88], generator, decision) == 88
