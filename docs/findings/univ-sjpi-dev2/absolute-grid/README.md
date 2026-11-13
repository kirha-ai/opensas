# Absolute-grid centers and bounded ULP transitions

**This bounded pass is complete, with no accepted raw selector.** None of the
72 frozen center/decision configurations passes the retained 163 assignments.
All six measured adjacent-value transitions also differ from every tested
configuration. The accepted binned core and public guard are unchanged.

This rejects the specific [frozen family](FROZEN.md), not every possible
absolute-coordinate preprocessing or internal SAS implementation. No further
candidate was appended after scoring or oracle observation.

## Offline family and preserved counterexamples

Twelve binary64 center generators cover fractional/integer barycentric forms,
both FMA operand orders, separate operations, two-ended product/FMA/inward
accumulation, midpoint-centered generation, and reflected-left generation.
Every center is stored before comparing rounded midpoint or rounded distances;
both equality choices are tested. There are 12 x 6 = 72 configurations.

The six barycentric generators had earlier partial offline counterexamples.
Those are preserved, not reset: this pass evaluates all 136 older assignments
plus the 27 already landed heldouts. The best score is **109/163**, from
two_ended_product/distance_down. **0/72** are viable.

[offline-results.json](offline-results.json) retains every failed-case index
and an explicit first counterexample with both center HEX patterns. The exact
163-case identity map is [old-cases.csv](old-cases.csv). No q-only tolerance or
new x87 precision/storage family is included in this pass.

## Prespecified transition branch

Because no configuration was viable, the frozen plan's six-search branch was
executed instead of its viable-candidate validation branch. Targets were
k=86/87/88 in [-8,8] and [-7.99,8.01], with fixed asymmetric background points.

- Initial bounds were +/-32 representable binary64 rank steps about each
  exact rational half-point rounded to binary64.
- Six bisection rounds reduced each bracket to adjacent representable values.
- A separate final batch checked L-1, L, R, R+1, including repeated L/R inputs.
  Every target reproduced the local left,left,right,right pattern.
- Exactly **72/72** allowed SAS sample groups were used in eight batches;
  there are **54 distinct inputs** within the search (some intentionally
  repeat earlier collision probes). No window or case set was expanded.
- All groups have a unique forced-left/forced-right bandwidth match, with
  maximum absolute h error **1.7763568394002505e-15**, tolerance 1e-10.
- All eight runs report SAS **9.04.01M9P06052025**, zero errors and warnings.
  Actual returned HEX16 values match every supplied query manifest.

All source/output/log triplets, adaptive query manifests, inferred assignments
and final state are retained. No measured threshold is compiled into any
runtime selector. [replay.py](replay.py) independently replays the schedule,
verifies actual bits and forced assignments, and reproduces the final results
without issuing another SAS query.

## Measured last-left / first-right values

Offsets below count representable binary64 values from the rounded rational
half-point, not a constant physical spacing. This matters around -1, where
the binade changes. L and R are adjacent in all rows.

| Domain | k | L offset | R offset | last-left HEX16 | first-right HEX16 |
|---|---:|---:|---:|---|---|
| [-8,8] | 86 | +3 | +4 | BFF147AE147AE145 | BFF147AE147AE144 |
| [-8,8] | 87 | +8 | +9 | BFEFFFFFFFFFFFF8 | BFEFFFFFFFFFFFF7 |
| [-8,8] | 88 | -7 | -6 | BFED70A3D70A3D78 | BFED70A3D70A3D77 |
| [-7.99,8.01] | 86 | -5 | -4 | BFF11EB851EB8525 | BFF11EB851EB8524 |
| [-7.99,8.01] | 87 | -8 | -7 | BFEFAE147AE147B8 | BFEFAE147AE147B7 |
| [-7.99,8.01] | 88 | -23 | -22 | BFED1EB851EB8538 | BFED1EB851EB8537 |

