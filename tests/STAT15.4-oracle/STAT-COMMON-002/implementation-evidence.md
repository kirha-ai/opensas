# STAT-COMMON-002 implementation evidence

The implementation uses the existing MEANS dispatch contract. No REG,
runtime-version, dispatcher, board, or skill changes are included.

## Specification and scope

Read SAS/STAT 15.4 physical PDF pages 253, 254, 564, 570 (printed 241,
242, 552, 558). The high-performance FREQ contract truncates positive
frequencies and excludes missing/<1 values. Its positive-only WEIGHT rule
is procedure-specific: it must not replace MEANS' default inclusion of
zero/negative-weight observations in N. ID values and typed missing cells
remain available without rewriting source data.

`src/stat/data_selection.zig` provides immutable observation views, original
1-based source observation numbers from WHERE/OBS selection, variable roles,
independent raw FREQ/WEIGHT values, explicit missing/frequency/weight policies,
and contiguous BY views using the existing formatted/sorted BY contract.
MEANS uses a bounded row-pointer expansion adapter for its existing kernels.
The source dataset and source frequency values are not changed.

The authorized prelude fixes recognize VALIDMEMNAME=COMPATIBLE (alias COMPAT)
and the existing en_US locale. EXTEND and other locales report capability gaps;
malformed values report user errors. These do not implement extended member
names or non-US locale behavior.

## Oracle comparison

The original `weight_roles.sas` is executed unmodified, including its prelude.
Expected status: 0. Actual status: 0. Actual stderr: empty (captured in full).
All stdout content matches the unchanged expected file with whitespace-only
normalization: Python `actual.split() == expected.split()`. This collapses
whitespace only; it preserves every non-whitespace token in order, including
missing-value dots, headings, BY labels, separator rules, and numeric fields.
No runtime-version replacement or numerical tolerance is used in this case.
The historical SAS source-echo/session NOTE log is read as reference evidence,
not claimed to be a byte-identical OpenSAS log.

Expected-file SHA-256:
`d540b8f08478f0192985f2181d63720b0314fc9544a07f7d14282cedccd72a0b`.
The checked-in file at this hash contains **one** `The MEANS Procedure` title,
after `group=A`, and no repeated title after `group=B`. Both BY tables are
compared in full. This differs from the review message describing two titles;
the file in the dev2 worktree, manager worktree, and rebase base agrees on one.
No expected file was edited to obtain the match.

| BY | Variable | N | Mean | Std Dev | Sum |
|---|---|---:|---:|---:|---:|
| A | x | 7 | 3.4444444 | 1.9245009 | 31.0000000 |
| A | y | 7 | 8.5555556 | 3.8777619 | 77.0000000 |
| B | x | 7 | 9.2000000 | 2.0655911 | 92.0000000 |
| B | y | 7 | 21.0000000 | 3.6055513 | 210.0000000 |

Reproduce after `zig build` from the repository root:

```python
from pathlib import Path
import subprocess
p = Path('tests/STAT15.4-oracle/STAT-COMMON-002')
r = subprocess.run(['zig-out/bin/opensas', str(p / 'weight_roles.sas')],
                   capture_output=True, text=True)
assert r.returncode == 0, (r.returncode, r.stderr)
assert r.stderr == '', r.stderr
assert r.stdout.split() == (p / 'weight_roles.expected.txt').read_text().split()
```

The baseline was not assumed green. A fresh build on the initial checkout
already produced the four numerical rows but returned an error for
VALIDMEMNAME; a temporary prelude probe exposed LOCALE next. Its listing also
had a different title order, count-column width, and separator length.

## Regression and gate

Three selection unit tests cover multiple BY groups, original row numbers,
character IDs, special numeric and blank-character missing indicators,
per-variable versus listwise exclusion, fractional/zero/negative/missing FREQ,
zero/negative/missing WEIGHT, numeric-role rejection, and unchanged input data.
Main tests pin prelude behavior and rc 0/1/2 with captured diagnostics.

The new corpus fixture copies the complete oracle program. Its listing golden
uses OpenSAS whitespace and the same complete oracle content. Eight existing
corpus goldens change only the corrected combined MEANS layout: numeric content
and missing fields are unchanged. The existing combined-table unit assertion
is updated consistently.

`zig build gate --summary all` passed before rebase: 1,594/1,594 tests,
2,302/2,302 corpus fixtures, and 11/11 program fixtures. Zig is 0.16.0,
matching `build.zig.zon`. The local branch is `codex/stat-dev2`; it was rebased
once onto local `feat/stat15.4-tickets` at
`fcd445e5f855d0838303f86fffdef006a3ee8435`. Final post-rebase gate and commit
identity are reported in the delivery message. Nothing is pushed.
