# Estimated-threshold Weibull EDF inference

All four threshold-estimated masks are implemented: theta alone, theta+sigma,
theta+c, and all three. Combined with fixed-threshold cases, every Weibull
estimation mask is handled. M9 requires fitted/specified c>2 and n>=10 when
theta is estimated. Fixed-threshold rules remain separate: estimated sigma/c
have only W2/A2, including at smaller samples.

The log-critical surface basis is c^-k * n^-j for k=0..3 and j=0..2. D critical
values divide exp(surface) by sqrt(n); W2/A2 use exp(surface). Each probability
level retains its own coefficients. The two upper bounds >.5/>.25 and lower
<.001 bound are preserved, with the endpoint check before interior interpolation.

## Oracle and regression coverage

Two calibration grids span c=2.01 through 50, multiple sample sizes and all four
masks. Actual estimated C is used in the equations, not the generator target.
Their SAS runs have zero errors/warnings. The median probe brackets 300 cutoffs.
Some brackets encounter numerical jumps in SAS fitting, most visibly for
input shape 20 at n=10; their final statistic need not equal a critical value.
All brackets are retained, and the deterministic equation fit uses continuous
cutoff equalities rather than treating those jumps as exact equalities.

An independent program evaluates both sides of **every one** of the 300
brackets (perturbation offsets ±1e-5). All **600** rows are available and match
their exact endpoint probability values and signs. No shape or bracket is
excluded from this validation. These are fit-path jumps, not availability
transitions, and no inference approximation is inserted for them.

Independent numerical heldouts use n=11/37/83/197, input shapes 2.001/2.7/8/30,
new rank offsets/perturbation spacing, and affine location/scale changes. Every
one of the **30294 emitted EDF rows** agrees to maximum p error **9.45e-12**
with exact signs. SAS emits no EDF table for 206 groups whose fitted shapes do
not meet its availability rule; all these outcomes remain in the retained log.
The heldout run has zero errors and zero warnings. The threshold-minimum probe
confirms tables begin at n=10 for all estimated-threshold Weibull and lognormal
masks; it has zero errors and expected small-sample warnings.

Zig embeds all 30294 numerical rows and 600 bound checks. Replay with bundled
NumPy (offline coefficient extraction, not Monte Carlo probability estimation):

```
/Users/thomas/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 docs/findings/univ-edf-dev5/dev5_edf_weibull_replay.py
```

All sources, output and logs are retained losslessly. Original oracle paths
were unique under `/tmp/opensas-dev5-edf-round2-20261113`. The median source was
run as threshold-median.sas; its retained name identifies the family. Public
fitting, warnings and ODS integration remain owned by dev4.
