# FEAT-univ-distributions — dev2 SJPI support investigation

**SUPPORT NOT COMPLETE / NOT ACCEPTED.** The independently callable
`src/stat/univ_kernel_sjpi.zig:fromBins` now implements bandwidth selection for
an already assigned 201-point histogram, with test discovery in root.zig.
It does NOT assign raw observations to bins and does not enable PROC SJPI.
Do not remove dev4's unsupported guard: no tested raw-sample binning candidate
yet passes all half-grid examples. Excluding those samples would not satisfy
the assigned acceptance. See [the follow-up](halfgrid-README.md).

Baseline acquired by clean `git merge --ff-only feat/stat/batch-3`: `6aa9b33`.
Read CLAUDE.md, lexer.zig, D-029, dev4's retained README and kernel API, and the
manager checkout's ignored statistical manual, printed pp.448–449.
The first landing (4d061f4) changed only this evidence directory. The follow-up
also adds the owned numeric module and root test import. No jira.md or other
developer's UNIV module is changed.

## Reproduction and provenance

Oracle version reported by reference.sas: **9.04.01M9P06052025**.
All samples are synthetic. Each retained triplet was run using its unique
absolute `/private/tmp/dev2-sjpi-*.sas` path, for example:

```
/Users/thomas/sas/bin/sasrun /private/tmp/dev2-sjpi-reference.sas -f text -o /private/tmp/dev2-sjpi-reference.txt -l /private/tmp/dev2-sjpi-reference.log
```

The acceptance command with `-o - -l /dev/null` was also used for the initial
n8 comparison. Named output/log arguments preserve the exact oracle evidence.
Sources can be rerun from this directory using absolute paths. No SAS server
or application internals were read. A sandbox socket failure was rerun with
approved direct sasrun execution; it was not treated as a numerical result.

Run `python3 compare.py` from any directory for the comparison report.
`python3 compare.py --require-parity` intentionally exits 1: it is a runnable
counterexample discriminator, NOT passing regression coverage for implemented
SJPI support. Python standard library only; `ctypes` calls the host C `fma`.
The script contains independently written mathematical evaluation; no external
implementation was copied or licensed into the repository.

## Narrowed numerical model

Normalization is established: `h = c * IQR * n**(-1/5)`.
The following candidate reproduces all 13 nondegenerate base cases to absolute
h error below `2e-14` (comparison tolerance `1e-10`):

1. Nearest-neighbor binning on 201 points spanning the sample min/max.
2. Recompute population standard deviation on the binned sample.
3. Gaussian derivative functionals, including diagonal terms, divided by
   `n*n*h**(r+1)`. Normal-reference pilots are
   `a = (32/(5*sqrt(2)))**(1/7) * sigma * n**(-1/7)` and
   `b = (64/(7*sqrt(2)))**(1/9) * sigma * n**(-1/9)`.
4. `alpha = (6*sqrt(2)*psi4(a)/(-psi6(b)))**(1/7)`;
   solve `h = [1/(2*sqrt(pi)*n*psi4(alpha*h**(5/7)))]**(1/5)`.
5. Use the ORIGINAL sample standard deviation to set the search upper limit
   to twice the oversmoothed bandwidth. Search 21 logarithmic grid points
   from upper/18 to upper, take the largest sign-change bracket, then bisect.
   Stop when bracket width is below **0.001 in original data units**, returning
   the last trial point. This explains lack of exact scale equivariance.

The candidate uses fused `min + i*step` lattice construction and fused midpoint
comparisons. This is a **hypothesis disproved at some exact half-grid points**,
not a confirmed account of SAS's internal implementation. The general SJ
formula alone, whether using IQR, sample SD, or population SD, is insufficient.
Rounded pilot constants also should not replace the analytic constants.

## Oracle inventory

- `cases`: 16 cases including n2/n3/n4/n8, ties, outliers, reflection, affine
  scaling, tiny units, zero IQR and constant/singleton data. n8 returns
  c=0.71482864776055. Scaling by 3 and shifting by 17 returns
  0.71498707792873; scaling by .001 returns 0.74968328476011.
  **Case 6 has a real SAS floating-point zero-divide and termination. Its
  printed stats/c are stale WORK datasets from case 5, NOT oracle evidence.**
  The script explicitly discards that stale output, not the acceptance case.
  Cases 7/8 produce no kernel rows and warnings about zero SD.
