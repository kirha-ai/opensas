# FEAT-corr-advanced — dev5 probability support

Standalone support implemented and independently oracle-verified. Integration
into CORR is owned by dev1; this does not mark the parent ticket complete.
No changes to corr.zig, corr_advanced.zig, corr_polychoric.zig or jira.md.

## API

`src/stat/corr_hoeffding_probability.zig`: `pub fn probability(d: f64, n: f64) f64`.
D is SAS's 30-times-original Hoeffding coefficient. N is the pairwise sum of
integer frequencies, after missing deletion. Missing inference is NaN, matching
corr_advanced.Estimate. N <= 5 (including D=1), nonfinite inputs, fractional N,
and D > 1 return NaN. Negative tied D is valid, including values below -0.5.
Dev1 can assign `result.p = probability(result.r, result.n)` and remove the
probability rejection only after integrating its listing/ODS regressions.

## Formula and provenance

SAS documents `z = pi^4 * ((n-1)*D/60 + 1/72)`:
https://support.sas.com/documentation/cdl/en/procstat/68142/HTML/default/procstat_corr_details07.htm

The finite-N factor is n-1, not n. The Hmisc primary source and documentation
were inspected as an investigative lead:
https://github.com/harrelfe/Hmisc/blob/master/R/hoeffd.s
https://cran.r-project.org/web/packages/Hmisc/refman/Hmisc.html#hoeffd
https://github.com/harrelfe/Hmisc/blob/master/DESCRIPTION
Hmisc describes a tabulated/interpolated BKR approximation plus an exponential
extension, but does not implement SAS's calibration. Its code is GPL >=2;
no implementation or table from it was copied into this Apache project.

The SAS public documentation does not disclose approximation coefficients.
The following rule was inferred independently from the actual SAS 9.4 M9
oracle, not claimed to be a published SAS internal algorithm:

| branch_z interval | calibrated quantity | polynomial degree |
|---|---|---:|
| below .3 | survival = 1 | constant |
| .3 to .55 | log(CDF) | 4 |
| .55 to 1.1 | survival | 7 |
| 1.1 to 2.95 | survival | 8 |
| 2.95 to 10.3 | log(survival) | 8 |
| above 10.3 | survival = .00001 | constant |

Branch selection uses `branch_z = pi^4*(n-1)*D/60 + 1.3529`.
The rounded center differs from the documented center by
`delta = pi^4/72 - 1.3529 = 0.0000040421389225`. Coefficients remain in the
unrounded z basis; therefore their actual intervals end at nominal+delta.
This fixed shift was inferred from the 365-case switch sweep and validated
on a further independent ten-case boundary run. It is not a tolerance/fudge
added to observed pairs. No branch threshold was fitted to those final ten.

D=1 returns zero for N>=6, independently of the tail floor. Small negative D
DOES NOT universally give p=1: N=8,D=-1/14 gives .97700651510051.
The supplied negative/constant examples do give 1. These are genuine SAS
endpoint conventions, not theoretical-distribution limits.

`dense.sas` / `dense.txt` are the 2,500-case discovery sweep (seed 8135;
N=6,8,12,20,30,50, random transpositions of ordered permutations). Polynomial
residuals distinguish the rule from linear table interpolation, a pure
spectral inversion, or a fitted single exponential. `recover_and_verify.py`
reconstructs coefficients in a stable Chebyshev basis using only discovery
rows, then checks fresh data. Requires NumPy; the bundled Python runtime has it.
The low log(CDF) fit uses z>.38 to avoid loss of precision in printed 1-p;
the same degree-4 polynomial is evaluated down to .3. No observed (N,D)->p
lookup or held-out fitting is used in production. The bounded polynomial
is evaluated using Clenshaw recurrence, and the tail is never extrapolated.

## Independent acceptance evidence

`heldout-gen.py` creates 500 additional cases with seed 991783. It includes
450 fresh untied/tied/FREQ cases, 30 close neighbors on both sides of all five
branch boundaries, and 20 order/reverse/constant cases. Search for boundary
neighbors uses D alone, never oracle p. Sample sizes differ from discovery,
including 5,7,9,11,17,23,31,47,80,100 and FREQ totals. No missing/mismatched p
case is ignored by the Zig regression. `heldout.sas` / `heldout.txt` retain the
complete input and printed output. SAS runs reported zero errors/warnings.

Unique absolute commands (stdout captured verbatim in the named .txt files):

    /Users/thomas/sas/bin/sasrun /private/tmp/dev5-hoeffding-dense.sas -f text -o - -l /dev/null
    /Users/thomas/sas/bin/sasrun /private/tmp/dev5-hoeffding-heldout.sas -f text -o - -l /dev/null

The 500-case held-out maximum absolute probability error is 2.8e-14 against
SAS's printed E25.17 values (the oracle supplies roughly 14 significant digits).
The Zig regression threshold is 5e-13, much tighter than the previous 5e-5
listing requirement. The three supplied discriminating p-values have their
own tests at the same threshold. Other tests cover missing inference,
nonfinite input, very large N/D, constants, and exact/floored endpoints.

