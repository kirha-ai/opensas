# GAP-univ-summary-complete — dev1 normality SUPPORT intermediate

This supplies the normality prerequisite, not ticket closure. Dev3 owns the
UNIVARIATE integration. Write scope: src/stat/normality.zig, src/root.zig test/API
wiring, tests in the new module, and this evidence family. No PROC implementation,
EBNF, function tracker, or jira.md changes are part of this support patch.

## API for integration

    pub const Method = enum { shapiro_wilk, kolmogorov_smirnov };
    pub const Result = struct { statistic: f64, p: f64, method: Method };
    pub fn compute(allocator: std.mem.Allocator,
        sorted_nonmissing: []const f64) error{OutOfMemory}!?Result;

Call once per unweighted analysis sample, after FREQ expansion and omission of
all ordinary/special missings. Input must be sorted ascending and finite; debug
assertions enforce that precondition. It is never modified. Caller must not
request these fields with a WEIGHT statement. null means both output fields
are missing. Otherwise store statistic in _NORMAL_ and p in _PROBN_. Method is
Shapiro–Wilk for n<=2000 and fitted-normal Kolmogorov–Smirnov for n>2000.
The allocation is confined to the SW coefficient vector and freed before return.

Nonconstant n=2 returns W=1,p=1 (SAS OUTTABLE convention, not an extrapolated
Shapiro–Wilk distribution); n=0/1 and exact constants return null. Independently
confirmed and cross-checked against dev3's raw dev3-robust.sas/.txt/.log and README
at /Users/thomas/kirha/opensas-dev3/docs/findings/univ-summary. No files there edited.

## Algorithm and primary references

- Local SAS 9.4 Statistical Procedures pp.444–447 and Table 4.36 printed p.461;
  _NORMAL_/_PROBN_ in Table 4.39 pp.463–464. Local reference was absent in dev1;
  read the copy in opensas-private/docs (no manager-tree edits).
- [SAS goodness-of-fit documentation](https://support.sas.com/documentation/cdl/en/procstat/67528/HTML/default/procstat_univariate_details52.htm)
  specifies Royston coefficients, the two transformations, estimated sample
  mean/variance for the normal EDF, and interpolation between tabulated levels.
- Royston, P. (1992), *Approximating the Shapiro-Wilk W-test for non-normality*,
  Statistics and Computing 2:117–119, [DOI](https://doi.org/10.1007/BF01891203).
  Read the [paper reproduction](https://www.scribd.com/document/378130543/Approximating-the-Shapiro-Wilk-W-test-for-Non-normality),
  including p.118 coefficient equations and normalization formulas. The second
  extreme-order coefficient ends in **-3.582663**, while the author's later
  [AS R94 code](https://lib.stat.cmu.edu/apstat/R94) uses -3.582633. Real SAS
  matches the 1992 coefficient: uniform n=8 W=.97485827830837, p=.93316533637933;
  the later coefficient instead gives W=.97485825629368,p=.93316519158339.
  Tests distinguish them rather than allowing the discrepancy inside tolerance.
- Stephens, M.A. (1974), *EDF Statistics for Goodness of Fit and Some Comparisons*,
  JASA 69:730–737, [DOI](https://doi.org/10.1080/01621459.1974.10480196),
  [paper](https://www.math.utah.edu/~morris/Courses/6010/p1/writeup/ks.pdf).
  Fitted-normal modification is D*(sqrt(n)-.01+.85/sqrt(n)); critical values
  (.775,.819,.895,.955,1.035) correspond to probabilities (.15,.10,.05,.025,.01).
  The .025 point is **.955**, not the .995 seen in some software documentation.
  SAS full-precision oracle values discriminate this and confirm linear
  interpolation in every interval, at n=2001 and n=5000.

SW uses the exact n=3 distribution; n=4–11 and n=12–2000 use the documented
normalizing transforms. The ordinary normal CDF/quantile are reused from
functions.zig. SAS stores zero when the SW upper-tail subtraction rounds to zero.
KS uses unbiased sample variance, not a known-parameter normal distribution.
Numeric stored KS p is clipped to **.01 and .15**, even when a listing would
show <.0100 or >.1500. Do not replace those numbers with uncensored tail values.

Computation uses a midpoint/radius change of units and compensated sums to avoid
overflow/underflow with extreme scales and unnecessary cancellation under
translation. No random simulation, interpolated Shapiro–Francia replacement,
or known-parameter KS shortcut is used.

## SAS near-constant convention and numerical boundary

SAS also makes normality missing for samples with very small spread relative to
nonzero mean, even when STD remains positive. The retained translation and
precision sweeps identify a relative population-variance cutoff near
500*machine-epsilon (about 1.110223e-13). The implementation applies this
oracle-derived criterion using scaled moments, before choosing SW/KS or n=2.
This cutoff is **empirical, not a threshold specified in the manual**.

At the exact floating-point cutoff, SAS's own summation order changes the result:
the balanced n=2/8/12 probes at factor 1 produce values, whereas n=2000 does not.
The helper uses stable moments rather than reproducing each accumulation error;
last-bit borderline missing/nonmissing classification is therefore not claimed
bit-identical. Tests pin the unambiguous .99 and 1.01 sides at n=2/8/12/2000/2001,
and moderate translations with numerical tolerances. This numerical boundary
qualification is explicit, not an unimplemented statistical-method fallback.

## Retained oracle evidence

Every file uses synthetic data only, invokes UNIVARIATE OUTTABLE without NORMAL,
and reads results with DATA _NULL_, FILE PRINT and BEST32. Reproduction:

    /Users/thomas/sas/bin/sasrun /absolute/probe.sas -f text -o /absolute/probe.txt -l /absolute/probe.log

Each basename has source, raw output and complete log retained:

- `univ-normality-oracle`: quantile/uniform/skew/tied/outlier samples at
  n=3,4,8,11,12,2000,2001; constants; 23 fitted-normal shape samples; extreme
  scale and translated data. Confirms n=2000 selects W and n=2001 selects D.
- `univ-normality-boundaries`: n=1/2, scales down to 1e-100, means up to 1e12;
  prints STD too, distinguishing a near-constant normality guard from zero SD.
- `univ-normality-degenerate`: n=2 distinct signed values, near-constant spread
  sweep, and translated n=2,3,8,12,2000,2001.
- `univ-normality-fuzz`: uniform and tied samples with the same range at n=3/8/12,
  distinguishing a relative variance criterion from a range-only shortcut.
- `univ-normality-precision`: samples either side of 500 machine epsilons,
  across the method/sample-size boundary; includes the borderline qualification.
- `univ-normality-ks`: 24 samples at n=2001/5000 spanning all interpolation
  intervals and both stored bounds. Examples at n=2001:
  D=.0191336979268,p=.07561110705591;
  D=.02012372759334,p=.04776392936703;
  D=.02210204219273,p=.01864761026227.

Six unit blocks exercise the full helper, not only its p-value functions. All
retained principal oracle-family rows have assertions; scale and translation
have explicit checks; the KS sweep also checks input immutability. Coefficient
regressions use 1e-10 absolute W tolerance, p tolerance 1e-8 or tighter. No corpus
fixture is added that pretends dev3's OUTTABLE integration already exists.

Landing is SUPPORT INTERMEDIATE. Dev3 must wire the helper, remove their
normality guard, and validate the complete OUTTABLE path before the summary
ticket can close. Other NORMAL inference options remain separate.
