# STAT-COMMON-009 implementation and verification

Original `estimability.sas`, expected listing, status and SAS log are unchanged.
The original case requests only the observed `group*h` levels: A0, A1, B0.
An absent B1 result must not be invented. Separate typed tests and a corpus
fixture request marginal group/h means to exercise real nonestimable results.

## Source and implementation

Read S154 physical pp.278–284 (row-space criterion, generating sets, reduction
notation), 4072–4076 and 4081 (LSMEANS/E/STDERR/SINGULAR), and 4144–4147
(coefficient construction, covariate means and estimability).

`glm_estimability` reuses the ordered alias equations from `reg_diagnostics`.
They are the transpose of H=(X'WX)-X'WX. It checks each component of L-LH
against SINGULAR*abs(L), using scale 1 for zero components, exactly as described
for LSMEANS. This tolerance is independent of MODEL's numerical rank cutoff.
A nonestimable result has a typed status and null estimate, variance factor,
standard error, t and p fields. A genuine estimable zero remains numeric zero.
An estimable result in a saturated model retains its estimate and variance
factor but has unavailable error-based inference. Invalid inputs fail loudly.
The independent rows of H are also exposed as a generating-set API.

`glm_lsmeans` owns the LSMEANS statement parser, coefficient construction and
rendering. It reuses the full indicator coding and CLASS labels from
`design_matrix`, which omits empty interaction columns and preserves canonical
CLASS order. Means are balanced over compatible columns of each CLASS effect;
ordinary continuous terms use their frequency-weighted, precision-unweighted
mean, including mean-of-product terms. The existing rank/QR helper fits that
coded basis with FREQ*WEIGHT. Error DF/MSE come from the full GLM fit. A mismatch
between the coded basis rank and the full model fails instead of returning
inconsistent inference. Rendering emits `Non-est` and missing inference tokens,
not a generalized-inverse coefficient passed off as an estimable mean.

Shared edits are limited to the LSMEANS Spec field, statement hook, and execution
hook. Type III/IV hypotheses, MODEL syntax, and ANOVA formatting belong to the
coordinated dev6 integration. No PRINT, main/root, board or skill edits.

## Discriminating checks

- Published one-way generating set: intercept coefficient equals the sum of
  the class coefficients; independent basis rows match the source example.
- Published dependent regression: x3=2*x1+3*x2 requires L4=2*L2+3*L3.
  Check strict/loose estimability tolerance separately from model rank.
- Published three-factor confounding: pure A and B contrasts are nonestimable,
  C1-2C2+C3 is estimable; its SS matches R(C | intercept,A,B). Zero-DF
  reductions retain SS=0 with missing MS/F/p.
- All original E columns/rows, level labels, three cell means and variance
  factors; B marginal and h=1 marginal are genuinely nonestimable.
- Blank CLASS, missing CLASS, and missing response rows do not create levels.
- Reordered data changes coefficient/level ordering together.
- Unequal FREQ and WEIGHT retain balanced margins and replicated error DF.
- Captured diagnostics reject invalid effects/options. Tests do not spawn an
  aborting process to assert failure.

`verify.py` replays the unchanged full source, checks the real process status,
and compares every listing token with whitespace-only normalization. It also
uses rational arithmetic on the original source data to verify the cell means,
error SS and shared-level Type III contrasts independently of production math.

## Scope limits

General ESTIMATE/CONTRAST syntax, nested or mixed CLASS/covariate LSMEANS,
AT/OM/PDIFF/CL/OUT and LSMEANS plots are not implemented by this ticket.
Unsupported statement options fail loudly. ORDER=FREQ with a FREQ statement
also fails loudly because the shared full-coded design does not yet accept
frequency-weighted level ordering. The original case uses none of these.

New corpus `glm_lsmeans_estimability` exercises the original E/observed-cell
portion plus marginal means with explicit SS1. Its E labels/coefficient values
and observed means derive from the unchanged SAS oracle; its additional
marginal coefficient/Non-est contracts derive from pp.4144–4147 and typed
row-space tests. This is a new golden, not a replacement of the original
expected listing. Dev6's CV precision correction is already included.
