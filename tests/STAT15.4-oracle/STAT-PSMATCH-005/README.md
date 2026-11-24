# STAT-PSMATCH-005 — PSMATCH — Output Table Enhancements / Observational Studies Contrasted with Randomized Trials / Propensity Score Analysis

## Source

S154 / Chapter 101 / `Output Table Enhancements` (PDF pp. 8235–8236); S154 / Chapter 101 / `Observational Studies Contrasted with Randomized Trials` (PDF pp. 8236–8237); S154 / Chapter 101 / `Propensity Score Analysis` (PDF pp. 8237–8239).

## Scope

Implement Output Table Enhancements; Observational Studies Contrasted with Randomized Trials; Propensity Score Analysis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Output Table Enhancements / Observational Studies Contrasted with Randomized Trials / Propensity Score Analysis, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
