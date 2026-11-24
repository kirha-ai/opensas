# STAT-SURVEYSELECT-009 — SURVEYSELECT — Proportional Allocation / Optimal Allocation / Neyman Allocation

## Source

S154 / Chapter 124 / `Proportional Allocation` (PDF p. 10257); S154 / Chapter 124 / `Optimal Allocation` (PDF pp. 10257–10258); S154 / Chapter 124 / `Neyman Allocation` (PDF pp. 10258–10259).

## Scope

Implement Proportional Allocation; Optimal Allocation; Neyman Allocation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Proportional Allocation / Optimal Allocation / Neyman Allocation, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