[thresholds.csv](thresholds.csv) also contains exact normalized-ULP positions.
There are **0 exact first-right matches in 432 model/target comparisons**.
Predictions outside the fixed search window cannot match the measured interior
transition and are explicitly marked. The best configuration matches only
44/72 queried groups. See [model-thresholds.csv](model-thresholds.csv) for the
stored centers and each predicted versus measured first-right value.

## Recurrence and translation fingerprints

The following are measurements, not fitted runtime constants. Let R_k be the
first-right value and d=(high-low)/200 in exact rational arithmetic.

- In BOTH domains, R_87-R_86-d = 41/(25*2^53).
- In BOTH domains, R_88-R_87-d = -3/(25*2^46).
- Relative to the stored operation RN53(R_k + RN53(d)), the next threshold is
  respectively +2 and -15 representable-value ranks away in both domains.
- For each k, translating R from domain 0 by the exact difference of the
  actual domain lows leaves the SAME physical residual **-2^-49** in domain 1.
  The stored-add rank residual is -8 at k=86 and -16 at k=87/88 because their
  local binades differ. It is not an independently fitted offset per index.

Thus ordinary repeated threshold addition and exact translation do not
reproduce the observations. The common physical translation residual, together
with the shared adjacent-index increment errors, constrains an absolute-domain
rounding mechanism more tightly than the original normalized-q contradiction.

## Post-measurement interpretation — not an accepted candidate

One simple origin calculation has the same translation-rounding fingerprint:

```
r = RN53(high-low)
p = RN53(low-r)
o = RN53(RN53(p+low)/2)
z = RN53(x-o)
```

For domain 0, p=-24 and o=-16. For domain 1, p=-23.990000000000002 and
o=-15.990000000000002. The latter origin shift differs from the data-domain
shift by exactly -2^-49. At all six measured transitions, the four values
z(L-1), z(L), z(R), z(R+1) form two constant plateaus separated by ONE binary64
step. The plateau pairs at each k are bit-identical across the two domains.

[fingerprint.py](fingerprint.py) and [origin-fingerprint.json](origin-fingerprint.json)
make that arithmetic observation reproducible. This expression has no index
or measured-threshold parameter, but it was inspected AFTER measurement and
is NOT part of the frozen selector family. It neither defines a bin rule nor
has generic heldout acceptance. It is not evidence that SAS implements this
particular origin calculation. No bins are predicted or enabled from it.

The narrowed open question is whether input-coordinate quantization following
absolute-origin arithmetic, or another equivalent internal path, explains the
local plateaus and the remaining 163 assignments. That is distinct from merely
rounding the tested center interpolations and selecting their nearest point.
This pass stops here rather than adding new arithmetic combinations.

## Reproduction

```
python3 docs/findings/univ-sjpi-dev2/absolute-grid/offline.py --out /private/tmp/dev2-sjpi-absgrid-offline --require-parity
python3 docs/findings/univ-sjpi-dev2/absolute-grid/replay.py --out /private/tmp/dev2-sjpi-absgrid-replay-new
python3 docs/findings/univ-sjpi-dev2/absolute-grid/fingerprint.py --work /private/tmp/dev2-sjpi-absgrid-replay-new
```

The first command intentionally exits 1 because no frozen configuration passes.
The replay requires a new/empty output directory and passes when all archived
oracle decisions, query-schedule constraints and fingerprints reproduce. It
does not regenerate or overwrite oracle source paths. One original run was:

```
/Users/thomas/sas/bin/sasrun /private/tmp/dev2-sjpi-absgrid-r0.sas -f text -o /private/tmp/dev2-sjpi-absgrid-stage/round-0.txt -l /private/tmp/dev2-sjpi-absgrid-stage/round-0.log
```

Rounds 1 through 7 use corresponding unique absolute source/output/log names.
Frozen hashes remain unchanged. This is evidence-only SUPPORT; raw C=SJPI and
the parent ticket remain unaccepted.
