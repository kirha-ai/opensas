# STAT-LIFEREG-008 — LIFEREG — ESTIMATE / TEST / Confidence Intervals

## Source

S154 / Chapter 76 / `ESTIMATE Statement` (PDF pp. 5549–5550); S154 / Chapter 76 / `TEST Statement` (PDF pp. 5565–5566); S154 / Chapter 76 / `Confidence Intervals` (PDF pp. 5574–5575).

## Scope

Implement ESTIMATE; TEST; Confidence Intervals. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ESTIMATE / TEST / Confidence Intervals, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LIFEREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ESTIMATE, TEST. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
