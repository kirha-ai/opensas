# STAT-FMM-006 — FMM — Overdispersion / Log-Likelihood Functions for Response Distributions / Conjugate Sampling

## Source

S154 / Chapter 46 / `Overdispersion` (PDF pp. 3018–3019); S154 / Chapter 46 / `Log-Likelihood Functions for Response Distributions` (PDF pp. 3019–3026); S154 / Chapter 46 / `Conjugate Sampling` (PDF pp. 3026–3027).

## Scope

Implement Overdispersion; Log-Likelihood Functions for Response Distributions; Conjugate Sampling. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Overdispersion / Log-Likelihood Functions for Response Distributions / Conjugate Sampling, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 46.4: Modeling Multinomial Overdispersion: Town and Country |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
