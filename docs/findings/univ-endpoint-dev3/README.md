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
estimated sigma, the prospectively verified moment-derived M9 width is now
implemented; supplied alpha is preserved, or its conditional optimum computed.
This finite curve has explicit nonstationary_candidate status. Failed pilot or
support initialization carries initialization_failed with no curve. See
[fixed-theta-power.md](fixed-theta-power.md) for the 84/85 matching oracle cases
and the one unresolved inadmissible-pilot/free-alpha exception. With estimated
theta, the generic optimizer remains unchanged and not fully SAS-compatible.

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
2. **Joint power stopping/failure behavior:** the fixed-theta sigma path now
   matches the recorded admissible candidates rather than substituting max(x).
   Joint endpoints still differ: SAS theta=-.00047, sigma=.971697, alpha=.52865
   versus the existing generic solver's near-boundary theta=.0002295684,
   sigma=.9696969697, alpha=.3528312565 on the old n=41 probe. The new free-theta
   tests also disprove applying the analogous moment-location candidate blindly.
3. **Inadmissible pilot with free alpha:** one symmetric heavy-tail sample
   returns sigma=8.002/alpha=.5574860401 in SAS but remains initialization_failed
   here. It stays in the regression fixture as an explicit mismatch.
4. **Beta coupled failure:** separate feasible fixed endpoints or a fixed shape
   permit fitting the small-unit counterexample, but a feasible starting-like
   location alone does not repair its joint shape/scale failure.

EPM is **outside the cited contract**, not a third acceptance gap. A full-text
search of all 22,444 lines of the supplied Sixth Edition manual found zero EPM
or expanded-name matches; see `manual-scope.txt` for exact command and SHA256.
M9 accepting a newer/undocumented option does not expand this ticket. Keep the
existing unsupported_method result; do not substitute MLE or pursue EPM here.

Core regular MLE support can be reviewed independently of these unresolved
cases, but neither this support slice nor the parent ticket is marked fully
accepted. The parent adapter still owns public option handling, warnings,
fallback-publication decisions and output/ODS regression acceptance.

## Bounded fallback diagnosis after core landing

See [fallback-diagnosis.md](fallback-diagnosis.md), the full-precision HEX16 ODS
probe, and independent `analyze-diagnostics.py` / `score-audit.json`. Power and
beta(alpha,1) are identical likelihoods and produce identical oracle behavior.
The new checks correct their numerical upper-boundary likelihood equivalence;
explicit fixed-endpoint request validation remains strict. Three new regression
tests cover identical likelihoods, reflected Pareto equivalence/score, and
feasible improvements at SAS's returned finite curves. Those curves are not
stationary fits, and generic warning tags do not cure mismatched public output.
The two in-scope fallback/stopping mismatches above remain unresolved.

## Narrowed width hypothesis (bounded follow-up)

[scale-hypothesis.md](scale-hypothesis.md) records 73 prespecified scale/shape/
replication probes and a moment-derived candidate width that predicts all 53
power outcomes and all 29 returned power widths to roundoff. Fresh non-beta1
beta cases support a candidate-floor interpretation, but a small-unit beta
feasibility-repair failure remains. Official SAS optimizer documentation does
not identify UNIVARIATE's internal algorithm. No production fitting rule was
changed and no case-specific exception was introduced. The parent is not done.

## Implemented fixed-theta power scale path

[fixed-theta-power.md](fixed-theta-power.md) supersedes the earlier diagnosis-only
status for this defined path. The API adds initialization_failed and
nonstationary_candidate reasons, preserving the optional best-curve payload.
Prospective and old oracle cases give 84 matches and one explicit unresolved
initialization case; green tests are not a claim that all 85 match SAS. The
joint-theta, beta and Pareto gaps remain open.

## Prospective fallback-start rejection and beta coupling control

[fallback-start-discriminator.md](fallback-start-discriminator.md) records all
85 old rows, 36 prospective mixtures/tie-weight requests, 27 conditional/joint
beta requests, and six fixed-width power controls. The clipped two-moment-start
hypothesis matches the old 85 outcomes but fails 11/36 new cases; no generic
production change was adopted. All 24 conditional beta fits and all six power
shape controls succeed, while the smallest-unit joint beta fit still fails.
The old 84/85 compiled count is not full fallback acceptance: the existing guard
also suppresses 19 new SAS-returned free-alpha curves. Parent scope remains open.