The reproducible CSV beside the module contains all 500 held-out rows, including
missing probabilities. It is expected-output evidence and is committed separately
from production code. Existing expected outputs are untouched. src/root.zig
has only one new test-discovery import; docs/decisions.md was searched first.

The inferred real-number boundary equality conventions cannot be directly
probed by arbitrary D in PROC CORR, but both sides of every boundary are
independently tested with attainable data. No claim to bit-for-bit equality
with undisclosed SAS coefficients is made; numerical compatibility is verified
to the fixed 5e-13 tolerance. Parent-ticket CORR integration remains dev1's work.

## Polynomial degrees and data partition

For each discovery interval, least-squares Chebyshev fits were tried in ascending
degree. The first degree reducing residuals to printed-oracle precision was
selected. These are maximum residuals in the calibrated quantity (logarithms
where indicated), not relaxed probability tolerances:

| region | unique discovery values | previous degree/residual | selected degree/residual |
|---|---:|---|---|
| log(CDF), .38–.55 | 75 | 3 / .00444013 | 4 / 7.9e-12 |
| p, .55–1.1 | 305 | 6 / 2.45e-5 | 7 / 3.1e-14 |
| p, 1.1–2.95 | 500 | 7 / 5.33e-5 | 8 / 1.3e-14 |
| log(p), 2.95–10.3 | 328 | 7 / 7.15e-5 | 8 / 4.6e-13 |

The relatively larger log(CDF) residual comes from taking log(1-p) of printed
probabilities close to one. Its held-out probability error remains below 5e-13.

Discovery: dense2500, initial-boundary10, switch365. The latter two only refined
branch selection, never polynomial coefficients. Independent holdout: the
original500 (40 missing, 460 finite) plus final-boundaries10 = 510 cases.
All 510 are executable Zig regressions. The final boundary seed is 129571,
distinct from coefficient/discovery seeds 8135/88391 and main holdout 991783.
The final boundary generator uses the rounded-center rule fixed beforehand
and computes D without asking SAS for probabilities. The previous failed
nominal-boundary run is retained explicitly as discovery, not counted as an
independent success. The source CSVs are copied from oracle outputs, not from
this implementation's predictions.

Ten original holdout cases fall in z .3–.38. Thus extrapolating the low degree-4
log(CDF) polynomial from its fitting interval .38–.55 is independently checked.
The 500 cases include n=5 (all inference missing), n=6, one/both margins constant,
perfect order/reverse, ties on either/both margins, and integer FREQ replication.
The fixture generator and complete inputs make these classifications auditable.

## Tight boundary validation and range certificate

`final-boundaries.sas/txt` are fresh N=200 permutations on each side of the
corrected switch. The following rows report unrounded z and actual SAS p;
the switch itself is the nominal value plus delta above:

| nominal | z below | SAS p below | z above | SAS p above |
|---:|---:|---:|---:|---:|
| .3 | .3000025183718 | 1 | .3000055762716 | .9999954044390 |
| .55 | .5500014954090 | .97384805392443 | .5500057000211 | .97015716844921 |
| 1.1 | 1.0999964927810 | .53089647013593 | 1.1000049020053 | .53090124887483 |
| 2.95 | 2.9500031675724 | .044077041611642 | 2.9500066077096 | .044072724853231 |
| 10.3 | 10.3000010977304 | .000014644156780 | 10.3000069587049 | .000010000000000 |

In particular, the upward discontinuity at 1.1 is real SAS behavior, not an
interpolation defect to smooth away. The new boundary test asserts each oracle
value at 5e-13 and every jump direction. Synthetic exact irrational-transform
boundaries are not claimed to have been supplied to PROC CORR; only attainable
rational D data are used as oracle fixtures.

`range_audit.py` reads the actual production coefficient arrays, converts each
to Bernstein form, and bounds the entire polynomial and derivative by their
Bernstein coefficient convex hulls. This is an interval-wide certificate, not
a finite sample grid or a clamp. The intervals are conservatively extended
past each corrected switch, including all of .3–.38. Bounds are strictly inside
[0,1] with ample margin from floating-point roundoff. The log(CDF) derivative
is positive throughout its interval; all other calibrated derivatives are
negative. Endpoint branches produce exactly 1, .00001, and (D=1) zero.
No silent clipping, generic monotonicity correction, or tail extrapolation is
used. The jump at 1.1 is allowed intentionally.

Run `python3 recover_and_verify.py` to rederive and validate, and
`python3 range_audit.py` for the whole-domain bounds (both require NumPy).
`range-audit.txt` and `verification.txt` retain the run results.

## Support landing status

Four standalone Zig test blocks pass: supplied discriminators, original holdout500,
input/endpoint handling, and final independent boundary10 including the upward
jump. Across all 3,385 retained oracle cases the maximum absolute probability
error is 3.1e-14. The whole-domain range certificate passes. This module is ready
for dev1 integration; no parent-ticket completion or integrated CORR p-value
listing/ODS acceptance is claimed. Final rebased commit and gate counts are in
the handoff so the recorded HEAD can be gated without a post-gate doc commit.
