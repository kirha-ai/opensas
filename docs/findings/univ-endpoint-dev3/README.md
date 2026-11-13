# FEAT-univ-distributions — dev3 endpoint support

Status: numerical SUPPORT checkpoint, **not full SAS acceptance**. The concrete
remaining differences below are not exclusions and must not be hidden by the
adapter. Parent ticket remains dev4's. Baseline 4e07869 after clean fast-forward;
read current dev4 fit module/findings and local manual before implementation.
Only new `src/stat/univ_endpoint_fit.zig`, its tests/evidence, and the permitted
root.zig import are owned here. No edits to dev4 modules, parser, PROC or jira.md.

## API

`fit(Family, sorted_finite_sample, Fixed, Controls) Result` is allocation-free.
Family is beta/power/pareto. Parameters are SAS theta, sigma, alpha, beta; sigma
is a width/scale, not an upper endpoint. Pareto alpha is **minus** the common GPD
shape xi. Null Fixed fields request estimation. Caller applies defaults:

- beta/power: theta=0, sigma=1, shape(s) estimated;
- Pareto: theta=0 fixed, alpha/sigma estimated.

`converged` contains parameters, total log-likelihood and iteration count.
`nonconverged` contains a reason and optional best finite valid curve. Never
label this payload converged; any publication requires a visible warning/status.
A failed beta fit carries no curve, matching retained SAS failures. The helper
has no parser, output, FREQ, BY/CLASS, ODS or diagnostics-reporter dependency.
It reuses the existing public log-gamma and distribution functions, not dev4's
unlanded parameter types.

`Controls.maxiter=1000` is a **private numerical budget per local start/root**,
not an implementation of PROC MAXITER. SAS accepted MAXITER=1/20/100/1000 and
returned identical beta endpoint estimates on the retained probe; the adapter
must not pass its generic default MAXITER=20 into this private solver budget.
`tolerance=1e-9` controls numerical stopping. `method=mle` is the implemented
method; `epm` returns explicit unsupported_method, never an MLE substitution.

The uniform Pareto special case alpha=1 has an estimated sigma equal to
max(x)-theta; the endpoint observation has finite uniform density. The helper's
likelihood supports this exact boundary case. Dev4's current generic strict
Pareto support check/logPdf must accommodate it when integrating this result.
Power's estimated-scale boundary result likewise includes its observed maximum.

## Sources and probes

