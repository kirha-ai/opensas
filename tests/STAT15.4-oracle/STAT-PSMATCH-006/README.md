# STAT-PSMATCH-006 — PSMATCH — Propensity Score Weighting / Propensity Score Stratification / Matching Process

## Source

S154 / Chapter 101 / `Propensity Score Weighting` (PDF pp. 8239–8242); S154 / Chapter 101 / `Propensity Score Stratification` (PDF pp. 8242–8243); S154 / Chapter 101 / `Matching Process` (PDF pp. 8244–8245).

## Scope

Implement Propensity Score Weighting; Propensity Score Stratification; Matching Process. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Propensity Score Weighting / Propensity Score Stratification / Matching Process, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
