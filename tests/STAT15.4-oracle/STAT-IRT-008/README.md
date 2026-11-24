# STAT-IRT-008 — IRT — Maximizing the Marginal Likelihood / Factor Score Estimation / Model and Item Fit

## Source

S154 / Chapter 72 / `Maximizing the Marginal Likelihood` (PDF pp. 5345–5348); S154 / Chapter 72 / `Factor Score Estimation` (PDF pp. 5349–5350); S154 / Chapter 72 / `Model and Item Fit` (PDF pp. 5350–5351).

## Scope

Implement Maximizing the Marginal Likelihood; Factor Score Estimation; Model and Item Fit. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Maximizing the Marginal Likelihood / Factor Score Estimation / Model and Item Fit, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
