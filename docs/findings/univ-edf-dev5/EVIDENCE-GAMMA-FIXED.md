# Fixed-threshold gamma EDF response surfaces

All three masks implemented: sigma estimated, alpha estimated, and both
estimated. Shape-dependent log-critical surfaces use the actual fitted alpha,
not the data generator's intended shape. Probability levels and bound semantics
are the same eleven-level convention as the estimated exponential tables.

D uses basis 1, n^-1/2, n^-1, alpha^-1, (n alpha)^-1; when only sigma is
estimated it additionally uses alpha^-2 and (n alpha²)^-1. Critical D is
exp(surface)/sqrt(n). W2/A2 use 1, n^-1, n^-2, alpha^-1, (n alpha)^-1 and
critical values exp(surface). Each probability knot has separate coefficients.

`dev5-edf-gamma-knots.sas` brackets all eleven critical values with 44 iterations
for alpha=1.5/3/10 and n=10/20/50/100/200. Saturated searches (target unreachable
for that particular synthetic perturbation) are not treated as equalities;
all emitted brackets are retained. The model is identified from the remaining
full-rank calibration equations. This does not exclude any implementation
shape/sample-size requests. There is no simulation substitute.

Independent heldouts use alpha=1.001/2.3/7/50, n=11/37/83/197, new rank offsets,
perturbation spacings, threshold=3 and scale=2. Actual fitted alpha is retained
alongside each EDF result. All **23184 rows** agree with probability error at
most 2.12e-13 and exact signs. Zig checks the full fixture at 1e-10 tolerance.
The final knots and heldout runs had zero errors and zero warnings.

Re-extraction and validation require NumPy (available in the bundled Python):

```
/Users/thomas/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 docs/findings/univ-edf-dev5/dev5_edf_gamma_fixed_replay.py
```

## Actual M9 availability differences

The original manual Table 4.31 lists fixed-threshold/one-estimated-parameter
cases without the alpha>1 restriction. Actual M9 emits no EDF table for sigma-
only and alpha-only estimation at alpha=.5, .99, or 1. All-known gamma remains
available below alpha=1. The helper now follows M9 for any estimated gamma
parameter: require alpha>1. `gamma-availability` records zero rows and actual
fitted alpha for each case. A both-estimated target exactly 1 is a floating-point
boundary: M9 can fit a value infinitesimally greater than 1 and emit a table;
use the actual estimate for the strict comparison. Eight expected ODS warnings
report that the deliberately unavailable GoodnessOfFit objects were not created;
there are zero SAS errors.

M9 also requires n>=10 when gamma is not fully specified. `gamma-minimum`
probes n=2 through 12 for sigma-only and both-estimated fits. Sixteen expected
warnings explicitly state the ten-observation requirement; tables start at
n=10. All-known gamma remains available for n>=2 (separate minimum-n probe).
The numeric helper returns absent tests for these unavailable cases. Dev4 owns
public warning rendering; no unsupported implementation is silently masked.

Original SAS probes used unique absolute paths in
`/tmp/opensas-dev5-edf-round2-20261113`; retained sources/output/logs are lossless.
The successful gamma-knots source corrects an earlier harness `%scan` delimiter
mistake that split decimal shape values; no failed run is used as evidence.
