# STAT-GAM-005 — GAM — Estimates from PROC GAM / Backfitting and Local Scoring Algorithms / Smoothers

## Source

S154 / Chapter 48 / `Estimates from PROC GAM` (PDF p. 3310); S154 / Chapter 48 / `Backfitting and Local Scoring Algorithms` (PDF pp. 3310–3313); S154 / Chapter 48 / `Smoothers` (PDF pp. 3313–3314).

## Scope

Implement Estimates from PROC GAM; Backfitting and Local Scoring Algorithms; Smoothers. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Estimates from PROC GAM / Backfitting and Local Scoring Algorithms / Smoothers, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 48.3: Comparing PROC GAM with PROC LOESS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Added the Experiment B fitting step described in prose but omitted from the printed program; PredGAMb is now produced explicitly.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