- `reference`: five independent KDE/UNIV comparisons, zero errors/warnings.
  With `SJPITOL=1e-12`, KDE itself is not the raw-sample continuous SJ formula:
  e.g. n4 KDE h=1.28177853044944 vs unbinned h=1.28283015190039.
  A single exact n9 KDE match did not generalize; do not claim otherwise.
- `kde-grid`: n4 KDE bandwidths at NGRID=101/129/401/1001 are
  1.27840000887399 / 1.28588350493669 / 1.28177853044944 /
  1.28241390206334. Nearest-grid binning AND recomputed population variance
  reproduce these high-precision values. This distinguishes binning from
  root-solver tolerance and the pilot formula.
- `grid`: changing UNIV endpoints/midpoints does not alter SJPI. Shifting the
  symmetric n9 sample by +100 changes c from .92146091297204 to .93484791296836.
- `shift`: 101 n4 translations by increments of .001 all return the same c.
- `sign`: 21 n9 translations by .01 give several discrete c values; 21 n4
  integer translations remain invariant. `hex` preserves actual binary input
  values, ruling out re-created Python decimals as an explanation.
- `counts`, `counts-bound`, `counts-truncate`: directly inspect KDE nonzero
  nearest-bin counts. Explicit [-8,8] or TRUNCATE with NGRID=201 produces
  n9 h=2.44313219683651; the same UNIV sample corresponds to
  h=2.37513558941864. KDE's boundary implementation cannot simply be reused.
  KDE output grid coordinates are generated by repeated addition (its central
  value is 6.022959908591474e-15 for [-8,8]); using repeated-addition nearest
  points alone still does not reproduce UNIV's half-grid assignment.

## Concrete remaining acceptance gaps

The runnable candidate passes 13/13 base comparisons but only **9/21** half-grid
translation comparisons. Maximum absolute standardized bandwidth discrepancy
is **0.0205580979628**. Do not loosen tolerances to accept this discrepancy.

The unresolved discriminator is UNIVARIATE's internal half-grid assignment,
not the documented h-to-c normalization. Formula, pilot and nonboundary search
rules are strongly supported by the retained cases; generic parity is not
established. Explicit-grid KDE counts demonstrate that its boundary handling
is different. Further work should obtain UNIV-specific bin assignments (or
an asymmetric half-grid experiment that separates the candidate assignments),
not repeat direct-plugin/solve-equation formula guessing.

The follow-up implements the proven binned numerical core with 23 SAS bandwidth
comparisons, captured-diagnostic tests and the oracle-established no-bracket
maximum fallback. Raw-sample bin assignment and PROC integration remain absent.
Non-normal-to-normal kernel warning behavior belongs to integration; dev4's
retained SJPI probe establishes it, but this numeric helper does not select a
requested kernel kind. Degenerate/zero-IQR requests are rejected visibly by the
helper; caller-level SAS warning/empty-estimate behavior is not implemented by
it. The entire parent ticket is not closed.

## Primary references

- Local SAS 9.4 Statistical Procedures, pp.448–449 (normalization and SJPI).
- SAS KDE Bandwidth Selection:
  https://support.sas.com/documentation/cdl/en/statug/66103/HTML/default/statug_kde_details06.htm
- SAS KDE UNIVAR options (search grid and SJPITOL):
  https://support.sas.com/documentation/cdl/en/statug/66103/HTML/default/statug_kde_syntax03.htm
- Jones, Marron and Sheather (1996), *A Brief Survey of Bandwidth Selection
  for Density Estimation*, JASA 91(433), 401–407, section 2.3.1:
  https://sites.stat.washington.edu/courses/stat527/s13/readings/Jones_etal_JASA_1996.pdf

References describe the mathematical method/search; the UNIV binning behavior
above is experimental evidence, not a claimed documented implementation detail.
