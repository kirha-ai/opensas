# STAT-TRANSREG-015 — TRANSREG — Hypothesis Tests / Hypothesis Tests for Simple Univariate Models / Hypothesis Tests with Dependent Variable Transformations

## Source

S154 / Chapter 126 / `Hypothesis Tests` (PDF pp. 10489–10491); S154 / Chapter 126 / `Hypothesis Tests for Simple Univariate Models` (PDF pp. 10502–10508); S154 / Chapter 126 / `Hypothesis Tests with Dependent Variable Transformations` (PDF pp. 10509–10512).

## Scope

Implement Hypothesis Tests; Hypothesis Tests for Simple Univariate Models; Hypothesis Tests with Dependent Variable Transformations. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Hypothesis Tests / Hypothesis Tests for Simple Univariate Models / Hypothesis Tests with Dependent Variable Transformations, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 126.2: Box-Cox Transformations |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