Local manual `docs/sas94-procedures-statistical.txt` in the manager checkout:
printed pp.431–432 beta, 437 Pareto/Grimshaw search domain, 438–439 power as beta
with second shape 1, 340–341 scale/threshold options. These sections specify MLE,
not moments. Some option-table defaults disagree with family paragraphs; actual
M9 and family descriptions establish the defaults above. SAS's official
[histogram documentation](https://support.sas.com/documentation/cdl/en/procstat/63963/HTML/default/procstat_univariate_sect013.htm)
also describes default Pareto alpha/sigma MLE.

Every probe source/output/log has a unique absolute path under this dev3
findings directory. Retained runs use:

    /Users/thomas/sas/bin/sasrun /Users/thomas/kirha/opensas-dev3/docs/findings/univ-endpoint-dev3/NAME.sas -f text -o /Users/thomas/kirha/opensas-dev3/docs/findings/univ-endpoint-dev3/NAME.txt -l /Users/thomas/kirha/opensas-dev3/docs/findings/univ-endpoint-dev3/NAME.log

These are actual SAS 9.4 M9 runs on synthetic observations. Expected constants
in tests come from those outputs, not from the helper. Text/log evidence is
committed separately from implementation and probe sources.

- combinations: all 16 beta parameter masks; eight power and eight Pareto
  masks. Pareto THETA=EST produces syntax errors (eight error messages). All
  beta masks produce curves. Power endpoint estimation fails on this alpha=2
  sample. Pareto fixed shape/scale combinations confirm conditional estimation.
- method-options: intentional invalid FITMETHOD requests expose M9's grammar.
  Pareto accepts MLE/EPM; beta/power do not accept FITMETHOD. This probe's errors
  are intentional evidence, not a successful-fitting claim.
- pareto-methods: default results agree with explicit MLE. Alpha=0 gives the
  exponential mean estimate; alpha=1 gives the uniform upper boundary. The
  alpha=1 simulation triggers a SAS floating-point exception after the parameter
  table, retained honestly. EPM is accepted and returns a different curve,
  even replacing supplied alpha/sigma (see remaining gaps).
- beta-iterations: MAXITER=1,20,100,1000 return identical estimated beta curves
  with no warnings. This is why the internal numerical budget is separate.
- heldout-boundaries: independent n=77 beta(3,4) shifted/scaled by -3,7 and GPD
  alpha=.2 shifted/scaled by 5,3; fixed/estimated combinations; power alpha=5;
  n=8 endpoint/degenerate beta failures and uniform/nonregular Pareto cases.
- shift-failures: repeats dev4's Pareto n=8 shifted cases and independently
  probes power alpha=.5. Unlike the alpha=2/5 samples, SAS DOES return power
  curves with estimated endpoints here. There is therefore no blanket rejection
  of power endpoint estimation in the helper.

## Numerical implementation and verified portion

Beta uses support-preserving endpoint coordinates, log shape coordinates, three
starts and Nelder-Mead. Small simplex size is insufficient: finite-difference
stationarity and positive curvature must also hold before returning converged.
A finite endpoint iterate is returned as failure, not an interior MLE. All 16
n=101 masks agree with SAS within 1e-4 parameter units; n=77 heldouts within
2e-4. Quantile inputs use the repo's beta inverse and independent SAS QUANTILE;
this is not fitting sample-specific constants.

Generalized Pareto with both shape/scale estimated uses Grimshaw's scalar
likelihood profile. Its transformed score removes the spurious zero at the
exponential limit with a moment series. A logarithmic search brackets roots;
local likelihood checks distinguish maxima, and only alpha<=1 is searched as
specified in the manual's regular domain. No-root cases are explicit failures.
Fixed shape or scale uses conditional numerical optimization, with closed-form
alpha=0/1 cases. Negative-shape fits agree within 5e-5; positive-shape translated
heldouts within 1e-4; n=8 alpha=.6815 fit within 2e-4. Affine scaling tests also
check the exact log-likelihood shift of -n*log(scale).

Power with fixed endpoints uses the closed-form shape MLE. With fixed theta and
estimated sigma, the mathematical boundary solution is sigma=max(x)-theta and
conditional shape MLE (or the supplied fixed alpha). This remains explicitly a
boundary-warning result. With estimated theta, the generic support-preserving
optimizer retains a finite candidate only under a nonconverged boundary tag.

Six helper tests cover the parameter matrix, independent heldouts, fixed values,
transforms, support/constant/unsorted/nonfinite inputs, iteration-budget status,
unsupported-method status, and no-root cases. The targeted test command is:

    /Users/thomas/.local/bin/zig test src/root.zig --test-filter 'endpoint '

The filter also selects a few existing tests with "endpoint" in their names;
full gate counts are reported separately at landing time.

## Concrete remaining compatibility gaps — not waived

1. **Nonregular Pareto fallback:** for n=8 data `1 2 3 4 6 8 10 15` shifted by
   two, SAS returns sigma=17.79312, alpha=1.045195, outside the regular profile
   region. The helper currently reports no_local_maximum with no curve. For
   shifts one, three and four, both SAS and helper report no estimate. There is
   no sample-specific switch or invented blanket rejection. Reproducing the
   shift-two finite fallback remains unresolved. Some fixed-alpha>1 probes
   also differ between SAS suppression and numerical boundary candidates.
2. **Power stopping/failure behavior:** n=41 alpha=.5, fixed theta=0: SAS prints
   sigma=.971697, alpha=.517165; exact boundary MLE gives .9699265381,
   .5176533456, differences .001770462 and .000488346. This is tested with an
   explicit boundary warning. Joint endpoints differ more: SAS theta=-.00047,
   sigma=.971697, alpha=.52865; the unbounded-likelihood numerical candidate is
   near theta=.0002295684, sigma=.9696969697, alpha=.3528312565. That shape
   difference (~.176) is NOT accepted as numerical equivalence. SAS also omits
   curves for alpha=2/5 samples where the helper can return a warned mathematical
   boundary candidate. Public failure/fallback parity is not complete.
3. **Pareto EPM:** M9 accepts this method although the supplied older manual
   documents MLE only. The n=101 probe returns sigma=1.935473, alpha=-.37398,
   unchanged when alpha or sigma is supplied. Its algorithm has not been
   established. Requests fail explicitly; no silent MLE replacement is allowed.

Core regular MLE support can be reviewed independently of these unresolved
cases, but neither this support slice nor the parent ticket is marked fully
accepted. The parent adapter still owns public option handling, warnings,
fallback-publication decisions and output/ODS regression acceptance.
