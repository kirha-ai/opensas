# STAT-CATMOD-006 — CATMOD — Logistic Analysis / Log-Linear Model Analysis / Computational Method

## Source

S154 / Chapter 36 / `Logistic Analysis` (PDF pp. 2227–2229); S154 / Chapter 36 / `Log-Linear Model Analysis` (PDF pp. 2229–2232); S154 / Chapter 36 / `Computational Method` (PDF pp. 2247–2248).

## Scope

Implement Logistic Analysis; Log-Linear Model Analysis; Computational Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Logistic Analysis / Log-Linear Model Analysis / Computational Method, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 36.4: Log-Linear Model, Three Dependent Variables |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
