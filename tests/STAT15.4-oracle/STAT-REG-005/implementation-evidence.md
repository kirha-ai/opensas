# STAT-REG-005 ridge implementation attempt

Read the original README/program/expected output/log and the supplied manual at
physical pp.8648–8649 and 8719–8723 (Example 105.5). Expected fixtures are unchanged.

The implementation centers predictors and response, scales predictor weighted
crossproducts to unit diagonals, and solves the augmented system
[Z; sqrt(k)I] gamma = [sqrt(W)(y-ybar); 0] using the existing QR fitter. It recovers
original-unit slopes and intercept, computes standardized coefficients with the
response CSS, and computes VIF as ||Z (Z'Z+kI)^-1[:,j]||². Ridge RMSE uses the
original ordinary model's error degrees of freedom. No coefficients or VIF values
are taken from a fixture. IPC remains an explicit unsupported feature.

Independent inline tests cover the orthogonal analytic shrinkage solution at k=0
and k=1, translation/predictor-unit/response scaling, and explicit failures for
undefined scales and negative penalties. New modules are reached through REG.

The complete original program was run. It returns rc 0 and produces five native
SVGs: default diagnostic panel, residual-predictor panel, packed ridge/VIF panel,
then separate logarithmic-VIF and standardized-ridge plots for PLOTS(ONLY).
SVG metadata retains the entire computed path, including full-precision estimates,
standardized coefficients and VIFs. The packed ridge figure was inspected against
manual Output 105.5.1; visual review of all final artifacts remains required.

The first OUTEST has the expected 23 rows and 13 columns: PARMS, then RIDGEVIF and
RIDGE for each of 11 constants. The second path omits VIF output rows. Values remain
full precision; ridge OUTEST presentation formats use a common six-significant-digit
column precision and RIDGE uses 6.3. The ordinary listing now preserves labels.

Current comparison has 588 expected/actual tokens. Four tokens differ:

- Corrected Total SST appears twice as 2123.70938 versus SAS 2123.70937. The exact
  decimal-input target is 2123.709375, a last-displayed-digit midpoint. No production
  value was altered to force SAS's floating-point rounding artifact.
- Two small negative x1x2 coefficients display as 0.000 versus SAS -0.000. Their
  stored values retain the correct negative sign and full precision. The shared
  fixed-decimal formatter suppresses a sign when the rounded magnitude is zero.

These differences are recorded, not silently normalized into an exact-match claim.
A rigorous complete independent path/graph verification and final all-artifact visual
review are still pending. No DONE or full IPC/graph-option coverage claim is made.

The initial test build failed on a Zig runtime/comptime numeric type inference in
axis layout; that source error was fixed before the committed gate attempt. Only a
separately successful gate exit may be reported as green.

Local reproducible capture files are in `.stat-reg-005-evidence/`: full stdout/stderr,
full token diffs, the original manual excerpts, reference PNGs and generated SVGs.
The caller can rerun the unchanged program with `--graphics-dir <new-directory>`.
