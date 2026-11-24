# STAT-GAM-004 — GAM — Nonparametric Regression / Additive Models and Generalized Additive Models / Forms of Additive Models

## Source

S154 / Chapter 48 / `Nonparametric Regression` (PDF pp. 3307–3308); S154 / Chapter 48 / `Additive Models and Generalized Additive Models` (PDF pp. 3308–3309); S154 / Chapter 48 / `Forms of Additive Models` (PDF pp. 3309–3310).

## Scope

Implement Nonparametric Regression; Additive Models and Generalized Additive Models; Forms of Additive Models. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Nonparametric Regression / Additive Models and Generalized Additive Models / Forms of Additive Models, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 48.1: Generalized Additive Model with Binary Data |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
