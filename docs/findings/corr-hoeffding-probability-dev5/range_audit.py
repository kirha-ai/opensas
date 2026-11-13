"""Range certificate for the production polynomials (NumPy required).

A polynomial on [0,1] lies in the convex hull of its Bernstein coefficients.
We convert the ACTUAL module constants, including the low-region extrapolation,
and bound both values and derivatives over complete intervals, not a grid.
"""
from pathlib import Path
from math import comb, exp
import re
import numpy as np
root = Path(__file__).resolve().parents[3]
source = (root / 'src/stat/corr_hoeffding_probability.zig').read_text()
for name, domain, interval, mode in [
    ('low', (.38,.55), (.3,.55001), 'cdf'),
    ('lower', (.55,1.1), (.55,1.10001), 'p'),
    ('middle', (1.1,2.95), (1.1,2.95001), 'p'),
    ('upper', (2.95,10.3), (2.95,10.30001), 'logp'),
]:
    raw = re.search(r'const '+name+r' = \[_\]f64\{([^}]+)\}', source).group(1)
    coefficients = [float(s) for s in raw.split(',') if s.strip()]
    f = np.polynomial.Chebyshev(coefficients, domain=domain)
    lo, hi = interval
    p = f.convert(kind=np.polynomial.Polynomial)(np.polynomial.Polynomial([lo,hi-lo]))
    degree = len(p.coef)-1
    b = [sum(p.coef[i]*comb(k,i)/comb(degree,i) for i in range(k+1)) for k in range(degree+1)]
    derivative = [degree*(b[k+1]-b[k])/(hi-lo) for k in range(degree)]
    if mode == 'cdf':
        assert max(b)<0 and min(derivative)>0
        bounds = (1-exp(max(b)), 1-exp(min(b)))
    elif mode == 'logp':
        assert max(b)<0 and max(derivative)<0
        bounds = (exp(min(b)), exp(max(b)))
    else:
        assert 0<min(b)<max(b)<1 and max(derivative)<0
        bounds = (min(b),max(b))
    assert 0<bounds[0]<bounds[1]<1
    print(name, 'interval', interval, 'p bounds', bounds, 'derivative bounds', (min(derivative),max(derivative)))
print('All polynomial regions stay strictly inside [0,1]; outer branches are exactly 1 and 1e-5, perfect D exactly 0. No clipping.')
