"""Reproduce independent normal-score input fixtures (Python standard library)."""
from pathlib import Path
from statistics import NormalDist

root = Path(__file__).resolve().parents[3]
for n, name in [(101, 'scores'), (77, 'heldout_scores'), (51, 'boundary_scores')]:
    values = [NormalDist().inv_cdf((i - .375) / (n + .25)) for i in range(1, n + 1)]
    target = root / 'src' / 'stat' / f'univ_johnson_dev3_{name}.csv'
    target.write_text(''.join(f'{v:.17g}\n' for v in values))
