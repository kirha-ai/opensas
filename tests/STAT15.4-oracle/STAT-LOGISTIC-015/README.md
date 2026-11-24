# STAT-LOGISTIC-015 — LOGISTIC — Confidence Intervals for Parameters / Testing Linear Hypotheses about the Regression Coefficients / Joint Tests and Type 3 Tests

## Source

S154 / Chapter 79 / `Confidence Intervals for Parameters` (PDF pp. 5920–5922); S154 / Chapter 79 / `Testing Linear Hypotheses about the Regression Coefficients` (PDF p. 5937); S154 / Chapter 79 / `Joint Tests and Type 3 Tests` (PDF pp. 5937–5938).

## Scope

Implement Confidence Intervals for Parameters; Testing Linear Hypotheses about the Regression Coefficients; Joint Tests and Type 3 Tests. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Confidence Intervals for Parameters / Testing Linear Hypotheses about the Regression Coefficients / Joint Tests and Type 3 Tests, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 79.1: Stepwise Logistic Regression and Predicted Values |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
