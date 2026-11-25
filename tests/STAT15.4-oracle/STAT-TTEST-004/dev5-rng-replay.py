"""Independent standard-library replay of the unchanged bootstrap_seeded oracle.

MT1998 recurrence/initialization: Matsumoto & Nishimura, TOMACS 8(1), 1998,
appendix, https://afpc.tamu.edu/courses/643/2016/reading/Matsumoto-Nisimura-Merseene-Twister.pdf
SAS RNG context: https://blogs.sas.com/content/iml/2018/01/29/random-number-generators-sas.html
Statistics and percentile ranks: S154 physical pp.10635-10637.
Reads the original input and expected result; never writes either or supplies
samples to OpenSAS. No seed offsets, burn-in, sampled-index constants or fitted RNG.
"""
from pathlib import Path
import math
import re
import statistics

folder = Path(__file__).resolve().parent
source = (folder / "bootstrap_seeded.sas").read_text()
expected = (folder / "bootstrap_seeded.expected.txt").read_text()
seed = int(re.search(r"\bseed\s*=\s*(\d+)", source, re.I)[1])
count = int(re.search(r"\bnsamples\s*=\s*(\d+)", source, re.I)[1])
columns = re.findall(r"[A-Za-z_]\w*", re.search(r"\binput\s+([^;]+);", source, re.I)[1])
response = re.search(r"\bvar\s+(\w+)\s*;", source, re.I)[1]
class_name = re.search(r"\bclass\s+(\w+)\s*;", source, re.I)[1]
groups = {}
for line in re.search(r"\bdatalines\s*;(.+?);\s*run;", source, re.I | re.S)[1].splitlines():
    fields = line.split()
    if fields:
        groups.setdefault(fields[columns.index(class_name)], []).append(float(fields[columns.index(response)]))
a, b = [groups[key] for key in sorted(groups)]

def uniform_mt1998(seed):
    state = [seed]
    for i in range(1, 624):
        state.append((69069 * state[-1]) & 0xFFFFFFFF)
    while True:
        for i in range(624):
            y = (state[i] & 0x80000000) | (state[(i + 1) % 624] & 0x7FFFFFFF)
            state[i] = state[(i + 397) % 624] ^ (y >> 1) ^ (0x9908B0DF if y & 1 else 0)
        for y in state:
            y ^= y >> 11
            y ^= (y << 7) & 0x9D2C5680
            y ^= (y << 15) & 0xEFC60000
            y ^= y >> 18
            yield y / 4294967296

def estimates(first, second):
    n, m = len(first), len(second)
    va, vb = statistics.variance(first), statistics.variance(second)
    return (statistics.mean(first) - statistics.mean(second),
            math.sqrt(2 * ((n - 1) * va + (m - 1) * vb) / (n + m - 2)),
            math.sqrt(va + vb))

def quantile(values, p):
    r = len(values)
    rp = r * p
    k = int(rp) if rp.is_integer() else math.floor((r + 1) * p) if p <= .5 else math.ceil((r + 1) * p)
    assert 1 <= k <= r
    return sorted(values)[k - 1]

stream = uniform_mt1998(seed)
draws = [estimates([a[int(next(stream) * len(a))] for _ in a],
                   [b[int(next(stream) * len(b))] for _ in b]) for _ in range(count)]
point = estimates(a, b)
checked = 0
for line in expected.splitlines():
    m = re.match(r"\s*\S+\s+Diff\s+\(1-2\)\s+(\d+)\s+(-?[\d.]+)\s+([\d.]+)\s+([\d.]+)\s*$", line)
    if m:
        for got, want in zip(draws[int(m[1]) - 1], map(float, m.groups()[1:])):
            assert abs(got - want) <= .00005
        checked += 1
assert checked == 12
section = expected.split("Bootstrap Statistics and Confidence Limits", 1)[1].split("Variable", 1)[0]
references = [list(map(float, line.split()[-4:])) for line in section.splitlines() if line.lstrip().startswith("Diff (1-2)")]
assert len(references) == 3
for j, reference in enumerate(references):
    values = [row[j] for row in draws]
    summary = (statistics.stdev(values), statistics.mean(values) - point[j], quantile(values, .025), quantile(values, .975))
    for got, want in zip(summary, reference):
        assert abs(got - want) <= .00005
    print(("Mean", "Pooled difference SD", "Satterthwaite difference SD")[j], summary)
print(f"PASS: seed {seed}, {count} replicates; all {checked} displayed draws and all bootstrap summaries.")
