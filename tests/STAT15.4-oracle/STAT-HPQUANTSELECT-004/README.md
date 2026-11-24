# STAT-HPQUANTSELECT-004 — HPQUANTSELECT — Linear Model with iid Errors / Linear-in-Parameter Model with Non-iid Settings / More Statistics for Parameter Estimates

## Source

S154 / Chapter 66 / `Linear Model with iid Errors` (PDF pp. 4996–4997); S154 / Chapter 66 / `Linear-in-Parameter Model with Non-iid Settings` (PDF pp. 4997–4998); S154 / Chapter 66 / `More Statistics for Parameter Estimates` (PDF p. 4998).

## Scope

Implement Linear Model with iid Errors; Linear-in-Parameter Model with Non-iid Settings; More Statistics for Parameter Estimates. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Linear Model with iid Errors / Linear-in-Parameter Model with Non-iid Settings / More Statistics for Parameter Estimates, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: Linear Model with iid Errors / Linear-in-Parameter Model with Non-iid Settings / More Statistics for Parameter Estimates |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
