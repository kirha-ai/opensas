# Estimated exponential EDF inference — continuation

Implemented all three estimation masks, using M9 tabulated response surfaces,
not resampling or asymptotic substitutes. Original sample size is passed to the
helper. The fixed-parameter case retains its separate existing table.

## Critical values and interpolation

Let m be the number of EDF observations after excluding values equal to the
fitted threshold. In the original distinct-sample calibration, m=n except
when theta alone is estimated, where m=n-1. See EVIDENCE-EXPONENTIAL-BOUNDARIES.md
for tied minima and fixed-threshold boundary observations. D critical values
are exp(L)/sqrt(m), W2/A2 critical values exp(L). Probability levels are
.5, .25, .20, .15, .10, .05, .025, .01, .005, .0025, .001. The .5 and .25
knots are separate upper-bound cutoffs, not one interpolated interval.
Below the median use >.5; below the .25 critical value use >.25; above the
.001 critical value use <.001. All other intervals interpolate probability
linearly. In particular .20 is a real knot: omitting it gives wrong results.

- Sigma estimated, theta fixed: D L=a+b/sqrt(m)+c/m²; W2/A2 L=a+b/m.
- Theta estimated, sigma fixed: same bases, different coefficient tables.
- Both estimated: D L=a+b/sqrt(n)+c/n+d/n²; W2 L=a+b/sqrt(n)+c/n;
  A2 L=a+b/n+c/n²+d/n³.

Each knot has its own coefficients. Their 8-decimal SAS response-surface
constants were recovered from equal-slope segments at n=5,8,12,20,30,50,100,
200,500,1000. This is a calibrated exact functional form, not a fitted spline
through sample-size grid points. Median cutoffs were independently bracketed
with 44 bisections; retained source and output show every bracket. Replaying
all numeric calibration and heldout output checks both probabilities and signs.

## Independent validation

New heldouts use n=2,3,4,5,6,7,9,17,37,83,157,733, new rank offsets, new
perturbation spacing, theta=3 and scale=2. M9 emits no EDF table below five
effective observations; theta-only consequently first appears at n=6.
9438 emitted rows match Zig to absolute p error below 2e-10 with exact signs.
The replay additionally checks 43227 previous dense-calibration rows and
72060 new sample-size calibration rows. Largest errors respectively
4.87e-11, 1.22e-10, 5.01e-11. Final runs had zero errors and warnings.

Run `python3 docs/findings/univ-edf-dev5/dev5_edf_exponential_replay.py` to
re-extract coefficients and compare retained SAS output. The Zig regression
embeds `src/stat/testdata/univ_edf_dev5_exponential.txt` (whitespace normalized
from SAS output only). No older expected-output file was altered.

Probes ran at unique absolute paths under
`/tmp/opensas-dev5-edf-round2-20261113`, using the assigned sasrun command.
`exp-bounds` was rerun with explicit output/log paths after correcting BY order
in the bisection harness; only successful final source/output are retained.

## Integration requirement for dev4

When only theta is estimated, SAS computes theta=min(x), then removes every
observation equal to that minimum before computing EDF statistics. This must happen in
the raw-statistics adapter; this helper cannot reconstruct altered W2/A2 from
uncorrected statistics. Pass the original n and `Request.exponential_boundary_count` to tabulated();
it uses n minus that count. The default assumes one excluded point when only
theta is estimated, zero otherwise. With n=100, x_i=-log(1-(i-.5)/n), theta-only
SAS gives D=.01005025125628, W2=.00167504187604, A2=.02301752878570. Direct
recomputation on the remaining 99 observations gives .010050251256281407,
.001675041876046903, .023017528785715058. Including the minimum would instead
make A2 infinite. Both-estimated uses the bias-corrected theta and retains all n.

Dev5 owns all tabulated-family oracle validation. Dev4 owns estimated
Gumbel/IGAUSS/Pareto/Rayleigh callback integration and oracle validation;
the existing fixed-family and fitted-Rayleigh helper evidence remains reusable.
