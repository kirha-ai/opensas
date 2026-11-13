# Beta EDF tables with both shapes estimated

Fixed endpoints and both estimated shapes now use SAS M9 response surfaces.
Use a=min(alpha,beta), b=max(alpha,beta), including when the user's order is
reversed. The log-critical basis is:

    1, 1/n, 1/n², 1/a, 1/b, 1/a², 1/b², 1/(ab), 1/(an), 1/(bn), 1/(a²n)

D critical values are exp(surface)/sqrt(n); W2/A2 use exp(surface). The eleven
probability levels, distinct >.5/>.25 cutoffs and <.001 lower bound are retained.
Actual fitted shapes, not generator targets, are used for inference. M9 needs
n>=10 when beta shapes are estimated; fixed-parameter beta works from n=2.
The retained minimum-n probe confirms this. Its eight expected SAS warnings
state the ten-observation requirement; there are no SAS errors.

## Calibration and independent checks

The two calibration grids span twenty shape pairs and multiple sample sizes.
Synthetic samples target beta sufficient log moments; SAS's converged estimates
can differ slightly from those targets. Equal-slope extraction identifies the
response basis; numerical refinement solves the exact adjacent-critical-value
interpolation equations using the actual SAS estimates. All 45702 interior
calibration equations agree to log-statistic residual below 6.2e-13. This is
neither a simulated probability estimate nor interpolation across a sparse
shape/sample-size grid.

Median cutoffs are bracketed separately. For most brackets, the continuous
cutoff equality recovers the same eight-decimal response constants. A few
symmetric small-shape brackets encounter finite numerical jumps in the SAS
quantile/fitting path: their final statistic is not exactly the critical value,
even after 44 bisections. A deterministic robust equation fit uses the 37–38
continuous equalities per statistic; all original brackets remain in evidence.
No runtime shape range or regression case is excluded. A second oracle program
checks both sides, 1e-5 away in perturbation parameter, of **all 120** brackets:
all **240** bound-value and sign checks pass. Exact rounded 15-digit SAS statistics
at a cutoff can differ by ~1e-14 from that cutoff; the two-sided check avoids
claiming bitwise equality from rounded output.

Independent heldouts use n=11/37/83/157, new rank offsets and spacing, and nine
shape pairs including .15, 4.999 and swapped asymmetric pairs. All **17388**
rows match with maximum p error 1.73e-13 and exact signs. The Zig test checks
these and all 240 cutoff probes (17628 total) with absolute tolerance 1e-10.
Calibration, median, heldout, and two-sided-bound SAS runs have zero errors
and zero warnings. No prior expected-output file was changed.

Replay with bundled NumPy:

```
/Users/thomas/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 docs/findings/univ-edf-dev5/dev5_edf_beta_replay.py
```

The replay retains the complete calibration data and validates every independent
heldout and bound row. Source/output/log files are retained losslessly. Original
oracle paths are unique under `/tmp/opensas-dev5-edf-round2-20261113`.
