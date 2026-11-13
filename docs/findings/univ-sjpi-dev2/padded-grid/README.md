# Padded 401-point grid hypothesis: bounded negative result

**No viable raw selector was found in this discovery family.** No raw adapter
was implemented and no public-path guard was removed. The already landed
201-count SJPI core remains unchanged.

The proposed padded geometry is internally consistent on the tested samples,
and one generic index expression reproduces all six measured transitions.
It nevertheless fails 16 of the retained 163 assignments. Passing the six
transitions is therefore insufficient to accept it or assume that SAS uses
this complete 401-point mechanism.

## Discovery and transparency

[DISCOVERY.md](DISCOVERY.md) records the initial 64 configurations and three
explicit, narrowly motivated amendments, all before any fresh oracle outcome:

| Recorded stage | Configurations | Best old cases | Transition query groups | Exact transitions |
|---|---:|---:|---:|---:|
| Initial origin/spacing/index/stored-center family | 64 | 129/163 | 62/72 | 4/6 |
| Add fractional linspace evaluation order | 80 | 129/163 | 62/72 | 4/6 |
| Add one-based index conversion, binary64/retained 64 bits | 88 | 147/163 | 72/72 | 6/6 |
| Add stored padded barycentric endpoint expressions | 184 | 147/163 | 72/72 | 6/6 |

The fractional-linspace/left-distance configuration itself reproduces all
72 transition groups and six thresholds, but only 123/163 old cases. A nearest
set audit also found old observed choices outside its nearest stored centers;
a fixed left/right tie switch cannot repair that construction.

No model predicts from the target k or measured threshold. Each evaluates a
GLOBAL padded index from x/low/high, then subtracts 100 for comparison. There
is no clamping to 100..300, per-index lookup, fitted tolerance, or replacement
of an old counterexample. The earlier 64/80/88 results are retained losslessly
in compact form; replay verifies that all of their failures still reproduce.

All prerequisite cases use the previously retained actual SAS 9.4 M9 sources,
outputs and HEX inputs. **No fresh oracle was run in this pass:** no candidate
passed the old-case gate and became eligible for freezing/fresh validation.
There is consequently no candidate accepted for raw-adapter implementation.

## Best rejected mechanism and exact obstruction

The best rejected identity is:

```
R = RN53(high-low)
o = RN53(RN53(RN53(low-R)+low)/2)
u = RN53(RN53(RN53(high+R)+high)/2)
z = RN53(x-o)
span = RN53(u-o)
one_based = RN64(RN64(RN64(z/span)*400)+1)
padded_index = nearest_even_integer(one_based)-1
```

RN64 here means a 64-bit significand, not binary64 storage. The physical step
supplied to the core is R/200. This expression is a rejected hypothesis, not
an assertion about SAS's internal instruction sequence or actual grid size.

For the same [-8,8] domain, o=-16, u=16 and these coordinates are EXACT:

| Retained case | x | z | Padded q | SAS padded bin (inferred +100) | Candidate |
|---|---:|---:|---:|---:|---:|
| halfgrid-profile:7 | -7 | 9 | 112.5 | 112 | 113 |
| halfgrid:1 | -3 | 13 | 162.5 | 163 | 163 |
| halfgrid:13 | -1 | 15 | 187.5 | 187 | 187 |

The first counterexample has oracle h=2.6108339052242213, while the candidate
assignment gives h=2.6005491338761426. This is not a last-bit bandwidth error.
It cannot be waived or fixed by loosening the comparison tolerance.

The lower/upper/lower choices at these exact padded half-coordinates are not
jointly explained by a fixed half-up, half-down, zero-based ties-even or
one-based ties-even integer convention. Increasing precision in this selected
ratio expression does not change those exact halves. Other center construction
or decision paths remain logically possible; the rejected family does not
establish a universal impossibility result for padded grids.

The complete 16 failures of the best rejected model, all other configuration
failures, the case-index maps and readable first counterexamples are in
[discovery-results.json](discovery-results.json). No successful identity was
selected (`selected` is null).

## Padding reduction and metadata: separate from decision accuracy

[audit.py](audit.py) audits the best rejected model's computed bins, without
claiming that its wrong assignments are SAS's bins. On all 163 sample arrays:

- counts are conserved exactly;
- the minimum and maximum observations map to padded indices 100 and 300;
- there are no nonempty bins outside 100..300;
- subtracting the common integer 100 shifts the integer first moment by 100*n;
- the exact variance numerator n*sum(count*j*j)-sum(count*j)^2 is unchanged;
- the full count-weighted pair-distance histogram is unchanged.

These integer identities confirm that empty-padding removal is mathematically
legitimate for the computed geometry, and that it can feed the existing core
without altering its pilot variance or pair distances. They do NOT repair the
incorrect raw quantization. This exact-arithmetic check does not establish
bitwise equality of alternative floating-point accumulation paths or complete
whole-sample SAS bandwidth parity. Min/max here means sample extrema in the retained
tests, not a claim about all extreme IEEE exponent/cancellation scenarios.
The metadata and exact-tie bandwidth witnesses are in
[geometry-audit.json](geometry-audit.json).

## Reproduce

```
python3 docs/findings/univ-sjpi-dev2/padded-grid/replay.py --out /private/tmp/dev2-sjpi-padded-replay
```

Replay recomputes every configuration and geometry identity from the retained
inputs, compares the final report, and verifies the historical counterexample
sets. Exit 0 means this negative result reproduces, not that raw SJPI is
accepted. `model.py` remains diagnostic code under findings; it is not imported
by the interpreter. The parent ticket remains open.
