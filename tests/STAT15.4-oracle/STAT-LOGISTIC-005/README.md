# STAT-LOGISTIC-005 — LOGISTIC — Convergence Criteria / Iterative Algorithms for Model Fitting

## Source

S154 / Chapter 79 / `Convergence Criteria` (PDF p. 5911); S154 / Chapter 79 / `Iterative Algorithms for Model Fitting` (PDF pp. 5909–5911).

## Scope

Implement Convergence Criteria; Iterative Algorithms for Model Fitting. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Convergence Criteria / Iterative Algorithms for Model Fitting, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 79.3: Ordinal Logistic Regression |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
